// Fachadas procedurales inspiradas en las calles de Guadalix:
//   tipo 0: enlucido (crema, blanco, amarillo) con zócalo de granito
//   tipo 1: mampostería de granito (piedra gris-beige irregular)
//   tipo 2: ladrillo visto rojo-anaranjado con zócalo de piedra
//   tipo 3: piedra lisa sin ventanas (iglesia, torre, muros)
// UV  = (metros a lo largo de la pared, altura en metros)
// UV2 = (longitud de la pared o 0 si no lleva ventanas, altura del edificio)
// COLOR.rgb = color base del enlucido
// COLOR.a   = (tipo * 64 + estilo * 16 + semilla) / 255
//   estilo 0: clásico (contraventanas, balcones de forja)
//   estilo 1: moderno (aluminio y persianas enrollables)
//   estilo 2: bajos comerciales (en granito: aplacado hexagonal)
//   estilo 3: edificio público (ventanales con montantes)
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float floor_h = 3.0;
uniform float spacing = 3.4;

varying vec2 fuv;
varying vec2 dims;
varying vec4 vcol;

void vertex() {
	fuv = UV;
	dims = UV2;
	vcol = COLOR;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float rect(vec2 p, vec2 mn, vec2 mx) {
	vec2 s = step(mn, p) * step(p, mx);
	return s.x * s.y;
}

// Mampostería de granito: piedras irregulares (patrón de Voronoi) con
// juntas oscuras, moteado del granito y cada piedra con su tono.
vec2 hash22(vec2 p) {
	vec3 a = fract(p.xyx * vec3(0.1031, 0.1030, 0.0973));
	a += dot(a, a.yzx + 33.33);
	return fract((a.xx + a.yz) * a.zy);
}

vec3 granite(vec2 p, float seed, out float mortar_out) {
	vec2 q = p / vec2(0.30, 0.21) + seed * 3.7;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(cell + g) * 0.8 + 0.1;
			vec2 r = (g + o - f) * vec2(0.30, 0.21);
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = cell + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float edge = sqrt(d2) - sqrt(d1);
	float wob = (texture(noise_tex, p * 1.3 + seed).r - 0.5) * 0.012;
	float mortar = 1.0 - smoothstep(0.004, 0.014, edge + wob);
	mortar_out = mortar;
	float h = hash12(id);
	vec3 stone = mix(vec3(0.58, 0.54, 0.48), vec3(0.74, 0.69, 0.60), h);
	stone = mix(stone, vec3(0.58, 0.50, 0.40), step(0.8, h));        // piedras tostadas
	stone = mix(stone, vec3(0.48, 0.48, 0.47), step(0.92, h));       // piedras grises
	float speck = texture(noise_tex, p * 7.0 + id).r;
	stone *= 0.8 + 0.35 * speck;
	stone *= 0.8 + 0.25 * smoothstep(0.0, 0.05, edge);              // bombeo de cada piedra
	return mix(stone, vec3(0.40, 0.38, 0.35), mortar);
}

vec3 brick(vec2 p, float seed, out float mortar_out) {
	vec2 bp = p / vec2(0.25, 0.075);
	bp.x += mod(floor(bp.y), 2.0) * 0.5;
	vec2 bf = fract(bp);
	float mortar = 1.0 - rect(bf, vec2(0.04, 0.12), vec2(0.96, 0.88));
	mortar_out = mortar;
	float h = hash12(floor(bp) + seed);
	vec3 b = mix(vec3(0.62, 0.30, 0.18), vec3(0.75, 0.42, 0.26), h);
	b = mix(b, vec3(0.48, 0.24, 0.16), step(0.88, h));
	b *= 0.85 + 0.3 * texture(noise_tex, p * 3.0).r;
	return mix(b, vec3(0.72, 0.68, 0.60), mortar);
}

// Aplacado de piedra hexagonal (Hogar del Mayor)
vec3 hexstone(vec2 p, float seed, out float mortar_out) {
	vec2 sz = vec2(1.0, 1.7320508);
	vec2 q = p / 0.2;
	vec2 a = mod(q, sz) - sz * 0.5;
	vec2 b = mod(q - sz * 0.5, sz) - sz * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 id = floor(q - g + 0.5);
	vec2 ag = abs(g);
	float d = max(dot(ag, vec2(0.5, 0.8660254)), ag.x);
	float mortar = 1.0 - smoothstep(0.035, 0.07, 0.5 - d);
	mortar_out = mortar;
	float h = hash12(id + seed);
	vec3 st = mix(vec3(0.70, 0.67, 0.60), vec3(0.80, 0.77, 0.70), h);
	st = mix(st, vec3(0.62, 0.58, 0.50), step(0.85, h));
	st *= 0.82 + 0.3 * texture(noise_tex, p * 5.0 + id).r;
	st *= 0.85 + 0.2 * smoothstep(0.0, 0.25, 0.5 - d);
	return mix(st, vec3(0.42, 0.40, 0.37), mortar);
}

void fragment() {
	float len = dims.x;
	float h = dims.y;
	float code = floor(vcol.a * 255.0 + 0.5);
	float kind = floor(code / 64.0);
	float wstyle = floor(mod(code, 64.0) / 16.0);
	float seed = mod(code, 16.0) + 1.0;
	vec3 wall_tint = vcol.rgb;
	vec2 p = fuv;

	float n_big = texture(noise_tex, p * 0.035 + vec2(seed * 0.13, seed * 0.07)).r;
	float n_mid = texture(noise_tex, p * 0.21 + vec2(seed * 0.31, 0.0)).r;
	float n_fine = texture(noise_tex, p * 1.9 + vec2(0.0, seed * 0.19)).r;

	float mortar = 0.0;
	vec3 col;
	float plinth_h = 0.9;
	vec3 plinth_col = vec3(-1.0);
	if (kind < 0.5) {
		col = wall_tint * (0.84 + 0.24 * n_big) * (0.94 + 0.12 * n_fine);
		float chip = smoothstep(0.79, 0.82, texture(noise_tex, p * 0.07 + vec2(seed * 0.5)).r);
		float m2;
		col = mix(col, granite(p, seed, m2) * 0.9, chip);
		if (wstyle > 2.5) plinth_col = vec3(0.42, 0.17, 0.12);   // zócalo rojizo (edificio público)
		if (wstyle > 1.5 && wstyle < 2.5) plinth_col = vec3(0.36, 0.18, 0.14);
	} else if (kind < 1.5) {
		if (wstyle > 1.5 && wstyle < 2.5) {
			col = hexstone(p, seed, mortar);
		} else {
			col = granite(p * (wstyle > 0.5 && wstyle < 1.5 ? 0.7 : 1.0), seed, mortar);
			if (wstyle > 0.5 && wstyle < 1.5) {
				col *= vec3(1.18, 1.05, 0.80);    // laja de piedra cálida (L'Antica)
				plinth_col = vec3(0.82, 0.80, 0.76);
			}
		}
		plinth_h = wstyle > 0.5 && wstyle < 1.5 ? 0.9 : 0.0;
	} else if (kind < 2.5) {
		if (wstyle > 2.5) {
			// bloque de hormigón (polideportivo)
			vec2 bp = p / vec2(0.4, 0.2);
			bp.x += mod(floor(bp.y), 2.0) * 0.5;
			vec2 bf = fract(bp);
			mortar = 1.0 - rect(bf, vec2(0.02, 0.05), vec2(0.98, 0.95));
			col = vec3(0.72, 0.71, 0.68) * (0.88 + 0.18 * hash12(floor(bp) + seed)) * (0.9 + 0.15 * n_fine);
			col = mix(col, vec3(0.58, 0.57, 0.55), mortar);
			plinth_h = 1.2;
			plinth_col = vec3(0.86, 0.86, 0.84);
		} else {
			col = brick(p, seed, mortar);
			plinth_h = wstyle > 0.5 ? 0.5 : 1.1;
		}
	} else {
		if (wstyle > 0.5 && wstyle < 1.5) {
			// sillería de granito (Ayuntamiento)
			vec2 bp = p / vec2(0.62, 0.36);
			bp.x += mod(floor(bp.y), 2.0) * 0.5;
			vec2 bf = fract(bp);
			mortar = 1.0 - rect(bf, vec2(0.015, 0.03), vec2(0.985, 0.97));
			float hb = hash12(floor(bp) + seed);
			col = mix(vec3(0.70, 0.66, 0.58), vec3(0.80, 0.76, 0.68), hb) * (0.85 + 0.25 * texture(noise_tex, p * 4.0).r);
			col = mix(col, vec3(0.55, 0.52, 0.47), mortar);
		} else {
			float m3;
			col = granite(p * vec2(0.6, 1.4), seed, m3);
			col = mix(col, vec3(0.6, 0.57, 0.52) * (0.85 + 0.3 * n_fine), 0.35);
		}
		plinth_h = 0.0;
	}
	float rough = 0.92;
	vec3 emit = vec3(0.0);

	// Zócalo
	if (p.y < plinth_h) {
		if (plinth_col.r >= 0.0) {
			// baldosa de zócalo
			vec2 tq = fract(p / vec2(0.3, 0.2));
			float tg = 1.0 - rect(tq, vec2(0.03), vec2(0.97));
			col = mix(plinth_col * (0.8 + 0.35 * n_fine), vec3(0.25), tg * 0.6);
			rough = 0.4;
		} else {
			float m4;
			col = granite(p + vec2(0.0, 3.0), seed + 5.0, m4) * 0.82;
		}
	}

	// Suciedad: abajo, chorreones desde la cornisa, manchas de humedad
	float streak = texture(noise_tex, vec2(p.x * 0.45 + seed, 0.37)).r;
	float drip = smoothstep(0.55, 0.85, streak) * smoothstep(h - 4.0, h - 0.2, p.y);
	float grime = smoothstep(1.5, 0.0, p.y) * 0.35 + drip * 0.3 + smoothstep(0.62, 0.85, n_mid) * 0.12;
	col *= 1.0 - clamp(grime, 0.0, 0.6);

	// Alero / cornisa
	float cornice = step(h - 0.25, p.y);
	col = mix(col, col * 0.6, cornice);

	// Cables pegados a la fachada
	if (kind < 2.5) {
		float cable_y = 2.75 + 0.15 * sin(p.x * 0.25 + seed);
		float cable = 1.0 - smoothstep(0.008, 0.02, abs(p.y - cable_y));
		col = mix(col, vec3(0.03), cable * step(0.4, hash12(vec2(seed, 9.0))));
	}

	// Ventanas, balcones y puertas
	float sp = wstyle > 2.5 ? 2.9 : (wstyle > 0.5 && wstyle < 1.5 ? 3.0 : spacing);
	float nwin = floor(len / sp);
	if (len > 0.5 && nwin >= 1.0) {
		float off = (len - nwin * sp) * 0.5;
		float lx = p.x - off;
		float idx = floor(lx / sp);
		if (idx >= 0.0 && idx < nwin) {
			float cx = lx - (idx + 0.5) * sp;
			float fl = floor(p.y / floor_h);
			float fy = p.y - fl * floor_h;
			float fits = step((fl + 1.0) * floor_h, h + 0.2);
			float r = hash12(vec2(idx + seed * 7.0, fl + seed * 3.0));
			float pal = hash12(vec2(seed, 2.0));
			bool modern = ((wstyle > 0.5 && wstyle < 1.5) || (wstyle > 1.5 && wstyle < 2.5 && fl > 0.5)) && kind != 1.0 && kind < 2.5;
			bool public_b = wstyle > 2.5 && kind < 1.5;
			bool shop = wstyle > 1.5 && wstyle < 2.5 && kind != 1.0 && fl < 0.5;
			bool is_door = fl < 0.5 && r < 0.3 && !shop;
			bool balcony = fl > 0.5 && r > (modern ? 0.75 : 0.55) && !public_b;
			float hw = modern ? 0.65 : (public_b ? 1.2 : 0.5);
			vec2 mn = is_door ? vec2(-0.55, 0.0) : (balcony ? vec2(-hw, 0.05) : vec2(-hw, 0.9));
			vec2 mx = is_door ? vec2(0.55, 2.25) : vec2(hw, 2.3);
			if (shop) {
				mn = vec2(-sp * 0.5 + 0.3, 0.15);
				mx = vec2(sp * 0.5 - 0.3, 2.55);
			}
			vec2 q = vec2(cx, fy);
			float hole = rect(q, mn, mx) * fits;
			float frame = rect(q, mn - vec2(0.1, is_door || balcony || shop ? 0.0 : 0.1), mx + vec2(0.1, 0.12)) * fits;

			// Contraventanas (solo estilo clásico)
			bool shutters = !is_door && !modern && !public_b && !shop && wstyle < 0.5 && r > 0.25 && pal > 0.35 && fits > 0.5;
			if (shutters) {
				float sh = rect(q, vec2(mn.x - 0.55, mn.y), vec2(mn.x - 0.1, mx.y))
						+ rect(q, vec2(mx.x + 0.1, mn.y), vec2(mx.x + 0.55, mx.y));
				sh = clamp(sh, 0.0, 1.0);
				vec3 sh_col = pal > 0.7 ? vec3(0.12, 0.33, 0.18) : vec3(0.30, 0.18, 0.10);
				float slat = 0.86 + 0.14 * step(0.5, fract(fy * 7.0));
				col = mix(col, sh_col * slat * (0.8 + 0.3 * n_fine), sh);
				rough = mix(rough, 0.65, sh);
			}
			// Cajón de persiana enrollable (moderno)
			if (modern && !is_door && fits > 0.5) {
				float box = rect(q, vec2(mn.x - 0.06, mx.y + 0.02), vec2(mx.x + 0.06, mx.y + 0.24));
				col = mix(col, vec3(0.78, 0.74, 0.66) * (0.9 + 0.1 * n_fine), box);
			}

			vec3 frame_col = kind > 0.5 && kind < 1.5 ? vec3(0.68, 0.65, 0.58) : col * 1.1 + vec3(0.03);
			if (kind > 2.5) frame_col = vec3(0.80, 0.77, 0.70);
			if (kind > 1.5 && kind < 2.5) frame_col = vec3(0.70, 0.67, 0.60);
			if (shop) frame_col = vec3(0.10, 0.25, 0.60);   // marcos azules de tienda
			col = mix(col, frame_col, frame * (1.0 - hole));

			if (hole > 0.5) {
				if (is_door) {
					float plank = 0.8 + 0.2 * step(0.5, fract(cx * 4.0));
					col = vec3(0.24, 0.14, 0.08) * plank * (0.7 + 0.5 * n_fine);
					if (pal > 0.6) col = vec3(0.10, 0.20, 0.13) * plank;
					if (modern) col = vec3(0.30, 0.30, 0.32) * plank;   // puerta de aluminio
					rough = 0.7;
				} else if (shop) {
					// escaparate: cristal con carteles de colores y marco azul
					col = vec3(0.03, 0.035, 0.04);
					rough = 0.05;
					vec2 pc = floor(vec2(cx / 0.45, fy / 0.6));
					float ph = hash12(pc + seed * 5.0 + idx * 13.0);
					if (ph > 0.55 && fy > 0.5 && fy < 2.1) {
						vec3 poster = mix(vec3(0.9, 0.75, 0.2), vec3(0.2, 0.5, 0.85), hash12(pc + 3.0));
						poster = mix(poster, vec3(0.85, 0.2, 0.2), step(0.7, hash12(pc + 7.0)));
						col = poster * (0.7 + 0.3 * n_fine);
						emit = poster * 0.15;
						rough = 0.6;
					}
					float mull = step(abs(cx), 0.04) + step(abs(fy - 2.1), 0.04);
					if (mull > 0.5) {
						col = vec3(0.10, 0.25, 0.60);
						emit = vec3(0.0);
					}
				} else {
					col = vec3(0.015, 0.018, 0.022);
					rough = 0.04;
					if (r > 0.9 && fl < 1.5) {
						emit = vec3(1.0, 0.55, 0.22) * (0.8 + 0.6 * n_mid) * 1.3;
						col = vec3(0.35, 0.2, 0.1);
						rough = 0.3;
					}
					vec3 wood_col = vec3(0.28, 0.17, 0.10);
					float wood = max(step(abs(cx), 0.03), step(abs(fy - (mn.y + (mx.y - mn.y) * 0.6)), 0.03));
					if (modern) {
						wood_col = vec3(0.33, 0.34, 0.36);   // aluminio
						wood = step(abs(cx), 0.03);
						// persiana enrollable a media altura
						float blind_y = mix(mn.y + 0.2, mx.y, r);
						if (fy > blind_y) {
							col = vec3(0.74, 0.70, 0.62) * (0.9 + 0.1 * step(0.5, fract(fy * 22.0)));
							emit = vec3(0.0);
							rough = 0.7;
						}
					}
					if (public_b) {
						wood_col = vec3(0.85, 0.85, 0.82);
						wood = step(abs(fract(cx / 0.6) - 0.5), 0.025) + step(abs(fy - 1.75), 0.025);
					}
					wood = max(wood, 1.0 - rect(q, mn + vec2(0.05), mx - vec2(0.05)));
					if (wood > 0.5) {
						col = wood_col * (0.8 + 0.3 * n_fine);
						rough = 0.6;
						emit = vec3(0.0);
					}
					if (fl < 0.5 && (!modern || kind > 1.5)) {
						float bar = step(abs(fract(cx / 0.13) - 0.5), 0.1) + step(abs(fract((fy - 0.95) / 0.45) - 0.5), 0.05);
						if (bar > 0.5) {
							col = public_b ? vec3(0.35, 0.12, 0.08) : vec3(0.04);
							rough = 0.5;
							emit = vec3(0.0);
						}
					}
				}
			}
			if (balcony && fits > 0.5) {
				float slab = rect(q, vec2(mn.x - 0.25, -0.08), vec2(mx.x + 0.25, 0.06));
				col = mix(col, vec3(0.45, 0.42, 0.38), slab);
				float rail_zone = rect(q, vec2(mn.x - 0.2, 0.06), vec2(mx.x + 0.2, 1.05));
				float bars = step(abs(fract(cx / 0.11) - 0.5), 0.09);
				float rails = step(abs(fy - 1.02), 0.025) + step(abs(fy - 0.12), 0.02);
				float curl = modern ? 0.0 : step(abs(length(vec2(fract(cx / 0.22) - 0.5, (fy - 0.85) / 0.22 * 0.5)) - 0.25), 0.04) * step(0.75, fy);
				float iron = rail_zone * clamp(bars + rails + curl, 0.0, 1.0);
				col = mix(col, vec3(0.03), iron);
				rough = mix(rough, 0.45, iron);
			}
		}
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}
