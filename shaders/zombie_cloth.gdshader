// Ropa de zombie: sucia, rasgada (agujeros) y manchada de sangre
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.3, 0.3, 0.35);
uniform float tear = 0.35;
uniform float blood = 0.4;
uniform float seed = 0.0;

varying vec3 opos;

void vertex() {
	opos = VERTEX;
}

void fragment() {
	vec3 p = opos * 2.5 + seed;
	float holes = texture(noise_tex, p.xy * 0.9 + p.z * 0.4 + 11.0).r;
	if (holes > 1.0 - tear * 0.35) {
		discard;
	}
	float weave = 0.9 + 0.1 * sin(opos.x * 600.0) * sin(opos.y * 600.0);
	float dirt = texture(noise_tex, p.xz * 0.6).r;
	vec3 col = color * (0.6 + 0.6 * dirt) * weave;
	float edge = smoothstep(1.0 - tear * 0.35 - 0.06, 1.0 - tear * 0.35, holes);
	col = mix(col, col * 0.4, edge);
	float b = smoothstep(1.0 - blood * 0.7, 1.0 - blood * 0.7 + 0.1, texture(noise_tex, p.xy * 0.45 + 3.0).r);
	col = mix(col, vec3(0.2, 0.015, 0.015), b * 0.9);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.4, b);
}
