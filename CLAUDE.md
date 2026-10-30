# Guada Der Totten — notas para Claude

Juego de zombies estilo World at War en Guadalix de la Sierra, Godot 4.6+ (renderizador
Compatibilidad: el PC del usuario no aguanta Forward+). Todo el mundo se genera por código al
arrancar (no hay escenas .tscn salvo main.tscn). Comunicación con el usuario en español neutro.

- Mapa: `data/town.json`, generado desde `data/map.osm` con
  `python3 tools/osm_to_json.py data/map.osm data/map_sur.osm data/map_pueblo.osm data/town.json --crop=-175,60,262,560 --start "Chiqui" --tanatorio data/tanatorio.osm --backdrop=-1300,-450,900,980`.
- Bar Chiqui (zona de inicio = todo el bar, 15x22 m como en OSM): `scripts/bar_chiqui.gd`,
  coordenadas locales (+Z = avenida). Ventanas W1-W6 en el perímetro; se descartan solas si
  dan contra otra casa. Única salida: la verja (BuyDoor estilo "gate").
- Zonas (WaW): `scripts/zones.gd` cierra las calles jugables (`PLAYABLE`/`PLAYABLE_AREAS` del
  conversor) con tapias y escombros; entre zonas hay BuyDoor estilo "debris" (avenida → lantica,
  poli, plaza). Los spawns de calle solo se usan si su zona está abierta.
- Edificios con interior en `scripts/interiors.gd` (`shell()` = caja hueca con huecos de puerta):
  bazar chino (pieza "canon"), L'Antica (pieza "tele"), polideportivo (garita bajo las gradas,
  pieza "calzoncillo"), Ayuntamiento + mesa de trabajo (grupo "workbench") y decoración de la
  Plaza Consistorial. Arma maravilla "zurraspa" (diseño de un colega del usuario): ráfaga
  de chorros que hace resbalar y ensucia (`apply_slip`/`apply_dirty` en zombie.gd) y deja charcos
  (`scripts/zurraspa_puddle.gd`). Versión Pack-a-Punch "zurraspa_pap": avalancha
  (`scripts/zurraspa_wave.gd`) y Defecación Nuclear con [G]. Pack-a-Punch dentro del
  tanatorio (`scripts/pack_a_punch.gd`, mejora según la clave "pap" de weapons.gd).
- Zona "instituto": puerta en el callejón de la biblioteca (plaza trasera del poli) → Eras de
  Abajo → glorieta → patio vallado del IES (áreas con "fence": valla verde y "gates"). Instituto
  y colegio en interiors.gd; en el vestíbulo del instituto está el portal (`scripts/portal.gd`,
  se enciende pagando y abre la zona "tanatorio").
- Tanatorio: nivel aparte (`scripts/tanatorio.gd`, datos en la clave "tanatorio" de town.json)
  a ~700 m al este del pueblo, con su propia navmesh. main.gd cambia niebla/luz y oculta el
  pueblo al entrar. El cementerio NO se modela ni se puede visitar (petición del usuario).
- Resto del pueblo de fondo (`scripts/backdrop.gd`, clave "backdrop"): casas y calles sencillas
  fuera del recorte, fusionadas por bloques de 100 m, sin colisión, visibility_range 300 m.
- Autobús 726 (`scripts/bus.gd`): línea circular con 5 paradas (BUS_STOPS del conversor:
  avenida, instituto, suroeste/Calle Hadar, norte/Calle Encinas, este/Av. Virgen del Espinar).
  Ruta = BUS_ROUTE a mano (avenida→instituto) + camino más corto por OSM entre paradas.
  AnimatableBody3D en capa 16; en marcha el viajero solo choca con el bus (collision_mask=16) y
  atraviesa tapias/barreras con él. Donde la ruta corta tapones o escombros se pone una barrera
  "SOLO BUS" (Bus.make_gate). Llegar a una parada abre su zona.
- Paradas nuevas = "islands" de town.json: recuadros con detalle fuera del recorte principal
  (calles jugables, casas, suelo, límites y su propia navmesh horneada con NavigationServer3D).
  `town.in_detail(p)` sustituye a `bounds.has_point` en zonas, farolas y spawns.
  La navmesh grande tarda unos segundos en estar lista (los tests esperan a `_main_nav_ready`).
- Edificios a mano sin interior (Sala Groove nº 6) en `scripts/landmarks.gd`; su posición
  aproximada está en `EXTRA_PREFABS` de `tools/osm_to_json.py`. Plazuelas (acera ensanchada)
  delante de Casa de la Juventud y Hogar del Mayor.
- Fachadas: `shaders/facade.gdshader`, COLOR.a = tipo*64 + estilo*16 + semilla
  (tipo: enlucido/granito/ladrillo/piedra; estilo: clásico/moderno/tiendas o hexagonal/público).
- Armas en `scripts/weapons.gd`: "sight_y" y "ads" alinean la mira al apuntar.
- Puertas comprables en capa 16 (excluida de la navmesh, no hace falta rehornear).
- Barricadas: capa 8 (bloquean jugador y zombies, no balas).
- Sonidos: `python3 tools/make_sounds.py assets/sounds` (sintetizados).
- Prueba: `godot --headless --path . --import` y luego
  `godot --headless --path . -s tests/smoke_test.gd --fixed-fps 60` → debe acabar en "RESULTADO: OK".
- Capturas: xvfb-run + `--rendering-method gl_compatibility`.
