shader_type spatial;
// Vórtice del portal (estilo años 80): espirales de colores que giran hacia el centro.
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 col_a : source_color = vec4(0.65, 0.15, 1.0, 1.0);
uniform vec4 col_b : source_color = vec4(0.05, 0.95, 0.85, 1.0);
uniform float power = 1.0;   // 0 = apagado

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x);
	float s1 = sin(a * 5.0 + r * 16.0 - TIME * 5.0) * 0.5 + 0.5;
	float s2 = sin(a * 3.0 - r * 9.0 + TIME * 2.3) * 0.5 + 0.5;
	vec3 c = mix(col_a.rgb, col_b.rgb, s1 * s2 + 0.2 * sin(TIME + r * 4.0));
	c *= 0.55 + 0.9 * s1;
	c += vec3(1.0, 0.95, 1.0) * smoothstep(0.32, 0.0, r) * 0.9;
	float edge = smoothstep(1.0, 0.82, r);
	ALBEDO = c * (0.15 + 0.85 * power);
	ALPHA = edge * mix(0.12, 0.6 + 0.4 * s1, power);
}
