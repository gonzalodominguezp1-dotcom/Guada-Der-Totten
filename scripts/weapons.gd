extends RefCounted
## Datos y modelos de las armas (pistola M1911 y escopeta de caza de dos
## cañones), con manos y mangas para la vista en primera persona.
## Convención: el arma apunta a -Z; "sight_y" es la altura de la línea de
## mira sobre el origen del modelo, para que al apuntar quede centrada.

const DATA := {
	"pistola": {
		"name": "Pistola M1911",
		"damage": 50.0, "pellets": 1, "mag": 8, "reserve": 80,
		"fire_delay": 0.16, "reload": 1.5, "auto": false,
		"spread_hip": 0.018, "spread_ads": 0.003, "range": 150.0, "falloff": 999.0,
		"recoil": 1.0, "kick": 0.010, "sound": "pistol_shot", "pitch": 1.0, "volume": -3.0,
		"cost": 0, "hip": Vector3(0.17, -0.165, -0.40), "ads": Vector3(0.0, -0.054, -0.30),
		"sight_y": 0.0585, "muzzle": Vector3(0, 0.036, -0.19), "ads_fov": 60.0,
	},
	"escopeta": {
		"name": "Escopeta de caza",
		"damage": 75.0, "pellets": 8, "mag": 2, "reserve": 60,
		"fire_delay": 0.28, "reload": 2.4, "auto": false,
		"spread_hip": 0.065, "spread_ads": 0.045, "range": 40.0, "falloff": 9.0,
		"recoil": 1.8, "kick": 0.04, "sound": "pistol_shot", "pitch": 0.62, "volume": 1.5,
		"cost": 500, "hip": Vector3(0.16, -0.18, -0.36), "ads": Vector3(0.0, -0.055, -0.22),
		"sight_y": 0.059, "muzzle": Vector3(0, 0.03, -0.70), "ads_fov": 62.0,
	},
	# Arma maravilla del mapa: se monta con 3 piezas en la mesa de trabajo.
	# Ficha del colega de Gonzalo: ráfaga de chorros, daño alto de cerca que baja
	# con la distancia (alcance medio), un solo cargador grande sin reserva.
	# Los zombies que reciben o pisan zurraspa resbalan y "se sienten sucios".
	"zurraspa": {
		"name": "Cañón de Zurraspa",
		"damage": 45.0, "pellets": 3, "mag": 60, "reserve": 0,
		"fire_delay": 0.09, "reload": 2.8, "auto": true,
		"spread_hip": 0.105, "spread_ads": 0.07, "range": 14.0, "falloff": 4.0,
		"min_factor": 0.25,
		"recoil": 0.5, "kick": 0.004, "sound": "zurraspa_spray", "pitch": 1.0, "volume": -6.0,
		"cost": 0, "hip": Vector3(0.17, -0.19, -0.42), "ads": Vector3(0.0, -0.16, -0.36),
		"sight_y": 0.16, "muzzle": Vector3(0, 0.07, -0.33), "ads_fov": 62.0,
		"spray": true, "slip": 2.0, "dirty": 5.0,
		"puddle_cooldown": 0.4, "puddle_radius": 1.8, "puddle_life": 10.0, "puddle_dps": 15.0,
		"pap": "zurraspa_pap",
	},
	# Pack-a-Punch: «¡De la taza al apocalipsis!». Dispara una avalancha que
	# atraviesa a todos los zombies de su camino y deja charcos dorados.
	# [G] = Defecación Nuclear (mata a todos los zombies, 90 s de espera).
	"zurraspa_pap": {
		"name": "Cañón de Zurraspa Dorado",
		"damage": 3000.0, "pellets": 1, "mag": 30, "reserve": 90,
		"fire_delay": 0.55, "reload": 3.2, "auto": true,
		"spread_hip": 0.0, "spread_ads": 0.0, "range": 22.0, "falloff": 999.0,
		"recoil": 1.4, "kick": 0.03, "sound": "avalanche", "pitch": 1.0, "volume": -2.0,
		"cost": 0, "hip": Vector3(0.17, -0.19, -0.42), "ads": Vector3(0.0, -0.16, -0.36),
		"sight_y": 0.16, "muzzle": Vector3(0, 0.07, -0.33), "ads_fov": 62.0,
		"wave": true, "wave_speed": 14.0, "wave_width": 5.0, "wave_height": 3.0, "wave_spacing": 3.0,
		"slip": 3.0, "dirty": 8.0,
		"puddle_radius": 2.5, "puddle_life": 14.0, "puddle_dps": 30.0,
		"nuclear_cooldown": 90.0, "gold": true,
	},
}


static func data(id: String) -> Dictionary:
	return DATA[id]


# ---------------------------------------------------------------- materiales

static var _mats := {}


static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var fn := FastNoiseLite.new()
	fn.frequency = 0.05
	var nt := NoiseTexture2D.new()
	nt.noise = fn
	nt.width = 128
	nt.height = 128
	nt.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.8, 0.8, 0.8))
	ramp.set_color(1, Color(1, 1, 1))
	nt.color_ramp = ramp
	var m := StandardMaterial3D.new()
	match key:
		"blued":
			m.albedo_color = Color(0.13, 0.135, 0.15)
			m.metallic = 0.85
			m.roughness = 0.32
		"blued_dark":
			m.albedo_color = Color(0.06, 0.06, 0.065)
			m.metallic = 0.7
			m.roughness = 0.45
		"bore":
			m.albedo_color = Color(0.0, 0.0, 0.0)
			m.roughness = 1.0
		"silver":
			m.albedo_color = Color(0.55, 0.55, 0.57)
			m.metallic = 1.0
			m.roughness = 0.3
			m.albedo_texture = nt
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(40, 40, 40)
		"walnut":
			m.albedo_color = Color(0.36, 0.17, 0.08)
			m.roughness = 0.45
			m.albedo_texture = nt
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(6, 60, 6)
		"grip":
			m.albedo_color = Color(0.30, 0.14, 0.07)
			m.roughness = 0.7
			m.albedo_texture = nt
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(120, 120, 120)
		"dot":
			m.albedo_color = Color(0.9, 0.95, 0.85)
			m.emission_enabled = true
			m.emission = Color(0.6, 0.9, 0.6)
			m.emission_energy_multiplier = 0.6
		"skin":
			# guantes de cuero oscuro (quedan mejor que la piel con formas simples)
			m.albedo_color = Color(0.11, 0.085, 0.065)
			m.roughness = 0.55
			m.albedo_texture = nt
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(30, 30, 30)
		"knuckle":
			m.albedo_color = Color(0.08, 0.06, 0.05)
			m.roughness = 0.6
		"nail":
			m.albedo_color = Color(0.72, 0.6, 0.55)
			m.roughness = 0.3
		"sleeve":
			m.albedo_color = Color(0.15, 0.17, 0.11)
			m.roughness = 0.95
			m.albedo_texture = nt
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(25, 25, 25)
		"cuff":
			m.albedo_color = Color(0.11, 0.12, 0.08)
			m.roughness = 0.95
		"rubber":
			m.albedo_color = Color(0.05, 0.05, 0.05)
			m.roughness = 0.9
		"zurraspa":
			m.albedo_color = Color(0.24, 0.13, 0.05)
			m.roughness = 0.25
		"cotton":
			m.albedo_color = Color(0.86, 0.84, 0.78)
			m.roughness = 0.95
			m.albedo_texture = nt
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(40, 40, 40)
		"elastic":
			m.albedo_color = Color(0.25, 0.3, 0.55)
			m.roughness = 0.8
		"plastic":
			m.albedo_color = Color(0.62, 0.58, 0.50)
			m.roughness = 0.55
		"plastic_dark":
			m.albedo_color = Color(0.12, 0.11, 0.10)
			m.roughness = 0.5
		"crt":
			m.albedo_color = Color(0.10, 0.14, 0.10)
			m.roughness = 0.08
			m.emission_enabled = true
			m.emission = Color(0.45, 0.30, 0.10)
			m.emission_energy_multiplier = 1.2
		"gold":
			# poco metálico: en Compatibilidad no hay reflejos y el oro puro sale negro
			m.albedo_color = Color(1.0, 0.76, 0.18)
			m.metallic = 0.45
			m.roughness = 0.3
			m.emission_enabled = true
			m.emission = Color(0.55, 0.38, 0.05)
			m.emission_energy_multiplier = 0.35
		"gold_crt":
			m.albedo_color = Color(1.0, 0.82, 0.15)
			m.metallic = 1.0
			m.roughness = 0.2
			m.emission_enabled = true
			m.emission = Color(1.0, 0.82, 0.15)
			m.emission_energy_multiplier = 2.5
		"copper":
			m.albedo_color = Color(0.72, 0.40, 0.22)
			m.metallic = 1.0
			m.roughness = 0.3
		"bulb":
			m.albedo_color = Color(0.45, 0.25, 0.08, 0.75)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.emission_enabled = true
			m.emission = Color(0.5, 0.28, 0.08)
			m.emission_energy_multiplier = 0.8
	_mats[key] = m
	return m


# ---------------------------------------------------------------- primitivas

static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, size: Vector3, pos: Vector3, key: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(parent, bm, pos, _mat(key), rot)


## Cilindro a lo largo de Z (cañones, bocachas)
static func _tube(parent: Node3D, r: float, length: float, pos: Vector3, key: String, seg := 20) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = seg
	cm.rings = 1
	return _add(parent, cm, pos, _mat(key), Vector3(PI * 0.5, 0, 0))


## Cápsula entre dos puntos (dedos, antebrazos, culata redondeada...)
static func _limb(parent: Node3D, a: Vector3, b: Vector3, r: float, key: String, flat := 1.0) -> MeshInstance3D:
	var d := b - a
	var L := d.length()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = L + r * 2.0
	cm.radial_segments = 14
	cm.rings = 6
	var y := d / L
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = _mat(key)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(x * flat, y, z), (a + b) * 0.5)
	parent.add_child(mi)
	return mi


static func _sphere(parent: Node3D, r: float, pos: Vector3, key: String, scl := Vector3.ONE) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	return _add(parent, sm, pos, _mat(key), Vector3.ZERO, scl)


## Dedo de tres falanges que sigue los puntos dados
static func _finger(parent: Node3D, pts: Array, r: float) -> void:
	for i in pts.size() - 1:
		_limb(parent, pts[i], pts[i + 1], r * (1.0 - 0.08 * i), "skin")
		_sphere(parent, r * 1.02 * (1.0 - 0.08 * i), pts[i], "knuckle")
	var tip: Vector3 = pts[pts.size() - 1]
	_sphere(parent, r * 0.8, tip, "skin")


# ---------------------------------------------------------------- modelos

static func build_model(id: String, with_hands := false) -> Node3D:
	var root := Node3D.new()
	root.name = id
	match id:
		"pistola":
			_pistol(root)
			if with_hands:
				_pistol_hands(root)
		"escopeta":
			_shotgun(root)
			if with_hands:
				_shotgun_hands(root)
		"zurraspa", "zurraspa_pap":
			_zurraspa(root)
			if id == "zurraspa_pap":
				_gild(root)
			if with_hands:
				_pistol_hands(root)
	return root


static func _pistol(root: Node3D) -> void:
	# Corredera (se anima al disparar)
	var slide := Node3D.new()
	slide.name = "slide"
	root.add_child(slide)
	_box(slide, Vector3(0.029, 0.026, 0.218), Vector3(0, 0.034, -0.064), "blued")
	_tube(slide, 0.0145, 0.218, Vector3(0, 0.0405, -0.064), "blued", 18)       # lomo redondeado
	_box(slide, Vector3(0.024, 0.004, 0.2), Vector3(0, 0.0545, -0.066), "blued")  # canal de mira
	for k in 9:
		_box(slide, Vector3(0.0305, 0.02, 0.0018), Vector3(0, 0.036, 0.008 + k * 0.0042), "blued_dark")
	_box(slide, Vector3(0.002, 0.011, 0.034), Vector3(0.0148, 0.042, -0.03), "bore")     # ventana de expulsión
	_tube(slide, 0.0098, 0.012, Vector3(0, 0.0345, -0.17), "blued", 18)        # casquillo del cañón
	_tube(slide, 0.0052, 0.014, Vector3(0, 0.0345, -0.1708), "bore", 12)       # ánima
	# Miras de tres puntos
	_box(slide, Vector3(0.0036, 0.009, 0.012), Vector3(0, 0.0545, -0.162), "blued_dark")
	_sphere(slide, 0.0013, Vector3(0, 0.0555, -0.1555), "dot")
	for x in [-0.0055, 0.0055]:
		_box(slide, Vector3(0.0045, 0.009, 0.009), Vector3(x, 0.0545, 0.032), "blued_dark")
		_sphere(slide, 0.0012, Vector3(x, 0.0555, 0.0368), "dot")
	_box(slide, Vector3(0.016, 0.004, 0.009), Vector3(0, 0.0505, 0.032), "blued_dark")
	# Armazón
	_box(root, Vector3(0.027, 0.02, 0.168), Vector3(0, 0.012, -0.058), "blued")
	_box(root, Vector3(0.025, 0.014, 0.06), Vector3(0, 0.006, -0.138), "blued")     # guardapolvo
	_box(root, Vector3(0.006, 0.006, 0.02), Vector3(-0.0155, 0.022, -0.035), "blued_dark")  # retén de corredera
	# Guardamonte y gatillo
	_box(root, Vector3(0.008, 0.004, 0.052), Vector3(0, -0.026, -0.04), "blued")
	_box(root, Vector3(0.008, 0.03, 0.004), Vector3(0, -0.012, -0.066), "blued", Vector3(0.25, 0, 0))
	_box(root, Vector3(0.006, 0.018, 0.006), Vector3(0, -0.008, -0.03), "silver", Vector3(-0.2, 0, 0))
	# Empuñadura con cachas de nogal estriadas
	var gr := Node3D.new()
	gr.position = Vector3(0, -0.012, 0.012)
	gr.rotation.x = -0.21
	root.add_child(gr)
	_box(gr, Vector3(0.027, 0.112, 0.054), Vector3(0, -0.048, 0.0), "blued")
	for side in [-1.0, 1.0]:
		_box(gr, Vector3(0.005, 0.092, 0.044), Vector3(side * 0.0158, -0.044, 0.0), "grip")
		_sphere(gr, 0.0028, Vector3(side * 0.0185, -0.012, 0.0), "silver")
		_sphere(gr, 0.0028, Vector3(side * 0.0185, -0.078, 0.0), "silver")
	_box(gr, Vector3(0.026, 0.008, 0.052), Vector3(0, -0.106, 0.0), "blued_dark")    # base del cargador
	_box(gr, Vector3(0.022, 0.09, 0.008), Vector3(0, -0.045, 0.028), "blued_dark")   # seguro de empuñadura
	# Cola de castor y martillo
	_box(root, Vector3(0.024, 0.008, 0.026), Vector3(0, 0.022, 0.05), "blued")
	_tube(root, 0.0065, 0.006, Vector3(0, 0.03, 0.046), "blued_dark", 12)


static func _pistol_hands(root: Node3D) -> void:
	var h := Node3D.new()
	h.name = "manos"
	root.add_child(h)
	# Mano derecha empuñando
	_limb(h, Vector3(0.022, -0.05, 0.03), Vector3(0.024, -0.085, 0.02), 0.026, "skin", 0.75)    # palma
	_limb(h, Vector3(0.022, -0.06, 0.05), Vector3(0.04, -0.13, 0.1), 0.03, "skin")               # muñeca
	_limb(h, Vector3(0.04, -0.13, 0.1), Vector3(0.09, -0.36, 0.2), 0.038, "sleeve")             # antebrazo
	_limb(h, Vector3(0.038, -0.125, 0.098), Vector3(0.05, -0.17, 0.12), 0.042, "cuff")
	for i in 3:
		var y := -0.04 - i * 0.022
		_finger(h, [Vector3(0.02, y, 0.0), Vector3(0.012, y - 0.003, -0.03), Vector3(-0.006, y - 0.004, -0.035), Vector3(-0.018, y - 0.004, -0.02)], 0.0085)
	# índice fuera del gatillo, apoyado en el armazón
	_finger(h, [Vector3(0.018, -0.008, -0.01), Vector3(0.017, -0.004, -0.045), Vector3(0.016, -0.002, -0.075)], 0.0082)
	# pulgar derecho por encima del pulgar izquierdo
	_finger(h, [Vector3(0.004, -0.02, 0.035), Vector3(-0.012, -0.004, 0.0), Vector3(-0.018, 0.002, -0.03)], 0.0095)
	# Mano izquierda de apoyo
	_limb(h, Vector3(-0.03, -0.06, 0.02), Vector3(-0.026, -0.1, 0.0), 0.027, "skin", 0.75)
	_limb(h, Vector3(-0.032, -0.08, 0.03), Vector3(-0.06, -0.15, 0.08), 0.03, "skin")
	_limb(h, Vector3(-0.06, -0.15, 0.08), Vector3(-0.14, -0.38, 0.18), 0.038, "sleeve")
	_limb(h, Vector3(-0.058, -0.145, 0.078), Vector3(-0.074, -0.19, 0.1), 0.042, "cuff")
	for i in 3:
		var y := -0.05 - i * 0.021
		_finger(h, [Vector3(-0.03, y, -0.01), Vector3(-0.022, y - 0.002, -0.042), Vector3(0.0, y - 0.004, -0.05), Vector3(0.018, y - 0.004, -0.04)], 0.0085)
	_finger(h, [Vector3(-0.03, -0.035, 0.0), Vector3(-0.022, -0.012, -0.03), Vector3(-0.019, -0.005, -0.06)], 0.0092)


static func _shotgun(root: Node3D) -> void:
	# Dos cañones yuxtapuestos con banda
	for x in [-0.0165, 0.0165]:
		_tube(root, 0.0162, 0.64, Vector3(x, 0.03, -0.37), "blued", 20)
		_tube(root, 0.0118, 0.012, Vector3(x, 0.03, -0.687), "bore", 14)
	_box(root, Vector3(0.012, 0.009, 0.62), Vector3(0, 0.0495, -0.37), "blued_dark")
	_sphere(root, 0.0028, Vector3(0, 0.0565, -0.675), "silver")       # punto de mira
	_box(root, Vector3(0.02, 0.012, 0.6), Vector3(0, 0.012, -0.37), "blued_dark")
	# Guardamanos de nogal
	_limb(root, Vector3(0, 0.006, -0.12), Vector3(0, 0.006, -0.33), 0.024, "walnut", 1.1)
	# Báscula grabada
	_box(root, Vector3(0.056, 0.058, 0.12), Vector3(0, 0.02, -0.02), "silver")
	_box(root, Vector3(0.058, 0.02, 0.1), Vector3(0, 0.0, -0.02), "silver")
	_box(root, Vector3(0.012, 0.024, 0.03), Vector3(0, 0.058, 0.035), "blued_dark", Vector3(0.6, 0, 0))   # palanca
	for x in [-0.009, 0.009]:
		_box(root, Vector3(0.006, 0.014, 0.012), Vector3(x, 0.05, 0.05), "blued_dark", Vector3(0.5, 0, 0))   # martillos
	# Guardamonte y gatillos
	_box(root, Vector3(0.01, 0.005, 0.075), Vector3(0, -0.03, 0.02), "blued")
	_box(root, Vector3(0.006, 0.02, 0.006), Vector3(0, -0.016, 0.01), "silver", Vector3(-0.2, 0, 0))
	_box(root, Vector3(0.006, 0.02, 0.006), Vector3(0, -0.016, 0.03), "silver", Vector3(-0.2, 0, 0))
	# Culata con garganta de pistola
	_limb(root, Vector3(0, -0.005, 0.06), Vector3(0, -0.04, 0.14), 0.022, "walnut", 1.0)
	_limb(root, Vector3(0, -0.035, 0.12), Vector3(0, -0.075, 0.36), 0.03, "walnut", 0.85)
	_limb(root, Vector3(0, 0.0, 0.1), Vector3(0, -0.03, 0.36), 0.024, "walnut", 0.85)
	_box(root, Vector3(0.042, 0.11, 0.02), Vector3(0, -0.055, 0.385), "rubber", Vector3(-0.15, 0, 0))


static func _shotgun_hands(root: Node3D) -> void:
	var h := Node3D.new()
	h.name = "manos"
	root.add_child(h)
	# Derecha en la garganta de la culata
	_limb(h, Vector3(0.022, -0.035, 0.11), Vector3(0.02, -0.06, 0.13), 0.028, "skin", 0.75)
	_limb(h, Vector3(0.025, -0.05, 0.14), Vector3(0.05, -0.12, 0.19), 0.031, "skin")
	_limb(h, Vector3(0.05, -0.12, 0.19), Vector3(0.11, -0.36, 0.28), 0.04, "sleeve")
	_limb(h, Vector3(0.048, -0.115, 0.188), Vector3(0.062, -0.16, 0.21), 0.044, "cuff")
	for i in 3:
		var y := -0.03 - i * 0.022
		_finger(h, [Vector3(0.02, y, 0.11), Vector3(0.012, y - 0.004, 0.085), Vector3(-0.008, y - 0.006, 0.08), Vector3(-0.02, y - 0.006, 0.095)], 0.0088)
	_finger(h, [Vector3(0.018, -0.015, 0.06), Vector3(0.012, -0.018, 0.03), Vector3(0.003, -0.02, 0.012)], 0.0085)
	_finger(h, [Vector3(0.0, 0.0, 0.11), Vector3(-0.016, 0.012, 0.085), Vector3(-0.022, 0.02, 0.06)], 0.0095)
	# Izquierda bajo el guardamanos
	_limb(h, Vector3(-0.005, -0.025, -0.22), Vector3(0.0, -0.03, -0.26), 0.028, "skin", 0.8)
	_limb(h, Vector3(-0.01, -0.035, -0.2), Vector3(-0.05, -0.1, -0.12), 0.031, "skin")
	_limb(h, Vector3(-0.05, -0.1, -0.12), Vector3(-0.16, -0.34, 0.05), 0.04, "sleeve")
	_limb(h, Vector3(-0.048, -0.096, -0.124), Vector3(-0.065, -0.13, -0.1), 0.044, "cuff")
	for i in 4:
		var z := -0.205 - i * 0.02
		_finger(h, [Vector3(-0.026, -0.016, z), Vector3(-0.03, 0.006, z - 0.004), Vector3(-0.024, 0.022, z - 0.006)], 0.0082)
	_finger(h, [Vector3(0.018, -0.02, -0.205), Vector3(0.026, 0.002, -0.235), Vector3(0.024, 0.016, -0.26)], 0.009)


# ---------------------------------------------------------------- Cañón de Zurraspa

## Piezas sueltas (también se usan en el mapa para recogerlas)
static func part_model(id: String, s := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = id
	match id:
		"calzoncillo":
			_box(root, Vector3(0.34, 0.05, 0.22) * s, Vector3(0, 0.1, 0) * s, "elastic")
			_box(root, Vector3(0.3, 0.16, 0.04) * s, Vector3(0, 0.0, 0.09) * s, "cotton", Vector3(0.15, 0, 0))
			_box(root, Vector3(0.3, 0.16, 0.04) * s, Vector3(0, 0.0, -0.09) * s, "cotton", Vector3(-0.15, 0, 0))
			_box(root, Vector3(0.12, 0.06, 0.2) * s, Vector3(0, -0.09, 0) * s, "cotton")
			for side in [-1.0, 1.0]:
				_box(root, Vector3(0.04, 0.12, 0.2) * s, Vector3(0.15 * side, 0.02, 0) * s, "cotton", Vector3(0, 0, 0.3 * side))
			_sphere(root, 0.06 * s, Vector3(0.01, -0.03, -0.112) * s, "zurraspa", Vector3(1.4, 1.1, 0.25))
			_sphere(root, 0.035 * s, Vector3(-0.05, -0.08, -0.06) * s, "zurraspa", Vector3(1.0, 0.3, 1.4))
		"tele":
			_box(root, Vector3(0.44, 0.36, 0.2) * s, Vector3(0, 0, 0.0) * s, "plastic")
			_box(root, Vector3(0.32, 0.26, 0.22) * s, Vector3(0, 0, 0.19) * s, "plastic")
			_box(root, Vector3(0.18, 0.14, 0.1) * s, Vector3(0, 0, 0.33) * s, "plastic_dark")
			_box(root, Vector3(0.36, 0.28, 0.01) * s, Vector3(-0.025, 0.01, -0.101) * s, "plastic_dark")
			_sphere(root, 0.17 * s, Vector3(-0.025, 0.01, -0.095) * s, "crt", Vector3(1.0, 0.8, 0.12))
			for k in 2:
				_tube(root, 0.012 * s, 0.012 * s, Vector3(0.19, 0.06 - k * 0.06, -0.102) * s, "plastic_dark", 10)
			for side in [-1.0, 1.0]:
				_limb(root, Vector3(0.02 * side, 0.18, 0.08) * s, Vector3(0.14 * side, 0.42, 0.12) * s, 0.005 * s, "silver")
			_sphere(root, 0.05 * s, Vector3(0.12, 0.17, 0.05) * s, "zurraspa", Vector3(1.4, 0.3, 1.2))
		"canon":
			_tube(root, 0.05 * s, 0.38 * s, Vector3.ZERO, "blued", 20)
			for k in 3:
				var t := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.05 * s
				tm.outer_radius = 0.07 * s
				t.mesh = tm
				t.material_override = _mat("copper")
				t.rotation.x = PI * 0.5
				t.position = Vector3(0, 0, (-0.12 + k * 0.12) * s)
				root.add_child(t)
			_sphere(root, 0.055 * s, Vector3(0, 0.08, 0.06) * s, "bulb")
			_tube(root, 0.06 * s, 0.03 * s, Vector3(0, 0, -0.205) * s, "copper", 16)
			_sphere(root, 0.03 * s, Vector3(0.04, 0.03, -0.1) * s, "zurraspa", Vector3(1.0, 0.4, 1.6))
	return root


## Versión dorada: pantalla de la tele dorada y radiactiva, calzones de oro.
static func _gild(root: Node3D) -> void:
	var swap := {_mat("crt"): _mat("gold_crt"), _mat("cotton"): _mat("gold"), _mat("elastic"): _mat("gold"),
		_mat("plastic"): _mat("gold"), _mat("copper"): _mat("gold")}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and swap.has(n.material_override):
			n.material_override = swap[n.material_override]
		stack.append_array(n.get_children())
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.15)
	l.light_energy = 1.2
	l.omni_range = 1.5
	l.position = Vector3(0, 0.07, -0.36)
	root.add_child(l)


static func _zurraspa(root: Node3D) -> void:
	# empuñadura envuelta en el calzoncillo
	var gr := Node3D.new()
	gr.position = Vector3(0, -0.012, 0.012)
	gr.rotation.x = -0.21
	root.add_child(gr)
	_box(gr, Vector3(0.03, 0.11, 0.055), Vector3(0, -0.048, 0.0), "blued_dark")
	var briefs := part_model("calzoncillo", 0.42)
	briefs.position = Vector3(0, -0.05, 0.0)
	briefs.rotation = Vector3(0, PI * 0.5, PI * 0.5)
	gr.add_child(briefs)
	# cuerpo: el cañón de bobinas
	var body := part_model("canon", 0.62)
	body.position = Vector3(0, 0.035, -0.08)
	root.add_child(body)
	_box(root, Vector3(0.03, 0.02, 0.12), Vector3(0, 0.0, -0.02), "blued_dark")
	_box(root, Vector3(0.008, 0.03, 0.05), Vector3(0, -0.02, -0.04), "blued")
	# la tele hace de boca del arma
	var tv := part_model("tele", 0.42)
	tv.position = Vector3(0, 0.07, -0.25)
	root.add_child(tv)
	_box(root, Vector3(0.006, 0.02, 0.006), Vector3(0, 0.152, -0.27), "silver")
	_box(root, Vector3(0.006, 0.075, 0.006), Vector3(0, 0.115, 0.02), "blued_dark")
	for x in [-0.009, 0.009]:
		_box(root, Vector3(0.006, 0.012, 0.006), Vector3(x, 0.156, 0.02), "silver")
	for p in [Vector3(0.02, 0.06, -0.12), Vector3(-0.025, 0.02, -0.05), Vector3(0.0, 0.13, -0.22), Vector3(0.018, -0.06, 0.02)]:
		_sphere(root, 0.018, p, "zurraspa", Vector3(1.3, 0.5, 1.6))
