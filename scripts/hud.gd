extends CanvasLayer
## HUD al estilo WaW: ronda en rojo con rayas abajo a la izquierda, perks
## encima, puntos y munición abajo a la derecha, avisos de compra en el
## centro, power-ups activos abajo en el centro y viñeta roja de daño.

var root: Control
var damage_mat: ShaderMaterial
var flash_rect: ColorRect
var round_label: Label
var points_label: Label
var ammo_label: Label
var weapon_label: Label
var center_label: Label
var announce_label: Label
var hint_label: Label
var prompt_label: Label
var hitmarker: Label
var points_box: VBoxContainer
var perk_box: HBoxContainer
var powerup_label: Label
var downed_box: VBoxContainer
var downed_bar: ProgressBar
var crosshair: Control

const DAMAGE_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float downed = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv) * 1.45;
	float a = smoothstep(0.3, 1.0, d) * amount;
	COLOR = vec4(0.5, 0.0, 0.0, max(a, downed * (0.35 + 0.4 * smoothstep(0.2, 0.9, d))));
}
"""

const PERK_COLORS := {"quick_revive": Color(0.35, 0.75, 1.0)}


func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var damage_rect := ColorRect.new()
	damage_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = DAMAGE_SHADER
	damage_mat = ShaderMaterial.new()
	damage_mat.shader = sh
	damage_rect.material = damage_mat
	root.add_child(damage_rect)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 1, 1, 0)
	root.add_child(flash_rect)

	round_label = _label(110, Color(0.62, 0.04, 0.02))
	round_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 36)
	round_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	perk_box = HBoxContainer.new()
	perk_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(perk_box)
	perk_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 36)
	perk_box.position.y -= 150
	perk_box.add_theme_constant_override("separation", 8)

	points_box = VBoxContainer.new()
	points_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	points_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(points_box)
	points_label = _label(38, Color(0.98, 0.86, 0.35), points_box)
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label = _label(20, Color(0.85, 0.85, 0.82), points_box)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label = _label(30, Color(0.92, 0.92, 0.92), points_box)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 36)
	points_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	points_box.grow_vertical = Control.GROW_DIRECTION_BEGIN

	center_label = _label(64, Color(0.75, 0.06, 0.03))
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.modulate.a = 0.0

	announce_label = _label(46, Color(0.95, 0.85, 0.3))
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 140)
	announce_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	announce_label.modulate.a = 0.0

	prompt_label = _label(24, Color(0.95, 0.95, 0.92))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_label.position.y += 90

	powerup_label = _label(26, Color(0.5, 1.0, 0.5))
	powerup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	powerup_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	powerup_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	powerup_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	hint_label = _label(20, Color(0.85, 0.85, 0.85))
	hint_label.text = "WASD moverse · Shift correr · Clic disparar · Clic dcho apuntar · R recargar · V cuchillo · F usar/comprar · 1/2 cambiar arma · Esc soltar ratón"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var tw := create_tween()
	tw.tween_interval(12.0)
	tw.tween_property(hint_label, "modulate:a", 0.0, 2.0)

	downed_box = VBoxContainer.new()
	downed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(downed_box)
	var dl := _label(30, Color(0.6, 0.85, 1.0), downed_box)
	dl.text = "QUICK REVIVE TE ESTÁ LEVANTANDO..."
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	downed_bar = ProgressBar.new()
	downed_bar.custom_minimum_size = Vector2(420, 16)
	downed_bar.show_percentage = false
	downed_bar.max_value = 1.0
	downed_box.add_child(downed_bar)
	downed_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	downed_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	downed_box.position.y += 60
	downed_box.visible = false

	crosshair = Control.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	root.add_child(crosshair)
	for r in [Rect2(-1, -14, 2, 8), Rect2(-1, 6, 2, 8), Rect2(-14, -1, 8, 2), Rect2(6, -1, 8, 2)]:
		var c := ColorRect.new()
		c.color = Color(1, 1, 1, 0.75)
		c.position = r.position
		c.size = r.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.add_child(c)

	hitmarker = _label(30, Color(1, 1, 1))
	hitmarker.text = "✕"
	hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hitmarker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hitmarker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hitmarker.modulate.a = 0.0


func _label(size: int, color: Color, parent: Control = null) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else root).add_child(l)
	return l


func set_points(p: int) -> void:
	points_label.text = str(p)


func set_ammo(mag: int, reserve: int, reloading: bool) -> void:
	ammo_label.text = ("RECARGANDO   " if reloading else "") + "%d / %d" % [mag, reserve]
	ammo_label.add_theme_color_override("font_color",
		Color(0.95, 0.3, 0.2) if mag == 0 else Color(0.92, 0.92, 0.92))


func set_weapon(n: String) -> void:
	weapon_label.text = n


func set_health(frac: float) -> void:
	damage_mat.set_shader_parameter("amount", clampf((1.0 - frac) * 1.6, 0.0, 1.0))


func set_prompt(t: String) -> void:
	if prompt_label.text != t:
		prompt_label.text = t


func set_perks(perks: Array) -> void:
	for c in perk_box.get_children():
		c.queue_free()
	for p in perks:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(52, 52)
		var sb := StyleBoxFlat.new()
		sb.bg_color = PERK_COLORS.get(p, Color.WHITE).darkened(0.3)
		sb.border_color = Color(0.9, 0.9, 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = "✚"
		l.add_theme_font_size_override("font_size", 34)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(l)
		perk_box.add_child(panel)


func set_powerups(active: Dictionary) -> void:
	var parts: Array = []
	for k in active:
		var name_txt: String = {"insta_kill": "MUERTE INSTANTÁNEA", "double_points": "PUNTOS x2"}.get(k, k)
		parts.append("%s %d" % [name_txt, ceili(active[k])])
	powerup_label.text = "     ".join(parts)


func announce(t: String) -> void:
	announce_label.text = t
	announce_label.modulate.a = 1.0
	announce_label.scale = Vector2(1.3, 1.3)
	var tw := create_tween()
	tw.tween_property(announce_label, "scale", Vector2.ONE, 0.25)
	tw.tween_interval(2.0)
	tw.tween_property(announce_label, "modulate:a", 0.0, 1.0)


func flash() -> void:
	flash_rect.color = Color(1, 1, 1, 0.9)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 1.2)


func show_downed(on: bool) -> void:
	downed_box.visible = on
	damage_mat.set_shader_parameter("downed", 1.0 if on else 0.0)


func set_downed_progress(v: float) -> void:
	downed_bar.value = v


func show_round(n: int) -> void:
	var tw := create_tween()
	tw.tween_property(round_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): round_label.text = _tally(n))
	tw.tween_property(round_label, "modulate", Color(1, 1, 1, 1), 0.6)
	tw.tween_property(round_label, "modulate", Color(1.8, 1.8, 1.8, 1), 0.4)
	tw.tween_property(round_label, "modulate", Color(1, 1, 1, 1), 0.4)
	center_label.text = "RONDA %d" % n
	var tw2 := create_tween()
	tw2.tween_property(center_label, "modulate:a", 1.0, 0.8)
	tw2.tween_interval(1.6)
	tw2.tween_property(center_label, "modulate:a", 0.0, 1.0)


func _tally(n: int) -> String:
	if n <= 5:
		return "I".repeat(n)
	return str(n)


func show_hitmarker(kill: bool) -> void:
	hitmarker.add_theme_color_override("font_color", Color(1, 0.2, 0.15) if kill else Color(1, 1, 1))
	hitmarker.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(hitmarker, "modulate:a", 0.0, 0.25)


func popup_points(n: int) -> void:
	var l := _label(26, Color(1.0, 0.85, 0.2) if n > 0 else Color(1.0, 0.3, 0.2))
	l.text = ("+%d" % n) if n > 0 else str(n)
	var base := points_box.global_position + Vector2(-60 + randf_range(-20, 20), 0)
	l.position = base
	var tw := create_tween()
	tw.tween_property(l, "position", base + Vector2(randf_range(-40, -10), -50), 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	tw.tween_callback(l.queue_free)


func show_game_over(round_num: int) -> void:
	var sobrevividas := maxi(round_num - 1, 0)
	center_label.text = "HAS MUERTO\n\n" + \
		"Sobreviviste %d %s\n\nPulsa ENTER para volver a jugar" % [sobrevividas, "ronda" if sobrevividas == 1 else "rondas"]
	center_label.add_theme_font_size_override("font_size", 48)
	var tw := create_tween()
	tw.tween_property(center_label, "modulate:a", 1.0, 1.5)
	crosshair.visible = false
	prompt_label.text = ""
