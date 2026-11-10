# Guada Der Totten — notas para Claude

Juego de zombies estilo World at War en Guadalix de la Sierra, Godot 4.6+ (renderizador
Compatibilidad: el PC del usuario no aguanta Forward+). Todo el mundo se genera por código al
arrancar (no hay escenas .tscn salvo main.tscn). Comunicación con el usuario en español neutro.

- Mapa: `data/town.json`, generado desde `data/map.osm` con
  `python3 tools/osm_to_json.py data/map.osm data/map_sur.osm data/map_pueblo.osm data/town.json --crop=-175,60,262,560 --start "Chiqui" --tanatorio data/tanatorio.osm --backdrop=-1300,-450,900,1060 --dem <PNOA_MDT05...tif>`
  (el .tif del MDT del IGN no está en el repo; `--dem` genera `data/terrain.bin`, rejilla de 5 m
  con alturas relativas al Bar Chiqui, y `tanatorio.town_lights`).
- Relieve: `town.gy(p)` = altura del suelo. El recorte principal se queda plano (FLAT_MARGIN/
  FLAT_BLEND); islas (Segundo Guada) y fondo siguen el MDT; los prefabs fuera llevan "pads" planos.
- Bar Chiqui (zona de inicio = todo el bar, 15x22 m como en OSM): `scripts/bar_chiqui.gd`,
  coordenadas locales (+Z = avenida). Ventanas W1-W6 en el perímetro; se descartan solas si
  dan contra otra casa. Única salida: la verja (BuyDoor estilo "gate").
- Zonas (WaW): `scripts/zones.gd` cierra las calles jugables (`PLAYABLE`/`PLAYABLE_AREAS` del
  conversor) con tapias y escombros; entre zonas hay BuyDoor estilo "debris" (avenida → lantica,
  instituto, poli, plaza; L'Antica es parte de la avenida y se compra su puerta). Los spawns de
  calle solo se usan si su zona está abierta.
- Edificios con interior en `scripts/interiors.gd` (`shell()` = caja hueca con huecos de puerta):
  bazar chino (pieza "canon"), L'Antica (al entrar sale el Panzer, que suelta la "tele"),
  polideportivo, Ayuntamiento + mesa de trabajo (grupo "workbench") y decoración de la
  Plaza Consistorial. Arma maravilla "zurraspa" (diseño de un colega del usuario): ráfaga
  de chorros que hace resbalar y ensucia (`apply_slip`/`apply_dirty` en zombie.gd) y deja charcos
  (`scripts/zurraspa_puddle.gd`). Versión Pack-a-Punch "zurraspa_pap": avalancha
  (`scripts/zurraspa_wave.gd`) y Defecación Nuclear con [G]. Pack-a-Punch dentro del
  tanatorio (`scripts/pack_a_punch.gd`, mejora según la clave "pap" de weapons.gd).
- Zona "instituto": puerta en el callejón de la biblioteca (plaza trasera del poli) → Eras de
  Abajo → glorieta → patio vallado del IES (áreas con "fence": valla negra de barrotes y "gates"). Instituto
  y colegio en interiors.gd; en el vestíbulo del instituto está el portal (`scripts/portal.gd`,
  se enciende pagando y abre la zona "tanatorio").
- Tanatorio: nivel aparte (`scripts/tanatorio.gd`, datos en la clave "tanatorio" de town.json)
  a ~2,5 km al este del pueblo, con su propia navmesh. main.gd cambia niebla/luz y oculta el
  pueblo al entrar. Al este, mirador con pretil bajo y el terreno cae al valle: luces del pueblo
  (MultiMesh billboard sin niebla, `_town_lights`). El cementerio NO se modela ni se puede visitar (petición del usuario).
- Resto del pueblo de fondo (`scripts/backdrop.gd`, clave "backdrop"): casas y calles sencillas
  fuera del recorte, fusionadas por bloques de 100 m, sin colisión, visibility_range 300 m.
- Autobús 726 (`scripts/bus.gd`): circular con 3 paradas (BUS_STOPS del conversor: Bar Chiqui,
  Instituto, Segundo Guada). Ruta = BUS_ROUTE a mano (Chiqui→instituto) + camino más corto por
  OSM (→ Segundo Guada → BUS_RETURN_VIA → avenida por el oeste → Chiqui). En marcha el viajero
  queda quieto (`player.riding_bus`) y `_carry` le aplica el movimiento del bus.
  Barreras "SOLO BUS" (Bus.make_gate) donde la ruta corta tapones/escombros. Llegar abre la zona.
- Segundo Guada = "island" de town.json (zona "segundo"): chalets de ladrillo retranqueados
  con muro de jardín (zones._garden_wall: zócalo + panel marrón opaco), casa Calle Artes 22 (prefab "artes22", ventana del
  pepino `scripts/ee_window.gd`) y portal al skatepark. `town.in_detail(p)`/`island_at(p)`.
  La navmesh grande tarda unos segundos en estar lista (los tests esperan a `_main_nav_ready`).
- Skatepark (`scripts/skatepark.gd`): nivel aparte; según se entra, a la derecha en línea quarter,
  meseta y plano inclinado; a la izquierda barandilla y olas (piezas extruidas con `_profile`); "el colega" (zombie special "npc", cara en
  assets/npc/cara.png) se queda quieto y con [F] le quitas el "calzoncillo"; con el pepino aparece la estatua del culo:
  10 muertes cerca con "zurraspa_pap" y luego [F] para meterle el pepino. Especiales (panzer, npc)
  no cuentan en la ronda (round_manager.spawn_special); zombies lejos/atascados reaparecen.
- Edificios a mano sin interior (Sala Groove nº 6) en `scripts/landmarks.gd`; su posición
  aproximada está en `EXTRA_PREFABS` de `tools/osm_to_json.py`. Plazuelas (acera ensanchada)
  delante de Casa de la Juventud y Hogar del Mayor.
- Fachadas: `shaders/facade.gdshader`, COLOR.a = tipo*64 + estilo*16 + semilla
  (tipo: enlucido/granito/ladrillo/piedra; estilo: clásico/moderno/tiendas o hexagonal/público).
- Armas en `scripts/weapons.gd`: "sight_y" y "ads" alinean la mira al apuntar. Armas WaW (kar98,
  mp40, thompson, stg44; mg42 y raygun solo en la caja) con modelo genérico `_longgun` (clave
  "model"). `data(id)` da a las normales Pack-a-Punch automático "<id>_pap" (camuflaje `_camo`).
- Reparto (`scripts/loadout.gd`, tabla SPOTS en coordenadas locales de cada prefab/nivel):
  armas de pared (tablón con patas si no hay pared), caja mágica (`scripts/mystery_box.gd`,
  950, osito y se mueve; empieza en el bar) y perks: Quick Revive (bar), Speed Cola (L'Antica),
  Juggernog (poli), Double Tap (Plaza Consistorial). Prueba: `tests/loadout_test.gd`.
- Coches aparcados y contenedores: `scripts/street_props.gd` (MultiMesh, colisión con cajas; nada en
  la ruta del bus, cruces, puertas de zona ni plazas).
- OJO: `Landmarks._box(parent, POS, SIZE, mat, colisión)` — primero la posición y luego el tamaño.
- Vallas en MultiMesh: usar `basis.scaled_local()` (con `scaled()` la escala va en ejes globales y
  las piezas salen torcidas/cruzadas).
- Puertas comprables en capa 16 (excluida de la navmesh, no hace falta rehornear).
- Barricadas: capa 8 (bloquean jugador y zombies, no balas).
- Sonidos: `python3 tools/make_sounds.py assets/sounds` (sintetizados).
- Prueba: `godot --headless --path . --import` y luego
  `godot --headless --path . -s tests/smoke_test.gd --fixed-fps 60` → debe acabar en "RESULTADO: OK"
  (tarda bastantes minutos). También `tests/loadout_test.gd` y `tests/bus_ride.gd`.
- Capturas: xvfb-run + `--rendering-method gl_compatibility`.
