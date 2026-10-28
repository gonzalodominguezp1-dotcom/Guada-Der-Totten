extends SceneTree
## Uso: xvfb-run godot --path . -s tests/screenshots.gd --fixed-fps 60 --resolution 1280x720
## Lee las cámaras de tests/screenshot_plan.json y guarda capturas en user://
## Capturas: cada entrada = [marco, posición cámara, objetivo, espacio ("bar" o "world"), apuntar]
var main
var f := 0
var plan := []
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var txt := FileAccess.get_file_as_string("res://tests/screenshot_plan.json")
	plan = JSON.parse_string(txt)
func cam(pos: Vector3, target: Vector3, space: String):
	var b = main.town.bar
	var p = main.player
	var cp: Vector3 = b.to_global(pos) if space == "bar" else pos
	var tg: Vector3 = b.to_global(target) if space == "bar" else target
	p.global_position = cp - Vector3(0, 1.65, 0)
	var to: Vector3 = tg - cp
	p.rotation.y = atan2(-to.x, -to.z)
	p.head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	p.velocity = Vector3.ZERO
func _process(_d):
	f += 1
	var p = main.player
	if f == 2:
		p.max_health = 1e9
		p.health = 1e9
		main.rounds.set_process(false)
		p.hud.hint_label.visible = false
	var i := 0
	for e in plan:
		var start := 20 + i * 45
		if f >= start and f < start + 40:
			cam(Vector3(e[0][0], e[0][1], e[0][2]), Vector3(e[1][0], e[1][1], e[1][2]), e[2])
			if e[3]:
				Input.action_press("aim")
			else:
				Input.action_release("aim")
		if f == start + 40:
			root.get_texture().get_image().save_png("user://captura_%d.png" % i)
		i += 1
	if f > 20 + plan.size() * 45:
		return true
	return false
