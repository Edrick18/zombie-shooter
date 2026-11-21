extends SceneTree
## Tests für das Level "Studio" (scripts/game/level): Aufbau, vier kaufbare Räume mit Türen und
## Preisen, Spawnpunkte je Zone (erst nach dem Kauf aktiv), Navigationsnetz (kein Weg durch eine
## geschlossene Tür, jeder offene Raum von der Bühne erreichbar und umgekehrt), Sperre der
## Zombie-Gänge für den Spieler, Bühnentreppe, Türkauf (zu wenig und genug Punkte),
## Verbindungstüren zwischen zwei Räumen, Rundweg, Boden unter jedem begehbaren Fleck, neuer Lauf.
## Wandkäufe gibt es nicht mehr.
##
## Der Spieler ist ein Ersatz (FakePlayer), damit der Test nicht vom Stand des Spieler-Moduls
## abhängt. Skripte, die Game oder Events benutzen, werden erst zur Laufzeit mit load() geholt
## (Abschnitt 13.7).

const Balance := preload("res://scripts/core/balance.gd")

const LEVEL_BUILDER_PATH: String = "res://scripts/game/level/level_builder.gd"
const ZOMBIE_PATH: String = "res://scripts/game/zombies/zombie.gd"
## So nah muss ein Zombie seinem Ziel kommen (waagrecht), damit er als angekommen gilt.
const ZOMBIE_ARRIVAL: float = 2.2
## Zeit in Sekunden Spielzeit, die echte Zombies für ihren längsten Weg durch das Studio bekommen.
const ZOMBIE_TIME_LIMIT: float = 18.0
const WALL_BUY_PATH: String = "res://scripts/game/level/wall_buy.gd"
## Höchster waagrechter Abstand zwischen Pfadende und Ziel, damit ein Pfad als "kommt an" gilt.
const PATH_TOLERANCE: float = 0.8
## Ab diesem Abstand zwischen Pfadende und Ziel gilt ein Raum als nicht erreichbar.
const PATH_BLOCKED_GAP: float = 3.0
## So viele Physik-Bilder darf die Navigationskarte brauchen, bis ein gekaufter Raum erreichbar ist.
const NAV_UPDATE_FRAMES: int = 5
## Erwartete Räume in der Reihenfolge ihrer Preise: Zone, Name, Knoten der Tür an der Bühne.
const ROOMS: Array[Dictionary] = [
	{ "zone": 2, "name": "Backstage", "door": "Door" },
	{ "zone": 3, "name": "Kantine", "door": "DoorCanteen" },
	{ "zone": 4, "name": "Garderobe", "door": "DoorWardrobe" },
	{ "zone": 5, "name": "Regieraum", "door": "DoorControlRoom" },
]
const STAGE_SPAWNS: int = 3
const ROOM_SPAWNS: int = 2
## Raster der Begehbarkeits-Probe in Metern.
const GRID: float = 0.25
## Wanddicke des Levels: So weit darf ein begehbarer Fleck über die Innenmaße hinausragen (Türöffnung).
const WALL: float = 0.4


## Ersatz-Spieler: ein Körper mit der Maske des echten Spielers. Die Tür braucht von ihm nichts weiter.
class FakePlayer:
	extends CharacterBody3D

	func _init() -> void:
		collision_layer = Balance.LAYER_PLAYER
		collision_mask = Balance.MASK_PLAYER


## Ziel für echte Zombies: steht still, zählt Schläge und hat, was zombie.gd vom Spieler liest.
class Bait:
	extends Node3D
	var is_dead: bool = false
	var hits: int = 0

	func take_damage(_amount: float) -> void:
		hits += 1


## Läufer für die Physik-Proben: Kapsel wie Spieler und Zombie, läuft stur in eine Richtung.
class Walker:
	extends CharacterBody3D
	var walk: Vector3 = Vector3.ZERO

	func _init() -> void:
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = Balance.PLAYER_RADIUS
		capsule.height = Balance.PLAYER_HEIGHT
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.shape = capsule
		shape.position = Vector3(0.0, Balance.PLAYER_HEIGHT * 0.5, 0.0)
		add_child(shape)

	func _physics_process(delta: float) -> void:
		velocity.x = walk.x
		velocity.z = walk.z
		velocity.y -= Balance.GRAVITY * delta
		move_and_slide()


var _failures := 0
var _checks := 0
var _game: Node
var _events: Node
var _banners: Array[String] = []
var _level: Node3D
var _info: Dictionary = {}
var _block_layer: int = 0
var _hx: float = 0.0
var _hz: float = 0.0
## Längste Wartezeit in Physik-Bildern, bis ein gekaufter Raum im Navigationsnetz erreichbar war.
var _slowest_update: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum und ihr _ready ist gelaufen.
	await process_frame
	_game = root.get_node_or_null("Game")
	_events = root.get_node_or_null("Events")
	_hx = Balance.ZONE1_SIZE.x * 0.5
	_hz = Balance.ZONE1_SIZE.z * 0.5
	_check(_game != null, "Autoload Game hängt im Baum.")
	_check(_events != null, "Autoload Events hängt im Baum.")
	if _game != null and _events != null:
		_events.connect("banner", func(text: String) -> void: _banners.append(text))
		_game.call("start_run", 5)
		_test_build()
		if _info.has("rooms") and _info.has("links") and _info.has("door") and _info.has("nav_region"):
			_test_no_wall_buys()
			_test_rooms_and_doors()
			_test_spawn_markers()
			await _test_player_spawn_free()
			await _test_navigation_closed()
			await _test_player_block()
			await _test_walking()
			await _test_chest_rescue()
			await _test_door()
			await _test_room_purchases()
			await _test_all_open()
			await _test_new_run()
		_game.set("player", null)
		paused = false

	print("Ein gekaufter Raum war spätestens nach %d Physik-Bildern erreichbar." % _slowest_update)
	if _failures == 0:
		print("Alle Level-Tests bestanden (%d Prüfungen)." % _checks)
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


# --- Aufbau ---

func _test_build() -> void:
	var builder_script: GDScript = load(LEVEL_BUILDER_PATH) as GDScript
	_check(builder_script != null, "level_builder.gd lädt.")
	if builder_script == null:
		return
	_block_layer = Balance.LAYER_PLAYER_BLOCK
	_check(_block_layer != 0, "Die Sperr-Lage für den Spieler ist festgelegt.")
	_check((_block_layer & (Balance.MASK_ZOMBIE | Balance.MASK_SHOT | Balance.MASK_INTERACT)) == 0,
			"Zombies, Schüsse und der Blick-Strahl treffen die Sperr-Lage nicht.")
	_check(Balance.ZONE1_SIZE.x * Balance.ZONE1_SIZE.z >= 22.0 * 18.0 * 1.35 and Balance.ZONE1_SIZE.x * Balance.ZONE1_SIZE.z <= 22.0 * 18.0 * 1.45,
			"Die Bühne hat etwa 40 %% mehr Fläche als früher (22 × 18 m), jetzt %.1f × %.1f m." % [Balance.ZONE1_SIZE.x, Balance.ZONE1_SIZE.z])
	_level = Node3D.new()
	_level.name = "Level"
	root.add_child(_level)
	var started: int = Time.get_ticks_msec()
	var result: Variant = builder_script.new().call("build", _level)
	var elapsed: int = Time.get_ticks_msec() - started
	_check(result is Dictionary, "build() liefert ein Dictionary.")
	if not (result is Dictionary):
		return
	_info = result
	print("build() samt Backen: %d ms." % elapsed)
	_check(elapsed < 3000, "build() samt Backen dauert unter 3 s (war %d ms)." % elapsed)
	_check(_info.get("player_spawn") is Vector3, "player_spawn ist ein Vector3.")
	_check(_info.get("nav_region") is NavigationRegion3D, "nav_region ist eine NavigationRegion3D.")
	_check(_info.get("door") is StaticBody3D, "door ist ein StaticBody3D.")
	_check(_info.get("rooms") is Array, "rooms ist ein Array.")
	_check(_info.get("links") is Array, "links ist ein Array.")
	_check(_info.size() == 5, "build() liefert genau die fünf Schlüssel des Vertrags (sind %d)." % _info.size())
	_check(_level.get_node_or_null("NavRegion") == _info.get("nav_region"), "Knoten Level/NavRegion ist die Region der Bühne.")
	_check(_level.get_node_or_null("Door") == _info.get("door"), "Knoten Level/Door ist die Tür zum Backstage.")
	_check(get_nodes_in_group("nav_source").size() > 60, "Es gibt Geometrie in der Gruppe nav_source.")
	for node: Node in get_nodes_in_group("nav_source"):
		var body: CollisionObject3D = node as CollisionObject3D
		if body == null or (body.collision_layer & Balance.LAYER_WORLD) == 0:
			_fail("nav_source-Knoten %s ist kein Körper der Lage world." % node.get_path())
			break
	var spawn: Vector3 = _info["player_spawn"]
	_check(absf(spawn.x) < _hx and absf(spawn.z) < _hz, "Der Spielerstart liegt in Zone 1.")
	_check(is_zero_approx(spawn.y), "Der Spielerstart liegt auf Bodenhöhe.")


func _test_no_wall_buys() -> void:
	_check(not FileAccess.file_exists(WALL_BUY_PATH) and not ResourceLoader.exists(WALL_BUY_PATH), "Das Skript wall_buy.gd gibt es nicht mehr.")
	var found: Array[String] = []
	var open: Array[Node] = [_level]
	while not open.is_empty():
		var node: Node = open.pop_back()
		var script: Script = node.get_script() as Script
		if String(node.name).to_lower().contains("wallbuy") or node.get("weapon_id") != null or (script != null and script.resource_path.contains("wall_buy")):
			found.append(String(node.get_path()))
		open.append_array(node.get_children())
	_check(found.is_empty(), "Im Level gibt es keinen Wandkauf mehr (gefunden: %s)." % str(found))
	# Kaufen lässt sich im Level nur noch eine Tür.
	for node: Node in get_nodes_in_group("interactables"):
		_check(node.is_in_group("doors"), "Interaktionsobjekt %s ist eine Tür." % node.name)


func _test_rooms_and_doors() -> void:
	var rooms: Array = _info["rooms"]
	var links: Array = _info["links"]
	_check(rooms.size() == ROOMS.size(), "Es gibt %d kaufbare Räume (sind %d)." % [ROOMS.size(), rooms.size()])
	_check(Balance.DOOR_COSTS == [750, 1250, 2000, 3000], "Die Türpreise sind 750, 1250, 2000 und 3000 (sind %s)." % str(Balance.DOOR_COSTS))
	_check(Balance.DOOR_COSTS[0] == Balance.DOOR_COST, "Der erste Türpreis ist Balance.DOOR_COST.")
	_check(links.size() == 2, "Es gibt 2 Verbindungstüren (sind %d)." % links.size())
	_check(get_nodes_in_group("doors").size() == ROOMS.size() + 2, "Das Level hat %d Türen (sind %d)." % [ROOMS.size() + 2, get_nodes_in_group("doors").size()])
	var at_stage: int = 0
	for i: int in range(mini(rooms.size(), ROOMS.size())):
		var room: Dictionary = rooms[i]
		var expected: Dictionary = ROOMS[i]
		var title: String = String(expected["name"])
		for key: String in ["zone", "key", "name", "cost", "door", "nav_region", "center", "size"]:
			_check(room.has(key), "Raum %s nennt \"%s\"." % [title, key])
		_check(int(room.get("zone", 0)) == int(expected["zone"]), "%s ist Zone %d." % [title, int(expected["zone"])])
		_check(String(room.get("name", "")) == title, "Raum %d heißt %s." % [i + 1, title])
		_check(int(room.get("cost", 0)) == Balance.DOOR_COSTS[i], "%s kostet %d Punkte." % [title, Balance.DOOR_COSTS[i]])
		var size: Vector3 = room.get("size", Vector3.ZERO)
		_check(is_equal_approx(size.x, Balance.ZONE2_SIZE.x) and is_equal_approx(size.z, Balance.ZONE2_SIZE.z), "%s hat die Maße aus Balance.ZONE2_SIZE." % title)
		var door: StaticBody3D = room.get("door") as StaticBody3D
		_check(door != null and door == _level.get_node_or_null(String(expected["door"])), "Die Tür von %s ist der Knoten Level/%s." % [title, String(expected["door"])])
		if door == null:
			continue
		_check(door.is_in_group("interactables"), "Die Tür von %s ist in der Gruppe interactables." % title)
		_check(not door.is_in_group("nav_source"), "Die Tür von %s gehört nicht zu nav_source." % title)
		_check(door.collision_layer == (Balance.LAYER_WORLD | Balance.LAYER_INTERACTABLES), "Die Tür von %s liegt auf den Lagen world und interactables." % title)
		_check(int(door.get("cost")) == Balance.DOOR_COSTS[i] and int(door.get("zone")) == int(expected["zone"]) and String(door.get("zone_name")) == title,
				"Die Tür von %s trägt Zone, Namen und Preis." % title)
		_check(not bool(door.get("is_open")), "Die Tür von %s ist anfangs zu." % title)
		var prompt: String = String(door.call("get_prompt"))
		_check(prompt.contains(title) and prompt.contains(str(Balance.DOOR_COSTS[i])), "Der Hinweis der Tür nennt %s und den Preis (\"%s\")." % [title, prompt])
		var leaf: Node = door.get_node_or_null("Leaf")
		var written: Array[String] = []
		if leaf != null:
			for child: Node in leaf.get_children():
				if child is Label3D:
					written.append((child as Label3D).text)
		_check(written.has(title.to_upper()) and written.has(str(Balance.DOOR_COSTS[i])), "Auf dem Türblatt stehen %s und der Preis." % title)
		if absf(absf(door.global_position.x) - (_hx + WALL * 0.5)) < 0.01 and absf(door.global_position.z) < _hz:
			at_stage += 1
		var region: NavigationRegion3D = room.get("nav_region") as NavigationRegion3D
		_check(region != null and not region.enabled, "Das Netz von %s ist anfangs aus." % title)
		var zone_node: Node3D = _level.get_node_or_null("Zone%d" % int(expected["zone"])) as Node3D
		_check(zone_node != null and not zone_node.visible, "%s ist bis zum Kauf ausgeblendet." % title)
		_check(_has_label(_level.get_node_or_null("Zone1"), title.to_upper()), "Auf der Bühne hängt ein Schild mit dem Namen %s." % title)
	_check(at_stage >= 2, "Mindestens zwei Räume haben ihre Tür direkt an der Bühne (sind %d)." % at_stage)
	for link: Variant in links:
		var link_door: StaticBody3D = link as StaticBody3D
		_check(link_door != null and link_door.is_in_group("doors") and int(link_door.get("back_zone")) > 1,
				"Eine Verbindungstür kennt den Raum auf beiden Seiten.")


## true, wenn unter node ein Label3D hängt, dessen Text needle enthält.
func _has_label(node: Node, needle: String) -> bool:
	if node == null:
		return false
	if node is Label3D and (node as Label3D).text.contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_label(child, needle):
			return true
	return false


func _test_spawn_markers() -> void:
	var counts: Dictionary = {}
	for node: Node in get_nodes_in_group("zombie_spawns"):
		_check(node is Marker3D, "Spawnpunkt %s ist ein Marker3D." % node.name)
		_check(node.has_meta("zone") and node.has_meta("active"), "Spawnpunkt %s trägt Meta zone und active." % node.name)
		var zone: int = int(node.get_meta("zone", 0))
		counts[zone] = int(counts.get(zone, 0)) + 1
		_check(zone >= 1 and zone <= ROOMS.size() + 1, "Spawnpunkt %s hat eine bekannte Zone (ist %d)." % [node.name, zone])
	_check(int(counts.get(1, 0)) == STAGE_SPAWNS, "Zone 1 hat %d Spawnpunkte (gefunden: %d)." % [STAGE_SPAWNS, int(counts.get(1, 0))])
	for expected: Dictionary in ROOMS:
		var zone: int = int(expected["zone"])
		_check(int(counts.get(zone, 0)) == ROOM_SPAWNS, "%s (Zone %d) hat %d Spawnpunkte (gefunden: %d)." % [String(expected["name"]), zone, ROOM_SPAWNS, int(counts.get(zone, 0))])
	_check_active_zones([], "Am Anfang")


## Prüft an jedem Spawnpunkt: aktiv genau dann, wenn er zur Bühne oder zu einem offenen Raum gehört.
func _check_active_zones(open_zones: Array, label: String) -> void:
	for node: Node in get_nodes_in_group("zombie_spawns"):
		var zone: int = int(node.get_meta("zone", 0))
		var expected: bool = zone == 1 or open_zones.has(zone)
		_check(bool(node.get_meta("active", true)) == expected,
				"%s ist Spawnpunkt %s (Zone %d) %s." % [label, node.name, zone, "aktiv" if expected else "aus"])


# --- Spielerstart ---

func _test_player_spawn_free() -> void:
	await physics_frame
	await physics_frame
	var spawn: Vector3 = _info["player_spawn"]
	_check(_capsule_free(spawn), "Am Spielerstart steht nichts im Weg.")
	for offset: Vector3 in [Vector3(1.5, 0.0, 0.0), Vector3(-1.5, 0.0, 0.0), Vector3(0.0, 0.0, 1.5), Vector3(0.0, 0.0, -1.5)]:
		_check(_capsule_free(spawn + offset), "1,5 m neben dem Spielerstart (%s) ist frei." % offset)
	var space: PhysicsDirectSpaceState3D = _level.get_world_3d().direct_space_state
	var down: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(spawn + Vector3(0.0, 1.0, 0.0), spawn + Vector3(0.0, -2.0, 0.0), Balance.LAYER_WORLD))
	_check(not down.is_empty() and absf((down["position"] as Vector3).y) < 0.02, "Unter dem Spielerstart liegt der Boden.")
	# Freie Sicht nach vorn zur Bühne (dorthin schaut der Spieler am Anfang).
	var ahead: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(spawn + Vector3(0.0, 1.6, 0.0), spawn + Vector3(0.0, 1.6, -9.0), Balance.LAYER_WORLD))
	_check(ahead.is_empty(), "Vom Spielerstart ist der Blick zur Bühne frei.")


## true, wenn eine Spielerkapsel mit den Füßen bei feet weder Welt noch Spieler-Sperre berührt.
func _capsule_free(feet: Vector3) -> bool:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = Balance.PLAYER_RADIUS
	capsule.height = Balance.PLAYER_HEIGHT
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = Balance.LAYER_WORLD | _block_layer
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, Balance.PLAYER_HEIGHT * 0.5 + 0.05, 0.0))
	return _level.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- Navigation ---

func _room_center(index: int) -> Vector3:
	return ((_info["rooms"] as Array)[index] as Dictionary)["center"]


func _map() -> RID:
	return (_info["nav_region"] as NavigationRegion3D).get_navigation_map()


## Abstand zwischen dem Ende des Pfads von from nach to und dem Ziel (INF ohne Pfad).
func _path_gap(from: Vector3, to: Vector3) -> float:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(_map(), from, to, true)
	if path.size() < 2:
		return INF
	return _flat_distance(path[path.size() - 1], to)


## Wartet, bis der Pfad von from nach to ankommt. Gibt die Zahl der Physik-Bilder zurück, -1 nach limit.
func _frames_until_reachable(from: Vector3, to: Vector3, limit: int) -> int:
	for frame: int in range(limit + 1):
		if _path_gap(from, to) < PATH_TOLERANCE:
			return frame
		await physics_frame
	return -1


func _test_navigation_closed() -> void:
	var region: NavigationRegion3D = _info["nav_region"]
	var nav_mesh: NavigationMesh = region.navigation_mesh
	_check(nav_mesh != null and nav_mesh.get_polygon_count() > 20, "Das Navigationsnetz der Bühne ist gebacken und hat Flächen.")
	if nav_mesh == null:
		return
	_check(nav_mesh.agent_radius >= Balance.ZOMBIE_RADIUS * 1.3, "Der Netz-Radius deckt auch die Elite ab.")
	_check(nav_mesh.agent_height >= Balance.ZOMBIE_HEIGHT * 1.3, "Die Netz-Höhe deckt auch die Elite ab.")
	var rooms: Array = _info["rooms"]
	for i: int in range(rooms.size()):
		var room_region: NavigationRegion3D = (rooms[i] as Dictionary)["nav_region"]
		_check(room_region.navigation_mesh != null and room_region.navigation_mesh.get_polygon_count() > 4,
				"%s hat ein eigenes gebackenes Netz." % String((rooms[i] as Dictionary)["name"]))
	var map: RID = _map()
	var spawn: Vector3 = _info["player_spawn"]
	var markers: Array[Node] = get_nodes_in_group("zombie_spawns")
	var first: Node3D = null
	for node: Node in markers:
		if int(node.get_meta("zone", 0)) == 1:
			first = node as Node3D
			break
	_check(first != null, "Es gibt einen Spawnpunkt der Zone 1.")
	if first == null:
		return
	# Die Navigationskarte übernimmt die Region erst nach ein paar Physik-Bildern.
	var waited: int = await _frames_until_reachable(first.global_position, spawn, 240)
	_check(waited >= 0, "Die Navigationskarte ist nach %d Physik-Bildern bereit." % waited)
	var on_floor: Vector3 = NavigationServer3D.map_get_closest_point(map, spawn)
	_check(absf(on_floor.y) < 0.15 and _flat_distance(on_floor, spawn) < 0.1, "Das Netz liegt am Spielerstart auf Bodenhöhe (Punkt %s)." % on_floor)
	var stage_point: Vector3 = Vector3(0.0, Balance.STAGE_HEIGHT, -_hz + 2.0)
	var on_stage: Vector3 = NavigationServer3D.map_get_closest_point(map, stage_point)
	_check(on_stage.distance_to(stage_point) < 0.3, "Die Bühne ist begehbar (Netzpunkt %s)." % on_stage)
	var targets: Dictionary = { "Spielerstart": spawn, "Bühne": stage_point }
	for node: Node in markers:
		var marker: Marker3D = node as Marker3D
		if int(marker.get_meta("zone", 0)) != 1:
			continue
		for label: String in targets:
			_check_path(marker.global_position, targets[label], "von %s zu %s" % [marker.name, label])
	# Kein Weg durch eine geschlossene Tür: Kein Raum ist erreichbar, auch nicht für Zombies der Bühne.
	for i: int in range(rooms.size()):
		var gap: float = _path_gap(spawn, _room_center(i))
		_check(gap > PATH_BLOCKED_GAP, "Solange die Tür zu ist, führt kein Pfad in den Raum %s (Abstand zum Ziel %.2f)." % [String((rooms[i] as Dictionary)["name"]), gap])


## Prüft, dass der Pfad am Start beginnt und am Ziel ankommt.
func _check_path(from: Vector3, to: Vector3, label: String) -> void:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(_map(), from, to, true)
	if path.size() < 2:
		_fail("Kein Pfad %s." % label)
		return
	var start_gap: float = _flat_distance(path[0], from)
	var end_gap: float = _flat_distance(path[path.size() - 1], to)
	_check(start_gap < PATH_TOLERANCE, "Der Pfad %s beginnt am Start (Abstand %.2f)." % [label, start_gap])
	_check(end_gap < PATH_TOLERANCE, "Der Pfad %s kommt an (Abstand %.2f)." % [label, end_gap])


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Sperre der Gänge ---

func _test_player_block() -> void:
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = _level.get_world_3d().direct_space_state
	var spawn: Vector3 = _info["player_spawn"]
	var blocks: Array[Node] = get_nodes_in_group("player_block")
	var markers: Array[Node] = get_nodes_in_group("zombie_spawns")
	_check(blocks.size() >= markers.size(), "Jeder Zombie-Eingang hat eine Spieler-Sperre (gefunden: %d)." % blocks.size())
	for node: Node in markers:
		var marker: Marker3D = node as Marker3D
		var from: Vector3 = marker.global_position + Vector3(0.0, 1.0, 0.0)
		# Aus dem Gang heraus geradeaus bis in den Raum.
		var inside: Vector3 = _room_point_for(marker)
		var player_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(inside, from, _block_layer)
		_check(not space.intersect_ray(player_query).is_empty(), "Der Gang von %s ist für den Spieler gesperrt." % marker.name)
		var zombie_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, inside, Balance.LAYER_WORLD)
		_check(space.intersect_ray(zombie_query).is_empty(), "Der Gang von %s ist für Zombies frei." % marker.name)
		var shot_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(inside, from, Balance.MASK_SHOT)
		_check(space.intersect_ray(shot_query).is_empty(), "Schüsse in den Gang von %s kommen durch." % marker.name)
	# Balance.MASK_PLAYER enthält die Sperr-Lage.
	var player: FakePlayer = FakePlayer.new()
	player.position = spawn
	root.add_child(player)
	_game.set("player", player)
	await physics_frame
	await physics_frame
	_check((player.collision_mask & _block_layer) != 0, "Die Maske des Spielers enthält die Sperr-Lage.")
	_game.set("player", null)
	player.queue_free()


## Innenfläche (x, z) der Zone eines Spawnpunkts: die Bühne oder sein Raum.
func _zone_rect(zone: int) -> Rect2:
	if zone <= 1:
		return Rect2(-_hx, -_hz, _hx * 2.0, _hz * 2.0)
	for entry: Variant in _info["rooms"]:
		var room: Dictionary = entry
		if int(room["zone"]) == zone:
			var center: Vector3 = room["center"]
			var size: Vector3 = room["size"]
			return Rect2(center.x - size.x * 0.5, center.z - size.z * 0.5, size.x, size.z)
	return Rect2()


## Punkt im Raum direkt vor dem Gang eines Spawnpunkts (2 m hinter der Wandöffnung, auf 1 m Höhe).
func _room_point_for(marker: Marker3D) -> Vector3:
	var pos: Vector3 = marker.global_position
	var rect: Rect2 = _zone_rect(int(marker.get_meta("zone", 1)))
	var result: Vector3 = pos
	if pos.x < rect.position.x:
		result.x = rect.position.x + 2.0
	elif pos.x > rect.end.x:
		result.x = rect.end.x - 2.0
	if pos.z < rect.position.y:
		result.z = rect.position.y + 2.0
	elif pos.z > rect.end.y:
		result.z = rect.end.y - 2.0
	result.y = pos.y + 1.0
	return result


# --- Laufen: Treppe hoch, Gang gesperrt, Zombie kommt heraus ---

func _test_walking() -> void:
	var spawn_b: Node3D = _level.get_node_or_null("Entrances/Entrance_B/Spawn_B") as Node3D
	_check(spawn_b != null, "Es gibt den Spawnpunkt Spawn_B.")
	if spawn_b == null:
		return
	var gang: Vector3 = spawn_b.global_position
	var mouth: Vector3 = _room_point_for(spawn_b as Marker3D)
	mouth.y = 0.05
	var out: Vector3 = Vector3(gang.x - mouth.x, 0.0, gang.z - mouth.z).normalized()
	# Spieler läuft die Showtreppe hoch auf die Bühne.
	var climber: Walker = _add_walker(Vector3(0.0, 0.05, -_hz + 8.5), Vector3(0.0, 0.0, -4.0), Balance.MASK_PLAYER | _block_layer)
	# Spieler läuft in den Zombie-Eingang B und bleibt an der Sperre hängen.
	var intruder: Walker = _add_walker(mouth, out * 5.0, Balance.MASK_PLAYER | _block_layer)
	# Spieler springt gegen die Brüstung zum Publikum.
	var jumper: Walker = _add_walker(Vector3(0.0, 0.05, _hz - 1.5), Vector3(0.0, 0.0, 5.0), Balance.MASK_PLAYER | _block_layer)
	jumper.velocity.y = Balance.PLAYER_JUMP_VELOCITY
	# Zombie kommt aus dem Gang B in den Raum.
	var zombie: Walker = _add_walker(Vector3(gang.x, 0.05, gang.z), -out * 4.0, Balance.MASK_ZOMBIE)
	# Zombie kommt aus dem Showtor und läuft über die Bühne die Treppe hinunter.
	var star: Walker = _add_walker(Vector3(0.0, Balance.STAGE_HEIGHT + 0.05, -_hz - 3.0), Vector3(0.0, 0.0, 4.0), Balance.MASK_ZOMBIE)
	for i: int in range(150):
		await physics_frame
	_check(climber.position.z < -_hz + 4.0 and absf(climber.position.y - Balance.STAGE_HEIGHT) < 0.1,
			"Der Spieler kommt über die Showtreppe auf die Bühne (steht bei %s)." % climber.position)
	var intruded: float = (intruder.position - mouth).dot(out)
	_check(intruded < 2.2, "Der Spieler kommt nicht in den Zombie-Gang (kam %.2f m weit, die Wand liegt 2 m entfernt)." % intruded)
	_check(jumper.position.z < _hz, "Der Spieler kommt nicht ins Publikum (steht bei z = %.2f)." % jumper.position.z)
	var came_out: float = (zombie.position - gang).dot(-out)
	_check(came_out > 5.0 and absf(zombie.position.y) < 0.1, "Ein Zombie läuft aus dem Gang in den Raum (kam %.2f m weit)." % came_out)
	_check(star.position.z > -_hz + 5.5 and star.position.y < 0.1,
			"Ein Zombie läuft vom Showtor über die Bühne die Treppe hinunter (steht bei %s)." % star.position)
	for walker: Walker in [climber, intruder, jumper, zombie, star]:
		walker.queue_free()


func _add_walker(pos: Vector3, walk: Vector3, mask: int) -> Walker:
	var walker: Walker = Walker.new()
	walker.collision_layer = 0
	walker.collision_mask = mask
	walker.position = pos
	walker.walk = walk
	root.add_child(walker)
	return walker


# --- Kiste im Zombie-Gang ---

func _test_chest_rescue() -> void:
	# Je eine Kiste landet tief in einem Gang der Bühne und eines Raums (dort kommt der Spieler
	# nicht hin), eine weitere liegt im Raum.
	var lost: Array[Area3D] = []
	var rects: Array[Rect2] = []
	for path: String in ["Entrances/Entrance_B/Spawn_B", "Entrances/Entrance_E/Spawn_E"]:
		var marker: Marker3D = _level.get_node_or_null(path) as Marker3D
		_check(marker != null, "Es gibt den Spawnpunkt %s." % path)
		if marker == null:
			continue
		var chest: Area3D = Area3D.new()
		chest.position = marker.global_position
		root.add_child(chest)
		lost.append(chest)
		rects.append(_zone_rect(int(marker.get_meta("zone", 1))))
	var fine: Area3D = Area3D.new()
	var fine_pos: Vector3 = Vector3(-_hx + 3.0, 0.0, 1.0)
	fine.position = fine_pos
	root.add_child(fine)
	for chest: Area3D in lost:
		_events.emit_signal("chest_dropped", chest)
	_events.emit_signal("chest_dropped", fine)
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		var all_home: bool = true
		for i: int in range(lost.size()):
			if not rects[i].grow(-0.5).has_point(Vector2(lost[i].position.x, lost[i].position.z)):
				all_home = false
		if all_home:
			break
		await process_frame
	for i: int in range(lost.size()):
		var flat: Vector2 = Vector2(lost[i].position.x, lost[i].position.z)
		_check(rects[i].grow(-0.5).has_point(flat) and not rects[i].grow(-2.0).has_point(flat),
				"Eine Kiste aus dem Zombie-Gang rutscht vor die Öffnung (liegt bei %s)." % lost[i].position)
		_check(_capsule_free(lost[i].position), "Dort kann der Spieler die Kiste aufheben.")
		lost[i].queue_free()
	_check(fine.position.is_equal_approx(fine_pos), "Eine Kiste im Raum bleibt liegen.")
	fine.queue_free()


# --- Tür zum Backstage: Kauf mit zu wenig und mit genug Punkten ---

func _test_door() -> void:
	var door: StaticBody3D = _info["door"]
	var opened_count: Array[int] = [0]
	door.connect("opened", func() -> void: opened_count[0] += 1)
	var player: FakePlayer = FakePlayer.new()
	root.add_child(player)
	_game.call("start_run", 5)
	_banners.clear()
	var cost: int = int(door.get("cost"))
	_check(cost == Balance.DOOR_COST, "Die Tür zum Backstage kostet Balance.DOOR_COST.")
	var prompt: String = String(door.call("get_prompt"))
	_check(prompt.contains(str(cost)) and prompt.contains("Backstage"), "Der Tür-Hinweis nennt Zone und Preis (\"%s\")." % prompt)
	_check(prompt.contains("fehlen"), "Ohne Punkte sagt der Tür-Hinweis, was fehlt (\"%s\")." % prompt)
	# Zu wenig Punkte: Tür bleibt zu, nichts wird abgezogen, Banner erscheint.
	_game.call("add_points", cost - 50)
	door.call("interact", player)
	_check(not bool(door.get("is_open")), "Mit zu wenig Punkten bleibt die Tür zu.")
	_check(int(_game.get("points")) == cost - 50, "Mit zu wenig Punkten wird nichts abgezogen.")
	_check(_banners.size() == 1 and _banners[0].contains("Nicht genug Punkte"), "Zu wenig Punkte gibt ein Banner.")
	_check(opened_count[0] == 0, "Das Signal opened kam noch nicht.")
	var space: PhysicsDirectSpaceState3D = _level.get_world_3d().direct_space_state
	var through_from: Vector3 = door.global_position + Vector3(-2.0, 1.0, 0.0)
	var through_to: Vector3 = door.global_position + Vector3(2.0, 1.0, 0.0)
	var through: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(through_from, through_to, Balance.LAYER_WORLD)
	_check(space.intersect_ray(through).get("collider") == door, "Die geschlossene Tür versperrt den Durchgang.")
	# Genug Punkte: bezahlt, offen, Spawns der Zone 2 aktiv, alle anderen Räume bleiben zu.
	_game.call("add_points", 100)
	prompt = String(door.call("get_prompt"))
	_check(prompt == "E – Backstage öffnen (%d)" % cost, "Mit genug Punkten lädt der Hinweis zum Kauf ein (\"%s\")." % prompt)
	_banners.clear()
	door.call("interact", player)
	_check(bool(door.get("is_open")), "Mit genug Punkten geht die Tür auf.")
	_check(int(_game.get("points")) == 50, "Der Preis der Tür wurde abgezogen (Rest %d)." % int(_game.get("points")))
	_check(opened_count[0] == 1, "Das Signal opened kam genau einmal.")
	_check(String(door.call("get_prompt")) == "", "Die offene Tür zeigt keinen Hinweis mehr.")
	_check(not door.is_in_group("interactables"), "Die offene Tür ist kein Interaktionsobjekt mehr.")
	_check(_banners.size() == 1 and _banners[0] == "Backstage ist offen!", "Das Öffnen gibt ein Banner (%s)." % str(_banners))
	_check_active_zones([2], "Nach dem Kauf des Backstage")
	for i: int in range(1, ROOMS.size()):
		var other: Node = _level.get_node_or_null(String(ROOMS[i]["door"]))
		_check(other != null and not bool(other.get("is_open")), "Die Tür von %s bleibt zu." % String(ROOMS[i]["name"]))
	# Zweites Drücken und zweites open() ändern nichts.
	door.call("interact", player)
	door.call("open")
	_check(int(_game.get("points")) == 50 and opened_count[0] == 1, "Die Tür wirkt nur einmal.")
	for i: int in range(3):
		await physics_frame
	space = _level.get_world_3d().direct_space_state
	_check(space.intersect_ray(through).is_empty(), "Durch die offene Tür ist der Weg frei.")
	# Türblatt fährt hoch und verschwindet.
	var leaf: Node3D = door.get_node_or_null("Leaf") as Node3D
	_check(leaf != null, "Die Tür hat ein Türblatt (Knoten Leaf).")
	# Headless laufen Bilder beliebig schnell: nach Uhrzeit warten, nicht nach Bildern.
	var deadline: int = Time.get_ticks_msec() + 4000
	while leaf != null and leaf.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(leaf != null and not leaf.visible, "Das Türblatt ist nach dem Hochfahren verschwunden.")
	player.queue_free()


# --- Die übrigen Räume, Verbindungstüren, Navigation nach dem Kauf ---

## Prüft, dass genau die Räume in open_zones ein Netz haben, zu sehen und von der Bühne erreichbar sind.
func _check_rooms_reachable(open_zones: Array, label: String) -> void:
	var rooms: Array = _info["rooms"]
	var spawn: Vector3 = _info["player_spawn"]
	for i: int in range(rooms.size()):
		var room: Dictionary = rooms[i]
		var zone: int = int(room["zone"])
		var title: String = String(room["name"])
		var open: bool = open_zones.has(zone)
		var region: NavigationRegion3D = room["nav_region"]
		var zone_node: Node3D = _level.get_node_or_null("Zone%d" % zone) as Node3D
		_check(region.enabled == open, "%s: Das Netz von %s ist %s." % [label, title, "an" if open else "aus"])
		_check(zone_node != null and zone_node.visible == open, "%s: %s ist %s." % [label, title, "zu sehen" if open else "ausgeblendet"])
		if open:
			var frames: int = await _frames_until_reachable(spawn, _room_center(i), NAV_UPDATE_FRAMES)
			_check(frames >= 0, "%s: %s ist von der Bühne aus erreichbar (nach %d Physik-Bildern)." % [label, title, frames])
			_slowest_update = maxi(_slowest_update, frames)
			_check_path(_room_center(i), spawn, "aus %s zurück zur Bühne" % title)
		else:
			var gap: float = _path_gap(spawn, _room_center(i))
			for _i: int in range(NAV_UPDATE_FRAMES):
				if gap > PATH_BLOCKED_GAP:
					break
				await physics_frame
				gap = _path_gap(spawn, _room_center(i))
			_check(gap > PATH_BLOCKED_GAP, "%s: In den Raum %s führt kein Pfad (Abstand zum Ziel %.2f)." % [label, title, gap])
	# Jeder aktive Spawnpunkt erreicht den Spieler auf der Bühne und in jedem offenen Raum.
	for node: Node in get_nodes_in_group("zombie_spawns"):
		var marker: Marker3D = node as Marker3D
		if not bool(marker.get_meta("active", false)):
			continue
		_check_path(marker.global_position, spawn, "von %s zum Spielerstart (%s)" % [marker.name, label])
		for i: int in range(rooms.size()):
			if open_zones.has(int((rooms[i] as Dictionary)["zone"])):
				_check_path(marker.global_position, _room_center(i), "von %s nach %s (%s)" % [marker.name, String((rooms[i] as Dictionary)["name"]), label])


func _door_of(index: int) -> StaticBody3D:
	return _level.get_node_or_null(String(ROOMS[index]["door"])) as StaticBody3D


func _test_room_purchases() -> void:
	var link_east: StaticBody3D = _level.get_node_or_null("LinkEast") as StaticBody3D
	var link_west: StaticBody3D = _level.get_node_or_null("LinkWest") as StaticBody3D
	_check(link_east != null and link_west != null, "Es gibt die Verbindungstüren LinkEast und LinkWest.")
	if link_east == null or link_west == null:
		return
	var player: FakePlayer = FakePlayer.new()
	root.add_child(player)
	# Stand: Backstage ist gekauft (Test davor), 50 Punkte übrig.
	await _check_rooms_reachable([2], "Backstage offen")

	# Die Verbindungstür im Backstage verkauft die Garderobe und bleibt bis dahin zu.
	_check(not bool(link_east.get("is_open")), "Die Verbindungstür Ost ist zu, solange die Garderobe fehlt.")
	_check(int(link_east.get("zone")) == 4 and int(link_east.get("cost")) == Balance.DOOR_COSTS[2], "Die Verbindungstür Ost verkauft die Garderobe für %d." % Balance.DOOR_COSTS[2])
	var prompt: String = String(link_east.call("get_prompt"))
	_check(prompt.contains("Garderobe") and prompt.contains(str(Balance.DOOR_COSTS[2])), "Ihr Hinweis nennt Garderobe und Preis (\"%s\")." % prompt)
	var space: PhysicsDirectSpaceState3D = _level.get_world_3d().direct_space_state
	var link_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			link_east.global_position + Vector3(0.0, 1.0, 2.0), link_east.global_position + Vector3(0.0, 1.0, -2.0), Balance.LAYER_WORLD)
	_check(space.intersect_ray(link_ray).get("collider") == link_east, "Die geschlossene Verbindungstür versperrt den Durchgang.")

	# Kantine an ihrer Tür an der Bühne kaufen.
	var canteen: StaticBody3D = _door_of(1)
	_game.call("spend_points", int(_game.get("points")))
	_game.call("add_points", Balance.DOOR_COSTS[1] - 1)
	canteen.call("interact", player)
	_check(not bool(canteen.get("is_open")) and int(_game.get("points")) == Balance.DOOR_COSTS[1] - 1, "Ein Punkt zu wenig: Die Kantine bleibt zu.")
	_game.call("add_points", 1)
	_banners.clear()
	canteen.call("interact", player)
	_check(bool(canteen.get("is_open")) and int(_game.get("points")) == 0, "Für %d Punkte geht die Kantine auf." % Balance.DOOR_COSTS[1])
	_check(_banners == ["Kantine ist offen!"], "Der Kauf der Kantine gibt genau ein Banner (%s)." % str(_banners))
	_check_active_zones([2, 3], "Nach dem Kauf der Kantine")
	_check(not bool(link_west.get("is_open")) and int(link_west.get("zone")) == 5 and int(link_west.get("cost")) == Balance.DOOR_COSTS[3],
			"Die Verbindungstür West verkauft jetzt den Regieraum für %d." % Balance.DOOR_COSTS[3])
	await _check_rooms_reachable([2, 3], "Backstage und Kantine offen")

	# Garderobe an der Verbindungstür kaufen (vom Backstage aus): Beide Türen der Garderobe gehen auf.
	var wardrobe: StaticBody3D = _door_of(2)
	_game.call("add_points", Balance.DOOR_COSTS[2] + 30)
	_banners.clear()
	link_east.call("interact", player)
	_check(int(_game.get("points")) == 30, "Die Garderobe kostet an der Verbindungstür %d Punkte." % Balance.DOOR_COSTS[2])
	_check(bool(link_east.get("is_open")), "Die Verbindungstür Ost ist offen, sobald beide Räume gekauft sind.")
	_check(bool(wardrobe.get("is_open")), "Mit der Garderobe geht auch ihre Tür an der Bühne auf.")
	_check(_banners == ["Garderobe ist offen!"], "Der Kauf der Garderobe gibt genau ein Banner (%s)." % str(_banners))
	_check(String(link_east.call("get_prompt")) == "" and String(wardrobe.call("get_prompt")) == "", "Offene Türen zeigen keinen Hinweis.")
	_check_active_zones([2, 3, 4], "Nach dem Kauf der Garderobe")
	for i: int in range(3):
		await physics_frame
	space = _level.get_world_3d().direct_space_state
	_check(space.intersect_ray(link_ray).is_empty(), "Durch die offene Verbindungstür ist der Weg frei.")
	await _check_rooms_reachable([2, 3, 4], "Drei Räume offen")

	# Regieraum ohne Bezahlung öffnen (open): Die Verbindungstür West geht von selbst mit auf.
	var control: StaticBody3D = _door_of(3)
	_banners.clear()
	control.call("open")
	_check(bool(control.get("is_open")) and bool(link_west.get("is_open")), "Mit dem Regieraum geht auch die Verbindungstür West auf.")
	_check(int(_game.get("points")) == 30, "open() kostet nichts.")
	_check(_banners == ["Regieraum ist offen!"], "Das Öffnen des Regieraums gibt genau ein Banner (%s)." % str(_banners))
	_check_active_zones([2, 3, 4, 5], "Nach dem Öffnen des Regieraums")
	_check(get_nodes_in_group("interactables").is_empty(), "Sind alle Räume offen, gibt es nichts mehr zu kaufen.")
	await _check_rooms_reachable([2, 3, 4, 5], "Alle Räume offen")
	player.queue_free()


# --- Alle Räume offen: Rundweg, kein eingesperrter Fleck, Boden überall ---

func _test_all_open() -> void:
	var rooms: Array = _info["rooms"]
	# Rundweg je Seite: Bühne - vorderer Raum - Verbindungstür - hinterer Raum - Bühne. Der Weg
	# durch die Verbindungstür ist kürzer als der Umweg über die Bühne.
	for pair: Array in [[0, 2, "LinkEast"], [1, 3, "LinkWest"]]:
		var front: Vector3 = _room_center(int(pair[0]))
		var back: Vector3 = _room_center(int(pair[1]))
		var link: Node3D = _level.get_node(String(pair[2])) as Node3D
		var path: PackedVector3Array = NavigationServer3D.map_get_path(_map(), front, back, true)
		var near_link: float = INF
		for i: int in range(path.size() - 1):
			near_link = minf(near_link, _segment_distance(path[i], path[i + 1], link.global_position))
		_check(path.size() >= 2 and near_link < 1.0, "Der Weg von %s nach %s führt durch die Verbindungstür (Abstand %.2f)." % [
				String((rooms[int(pair[0])] as Dictionary)["name"]), String((rooms[int(pair[1])] as Dictionary)["name"]), near_link])
	await _test_round_trip()
	_test_flood_fill()
	await _test_real_zombies()


## Ein Läufer mit der Kapsel des Spielers geht je Seite den Rundweg ab: durch die Tür in den
## vorderen Raum, durch die Verbindungstür in den hinteren und durch dessen Tür zurück zur Bühne.
func _test_round_trip() -> void:
	var rooms: Array = _info["rooms"]
	for pair: Array in [[0, 2, "LinkEast"], [1, 3, "LinkWest"]]:
		var front_door: Node3D = (rooms[int(pair[0])] as Dictionary)["door"]
		var back_door: Node3D = (rooms[int(pair[1])] as Dictionary)["door"]
		var link: Node3D = _level.get_node(String(pair[2])) as Node3D
		var side: float = signf(front_door.global_position.x)
		var stops: Array[Vector3] = [
			front_door.global_position + Vector3(side * 2.3, 0.0, 0.0),
			link.global_position + Vector3(0.0, 0.0, 2.2),
			link.global_position + Vector3(0.0, 0.0, -2.2),
			back_door.global_position + Vector3(side * 2.3, 0.0, 0.0),
			back_door.global_position + Vector3(-side * 2.3, 0.0, 0.0),
		]
		var walker: Walker = _add_walker(front_door.global_position + Vector3(-side * 2.3, 0.05, 0.0), Vector3.ZERO, Balance.MASK_PLAYER | _block_layer)
		var lowest: float = 0.0
		var reached: int = 0
		for stop: Vector3 in stops:
			var arrived: bool = false
			for _frame: int in range(360):
				var to_stop: Vector3 = stop - walker.position
				to_stop.y = 0.0
				if to_stop.length() < 0.25:
					arrived = true
					break
				walker.walk = to_stop.normalized() * Balance.PLAYER_WALK_SPEED
				await physics_frame
				lowest = minf(lowest, walker.position.y)
			if not arrived:
				break
			reached += 1
		_check(reached == stops.size(), "Der Rundweg über %s lässt sich ablaufen (%d von %d Etappen, steht bei %s)." % [
				String(pair[2]), reached, stops.size(), walker.position])
		_check(lowest > -0.05, "Auf dem Rundweg über %s fällt niemand durch den Boden (tiefster Punkt y = %.2f)." % [String(pair[2]), lowest])
		walker.queue_free()


## Kürzester waagrechter Abstand des Punkts p zur Strecke a-b.
func _segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var start: Vector2 = Vector2(a.x, a.z)
	var along: Vector2 = Vector2(b.x, b.z) - start
	var point: Vector2 = Vector2(p.x, p.z)
	var t: float = 0.0 if along.length_squared() < 0.000001 else clampf((point - start).dot(along) / along.length_squared(), 0.0, 1.0)
	return (start + along * t).distance_to(point)


## Füllt vom Spielerstart aus alle Flecken, auf denen die Kapsel des Spielers stehen kann (Raster
## GRID, alle Türen offen). Daran hängen vier Prüfungen: kein Loch nach draußen, jeder Raum ist
## weitgehend begehbar, kein größerer freier Fleck ist abgeschnitten (hinter Requisiten
## eingesperrt), und unter jedem begehbaren Fleck liegt Boden. Dazu: Das Navigationsnetz der
## Bühne und der Räume liegt dort, wo auch der Spieler hinkommt (eine Kiste liegt nie unerreichbar).
func _test_flood_fill() -> void:
	var rooms: Array = _info["rooms"]
	var rects: Array[Rect2] = [_zone_rect(1)]
	var bounds: Rect2 = rects[0]
	for entry: Variant in rooms:
		var rect: Rect2 = _zone_rect(int((entry as Dictionary)["zone"]))
		rects.append(rect)
		bounds = bounds.merge(rect)
	bounds = bounds.grow(8.0)
	var columns: int = int(ceil(bounds.size.x / GRID))
	var rows: int = int(ceil(bounds.size.y / GRID))
	# 0 = unbekannt, 1 = frei, 2 = belegt, 3 = frei und vom Spielerstart erreicht.
	var cells: PackedByteArray = PackedByteArray()
	cells.resize(columns * rows)
	var spawn: Vector3 = _info["player_spawn"]
	var start: Vector2i = Vector2i(int((spawn.x - bounds.position.x) / GRID), int((spawn.z - bounds.position.y) / GRID))
	var started: int = Time.get_ticks_msec()
	_fill_from(cells, columns, rows, bounds, start, 3)
	# Erreichte Flecken: alle innerhalb der Bühne oder eines Raums (samt Türöffnung), Boden darunter.
	var space: PhysicsDirectSpaceState3D = _level.get_world_3d().direct_space_state
	var reached_per_zone: Array[int] = []
	reached_per_zone.resize(rects.size())
	reached_per_zone.fill(0)
	var leaks: int = 0
	var holes: int = 0
	var first_bad: Vector2 = Vector2.ZERO
	for index: int in range(cells.size()):
		if cells[index] != 3:
			continue
		var point: Vector2 = _cell_point(index, columns, bounds)
		var inside: bool = false
		for i: int in range(rects.size()):
			if rects[i].has_point(point):
				reached_per_zone[i] += 1
			if rects[i].grow(WALL + 0.05).has_point(point):
				inside = true
		if not inside:
			leaks += 1
			first_bad = point
			continue
		var down: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(point.x, 0.5, point.y), Vector3(point.x, -3.0, point.y), Balance.LAYER_WORLD))
		# Der Fuß einer Rampe darf knapp über dem Boden liegen, ein Loch läge darunter.
		if down.is_empty() or (down["position"] as Vector3).y < -0.02 or (down["position"] as Vector3).y > 0.1:
			holes += 1
			first_bad = point
	_check(leaks == 0, "Der Spieler kommt nirgends aus dem Studio hinaus (Flecken außerhalb: %d, einer bei %s)." % [leaks, first_bad])
	_check(holes == 0, "Unter jedem begehbaren Fleck liegt der Boden (Löcher: %d, eines bei %s)." % [holes, first_bad])
	for i: int in range(rects.size()):
		var share: float = float(reached_per_zone[i]) * GRID * GRID / rects[i].get_area()
		var title: String = "Die Bühne" if i == 0 else String((rooms[i - 1] as Dictionary)["name"])
		_check(share > 0.6, "%s ist zu %d %% begehbar (mindestens 60 %%)." % [title, int(share * 100.0)])
	# Freie Flecken, die vom Start aus nicht erreicht wurden: Mehr als 1 m² am Stück wäre eine Falle.
	var biggest: int = 0
	var biggest_at: Vector2 = Vector2.ZERO
	for i: int in range(rects.size()):
		var rect: Rect2 = rects[i]
		var x: float = rect.position.x + GRID * 0.5
		while x < rect.end.x:
			var z: float = rect.position.y + GRID * 0.5
			while z < rect.end.y:
				var cell: Vector2i = Vector2i(int((x - bounds.position.x) / GRID), int((z - bounds.position.y) / GRID))
				if _cell_state(cells, columns, bounds, cell) == 1:
					var count: int = _fill_from(cells, columns, rows, bounds, cell, 2)
					if count > biggest:
						biggest = count
						biggest_at = Vector2(x, z)
				z += GRID
			x += GRID
	_check(float(biggest) * GRID * GRID < 1.0, "Kein begehbarer Fleck ist hinter Requisiten eingesperrt (größter: %.2f m² bei %s)." % [float(biggest) * GRID * GRID, biggest_at])
	# Das Navigationsnetz liegt dort, wo der Spieler hinkommt (außer in den gesperrten Zombie-Gängen).
	var stranded: int = 0
	var regions: Array[NavigationRegion3D] = [_info["nav_region"] as NavigationRegion3D]
	for entry: Variant in rooms:
		regions.append((entry as Dictionary)["nav_region"] as NavigationRegion3D)
	var polygons: int = 0
	for region: NavigationRegion3D in regions:
		var nav_mesh: NavigationMesh = region.navigation_mesh
		var vertices: PackedVector3Array = nav_mesh.get_vertices()
		for p: int in range(nav_mesh.get_polygon_count()):
			var middle: Vector3 = Vector3.ZERO
			var polygon: PackedInt32Array = nav_mesh.get_polygon(p)
			for corner: int in polygon:
				middle += vertices[corner]
			middle /= float(polygon.size())
			if middle.y > 0.1:
				continue
			var in_room: bool = false
			for rect: Rect2 in rects:
				if rect.has_point(Vector2(middle.x, middle.z)):
					in_room = true
			if not in_room:
				continue
			polygons += 1
			var cell: Vector2i = Vector2i(int((middle.x - bounds.position.x) / GRID), int((middle.z - bounds.position.y) / GRID))
			var found: bool = false
			for dx: int in range(-2, 3):
				for dz: int in range(-2, 3):
					var at: Vector2i = cell + Vector2i(dx, dz)
					if at.x >= 0 and at.y >= 0 and at.x < columns and at.y < rows and cells[at.y * columns + at.x] == 3:
						found = true
			if not found:
				stranded += 1
				first_bad = Vector2(middle.x, middle.z)
	_check(polygons > 100 and stranded == 0, "Jede Fläche des Navigationsnetzes am Boden ist für den Spieler erreichbar (%d Flächen, unerreichbar: %d, eine bei %s)." % [polygons, stranded, first_bad])
	print("Begehbarkeits-Probe: %d ms." % (Time.get_ticks_msec() - started))


func _cell_point(index: int, columns: int, bounds: Rect2) -> Vector2:
	return Vector2(bounds.position.x + (float(index % columns) + 0.5) * GRID, bounds.position.y + (float(index / columns) + 0.5) * GRID)


## Zustand einer Zelle (1 = frei, 2 = belegt, 3 = erreicht). Fragt die Physik beim ersten Mal.
func _cell_state(cells: PackedByteArray, columns: int, bounds: Rect2, cell: Vector2i) -> int:
	var index: int = cell.y * columns + cell.x
	if cells[index] == 0:
		var point: Vector2 = _cell_point(index, columns, bounds)
		cells[index] = 1 if _capsule_free(Vector3(point.x, 0.0, point.y)) else 2
	return cells[index]


## Markiert von start aus alle zusammenhängenden freien Zellen mit mark und gibt ihre Zahl zurück.
func _fill_from(cells: PackedByteArray, columns: int, rows: int, bounds: Rect2, start: Vector2i, mark: int) -> int:
	if _cell_state(cells, columns, bounds, start) != 1:
		return 0
	var count: int = 0
	var open: Array[Vector2i] = [start]
	cells[start.y * columns + start.x] = mark
	while not open.is_empty():
		var cell: Vector2i = open.pop_back()
		count += 1
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= columns or next.y >= rows:
				continue
			if _cell_state(cells, columns, bounds, next) == 1:
				cells[next.y * columns + next.x] = mark
				open.append(next)
	return count


# --- Echte Zombies finden in die Räume hinein und wieder heraus ---

func _test_real_zombies() -> void:
	var zombie_script: GDScript = load(ZOMBIE_PATH) as GDScript
	_check(zombie_script != null, "zombie.gd lädt.")
	if zombie_script == null:
		return
	var bait: Bait = Bait.new()
	root.add_child(bait)
	_game.set("player", bait)
	# Hinein: Das Ziel steht mitten in der Garderobe. Ein Sprinter kommt von der Bühne, einer aus
	# der Kantine (durch zwei Türen), die Elite (der größte Körper) aus dem Backstage durch die
	# Verbindungstür.
	bait.global_position = _room_center(2)
	await _zombies_reach(zombie_script, bait, [["sprinter", "B"], ["sprinter", "G"], ["elite", "E"]], "in die Garderobe")
	# Heraus: Das Ziel steht am Spielerstart. Aus jedem Raum kommt ein Sprinter aus seinem Gang.
	bait.global_position = _info["player_spawn"]
	await _zombies_reach(zombie_script, bait, [["sprinter", "D"], ["sprinter", "F"], ["sprinter", "I"], ["sprinter", "K"]], "zum Spielerstart")
	_game.set("player", null)
	bait.queue_free()


## Setzt je Eintrag [Typ, Kennbuchstabe des Eingangs] einen echten Zombie auf den Spawnpunkt und
## wartet, bis alle beim Ziel sind (oder die Zeit um ist).
func _zombies_reach(zombie_script: GDScript, bait: Bait, starts: Array, label: String) -> void:
	var zombies: Array[Node3D] = []
	var names: Array[String] = []
	for start: Array in starts:
		var marker: Node3D = _level.get_node_or_null("Entrances/Entrance_%s/Spawn_%s" % [String(start[1]), String(start[1])]) as Node3D
		_check(marker != null, "Es gibt den Spawnpunkt Spawn_%s." % String(start[1]))
		if marker == null:
			continue
		var zombie: Node3D = zombie_script.new() as Node3D
		zombie.call("setup", String(start[0]), 3)
		zombie.position = marker.global_position
		root.add_child(zombie)
		zombies.append(zombie)
		names.append("%s aus Gang %s" % [String(start[0]), String(start[1])])
	var arrived: Array[bool] = []
	arrived.resize(zombies.size())
	arrived.fill(false)
	var lowest: float = 0.0
	var frames: int = int(ZOMBIE_TIME_LIMIT * float(Engine.physics_ticks_per_second))
	for _frame: int in range(frames):
		await physics_frame
		var waiting: bool = false
		for i: int in range(zombies.size()):
			if arrived[i]:
				continue
			if not is_instance_valid(zombies[i]):
				arrived[i] = true
				continue
			lowest = minf(lowest, zombies[i].global_position.y)
			if _flat_distance(zombies[i].global_position, bait.global_position) < ZOMBIE_ARRIVAL:
				arrived[i] = true
				zombies[i].queue_free()
			else:
				waiting = true
		if not waiting:
			break
	for i: int in range(zombies.size()):
		var where: String = "angekommen"
		if not arrived[i] and is_instance_valid(zombies[i]):
			where = "steht bei %s" % zombies[i].global_position
			zombies[i].queue_free()
		_check(arrived[i], "Ein echter Zombie (%s) findet %s (%s)." % [names[i], label, where])
	_check(lowest > -0.1, "Kein Zombie fällt auf dem Weg %s durch den Boden (tiefster Punkt y = %.2f)." % [label, lowest])
	await physics_frame


# --- Neuer Lauf: alles wieder zu ---

func _test_new_run() -> void:
	_game.call("start_run", 5)
	for i: int in range(3):
		await physics_frame
	for i: int in range(ROOMS.size()):
		var door: StaticBody3D = _door_of(i)
		_check(not bool(door.get("is_open")) and door.is_in_group("interactables"), "Nach run_started ist die Tür von %s wieder zu." % String(ROOMS[i]["name"]))
		_check(int(door.get("zone")) == int(ROOMS[i]["zone"]) and int(door.get("cost")) == Balance.DOOR_COSTS[i], "Sie verkauft wieder %s." % String(ROOMS[i]["name"]))
	var link_east: StaticBody3D = _level.get_node("LinkEast") as StaticBody3D
	var link_west: StaticBody3D = _level.get_node("LinkWest") as StaticBody3D
	_check(not bool(link_east.get("is_open")) and not bool(link_west.get("is_open")), "Die Verbindungstüren sind wieder zu.")
	_check_active_zones([], "Nach run_started")
	await _check_rooms_reachable([], "Neuer Lauf")
	var space: PhysicsDirectSpaceState3D = _level.get_world_3d().direct_space_state
	for i: int in range(ROOMS.size()):
		var door: StaticBody3D = _door_of(i)
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				door.global_position + Vector3(-2.0, 1.0, 0.0), door.global_position + Vector3(2.0, 1.0, 0.0), Balance.LAYER_WORLD)
		_check(space.intersect_ray(ray).get("collider") == door, "Die Tür von %s versperrt den Durchgang wieder." % String(ROOMS[i]["name"]))

	# Andere Reihenfolge: zuerst die Garderobe (an der Bühne). Die Verbindungstür bleibt zu und
	# verkauft jetzt den Backstage. Dort gekauft, gehen sie und die Backstage-Tür auf.
	var wardrobe: StaticBody3D = _door_of(2)
	var backstage: StaticBody3D = _door_of(0)
	wardrobe.call("open")
	_check(bool(wardrobe.get("is_open")) and not bool(link_east.get("is_open")) and not bool(backstage.get("is_open")),
			"Nur die Garderobe ist offen: Verbindungstür und Backstage bleiben zu.")
	_check(int(link_east.get("zone")) == 2 and int(link_east.get("cost")) == Balance.DOOR_COST and String(link_east.get("zone_name")) == "Backstage",
			"Von der Garderobe aus verkauft die Verbindungstür den Backstage für %d." % Balance.DOOR_COST)
	_check_active_zones([4], "Nur Garderobe offen")
	await _check_rooms_reachable([4], "Nur Garderobe offen")
	_game.call("add_points", Balance.DOOR_COST)
	_banners.clear()
	link_east.call("interact", null)
	_check(int(_game.get("points")) == 0 and bool(link_east.get("is_open")) and bool(backstage.get("is_open")),
			"Der Kauf an der Verbindungstür öffnet sie und die Backstage-Tür.")
	_check(_banners == ["Backstage ist offen!"], "Dazu kommt genau ein Banner (%s)." % str(_banners))
	_check_active_zones([2, 4], "Garderobe und Backstage offen")
	await _check_rooms_reachable([2, 4], "Garderobe und Backstage offen")
	_game.call("start_run", 5)
	_check(int(link_east.get("zone")) == 4 and not bool(link_east.get("is_open")), "Ein weiterer neuer Lauf stellt die Verbindungstür zurück.")
	_check_active_zones([], "Nach dem zweiten run_started")


# --- Helfer ---

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	printerr("FEHLER: %s" % message)
