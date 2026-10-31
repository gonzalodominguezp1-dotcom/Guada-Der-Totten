extends SceneTree
## Viaje completo en el autobús 726 con el jugador dentro (comprueba que no se sale):
##   godot --headless --path . -s tests/bus_ride.gd --fixed-fps 60
var main
var f := 0
var placed := false
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
func _process(_d):
	f += 1
	var t = main.town
	var p = main.player
	var b = t.bus
	if f == 3:
		p.max_health = 1e9
		p.health = 1e9
		main.rounds.set_process(false)
		t.exterior_open = true
		b.wait_t = 2.0
	if f == 20:
		p.global_position = b.body.to_global(Vector3(-0.3, 0.6, 2.2))
		p.velocity = Vector3.ZERO
	if f > 20 and f % 120 == 0:
		var lp: Vector3 = b.body.to_local(p.global_position)
		var bad := absf(lp.x) > 1.3 or absf(lp.z) > 6.0 or lp.y < -0.2 or lp.y > 3.0
		print("f ", f, " st ", b.state, " s ", int(b.s), " v ", snappedf(b.v, 0.1), " next ", b.next_stop, " lp ", lp.snappedf(0.1), " mask ", p.collision_mask, " floor ", p.is_on_floor(), " BAD" if bad else "")
		if bad:
			return true
	return f > 30000 or b.arrivals >= 5
