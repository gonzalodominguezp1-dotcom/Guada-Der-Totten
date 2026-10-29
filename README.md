# Zombies del Pueblo — Guadalix de la Sierra

Zombies por rondas al estilo **World at War**, en el centro de Guadalix de la Sierra
(Avenida Alejandro Rubio, Calle Caño...). Empiezas dentro del **Bar Restaurante Chiqui**.
Hecho con **Godot 4.6 / 4.7** (versión normal, no .NET), renderizador Compatibilidad.

## Jugar

Abre Godot → Importar → `project.godot` → Importar y editar → **F5**.

| Acción | Tecla |
|---|---|
| Moverse / correr / saltar | W A S D / Shift / Espacio |
| Disparar / apuntar | Clic izquierdo / Clic derecho |
| Recargar | R |
| Cuchillo | V (o rueda del ratón pulsada) |
| Defecación Nuclear (Cañón de Zurraspa Dorado) | G |
| Usar / comprar / reparar | F (mantener para reparar ventanas) |
| Cambiar de arma | 1 / 2 / rueda del ratón |
| Soltar el ratón | Esc |
| Reiniciar al morir | Enter |

## Cómo funciona la partida

- Empiezas en el comedor del Bar Chiqui (Av. Alejandro Rubio 14) con la pistola (8/80) y 500 puntos.
- La primera zona es **todo el bar**, a la escala del edificio de OpenStreetMap (15 × 22 m):
  terraza delantera, comedor con barra, terraza trasera con la charanga y el pasillo lateral
  que une las dos terrazas.
- Los zombies llegan desde la calle y arrancan las tablas de las **6 ventanas del perímetro**.
  Mantén F en una ventana para volver a clavar tablas (+10 puntos).
- Dentro del bar:
  - **Quick Revive** (500): si caes, te levantas sola a los 9 s (hasta 3 compras).
  - **Escopeta de caza** en la pared (500; munición 250).
- **Verja del bar** (750) → Avenida Alejandro Rubio. Al abrirla, los zombies también salen por las calles.
- En la avenida: el bazar del nº 2 (esquina con Calle Caño), la Sala Groove (nº 6), y la
  Casa de la Juventud y el Hogar del Mayor con su plazuela, bancos y bolardos.
- Puntos: 10 por impacto, 60 por baja, 100 a la cabeza, 130 con cuchillo.
- Power-ups (verdes): Munición máxima, Muerte instantánea, Puntos x2 y Nuke.

## Zombies de Mixamo

Lee `assets/zombies/LEEME.txt`. Con 5 archivos de Mixamo los zombies pasan a tener
modelo y animaciones de verdad.

## Cambiar el mapa

```
python3 tools/osm_to_json.py data/map.osm data/map_sur.osm data/map_pueblo.osm data/town.json --crop=-175,60,262,560 --start "Chiqui" --tanatorio data/tanatorio.osm --backdrop=-1300,-450,900,980
```

`--crop` recorta la zona (metros desde el centro de la exportación), `--start` elige el inicio,
`--no-fill` quita las casas de relleno. El Bar Chiqui se detecta por su nombre en OSM y se
sustituye por el edificio hecho a mano.

## Estructura

```
scripts/main.gd             ambiente, controles, power-ups
scripts/town_generator.gd   calles, aceras, casas, tejados, postes, árboles, farolas, navegación
scripts/bar_chiqui.gd       el Bar Chiqui (zona de inicio, a escala)
scripts/landmarks.gd        Sala Groove nº 6 y plazuelas
scripts/interiors.gd        bazar chino, L'Antica, polideportivo, Ayuntamiento y plaza
scripts/zones.gd            zonas del mapa: tapias, escombros y puertas entre zonas
scripts/workbench.gd        mesa de trabajo del Cañón de Zurraspa (+ part_pickup.gd)
scripts/zurraspa_*.gd       charcos y avalancha del Cañón de Zurraspa
scripts/pack_a_punch.gd     máquina de mejora (en el tanatorio)
scripts/portal.gd           portal instituto <-> tanatorio
scripts/bus.gd              autobús 726 (avenida <-> instituto)
scripts/backdrop.gd         resto del pueblo de fondo, entre la niebla
scripts/tanatorio.gd        nivel del tanatorio (niebla, Pack-a-Punch)
scripts/player.gd           jugador, armas, cuchillo, compras, perks, Quick Revive
scripts/weapons.gd          datos y modelos de las armas
scripts/zombie.gd           zombie: ventanas, persecución, animación, Mixamo
scripts/barricade.gd        ventanas con tablas
scripts/buy_door.gd         puertas que se compran
scripts/perk_machine.gd     máquina de Quick Revive
scripts/wall_weapon.gd      armas de pared
scripts/powerup.gd          power-ups
scripts/round_manager.gd    rondas y aparición de zombies
scripts/hud.gd              interfaz
scripts/sfx.gd              sonidos (autoload)
shaders/                    fachadas (enlucido, granito, ladrillo), tejas, acera, interior...
tools/osm_to_json.py        OpenStreetMap → data/town.json
tools/make_sounds.py        genera los sonidos (sintetizados, sin audio de ningún juego)
tests/smoke_test.gd         prueba automática
tests/screenshots.gd        capturas desde cámaras definidas en tests/screenshot_plan.json
```
