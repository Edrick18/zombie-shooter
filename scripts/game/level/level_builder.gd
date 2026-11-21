extends RefCounted
## Modul: Level (scripts/game/level).
## Baut das Level "Studio" (Abschnitt 9) vollständig im Code aus Quadern, als Kinder des
## übergebenen Knotens. Aufruf in main.gd: LevelBuilder.new().build(level_root). Der Builder
## selbst wird danach verworfen: alles Dauerhafte gehört in Knoten (siehe StudioShow unten).
##
## Grundriss (Blick von oben, +X rechts, +Z zum Publikum, der Spieler schaut anfangs nach -Z):
##   Zone 1 "Bühne":     x -11..11, z -9..9, 5 m hoch. Bühne (0,4 m) an der Rückwand, davor die
##                       Showtreppe, links und rechts je eine Rampe. Publikum hinter einer
##                       Brüstung bei z = 9 (nur Deko, für den Spieler gesperrt).
##   Zone 2 "Backstage": x 11,4..25,4, z -3..9, hinter der Tür in der Ostwand (z = 4).
##   Zombie-Eingänge:    A Showtor in der Rückwand auf Bühnenhöhe, B Westwand, C Ostwand (Zone 1),
##                       D Nordwand, E Ostwand (Zone 2). Je ein kurzer Gang mit Spawnpunkt.
##
## Knoten unter parent: NavRegion, Door, WallBuy_shotgun, WallBuy_smg, Show (Laufzeit-Knoten),
## Environment, Lights, Zone1, Zone2, Audience, Entrances (darin die Marker3D "Spawn_A" bis
## "Spawn_E" der Gruppe "zombie_spawns").

const Balance := preload("res://scripts/core/balance.gd")
const Door := preload("res://scripts/game/level/door.gd")
const WallBuy := preload("res://scripts/game/level/wall_buy.gd")

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
## Mitte der Tür auf der Z-Achse (Ostwand der Zone 1).
const DOOR_Z: float = 4.0
const STAGE_DEPTH: float = 4.5
const STAGE_HALF_WIDTH: float = 6.0
const RAMP_RUN: float = 1.6
const STAIR_STEPS: int = 4
const BARRIER_HEIGHT: float = 1.1
const WINDOW_TOP: float = 4.2
const WINDOW_WIDTH: float = 18.0
const AUDIENCE_DEPTH: float = 4.8
const CEILING: float = 0.3
const FLOOR_THICKNESS: float = 0.5

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

## Titel der Show auf dem großen Schild.
const SHOW_TITLE: String = "WER WIRD ZOMBIEFUTTER?"
## Halber Öffnungswinkel der Bühnenscheinwerfer in Grad und Länge ihres sichtbaren Lichtkegels.
const SPOT_ANGLE: float = 24.0
const SPOT_CONE_LENGTH: float = 5.2


## Laufzeit-Knoten des Levels (Knoten "Show"). Bewegt die Scheinwerfer, lässt Lampen blinken und
## das Publikum jubeln, rettet Kisten aus den Zombie-Gängen und backt das Navigationsnetz, falls das
## Level beim Bauen noch nicht im Baum hing.
class StudioShow:
	extends Node3D

	var nav_region: NavigationRegion3D
	## Einstellungen und Ergebnis des Navigationsnetzes (wird nach dem Backen der Region zugewiesen).
	var nav_mesh: NavigationMesh
	var door: Node3D
	var spots: Array[SpotLight3D] = []
	var spot_targets: Array[Vector3] = []
	var bulbs_a: StandardMaterial3D
	var bulbs_b: StandardMaterial3D
	var warn_zone1: StandardMaterial3D
	var warn_zone2: StandardMaterial3D
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
		if bake_on_ready:
			bake()

	## Backt das Navigationsnetz aus den Kollisionen der Gruppe "nav_source" (im Hauptthread,
	## dauert wenige Millisekunden) und weist es der Region zu. Gibt true zurück, wenn das Netz
	## danach Flächen hat. Darf erneut aufgerufen werden, wenn sich die Geometrie geändert hat.
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
		nav_region.navigation_mesh = null
		nav_region.navigation_mesh = nav_mesh
		var ok: bool = nav_mesh.get_polygon_count() > 0
		if not ok:
			push_warning("Level: Das Navigationsnetz ist nach dem Backen leer.")
		return ok

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
		if warn_zone2 != null:
			var open: bool = is_instance_valid(door) and bool(door.get("is_open"))
			warn_zone2.albedo_color = lit if open else WARN_OFF

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
## Render-Ebene neuer Meshes: 1 = Zone 1 (warmes Hauptlicht), 2 = Backstage (kühles Hauptlicht).
var _render_layer: int = 1
var _show: StudioShow
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Grundriss, in build() aus Balance berechnet.
var _hx: float = 11.0
var _hz: float = 9.0
var _height1: float = 5.0
var _height2: float = 5.0
var _z2_min_x: float = 11.4
var _z2_max_x: float = 25.4
var _z2_min_z: float = -3.0
var _z2_max_z: float = 9.0
var _stage_y: float = 0.4
var _stage_front_z: float = -4.5


## Baut das Level unter parent und gibt zurück:
## { "player_spawn": Vector3 (Füße des Spielers, Weltkoordinaten),
##   "nav_region": NavigationRegion3D, "door": Node3D (door.gd) }.
## Hängt parent schon im Baum, ist das Navigationsnetz bei der Rückkehr fertig gebacken.
func build(parent: Node3D) -> Dictionary:
	_measure()
	_rng.seed = 20240917
	_show = StudioShow.new()
	_show.name = "Show"
	_show.warn_zone1 = _glow_unique(StudioShow.WARN_COLOR)
	_show.warn_zone2 = _glow_unique(StudioShow.WARN_OFF)
	_show.bulbs_a = _glow_unique(StudioShow.BULB_BRIGHT)
	_show.bulbs_b = _glow_unique(StudioShow.BULB_DIM)

	var nav_region: NavigationRegion3D = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	parent.add_child(nav_region)

	_build_environment(parent)
	var entrances: Node3D = _group_node(parent, "Entrances")
	_render_layer = 1
	_build_zone1(_group_node(parent, "Zone1"), entrances)
	_build_audience(_group_node(parent, "Audience"))
	_render_layer = 2
	_build_zone2(_group_node(parent, "Zone2"), entrances)
	_render_layer = 1
	var door: StaticBody3D = _build_door(parent)
	_add_wall_buy(parent, "shotgun", Vector3(-_hx + 2.2, 1.55, -_hz), 0.0)
	_add_wall_buy(parent, "smg", Vector3(_z2_min_x + 5.0, 1.55, _z2_max_z), 180.0)
	_build_lights(_group_node(parent, "Lights"))

	_show.nav_region = nav_region
	_show.nav_mesh = _make_navigation_mesh()
	_show.door = door
	_show.bake_on_ready = not parent.is_inside_tree()
	parent.add_child(_show)
	if parent.is_inside_tree():
		_show.bake()

	var spawn_local: Vector3 = Vector3(0.0, 0.0, _hz - 4.0)
	return {
		"player_spawn": parent.to_global(spawn_local) if parent.is_inside_tree() else spawn_local,
		"nav_region": nav_region,
		"door": door,
	}


func _measure() -> void:
	_hx = Balance.ZONE1_SIZE.x * 0.5
	_hz = Balance.ZONE1_SIZE.z * 0.5
	_height1 = Balance.ZONE1_SIZE.y
	_height2 = Balance.ZONE2_SIZE.y
	_z2_min_x = _hx + WALL
	_z2_max_x = _z2_min_x + Balance.ZONE2_SIZE.x
	_z2_max_z = _hz
	_z2_min_z = _hz - Balance.ZONE2_SIZE.z
	_stage_y = Balance.STAGE_HEIGHT
	_stage_front_z = -_hz + STAGE_DEPTH


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
	var low: Vector3 = Vector3(-_hx - reach, -1.0 + NAV_HEIGHT_EPSILON, minf(-_hz, _z2_min_z) - reach)
	var high: Vector3 = Vector3(_z2_max_x + reach, 4.0, _hz + reach)
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

	# Boden: ein Kollisionskörper, aber sechs Mesh-Stücke (damit je Stück wenige Lichter zählen).
	var floor_body: StaticBody3D = _collider(zone, "Floor", Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0),
			Vector3(outer_x * 2.0, FLOOR_THICKNESS, outer_z * 2.0), true)
	var tile: Vector3 = Vector3(outer_x * 2.0 / 3.0, FLOOR_THICKNESS, outer_z)
	for ix: int in range(3):
		for iz: int in range(2):
			var center: Vector3 = Vector3(-outer_x + tile.x * (float(ix) + 0.5), 0.0, -outer_z + tile.z * (float(iz) + 0.5))
			_deco(floor_body, "FloorMesh", center, tile, floor_mat)
	_solid(zone, "Ceiling", Vector3(0.0, _height1 + CEILING * 0.5, 0.0),
			Vector3(outer_x * 2.0, CEILING, outer_z * 2.0), ceiling_mat, false)

	# Wände mit Öffnungen: Showtor (A), Publikumsfenster, Westeingang (B), Osteingang (C), Tür.
	var gate_top: float = _stage_y + ENTRANCE_HEIGHT
	_wall(zone, "WallNorth", true, -_hz - WALL * 0.5, -outer_x, outer_x, _height1,
			[_opening(0.0, ENTRANCE_WIDTH, 0.0, gate_top)], wall_mat)
	_wall(zone, "WallSouth", true, _hz + WALL * 0.5, -outer_x, outer_x, _height1,
			[_opening(0.0, WINDOW_WIDTH, BARRIER_HEIGHT, WINDOW_TOP)], wall_mat)
	_wall(zone, "WallWest", false, -_hx - WALL * 0.5, -_hz, _hz, _height1,
			[_opening(1.0, ENTRANCE_WIDTH, 0.0, ENTRANCE_HEIGHT)], wall_mat)
	_wall(zone, "WallEast", false, _hx + WALL * 0.5, -_hz, _hz, _height1, [
		_opening(-6.0, ENTRANCE_WIDTH, 0.0, ENTRANCE_HEIGHT),
		_opening(DOOR_Z, DOOR_WIDTH, 0.0, DOOR_HEIGHT),
	], wall_mat)

	_add_entrance(entrances, "A", 1, Vector3(0.0, _stage_y, -_hz), Vector3(0.0, 0.0, -1.0), "")
	_add_entrance(entrances, "B", 1, Vector3(-_hx, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0), "AUFTRITT ZOMBIES")
	_add_entrance(entrances, "C", 1, Vector3(_hx, 0.0, -6.0), Vector3(1.0, 0.0, 0.0), "AUFTRITT ZOMBIES")

	_build_stage(zone)
	_build_show_sign(zone)
	_build_set_pieces(zone)
	_build_rig(zone)
	_build_ceiling_lamps(zone)

	# Schild über der Tür zur Zone 2.
	var sign_pos: Vector3 = Vector3(_hx - 0.06, DOOR_HEIGHT + 0.75, DOOR_Z)
	_deco(zone, "BackstageSign", sign_pos, Vector3(0.1, 0.8, 3.6), _flat(COLOR_BLACK))
	_label(zone, "BACKSTAGE >>", sign_pos + Vector3(-0.07, 0.0, 0.0), -90.0, 0.5, COLOR_STAGE_B, COLOR_BLACK)


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
	for side: float in [-1.0, 1.0]:
		_deco(zone, "Curtain", Vector3(side * 3.4, _stage_y + 1.7, -_hz + 0.06), Vector3(3.6, 3.4, 0.1), curtain_mat)
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
	var sign_width: float = 10.6
	var center: Vector3 = Vector3(0.0, gate_top + 0.4 + sign_height * 0.5, -_hz + 0.12)
	_deco(zone, "ShowSignFrame", center, Vector3(sign_width + 0.3, sign_height + 0.3, 0.16), _flat(COLOR_GOLD))
	_deco(zone, "ShowSign", center + Vector3(0.0, 0.0, 0.05), Vector3(sign_width, sign_height, 0.16), _flat(Color(0.3, 0.05, 0.4)))
	var title: Label3D = _label(zone, SHOW_TITLE, center + Vector3(0.0, 0.0, 0.15), 0.0, 0.66, COLOR_GOLD, COLOR_RED)
	title.name = "ShowTitle"
	# Glühbirnen rund um das Schild, abwechselnd Material A und B (blinken im Wechsel).
	var bulb: SphereMesh = SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	bulb.radial_segments = 8
	bulb.rings = 4
	var count_x: int = 20
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
	_add_studio_camera(zone, Vector3(-7.4, 0.0, _hz - 2.6), 150.0)
	_add_studio_camera(zone, Vector3(7.0, 0.0, _hz - 2.2), -160.0)


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
	_deco(zone, "Truss", Vector3(0.0, rig_y + 0.2, rig_z), Vector3(17.0, 0.18, 0.18), metal)
	_deco(zone, "Truss", Vector3(0.0, rig_y + 0.2, rig_z + 0.5), Vector3(17.0, 0.18, 0.18), metal)
	for i: int in range(SPOT_COLORS.size()):
		var x: float = lerpf(-6.6, 6.6, float(i) / float(SPOT_COLORS.size() - 1))
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
	for z: float in [1.5, 5.5]:
		_deco(zone, "CeilingTruss", Vector3(0.0, y + 0.12, z), Vector3(_hx * 2.0 - 3.0, 0.14, 0.14), metal)
		for x: float in [-6.5, 0.0, 6.5]:
			_deco(zone, "CeilingLamp", Vector3(x, y, z), Vector3(2.0, 0.1, 0.55), lamp)


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
# Zone 2 "Backstage"
# ---------------------------------------------------------------------------------------------

func _build_zone2(zone: Node3D, entrances: Node3D) -> void:
	var floor_mat: StandardMaterial3D = _pattern("checker", COLOR_BACK_FLOOR_A, COLOR_BACK_FLOOR_B, 2.0)
	var wall_mat: StandardMaterial3D = _pattern("bands", COLOR_BACK_WALL_A, COLOR_BACK_WALL_B, 1.25)
	var outer_x: float = _z2_max_x + WALL
	var center_x: float = (_z2_min_x + outer_x) * 0.5
	var size_z: float = (_z2_max_z + WALL) - (_z2_min_z - WALL)
	var center_z: float = (_z2_max_z + _z2_min_z) * 0.5
	_solid(zone, "Floor", Vector3(center_x, -FLOOR_THICKNESS * 0.5, center_z),
			Vector3(outer_x - _z2_min_x, FLOOR_THICKNESS, size_z), floor_mat)
	_solid(zone, "Ceiling", Vector3(center_x, _height2 + CEILING * 0.5, center_z),
			Vector3(outer_x - _z2_min_x, CEILING, size_z), _flat(COLOR_CEILING), false)

	var mouth_d: Vector3 = Vector3(_z2_min_x + 9.6, 0.0, _z2_min_z)
	var mouth_e: Vector3 = Vector3(_z2_max_x, 0.0, _z2_max_z - 3.0)
	_wall(zone, "WallNorth", true, _z2_min_z - WALL * 0.5, _z2_min_x, outer_x, _height2,
			[_opening(mouth_d.x, ENTRANCE_WIDTH, 0.0, ENTRANCE_HEIGHT)], wall_mat)
	_wall(zone, "WallSouth", true, _z2_max_z + WALL * 0.5, _z2_min_x, outer_x, _height2, [], wall_mat)
	_wall(zone, "WallEast", false, _z2_max_x + WALL * 0.5, _z2_min_z, _z2_max_z, _height2,
			[_opening(mouth_e.z, ENTRANCE_WIDTH, 0.0, ENTRANCE_HEIGHT)], wall_mat)
	# Rückseite der Studiowand (die Wand selbst gehört zur Zone 1): Sperrholz-Verkleidung.
	var ply: StandardMaterial3D = _pattern("stripes", COLOR_WOOD_A, COLOR_WOOD_B, 0.6)
	var door_min: float = DOOR_Z - DOOR_WIDTH * 0.5
	var door_max: float = DOOR_Z + DOOR_WIDTH * 0.5
	_deco_span(zone, "WallBack", Vector3(_z2_min_x, 0.0, _z2_min_z), Vector3(_z2_min_x + 0.04, _height2, door_min), ply)
	_deco_span(zone, "WallBack", Vector3(_z2_min_x, 0.0, door_max), Vector3(_z2_min_x + 0.04, _height2, _z2_max_z), ply)
	_deco_span(zone, "WallBack", Vector3(_z2_min_x, DOOR_HEIGHT, door_min), Vector3(_z2_min_x + 0.04, _height2, door_max), ply)
	_label(zone, "<< BÜHNE", Vector3(_z2_min_x + 0.07, DOOR_HEIGHT + 0.6, DOOR_Z), 90.0, 0.45, COLOR_WHITE, COLOR_BLACK)

	_add_entrance(entrances, "D", 2, mouth_d, Vector3(0.0, 0.0, -1.0), "AUFTRITT ZOMBIES")
	_add_entrance(entrances, "E", 2, mouth_e, Vector3(1.0, 0.0, 0.0), "AUFTRITT ZOMBIES")
	_build_clutter(zone)


## Kisten und Gerümpel als Deckung. Die Raummitte bleibt frei.
func _build_clutter(zone: Node3D) -> void:
	var crate: StandardMaterial3D = _pattern("bands", COLOR_WOOD_A, COLOR_WOOD_B, 0.2, false)
	var crate_dark: StandardMaterial3D = _pattern("stripes", COLOR_WOOD_B, Color(0.36, 0.23, 0.1), 0.2, false)
	var case_mat: StandardMaterial3D = _flat(Color(0.1, 0.1, 0.12))
	var metal: StandardMaterial3D = _flat(Color(0.7, 0.72, 0.76))
	var x0: float = _z2_min_x
	var z1: float = _z2_max_z
	# Kistenstapel nahe der Tür (Nordwest).
	_solid(zone, "Crate", Vector3(x0 + 3.6, 0.6, z1 - 9.4), Vector3(1.2, 1.2, 1.2), crate, true, 8.0)
	_solid(zone, "Crate", Vector3(x0 + 4.9, 0.5, z1 - 9.0), Vector3(1.0, 1.0, 1.0), crate_dark, true, -14.0)
	_solid(zone, "Crate", Vector3(x0 + 3.7, 1.55, z1 - 9.4), Vector3(0.7, 0.7, 0.7), crate_dark, false, 30.0)
	# Kleiderständer mit Kostümen an der Nordwand.
	var rack: Vector3 = Vector3(x0 + 3.0, 0.0, _z2_min_z + 0.45)
	var rack_body: StaticBody3D = _solid(zone, "CostumeRack", rack + Vector3(0.0, 0.95, 0.0), Vector3(3.0, 1.9, 0.6), null, true)
	_child_box(rack_body, "Rail", Vector3(0.0, 0.9, 0.0), Vector3(3.0, 0.06, 0.06), metal, false)
	for i: int in range(7):
		var costume: Color = AUDIENCE_SHIRTS[i % AUDIENCE_SHIRTS.size()]
		_child_box(rack_body, "Costume", Vector3(-1.2 + 0.4 * float(i), 0.25, 0.0), Vector3(0.3, 1.25, 0.5), _flat(costume), false)
	# Flightcases vor der Südwand, neben dem Wandkauf.
	var case_pos: Vector3 = Vector3(x0 + 8.4, 0.45, z1 - 2.6)
	_solid(zone, "FlightCase", case_pos, Vector3(2.2, 0.9, 0.9), case_mat, true, 18.0)
	_deco(zone, "FlightCaseEdge", case_pos + Vector3(0.0, 0.46, 0.0), Vector3(2.26, 0.05, 0.96), metal, 18.0)
	_solid(zone, "FlightCase", case_pos + Vector3(0.2, 0.75, 0.0), Vector3(1.2, 0.6, 0.8), case_mat, false, 34.0)
	# Kisten in der Osthälfte.
	_solid(zone, "Crate", Vector3(x0 + 10.6, 0.6, z1 - 7.4), Vector3(1.2, 1.2, 1.2), crate_dark, true, -6.0)
	_solid(zone, "Crate", Vector3(x0 + 10.9, 0.5, z1 - 6.2), Vector3(1.0, 1.0, 1.0), crate, true, 22.0)
	_solid(zone, "Crate", Vector3(x0 + 2.2, 0.45, z1 - 1.1), Vector3(0.9, 0.9, 0.9), crate, true, 12.0)
	# Kabeltrommel.
	_add_cable_drum(zone, Vector3(x0 + 7.2, 0.0, z1 - 1.4))
	# Schminktisch mit Spiegel und Glühbirnen an der Südwand.
	var table: Vector3 = Vector3(x0 + 11.2, 0.0, z1 - 0.4)
	_solid(zone, "MakeupTable", table + Vector3(0.0, 0.45, 0.0), Vector3(3.0, 0.9, 0.8), _flat(COLOR_STAGE_A), true)
	var mirror: Vector3 = Vector3(table.x, 1.75, z1 - 0.05)
	_deco(zone, "MirrorFrame", mirror, Vector3(2.8, 1.4, 0.08), _flat(COLOR_GOLD))
	_deco(zone, "Mirror", mirror + Vector3(0.0, 0.0, -0.03), Vector3(2.5, 1.1, 0.08), _glow(Color(0.7, 0.88, 1.0)))
	var bulb: SphereMesh = SphereMesh.new()
	bulb.radius = 0.08
	bulb.height = 0.16
	bulb.radial_segments = 8
	bulb.rings = 4
	for i: int in range(7):
		_add_bulb(zone, bulb, mirror + Vector3(-1.2 + 0.4 * float(i), 0.66, -0.08), i)


func _add_cable_drum(zone: Node3D, pos: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "CableDrum"
	body.collision_layer = Balance.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos + Vector3(0.0, 0.5, 0.0)
	body.add_to_group(GROUP_NAV_SOURCE)
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = 0.7
	cylinder.height = 1.0
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = cylinder
	body.add_child(shape)
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.12
	disc.radial_segments = 12
	disc.material = _pattern("stripes", COLOR_WOOD_A, COLOR_WOOD_B, 0.15, false)
	for y: float in [-0.44, 0.44]:
		var plate: MeshInstance3D = MeshInstance3D.new()
		plate.name = "Plate"
		plate.mesh = disc
		plate.position = Vector3(0.0, y, 0.0)
		plate.layers = _render_layer
		body.add_child(plate, true)
	var core: CylinderMesh = CylinderMesh.new()
	core.top_radius = 0.45
	core.bottom_radius = 0.45
	core.height = 0.8
	core.radial_segments = 12
	core.material = _flat(COLOR_BLACK)
	var coil: MeshInstance3D = MeshInstance3D.new()
	coil.name = "Coil"
	coil.mesh = core
	coil.layers = _render_layer
	body.add_child(coil)
	zone.add_child(body, true)


# ---------------------------------------------------------------------------------------------
# Tür, Wandkäufe, Eingänge
# ---------------------------------------------------------------------------------------------

func _build_door(parent: Node3D) -> StaticBody3D:
	var door: StaticBody3D = Door.new()
	door.name = "Door"
	door.set("size", Vector3(DOOR_WIDTH, DOOR_HEIGHT, DOOR_THICKNESS))
	door.position = Vector3(_hx + WALL * 0.5, 0.0, DOOR_Z)
	# Die Breite der Tür (lokal X) liegt entlang der Wand, also entlang Z.
	door.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	parent.add_child(door)
	return door


## Wandkauf: pos ist die Mitte der Tafel auf der Wandfläche, yaw dreht die Tafel zum Raum.
func _add_wall_buy(parent: Node3D, weapon_id: String, pos: Vector3, yaw_deg: float) -> void:
	var wall_buy: StaticBody3D = WallBuy.new()
	wall_buy.name = "WallBuy_%s" % weapon_id
	wall_buy.call("setup", weapon_id)
	wall_buy.position = pos
	wall_buy.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	parent.add_child(wall_buy)


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
	var warn: StandardMaterial3D = _show.warn_zone1 if zone == 1 else _show.warn_zone2
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
## kühles, schwächeres Grundlicht für die Backstage-Geometrie (Render-Ebene 2). Ohne Schatten,
## damit das Licht durch die Decke kommt. Dazu bunte Punktlichter als Akzente.
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

	_omni(root, "FloorWash", Vector3(0.0, _height1 - 0.7, 2.5), Color(1.0, 0.9, 0.75), 1.1, 13.0)
	_omni(root, "AudienceLight", Vector3(0.0, _height1 - 1.2, _hz + WALL + 1.2), Color(0.7, 0.68, 1.0), 2.0, 9.5)
	_omni(root, "DoorLight", Vector3(_hx - 1.0, DOOR_HEIGHT + 0.6, DOOR_Z), COLOR_STAGE_B, 1.6, 5.5)
	var mid_x: float = (_z2_min_x + _z2_max_x) * 0.5
	var mid_z: float = (_z2_min_z + _z2_max_z) * 0.5
	for dx: float in [-3.5, 3.5]:
		var pos: Vector3 = Vector3(mid_x + dx, _height2 - 0.5, mid_z)
		_omni(root, "WorkLight", pos, Color(0.6, 0.75, 1.0), 1.5, 10.0)
		_render_layer = 2
		_deco(root, "WorkLamp", pos + Vector3(0.0, 0.3, 0.0), Vector3(1.6, 0.12, 0.3), _glow(Color(0.8, 0.9, 1.0)))
		_render_layer = 1
	_omni(root, "MakeupLight", Vector3(_z2_min_x + 11.2, 2.0, _z2_max_z - 1.0), Color(1.0, 0.85, 0.6), 1.3, 4.5)


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
