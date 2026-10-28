extends RefCounted
## Datos y modelos de las armas.

const DATA := {
	"pistola": {
		"name": "Pistola M1911",
		"damage": 50.0, "pellets": 1, "mag": 8, "reserve": 80,
		"fire_delay": 0.16, "reload": 1.5, "auto": false,
		"spread_hip": 0.018, "spread_ads": 0.003, "range": 150.0, "falloff": 999.0,
		"recoil": 1.0, "kick": 0.010, "sound": "pistol_shot", "pitch": 1.0, "volume": -3.0,
		"cost": 0, "hip": Vector3(0.20, -0.20, -0.44), "ads": Vector3(0.0, -0.118, -0.32),
	},
	"escopeta": {
		"name": "Escopeta de caza",
		"damage": 75.0, "pellets": 8, "mag": 2, "reserve": 60,
		"fire_delay": 0.28, "reload": 2.4, "auto": false,
		"spread_hip": 0.065, "spread_ads": 0.045, "range": 40.0, "falloff": 9.0,
		"recoil": 1.8, "kick": 0.04, "sound": "pistol_shot", "pitch": 0.62, "volume": 1.5,
		"cost": 500, "hip": Vector3(0.18, -0.22, -0.52), "ads": Vector3(0.0, -0.13, -0.36),
	},
}


static func data(id: String) -> Dictionary:
	return DATA[id]


static func _m(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3(PI * 0.5, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Modelo del arma. Si with_hands, añade manos y mangas (vista en primera persona).
static func build_model(id: String, with_hands := false) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var steel := _m(Color(0.20, 0.20, 0.21), 0.38, 0.85)
	var dark := _m(Color(0.09, 0.09, 0.095), 0.45, 0.6)
	var wood := _m(Color(0.36, 0.20, 0.10), 0.55)
	var walnut := _m(Color(0.28, 0.14, 0.07), 0.5)
	match id:
		"pistola":
			_box(root, Vector3(0.036, 0.034, 0.205), Vector3(0, 0.032, -0.06), steel)          # corredera
			for k in 6:
				_box(root, Vector3(0.038, 0.026, 0.004), Vector3(0, 0.034, 0.02 + k * 0.006), dark)  # estrías
			_box(root, Vector3(0.032, 0.026, 0.17), Vector3(0, 0.003, -0.05), dark)            # armazón
			_cyl(root, 0.009, 0.03, Vector3(0, 0.03, -0.17), dark)                            # boca de cañón
			_box(root, Vector3(0.036, 0.115, 0.058), Vector3(0, -0.062, 0.018), walnut, Vector3(-0.2, 0, 0))  # cachas
			_box(root, Vector3(0.006, 0.012, 0.012), Vector3(0, 0.054, -0.15), steel)          # punto de mira
			_box(root, Vector3(0.03, 0.01, 0.012), Vector3(0, 0.052, 0.035), steel)            # alza
			_box(root, Vector3(0.026, 0.006, 0.05), Vector3(0, -0.033, -0.025), dark)          # guardamonte
			_box(root, Vector3(0.012, 0.018, 0.012), Vector3(0, 0.035, 0.05), dark, Vector3(0.5, 0, 0))  # martillo
		"escopeta":
			for x in [-0.017, 0.017]:
				_cyl(root, 0.016, 0.62, Vector3(x, 0.03, -0.36), steel)                         # cañones
			_box(root, Vector3(0.012, 0.008, 0.6), Vector3(0, 0.05, -0.36), dark)             # banda
			_box(root, Vector3(0.006, 0.01, 0.01), Vector3(0, 0.058, -0.66), steel)          # punto de mira
			_box(root, Vector3(0.05, 0.03, 0.26), Vector3(0, 0.0, -0.22), wood)               # guardamanos
			_box(root, Vector3(0.056, 0.06, 0.13), Vector3(0, 0.02, -0.02), steel)            # báscula
			_box(root, Vector3(0.012, 0.03, 0.03), Vector3(0, 0.06, 0.04), dark, Vector3(0.6, 0, 0))  # palanca
			_box(root, Vector3(0.026, 0.008, 0.07), Vector3(0, -0.02, 0.03), dark)            # guardamonte
			_box(root, Vector3(0.045, 0.07, 0.12), Vector3(0, -0.02, 0.1), walnut, Vector3(-0.25, 0, 0))   # garganta
			_box(root, Vector3(0.048, 0.11, 0.26), Vector3(0, -0.06, 0.26), walnut, Vector3(-0.12, 0, 0))  # culata
	if with_hands:
		var skin := _m(Color(0.50, 0.37, 0.30), 0.7)
		var sleeve := _m(Color(0.22, 0.24, 0.18), 0.95)
		var glove := _m(Color(0.12, 0.10, 0.08), 0.8)
		match id:
			"pistola":
				_box(root, Vector3(0.06, 0.07, 0.09), Vector3(0.0, -0.075, 0.045), glove, Vector3(-0.2, 0, 0))
				_box(root, Vector3(0.075, 0.085, 0.32), Vector3(0.01, -0.13, 0.24), sleeve, Vector3(0.35, 0.08, 0))
				_box(root, Vector3(0.055, 0.055, 0.08), Vector3(-0.03, -0.05, 0.03), skin, Vector3(-0.1, 0.3, 0))
				_box(root, Vector3(0.07, 0.08, 0.3), Vector3(-0.09, -0.12, 0.22), sleeve, Vector3(0.35, -0.35, 0))
			"escopeta":
				_box(root, Vector3(0.06, 0.06, 0.09), Vector3(0, -0.035, -0.26), glove)
				_box(root, Vector3(0.075, 0.085, 0.36), Vector3(-0.06, -0.1, -0.06), sleeve, Vector3(0.25, -0.5, 0))
				_box(root, Vector3(0.06, 0.07, 0.08), Vector3(0, -0.06, 0.08), glove, Vector3(-0.3, 0, 0))
				_box(root, Vector3(0.075, 0.085, 0.3), Vector3(0.03, -0.12, 0.25), sleeve, Vector3(0.4, 0.1, 0))
	return root
