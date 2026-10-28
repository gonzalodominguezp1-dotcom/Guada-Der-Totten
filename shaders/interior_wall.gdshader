// Pared interior del bar: zócalo rojo hasta 1 m y estuco rosado "esponjado"
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float dado_h = 1.0;
uniform vec3 upper : source_color = vec3(0.86, 0.62, 0.52);
uniform vec3 lower : source_color = vec3(0.55, 0.07, 0.06);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = abs(wnorm.x) > 0.5 ? wpos.zy : wpos.xy;
	float y = wpos.y;
	float sponge = texture(noise_tex, p * 0.9).r * 0.6 + texture(noise_tex, p * 3.1).r * 0.4;
	vec3 col = upper * (0.78 + 0.35 * sponge);
	col = mix(col, upper * vec3(1.05, 0.85, 0.8), smoothstep(0.55, 0.75, sponge) * 0.5);
	float d = step(y, dado_h);
	vec3 dado = lower * (0.85 + 0.25 * texture(noise_tex, p * 2.0).r);
	col = mix(col, dado, d);
	float rail = 1.0 - smoothstep(0.0, 0.03, abs(y - dado_h));
	col = mix(col, vec3(0.30, 0.16, 0.08), rail);
	col *= 1.0 - 0.25 * smoothstep(0.4, 0.0, y);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.4, d);
}
