// Acera de adoquín prefabricado rojizo (como la Avenida Alejandro Rubio)
shader_type spatial;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 color_a : source_color = vec3(0.50, 0.30, 0.26);
uniform vec3 color_b : source_color = vec3(0.60, 0.38, 0.33);

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
	vec2 sz = vec2(0.20, 0.10);
	vec2 p = wpos.xz / sz;
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 d = min(f, 1.0 - f) * sz;
	float edge = min(d.x, d.y);
	float stone = smoothstep(0.003, 0.012, edge);
	float h = hash12(cell);
	float n = texture(noise_tex, wpos.xz * 0.05).r;
	float n2 = texture(noise_tex, wpos.xz * 1.3).r;
	vec3 col = mix(color_a, color_b, h) * (0.8 + 0.35 * n2) * (0.85 + 0.3 * n);
	col = mix(vec3(0.16, 0.13, 0.12), col, stone);
	float wet = smoothstep(0.6, 0.7, n);
	ALBEDO = col * (1.0 - 0.3 * wet);
	ROUGHNESS = mix(mix(0.95, 0.8, stone), 0.15, wet);
}
