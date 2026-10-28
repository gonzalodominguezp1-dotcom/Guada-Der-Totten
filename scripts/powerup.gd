extends Area3D
## Power-up que suelta un zombie al morir: brilla en verde, gira y
## desaparece a los 30 s (parpadea al final).

var kind := "max_ammo"
var game
var life := 30.0
var t := 0.0
var icon: Node3D
var label: Label3D

const LABELS := {
	"max_ammo": "MUNICIÓN", "insta_kill": "MUERTE\nINSTANTÁNEA",
	"double_points": "PUNTOS x2", "nuke": "NUKE",
}


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.9
	cs.shape = sh
	add_child(cs)
	body_entered.connect(_on_body)

	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.75, 0.25)
	gold.metallic = 1.0
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Color(0.6, 0.45, 0.1)
	gold.emission_energy_multiplier = 0.6
	icon = Node3D.new()
	add_child(icon)
	match kind:
		"max_ammo":
			for x in [-0.12, 0.0, 0.12]:
				_cyl(icon, 0.045, 0.32, Vector3(x, 0, 0), gold)
				_cyl(icon, 0.03, 0.08, Vector3(x, 0.2, 0), gold)
		"insta_kill":
			var sk := SphereMesh.new()
			sk.radius = 0.2
			sk.height = 0.4
			_mesh(icon, sk, Vector3(0, 0.05, 0), gold)
			var jm := BoxMesh.new()
			jm.size = Vector3(0.22, 0.12, 0.22)
			_mesh(icon, jm, Vector3(0, -0.15, 0), gold)
		"double_points":
			var l := Label3D.new()
			l.text = "x2"
			l.font_size = 120
			l.pixel_size = 0.004
			l.modulate = Color(1.0, 0.85, 0.3)
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			icon.add_child(l)
		"nuke":
			_cyl(icon, 0.16, 0.42, Vector3.ZERO, gold, Vector3(0, 0, PI * 0.5))
			for k in 3:
				var fin := BoxMesh.new()
				fin.size = Vector3(0.12, 0.2, 0.02)
				var f := _mesh(icon, fin, Vector3(-0.22, 0, 0), gold)
				f.rotation.x = TAU * k / 3.0
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 1.0, 0.35)
	light.light_energy = 2.5
	light.omni_range = 4.0
	add_child(light)
	var p := CPUParticles3D.new()
	p.amount = 30
	p.lifetime = 1.2
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, 0.5, 0)
	var pm := SphereMesh.new()
	pm.radius = 0.03
	pm.height = 0.06
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.4, 1.0, 0.4)
	pm.material = glow
	p.mesh = pm
	add_child(p)
	Sfx.play3d("powerup_spawn", global_position, -6.0)


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	var mi := _mesh(parent, cm, pos, mat)
	mi.rotation = rot
	return mi


func _mesh(parent: Node3D, m: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _process(delta: float) -> void:
	t += delta
	life -= delta
	icon.rotation.y += delta * 2.0
	icon.position.y = sin(t * 2.5) * 0.1
	if life < 8.0:
		visible = fmod(t, 0.4 if life > 3.0 else 0.2) < (0.25 if life > 3.0 else 0.1)
	if life <= 0.0:
		queue_free()


func _on_body(body: Node) -> void:
	if not body.is_in_group("player") or body.dead:
		return
	if game:
		game.activate_powerup(kind)
	Sfx.play("powerup_grab", -2.0)
	queue_free()
