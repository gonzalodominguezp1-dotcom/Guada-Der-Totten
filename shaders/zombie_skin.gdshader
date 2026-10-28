// Piel de zombie: pálida verdosa, venas, moratones y sangre
shader_type spatial;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.50, 0.52, 0.42);
uniform float blood = 0.4;
uniform float seed = 0.0;

varying vec3 opos;

void vertex() {
	opos = VERTEX;
}

void fragment() {
	vec3 p = opos * 3.0 + seed;
	float n1 = texture(noise_tex, p.xy * 0.7 + p.z * 0.3).r;
	float n2 = texture(noise_tex, p.yz * 1.9 + 3.1).r;
	float veins = smoothstep(0.03, 0.0, abs(texture(noise_tex, p.xz * 1.3 + p.y * 0.2).r - 0.5)) * 0.6;
	vec3 col = tint * (0.75 + 0.45 * n1);
	col = mix(col, vec3(0.30, 0.22, 0.30), smoothstep(0.62, 0.78, n2) * 0.6);     // moratones
	col = mix(col, vec3(0.18, 0.20, 0.25), veins);
	float b = smoothstep(1.0 - blood * 0.6, 1.0 - blood * 0.6 + 0.08, texture(noise_tex, p.xy * 0.5 + 7.0).r);
	col = mix(col, vec3(0.22, 0.02, 0.02), b);
	ALBEDO = col;
	ROUGHNESS = mix(0.75, 0.25, b);
}
