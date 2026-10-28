extends Node3D
## Escena principal: ambiente nocturno, pueblo, jugador, HUD, rondas
## y power-ups.

const TownGenerator = preload("res://scripts/town_generator.gd")
const PlayerScript = preload("res://scripts/player.gd")
const RoundManagerScript = preload("res://scripts/round_manager.gd")
const HudScript = preload("res://scripts/hud.gd")

const TOWN_JSON := "res://data/town.json"
const POWERUP_TIME := 30.0

var town: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var rounds: Node
var flicker_t := 0.0
var powerups := {}   # nombre -> segundos restantes
var parts := {}      # piezas del Cañón de Zurraspa conseguidas


func _ready() -> void:
	randomize()
	_setup_input()
	_setup_environment()

	town = TownGenerator.new()
	town.name = "Town"
	add_child(town)
	town.build(TOWN_JSON)
	for wb in get_tree().get_nodes_in_group("workbench"):
		wb.game = self

	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)

	player = PlayerScript.new()
	player.name = "Player"
	player.hud = hud
	player.game = self
	add_child(player)
	player.global_position = town.player_start + Vector3.UP * 0.2
	player.rotation.y = town.player_start_yaw
	player.died.connect(_on_player_died)

	rounds = RoundManagerScript.new()
	rounds.name = "Rounds"
	add_child(rounds)
	rounds.setup(player, town, hud, self)
	rounds.start()
	Sfx.loop_2d("wind_loop", -18.0)


func _process(delta: float) -> void:
	flicker_t += delta
	for l in town.lamps:
		var light: OmniLight3D = l["light"]
		match l["mode"]:
			"flicker":
				var v := sin(flicker_t * l["speed"]) + sin(flicker_t * l["speed"] * 2.7 + 1.3)
				light.light_energy = l["base"] * (0.15 if v > 1.3 else 1.0)
			"dying":
				light.light_energy = l["base"] * (0.0 if randf() < 0.08 else 0.55)
	if not powerups.is_empty():
		for k in powerups.keys():
			powerups[k] -= delta
			if powerups[k] <= 0.0:
				powerups.erase(k)
		hud.set_powerups(powerups)


# ---------------------------------------------------------------- power-ups

func collect_part(part: String) -> void:
	parts[part] = true
	var names := {"calzoncillo": "EL CALZONCILLO SUCIO", "tele": "LA TELE DE TUBO", "canon": "EL CAÑÓN"}
	hud.announce("¡Has encontrado %s!" % names.get(part, part))
	hud.set_parts(parts)


func instakill_active() -> bool:
	return powerups.has("insta_kill")


func double_points_active() -> bool:
	return powerups.has("double_points")


func activate_powerup(kind: String) -> void:
	match kind:
		"max_ammo":
			player.refill_all_ammo()
			hud.announce("¡MUNICIÓN MÁXIMA!")
		"insta_kill":
			powerups["insta_kill"] = POWERUP_TIME
			hud.announce("¡MUERTE INSTANTÁNEA!")
		"double_points":
			powerups["double_points"] = POWERUP_TIME
			hud.announce("¡PUNTOS DOBLES!")
		"nuke":
			hud.flash()
			hud.announce("¡KABOOM!")
			rounds.kill_all()
			player.add_points(400)
	hud.set_powerups(powerups)


# ---------------------------------------------------------------- partida

func _unhandled_input(event: InputEvent) -> void:
	if player and player.dead:
		if event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
			get_tree().reload_current_scene()


func _on_player_died() -> void:
	hud.show_game_over(rounds.round_num)


func _setup_input() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("jump", KEY_SPACE)
	_add_key("sprint", KEY_SHIFT)
	_add_key("reload", KEY_R)
	_add_key("interact", KEY_F)
	_add_key("melee", KEY_V)
	_add_key("weapon_1", KEY_1)
	_add_key("weapon_2", KEY_2)
	_add_mouse("shoot", MOUSE_BUTTON_LEFT)
	_add_mouse("aim", MOUSE_BUTTON_RIGHT)
	_add_mouse("melee", MOUSE_BUTTON_MIDDLE)


func _add_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	var env := Environment.new()
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.03, 0.045, 0.08)
	sky_mat.sky_horizon_color = Color(0.11, 0.13, 0.17)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.02)
	sky_mat.ground_horizon_color = Color(0.09, 0.1, 0.12)
	sky_mat.sun_angle_max = 2.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.11, 0.13, 0.17)
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.78
	env.adjustment_contrast = 1.08

	if compat:
		# OpenGL: sin iluminación global ni niebla volumétrica → más luz ambiente
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.40, 0.45, 0.58)
		env.ambient_light_energy = 0.75
		env.tonemap_exposure = 1.45
		env.fog_density = 0.016
		env.adjustment_brightness = 1.05
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.4
		env.tonemap_exposure = 1.3
		env.ssao_enabled = true
		env.ssr_enabled = true
		env.sdfgi_enabled = true
		env.fog_density = 0.012
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.02
		env.volumetric_fog_albedo = Color(0.75, 0.77, 0.8)
		env.volumetric_fog_length = 70.0

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Luna"
	moon.light_color = Color(0.62, 0.70, 0.95)
	moon.light_energy = 0.7
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 70.0
	moon.rotation_degrees = Vector3(-50, 35, 0)
	add_child(moon)
