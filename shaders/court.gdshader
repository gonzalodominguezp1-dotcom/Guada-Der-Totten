// Pista de fútbol sala: suelo verde con líneas blancas (coordenadas del plano en metros)
shader_type spatial;

uniform vec2 court = vec2(40.0, 20.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

float line(float d, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.01, abs(d));
}

void fragment() {
	vec2 h = court * 0.5;
	vec2 p = lp;
	float w = 0.08;
	float l = 0.0;
	// banda exterior
	vec2 q = abs(p);
	if (q.x < h.x + w && q.y < h.y + w) {
		l = max(l, line(q.x - h.x, w) * step(q.y, h.y + w * 0.5));
		l = max(l, line(q.y - h.y, w) * step(q.x, h.x + w * 0.5));
	}
	l = max(l, line(p.x, w) * step(q.y, h.y));                       // medio campo
	l = max(l, line(length(p) - 3.0, w));                             // círculo central
	// áreas (semicírculos de 6 m)
	vec2 g = vec2(q.x - h.x, p.y);
	float dl = length(vec2(g.x, max(abs(g.y) - 1.6, 0.0)));
	l = max(l, line(dl - 6.0, w) * step(-h.x + 0.0, -q.x + h.x) * step(q.x, h.x));
	l = max(l, step(length(vec2(q.x - (h.x - 6.0), p.y)), 0.12));    // punto de penalti
	vec3 base = vec3(0.12, 0.42, 0.24);
	if (q.x > h.x || q.y > h.y) base = vec3(0.45, 0.20, 0.18);         // zona exterior granate
	float n = texture(noise_tex, lp * 0.08).r;
	vec3 col = base * (0.88 + 0.2 * n);
	col = mix(col, vec3(0.9, 0.9, 0.88), l);
	ALBEDO = col;
	ROUGHNESS = 0.35;
}
