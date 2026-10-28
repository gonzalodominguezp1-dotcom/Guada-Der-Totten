// Teja árabe: filas de tejas curvas a lo largo del alero.
// UV.x = metros a lo largo del alero, UV.y = metros subiendo por el faldón.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = UV;
	float w = 0.23;
	float l = 0.38;
	float col_i = floor(p.x / w);
	float xf = fract(p.x / w);
	float row = floor((p.y + hash12(vec2(col_i, 0.0)) * 0.1) / l);
	float yf = fract((p.y + hash12(vec2(col_i, 0.0)) * 0.1) / l);
	float h = hash12(vec2(col_i, row));
	// curvatura de la teja (canal / cobija alternos)
	float curve = sin(xf * 3.14159);
	bool cover = mod(col_i, 2.0) > 0.5;
	float shade = cover ? 0.55 + 0.5 * curve : 0.45 + 0.25 * (1.0 - curve);
	// solape: sombra en el borde inferior de cada teja
	shade *= 0.65 + 0.35 * smoothstep(0.0, 0.18, yf);
	vec3 c = mix(vec3(0.55, 0.24, 0.13), vec3(0.70, 0.36, 0.20), h);
	c = mix(c, vec3(0.38, 0.22, 0.16), step(0.85, h));
	float n = texture(noise_tex, p * 0.15).r;
	float moss = smoothstep(0.6, 0.8, texture(noise_tex, p * 0.4 + 7.0).r);
	c = mix(c, vec3(0.22, 0.24, 0.16), moss * 0.6);
	c *= 0.75 + 0.4 * n;
	ALBEDO = c * shade;
	ROUGHNESS = 0.8;
}
