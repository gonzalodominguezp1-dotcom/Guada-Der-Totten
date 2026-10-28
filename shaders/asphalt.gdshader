// Asfalto viejo con grietas y charcos.
shader_type spatial;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, wpos.xz * 0.04).r;
	float f = texture(noise_tex, wpos.xz * 1.7).r;
	float crack = smoothstep(0.012, 0.0, abs(texture(noise_tex, wpos.xz * 0.11).r - 0.5));
	vec3 col = vec3(0.16, 0.16, 0.165) * (0.8 + 0.4 * f) * (0.9 + 0.2 * n);
	col = mix(col, vec3(0.025), crack * 0.8);
	float wet = smoothstep(0.64, 0.72, n);

	ALBEDO = col * (1.0 - 0.15 * wet);
	ROUGHNESS = mix(0.85, 0.12, wet);
	SPECULAR = 0.5;
}
