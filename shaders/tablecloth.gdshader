// Mantel de cuadros rojos y blancos
shader_type spatial;
render_mode cull_disabled;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (wpos.xz + vec2(wpos.y)) / 0.07;
	float a = step(0.5, fract(p.x * 0.5));
	float b = step(0.5, fract(p.y * 0.5));
	vec3 red = vec3(0.62, 0.05, 0.06);
	vec3 white = vec3(0.86, 0.84, 0.80);
	vec3 col = mix(white, red, 0.5 * (a + b));
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
