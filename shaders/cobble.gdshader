// Adoquines con juntas, variación por piedra y charcos que reflejan las farolas.
shader_type spatial;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 stone_color : source_color = vec3(0.36, 0.34, 0.31);
uniform vec3 gap_color : source_color = vec3(0.10, 0.095, 0.09);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 sz = vec2(0.34, 0.22);
	vec2 p = wpos.xz / sz;
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float h = hash12(cell);
	vec2 d = min(f, 1.0 - f) * sz;
	float edge = min(d.x, d.y);
	float stone = smoothstep(0.006, 0.022, edge);

	float n = texture(noise_tex, wpos.xz * 0.05).r;
	float n2 = texture(noise_tex, wpos.xz * 0.9).r;
	vec3 col = mix(gap_color, stone_color * (0.7 + 0.55 * h) * (0.8 + 0.4 * n2), stone);
	float wet = smoothstep(0.56, 0.68, n);

	ALBEDO = col * (1.0 - 0.35 * wet);
	ROUGHNESS = mix(mix(0.95, 0.72, stone), 0.1, wet);
	SPECULAR = 0.5;
}
