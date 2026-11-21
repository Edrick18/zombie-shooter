extends SceneTree
## Tests für das Level "Studio" (scripts/game/level): Aufbau, Spawnpunkte je Zone, Navigationsnetz
## (Pfad von jedem Spawnpunkt zum Spielerstart und in die Backstage-Mitte), Sperre der Zombie-Gänge
## für den Spieler, Bühnentreppe, Türkauf (zu wenig und genug Punkte) und Wandkauf (die Waffe
## kommt als Gegenstand in die Ablage des Rucksacks, Abschnitt 18).
##
## Der Spieler ist ein Ersatz (FakePlayer), damit der Test nicht vom Stand des Spieler-Moduls
## abhängt. Skripte, die Game oder Events benutzen, werden erst zur Laufzeit mit load() geholt
## (Abschnitt 13.7).

const Balance := preload("res://scripts/core/balance.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")

const LEVEL_BUILDER_PATH: String = "res://scripts/game/level/level_builder.gd"
## Höchster waagrechter Abstand zwischen Pfadende und Ziel, damit ein Pfad als "kommt an" gilt.
const PATH_TOLERANCE: float = 0.8
const STATE_PLAYING: int = 1
const STATE_PACKING: int = 5


## Ersatz-Spieler: ein Körper mit der Maske des echten Spielers. Tür und Wandkauf brauchen von
## ihm nichts weiter.
class FakePlayer:
	extends CharacterBody3D

	func _init() -> void:
		collision_layer = Balance.LAYER_PLAYER
		collision_mask = Balance.MASK_PLAYER


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


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum und ihr _ready ist gelaufen.
	await process_frame
	_game = root.get_node_or_null("Game")
	_events = root.get_node_or_null("Events")
	_check(_game != null, "Autoload Game hängt im Baum.")
	_check(_events != null, "Autoload Events hängt im Baum.")
	if _game != null and _events != null:
		_events.connect("banner", func(text: String) -> void: _banners.append(text))
		_game.call("start_run", 5)
		_test_build()
		if not _info.is_empty():
			_test_spawn_markers()
			await _test_navigation()
			await _test_player_block()
			await _test_walking()
			await _test_chest_rescue()
			await _test_door()
			await _test_wall_buy()
		_game.set("player", null)
		paused = false

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
	_check(elapsed < 3000, "build() samt Backen dauert unter 3 s (war %d ms)." % elapsed)
	_check(_info.get("player_spawn") is Vector3, "player_spawn ist ein Vector3.")
	_check(_info.get("nav_region") is NavigationRegion3D, "nav_region ist eine NavigationRegion3D.")
	_check(_info.get("door") is StaticBody3D, "door ist ein StaticBody3D.")
	_check(_info.size() == 3, "build() liefert genau die drei Schlüssel des Vertrags.")
	_check(_level.get_node_or_null("NavRegion") == _info.get("nav_region"), "Knoten Level/NavRegion ist die Region.")
	_check(_level.get_node_or_null("Door") == _info.get("door"), "Knoten Level/Door ist die Tür.")
	for weapon_id: String in ["shotgun", "smg"]:
		var wall_buy: Node = _level.get_node_or_null("WallBuy_%s" % weapon_id)
		_check(wall_buy != null, "Knoten Level/WallBuy_%s existiert." % weapon_id)
		if wall_buy != null:
			_check(String(wall_buy.get("weapon_id")) == weapon_id, "WallBuy_%s trägt die richtige Waffe." % weapon_id)
			_check(wall_buy.is_in_group("interactables"), "WallBuy_%s ist in der Gruppe interactables." % weapon_id)
			_check((wall_buy as CollisionObject3D).collision_layer == Balance.LAYER_INTERACTABLES,
					"WallBuy_%s liegt auf der Lage interactables." % weapon_id)
	var door: StaticBody3D = _info["door"]
	_check(door.is_in_group("interactables"), "Die Tür ist in der Gruppe interactables.")
	_check(not door.is_in_group("nav_source"), "Die Tür gehört nicht zu nav_source.")
	_check(door.collision_layer == (Balance.LAYER_WORLD | Balance.LAYER_INTERACTABLES), "Die Tür liegt auf den Lagen world und interactables.")
	_check(int(door.get("cost")) == Balance.DOOR_COST, "Die Tür kostet Balance.DOOR_COST.")
	_check(get_nodes_in_group("nav_source").size() > 20, "Es gibt Geometrie in der Gruppe nav_source.")
	for node: Node in get_nodes_in_group("nav_source"):
		var body: CollisionObject3D = node as CollisionObject3D
		if body == null or (body.collision_layer & Balance.LAYER_WORLD) == 0:
			_fail("nav_source-Knoten %s ist kein Körper der Lage world." % node.get_path())
			break
	var spawn: Vector3 = _info["player_spawn"]
	_check(absf(spawn.x) < Balance.ZONE1_SIZE.x * 0.5 and absf(spawn.z) < Balance.ZONE1_SIZE.z * 0.5,
			"Der Spielerstart liegt in Zone 1.")
	_check(is_zero_approx(spawn.y), "Der Spielerstart liegt auf Bodenhöhe.")


func _test_spawn_markers() -> void:
	var zone1: int = 0
	var zone2: int = 0
	for node: Node in get_nodes_in_group("zombie_spawns"):
		_check(node is Marker3D, "Spawnpunkt %s ist ein Marker3D." % node.name)
		_check(node.has_meta("zone") and node.has_meta("active"), "Spawnpunkt %s trägt Meta zone und active." % node.name)
		var zone: int = int(node.get_meta("zone", 0))
		var active: bool = bool(node.get_meta("active", true))
		if zone == 1:
			zone1 += 1
			_check(active, "Spawnpunkt %s der Zone 1 ist von Anfang an aktiv." % node.name)
		elif zone == 2:
			zone2 += 1
			_check(not active, "Spawnpunkt %s der Zone 2 ist anfangs aus." % node.name)
		else:
			_fail("Spawnpunkt %s hat eine unbekannte Zone %d." % [node.name, zone])
	_check(zone1 == 3, "Zone 1 hat 3 Spawnpunkte (gefunden: %d)." % zone1)
	_check(zone2 == 2, "Zone 2 hat 2 Spawnpunkte (gefunden: %d)." % zone2)


# --- Navigation ---

func _backstage_middle() -> Vector3:
	var min_x: float = Balance.ZONE1_SIZE.x * 0.5
	return Vector3(min_x + 0.4 + Balance.ZONE2_SIZE.x * 0.5, 0.0, Balance.ZONE1_SIZE.z * 0.5 - Balance.ZONE2_SIZE.z * 0.5)


func _test_navigation() -> void:
	var region: NavigationRegion3D = _info["nav_region"]
	var nav_mesh: NavigationMesh = region.navigation_mesh
	_check(nav_mesh != null and nav_mesh.get_polygon_count() > 20, "Das Navigationsnetz ist gebacken und hat Flächen.")
	if nav_mesh == null:
		return
	_check(nav_mesh.agent_radius >= Balance.ZOMBIE_RADIUS * 1.3, "Der Netz-Radius deckt auch die Elite ab.")
	_check(nav_mesh.agent_height >= Balance.ZOMBIE_HEIGHT * 1.3, "Die Netz-Höhe deckt auch die Elite ab.")
	var map: RID = region.get_navigation_map()
	var spawn: Vector3 = _info["player_spawn"]
	var markers: Array[Node] = get_nodes_in_group("zombie_spawns")
	# Die Navigationskarte übernimmt die Region erst nach ein paar Physik-Bildern.
	var waited: int = 0
	while waited < 240:
		await physics_frame
		waited += 1
		if not NavigationServer3D.map_get_path(map, (markers[0] as Node3D).global_position, spawn, true).is_empty():
			break
	_check(waited < 240, "Die Navigationskarte ist nach %d Physik-Bildern bereit." % waited)
	var on_floor: Vector3 = NavigationServer3D.map_get_closest_point(map, spawn)
	_check(absf(on_floor.y) < 0.15, "Das Netz liegt am Spielerstart auf Bodenhöhe (y = %.2f)." % on_floor.y)
	var stage_point: Vector3 = Vector3(0.0, Balance.STAGE_HEIGHT, -Balance.ZONE1_SIZE.z * 0.5 + 2.0)
	var on_stage: Vector3 = NavigationServer3D.map_get_closest_point(map, stage_point)
	_check(on_stage.distance_to(stage_point) < 0.3, "Die Bühne ist begehbar (Netzpunkt %s)." % on_stage)
	var targets: Dictionary = { "Spielerstart": spawn, "Backstage-Mitte": _backstage_middle(), "Bühne": stage_point }
	for node: Node in markers:
		var marker: Marker3D = node as Marker3D
		for label: String in targets:
			var target: Vector3 = targets[label]
			var path: PackedVector3Array = NavigationServer3D.map_get_path(map, marker.global_position, target, true)
			if path.size() < 2:
				_fail("Kein Pfad von %s zu %s." % [marker.name, label])
				continue
			var start_gap: float = _flat_distance(path[0], marker.global_position)
			var end_gap: float = _flat_distance(path[path.size() - 1], target)
			_check(start_gap < PATH_TOLERANCE, "Pfad von %s beginnt am Spawnpunkt (Abstand %.2f)." % [marker.name, start_gap])
			_check(end_gap < PATH_TOLERANCE, "Pfad von %s erreicht %s (Abstand %.2f)." % [marker.name, label, end_gap])


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Sperre der Gänge ---

func _test_player_block() -> void:
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = _level.get_world_3d().direct_space_state
	var spawn: Vector3 = _info["player_spawn"]
	var blocks: Array[Node] = get_nodes_in_group("player_block")
	_check(blocks.size() >= 5, "Jeder Zombie-Eingang hat eine Spieler-Sperre (gefunden: %d)." % blocks.size())
	for node: Node in get_nodes_in_group("zombie_spawns"):
		var marker: Marker3D = node as Marker3D
		var from: Vector3 = marker.global_position + Vector3(0.0, 1.0, 0.0)
		# Aus dem Gang heraus geradeaus bis in den Raum: Richtung = die waagrechte Hauptachse zum Raum.
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


## Punkt im Raum direkt vor dem Gang eines Spawnpunkts (2 m hinter der Wandöffnung, auf 1 m Höhe).
func _room_point_for(marker: Marker3D) -> Vector3:
	var pos: Vector3 = marker.global_position
	var hx: float = Balance.ZONE1_SIZE.x * 0.5
	var hz: float = Balance.ZONE1_SIZE.z * 0.5
	var z2_min_x: float = hx + 0.4
	var z2_max_x: float = z2_min_x + Balance.ZONE2_SIZE.x
	var z2_min_z: float = hz - Balance.ZONE2_SIZE.z
	var result: Vector3 = pos
	if int(marker.get_meta("zone", 1)) == 1:
		if pos.z < -hz:
			result.z = -hz + 2.0
		elif pos.x < -hx:
			result.x = -hx + 2.0
		else:
			result.x = hx - 2.0
	else:
		if pos.z < z2_min_z:
			result.z = z2_min_z + 2.0
		else:
			result.x = z2_max_x - 2.0
	result.y = pos.y + 1.0
	return result


# --- Laufen: Treppe hoch, Gang gesperrt, Zombie kommt heraus ---

func _test_walking() -> void:
	var hx: float = Balance.ZONE1_SIZE.x * 0.5
	var hz: float = Balance.ZONE1_SIZE.z * 0.5
	# Spieler läuft die Showtreppe hoch auf die Bühne.
	var climber: Walker = _add_walker(Vector3(0.0, 0.05, -hz + 7.5), Vector3(0.0, 0.0, -4.0), Balance.MASK_PLAYER | _block_layer)
	# Spieler läuft in den Westeingang und bleibt an der Sperre hängen.
	var intruder: Walker = _add_walker(Vector3(-hx + 2.0, 0.05, 1.0), Vector3(-5.0, 0.0, 0.0), Balance.MASK_PLAYER | _block_layer)
	# Spieler springt gegen die Brüstung zum Publikum.
	var jumper: Walker = _add_walker(Vector3(0.0, 0.05, hz - 1.5), Vector3(0.0, 0.0, 5.0), Balance.MASK_PLAYER | _block_layer)
	jumper.velocity.y = Balance.PLAYER_JUMP_VELOCITY
	# Zombie kommt aus dem Westgang in den Raum.
	var zombie: Walker = _add_walker(Vector3(-hx - 3.0, 0.05, 1.0), Vector3(4.0, 0.0, 0.0), Balance.MASK_ZOMBIE)
	# Zombie kommt aus dem Showtor und läuft über die Bühne die Treppe hinunter.
	var star: Walker = _add_walker(Vector3(0.0, Balance.STAGE_HEIGHT + 0.05, -hz - 3.0), Vector3(0.0, 0.0, 4.0), Balance.MASK_ZOMBIE)
	for i: int in range(150):
		await physics_frame
	_check(climber.position.z < -hz + 4.0 and absf(climber.position.y - Balance.STAGE_HEIGHT) < 0.1,
			"Der Spieler kommt über die Showtreppe auf die Bühne (steht bei %s)." % climber.position)
	_check(intruder.position.x > -hx - 0.1, "Der Spieler kommt nicht in den Zombie-Gang (steht bei x = %.2f)." % intruder.position.x)
	_check(jumper.position.z < hz, "Der Spieler kommt nicht ins Publikum (steht bei z = %.2f)." % jumper.position.z)
	_check(zombie.position.x > -hx + 1.0, "Ein Zombie läuft aus dem Gang in den Raum (steht bei x = %.2f)." % zombie.position.x)
	_check(star.position.z > -hz + 5.0 and star.position.y < 0.1,
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
	var hx: float = Balance.ZONE1_SIZE.x * 0.5
	# Eine Kiste landet tief im Westgang (dort kommt der Spieler nicht hin) und eine im Raum.
	var lost: Area3D = Area3D.new()
	lost.position = Vector3(-hx - 3.0, 0.0, 1.0)
	root.add_child(lost)
	var fine: Area3D = Area3D.new()
	var fine_pos: Vector3 = Vector3(-hx + 3.0, 0.0, 1.0)
	fine.position = fine_pos
	root.add_child(fine)
	_events.emit_signal("chest_dropped", lost)
	_events.emit_signal("chest_dropped", fine)
	var deadline: int = Time.get_ticks_msec() + 3000
	while lost.position.x < -hx + 0.5 and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(lost.position.x > -hx + 0.5 and lost.position.x < -hx + 2.0 and absf(lost.position.z - 1.0) < 0.1,
			"Eine Kiste aus dem Zombie-Gang rutscht vor die Öffnung (liegt bei %s)." % lost.position)
	_check(fine.position.is_equal_approx(fine_pos), "Eine Kiste im Raum bleibt liegen.")
	lost.queue_free()
	fine.queue_free()


# --- Tür ---

func _test_door() -> void:
	var door: StaticBody3D = _info["door"]
	var opened_count: Array[int] = [0]
	door.connect("opened", func() -> void: opened_count[0] += 1)
	var player: FakePlayer = FakePlayer.new()
	root.add_child(player)
	_game.call("start_run", 5)
	_banners.clear()
	var cost: int = int(door.get("cost"))
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
	# Genug Punkte: bezahlt, offen, Spawns der Zone 2 aktiv.
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
	_check(_banners.size() == 1 and _banners[0].contains("offen"), "Das Öffnen gibt ein Banner.")
	for node: Node in get_nodes_in_group("zombie_spawns"):
		_check(bool(node.get_meta("active", false)), "Nach dem Öffnen ist Spawnpunkt %s aktiv." % node.name)
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


# --- Wandkauf ---

func _test_wall_buy() -> void:
	var wall_buy: StaticBody3D = _level.get_node_or_null("WallBuy_shotgun") as StaticBody3D
	if wall_buy == null:
		return
	var def: Dictionary = WeaponDefs.get_def("shotgun")
	var weapon_name: String = String(def["name"])
	var price: int = int(def["price"])
	var player: FakePlayer = FakePlayer.new()
	root.add_child(player)
	_game.call("start_run", 5)
	_game.set("player", player)
	_game.set("auto_pack", false)
	_banners.clear()
	var opened: Array[int] = []
	var on_opened: Callable = func(uid: int) -> void: opened.append(uid)
	_events.connect("backpack_opened", on_opened)
	var backpack: RefCounted = _game.get("backpack") as RefCounted
	_check((wall_buy.get_node("PriceLabel") as Label3D).text == "%d Punkte" % price, "Die Tafel nennt den Preis der Waffe.")
	_check((wall_buy.get_node("NameLabel") as Label3D).text == weapon_name, "Die Tafel nennt den Namen der Waffe.")

	# Ohne Punkte: Hinweis nennt Preis und Fehlbetrag, Kauf scheitert.
	var prompt: String = String(wall_buy.call("get_prompt"))
	_check(prompt == "%s (%d Punkte): dir fehlen %d Punkte" % [weapon_name, price, price],
			"Ohne Punkte nennt der Wandkauf Preis und Fehlbetrag (\"%s\")." % prompt)
	wall_buy.call("interact", player)
	_check((backpack.call("storage_items") as Array).is_empty() and opened.is_empty(), "Ohne Punkte gibt es keine Waffe.")
	_check(_banners.size() == 1 and _banners[0].contains("Nicht genug Punkte"), "Der gescheiterte Kauf gibt ein Banner.")
	_check(int(_game.get("state")) == STATE_PLAYING and not paused, "Nach dem gescheiterten Kauf läuft das Spiel weiter.")

	# Kauf: Punkte weg, die Waffe liegt als gewöhnlicher Gegenstand in der Ablage, der Rucksack öffnet sich.
	_game.call("add_points", price + 100)
	prompt = String(wall_buy.call("get_prompt"))
	_check(prompt == "E: %s kaufen (%d Punkte)" % [weapon_name, price], "Hinweis für den Kauf (\"%s\")." % prompt)
	_banners.clear()
	wall_buy.call("interact", player)
	_check(int(_game.get("points")) == 100, "Der Kaufpreis wurde abgezogen.")
	var stored: Array = backpack.call("storage_items")
	_check(stored.size() == 1 and String(stored[0]["id"]) == "shotgun" and int(stored[0]["level"]) == 1,
			"Die Waffe liegt als gewöhnlicher Gegenstand in der Ablage.")
	_check(opened.size() == 1 and stored.size() == 1 and opened[0] == int(stored[0]["uid"]), "Der Rucksack öffnet sich mit dem neuen Gegenstand.")
	_check(int(_game.get("state")) == STATE_PACKING and paused, "Nach dem Kauf ist der Rucksack offen (State PACKING, Pause).")
	_check(_banners.size() == 1 and _banners[0].contains(weapon_name) and _banners[0].contains("gekauft"), "Der Kauf gibt ein Banner.")
	_check((backpack.call("placed_items") as Array).is_empty(), "Eingeräumt ist die Waffe noch nicht: Das macht der Spieler im Rucksack.")
	_check(String((_game.get("loadout") as Array)[0]["id"]) == "pistol", "Bis dahin hält der Spieler weiter die Dienstpistole.")

	# Solange der Rucksack offen ist, kauft ein weiterer Druck nichts und kostet nichts.
	_game.call("add_points", price)
	wall_buy.call("interact", player)
	_check(int(_game.get("points")) == price + 100 and (backpack.call("storage_items") as Array).size() == 1,
			"Bei offenem Rucksack wird nichts gekauft und nichts abgezogen.")
	_check(bool(_game.call("close_backpack")), "Der Rucksack lässt sich schließen.")

	# Zweiter Kauf: ein weiteres Exemplar (kein Auffüllen von Munition mehr).
	wall_buy.call("interact", player)
	_check(int(_game.get("points")) == 100 and (backpack.call("storage_items") as Array).size() == 2,
			"Der zweite Kauf gibt ein zweites Exemplar für den vollen Preis.")
	_check(opened.size() == 2, "Auch der zweite Kauf öffnet den Rucksack.")
	_game.call("close_backpack")

	# Pause: kein Kauf, keine Punkte weg.
	_game.call("add_points", price)
	_game.call("set_paused", true)
	wall_buy.call("interact", player)
	_check(int(_game.get("points")) == price + 100 and (backpack.call("storage_items") as Array).size() == 2,
			"Außerhalb des laufenden Spiels kostet der Wandkauf nichts.")
	_game.call("set_paused", false)

	# Mit auto_pack räumt sich die Waffe selbst ein: Der Spieler hält sie sofort.
	_game.call("start_run", 5)
	_game.set("auto_pack", true)
	backpack = _game.get("backpack") as RefCounted
	_game.call("add_points", price * 2)
	wall_buy.call("interact", player)
	var loadout: Array = _game.get("loadout")
	_check(int(_game.get("state")) == STATE_PLAYING and not paused, "Mit auto_pack bleibt der Rucksack zu.")
	_check(loadout.size() == 1 and String(loadout[0]["id"]) == "shotgun" and int(loadout[0]["level"]) == 1 and int(loadout[0]["hands"]) == 2,
			"Mit auto_pack liegt die gekaufte Schrotflinte im Rucksack und in der Hand.")
	# Noch eine: Zwei gleiche Waffen werden zur nächsten Rarität kombiniert.
	wall_buy.call("interact", player)
	loadout = _game.get("loadout")
	_check(int(_game.get("points")) == 0 and loadout.size() == 1 and int(loadout[0]["level"]) == 2,
			"Zwei gekaufte Schrotflinten ergeben mit auto_pack eine ungewöhnliche.")
	_game.set("auto_pack", false)

	# Die zweite Wand kennt ihre eigene Waffe und ihren Preis.
	var smg: Node = _level.get_node_or_null("WallBuy_smg")
	if smg != null:
		prompt = String(smg.call("get_prompt"))
		_check(prompt.contains(WeaponDefs.display_name("smg")) and prompt.contains(str(int(WeaponDefs.get_def("smg")["price"]))),
				"Der zweite Wandkauf nennt seine Waffe und ihren Preis (\"%s\")." % prompt)
		_game.call("add_points", int(WeaponDefs.get_def("smg")["price"]))
		smg.call("interact", player)
		stored = backpack.call("storage_items")
		_check(int(_game.get("points")) == 0 and stored.size() == 1 and String(stored[0]["id"]) == "smg",
				"Der zweite Wandkauf legt die Maschinenpistole in die Ablage.")
		_game.call("close_backpack")
	# Ungültiger Spieler: kein Absturz, nichts passiert, nichts wird abgezogen.
	_game.call("add_points", price)
	var points_before: int = int(_game.get("points"))
	wall_buy.call("interact", null)
	_check(int(_game.get("points")) == points_before, "Ohne Spieler wird nichts gekauft.")
	_game.set("player", null)
	_check(String(wall_buy.call("get_prompt")).contains(weapon_name), "Ohne Spieler zeigt der Wandkauf den Kaufhinweis.")
	_events.disconnect("backpack_opened", on_opened)
	await process_frame
	player.queue_free()


# --- Helfer ---

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	printerr("FEHLER: %s" % message)
