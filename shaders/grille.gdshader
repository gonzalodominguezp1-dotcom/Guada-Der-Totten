// Reja blanca con cristal (ventanales de las terrazas del bar).
// Usa las coordenadas del propio QuadMesh (en metros).
shader_type spatial;
render_mode cull_disabled;

varying vec2 lp;

void vertex() {
	lp = VERTEX.xy;
}

void fragment() {
	// barrotes verticales cada 12 cm, travesaños cada 42 cm
	float vb = 1.0 - step(0.012, abs(fract(lp.x / 0.12) - 0.5) * 0.12);
	float hb = 1.0 - step(0.015, abs(fract((lp.y + 0.85) / 0.425) - 0.5) * 0.425);
	// motivo de "ces" de forja en la banda central
	vec2 c = vec2(fract(lp.x / 0.24) - 0.5, (lp.y - 0.0) / 0.24);
	float ring = (1.0 - step(0.012, abs(length(c * vec2(0.24, 0.24)) - 0.075))) * step(abs(lp.y), 0.1);
	float iron = clamp(vb + hb + ring, 0.0, 1.0);
	if (iron < 0.5) {
		ALBEDO = vec3(0.02, 0.025, 0.03);
		ROUGHNESS = 0.05;
		ALPHA = 0.3;
	} else {
		ALBEDO = vec3(0.82, 0.82, 0.79);
		ROUGHNESS = 0.5;
		ALPHA = 1.0;
	}
}
