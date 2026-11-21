extends RefCounted
## Modul: Level (scripts/game/level).
## Baut das Level "Studio" (Abschnitt 9) vollständig im Code aus Quadern, als Kinder des
## übergebenen Knotens. Aufruf in main.gd: LevelBuilder.new().build(level_root). Der Builder
## selbst wird danach verworfen: alles Dauerhafte gehört in Knoten (siehe StudioShow unten).
##
## Grundriss (Blick von oben, +X rechts = Osten, +Z zum Publikum = Süden, der Spieler schaut
## anfangs nach -Z). Maße mit Balance.ZONE1_SIZE 26,5 × 21 und ZONE2_SIZE 14 × 12:
##   Zone 1 "Bühne":     x -13,25..13,25, z -10,5..10,5, 5 m hoch. Bühne (0,4 m) an der Rückwand,
##                       davor die Showtreppe, links und rechts je eine Rampe. Publikum hinter
##                       einer Brüstung bei z = 10,5 (nur Deko, für den Spieler gesperrt).
##   Vier kaufbare Räume (ROOMS), je 14 × 12 m, zwei östlich und zwei westlich der Bühne:
##     Zone 2 "Backstage" Südost (z -1,5..10,5),  Tür in der Ostwand bei z = 4.
##     Zone 3 "Kantine"   Südwest,                Tür in der Westwand bei z = 4.
##     Zone 4 "Garderobe" Nordost (z -13,9..-1,9), Tür in der Ostwand bei z = -6.
##     Zone 5 "Regieraum" Nordwest,               Tür in der Westwand bei z = -6.
##   Zwischen den beiden Räumen einer Seite liegt eine Verbindungstür (LinkEast, LinkWest). Sie
##   geht auf, sobald beide Räume gekauft sind, und verkauft vorher den Raum, der noch zu ist.
##   So entsteht je Seite ein Rundweg Bühne - Raum - Raum - Bühne.
##   Zombie-Eingänge:    A Showtor in der Rückwand auf Bühnenhöhe, B Südwand ganz im Westen,
##                       C Nordwand ganz im Osten (Zone 1). Je Raum zwei: einer in der Stirnwand
##                       (Süd oder Nord), einer in der Außenwand (D, E Backstage, F, G Kantine,
##                       H, I Garderobe, J, K Regieraum). Je ein kurzer Gang mit Spawnpunkt.
##
## Knoten unter parent: NavRegion (Bühne), NavRegion2 bis NavRegion5 (Räume, erst nach dem Kauf
## eingeschaltet), Door (Backstage), DoorCanteen, DoorWardrobe, DoorControlRoom, LinkEast,
## LinkWest, Show (Laufzeit-Knoten), Environment, Lights, Zone1 bis Zone5, Partitions (Wände
## zwischen zwei Räumen), Audience, Entrances (darin "Entrance_A" bis "Entrance_K" mit den
## Marker3D "Spawn_A" bis "Spawn_K" der Gruppe "zombie_spawns").

const Balance := preload("res://scripts/core/balance.gd")
const Door := preload("res://scripts/game/level/door.gd")

## Sperren nur für den Spieler liegen auf Balance.LAYER_PLAYER_BLOCK (Lage 6): Sie halten ihn aus
## den Zombie-Gängen und aus dem Publikum heraus, Zombies und Schüsse gehen hindurch.
const GROUP_PLAYER_BLOCK: String = "player_block"
const GROUP_NAV_SOURCE: String = "nav_source"
const GROUP_SPAWNS: String = "zombie_spawns"

# --- Maße des Grundrisses (Mesh-Maße, keine Spielregeln) ---
const WALL: float = 0.4
const CORRIDOR_WALL: float = 0.3
const ENTRANCE_WIDTH: float = 2.8
const ENTRANCE_HEIGHT: float = 3.0
const CORRIDOR_LENGTH: float = 4.5
## Abstand des Spawnpunkts vom Ende des Gangs.
const SPAWN_INSET: float = 1.5
## Ab dieser Tiefe hinter der Wandöffnung erreicht der Spieler eine Kiste nicht mehr sicher,
## und so weit vor der Öffnung landet sie dann im Raum.
const CHEST_RESCUE_DEPTH: float = 0.6
const CHEST_EXIT_INSET: float = 0.9
const DOOR_WIDTH: float = 2.6
const DOOR_HEIGHT: float = 3.0
const DOOR_THICKNESS: float = 0.3
## Mitte der Türen von der Bühne in die Räume auf der Z-Achse: vordere Reihe (Backstage, Kantine)
## und hintere Reihe (Garderobe, Regieraum). Ost- und Westwand sind gleich aufgeteilt.
const DOOR_Z: float = 4.0
const DOOR_BACK_Z: float = -6.0
## Verbindungstür zwischen den beiden Räumen einer Seite: Abstand ihrer Mitte von der Bühnenwand.
const LINK_DOOR_INSET: float = 7.0
## Spielerstart: so weit vor der Raummitte Richtung Publikum (Füße auf Bodenhöhe).
const PLAYER_SPAWN_Z: float = 5.0
## Zombie-Eingänge B und C der Bühne: Abstand ihrer Mitte von der Raumecke.
const STAGE_ENTRANCE_INSET: float = 2.0
const STAGE_DEPTH: float = 5.0
const STAGE_HALF_WIDTH: float = 7.0
const RAMP_RUN: float = 1.6
const STAIR_STEPS: int = 4
const BARRIER_HEIGHT: float = 1.1
const WINDOW_TOP: float = 4.2
const WINDOW_WIDTH: float = 18.0
const AUDIENCE_DEPTH: float = 4.8
const CEILING: float = 0.3
const FLOOR_THICKNESS: float = 0.5
## Dicke der Verkleidung, die in einem Raum die Rückseite einer fremden Wand bedeckt.
const CLADDING: float = 0.04

## Die kaufbaren Räume in der Reihenfolge ihrer Preise (Balance.DOOR_COSTS). Zone 1 ist die Bühne.
## side: +1 östlich, -1 westlich der Bühne. row: 0 = vordere Reihe (schließt mit der Südwand der
## Bühne ab), 1 = hintere Reihe (nördlich davon). door: Knotenname der Tür an der Bühne.
## entrances: Kennbuchstaben der beiden Zombie-Eingänge (Stirnwand, Außenwand). end_offset:
## Abstand des Eingangs in der Stirnwand von der Bühnenwand. side_offset: Abstand des Eingangs in
## der Außenwand von der Stirnwand. accent: Farbe von Türschild und Türlicht.
const ROOMS: Array[Dictionary] = [
	{ "zone": 2, "key": "backstage", "name": "Backstage", "door": "Door", "side": 1.0, "row": 0,
		"entrances": ["D", "E"], "end_offset": 5.0, "side_offset": 3.5, "accent": Color(0.97, 0.33, 0.64) },
	{ "zone": 3, "key": "canteen", "name": "Kantine", "door": "DoorCanteen", "side": -1.0, "row": 0,
		"entrances": ["F", "G"], "end_offset": 5.0, "side_offset": 3.5, "accent": Color(1.0, 0.72, 0.15) },
	{ "zone": 4, "key": "wardrobe", "name": "Garderobe", "door": "DoorWardrobe", "side": 1.0, "row": 1,
		"entrances": ["H", "I"], "end_offset": 9.5, "side_offset": 3.5, "accent": Color(0.75, 0.45, 1.0) },
	{ "zone": 5, "key": "control_room", "name": "Regieraum", "door": "DoorControlRoom", "side": -1.0, "row": 1,
		"entrances": ["J", "K"], "end_offset": 9.5, "side_offset": 3.5, "accent": Color(0.2, 0.85, 1.0) },
]

# --- Navigationsnetz ---
## Zellgröße des Netzes. Muss zur Zellgröße der Navigationskarte passen (Godot-Standard 0,25).
const NAV_CELL: float = 0.25
## Kleinste Fläche (in Zellen je Kante), die als begehbar übrig bleibt: wirft Inseln auf Kisten weg.
const NAV_REGION_MIN_SIZE: float = 8.0
const NAV_HEIGHT_EPSILON: float = 0.01

# --- Farben ---
const COLOR_FLOOR_A: Color = Color(0.2, 0.13, 0.42)
const COLOR_FLOOR_B: Color = Color(0.31, 0.2, 0.6)
const COLOR_WALL_A: Color = Color(0.07, 0.5, 0.58)
const COLOR_WALL_B: Color = Color(0.1, 0.62, 0.68)
const COLOR_CEILING: Color = Color(0.07, 0.06, 0.11)
const COLOR_STAGE_A: Color = Color(0.86, 0.14, 0.5)
const COLOR_STAGE_B: Color = Color(0.97, 0.33, 0.64)
const COLOR_GOLD: Color = Color(1.0, 0.8, 0.12)
const COLOR_RED: Color = Color(0.85, 0.1, 0.12)
const COLOR_CYAN: Color = Color(0.1, 0.8, 0.92)
const COLOR_ORANGE: Color = Color(1.0, 0.5, 0.08)
const COLOR_WHITE: Color = Color(0.96, 0.96, 0.92)
const COLOR_BLACK: Color = Color(0.06, 0.06, 0.07)
const COLOR_CORRIDOR_A: Color = Color(0.09, 0.17, 0.11)
const COLOR_CORRIDOR_B: Color = Color(0.13, 0.25, 0.14)
const COLOR_BACK_FLOOR_A: Color = Color(0.25, 0.27, 0.32)
const COLOR_BACK_FLOOR_B: Color = Color(0.3, 0.32, 0.38)
const COLOR_BACK_WALL_A: Color = Color(0.2, 0.26, 0.4)
const COLOR_BACK_WALL_B: Color = Color(0.25, 0.32, 0.47)
const COLOR_WOOD_A: Color = Color(0.66, 0.45, 0.2)
const COLOR_WOOD_B: Color = Color(0.5, 0.33, 0.14)
const COLOR_CANTEEN_FLOOR_A: Color = Color(0.86, 0.82, 0.66)
const COLOR_CANTEEN_FLOOR_B: Color = Color(0.42, 0.68, 0.58)
const COLOR_CANTEEN_WALL_A: Color = Color(0.93, 0.9, 0.78)
const COLOR_CANTEEN_WALL_B: Color = Color(0.96, 0.72, 0.28)
const COLOR_WARDROBE_FLOOR_A: Color = Color(0.5, 0.14, 0.3)
const COLOR_WARDROBE_FLOOR_B: Color = Color(0.62, 0.22, 0.4)
const COLOR_WARDROBE_WALL_A: Color = Color(0.95, 0.86, 0.8)
const COLOR_WARDROBE_WALL_B: Color = Color(0.9, 0.66, 0.72)
const COLOR_CONTROL_FLOOR_A: Color = Color(0.17, 0.19, 0.27)
const COLOR_CONTROL_FLOOR_B: Color = Color(0.23, 0.26, 0.36)
const COLOR_CONTROL_WALL_A: Color = Color(0.1, 0.15, 0.33)
const COLOR_CONTROL_WALL_B: Color = Color(0.15, 0.24, 0.46)
const COLOR_STEEL: Color = Color(0.7, 0.72, 0.76)
const COLOR_DARK_METAL: Color = Color(0.2, 0.2, 0.24)
const COLOR_AUDIENCE_DARK: Color = Color(0.08, 0.08, 0.2)
const AUDIENCE_SHIRTS: Array[Color] = [
	Color(0.95, 0.25, 0.3), Color(0.2, 0.7, 0.95), Color(1.0, 0.8, 0.2),
	Color(0.4, 0.85, 0.35), Color(0.9, 0.4, 0.9), Color(1.0, 0.55, 0.15),
]
const AUDIENCE_SKIN: Array[Color] = [
	Color(0.95, 0.78, 0.62), Color(0.75, 0.55, 0.4), Color(0.5, 0.35, 0.25),
]
const SPOT_COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.75), Color(0.2, 0.85, 1.0), Color(1.0, 0.9, 0.25), Color(0.35, 1.0, 0.4),
]

## Titel der Show auf dem großen Schild und dessen Breite in Metern.
const SHOW_TITLE: String = "WER WIRD ZOMBIEFUTTER?"
const SHOW_SIGN_WIDTH: float = 12.0
## Halber Öffnungswinkel der Bühnenscheinwerfer in Grad und Länge ihres sichtbaren Lichtkegels.
const SPOT_ANGLE: float = 24.0
const SPOT_CONE_LENGTH: float = 5.2
## Reichweite des Deckenlichts eines kaufbaren Raums in Metern.
const ROOM_LIGHT_RANGE: float = 13.0


## Laufzeit-Knoten des Levels (Knoten "Show"). Bewegt die Scheinwerfer, lässt Lampen blinken und
## das Publikum jubeln, rettet Kisten aus den Zombie-Gängen, backt das Navigationsnetz, falls das
## Level beim Bauen noch nicht im Baum hing, und schaltet mit jeder gekauften Tür den Raum dahinter
## frei (Navigationsnetz, Sichtbarkeit, Licht, Warnlampen).
class StudioShow:
	extends Node3D

	## Region der Bühne (Zone 1), immer eingeschaltet.
	var nav_region: NavigationRegion3D
	## Einstellungen des Navigationsnetzes und das zuletzt gebackene Gesamtnetz (alle Zonen).
	var nav_mesh: NavigationMesh
	## Die Tür zum Backstage (Zone 2).
	var door: Node3D
	## Je kaufbarem Raum (Schlüssel = Zone): die Tür an der Bühne, die Region seines Netzes,
	## alles, was nur bei offenem Raum zu sehen ist (Geometrie, Gänge, Lichter), und das Material
	## seiner Warnlampen.
	var zone_doors: Dictionary = {}
	var zone_regions: Dictionary = {}
	var zone_nodes: Dictionary = {}
	var zone_warn: Dictionary = {}
	## Grundfläche der Bühne und je Raum die Fläche samt seiner Zombie-Gänge (x, z in Koordinaten
	## des Levels). Danach wird das gebackene Netz auf die Regionen verteilt.
	var stage_rect: Rect2 = Rect2()
	var zone_rects: Dictionary = {}
	var spots: Array[SpotLight3D] = []
	var spot_targets: Array[Vector3] = []
	var bulbs_a: StandardMaterial3D
	var bulbs_b: StandardMaterial3D
	var warn_zone1: StandardMaterial3D
	var applause_label: Label3D
	var audience: Array[Node3D] = []
	## true: Das Netz wird erst in _ready gebacken (Level wurde außerhalb des Baums gebaut).
	var bake_on_ready: bool = false
	## Für den Spieler gesperrte Bereiche (Zombie-Gänge, in Koordinaten des Levels) und je Bereich
	## der Punkt im Raum davor. Eine Kiste, die in einem Gang landet, rutscht dorthin heraus.
	var blocked_zones: Array[AABB] = []
	var blocked_exits: Array[Vector3] = []

	var _audience_base: PackedFloat32Array = PackedFloat32Array()
	var _time: float = 0.0
	var _cheer_left: float = 0.0
	var _bulb_phase: int = -1
	var _applause_on: int = -1

	const BULB_BRIGHT: Color = Color(1.0, 0.95, 0.6)
	const BULB_DIM: Color = Color(0.45, 0.3, 0.1)
	const WARN_COLOR: Color = Color(1.0, 0.12, 0.08)
	const WARN_OFF: Color = Color(0.2, 0.05, 0.05)
	const APPLAUSE_ON: Color = Color(1.0, 0.92, 0.25)
	const APPLAUSE_OFF: Color = Color(0.35, 0.3, 0.2)
	const SPOT_ENERGY: float = 6.5
	const CHEST_SLIDE_TIME: float = 0.4

	func _ready() -> void:
		for person: Node3D in audience:
			_audience_base.append(person.position.y)
		Events.zombie_killed.connect(_on_zombie_killed)
		Events.wave_started.connect(_on_wave_started)
		Events.chest_dropped.connect(_on_chest_dropped)
		for zone: int in zone_doors:
			var zone_door: Node = zone_doors[zone]
			if is_instance_valid(zone_door):
				zone_door.connect("opened", _refresh_zones)
				zone_door.connect("closed", _refresh_zones)
		# Die Karte übernimmt Änderungen im nächsten Physik-Schritt statt irgendwann danach in
		# einem Thread: Ein gekaufter Raum ist so sofort begehbar (die Karte ist klein genug).
		if is_instance_valid(nav_region) and nav_region.is_inside_tree():
			NavigationServer3D.map_set_use_async_iterations(nav_region.get_navigation_map(), false)
		_refresh_zones()
		if bake_on_ready:
			bake()

	## true, wenn der Raum gekauft ist (Zone 1, die Bühne, ist immer offen).
	func is_zone_open(zone: int) -> bool:
		if zone <= 1:
			return true
		var zone_door: Node = zone_doors.get(zone) as Node
		return is_instance_valid(zone_door) and bool(zone_door.get("is_open"))

	## Gleicht jeden Raum mit seiner Tür ab: Nur ein gekaufter Raum hat ein Navigationsnetz (kein
	## Zombie plant einen Weg durch eine geschlossene Tür), ist zu sehen und beleuchtet.
	func _refresh_zones() -> void:
		for zone: int in zone_doors:
			var open: bool = is_zone_open(zone)
			var region: NavigationRegion3D = zone_regions.get(zone) as NavigationRegion3D
			if is_instance_valid(region) and region.enabled != open:
				region.enabled = open
			for node: Variant in zone_nodes.get(zone, []):
				if is_instance_valid(node):
					(node as Node3D).visible = open

	## Backt das Navigationsnetz aus den Kollisionen der Gruppe "nav_source" (im Hauptthread,
	## dauert einige Millisekunden) und verteilt es auf die Regionen: Bühne und je Raum eine.
	## Alle Regionen teilen dieselben Eckpunkte, an den Türen schließen ihre Flächen deshalb
	## lückenlos aneinander an. Gibt true zurück, wenn das Netz danach Flächen hat. Darf erneut
	## aufgerufen werden, wenn sich die Geometrie geändert hat.
	func bake() -> bool:
		if not is_instance_valid(nav_region) or not nav_region.is_inside_tree() or nav_mesh == null:
			return false
		var source: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source, nav_region)
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
		# Godot legt das Netz eine Zellhöhe über die Oberfläche. Zurück auf Bodenhöhe schieben,
		# damit Pfadpunkte dort liegen, wo die Füße der Zombies sind.
		var vertices: PackedVector3Array = nav_mesh.get_vertices()
		for i: int in range(vertices.size()):
			vertices[i].y -= nav_mesh.cell_height
		nav_mesh.set_vertices(vertices)
		var parts: Dictionary = { 1: _empty_part() }
		for zone: int in zone_regions:
			parts[zone] = _empty_part()
		for i: int in range(nav_mesh.get_polygon_count()):
			var polygon: PackedInt32Array = nav_mesh.get_polygon(i)
			var zone: int = _zone_of_polygon(vertices, polygon)
			(parts[zone] as NavigationMesh).add_polygon(polygon)
		nav_region.navigation_mesh = parts[1]
		for zone: int in zone_regions:
			var region: NavigationRegion3D = zone_regions[zone] as NavigationRegion3D
			if is_instance_valid(region):
				region.navigation_mesh = parts[zone]
		var ok: bool = (parts[1] as NavigationMesh).get_polygon_count() > 0
		if not ok:
			push_warning("Level: Das Navigationsnetz ist nach dem Backen leer.")
		return ok

	## Leeres Netz mit den Einstellungen und Eckpunkten des Gesamtnetzes.
	func _empty_part() -> NavigationMesh:
		var part: NavigationMesh = nav_mesh.duplicate() as NavigationMesh
		part.clear_polygons()
		return part

	## Zone einer Netzfläche. Was mit einer Ecke in der Bühne liegt, gehört zur Bühne (auch der
	## Streifen durch eine Türöffnung, so hat die Bühne nie ein Loch vor einer geschlossenen Tür).
	## Sonst entscheidet der Mittelpunkt: der Raum, in dessen Fläche er liegt.
	func _zone_of_polygon(vertices: PackedVector3Array, polygon: PackedInt32Array) -> int:
		var middle: Vector2 = Vector2.ZERO
		for index: int in polygon:
			var corner: Vector2 = Vector2(vertices[index].x, vertices[index].z)
			if stage_rect.has_point(corner):
				return 1
			middle += corner
		middle /= float(maxi(polygon.size(), 1))
		for zone: int in zone_rects:
			if (zone_rects[zone] as Rect2).has_point(middle):
				return zone
		return 1

	func _process(delta: float) -> void:
		_time += delta
		_cheer_left = maxf(_cheer_left - delta, 0.0)
		var cheering: bool = _cheer_left > 0.0
		_animate_spots(cheering)
		_animate_bulbs()
		_animate_warning()
		_animate_audience(cheering)
		_animate_applause(cheering)

	func _animate_spots(cheering: bool) -> void:
		var speed: float = 2.2 if cheering else 1.0
		for i: int in range(spots.size()):
			var spot: SpotLight3D = spots[i]
			if not is_instance_valid(spot) or i >= spot_targets.size():
				continue
			var phase: float = _time * speed + float(i) * 1.7
			var target: Vector3 = spot_targets[i] + Vector3(sin(phase * 0.7) * 2.4, 0.0, cos(phase * 0.9) * 1.3)
			var from: Vector3 = spot.global_position
			if from.distance_squared_to(target) > 0.01 and absf((target - from).normalized().y) < 0.99:
				spot.look_at(target, Vector3.UP)
			spot.light_energy = SPOT_ENERGY * (1.2 + 0.4 * sin(_time * 18.0 + float(i))) if cheering else SPOT_ENERGY

	func _animate_bulbs() -> void:
		var phase: int = int(_time / 0.4) % 2
		if phase == _bulb_phase:
			return
		_bulb_phase = phase
		if bulbs_a != null:
			bulbs_a.albedo_color = BULB_BRIGHT if phase == 0 else BULB_DIM
		if bulbs_b != null:
			bulbs_b.albedo_color = BULB_DIM if phase == 0 else BULB_BRIGHT

	func _animate_warning() -> void:
		var pulse: float = 0.35 + 0.65 * absf(sin(_time * 3.2))
		var lit: Color = WARN_OFF.lerp(WARN_COLOR, pulse)
		if warn_zone1 != null:
			warn_zone1.albedo_color = lit
		for zone: int in zone_warn:
			var material: StandardMaterial3D = zone_warn[zone] as StandardMaterial3D
			if material != null:
				material.albedo_color = lit if is_zone_open(zone) else WARN_OFF

	func _animate_audience(cheering: bool) -> void:
		var amplitude: float = 0.32 if cheering else 0.03
		var speed: float = 11.0 if cheering else 2.0
		for i: int in range(audience.size()):
			var person: Node3D = audience[i]
			if not is_instance_valid(person) or i >= _audience_base.size():
				continue
			person.position.y = _audience_base[i] + absf(sin(_time * speed + float(i) * 1.3)) * amplitude

	func _animate_applause(cheering: bool) -> void:
		if not is_instance_valid(applause_label):
			return
		var state: int = 0
		if cheering:
			state = 1 + (int(_time / 0.15) % 2)
		if state == _applause_on:
			return
		_applause_on = state
		applause_label.modulate = APPLAUSE_ON if state == 1 else APPLAUSE_OFF

	func _on_zombie_killed(_zombie: Node3D, _info: Dictionary) -> void:
		_cheer_left = maxf(_cheer_left, 0.9)

	func _on_wave_started(_wave: int, _total: int) -> void:
		_cheer_left = maxf(_cheer_left, 1.8)

	func _on_chest_dropped(chest: Node3D) -> void:
		# Erst nach dem Signal prüfen: Dann steht die Kiste sicher an ihrem endgültigen Platz.
		_rescue_chest.call_deferred(chest)

	## Liegt die Kiste in einem Zombie-Gang (für den Spieler gesperrt), rutscht sie in den Raum.
	func _rescue_chest(chest: Node3D) -> void:
		if not is_instance_valid(chest) or not chest.is_inside_tree() or not is_inside_tree():
			return
		var local: Vector3 = to_local(chest.global_position)
		for i: int in range(mini(blocked_zones.size(), blocked_exits.size())):
			if not blocked_zones[i].has_point(local):
				continue
			var tween: Tween = chest.create_tween()
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(chest, "global_position", to_global(blocked_exits[i]), CHEST_SLIDE_TIME)
			return


var _materials: Dictionary = {}
var _textures: Dictionary = {}
## Render-Ebene neuer Meshes: 1 = Zone 1 (warmes Hauptlicht), 2 = die Räume (kühles Hauptlicht).
var _render_layer: int = 1
var _show: StudioShow
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Grundriss, in build() aus Balance berechnet.
var _hx: float = 13.25
var _hz: float = 10.5
var _height1: float = 5.0
var _height2: float = 5.0
var _stage_y: float = 0.4
var _stage_front_z: float = -5.5
## Die Räume aus ROOMS mit ihren Maßen. Zusätzliche Schlüssel je Raum: cost (int), inner_x
## (Raumseite der Wand zur Bühne), outer_x (Raumseite der Außenwand), min_z, max_z (Innenmaße),
## door_z (Mitte der Tür an der Bühne), link_x (Mitte der Verbindungstür).
var _rooms: Array[Dictionary] = []


## Baut das Level unter parent und gibt zurück:
## { "player_spawn": Vector3 (Füße des Spielers, Weltkoordinaten),
##   "nav_region": NavigationRegion3D (Netz der Bühne),
##   "door": Node3D (door.gd, die Tür zum Backstage),
##   "rooms": Array[Dictionary] (die kaufbaren Räume nach Preis: zone, key, name, cost, door,
##            nav_region, center (Bodenmitte in Weltkoordinaten), size (Innenmaße)),
##   "links": Array[Node3D] (die Verbindungstüren zwischen zwei Räumen) }.
## Hängt parent schon im Baum, ist das Navigationsnetz bei der Rückkehr fertig gebacken.
func build(parent: Node3D) -> Dictionary:
	_measure()
	_rng.seed = 20240917
	_show = StudioShow.new()
	_show.name = "Show"
	_show.warn_zone1 = _glow_unique(StudioShow.WARN_COLOR)
	_show.bulbs_a = _glow_unique(StudioShow.BULB_BRIGHT)
	_show.bulbs_b = _glow_unique(StudioShow.BULB_DIM)

	var nav_region: NavigationRegion3D = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	parent.add_child(nav_region)
	for room: Dictionary in _rooms:
		var zone: int = int(room["zone"])
		var room_region: NavigationRegion3D = NavigationRegion3D.new()
		room_region.name = "NavRegion%d" % zone
		room_region.enabled = false
		parent.add_child(room_region)
		_show.zone_regions[zone] = room_region
		_show.zone_warn[zone] = _glow_unique(StudioShow.WARN_OFF)
		_show.zone_nodes[zone] = []
		_show.zone_rects[zone] = _room_nav_rect(room)
	var inside: float = NAV_CELL * 0.2
	_show.stage_rect = Rect2(-_hx + inside, -_hz + inside, (_hx - inside) * 2.0, (_hz - inside) * 2.0)

	_build_environment(parent)
	var entrances: Node3D = _group_node(parent, "Entrances")
	_render_layer = 1
	_build_zone1(_group_node(parent, "Zone1"), entrances)
	_build_audience(_group_node(parent, "Audience"))
	_render_layer = 2
	var partitions: Node3D = _group_node(parent, "Partitions")
	for room: Dictionary in _rooms:
		var zone_node: Node3D = _group_node(parent, "Zone%d" % int(room["zone"]))
		(_show.zone_nodes[int(room["zone"])] as Array).append(zone_node)
		_build_room(zone_node, partitions, entrances, room)
	_render_layer = 1
	var room_infos: Array[Dictionary] = []
	for room: Dictionary in _rooms:
		var zone: int = int(room["zone"])
		var door: StaticBody3D = _add_door(parent, String(room["door"]),
				Vector3(float(room["side"]) * (_hx + WALL * 0.5), 0.0, float(room["door_z"])), 90.0, room, {})
		_show.zone_doors[zone] = door
		var center: Vector3 = Vector3((float(room["inner_x"]) + float(room["outer_x"])) * 0.5, 0.0,
				(float(room["min_z"]) + float(room["max_z"])) * 0.5)
		room_infos.append({
			"zone": zone, "key": String(room["key"]), "name": String(room["name"]), "cost": int(room["cost"]),
			"door": door, "nav_region": _show.zone_regions[zone],
			"center": parent.to_global(center) if parent.is_inside_tree() else center,
			"size": Vector3(Balance.ZONE2_SIZE.x, _height2, Balance.ZONE2_SIZE.z),
		})
	var links: Array[Node3D] = _build_links(parent)
	_build_lights(_group_node(parent, "Lights"))

	_show.nav_region = nav_region
	_show.nav_mesh = _make_navigation_mesh()
	_show.door = _show.zone_doors[int(_rooms[0]["zone"])]
	_show.bake_on_ready = not parent.is_inside_tree()
	parent.add_child(_show)
	if parent.is_inside_tree():
		_show.bake()

	var spawn_local: Vector3 = Vector3(0.0, 0.0, PLAYER_SPAWN_Z)
	return {
		"player_spawn": parent.to_global(spawn_local) if parent.is_inside_tree() else spawn_local,
		"nav_region": nav_region,
		"door": _show.door,
		"rooms": room_infos,
		"links": links,
	}


func _measure() -> void:
	_hx = Balance.ZONE1_SIZE.x * 0.5
	_hz = Balance.ZONE1_SIZE.z * 0.5
	_height1 = Balance.ZONE1_SIZE.y
	_height2 = Balance.ZONE2_SIZE.y
	_stage_y = Balance.STAGE_HEIGHT
	_stage_front_z = -_hz + STAGE_DEPTH
	_rooms.clear()
	for i: int in range(ROOMS.size()):
		var room: Dictionary = ROOMS[i].duplicate()
		var side: float = float(room["side"])
		var front: bool = int(room["row"]) == 0
		room["cost"] = Balance.DOOR_COSTS[mini(i, Balance.DOOR_COSTS.size() - 1)]
		room["inner_x"] = side * (_hx + WALL)
		room["outer_x"] = side * (_hx + WALL + Balance.ZONE2_SIZE.x)
		room["max_z"] = _hz if front else _hz - Balance.ZONE2_SIZE.z - WALL
		room["min_z"] = float(room["max_z"]) - Balance.ZONE2_SIZE.z
		room["door_z"] = DOOR_Z if front else DOOR_BACK_Z
		room["link_x"] = side * (_hx + WALL + LINK_DOOR_INSET)
		_rooms.append(room)


## Punkt in einem Raum: u = Abstand von der Wand zur Bühne, v = Abstand von der Nordwand.
## So stehen die Requisiten der östlichen und der westlichen Räume in derselben Schreibweise.
func _room_point(room: Dictionary, u: float, v: float, y: float = 0.0) -> Vector3:
	return Vector3(float(room["inner_x"]) + float(room["side"]) * u, y, float(room["min_z"]) + v)


## Der Raum einer Zone aus _rooms (leer, wenn es ihn nicht gibt).
func _room_of(zone: int) -> Dictionary:
	for room: Dictionary in _rooms:
		if int(room["zone"]) == zone:
			return room
	return {}


## Der andere Raum derselben Seite (leer, wenn es keinen gibt).
func _neighbour_of(room: Dictionary) -> Dictionary:
	for other: Dictionary in _rooms:
		if is_equal_approx(float(other["side"]), float(room["side"])) and int(other["row"]) != int(room["row"]):
			return other
	return {}


## Fläche eines Raums samt seiner Zombie-Gänge (x, z): von der Bühnenwand bis hinter die Gänge
## der Außen- und der Stirnwand, zum Nachbarraum hin bis zur Mitte der gemeinsamen Wand.
func _room_nav_rect(room: Dictionary) -> Rect2:
	var reach: float = WALL + CORRIDOR_LENGTH + CORRIDOR_WALL + 1.0
	var side: float = float(room["side"])
	var x_a: float = side * _hx
	var x_b: float = float(room["outer_x"]) + side * reach
	var min_z: float = float(room["min_z"])
	var max_z: float = float(room["max_z"])
	if int(room["row"]) == 0:
		min_z -= WALL * 0.5
		max_z += reach
	else:
		min_z -= reach
		max_z += WALL * 0.5
	return Rect2(minf(x_a, x_b), min_z, absf(x_b - x_a), max_z - min_z)


# ---------------------------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------------------------

## Einstellungen des Netzes: gebacken wird aus den Kollisionsformen der Gruppe "nav_source".
## Radius und Höhe richten sich nach dem größten Zombie (Elite), auf Zellen aufgerundet.
func _make_navigation_mesh() -> NavigationMesh:
	var max_scale: float = 1.0
	for type: String in Balance.ZOMBIE_TYPES:
		max_scale = maxf(max_scale, float(Balance.ZOMBIE_TYPES[type].get("scale", 1.0)))
	var nav_mesh: NavigationMesh = NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = Balance.LAYER_WORLD
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nav_mesh.geometry_source_group_name = GROUP_NAV_SOURCE
	nav_mesh.cell_size = NAV_CELL
	nav_mesh.cell_height = NAV_CELL
	nav_mesh.agent_radius = ceilf(Balance.ZOMBIE_RADIUS * max_scale / NAV_CELL) * NAV_CELL
	nav_mesh.agent_height = ceilf(Balance.ZOMBIE_HEIGHT * max_scale / NAV_CELL) * NAV_CELL
	nav_mesh.agent_max_climb = NAV_CELL
	nav_mesh.agent_max_slope = 40.0
	nav_mesh.region_min_size = NAV_REGION_MIN_SIZE
	# Nur bis knapp unter die Decke backen: Oberkanten von Wänden und Decken zählen nicht.
	# Die Unterkante liegt bewusst knapp neben dem Zellraster: Der Boden (y = 0) fällt so sicher
	# in die Zelle darunter statt genau auf eine Zellgrenze (sonst liegt das Netz eine Zelle zu hoch).
	var reach: float = WALL + CORRIDOR_LENGTH + 2.0
	var far_x: float = _hx
	var min_z: float = -_hz
	for room: Dictionary in _rooms:
		far_x = maxf(far_x, absf(float(room["outer_x"])))
		min_z = minf(min_z, float(room["min_z"]))
	var low: Vector3 = Vector3(-far_x - reach, -1.0 + NAV_HEIGHT_EPSILON, min_z - reach)
	var high: Vector3 = Vector3(far_x + reach, 4.0, _hz + reach)
	nav_mesh.filter_baking_aabb = AABB(low, high - low)
	return nav_mesh


# ---------------------------------------------------------------------------------------------
# Zone 1 "Bühne"
# ---------------------------------------------------------------------------------------------

func _build_zone1(zone: Node3D, entrances: Node3D) -> void:
	var floor_mat: StandardMaterial3D = _pattern("checker", COLOR_FLOOR_A, COLOR_FLOOR_B, 1.0)
	var wall_mat: StandardMaterial3D = _pattern("stripes", COLOR_WALL_A, COLOR_WALL_B, 1.0)
	var ceiling_mat: StandardMaterial3D = _flat(COLOR_CEILING)
	var outer_x: float = _hx + WALL
	var outer_z: float = _hz + WALL

	# Boden: ein Kollisionskörper, aber zwölf Mesh-Stücke (damit je Stück wenige Lichter zählen).
	var floor_body: StaticBody3D = _collider(zone, "Floor", Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0),
			Vector3(outer_x * 2.0, FLOOR_THICKNESS, outer_z * 2.0), true)
	var tile: Vector3 = Vector3(outer_x * 2.0 / 4.0, FLOOR_THICKNESS, outer_z * 2.0 / 3.0)
	for ix: int in range(4):
		for iz: int in range(3):
			var center: Vector3 = Vector3(-outer_x + tile.x * (float(ix) + 0.5), 0.0, -outer_z + tile.z * (float(iz) + 0.5))
			_deco(floor_body, "FloorMesh", center, tile, floor_mat)
	_solid(zone, "Ceiling", Vector3(0.0, _height1 + CEILING * 0.5, 0.0),
			Vector3(outer_x * 2.0, CEILING, outer_z * 2.0), ceiling_mat, false)

	# Wände mit Öffnungen: Showtor (A) und Eingang C in der Rückwand, Eingang B und das
	# Publikumsfenster in der Südwand, je zwei Türen in der Ost- und in der Westwand.
	var gate_top: float = _stage_y + ENTRANCE_HEIGHT
	var mouth_b: Vector3 = Vector3(-_hx + STAGE_ENTRANCE_INSET, 0.0, _hz)
	var mouth_c: Vector3 = Vector3(_hx - STAGE_ENTRANCE_INSET, 0.0, -_hz)
	_wall(zone, "WallNorth", true, -_hz - WALL * 0.5, -outer_x, outer_x, _height1, [
		_opening(0.0, ENTRANCE_WIDTH, 0.0, gate_top),
		_opening(mouth_c.x, ENTRANCE_WIDTH, 0.0, ENTRANCE_HEIGHT),
	], wall_mat)
	_wall(zone, "WallSouth", true, _hz + WALL * 0.5, -outer_x, outer_x, _height1, [
		_opening(mouth_b.x, ENTRANCE_WIDTH, 0.0, ENTRANCE_HEIGHT),
		_opening(0.0, WINDOW_WIDTH, BARRIER_HEIGHT, WINDOW_TOP),
	], wall_mat)
	var doors: Array = [
		_opening(DOOR_BACK_Z, DOOR_WIDTH, 0.0, DOOR_HEIGHT),
		_opening(DOOR_Z, DOOR_WIDTH, 0.0, DOOR_HEIGHT),
	]
	_wall(zone, "WallWest", false, -_hx - WALL * 0.5, -_hz, _hz, _height1, doors, wall_mat)
	_wall(zone, "WallEast", false, _hx + WALL * 0.5, -_hz, _hz, _height1, doors, wall_mat)

	_add_entrance(entrances, "A", 1, Vector3(0.0, _stage_y, -_hz), Vector3(0.0, 0.0, -1.0), "")
	_add_entrance(entrances, "B", 1, mouth_b, Vector3(0.0, 0.0, 1.0), "AUFTRITT ZOMBIES")
	_add_entrance(entrances, "C", 1, mouth_c, Vector3(0.0, 0.0, -1.0), "AUFTRITT ZOMBIES")

	_build_stage(zone)
	_build_show_sign(zone)
	_build_set_pieces(zone)
	_build_rig(zone)
	_build_ceiling_lamps(zone)

	# Schild mit dem Raumnamen über jeder Tür, in der Farbe des Raums.
	for room: Dictionary in _rooms:
		var side: float = float(room["side"])
		var title: String = String(room["name"]).to_upper()
		var sign_pos: Vector3 = Vector3(side * (_hx - 0.06), DOOR_HEIGHT + 0.75, float(room["door_z"]))
		_deco(zone, "RoomSign", sign_pos, Vector3(0.1, 0.8, 3.9), _flat(COLOR_BLACK))
		_label(zone, "%s >>" % title if side > 0.0 else "<< %s" % title, sign_pos + Vector3(-side * 0.07, 0.0, 0.0),
				-90.0 * side, 0.5, room["accent"], COLOR_BLACK)


func _build_stage(zone: Node3D) -> void:
	var stage_mat: StandardMaterial3D = _pattern("checker", COLOR_STAGE_A, COLOR_STAGE_B, 0.75)
	var skirt_mat: StandardMaterial3D = _pattern("stripes", COLOR_GOLD, COLOR_RED, 0.3)
	var center_z: float = -_hz + STAGE_DEPTH * 0.5
	_solid(zone, "Stage", Vector3(0.0, _stage_y * 0.5, center_z),
			Vector3(STAGE_HALF_WIDTH * 2.0, _stage_y, STAGE_DEPTH), stage_mat)
	# Zierblenden an den freien Kanten der Bühne.
	_deco(zone, "StageSkirt", Vector3(0.0, _stage_y * 0.5, _stage_front_z + 0.02),
			Vector3(STAGE_HALF_WIDTH * 2.0 + 0.08, _stage_y + 0.02, 0.04), skirt_mat)
	for side: float in [-1.0, 1.0]:
		_deco(zone, "StageSkirt", Vector3(side * (STAGE_HALF_WIDTH + 0.02), _stage_y * 0.5, center_z),
				Vector3(0.04, _stage_y + 0.02, STAGE_DEPTH), skirt_mat)
	# Showtreppe vorn, je eine Rampe links und rechts. Kollision ist ein Keil, sichtbar sind Stufen.
	_add_ramp(zone, "ShowStairs", Vector3(0.0, _stage_y, _stage_front_z), Vector3(0.0, 0.0, 1.0), 5.0)
	_add_ramp(zone, "RampWest", Vector3(-STAGE_HALF_WIDTH, _stage_y, center_z + 0.3), Vector3(-1.0, 0.0, 0.0), 2.6)
	_add_ramp(zone, "RampEast", Vector3(STAGE_HALF_WIDTH, _stage_y, center_z + 0.3), Vector3(1.0, 0.0, 0.0), 2.6)

	# Rahmen des Showtors (Eingang A) mit Vorhang-Streifen links und rechts.
	var curtain_mat: StandardMaterial3D = _pattern("stripes", COLOR_RED, Color(0.6, 0.05, 0.1), 0.25)
	var curtain_from: float = ENTRANCE_WIDTH * 0.5 + 0.2
	var curtain_to: float = STAGE_HALF_WIDTH - 0.2
	for side: float in [-1.0, 1.0]:
		_deco(zone, "Curtain", Vector3(side * (curtain_from + curtain_to) * 0.5, _stage_y + 1.7, -_hz + 0.06),
				Vector3(curtain_to - curtain_from, 3.4, 0.1), curtain_mat)
	# Pult des Moderators und Preis-Würfel als Deckung auf der Bühne.
	var desk_pos: Vector3 = Vector3(3.7, _stage_y + 0.55, center_z + 0.2)
	_solid(zone, "HostDesk", desk_pos, Vector3(2.4, 1.1, 0.9), _pattern("bands", COLOR_CYAN, COLOR_WHITE, 0.28, false), true, -14.0)
	_deco(zone, "HostDeskTop", desk_pos + Vector3(0.0, 0.59, 0.0), Vector3(2.6, 0.08, 1.1), _flat(COLOR_GOLD), -14.0)
	var gift_pos: Vector3 = Vector3(-3.9, _stage_y + 0.5, center_z - 0.6)
	_solid(zone, "PrizeBox", gift_pos, Vector3(1.0, 1.0, 1.0), _flat(COLOR_GOLD), true, 20.0)
	_deco(zone, "PrizeRibbon", gift_pos, Vector3(1.04, 1.04, 0.22), _flat(COLOR_RED), 20.0)
	_deco(zone, "PrizeRibbon", gift_pos, Vector3(0.22, 1.04, 1.04), _flat(COLOR_RED), 20.0)
	_deco(zone, "PrizeBoxSmall", gift_pos + Vector3(0.0, 0.8, 0.0), Vector3(0.6, 0.6, 0.6), _flat(COLOR_CYAN), 50.0)


## Großes Show-Logo über dem Showtor mit Lauflicht aus Glühbirnen.
func _build_show_sign(zone: Node3D) -> void:
	var gate_top: float = _stage_y + ENTRANCE_HEIGHT
	var sign_height: float = minf(1.25, _height1 - gate_top - 0.65)
	var sign_width: float = SHOW_SIGN_WIDTH
	var center: Vector3 = Vector3(0.0, gate_top + 0.4 + sign_height * 0.5, -_hz + 0.12)
	_deco(zone, "ShowSignFrame", center, Vector3(sign_width + 0.3, sign_height + 0.3, 0.16), _flat(COLOR_GOLD))
	_deco(zone, "ShowSign", center + Vector3(0.0, 0.0, 0.05), Vector3(sign_width, sign_height, 0.16), _flat(Color(0.3, 0.05, 0.4)))
	var title: Label3D = _label(zone, SHOW_TITLE, center + Vector3(0.0, 0.0, 0.15), 0.0, 0.74, COLOR_GOLD, COLOR_RED)
	title.name = "ShowTitle"
	# Glühbirnen rund um das Schild, abwechselnd Material A und B (blinken im Wechsel).
	var bulb: SphereMesh = SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	bulb.radial_segments = 8
	bulb.rings = 4
	var count_x: int = 22
	var index: int = 0
	for i: int in range(count_x + 1):
		var x: float = lerpf(-sign_width * 0.5 - 0.08, sign_width * 0.5 + 0.08, float(i) / float(count_x))
		for dy: float in [-1.0, 1.0]:
			var pos: Vector3 = center + Vector3(x, dy * (sign_height * 0.5 + 0.08), 0.12)
			_add_bulb(zone, bulb, pos, index + (0 if dy < 0.0 else 1))
		index += 1


func _add_bulb(parent: Node3D, mesh: Mesh, pos: Vector3, index: int) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "Bulb"
	node.mesh = mesh
	node.position = pos
	node.material_override = _show.bulbs_a if index % 2 == 0 else _show.bulbs_b
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node, true)


## Kulissen und Requisiten als Deckung auf der Spielfläche.
func _build_set_pieces(zone: Node3D) -> void:
	# Zwei Kulissenwände.
	var flat_a: Vector3 = Vector3(-5.2, 1.1, 2.6)
	_solid(zone, "SetFlat", flat_a, Vector3(2.6, 2.2, 0.4), _pattern("bands", COLOR_GOLD, COLOR_ORANGE, 0.55, false), true, 24.0)
	_label_on_box(zone, "?", flat_a, 24.0, 0.21, 1.7, COLOR_RED, COLOR_WHITE)
	var flat_b: Vector3 = Vector3(5.4, 1.1, 0.0)
	_solid(zone, "SetFlat", flat_b, Vector3(2.6, 2.2, 0.4), _pattern("bands", COLOR_CYAN, Color(0.1, 0.4, 0.9), 0.55, false), true, -28.0)
	_label_on_box(zone, "!", flat_b, -28.0, 0.21, 1.7, COLOR_GOLD, COLOR_BLACK)
	# Kandidatenpulte vor der Showtreppe.
	for side: float in [-1.0, 1.0]:
		var pos: Vector3 = Vector3(side * 1.9, 0.55, 0.4)
		var yaw: float = -side * 12.0
		_solid(zone, "Podium", pos, Vector3(1.0, 1.1, 0.7), _flat(Color(0.95, 0.3, 0.1) if side < 0.0 else Color(0.2, 0.75, 0.3)), true, yaw)
		_deco(zone, "PodiumTop", pos + Vector3(0.0, 0.58, 0.0), Vector3(1.12, 0.07, 0.82), _flat(COLOR_WHITE), yaw)
		_deco(zone, "PodiumBuzzer", pos + Vector3(0.0, 0.68, 0.0), Vector3(0.3, 0.14, 0.3), _glow(COLOR_RED), yaw)
	# Zwei Studiokameras nahe der Brüstung.
	_add_studio_camera(zone, Vector3(-8.4, 0.0, _hz - 2.6), 150.0)
	_add_studio_camera(zone, Vector3(6.4, 0.0, _hz - 2.2), -160.0)
	# Hauptgewinn: ein mannshohes Geschenk links vor der Bühne.
	var gift: Vector3 = Vector3(-_hx + 3.8, 0.8, -2.2)
	_solid(zone, "GrandPrize", gift, Vector3(1.6, 1.6, 1.6), _flat(COLOR_CYAN), true, -18.0)
	_deco(zone, "GrandPrizeRibbon", gift, Vector3(1.64, 1.64, 0.3), _flat(COLOR_GOLD), -18.0)
	_deco(zone, "GrandPrizeRibbon", gift, Vector3(0.3, 1.64, 1.64), _flat(COLOR_GOLD), -18.0)
	_deco(zone, "GrandPrizeBow", gift + Vector3(0.0, 0.98, 0.0), Vector3(0.7, 0.36, 0.7), _flat(COLOR_GOLD), 27.0)
	_label_on_box(zone, "HAUPTGEWINN", gift + Vector3(0.0, 0.42, 0.0), -18.0, 0.83, 0.2, COLOR_WHITE, COLOR_BLACK)
	# Glücksrad rechts vor der Brüstung: eine Stellwand mit einer bunten Scheibe.
	_add_prize_wheel(zone, Vector3(_hx - 3.6, 0.0, 6.5), -38.0)


## Glücksrad: eine Stellwand als Deckung, auf beiden Seiten eine Scheibe mit acht bunten Feldern,
## ein Zeiger und der Schriftzug. pos ist die Mitte der Unterkante.
func _add_prize_wheel(zone: Node3D, pos: Vector3, yaw: float) -> void:
	var board_size: Vector3 = Vector3(2.4, 2.6, 0.4)
	var board_mat: StandardMaterial3D = _pattern("bands", Color(0.45, 0.12, 0.6), Color(0.33, 0.08, 0.46), 0.65, false)
	var board: StaticBody3D = _solid(zone, "PrizeWheel", pos + Vector3(0.0, board_size.y * 0.5, 0.0), board_size, board_mat, true, yaw)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.9, 1.9)
	var wheel_mat: StandardMaterial3D = StandardMaterial3D.new()
	wheel_mat.albedo_texture = _wheel_texture()
	wheel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	wheel_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	wheel_mat.roughness = 0.9
	quad.material = wheel_mat
	var face: float = board_size.z * 0.5
	for side: float in [-1.0, 1.0]:
		var disc: MeshInstance3D = MeshInstance3D.new()
		disc.name = "Wheel"
		disc.mesh = quad
		disc.position = Vector3(0.0, 0.25, side * (face + 0.02))
		disc.rotation_degrees = Vector3(0.0, 0.0 if side > 0.0 else 180.0, 0.0)
		disc.layers = _render_layer
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		board.add_child(disc, true)
		_child_box(board, "WheelHub", Vector3(0.0, 0.25, side * (face + 0.04)), Vector3(0.22, 0.22, 0.06), _flat(COLOR_GOLD), false)
		_child_box(board, "WheelPointer", Vector3(0.0, 1.2, side * (face + 0.05)), Vector3(0.14, 0.3, 0.08), _glow(COLOR_RED), false)
		var title: Label3D = _label(board, "GLÜCKSRAD", Vector3(0.0, -1.02, side * (face + 0.02)),
				0.0 if side > 0.0 else 180.0, 0.24, COLOR_GOLD, COLOR_BLACK)
		title.name = "WheelTitle"


## Runde Scheibe mit acht Feldern in den Farben der Scheinwerfer, außen durchsichtig.
func _wheel_texture() -> ImageTexture:
	if _textures.has("wheel"):
		return _textures["wheel"]
	var n: int = 128
	var colors: Array[Color] = [COLOR_RED, COLOR_GOLD, COLOR_CYAN, COLOR_WHITE, COLOR_STAGE_A, COLOR_ORANGE, Color(0.3, 0.8, 0.35), COLOR_WHITE]
	var image: Image = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var middle: float = float(n - 1) * 0.5
	for y: int in range(n):
		for x: int in range(n):
			var offset: Vector2 = Vector2(float(x) - middle, float(y) - middle) / middle
			var distance: float = offset.length()
			if distance > 1.0:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			elif distance > 0.93:
				image.set_pixel(x, y, COLOR_BLACK)
			else:
				var sector: int = int(floor((offset.angle() + PI) / TAU * float(colors.size()))) % colors.size()
				image.set_pixel(x, y, colors[sector])
	image.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_textures["wheel"] = texture
	return texture


func _add_studio_camera(zone: Node3D, pos: Vector3, yaw: float) -> void:
	var grey: StandardMaterial3D = _flat(Color(0.25, 0.26, 0.3))
	var body: StaticBody3D = _solid(zone, "StudioCamera", pos + Vector3(0.0, 0.2, 0.0), Vector3(1.1, 0.4, 1.1), grey, true, yaw)
	# Säule und Kamerakopf zählen zur Kollision (Deckung), aber nicht zur Navigation.
	_child_box(body, "Column", Vector3(0.0, 0.7, 0.0), Vector3(0.25, 1.0, 0.25), _flat(COLOR_BLACK), true)
	_child_box(body, "Head", Vector3(0.0, 1.45, 0.0), Vector3(0.6, 0.55, 1.0), grey, true)
	_child_box(body, "Lens", Vector3(0.0, 1.45, -0.6), Vector3(0.34, 0.34, 0.25), _flat(COLOR_BLACK), false)
	_child_box(body, "Tally", Vector3(0.0, 1.8, -0.3), Vector3(0.14, 0.12, 0.14), _show.warn_zone1, false)


## Lichttraverse über der Bühnenkante mit vier bunten, schwenkenden Scheinwerfern.
func _build_rig(zone: Node3D) -> void:
	var metal: StandardMaterial3D = _flat(Color(0.2, 0.2, 0.24))
	var rig_z: float = _stage_front_z + 2.2
	var rig_y: float = _height1 - 0.55
	var spot_reach: float = STAGE_HALF_WIDTH + 0.6
	var truss_length: float = spot_reach * 2.0 + 3.8
	_deco(zone, "Truss", Vector3(0.0, rig_y + 0.2, rig_z), Vector3(truss_length, 0.18, 0.18), metal)
	_deco(zone, "Truss", Vector3(0.0, rig_y + 0.2, rig_z + 0.5), Vector3(truss_length, 0.18, 0.18), metal)
	for i: int in range(SPOT_COLORS.size()):
		var x: float = lerpf(-spot_reach, spot_reach, float(i) / float(SPOT_COLORS.size() - 1))
		var pos: Vector3 = Vector3(x, rig_y, rig_z + 0.25)
		_deco(zone, "SpotCan", pos, Vector3(0.4, 0.4, 0.5), metal)
		_deco(zone, "SpotLens", pos + Vector3(0.0, -0.18, -0.2), Vector3(0.3, 0.1, 0.3), _glow(SPOT_COLORS[i]))
		var spot: SpotLight3D = SpotLight3D.new()
		spot.name = "StageSpot"
		spot.position = pos + Vector3(0.0, -0.25, -0.2)
		spot.light_color = SPOT_COLORS[i]
		spot.light_energy = StudioShow.SPOT_ENERGY
		spot.spot_range = 12.0
		spot.spot_angle = SPOT_ANGLE
		spot.spot_angle_attenuation = 0.5
		spot.spot_attenuation = 0.4
		spot.shadow_enabled = false
		zone.add_child(spot, true)
		spot.add_child(_light_cone(SPOT_COLORS[i]))
		var target: Vector3 = Vector3(x * 0.6, _stage_y, -_hz + STAGE_DEPTH * 0.55)
		spot.rotation = _look_rotation(spot.position, target)
		_show.spots.append(spot)
		_show.spot_targets.append(target)


## Sichtbarer Lichtkegel eines Scheinwerfers: durchsichtiger, leuchtender Kegelstumpf, der zum
## Boden hin ausblendet. Hängt als Kind am Scheinwerfer (der entlang -Z strahlt).
func _light_cone(color: Color) -> MeshInstance3D:
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 0.12 + tan(deg_to_rad(SPOT_ANGLE)) * SPOT_CONE_LENGTH
	cone.height = SPOT_CONE_LENGTH
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color.r, color.g, color.b, 0.16)
	material.albedo_texture = _fade_texture()
	material.texture_repeat = false
	cone.material = material
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Cone"
	mesh.mesh = cone
	# Zylinderachse (Y) auf die Strahlrichtung (-Z) legen, schmales Ende am Scheinwerfer.
	mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	mesh.position = Vector3(0.0, 0.0, -SPOT_CONE_LENGTH * 0.5)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


## Verlauf von deckend (oben) nach durchsichtig. Der Mantel eines Zylinders nutzt die obere
## Hälfte der Textur, deshalb endet der Verlauf in der Mitte.
func _fade_texture() -> ImageTexture:
	if _textures.has("fade"):
		return _textures["fade"]
	var n: int = 64
	var image: Image = Image.create_empty(4, n, false, Image.FORMAT_RGBA8)
	for y: int in range(n):
		var alpha: float = clampf(1.0 - float(y) / float(n / 2 - 1), 0.0, 1.0)
		for x: int in range(4):
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_textures["fade"] = texture
	return texture


## Studioleuchten an zwei Traversen über der Spielfläche: Die Decke wirkt wie ein Studiohimmel.
func _build_ceiling_lamps(zone: Node3D) -> void:
	var metal: StandardMaterial3D = _flat(Color(0.2, 0.2, 0.24))
	var lamp: StandardMaterial3D = _glow(Color(1.0, 0.94, 0.78))
	var y: float = _height1 - 0.35
	for z: float in [-1.5, 2.5, 6.5]:
		_deco(zone, "CeilingTruss", Vector3(0.0, y + 0.12, z), Vector3(_hx * 2.0 - 3.0, 0.14, 0.14), metal)
		for step: int in [-1, 0, 1]:
			_deco(zone, "CeilingLamp", Vector3(float(step) * _hx * 0.6, y, z), Vector3(2.0, 0.1, 0.55), lamp)


# ---------------------------------------------------------------------------------------------
# Publikum (nur Deko hinter der Brüstung)
# ---------------------------------------------------------------------------------------------

func _build_audience(root: Node3D) -> void:
	var dark: StandardMaterial3D = _flat(COLOR_AUDIENCE_DARK)
	var z0: float = _hz + WALL
	var z1: float = z0 + AUDIENCE_DEPTH
	var half_w: float = WINDOW_WIDTH * 0.5 + 0.4
	var top: float = _height1 - 0.2
	_deco(root, "AudienceFloor", Vector3(0.0, -0.1, (z0 + z1) * 0.5), Vector3(half_w * 2.0, 0.2, AUDIENCE_DEPTH), dark)
	_deco(root, "AudienceCeiling", Vector3(0.0, top + 0.1, (z0 + z1) * 0.5), Vector3(half_w * 2.0, 0.2, AUDIENCE_DEPTH), dark)
	# Rückwand mit Kollision: Dort enden Schüsse ins Publikum.
	_solid(root, "AudienceBack", Vector3(0.0, top * 0.5, z1 + 0.15), Vector3(half_w * 2.0 + 0.6, top, 0.3),
			_pattern("stripes", COLOR_AUDIENCE_DARK, Color(0.12, 0.1, 0.3), 0.8), false)
	for side: float in [-1.0, 1.0]:
		_solid(root, "AudienceSide", Vector3(side * (half_w + 0.15), top * 0.5, (z0 + z1) * 0.5),
				Vector3(0.3, top, AUDIENCE_DEPTH), dark, false)
	# Sperre nur für den Spieler: über der Brüstung, Schüsse fliegen ins Publikum.
	_add_player_block(root, "AudienceBlock", Vector3(0.0, _height1 * 0.5, _hz + WALL * 0.5),
			Vector3(WINDOW_WIDTH, _height1, 0.3))
	# Handlauf der Brüstung.
	_deco(root, "BarrierRail", Vector3(0.0, BARRIER_HEIGHT + 0.04, _hz + WALL * 0.5),
			Vector3(WINDOW_WIDTH, 0.08, WALL + 0.12), _flat(COLOR_GOLD))

	# Drei ansteigende Ränge mit Zuschauern aus Quadern.
	var body_mesh: BoxMesh = BoxMesh.new()
	body_mesh.size = Vector3(0.55, 0.7, 0.35)
	var head_mesh: BoxMesh = BoxMesh.new()
	head_mesh.size = Vector3(0.32, 0.32, 0.32)
	var tier_mat: StandardMaterial3D = _flat(Color(0.16, 0.12, 0.32))
	for row: int in range(3):
		var tier_height: float = 0.7 + 0.5 * float(row)
		var tier_z0: float = z0 + 0.5 + 1.3 * float(row)
		_deco(root, "Tier", Vector3(0.0, tier_height * 0.5, (tier_z0 + z1) * 0.5),
				Vector3(half_w * 2.0, tier_height, z1 - tier_z0), tier_mat)
		var seats: int = 14
		for seat: int in range(seats):
			var x: float = lerpf(-half_w + 1.0, half_w - 1.0, float(seat) / float(seats - 1)) + _rng.randf_range(-0.15, 0.15)
			if row % 2 == 1:
				x += 0.35
			var person: Node3D = Node3D.new()
			person.name = "Fan"
			person.position = Vector3(x, tier_height, tier_z0 + 0.6)
			var torso: MeshInstance3D = MeshInstance3D.new()
			torso.name = "Body"
			torso.mesh = body_mesh
			torso.position = Vector3(0.0, 0.35, 0.0)
			torso.material_override = _flat(AUDIENCE_SHIRTS[_rng.randi_range(0, AUDIENCE_SHIRTS.size() - 1)])
			person.add_child(torso)
			var head: MeshInstance3D = MeshInstance3D.new()
			head.name = "Head"
			head.mesh = head_mesh
			head.position = Vector3(0.0, 0.88, 0.0)
			head.material_override = _flat(AUDIENCE_SKIN[_rng.randi_range(0, AUDIENCE_SKIN.size() - 1)])
			person.add_child(head)
			root.add_child(person, true)
			_show.audience.append(person)

	# Leuchtschild "APPLAUS" über dem Fenster, zum Studio hin lesbar.
	var sign_pos: Vector3 = Vector3(0.0, (WINDOW_TOP + _height1) * 0.5, _hz - 0.08)
	_deco(root, "ApplauseSign", sign_pos, Vector3(4.2, 0.62, 0.12), _flat(COLOR_BLACK))
	_show.applause_label = _label(root, "APPLAUS", sign_pos + Vector3(0.0, 0.0, -0.08), 180.0, 0.5,
			StudioShow.APPLAUSE_OFF, COLOR_BLACK)
	_show.applause_label.name = "ApplauseLabel"


# ---------------------------------------------------------------------------------------------
# Die kaufbaren Räume (Zonen 2 bis 5)
# ---------------------------------------------------------------------------------------------

## Baut einen Raum aus _rooms: Boden, Decke, Wände, zwei Zombie-Eingänge, Schilder, Requisiten.
## Die Wand zur Bühne gehört zur Zone 1. Die Wand zwischen den beiden Räumen einer Seite baut der
## vordere Raum unter partitions: Sie bleibt sichtbar, auch wenn nur der hintere Raum offen ist.
func _build_room(zone_node: Node3D, partitions: Node3D, entrances: Node3D, room: Dictionary) -> void:
	var zone: int = int(room["zone"])
	var side: float = float(room["side"])
	var front: bool = int(room["row"]) == 0
	var inner: float = float(room["inner_x"])
	var outer: float = float(room["outer_x"])
	var min_z: float = float(room["min_z"])
	var max_z: float = float(room["max_z"])
	var look: Dictionary = _room_look(String(room["key"]))
	var floor_mat: StandardMaterial3D = look["floor"]
	var wall_mat: StandardMaterial3D = look["wall"]
	var ceiling_mat: StandardMaterial3D = _flat(COLOR_CEILING)
	var far_x: float = outer + side * WALL
	var low_x: float = minf(inner, far_x)
	var high_x: float = maxf(inner, far_x)

	# Boden und Decke reichen unter die eigenen Außenwände. Der Streifen unter der gemeinsamen
	# Wand gehört zu partitions.
	var floor_min_z: float = min_z if front else min_z - WALL
	var floor_max_z: float = max_z + WALL if front else max_z
	_solid_span(zone_node, "Floor", Vector3(inner, -FLOOR_THICKNESS, floor_min_z), Vector3(far_x, 0.0, floor_max_z), floor_mat, true)
	_solid_span(zone_node, "Ceiling", Vector3(inner, _height2, floor_min_z), Vector3(far_x, _height2 + CEILING, floor_max_z), ceiling_mat, false)

	# Stirnwand (Süden beim vorderen, Norden beim hinteren Raum) mit Zombie-Eingang. Der hintere
	# Raum ragt nach Norden über die Bühne hinaus: Seine Stirnwand deckt auch diese Ecke ab.
	var end_dir: float = 1.0 if front else -1.0
	var end_z: float = max_z if front else min_z
	var end_mouth: Vector3 = Vector3(inner + side * float(room["end_offset"]), 0.0, end_z)
	var end_from: float = inner if front else side * _hx
	_wall(zone_node, "WallEnd", true, end_z + end_dir * WALL * 0.5, minf(end_from, far_x), maxf(end_from, far_x), _height2,
			[_opening(end_mouth.x, ENTRANCE_WIDTH, 0.0, ENTRANCE_HEIGHT)], wall_mat)
	if not front and min_z < -_hz - WALL:
		_wall(zone_node, "WallInner", false, side * (_hx + WALL * 0.5), min_z, -_hz - WALL, _height2, [], wall_mat)

	# Außenwand mit Zombie-Eingang.
	var side_z: float = max_z - float(room["side_offset"]) if front else min_z + float(room["side_offset"])
	var side_mouth: Vector3 = Vector3(outer, 0.0, side_z)
	_wall(zone_node, "WallOuter", false, outer + side * WALL * 0.5, min_z, max_z, _height2,
			[_opening(side_mouth.z, ENTRANCE_WIDTH, 0.0, ENTRANCE_HEIGHT)], wall_mat)

	# Wand zwischen den beiden Räumen dieser Seite mit der Öffnung der Verbindungstür.
	var link_x: float = float(room["link_x"])
	if front:
		var partition_mat: StandardMaterial3D = _flat(COLOR_DARK_METAL)
		_wall(partitions, "Partition", true, min_z - WALL * 0.5, low_x, high_x, _height2,
				[_opening(link_x, DOOR_WIDTH, 0.0, DOOR_HEIGHT)], partition_mat)
		_solid_span(partitions, "PartitionFloor", Vector3(inner, -FLOOR_THICKNESS, min_z - WALL), Vector3(far_x, 0.0, min_z), partition_mat, true)
		_solid_span(partitions, "PartitionCeiling", Vector3(inner, _height2, min_z - WALL), Vector3(far_x, _height2 + CEILING, min_z), ceiling_mat, false)

	# Verkleidung in den Farben des Raums: auf der Rückseite der Bühnenwand und auf seiner Seite
	# der gemeinsamen Wand. Darüber je ein Schild, wohin die Tür führt.
	_clad(zone_node, false, inner, inner + side * CLADDING, min_z, max_z, float(room["door_z"]), wall_mat)
	var stage_sign: Vector3 = Vector3(inner + side * (CLADDING + 0.03), DOOR_HEIGHT + 0.62, float(room["door_z"]))
	_deco(zone_node, "SignBoard", stage_sign, Vector3(0.06, 0.7, 3.0), _flat(COLOR_BLACK))
	_label(zone_node, "<< BÜHNE" if side > 0.0 else "BÜHNE >>", stage_sign + Vector3(side * 0.04, 0.0, 0.0), 90.0 * side, 0.42, COLOR_WHITE, COLOR_BLACK)
	var neighbour: Dictionary = _neighbour_of(room)
	if not neighbour.is_empty():
		var face_z: float = min_z if front else max_z
		var into: float = 1.0 if front else -1.0
		_clad(zone_node, true, face_z, face_z + into * CLADDING, low_x, high_x, link_x, wall_mat)
		var link_sign: Vector3 = Vector3(link_x, DOOR_HEIGHT + 0.62, face_z + into * (CLADDING + 0.03))
		_deco(zone_node, "SignBoard", link_sign, Vector3(3.6, 0.7, 0.06), _flat(COLOR_BLACK))
		_label(zone_node, String(neighbour["name"]).to_upper(), link_sign + Vector3(0.0, 0.0, into * 0.04),
				0.0 if front else 180.0, 0.42, neighbour["accent"], COLOR_BLACK)

	var ids: Array = room["entrances"]
	_add_entrance(entrances, String(ids[0]), zone, end_mouth, Vector3(0.0, 0.0, end_dir), "AUFTRITT ZOMBIES")
	_add_entrance(entrances, String(ids[1]), zone, side_mouth, Vector3(side, 0.0, 0.0), "AUFTRITT ZOMBIES")

	match String(room["key"]):
		"backstage":
			_build_backstage_props(zone_node, room)
		"canteen":
			_build_canteen_props(zone_node, room)
		"wardrobe":
			_build_wardrobe_props(zone_node, room)
		"control_room":
			_build_control_room_props(zone_node, room)


## Aussehen eines Raums: Boden- und Wandmaterial, Farbe und Stärke seiner Deckenlichter.
func _room_look(key: String) -> Dictionary:
	match key:
		"canteen":
			return {
				"floor": _pattern("checker", COLOR_CANTEEN_FLOOR_A, COLOR_CANTEEN_FLOOR_B, 1.0),
				"wall": _pattern("checker", COLOR_CANTEEN_WALL_A, COLOR_CANTEEN_WALL_B, 0.6),
				"light": Color(1.0, 0.95, 0.78), "energy": 2.2,
			}
		"wardrobe":
			return {
				"floor": _pattern("stripes", COLOR_WARDROBE_FLOOR_A, COLOR_WARDROBE_FLOOR_B, 0.75),
				"wall": _pattern("stripes", COLOR_WARDROBE_WALL_A, COLOR_WARDROBE_WALL_B, 0.6),
				"light": Color(1.0, 0.82, 0.86), "energy": 2.2,
			}
		"control_room":
			return {
				"floor": _pattern("checker", COLOR_CONTROL_FLOOR_A, COLOR_CONTROL_FLOOR_B, 1.5),
				"wall": _pattern("bands", COLOR_CONTROL_WALL_A, COLOR_CONTROL_WALL_B, 0.8),
				"light": Color(0.5, 0.7, 1.0), "energy": 2.8,
			}
	return {
		"floor": _pattern("checker", COLOR_BACK_FLOOR_A, COLOR_BACK_FLOOR_B, 2.0),
		"wall": _pattern("bands", COLOR_BACK_WALL_A, COLOR_BACK_WALL_B, 1.25),
		"light": Color(0.62, 0.76, 1.0), "energy": 2.8,
	}


## Verkleidung auf der Raumseite einer Wand, mit Ausschnitt für eine Tür. along_x: Die Wand
## verläuft entlang X. face_a und face_b sind Vorder- und Rückseite der Verkleidung auf der
## anderen Achse, from und to ihre Enden entlang der Wand, door_center die Mitte der Türöffnung.
func _clad(parent: Node3D, along_x: bool, face_a: float, face_b: float, from: float, to: float,
		door_center: float, material: Material) -> void:
	var door_min: float = door_center - DOOR_WIDTH * 0.5
	var door_max: float = door_center + DOOR_WIDTH * 0.5
	var pieces: Array[Vector3] = [Vector3(from, door_min, 0.0), Vector3(door_max, to, 0.0), Vector3(door_min, door_max, DOOR_HEIGHT)]
	for piece: Vector3 in pieces:
		if piece.y - piece.x < 0.01:
			continue
		if along_x:
			_deco_span(parent, "Cladding", Vector3(piece.x, piece.z, face_a), Vector3(piece.y, _height2, face_b), material)
		else:
			_deco_span(parent, "Cladding", Vector3(face_a, piece.z, piece.x), Vector3(face_b, _height2, piece.y), material)


## Quader mit Kollision in einem Raum. u, v wie bei _room_point, size = (Maß entlang u, Höhe,
## Maß entlang v), base_y = Unterkante. Die Drehung wird in den westlichen Räumen gespiegelt.
func _room_box(zone: Node3D, room: Dictionary, node_name: String, u: float, v: float, size: Vector3,
		material: Material, nav: bool = true, yaw_deg: float = 0.0, base_y: float = 0.0) -> StaticBody3D:
	return _solid(zone, node_name, _room_point(room, u, v, base_y + size.y * 0.5), size, material, nav,
			yaw_deg * float(room["side"]))


## Backstage: Kisten, Flightcases, Kabeltrommel, Requisitenregal. Die Raummitte bleibt frei.
func _build_backstage_props(zone: Node3D, room: Dictionary) -> void:
	var crate: StandardMaterial3D = _pattern("bands", COLOR_WOOD_A, COLOR_WOOD_B, 0.2, false)
	var crate_dark: StandardMaterial3D = _pattern("stripes", COLOR_WOOD_B, Color(0.36, 0.23, 0.1), 0.2, false)
	var case_mat: StandardMaterial3D = _flat(Color(0.1, 0.1, 0.12))
	var metal: StandardMaterial3D = _flat(COLOR_STEEL)
	# Kistenstapel nördlich der Tür.
	_room_box(zone, room, "Crate", 3.2, 1.5, Vector3(1.2, 1.2, 1.2), crate, true, 8.0)
	_room_box(zone, room, "Crate", 4.5, 1.9, Vector3(1.0, 1.0, 1.0), crate_dark, true, -14.0)
	_room_box(zone, room, "Crate", 3.3, 1.5, Vector3(0.7, 0.7, 0.7), crate_dark, false, 30.0, 1.2)
	# Flightcases vor der Südwand.
	var flight_case: StaticBody3D = _room_box(zone, room, "FlightCase", 9.6, 10.9, Vector3(2.2, 0.9, 0.9), case_mat, true, 18.0)
	_child_box(flight_case, "Edge", Vector3(0.0, 0.46, 0.0), Vector3(2.26, 0.05, 0.96), metal, false)
	_room_box(zone, room, "FlightCase", 9.8, 10.9, Vector3(1.2, 0.6, 0.8), case_mat, false, 34.0, 0.9)
	# Kisten in der äußeren Hälfte und südlich der Tür.
	_room_box(zone, room, "Crate", 10.6, 4.4, Vector3(1.2, 1.2, 1.2), crate_dark, true, -6.0)
	_room_box(zone, room, "Crate", 10.9, 5.6, Vector3(1.0, 1.0, 1.0), crate, true, 22.0)
	_room_box(zone, room, "Crate", 1.5, 9.0, Vector3(0.9, 0.9, 0.9), crate, true, 12.0)
	_add_cable_drum(zone, _room_point(room, 2.2, 10.9))
	# Requisitenregal an der Außenwand und ein Scheinwerfer auf Stativ in der Ecke.
	_add_shelf(zone, room, "PropShelf", 2.9, 3.2, _flat(COLOR_WOOD_B), AUDIENCE_SHIRTS)
	var stand: StaticBody3D = _room_box(zone, room, "LampStand", 12.9, 11.2, Vector3(0.5, 2.2, 0.5), null)
	_child_box(stand, "Pole", Vector3.ZERO, Vector3(0.1, 2.2, 0.1), _flat(COLOR_BLACK), false)
	_child_box(stand, "Foot", Vector3(0.0, -1.06, 0.0), Vector3(0.5, 0.08, 0.5), _flat(COLOR_BLACK), false)
	_child_box(stand, "Head", Vector3(0.0, 1.0, 0.0), Vector3(0.5, 0.4, 0.4), _flat(COLOR_DARK_METAL), false)
	_child_box(stand, "Lens", Vector3(-float(room["side"]) * 0.26, 1.0, 0.0), Vector3(0.04, 0.3, 0.3), _glow(Color(1.0, 0.92, 0.7)), false)


## Kantine: Essensausgabe mit Tafel, Stehtische, Automaten, Tablettwagen, Getränkekisten.
func _build_canteen_props(zone: Node3D, room: Dictionary) -> void:
	var side: float = float(room["side"])
	var steel: StandardMaterial3D = _flat(COLOR_STEEL)
	var cream: StandardMaterial3D = _flat(Color(0.95, 0.92, 0.82))
	# Essensausgabe an der Außenwand, daneben der Kühlschrank.
	var counter: StaticBody3D = _room_box(zone, room, "Counter", 13.45, 3.6, Vector3(1.1, 1.1, 4.4),
			_pattern("bands", Color(0.9, 0.35, 0.15), COLOR_WHITE, 0.275, false))
	_child_box(counter, "CounterTop", Vector3(0.0, 0.59, 0.0), Vector3(1.24, 0.08, 4.5), steel, false)
	for i: int in range(3):
		_child_box(counter, "Pot", Vector3(0.0, 0.8, -1.3 + 1.3 * float(i)), Vector3(0.6, 0.34, 0.6), steel, false)
		_child_box(counter, "Soup", Vector3(0.0, 0.98, -1.3 + 1.3 * float(i)), Vector3(0.5, 0.02, 0.5),
				_flat(Color(0.45, 0.75, 0.25) if i != 1 else Color(0.8, 0.25, 0.15)), false)
	var board: Vector3 = _room_point(room, Balance.ZONE2_SIZE.x - 0.05, 3.6, 2.75)
	_deco(zone, "MenuBoard", board, Vector3(0.08, 1.5, 3.8), _flat(Color(0.08, 0.16, 0.12)))
	_label(zone, "HEUTE:", board + Vector3(-side * 0.05, 0.36, 0.0), -90.0 * side, 0.32, COLOR_WHITE, COLOR_BLACK)
	_label(zone, "KOPFSALAT", board + Vector3(-side * 0.05, -0.2, 0.0), -90.0 * side, 0.46, Color(0.55, 1.0, 0.45), COLOR_BLACK)
	var fridge: StaticBody3D = _room_box(zone, room, "Fridge", 13.5, 0.6, Vector3(0.9, 2.0, 0.9), _flat(COLOR_WHITE))
	_child_box(fridge, "Handle", Vector3(-side * 0.47, 0.2, 0.3), Vector3(0.05, 0.6, 0.06), steel, false)
	# Stehtische, locker im Raum verteilt. Die Mitte bleibt frei.
	var table_spots: Array[Vector2] = [Vector2(4.6, 8.4), Vector2(8.6, 9.6), Vector2(9.7, 5.4), Vector2(3.7, 2.6)]
	for spot: Vector2 in table_spots:
		var table: StaticBody3D = _add_round_prop(zone, "BarTable", _room_point(room, spot.x, spot.y), 0.5, 1.1)
		_child_cylinder(table, "Top", 0.52, 0.5, 0.08, cream)
		_child_cylinder(table, "Leg", 0.0, 0.07, 1.0, steel)
		_child_cylinder(table, "Foot", -0.52, 0.32, 0.06, steel)
		_child_box(table, "Ketchup", Vector3(0.12, 0.66, 0.05), Vector3(0.09, 0.2, 0.09), _flat(COLOR_RED), false)
		_child_box(table, "Mustard", Vector3(-0.1, 0.66, -0.08), Vector3(0.09, 0.2, 0.09), _flat(COLOR_GOLD), false)
	# Zwei Automaten an der Wand zur Bühne.
	var machines: Array = [["SNACKS", COLOR_ORANGE, 9.5], ["BRAUSE", COLOR_CYAN, 10.7]]
	for machine: Array in machines:
		var body: StaticBody3D = _room_box(zone, room, "VendingMachine", 0.5, float(machine[2]), Vector3(0.9, 2.0, 1.0), _flat(Color(0.16, 0.16, 0.2)))
		_child_box(body, "Window", Vector3(side * 0.46, 0.1, 0.0), Vector3(0.04, 1.3, 0.8), _glow(machine[1]), false)
		_child_box(body, "Slot", Vector3(side * 0.46, -0.78, 0.0), Vector3(0.04, 0.22, 0.6), _flat(COLOR_BLACK), false)
		_label(body, String(machine[0]), Vector3(side * 0.47, 0.87, 0.0), 90.0 * side, 0.2, COLOR_WHITE, COLOR_BLACK)
	# Tablettwagen und Getränkekisten.
	var trolley: StaticBody3D = _room_box(zone, room, "TrayTrolley", 2.0, 1.2, Vector3(0.7, 1.5, 1.1), null, true, 10.0)
	for post_x: float in [-0.32, 0.32]:
		for post_z: float in [-0.52, 0.52]:
			_child_box(trolley, "Post", Vector3(post_x, 0.0, post_z), Vector3(0.05, 1.5, 0.05), steel, false)
	for i: int in range(5):
		_child_box(trolley, "Tray", Vector3(0.0, -0.6 + 0.3 * float(i), 0.0), Vector3(0.66, 0.04, 1.06),
				_flat(AUDIENCE_SHIRTS[i % AUDIENCE_SHIRTS.size()]), false)
	var drinks: StandardMaterial3D = _pattern("checker", Color(0.85, 0.15, 0.15), Color(0.95, 0.8, 0.2), 0.15, false)
	_room_box(zone, room, "DrinkCrates", 12.9, 11.3, Vector3(1.0, 1.2, 1.0), drinks, true, 6.0)
	_room_box(zone, room, "DrinkCrates", 11.7, 11.35, Vector3(1.0, 0.9, 1.0), drinks, true, -8.0)


## Garderobe: Kleiderständer, Schminktische mit Spiegeln, Paravent, Schrank, Hutschachteln.
func _build_wardrobe_props(zone: Node3D, room: Dictionary) -> void:
	var side: float = float(room["side"])
	var depth: float = Balance.ZONE2_SIZE.z
	# Kleiderständer mit Kostümen: einer an der Nordwand, einer frei im Raum.
	_add_costume_rack(zone, _room_point(room, 3.2, 0.5), 0.0)
	_add_costume_rack(zone, _room_point(room, 4.8, 4.8), 90.0)
	# Schminktische: an der Außenwand und an der Wand zum Nachbarraum.
	_add_makeup_table(zone, _room_point(room, Balance.ZONE2_SIZE.x - 0.42, 8.0), false, Vector3(side, 0.0, 0.0))
	_add_makeup_table(zone, _room_point(room, 11.0, depth - 0.46), true, Vector3(0.0, 0.0, 1.0))
	# Paravent aus drei Stellwänden im Zickzack.
	var screen_mat: StandardMaterial3D = _pattern("stripes", Color(0.3, 0.75, 0.7), COLOR_WHITE, 0.15, false)
	for i: int in range(3):
		var zig: float = 1.0 if i % 2 == 0 else -1.0
		_room_box(zone, room, "FoldingScreen", 9.2 + 1.08 * float(i), 4.5, Vector3(1.25, 1.9, 0.1), screen_mat, true, 24.0 * zig)
	# Garderobenschrank an der Wand zur Bühne, nördlich der Tür.
	var closet: StaticBody3D = _room_box(zone, room, "Closet", 0.6, 3.6, Vector3(1.0, 2.2, 2.6), _pattern("stripes", COLOR_WOOD_A, COLOR_WOOD_B, 0.65, false))
	_child_box(closet, "Gap", Vector3(side * 0.5, 0.0, 0.0), Vector3(0.03, 2.1, 0.04), _flat(COLOR_BLACK), false)
	for knob_z: float in [-0.14, 0.14]:
		_child_box(closet, "Knob", Vector3(side * 0.53, 0.0, knob_z), Vector3(0.06, 0.2, 0.06), _flat(COLOR_GOLD), false)
	# Hutschachteln neben der Verbindungstür und ein goldener Stern an der Nordwand.
	var boxes: StaticBody3D = _add_round_prop(zone, "HatBoxes", _room_point(room, 3.4, depth - 0.9), 0.5, 1.0)
	_child_cylinder(boxes, "Box", -0.25, 0.5, 0.5, _pattern("stripes", COLOR_STAGE_A, COLOR_WHITE, 0.12, false))
	_child_cylinder(boxes, "Box", 0.24, 0.4, 0.48, _pattern("stripes", COLOR_CYAN, COLOR_WHITE, 0.12, false))
	var star: Vector3 = _room_point(room, 5.4, 0.07, 3.4)
	_deco(zone, "StarPlate", star, Vector3(2.6, 0.7, 0.06), _flat(COLOR_BLACK))
	_label(zone, "NUR FÜR STARS", star + Vector3(0.0, 0.0, 0.04), 0.0, 0.34, COLOR_GOLD, COLOR_BLACK)


## Regieraum: Monitorwand, Regiepult, Serverschränke, Bandarchiv.
func _build_control_room_props(zone: Node3D, room: Dictionary) -> void:
	var side: float = float(room["side"])
	var dark: StandardMaterial3D = _flat(Color(0.1, 0.11, 0.15))
	# Monitorwand an der Nordwand: zwei Reihen leuchtender Bildschirme.
	var wall_mid: Vector3 = _room_point(room, 4.2, 0.07, 2.65)
	_deco(zone, "MonitorWall", wall_mid, Vector3(6.6, 2.3, 0.1), _flat(COLOR_BLACK))
	var screens: Array[Color] = [
		Color(0.25, 0.75, 1.0), Color(0.95, 0.3, 0.6), Color(0.4, 1.0, 0.5), Color(1.0, 0.85, 0.3),
		Color(1.0, 0.5, 0.15), Color(0.6, 0.5, 1.0), Color(0.2, 0.9, 0.85), Color(0.9, 0.9, 0.95),
	]
	for i: int in range(screens.size()):
		var column: float = float(i % 4) - 1.5
		var row: float = 0.5 if i < 4 else -0.5
		_deco(zone, "Screen", wall_mid + Vector3(column * 1.58, row * 1.06, 0.06), Vector3(1.42, 0.9, 0.04), _glow(screens[i]))
	var on_air: Vector3 = wall_mid + Vector3(0.0, 1.55, 0.0)
	_deco(zone, "OnAirSign", on_air, Vector3(3.4, 0.56, 0.1), _flat(Color(0.25, 0.02, 0.03)))
	_label(zone, "AUF SENDUNG", on_air + Vector3(0.0, 0.0, 0.06), 0.0, 0.36, Color(1.0, 0.25, 0.2), COLOR_BLACK)
	# Regiepult davor: Hinter dem Pult bleibt ein Gang, der an beiden Enden offen ist.
	var desk: StaticBody3D = _room_box(zone, room, "ControlDesk", 4.2, 2.4, Vector3(5.2, 1.0, 1.1), _flat(COLOR_DARK_METAL))
	_child_box(desk, "Panel", Vector3(0.0, 0.53, 0.08), Vector3(5.0, 0.06, 0.8), dark, false)
	_child_box(desk, "Riser", Vector3(0.0, 0.75, -0.45), Vector3(5.2, 0.5, 0.2), dark, true)
	for i: int in range(12):
		var x: float = -2.2 + 0.4 * float(i)
		_child_box(desk, "Fader", Vector3(x, 0.58, 0.2 if i % 3 != 0 else 0.0), Vector3(0.22, 0.05, 0.12),
				_glow(screens[i % screens.size()]), false)
	for i: int in range(4):
		_child_box(desk, "Preview", Vector3(-1.8 + 1.2 * float(i), 0.78, -0.34), Vector3(0.8, 0.34, 0.03), _glow(screens[(i + 3) % screens.size()]), false)
	# Serverschränke: zwei frei im Raum, zwei an der Wand zur Bühne südlich der Tür.
	var rack_spots: Array[Vector2] = [Vector2(9.6, 8.0), Vector2(10.7, 8.0), Vector2(0.55, 10.5), Vector2(0.55, 11.45)]
	for i: int in range(rack_spots.size()):
		var rack: StaticBody3D = _room_box(zone, room, "ServerRack", rack_spots[i].x, rack_spots[i].y, Vector3(0.9, 2.1, 0.9), dark)
		var led: StandardMaterial3D = _glow(Color(0.3, 1.0, 0.5) if i % 2 == 0 else Color(0.2, 0.8, 1.0))
		for strip: int in range(5):
			var y: float = -0.8 + 0.4 * float(strip)
			if i < 2:
				_child_box(rack, "Led", Vector3(0.0, y, -0.46), Vector3(0.7, 0.06, 0.03), led, false)
				_child_box(rack, "Led", Vector3(0.0, y, 0.46), Vector3(0.7, 0.06, 0.03), led, false)
			else:
				_child_box(rack, "Led", Vector3(side * 0.46, y, 0.0), Vector3(0.03, 0.06, 0.7), led, false)
	# Bandarchiv an der Außenwand und eine Kabeltrommel.
	_add_shelf(zone, room, "TapeShelf", 9.0, 3.4, dark, screens)
	_add_cable_drum(zone, _room_point(room, 11.6, 10.9))


## Regal an der Außenwand eines Raums: v ist seine Mitte, length sein Maß entlang der Wand.
## Auf der Raumseite stehen drei Reihen bunter Dinge.
func _add_shelf(zone: Node3D, room: Dictionary, node_name: String, v: float, length: float, frame: Material, colors: Array[Color]) -> void:
	var side: float = float(room["side"])
	var body: StaticBody3D = _room_box(zone, room, node_name, Balance.ZONE2_SIZE.x - 0.45, v, Vector3(0.9, 2.1, length), frame)
	var count: int = int(floor(length / 0.4))
	for shelf: int in range(3):
		_child_box(body, "Board", Vector3(-side * 0.47, -0.82 + 0.7 * float(shelf), 0.0), Vector3(0.06, 0.06, length), _flat(COLOR_BLACK), false)
		for i: int in range(count):
			var z: float = -length * 0.5 + 0.4 * (float(i) + 0.5) + (length - 0.4 * float(count)) * 0.5
			var tall: float = 0.3 + 0.08 * float((i + shelf) % 3)
			_child_box(body, "Item", Vector3(-side * 0.48, -0.79 + 0.7 * float(shelf) + tall * 0.5, z), Vector3(0.08, tall, 0.3),
					_flat(colors[(i + shelf * 2) % colors.size()]), false)


## Kleiderständer mit Kostümen. pos ist die Mitte der Unterkante, yaw 0 = entlang X.
func _add_costume_rack(zone: Node3D, pos: Vector3, yaw: float) -> void:
	var body: StaticBody3D = _solid(zone, "CostumeRack", pos + Vector3(0.0, 0.95, 0.0), Vector3(3.0, 1.9, 0.6), null, true, yaw)
	_child_box(body, "Rail", Vector3(0.0, 0.9, 0.0), Vector3(3.0, 0.06, 0.06), _flat(COLOR_STEEL), false)
	for post: float in [-1.47, 1.47]:
		_child_box(body, "Post", Vector3(post, 0.0, 0.0), Vector3(0.06, 1.9, 0.06), _flat(COLOR_STEEL), false)
	for i: int in range(7):
		var costume: Color = AUDIENCE_SHIRTS[i % AUDIENCE_SHIRTS.size()]
		_child_box(body, "Costume", Vector3(-1.2 + 0.4 * float(i), 0.25, 0.0), Vector3(0.3, 1.25, 0.5), _flat(costume), false)


## Schminktisch mit Spiegel und Glühbirnen an einer Wand. center ist die Mitte der Unterkante,
## along_x: Der Tisch steht entlang X. to_wall zeigt vom Tisch zur Wand.
func _add_makeup_table(zone: Node3D, center: Vector3, along_x: bool, to_wall: Vector3) -> void:
	var along: Vector3 = Vector3(1.0, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, 1.0)
	var depth: Vector3 = to_wall.abs()
	_solid(zone, "MakeupTable", center + Vector3(0.0, 0.45, 0.0), _abs_size(along * 3.0 + Vector3.UP * 0.9 + depth * 0.8), _flat(COLOR_STAGE_A), true)
	var mirror: Vector3 = center + Vector3(0.0, 1.75, 0.0) + to_wall * 0.36
	_deco(zone, "MirrorFrame", mirror, _abs_size(along * 2.8 + Vector3.UP * 1.4 + depth * 0.08), _flat(COLOR_GOLD))
	_deco(zone, "Mirror", mirror - to_wall * 0.03, _abs_size(along * 2.5 + Vector3.UP * 1.1 + depth * 0.08), _glow(Color(0.7, 0.88, 1.0)))
	var bulb: SphereMesh = SphereMesh.new()
	bulb.radius = 0.08
	bulb.height = 0.16
	bulb.radial_segments = 8
	bulb.rings = 4
	for i: int in range(7):
		_add_bulb(zone, bulb, mirror + along * (-1.2 + 0.4 * float(i)) + Vector3(0.0, 0.66, 0.0) - to_wall * 0.08, i)


func _add_cable_drum(zone: Node3D, pos: Vector3) -> void:
	var body: StaticBody3D = _add_round_prop(zone, "CableDrum", pos, 0.7, 1.0)
	var plate: StandardMaterial3D = _pattern("stripes", COLOR_WOOD_A, COLOR_WOOD_B, 0.15, false)
	_child_cylinder(body, "Plate", -0.44, 0.7, 0.12, plate)
	_child_cylinder(body, "Plate", 0.44, 0.7, 0.12, plate)
	_child_cylinder(body, "Coil", 0.0, 0.45, 0.8, _flat(COLOR_BLACK))


## Runder Körper mit Kollision (Zylinder, zählt zur Navigation), noch ohne Mesh. pos ist die Mitte
## der Unterkante.
func _add_round_prop(zone: Node3D, node_name: String, pos: Vector3, radius: float, height: float) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.collision_layer = Balance.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos + Vector3(0.0, height * 0.5, 0.0)
	body.add_to_group(GROUP_NAV_SOURCE)
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = cylinder
	body.add_child(shape)
	zone.add_child(body, true)
	return body


## Zylinder-Mesh an einem Körper, y ist seine Mitte über der Körpermitte.
func _child_cylinder(body: Node3D, node_name: String, y: float, radius: float, height: float, material: Material) -> void:
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 12
	cylinder.rings = 1
	cylinder.material = material
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = cylinder
	mesh.position = Vector3(0.0, y, 0.0)
	mesh.layers = _render_layer
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh, true)


# ---------------------------------------------------------------------------------------------
# Türen, Eingänge
# ---------------------------------------------------------------------------------------------

## Tür, die den Raum room verkauft. pos ist die Mitte der Unterkante, yaw 0 = Breite entlang X.
## back (leer oder ein Raum): der kaufbare Raum auf der anderen Seite einer Verbindungstür.
func _add_door(parent: Node3D, node_name: String, pos: Vector3, yaw_deg: float, room: Dictionary, back: Dictionary) -> StaticBody3D:
	var door: StaticBody3D = Door.new()
	door.name = node_name
	door.set("size", Vector3(DOOR_WIDTH, DOOR_HEIGHT, DOOR_THICKNESS))
	door.set("zone", int(room["zone"]))
	door.set("zone_name", String(room["name"]))
	door.set("cost", int(room["cost"]))
	if not back.is_empty():
		door.set("back_zone", int(back["zone"]))
		door.set("back_zone_name", String(back["name"]))
		door.set("back_cost", int(back["cost"]))
	door.position = pos
	door.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(door)
	return door


## Verbindungstüren in der Wand zwischen den beiden Räumen einer Seite. Jede verkauft zuerst den
## hinteren Raum (solange nur der vordere offen ist) und sonst den vorderen.
func _build_links(parent: Node3D) -> Array[Node3D]:
	var links: Array[Node3D] = []
	for room: Dictionary in _rooms:
		if int(room["row"]) != 0:
			continue
		var back_room: Dictionary = _neighbour_of(room)
		if back_room.is_empty():
			continue
		var pos: Vector3 = Vector3(float(room["link_x"]), 0.0, float(room["min_z"]) - WALL * 0.5)
		links.append(_add_door(parent, "LinkEast" if float(room["side"]) > 0.0 else "LinkWest", pos, 0.0, back_room, room))
	return links


## Zombie-Eingang: Gang hinter einer Wandöffnung mit Spawnpunkt, Spieler-Sperre, Warnlampe.
## mouth ist die Mitte der Öffnung auf der Innenseite der Wand in Bodenhöhe, outward zeigt
## aus dem Raum hinaus (achsparallel). Zone 1 ist sofort aktiv, alle anderen erst nach der Tür.
func _add_entrance(parent: Node3D, id: String, zone: int, mouth: Vector3, outward: Vector3, sign_text: String) -> void:
	var side: Vector3 = Vector3(outward.z, 0.0, -outward.x)
	var up: Vector3 = Vector3.UP
	var depth: float = WALL + CORRIDOR_LENGTH
	var half: float = ENTRANCE_WIDTH * 0.5
	var floor_y: float = mouth.y
	var base: Vector3 = Vector3(mouth.x, 0.0, mouth.z)
	var wall_mat: StandardMaterial3D = _pattern("stripes", COLOR_CORRIDOR_A, COLOR_CORRIDOR_B, 0.5)
	var floor_mat: StandardMaterial3D = _flat(Color(0.12, 0.13, 0.12))
	var root: Node3D = _group_node(parent, "Entrance_%s" % id)
	if _show.zone_nodes.has(zone):
		# Gang eines kaufbaren Raums: nur zu sehen und beleuchtet, wenn der Raum offen ist.
		(_show.zone_nodes[zone] as Array).append(root)

	# Boden: ebenerdig beginnt er hinter der Wand (darunter liegt der Raumboden), erhöht ab der Öffnung.
	var floor_start: float = WALL if floor_y < 0.01 else 0.0
	_solid_span(root, "Floor", base + outward * floor_start - side * half + up * -FLOOR_THICKNESS,
			base + outward * (depth + CORRIDOR_WALL) + side * half + up * floor_y, floor_mat, true)
	for s: float in [-1.0, 1.0]:
		_solid_span(root, "Wall", base + outward * WALL + side * (s * half) + up * -FLOOR_THICKNESS,
				base + outward * (depth + CORRIDOR_WALL) + side * (s * (half + CORRIDOR_WALL)) + up * (floor_y + ENTRANCE_HEIGHT), wall_mat, true)
	_solid_span(root, "End", base + outward * depth - side * half + up * floor_y,
			base + outward * (depth + CORRIDOR_WALL) + side * half + up * (floor_y + ENTRANCE_HEIGHT), wall_mat, true)
	_solid_span(root, "Ceiling", base + outward * WALL - side * (half + CORRIDOR_WALL) + up * (floor_y + ENTRANCE_HEIGHT),
			base + outward * (depth + CORRIDOR_WALL) + side * (half + CORRIDOR_WALL) + up * (floor_y + ENTRANCE_HEIGHT + CORRIDOR_WALL),
			_flat(COLOR_CEILING), false)

	# Spawnpunkt im Gang.
	var marker: Marker3D = Marker3D.new()
	marker.name = "Spawn_%s" % id
	marker.position = mouth + outward * (depth - SPAWN_INSET)
	marker.set_meta("zone", zone)
	marker.set_meta("active", zone == 1)
	marker.add_to_group(GROUP_SPAWNS)
	root.add_child(marker)

	# Sperre nur für den Spieler, in der Wanddicke der Öffnung.
	_add_player_block(root, "PlayerBlock", mouth + outward * 0.2 + up * (ENTRANCE_HEIGHT * 0.5),
			_abs_size(side * ENTRANCE_WIDTH + up * ENTRANCE_HEIGHT + outward * 0.3))

	# Kisten, die tiefer im Gang landen, als der Spieler greifen kann, rutschen vor die Öffnung.
	var zone_a: Vector3 = base + outward * CHEST_RESCUE_DEPTH - side * (half + CORRIDOR_WALL) + up * -1.0
	var zone_b: Vector3 = base + outward * (depth + CORRIDOR_WALL) + side * (half + CORRIDOR_WALL) + up * (floor_y + ENTRANCE_HEIGHT + 1.0)
	_show.blocked_zones.append(AABB(zone_a.min(zone_b), zone_a.max(zone_b) - zone_a.min(zone_b)))
	_show.blocked_exits.append(mouth - outward * CHEST_EXIT_INSET)

	# Giftgrünes Licht im Gang: Zombies sind schon im Anmarsch gut zu sehen.
	var glow: OmniLight3D = OmniLight3D.new()
	glow.name = "Glow"
	glow.position = mouth + outward * (depth * 0.55) + up * (ENTRANCE_HEIGHT - 0.6)
	glow.light_color = Color(0.45, 1.0, 0.35)
	glow.light_energy = 1.8
	glow.omni_range = 6.5
	glow.shadow_enabled = false
	root.add_child(glow)

	# Rahmen in Warnfarben, Warnlampe und Schild auf der Raumseite.
	var hazard: StandardMaterial3D = _pattern("hazard", COLOR_GOLD, COLOR_BLACK, 0.3)
	var inward: Vector3 = -outward
	for s: float in [-1.0, 1.0]:
		_deco(root, "FramePost", mouth + side * (s * (half + 0.12)) + inward * 0.05 + up * (ENTRANCE_HEIGHT * 0.5),
				_abs_size(side * 0.24 + up * ENTRANCE_HEIGHT + outward * 0.1), hazard)
	_deco(root, "FrameTop", mouth + inward * 0.05 + up * (ENTRANCE_HEIGHT + 0.11),
			_abs_size(side * (ENTRANCE_WIDTH + 0.48) + up * 0.22 + outward * 0.1), hazard)
	var warn: StandardMaterial3D = _show.warn_zone1 if zone == 1 else _show.zone_warn.get(zone) as StandardMaterial3D
	_deco(root, "WarnLamp", mouth + inward * 0.14 + up * (ENTRANCE_HEIGHT + 0.11),
			_abs_size(side * 0.5 + up * 0.26 + outward * 0.2), warn)
	if sign_text != "":
		var yaw: float = rad_to_deg(atan2(inward.x, inward.z))
		var sign_pos: Vector3 = mouth + inward * 0.04 + up * (ENTRANCE_HEIGHT + 0.6)
		_deco(root, "SignBoard", sign_pos, _abs_size(side * 3.3 + up * 0.5 + outward * 0.06), _flat(COLOR_BLACK))
		_label(root, sign_text, sign_pos + inward * 0.04, yaw, 0.3, COLOR_GOLD, COLOR_BLACK)


## Treppe oder Rampe von der Bühne herunter. top ist die Mitte der Oberkante an der Bühne,
## downhill zeigt waagrecht bergab (achsparallel). Kollision: ein Keil. Sichtbar: Stufen.
func _add_ramp(parent: Node3D, node_name: String, top: Vector3, downhill: Vector3, width: float) -> void:
	var across: Vector3 = Vector3(downhill.z, 0.0, -downhill.x) * (width * 0.5)
	var ground: Vector3 = Vector3(top.x, 0.0, top.z)
	var foot: Vector3 = ground + downhill * RAMP_RUN
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.collision_layer = Balance.LAYER_WORLD
	body.collision_mask = 0
	body.add_to_group(GROUP_NAV_SOURCE)
	var wedge: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array([
		top + across, top - across, ground + across, ground - across, foot + across, foot - across,
	])
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = wedge
	body.add_child(shape)
	var carpet: StandardMaterial3D = _flat(COLOR_RED)
	var edge: StandardMaterial3D = _flat(COLOR_GOLD)
	var step_run: float = RAMP_RUN / float(STAIR_STEPS)
	for i: int in range(STAIR_STEPS):
		var step_height: float = top.y * float(STAIR_STEPS - i) / float(STAIR_STEPS)
		var center: Vector3 = ground + downhill * (step_run * (float(i) + 0.5)) + Vector3.UP * (step_height * 0.5)
		var size: Vector3 = _abs_size(downhill * step_run + Vector3.UP * step_height + across * 2.0)
		_deco(body, "Step", center, size, carpet)
		# Goldene Kante vorn an jeder Stufe.
		var lip: Vector3 = ground + downhill * (step_run * (float(i) + 1.0) - 0.04) + Vector3.UP * (step_height - 0.02)
		_deco(body, "StepEdge", lip, _abs_size(downhill * 0.1 + Vector3.UP * 0.06 + across * 2.0), edge)
	parent.add_child(body)


func _add_player_block(parent: Node3D, node_name: String, center: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.collision_layer = Balance.LAYER_PLAYER_BLOCK
	body.collision_mask = 0
	body.position = center
	body.add_to_group(GROUP_PLAYER_BLOCK)
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body, true)


# ---------------------------------------------------------------------------------------------
# Licht
# ---------------------------------------------------------------------------------------------

func _build_environment(parent: Node3D) -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.02, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.76, 0.95)
	environment.ambient_light_energy = 0.55
	var world: WorldEnvironment = WorldEnvironment.new()
	world.name = "Environment"
	world.environment = environment
	parent.add_child(world)


## Warmes Grundlicht für das Studio (Render-Ebene 1, also auch Spieler, Zombies und Kisten überall),
## kühles, schwächeres Grundlicht für die Geometrie der Räume (Render-Ebene 2). Ohne Schatten,
## damit das Licht durch die Decke kommt. Dazu bunte Punktlichter als Akzente. Die Lichter eines
## Raums sind nur an, solange er offen ist: Der Renderer zeigt höchstens 32 Punktlichter je Bild
## und 8 je Mesh.
func _build_lights(root: Node3D) -> void:
	var warm: DirectionalLight3D = DirectionalLight3D.new()
	warm.name = "KeyWarm"
	warm.rotation_degrees = Vector3(-58.0, 28.0, 0.0)
	warm.light_color = Color(1.0, 0.93, 0.8)
	warm.light_energy = 0.8
	warm.light_cull_mask = 1
	warm.shadow_enabled = false
	root.add_child(warm)
	var cool: DirectionalLight3D = DirectionalLight3D.new()
	cool.name = "KeyCool"
	cool.rotation_degrees = Vector3(-62.0, -140.0, 0.0)
	cool.light_color = Color(0.62, 0.74, 1.0)
	cool.light_energy = 0.5
	cool.light_cull_mask = 2
	cool.shadow_enabled = false
	root.add_child(cool)

	_omni(root, "FloorWash", Vector3(0.0, _height1 - 0.7, 2.0), Color(1.0, 0.9, 0.75), 1.2, 15.0)
	_omni(root, "AudienceLight", Vector3(0.0, _height1 - 1.2, _hz + WALL + 1.2), Color(0.7, 0.68, 1.0), 2.0, 9.5)
	for room: Dictionary in _rooms:
		var zone: int = int(room["zone"])
		var side: float = float(room["side"])
		var look: Dictionary = _room_look(String(room["key"]))
		var nodes: Array = _show.zone_nodes[zone]
		# Farbiges Licht vor der Tür auf der Bühne (immer an).
		_omni(root, "DoorLight", Vector3(side * (_hx - 1.0), DOOR_HEIGHT + 0.6, float(room["door_z"])), room["accent"], 1.6, 5.5)
		# Ein Deckenlicht in der Raummitte (ein Licht statt zweier, wegen der Grenze oben) und zwei
		# leuchtende Lampen als Deko.
		var middle: Vector3 = _room_point(room, Balance.ZONE2_SIZE.x * 0.5, Balance.ZONE2_SIZE.z * 0.5, _height2 - 0.5)
		nodes.append(_omni(root, "RoomLight", middle, look["light"], float(look["energy"]), ROOM_LIGHT_RANGE))
		_render_layer = 2
		for du: float in [-3.5, 3.5]:
			nodes.append(_deco(root, "RoomLamp", middle + Vector3(du, 0.3, 0.0), Vector3(1.6, 0.12, 0.3), _glow((look["light"] as Color).lerp(COLOR_WHITE, 0.5))))
		_render_layer = 1
		match String(room["key"]):
			"wardrobe":
				nodes.append(_omni(root, "MakeupLight", _room_point(room, 12.6, 8.0, 2.0), Color(1.0, 0.85, 0.6), 1.3, 4.5))
			"control_room":
				nodes.append(_omni(root, "MonitorLight", _room_point(room, 4.2, 1.2, 2.6), Color(0.55, 0.8, 1.0), 1.6, 6.0))


func _omni(parent: Node3D, node_name: String, pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = node_name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	parent.add_child(light, true)
	return light


# ---------------------------------------------------------------------------------------------
# Bausteine
# ---------------------------------------------------------------------------------------------

func _group_node(parent: Node3D, node_name: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = node_name
	parent.add_child(node)
	return node


## Quader mit Kollision (Lage world) und, wenn material gesetzt ist, mit Mesh.
## nav = true: Gruppe "nav_source", Zombies laufen darum herum (oder darauf, wenn begehbar).
func _solid(parent: Node3D, node_name: String, center: Vector3, size: Vector3, material: Material,
		nav: bool = true, yaw_deg: float = 0.0) -> StaticBody3D:
	var body: StaticBody3D = _collider(parent, node_name, center, size, nav, yaw_deg)
	if material != null:
		var mesh: MeshInstance3D = _box_mesh(size, material)
		mesh.name = "Mesh"
		body.add_child(mesh)
	return body


## Quader nur mit Kollision.
func _collider(parent: Node3D, node_name: String, center: Vector3, size: Vector3, nav: bool, yaw_deg: float = 0.0) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.collision_layer = Balance.LAYER_WORLD
	body.collision_mask = 0
	body.position = center
	body.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	if nav:
		body.add_to_group(GROUP_NAV_SOURCE)
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body, true)
	return body


## Quader mit Kollision zwischen zwei gegenüberliegenden Ecken.
func _solid_span(parent: Node3D, node_name: String, a: Vector3, b: Vector3, material: Material, nav: bool) -> StaticBody3D:
	var low: Vector3 = a.min(b)
	var high: Vector3 = a.max(b)
	return _solid(parent, node_name, (low + high) * 0.5, high - low, material, nav)


## Quader ohne Kollision (Deko).
func _deco(parent: Node3D, node_name: String, center: Vector3, size: Vector3, material: Material, yaw_deg: float = 0.0) -> MeshInstance3D:
	var mesh: MeshInstance3D = _box_mesh(size, material)
	mesh.name = node_name
	mesh.position = center
	mesh.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(mesh, true)
	return mesh


func _deco_span(parent: Node3D, node_name: String, a: Vector3, b: Vector3, material: Material) -> MeshInstance3D:
	var low: Vector3 = a.min(b)
	var high: Vector3 = a.max(b)
	return _deco(parent, node_name, (low + high) * 0.5, high - low, material)


## Zusatzteil eines Körpers: Mesh und wahlweise eine weitere Kollisionsform am selben Körper.
func _child_box(body: StaticBody3D, node_name: String, center: Vector3, size: Vector3, material: Material, collide: bool) -> void:
	_deco(body, node_name, center, size, material)
	if collide:
		var box: BoxShape3D = BoxShape3D.new()
		box.size = size
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.name = "%sShape" % node_name
		shape.shape = box
		shape.position = center
		body.add_child(shape, true)


func _box_mesh(size: Vector3, material: Material) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	box.material = material
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = box
	mesh.layers = _render_layer
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func _opening(center: float, width: float, bottom: float, top: float) -> Dictionary:
	return { "center": center, "width": width, "bottom": bottom, "top": top }


## Gerade Wand aus Quadern mit Öffnungen. along_x: Die Wand verläuft entlang X (sonst entlang Z),
## fixed ist die Mitte der Wanddicke auf der anderen Achse. openings: Liste von _opening(...),
## aufsteigend nach "center". Unter "bottom" und über "top" bleibt die Wand stehen.
func _wall(parent: Node3D, node_name: String, along_x: bool, fixed: float, from: float, to: float,
		height: float, openings: Array, material: Material) -> void:
	var cursor: float = from
	for opening: Dictionary in openings:
		var left: float = float(opening["center"]) - float(opening["width"]) * 0.5
		var right: float = float(opening["center"]) + float(opening["width"]) * 0.5
		if left > cursor:
			_wall_piece(parent, node_name, along_x, fixed, cursor, left, 0.0, height, material)
		if float(opening["bottom"]) > 0.0:
			_wall_piece(parent, node_name, along_x, fixed, left, right, 0.0, float(opening["bottom"]), material)
		if float(opening["top"]) < height:
			_wall_piece(parent, node_name, along_x, fixed, left, right, float(opening["top"]), height, material)
		cursor = right
	if cursor < to:
		_wall_piece(parent, node_name, along_x, fixed, cursor, to, 0.0, height, material)


func _wall_piece(parent: Node3D, node_name: String, along_x: bool, fixed: float, from: float, to: float,
		bottom: float, top: float, material: Material) -> void:
	var length: float = to - from
	var mid: float = (from + to) * 0.5
	var center: Vector3 = Vector3(mid, (bottom + top) * 0.5, fixed) if along_x else Vector3(fixed, (bottom + top) * 0.5, mid)
	var size: Vector3 = Vector3(length, top - bottom, WALL) if along_x else Vector3(WALL, top - bottom, length)
	_solid(parent, node_name, center, size, material, true)


## Beschriftung (Label3D), lesbar aus Richtung yaw (0 = Blick von +Z). height ist die Schriftgröße in Metern.
func _label(parent: Node3D, text: String, pos: Vector3, yaw_deg: float, height: float, color: Color, outline: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = text
	label.font_size = 128
	label.pixel_size = height / 128.0
	label.outline_size = 28
	label.modulate = color
	label.outline_modulate = outline
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	label.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(label, true)
	return label


## Beschriftung auf beiden großen Seiten eines gedrehten Quaders (Kulisse).
func _label_on_box(parent: Node3D, text: String, center: Vector3, yaw_deg: float, offset: float,
		height: float, color: Color, outline: Color) -> void:
	var normal: Vector3 = Vector3(sin(deg_to_rad(yaw_deg)), 0.0, cos(deg_to_rad(yaw_deg)))
	_label(parent, text, center + normal * offset, yaw_deg, height, color, outline)
	_label(parent, text, center - normal * offset, yaw_deg + 180.0, height, color, outline)


## Maße eines achsparallelen Quaders aus der Summe seiner drei Kantenvektoren.
func _abs_size(edges: Vector3) -> Vector3:
	return edges.abs()


## Drehung (Euler), mit der ein Knoten an from entlang -Z auf target schaut.
func _look_rotation(from: Vector3, target: Vector3) -> Vector3:
	var basis: Basis = Basis.looking_at(target - from, Vector3.UP)
	return basis.get_euler()


# ---------------------------------------------------------------------------------------------
# Materialien: kräftige Flächenfarben, Karo und Streifen aus winzigen erzeugten Texturen
# ---------------------------------------------------------------------------------------------

func _flat(color: Color) -> StandardMaterial3D:
	var key: String = "flat_%s" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.metallic_specular = 0.2
	_materials[key] = material
	return material


## Leuchtfarbe ohne Beleuchtung (Schilder, Linsen), geteilt je Farbe.
func _glow(color: Color) -> StandardMaterial3D:
	var key: String = "glow_%s" % color.to_html()
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = _glow_unique(color)
	_materials[key] = material
	return material


## Leuchtfarbe als eigenes Material (wird zur Laufzeit umgefärbt).
func _glow_unique(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


## Gemustertes Material. kind: "checker" (Karo), "stripes" (senkrechte Streifen an Wänden),
## "bands" (waagrechte Streifen), "hazard" (schräge Warnstreifen). tile ist die Breite eines
## Feldes in Metern. world = false: Das Muster hängt am Objekt (für gedrehte und bewegte Teile).
func _pattern(kind: String, color_a: Color, color_b: Color, tile: float, world: bool = true) -> StandardMaterial3D:
	var key: String = "%s_%s_%s_%.3f_%s" % [kind, color_a.to_html(), color_b.to_html(), tile, world]
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = _pattern_texture(kind, color_a, color_b)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_world_triplanar = world
	material.uv1_triplanar_sharpness = 8.0
	material.uv1_scale = Vector3.ONE * (0.5 / maxf(tile, 0.01))
	material.roughness = 0.95
	material.metallic_specular = 0.2
	_materials[key] = material
	return material


func _pattern_texture(kind: String, color_a: Color, color_b: Color) -> ImageTexture:
	var key: String = "%s_%s_%s" % [kind, color_a.to_html(), color_b.to_html()]
	if _textures.has(key):
		return _textures[key]
	var n: int = 64
	var half: int = n / 2
	var image: Image = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	image.fill(color_a)
	match kind:
		"checker":
			image.fill_rect(Rect2i(0, 0, half, half), color_b)
			image.fill_rect(Rect2i(half, half, half, half), color_b)
		"stripes":
			image.fill_rect(Rect2i(0, 0, half, n), color_b)
		"bands":
			image.fill_rect(Rect2i(0, 0, n, half), color_b)
		"hazard":
			for y: int in range(n):
				for x: int in range(n):
					if (x + y) % n < half:
						image.set_pixel(x, y, color_b)
	image.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture
