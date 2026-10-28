# Guada Der Totten — notas para Claude

Juego de zombies estilo World at War en Guadalix de la Sierra, Godot 4.6+ (renderizador
Compatibilidad: el PC del usuario no aguanta Forward+). Todo el mundo se genera por código al
arrancar (no hay escenas .tscn salvo main.tscn). Comunicación con el usuario en español neutro.

- Mapa: `data/town.json`, generado desde `data/map.osm` con
  `python3 tools/osm_to_json.py data/map.osm data/town.json --crop=-110,55,115,235 --start "Chiqui"`.
- Bar Chiqui (zona de inicio): `scripts/bar_chiqui.gd`, coordenadas locales (+Z = avenida).
- Puertas comprables en capa 16 (excluida de la navmesh, no hace falta rehornear).
- Barricadas: capa 8 (bloquean jugador y zombies, no balas).
- Sonidos: `python3 tools/make_sounds.py assets/sounds` (sintetizados).
- Prueba: `godot --headless --path . --import` y luego
  `godot --headless --path . -s tests/smoke_test.gd --fixed-fps 60` → debe acabar en "RESULTADO: OK".
- Capturas: xvfb-run + `--rendering-method gl_compatibility`.
