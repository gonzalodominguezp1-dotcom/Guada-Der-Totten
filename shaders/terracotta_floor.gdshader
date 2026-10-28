// Baldosa de barro (suelo del bar)
shader_type spatial;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile = 0.33;
uniform vec3 base : source_color = vec3(0.58, 0.30, 0.18);

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
	vec2 p = wpos.xz / tile;
	vec2 c = floor(p);
	vec2 f = fract(p);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * tile;
	float grout = 1.0 - smoothstep(0.003, 0.009, edge);
	float h = hash12(c);
	vec3 col = base * (0.8 + 0.4 * h) * (0.85 + 0.3 * texture(noise_tex, wpos.xz * 0.8).r);
	col = mix(col, vec3(0.30, 0.27, 0.24), grout);
	float dirt = texture(noise_tex, wpos.xz * 0.12).r;
	col *= 0.8 + 0.25 * dirt;
	ALBEDO = col;
	ROUGHNESS = mix(0.35, 0.9, grout);
}
