#!/usr/bin/env python3
"""
Convierte un archivo .osm exportado desde openstreetmap.org en data/town.json,
que es lo que lee el juego para construir el pueblo.

Uso básico:
    python3 tools/osm_to_json.py mi_pueblo.osm data/town.json

Opciones:
    --crop X0,Z0,X1,Z1   recorta la zona jugable (metros desde el centro de la
                         exportación; X hacia el este, Z hacia el sur)
    --start "Nombre"     lugar donde aparece el jugador (una plaza o edificio
                         con nombre en OSM). Por defecto, la primera plaza.
    --no-fill            no rellenar con casas las calles sin edificios en OSM
    --seed N             semilla para las casas de relleno

En muchos pueblos OSM solo tiene dibujados algunos edificios. Por defecto el
script rellena las fachadas vacías de las calles con casas adosadas, dejando
libres las calles, las plazas y los edificios reales.

Coordenadas de salida: x = metros al este, z = metros al sur (en Godot -Z es
el norte), con el origen en el centro de la zona jugable.
Solo usa la librería estándar de Python.
"""
import argparse
import json
import math
import random
import re
import xml.etree.ElementTree as ET

HIGHWAY_WIDTHS = {
    "primary": 9.0, "secondary": 8.0, "tertiary": 7.0, "residential": 6.0,
    "unclassified": 6.0, "living_street": 5.0, "service": 4.0, "pedestrian": 5.0,
    "track": 3.5, "footway": 2.5, "path": 2.0, "steps": 2.0,
}
NO_FILL_TYPES = {"track", "path", "footway", "steps", "service"}
TALL_BUILDINGS = {"church": 13.0, "cathedral": 18.0, "chapel": 8.0}
POI_KEYS = ("amenity", "shop", "tourism", "leisure", "historic")


# ------------------------------------------------------------------ geometría

def poly_area(p):
    return 0.5 * sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))


def centroid(p):
    return (sum(q[0] for q in p) / len(p), sum(q[1] for q in p) / len(p))


def point_in_poly(pt, poly):
    x, y = pt
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def _orient(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def segs_intersect(a, b, c, d):
    d1, d2 = _orient(c, d, a), _orient(c, d, b)
    d3, d4 = _orient(a, b, c), _orient(a, b, d)
    return (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0)


def pt_seg_dist(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    L = ax * ax + ay * ay
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / L))
    return math.hypot(p[0] - a[0] - ax * t, p[1] - a[1] - ay * t)


def seg_seg_dist(a, b, c, d):
    if segs_intersect(a, b, c, d):
        return 0.0
    return min(pt_seg_dist(a, c, d), pt_seg_dist(b, c, d), pt_seg_dist(c, a, b), pt_seg_dist(d, a, b))


def poly_seg_dist(poly, a, b):
    if point_in_poly(a, poly) or point_in_poly(b, poly):
        return 0.0
    return min(seg_seg_dist(poly[i], poly[(i + 1) % len(poly)], a, b) for i in range(len(poly)))


def polys_overlap(p, q):
    if any(point_in_poly(v, q) for v in p) or any(point_in_poly(v, p) for v in q):
        return True
    for i in range(len(p)):
        for j in range(len(q)):
            if segs_intersect(p[i], p[(i + 1) % len(p)], q[j], q[(j + 1) % len(q)]):
                return True
    return False


def bbox(p, pad=0.0):
    xs = [v[0] for v in p]
    ys = [v[1] for v in p]
    return (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)


def bbox_hit(a, b):
    return a[0] <= b[2] and b[0] <= a[2] and a[1] <= b[3] and b[1] <= a[3]


def clip_polyline(pts, rect):
    """Recorta una polilínea a un rectángulo (Liang-Barsky por segmento)."""
    x0, z0, x1, z1 = rect
    out, cur = [], []
    for i in range(len(pts) - 1):
        (ax, az), (bx, bz) = pts[i], pts[i + 1]
        dx, dz = bx - ax, bz - az
        t0, t1, ok = 0.0, 1.0, True
        for p, q in ((-dx, ax - x0), (dx, x1 - ax), (-dz, az - z0), (dz, z1 - az)):
            if p == 0:
                if q < 0:
                    ok = False
                    break
            else:
                r = q / p
                if p < 0:
                    t0 = max(t0, r)
                else:
                    t1 = min(t1, r)
        if not ok or t0 > t1:
            if len(cur) >= 2:
                out.append(cur)
            cur = []
            continue
        a = [ax + dx * t0, az + dz * t0]
        b = [ax + dx * t1, az + dz * t1]
        if not cur:
            cur = [a]
        elif math.dist(cur[-1], a) > 1e-6:
            if len(cur) >= 2:
                out.append(cur)
            cur = [a]
        cur.append(b)
        if t1 < 1.0:
            if len(cur) >= 2:
                out.append(cur)
            cur = []
    if len(cur) >= 2:
        out.append(cur)
    return out


# ------------------------------------------------------------------ OSM

def parse_height(tags, way_id):
    h = tags.get("height")
    if h:
        m = re.match(r"[\d.]+", h.replace(",", "."))
        if m:
            return float(m.group(0))
    levels = tags.get("building:levels")
    if levels:
        m = re.match(r"\d+", levels)
        if m:
            return int(m.group(0)) * 3.1 + 0.4
    b = tags.get("building", "")
    if b in TALL_BUILDINGS:
        return TALL_BUILDINGS[b]
    if b in ("garage", "shed", "hut", "kiosk"):
        return 3.0
    return (1, 2, 2, 2, 3, 3)[int(way_id) % 6] * 3.1 + 0.4


def load_osm(src):
    root = ET.parse(src).getroot()
    nodes, node_tags = {}, {}
    for n in root.iter("node"):
        nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")))
        tags = {t.get("k"): t.get("v") for t in n.findall("tag")}
        if tags:
            node_tags[n.get("id")] = tags
    b = root.find("bounds")
    if b is not None:
        bb = (float(b.get("minlat")), float(b.get("minlon")), float(b.get("maxlat")), float(b.get("maxlon")))
    else:
        lats = [p[0] for p in nodes.values()]
        lons = [p[1] for p in nodes.values()]
        bb = (min(lats), min(lons), max(lats), max(lons))
    ways = []
    for way in root.iter("way"):
        tags = {t.get("k"): t.get("v") for t in way.findall("tag")}
        refs = [nd.get("ref") for nd in way.findall("nd")]
        ways.append((way.get("id"), tags, refs))
    return nodes, node_tags, bb, ways


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--crop", help="X0,Z0,X1,Z1 en metros desde el centro de la exportación")
    ap.add_argument("--start", default="", help="nombre del lugar de inicio")
    ap.add_argument("--no-fill", action="store_true")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    nodes, node_tags, (minlat, minlon, maxlat, maxlon), ways = load_osm(args.src)
    lat0, lon0 = (minlat + maxlat) / 2, (minlon + maxlon) / 2
    kx = 111320.0 * math.cos(math.radians(lat0))
    kz = 110540.0

    def proj(lat, lon):
        return [(lon - lon0) * kx, -(lat - lat0) * kz]

    full = (proj(maxlat, minlon)[0], proj(maxlat, minlon)[1], proj(minlat, maxlon)[0], proj(minlat, maxlon)[1])
    crop = tuple(float(v) for v in args.crop.split(",")) if args.crop else full
    ox, oz = (crop[0] + crop[2]) / 2, (crop[1] + crop[3]) / 2

    def rel(p):
        return [round(p[0] - ox, 2), round(p[1] - oz, 2)]

    def in_crop(p, margin=0.0):
        return crop[0] - margin <= p[0] <= crop[2] + margin and crop[1] - margin <= p[1] <= crop[3] + margin

    buildings, streets, pois, plazas, prefabs = [], [], [], [], []
    for wid, tags, refs in ways:
        pts = [proj(*nodes[r]) for r in refs if r in nodes]
        if len(pts) < 2:
            continue
        closed = len(refs) >= 4 and refs[0] == refs[-1]
        if "building" in tags and closed:
            poly = pts[:-1]
            c = centroid(poly)
            if not in_crop(c):
                continue
            name = tags.get("name", "")
            btype = tags.get("building", "yes")
            if "chiqui" in name.lower():
                prefabs.append({"prefab": "bar_chiqui", "osm_points": [rel(p) for p in poly]})
                pois.append({"name": name, "type": "bar", "pos": rel(c)})
                continue
            if tags.get("amenity") == "place_of_worship" and btype == "yes":
                btype = "church"
            buildings.append({"points": [rel(p) for p in poly],
                              "height": round(parse_height(dict(tags, building=btype), wid), 2),
                              "name": name, "type": btype})
            if name or any(k in tags for k in POI_KEYS):
                pois.append({"name": name, "type": next((tags[k] for k in POI_KEYS if k in tags), btype),
                             "pos": rel(c)})
        elif tags.get("highway") in HIGHWAY_WIDTHS and not (closed and tags.get("area") == "yes"):
            for part in clip_polyline(pts, (crop[0] - 30, crop[1] - 30, crop[2] + 30, crop[3] + 30)):
                streets.append({"points": [rel(p) for p in part], "width": HIGHWAY_WIDTHS[tags["highway"]],
                                "name": tags.get("name", ""), "type": tags["highway"]})
        elif tags.get("place") == "square" or (closed and tags.get("highway") == "pedestrian"):
            poly = pts[:-1] if closed else pts
            c = centroid(poly)
            if in_crop(c):
                plazas.append({"name": tags.get("name", ""), "points": [rel(p) for p in poly]})
                pois.append({"name": tags.get("name", ""), "type": "square", "pos": rel(c)})

    for nid, tags in node_tags.items():
        if nid in nodes and (any(k in tags for k in POI_KEYS)):
            p = proj(*nodes[nid])
            if in_crop(p):
                t = next(tags[k] for k in POI_KEYS if k in tags)
                if t == "drinking_water":
                    t = "fountain"
                pois.append({"name": tags.get("name", ""), "type": t, "pos": rel(p)})

    # Torre de la iglesia: en el extremo oeste de la nave (lo habitual en
    # las iglesias españolas), si OSM no la tiene dibujada aparte.
    for b in list(buildings):
        if b["type"] in ("church", "cathedral", "chapel") and b["type"] != "chapel":
            poly = b["points"]
            west = min(poly, key=lambda v: v[0])
            east = max(poly, key=lambda v: v[0])
            c = centroid(poly)
            d = [c[0] - west[0], c[1] - west[1]]
            L = math.hypot(*d) or 1.0
            tc = [west[0] + d[0] / L * 3.5, west[1] + d[1] / L * 3.5]
            s = 3.0
            buildings.append({"points": [[tc[0] - s, tc[1] - s], [tc[0] + s, tc[1] - s],
                                         [tc[0] + s, tc[1] + s], [tc[0] - s, tc[1] + s]],
                              "height": round(b["height"] + 11.0, 2),
                              "name": "Torre de la iglesia", "type": "tower"})

    fixed = []
    for ex in EXTRA_PREFABS:
        if "front" in ex:
            f = rel(ex["front"])
            if crop[0] - ox <= f[0] <= crop[2] - ox and crop[1] - oz <= f[1] <= crop[3] - oz:
                pf = {"prefab": ex["prefab"]}
                set_fixed(pf, f, ex["fwd"])
                fixed.append(pf)
            continue
        a = rel(ex["anchor"])
        if crop[0] - ox <= a[0] <= crop[2] - ox and crop[1] - oz <= a[1] <= crop[3] - oz:
            prefabs.append({"prefab": ex["prefab"], "street": ex["street"],
                            "osm_points": [[a[0] - 1, a[1] - 1], [a[0] + 1, a[1] - 1], [a[0] + 1, a[1] + 1], [a[0] - 1, a[1] + 1]]})
    for pf in prefabs:
        place_prefab(pf, streets)
    prefabs.extend(fixed)
    for pf in prefabs:
        buildings[:] = [b for b in buildings
                        if not polys_overlap(b["points"], pf["footprint"])]

    plazuelas = make_plazuelas(buildings, streets)

    # zonas jugables
    playable = []
    for pl in PLAYABLE:
        for wid, tags, refs in ways:
            if tags.get("name") != pl["street"] or tags.get("highway") not in HIGHWAY_WIDTHS:
                continue
            pts = [proj(*nodes[r]) for r in refs if r in nodes]
            if len(pts) < 2:
                continue
            r = pl["rect"]
            for part in clip_polyline(pts, (r[0], r[1], r[2], r[3])):
                part = clip_polyline(part, (crop[0] - 5, crop[1] - 5, crop[2] + 5, crop[3] + 5))
                for pp in part:
                    playable.append({"zone": pl["zone"], "name": pl["street"],
                                     "points": [rel(p) for p in pp], "width": HIGHWAY_WIDTHS[tags["highway"]]})
    areas = []
    for pz in plazuelas:
        areas.append({"zone": "avenida", "name": pz["name"], "points": pz["points"]})
    for a in PLAYABLE_AREAS:
        areas.append({"zone": a["zone"], "name": a["name"], "points": [rel(p) for p in a["points"]]})
    for pl in plazas:
        if pl["name"] in SQUARE_ZONES:
            areas.append({"zone": SQUARE_ZONES[pl["name"]], "name": pl["name"], "points": pl["points"]})
    zone_doors = []
    for zd in ZONE_DOORS:
        for wid, tags, refs in ways:
            if tags.get("name") != zd["street"]:
                continue
            pts = [proj(*nodes[r]) for r in refs if r in nodes]
            for i in range(len(pts) - 1):
                a_, b_ = pts[i], pts[i + 1]
                k = zd["axis"]
                lo, hi = sorted((a_[k], b_[k]))
                if lo <= zd["value"] <= hi and hi > lo:
                    t = (zd["value"] - a_[k]) / (b_[k] - a_[k])
                    p = [a_[0] + (b_[0] - a_[0]) * t, a_[1] + (b_[1] - a_[1]) * t]
                    L = math.dist(a_, b_)
                    zone_doors.append({"zone": zd["zone"], "cost": zd["cost"], "label": zd["label"],
                                       "pos": rel(p), "dir": [round((b_[0] - a_[0]) / L, 4), round((b_[1] - a_[1]) / L, 4)],
                                       "width": HIGHWAY_WIDTHS.get(tags.get("highway"), 6.0)})
                    break
            if any(d["label"] == zd["label"] for d in zone_doors):
                break

    real_count = len(buildings)
    if not args.no_fill:
        fill_houses(buildings, streets, plazas, pois, (crop[0] - ox, crop[1] - oz, crop[2] - ox, crop[3] - oz), rng,
                    extra_obstacles=[pf["footprint"] for pf in prefabs] + [a["points"] for a in areas])

    start = None
    want = args.start.lower()
    for p in pois:
        if want and want in p["name"].lower():
            start = p
            break
    if start is None:
        squares = [p for p in pois if p["type"] == "square"]
        start = squares[0] if squares else None
    if start is None and prefabs:
        start = {"name": "Bar Chiqui", "pos": prefabs[0]["pos"]}
    if start:
        pois.append({"name": "Inicio (" + start["name"] + ")", "type": "start", "pos": start["pos"]})

    half_w, half_h = (crop[2] - crop[0]) / 2, (crop[3] - crop[1]) / 2
    out = {
        "origin_latlon": [lat0, lon0],
        "crop_offset": [round(ox, 2), round(oz, 2)],
        "bounds": [-round(half_w, 2), -round(half_h, 2), round(half_w, 2), round(half_h, 2)],
        "buildings": buildings,
        "streets": streets,
        "plazas": plazas,
        "prefabs": prefabs,
        "plazuelas": plazuelas,
        "playable": playable,
        "areas": areas,
        "zone_doors": zone_doors,
        "pois": pois,
    }
    with open(args.dst, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"{real_count} edificios de OSM + {len(buildings) - real_count} casas de relleno, "
          f"{len(streets)} tramos de calle, {len(plazas)} plazas, {len(pois)} lugares")
    print(f"Zona jugable: {crop[2] - crop[0]:.0f} x {crop[3] - crop[1]:.0f} m"
          + (f", inicio en {start['name']}" if start else "") + f"  ->  {args.dst}")


PREFAB_SIZE = {"bar_chiqui": (15.0, 22.0), "bazar": (14.0, 11.0), "sala_groove": (13.0, 9.0),
               "lantica": (16.0, 10.0), "polideportivo": (46.0, 30.0), "ayuntamiento": (16.0, 12.4)}  # ancho, fondo (m)

# Edificios hechos a mano que no están en OSM: posición aproximada (x, z en
# metros desde el centro de la exportación) y calle a la que dan.
# Av. Alejandro Rubio 2 (bazar, esquina con Calle Caño) y 6 (Sala Groove).
EXTRA_PREFABS = [
    {"prefab": "bazar", "anchor": [49.5, 118.0], "street": "Alejandro Rubio"},
    {"prefab": "sala_groove", "anchor": [28.0, 121.0], "street": "Alejandro Rubio"},
    # L'Antica: al oeste del aparcamiento, en la acera sur de la avenida
    {"prefab": "lantica", "anchor": [-136.0, 158.0], "street": "Alejandro Rubio"},
    # Polideportivo: fachada norte (puertas amarillas) mirando a la plaza trasera
    {"prefab": "polideportivo", "front": [-40.3, 191.2], "fwd": [-0.168, -0.986]},
    # Ayuntamiento: sustituye al edificio de OSM, fachada a la Plaza Consistorial
    {"prefab": "ayuntamiento", "front": [231.4, 129.7], "fwd": [-0.248, 0.969]},
]

# Zonas jugables (coordenadas de la exportación). Todo lo demás queda fuera,
# cerrado con tapias y escombros.
PLAYABLE = [
    {"zone": "avenida", "street": "Avenida Alejandro Rubio", "rect": [-95, -1e9, 61.5, 1e9]},
    {"zone": "lantica", "street": "Avenida Alejandro Rubio", "rect": [-1e9, -1e9, -95, 1e9]},
    {"zone": "poli", "street": "Calle Nogal", "rect": [-1e9, 132, 1e9, 172]},
    {"zone": "plaza", "street": "Calle Pozo", "rect": [-1e9, -1e9, 1e9, 1e9]},
    {"zone": "plaza", "street": "Plaza Libertad", "rect": [-1e9, -1e9, 1e9, 1e9]},
    {"zone": "plaza", "street": "Calle Egido", "rect": [-1e9, -1e9, 1e9, 1e9]},
]
PLAYABLE_AREAS = [
    {"zone": "poli", "name": "Plaza trasera",
     "points": [[-60, 166], [-3, 162], [-3, 186.5], [-17, 187.5], [-61, 194.5]]},
]
SQUARE_ZONES = {"Plaza Consistorial": "plaza", "Plaza Libertad": "plaza"}
# Puertas de zona (escombros que se compran): calle, eje y valor donde cortan
ZONE_DOORS = [
    {"zone": "lantica", "street": "Avenida Alejandro Rubio", "axis": 0, "value": -96.0, "cost": 1000,
     "label": "despejar el paso hacia L'Antica"},
    {"zone": "poli", "street": "Calle Nogal", "axis": 1, "value": 141.0, "cost": 1000,
     "label": "despejar la Calle Nogal (polideportivo)"},
    {"zone": "plaza", "street": "Calle Pozo", "axis": 0, "value": 73.0, "cost": 1250,
     "label": "despejar la Calle Pozo (plaza del Ayuntamiento)"},
]


def set_fixed(pf, front, fwd):
    """Prefab con posición y orientación fijas (frente y dirección hacia fuera)."""
    w, d = PREFAB_SIZE[pf["prefab"]]
    L = math.hypot(*fwd)
    fwd = (fwd[0] / L, fwd[1] / L)
    right = (-fwd[1], fwd[0])
    pf["pos"] = [round(front[0], 2), round(front[1], 2)]
    pf["yaw"] = round(math.atan2(fwd[0], fwd[1]), 4)
    hw = w / 2 + 0.3
    back = [front[0] - fwd[0] * (d + 0.3), front[1] - fwd[1] * (d + 0.3)]
    pf["footprint"] = [
        [round(front[0] + right[0] * hw, 2), round(front[1] + right[1] * hw, 2)],
        [round(front[0] - right[0] * hw, 2), round(front[1] - right[1] * hw, 2)],
        [round(back[0] - right[0] * hw, 2), round(back[1] - right[1] * hw, 2)],
        [round(back[0] + right[0] * hw, 2), round(back[1] + right[1] * hw, 2)],
    ]


def place_prefab(pf, streets):
    """Coloca el prefab con el frente mirando a la calle más cercana."""
    poly = pf["osm_points"]
    c = centroid(poly)
    best = None
    for s in streets:
        if s["type"] in NO_FILL_TYPES:
            continue
        if pf.get("street") and pf["street"] not in s["name"]:
            continue
        for i in range(len(s["points"]) - 1):
            a, b = s["points"][i], s["points"][i + 1]
            d = pt_seg_dist(c, a, b)
            if best is None or d < best[0]:
                best = (d, a, b)
    _, a, b = best
    L = math.dist(a, b)
    dx, dz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    # punto de la calle más cercano al edificio
    t = max(0.0, min(L, (c[0] - a[0]) * dx + (c[1] - a[1]) * dz))
    q = [a[0] + dx * t, a[1] + dz * t]
    nx, nz = c[0] - q[0], c[1] - q[1]
    nl = math.hypot(nx, nz)
    nx, nz = nx / nl, nz / nl            # de la calle hacia el edificio
    fwd = (-nx, -nz)                     # el frente mira a la calle
    w, d = PREFAB_SIZE[pf["prefab"]]
    # frente del edificio: al borde de la acera (ancho calle/2 + 1.8 m)
    street_w = 6.0
    for s in streets:
        if a in s["points"]:
            street_w = s["width"]
    front = [q[0] + nx * (street_w / 2 + 1.8), q[1] + nz * (street_w / 2 + 1.8)]
    right = (-fwd[1], fwd[0])
    # en Godot: yaw tal que el eje +Z local apunte a "fwd"
    pf["pos"] = [round(front[0], 2), round(front[1], 2)]
    pf["yaw"] = round(math.atan2(fwd[0], fwd[1]), 4)
    hw = w / 2 + 0.3
    back = [front[0] - fwd[0] * (d + 0.3), front[1] - fwd[1] * (d + 0.3)]
    pf["footprint"] = [
        [round(front[0] + right[0] * hw, 2), round(front[1] + right[1] * hw, 2)],
        [round(front[0] - right[0] * hw, 2), round(front[1] - right[1] * hw, 2)],
        [round(back[0] - right[0] * hw, 2), round(back[1] - right[1] * hw, 2)],
        [round(back[0] + right[0] * hw, 2), round(back[1] + right[1] * hw, 2)],
    ]
    del pf["osm_points"]
    pf.pop("street", None)


PLAZUELA_NAMES = ("juventud", "hogar del mayor")


def make_plazuelas(buildings, streets):
    """Zona entre la fachada y la acera (Casa de la Juventud, Hogar del Mayor):
    la acera se mete hacia dentro y hay bancos. Aquí no se ponen casas."""
    out = []
    for b in buildings:
        if not any(n in b["name"].lower() for n in PLAZUELA_NAMES):
            continue
        c = centroid(b["points"])
        best = None
        for st in streets:
            if st["type"] in NO_FILL_TYPES:
                continue
            for i in range(len(st["points"]) - 1):
                a, q = st["points"][i], st["points"][i + 1]
                d = pt_seg_dist(c, a, q)
                if best is None or d < best[0]:
                    best = (d, a, q, st["width"])
        if best is None:
            continue
        _, a, q, w = best
        L = math.dist(a, q)
        dx, dz = (q[0] - a[0]) / L, (q[1] - a[1]) / L
        nx, nz = -dz, dx
        if (c[0] - a[0]) * nx + (c[1] - a[1]) * nz < 0:
            nx, nz = -nx, -nz
        along = [(p[0] - a[0]) * dx + (p[1] - a[1]) * dz for p in b["points"]]
        across = [(p[0] - a[0]) * nx + (p[1] - a[1]) * nz for p in b["points"]]
        t0, t1 = min(along) - 1.0, max(along) + 1.0
        s0, s1 = w / 2 + 0.3, min(across) - 0.2
        if s1 - s0 < 2.0:
            continue
        P = lambda t, s_: [round(a[0] + dx * t + nx * s_, 2), round(a[1] + dz * t + nz * s_, 2)]
        out.append({"name": b["name"], "points": [P(t0, s0), P(t1, s0), P(t1, s1), P(t0, s1)],
                    "dir": [round(dx, 4), round(dz, 4)], "normal": [round(nx, 4), round(nz, 4)]})
    return out


def fill_houses(buildings, streets, plazas, pois, rect, rng, extra_obstacles=()):
    """Coloca casas adosadas a lo largo de las calles donde OSM no tiene edificios."""
    inner = (rect[0] + 2, rect[1] + 2, rect[2] - 2, rect[3] - 2)
    seg_list = []  # (a, b, radio libre, bbox)
    for s in streets:
        r = s["width"] / 2 + 0.6
        for i in range(len(s["points"]) - 1):
            a, b = s["points"][i], s["points"][i + 1]
            seg_list.append((a, b, r, bbox([a, b], r)))
    obstacles = [(b["points"], bbox(b["points"], 0.4)) for b in buildings]
    obstacles += [(p["points"], bbox(p["points"], 1.0)) for p in plazas]
    obstacles += [(p, bbox(p, 1.0)) for p in extra_obstacles]
    keep_clear = [p["pos"] for p in pois if p["type"] in ("fountain", "square")]

    def ok(poly):
        c0 = centroid(poly)
        poly = [[v[0] + (c0[0] - v[0]) * 0.03, v[1] + (c0[1] - v[1]) * 0.03] for v in poly]
        if not all(inner[0] <= v[0] <= inner[2] and inner[1] <= v[1] <= inner[3] for v in poly):
            return False
        bb = bbox(poly)
        for a, b, r, sb in seg_list:
            if bbox_hit(bb, sb) and poly_seg_dist(poly, a, b) < r:
                return False
        for q, qb in obstacles:
            if bbox_hit(bb, qb) and polys_overlap(poly, q):
                return False
        c = centroid(poly)
        return all(math.dist(c, k) > 9.0 for k in keep_clear)

    for s in streets:
        if s["type"] in NO_FILL_TYPES:
            continue
        pts = s["points"]
        off = s["width"] / 2 + 0.7
        for side in (1, -1):
            for i in range(len(pts) - 1):
                a, b = pts[i], pts[i + 1]
                L = math.dist(a, b)
                if L < 5:
                    continue
                dx, dz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
                nx, nz = -dz * side, dx * side
                t = 1.0
                while t < L - 3.0:
                    w = rng.uniform(6.0, 10.5)
                    depth = rng.uniform(8.0, 12.0)
                    w = min(w, L - t)
                    if w < 4.0:
                        break
                    o = off + rng.uniform(0.0, 0.3)
                    p0 = [a[0] + dx * t + nx * o, a[1] + dz * t + nz * o]
                    p1 = [p0[0] + dx * w, p0[1] + dz * w]
                    p2 = [p1[0] + nx * depth, p1[1] + nz * depth]
                    p3 = [p0[0] + nx * depth, p0[1] + nz * depth]
                    poly = [p0, p1, p2, p3]
                    if not ok(poly):
                        # prueba más estrecha y menos profunda (esquinas, huecos)
                        w2, d2 = w * 0.6, depth * 0.6
                        p1 = [p0[0] + dx * w2, p0[1] + dz * w2]
                        p2 = [p1[0] + nx * d2, p1[1] + nz * d2]
                        p3 = [p0[0] + nx * d2, p0[1] + nz * d2]
                        poly = [p0, p1, p2, p3]
                        w = w2
                    if ok(poly):
                        poly = [[round(v[0], 2), round(v[1], 2)] for v in poly]
                        floors = rng.choices([1, 2, 3], weights=[2, 6, 2])[0]
                        buildings.append({"points": poly, "height": round(floors * 3.1 + rng.uniform(0.2, 0.6), 2),
                                          "name": "", "type": "fill"})
                        obstacles.append((poly, bbox(poly, 0.4)))
                    t += w + (rng.uniform(1.5, 3.0) if rng.random() < 0.12 else 0.0)


if __name__ == "__main__":
    main()
