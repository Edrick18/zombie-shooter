extends SceneTree
## Tests für das Modul Spieler: player.gd, weapon_controller.gd, view_model.gd.
## Baut headless eine kleine Welt (Boden, Spieler, Ersatz-Zombies auf Lage 3 in Gruppe "zombies")
## und prüft Schaden, Kopftreffer, Durchschlag mit Schadensabfall, Schrotkugeln, Magazin und
## unendliche Munition, Nachladen, Waffen aus dem Rucksack (eine Hand, zwei Hände, beidhändig),
## Abgleich bei build_changed, Faktoren für Schaden und Nachladen, Raketen-Explosion, Signale je
## Hand, Leben, Tod, Bewegung, Stufen und Interaktion.
##
## Startet in _initialize und wartet ein Bild (Autoloads, siehe Architektur 13.7). Die Skripte
## des Spiels werden zur Laufzeit mit load() geholt, weil sie Game und Events benutzen.

const Balance := preload("res://scripts/core/balance.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const WeaponState := preload("res://scripts/core/weapon_state.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")

const HEADSHOT_RATIO: float = Balance.HEADSHOT_HEIGHT_RATIO


## Ersatz-Zombie: Quader auf Lage 3 in Gruppe "zombies", merkt sich jeden Treffer.
class Dummy:
	extends StaticBody3D
	var is_dead: bool = false
	var body_height: float = 3.0
	var hits: Array[Dictionary] = []
	## Gemeinsames Protokoll des Tests (Reihenfolge von Schaden und Signalen).
	var journal: Array = []

	func build(dummy_name: String, height: float, width: float) -> void:
		name = dummy_name
		body_height = height
		collision_layer = Balance.LAYER_ZOMBIES
		collision_mask = 0
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(width, height, 0.6)
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.shape = box
		shape.position = Vector3(0.0, height * 0.5, 0.0)
		add_child(shape)
		add_to_group("zombies")

	func take_damage(amount: float, info: Dictionary) -> void:
		hits.append({"amount": amount, "info": info})
		journal.append("damage:%s" % name)

	func is_headshot(hit_position: Vector3) -> bool:
		return hit_position.y - global_position.y > body_height * HEADSHOT_RATIO

	func total_damage() -> float:
		var sum: float = 0.0
		for hit: Dictionary in hits:
			sum += float(hit["amount"])
		return sum


## Ersatz-Interaktionsobjekt auf Lage 5 in Gruppe "interactables".
class Switch:
	extends StaticBody3D
	var used: int = 0
	var last_user: Node3D = null

	func build() -> void:
		name = "Switch"
		collision_layer = Balance.LAYER_INTERACTABLES
		collision_mask = 0
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(0.6, 0.6, 0.2)
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.shape = box
		add_child(shape)
		add_to_group("interactables")

	func get_prompt() -> String:
		return "E – Testknopf drücken"

	func interact(player: Node3D) -> void:
		used += 1
		last_user = player


var _failures := 0
var _checks := 0
var _game: Node
var _events: Node
var _player: CharacterBody3D
var _weapons: Node
## Signalname -> Liste der Argument-Listen, in der Reihenfolge des Eintreffens.
var _received: Dictionary = {}
## Reihenfolge von take_damage und Signalen eines Schusses.
var _journal: Array = []
var _dummies: Array[Dummy] = []


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
		_listen()
		_build_world()
		_game.start_run(11)
		await _settle()
		_test_setup()
		await _test_single_shot()
		await _test_headshot()
		await _test_pierce()
		await _test_shotgun()
		await _test_reload()
		await _test_loadout()
		await _test_akimbo()
		await _test_mixed_akimbo()
		await _test_two_handed()
		await _test_resync()
		await _test_multipliers()
		await _test_rocket()
		await _test_fire_input()
		await _test_not_playing()
		await _test_view_model()
		await _test_health_and_death()
		await _test_movement()
		await _test_steps()
		await _test_interaction()
		await _test_mouse_look()
		_release_all_actions()
	if _failures == 0:
		print("test_player_weapons: alle Prüfungen bestanden (%d)." % _checks)
	quit(1 if _failures > 0 else 0)


# --- Aufbau ---


func _listen() -> void:
	_events.connect("bullet_hit", func(zombie: Node3D, damage: float, info: Dictionary) -> void:
		_record("bullet_hit", [zombie, damage, info])
		_journal.append("bullet_hit:%s" % zombie.name))
	_events.connect("weapon_fired", func(id: String) -> void:
		_record("weapon_fired", [id])
		_journal.append("weapon_fired"))
	_events.connect("weapon_changed", func(id: String) -> void: _record("weapon_changed", [id]))
	_events.connect("ammo_changed", func(mag: int, reserve: int) -> void: _record("ammo_changed", [mag, reserve]))
	_events.connect("reload_started", func(id: String, duration: float) -> void: _record("reload_started", [id, duration]))
	_events.connect("reload_finished", func(id: String) -> void: _record("reload_finished", [id]))
	_events.connect("loadout_changed", func() -> void: _record("loadout_changed", []))
	_events.connect("hand_ammo_changed", func(hand: int, mag: int, size: int) -> void: _record("hand_ammo_changed", [hand, mag, size]))
	_events.connect("hand_reload_started", func(hand: int, duration: float) -> void: _record("hand_reload_started", [hand, duration]))
	_events.connect("hand_reload_finished", func(hand: int) -> void: _record("hand_reload_finished", [hand]))
	_events.connect("player_health_changed", func(hp: float, max_hp: float) -> void: _record("player_health_changed", [hp, max_hp]))
	_events.connect("player_damaged", func(amount: float) -> void: _record("player_damaged", [amount]))
	_events.connect("player_died", func() -> void: _record("player_died", []))
	_events.connect("interact_prompt_changed", func(text: String) -> void: _record("interact_prompt_changed", [text]))
	_events.connect("banner", func(text: String) -> void: _record("banner", [text]))


func _build_world() -> void:
	_add_block("Floor", Vector3(0.0, -0.5, 0.0), Vector3(600.0, 1.0, 600.0))
	var player_script: GDScript = load("res://scripts/game/player/player.gd")
	_player = player_script.new()
	root.add_child(_player)
	_weapons = _player.get_weapon_controller()


## Quader auf Lage 1 (Welt). Mitte und Größe in Metern.
func _add_block(block_name: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = block_name
	body.collision_layer = Balance.LAYER_WORLD
	body.collision_mask = 0
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	body.position = center
	root.add_child(body)
	return body


func _add_dummy(dummy_name: String, feet: Vector3, height: float = 3.0, width: float = 1.2) -> Dummy:
	var dummy: Dummy = Dummy.new()
	dummy.build(dummy_name, height, width)
	dummy.journal = _journal
	dummy.position = feet
	root.add_child(dummy)
	_dummies.append(dummy)
	return dummy


func _clear_dummies() -> void:
	for dummy: Dummy in _dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	_dummies.clear()
	await _settle()


## Einige Physik- und Bildschritte warten: neue Körper sind dann für Strahlen sichtbar.
func _settle(steps: int = 4) -> void:
	for i: int in steps:
		await physics_frame
	await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame


## Stellt den Spieler an einen Ort, Blick nach -Z, ohne Restbewegung.
func _place_player(feet: Vector3) -> void:
	_player.global_position = feet
	_player.velocity = Vector3.ZERO
	_player.look_at_point(feet + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, -10.0))
	await _settle()


## Schussfolge aller gehaltenen Waffen sofort ablaufen lassen (spart Wartezeit).
func _ready_weapon() -> void:
	for hand: Dictionary in _weapons.get_hands():
		var state: WeaponState = _weapons.get_state_of(int(hand["uid"]))
		if state != null:
			state.cooldown_left = 0.0


## Legt eine Waffe dieser Rarität in den Rucksack (alle anderen Waffen kommen in die Ablage) und
## gleicht ab. Gibt die uid zurück.
func _hold_item(weapon_id: String, level: int) -> int:
	var backpack: RefCounted = _game.backpack
	for entry: Dictionary in backpack.placed_items():
		if ItemDefs.is_weapon(String(entry["id"])):
			backpack.store(int(entry["uid"]))
	var uid: int = backpack.add_item(weapon_id, level)
	_check(backpack.auto_place(uid), "Aufbau: %s passt in den Rucksack." % weapon_id)
	_game.sync_build()
	return uid


## Mündung einer Hand in Kamera-Koordinaten (x < 0 = links der Bildmitte, z < 0 = vor der Kamera).
func _muzzle_in_view(hand: int) -> Vector3:
	var view_model: Node3D = _player.get_node("Camera/ViewModel")
	return _player.get_camera().global_transform.affine_inverse() * (view_model.get_muzzle_position(hand) as Vector3)


## Wie oft kam weapon_fired mit dieser Waffen-ID?
func _fired(weapon_id: String) -> int:
	var count: int = 0
	for args: Array in _received.get("weapon_fired", []):
		if args[0] == weapon_id:
			count += 1
	return count


## Kam das Signal mit genau diesen Argumenten?
func _has_record(signal_name: String, args: Array) -> bool:
	return (_received.get(signal_name, []) as Array).has(args)


func _reset_records() -> void:
	_received.clear()
	_journal.clear()
	for dummy: Dummy in _dummies:
		if is_instance_valid(dummy):
			dummy.hits.clear()


func _release_all_actions() -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint",
			"fire", "reload", "interact", "weapon_1", "weapon_2", "weapon_3"]:
		Input.action_release(action)


# --- Tests ---


func _test_setup() -> void:
	_check(_player.is_in_group("player"), "Der Spieler ist in der Gruppe player.")
	_check(_game.player == _player, "Der Spieler trägt sich in Game.player ein.")
	_check(_player.collision_layer == Balance.LAYER_PLAYER and _player.collision_mask == Balance.MASK_PLAYER,
		"Spieler: Lage 2, Maske Welt + Zombies.")
	_check(_player.get_node_or_null("Shape") is CollisionShape3D, "Knoten Player/Shape.")
	_check(_player.get_node_or_null("Camera") is Camera3D, "Knoten Player/Camera.")
	_check(_player.get_node_or_null("Camera/ViewModel") != null, "Knoten Player/Camera/ViewModel.")
	_check(_player.get_node_or_null("WeaponController") == _weapons, "Knoten Player/WeaponController.")
	_check(_player.get_camera() == _player.get_node("Camera"), "get_camera liefert die Kamera.")
	_check(is_equal_approx(_player.get_camera().fov, Balance.PLAYER_FOV), "Sichtfeld aus Balance.")
	_check(is_equal_approx(_player.hp, Balance.PLAYER_MAX_HP) and is_equal_approx(_player.max_hp, Balance.PLAYER_MAX_HP),
		"Start mit vollem Leben.")
	_check(not _player.is_dead, "Der Spieler lebt am Anfang.")
	_check(_player.is_on_floor(), "Der Spieler steht auf dem Boden.")
	_check(absf(_player.get_eye_position().y - Balance.PLAYER_EYE_HEIGHT) < 0.05,
		"Augenhöhe 1,6 m über den Füßen, war %s." % _player.get_eye_position().y)
	# Ohne Kandidat ist der Rucksack leer: Der Spieler hält die Dienstpistole mit der uid 0.
	_check(_game.character_id == "" and (_game.backpack.placed_items() as Array).is_empty(), "Im Test ist der Rucksack leer.")
	_check(_weapons.get_current_weapon_id() == "pistol", "Startwaffe ist die Pistole.")
	_check(_weapons.get_owned_weapon_ids() == (["pistol"] as Array[String]), "Am Anfang nur die Pistole.")
	_check(_weapons.has_weapon("pistol") and not _weapons.has_weapon("shotgun"), "has_weapon stimmt.")
	var hands: Array[Dictionary] = _weapons.get_hands()
	_check(hands.size() == 1, "Eine Hand ist belegt.")
	if hands.size() == 1:
		var hand: Dictionary = hands[0]
		_check(hand["hand"] == 0 and hand["uid"] == 0 and hand["id"] == "pistol" and hand["level"] == 1 and hand["hands"] == 1,
			"get_hands: Dienstpistole mit uid 0 in der linken Hand, war %s." % [hand])
		_check(hand["mag"] == 10 and hand["magazine"] == 10 and hand["reloading"] == false, "get_hands: volles Magazin, kein Nachladen.")
	_check(_weapons.get_state_of(0) != null and _weapons.get_state_of(0) == _weapons.get_state("pistol"),
		"get_state_of(0) und get_state(pistol) liefern denselben Zustand.")
	_check(_weapons.get_state_of(99) == null and _weapons.get_state("smg") == null, "Für nicht gehaltene Waffen gibt es keinen Zustand.")
	_check(not _weapons.is_reloading(), "Am Anfang lädt nichts nach.")
	_check(_count("loadout_changed") >= 1, "run_started meldet die Bewaffnung über loadout_changed.")
	_check(_count("weapon_changed") >= 1 and _last("weapon_changed") == ["pistol"],
		"run_started meldet die Pistole über weapon_changed.")
	_check(_last("ammo_changed") == [10, -1], "run_started meldet 10 Schuss und unendlichen Vorrat.")
	_check(_last("hand_ammo_changed") == [0, 10, 10], "run_started meldet das Magazin der linken Hand.")
	var health: Array = _last("player_health_changed")
	_check(health.size() == 2 and is_equal_approx(health[0], 100.0) and is_equal_approx(health[1], 100.0),
		"run_started meldet volles Leben.")


func _test_single_shot() -> void:
	var target: Dummy = _add_dummy("A", Vector3(0.0, 0.0, -6.0))
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	_reset_records()
	_check(_weapons.try_fire(), "Die Pistole schießt.")
	_check(target.hits.size() == 1, "Ein Schuss trifft den Zombie genau einmal, waren %d." % target.hits.size())
	if target.hits.size() == 1:
		var info: Dictionary = target.hits[0]["info"]
		_check(is_equal_approx(target.hits[0]["amount"], 25.0), "Pistole: 25 Schaden, waren %s." % target.hits[0]["amount"])
		_check(info.get("source") == "bullet", "info.source ist bullet.")
		_check(info.get("headshot") == false, "Körpertreffer ist kein Kopftreffer.")
		_check(info.get("weapon_id") == "pistol" and info.get("weapon") == "pistol", "info.weapon und info.weapon_id sind pistol.")
		_check(info.get("weapon_uid") == 0, "info.weapon_uid ist 0 (Dienstpistole ohne Rucksack).")
		_check(info.get("hand") == 0, "info.hand ist 0 (linke Hand).")
		var hit_position: Vector3 = info.get("hit_position", Vector3.ZERO)
		_check(absf(hit_position.z + 5.7) < 0.05 and absf(hit_position.y - 1.2) < 0.15,
			"info.hit_position liegt auf der Vorderseite des Zombies, war %s." % hit_position)
	_check(_count("bullet_hit") == 1, "Ein Treffer sendet ein bullet_hit.")
	if _count("bullet_hit") == 1:
		var args: Array = _last("bullet_hit")
		_check(args[0] == target and is_equal_approx(args[1], 25.0) and args[2] == target.hits[0]["info"],
			"bullet_hit trägt Zombie, Schaden und dieselbe info.")
	_check(_journal == ["damage:A", "bullet_hit:A", "weapon_fired"],
		"Reihenfolge: take_damage, bullet_hit, weapon_fired. War %s." % [_journal])
	_check(_received.get("weapon_fired", []) == [["pistol"]], "weapon_fired(pistol) genau einmal.")
	_check(_last("ammo_changed") == [9, -1], "ammo_changed meldet 9 Schuss.")
	_check(_received.get("hand_ammo_changed", []) == [[0, 9, 10]], "hand_ammo_changed(0, 9, 10) genau einmal.")
	_check(_weapons.get_state("pistol").mag == 9, "Ein Schuss kostet eine Kugel.")
	_check(not _weapons.try_fire(), "Innerhalb der Schussfolge fällt kein zweiter Schuss.")
	_check(_weapons.get_state("pistol").mag == 9 and target.hits.size() == 1, "Der abgelehnte Schuss kostet nichts.")
	await _wait(WeaponDefs.fire_interval("pistol") + 0.05)
	_check(_weapons.try_fire(), "Nach der Schussfolge (0,2 s) schießt die Pistole wieder.")
	# Vorbei geschossen: kein Treffer, die Kugel ist trotzdem weg.
	_ready_weapon()
	_player.look_at_point(Vector3(5.0, 1.2, -6.0))
	_reset_records()
	_check(_weapons.try_fire(), "Ein Schuss ins Leere fällt.")
	_check(target.hits.is_empty() and _count("bullet_hit") == 0, "Ein Schuss ins Leere trifft nichts.")
	_check(_count("weapon_fired") == 1, "Auch ein Schuss ins Leere sendet weapon_fired.")
	await _clear_dummies()


func _test_headshot() -> void:
	# 1,8 m hoch: Kopf ab 0,78 * 1,8 = 1,404 m.
	var target: Dummy = _add_dummy("H", Vector3(0.0, 0.0, -6.0), 1.8)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.62, -5.7))
	_ready_weapon()
	_reset_records()
	_check(_weapons.try_fire(), "Schuss auf den Kopf fällt.")
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 50.0),
		"Kopftreffer: doppelter Schaden (50).")
	_check(target.hits.size() == 1 and target.hits[0]["info"].get("headshot") == true, "info.headshot ist true.")
	_player.look_at_point(Vector3(0.0, 0.9, -5.7))
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 25.0)
		and target.hits[0]["info"].get("headshot") == false, "Bauchtreffer: einfacher Schaden, kein Kopftreffer.")
	await _clear_dummies()


func _test_pierce() -> void:
	var line: Array[Dummy] = []
	for i: int in 4:
		line.append(_add_dummy("P%d" % i, Vector3(0.0, 0.0, -4.0 - 2.0 * float(i))))
	await _place_player(Vector3.ZERO)
	_weapons.refill_ammo("pistol")
	_player.look_at_point(Vector3(0.0, 1.2, -4.0))
	# Ohne Upgrade: nur der vorderste.
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(_hit_counts(line) == [1, 0, 0, 0], "Ohne Durchschlag trifft die Kugel nur den Vordersten, war %s." % [_hit_counts(line)])
	# Stufe 2: zwei weitere Ziele, je Ziel 15 % weniger.
	_game.upgrades.add_levels("pierce", 2)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(_hit_counts(line) == [1, 1, 1, 0], "Durchschlag 2 trifft drei Zombies, war %s." % [_hit_counts(line)])
	if _hit_counts(line) == [1, 1, 1, 0]:
		_check(is_equal_approx(line[0].total_damage(), 25.0), "Erstes Ziel: voller Schaden.")
		_check(is_equal_approx(line[1].total_damage(), 25.0 * 0.85), "Zweites Ziel: 85 %%, war %s." % line[1].total_damage())
		_check(is_equal_approx(line[2].total_damage(), 25.0 * 0.85 * 0.85), "Drittes Ziel: 72,25 %%, war %s." % line[2].total_damage())
	_check(_count("bullet_hit") == 3, "Drei Treffer senden drei bullet_hit.")
	_check(_journal == ["damage:P0", "bullet_hit:P0", "damage:P1", "bullet_hit:P1", "damage:P2", "bullet_hit:P2", "weapon_fired"],
		"Durchschlag von vorn nach hinten, je Ziel erst Schaden, dann bullet_hit. War %s." % [_journal])
	_check(_count("weapon_fired") == 1 and _weapons.get_state("pistol").mag == 8, "Durchschlag kostet nur eine Kugel.")
	# Ein toter Zombie im Weg zählt nicht mit und bekommt keinen Schaden.
	line[1].is_dead = true
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(_hit_counts(line) == [1, 0, 1, 1], "Tote Zombies werden übersprungen, war %s." % [_hit_counts(line)])
	_check(is_equal_approx(line[3].total_damage(), 25.0 * 0.85 * 0.85), "Der Tote verbraucht keinen Durchschlag.")
	line[1].is_dead = false
	# Kopftreffer und Durchschlag zusammen.
	_ready_weapon()
	_reset_records()
	# Flach nach oben: die Kugel bleibt bei beiden vorderen Zombies im Kopfbereich (2,34 bis 3,0 m).
	_player.look_at_point(Vector3(0.0, 2.414, -3.7))
	_weapons.try_fire()
	_check(is_equal_approx(line[0].total_damage(), 50.0) and is_equal_approx(line[1].total_damage(), 50.0 * 0.85),
		"Kopftreffer mit Durchschlag: 50 und 42,5, waren %s und %s." % [line[0].total_damage(), line[1].total_damage()])
	_player.look_at_point(Vector3(0.0, 1.2, -4.0))
	# Eine Wand hält die Kugel auf.
	var wall: StaticBody3D = _add_block("Wall", Vector3(0.0, 1.5, -5.0), Vector3(4.0, 3.0, 0.2))
	await _settle()
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(_hit_counts(line) == [1, 0, 0, 0], "Eine Wand hält die Kugel auf, war %s." % [_hit_counts(line)])
	wall.queue_free()
	await _settle()
	# Stufe 5: fünf weitere Ziele, hier stehen nur vier.
	_game.upgrades.add_levels("pierce", 3)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(_hit_counts(line) == [1, 1, 1, 1], "Durchschlag 5 trifft alle vier, war %s." % [_hit_counts(line)])
	_check(is_equal_approx(line[3].total_damage(), 25.0 * pow(0.85, 3.0)), "Viertes Ziel: 85 %% hoch 3.")
	await _clear_dummies()
	# Neuer Lauf: Upgrades weg, Waffen zurück auf Anfang.
	_game.start_run(11)
	await _settle()
	_check(_game.upgrades.get_level("pierce") == 0 and _weapons.get_state("pistol").mag == 10,
		"start_run setzt Upgrades und Magazin zurück.")


func _test_shotgun() -> void:
	# Breit und hoch: alle 8 Kugeln treffen, keine in den Kopf.
	var target: Dummy = _add_dummy("W", Vector3(0.0, 0.0, -3.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_reset_records()
	_weapons.give_weapon("shotgun")
	_check(_weapons.get_current_weapon_id() == "shotgun", "give_weapon gibt die Schrotflinte in die Hand.")
	_check(_received.get("weapon_changed", []) == [["shotgun"]], "give_weapon sendet weapon_changed(shotgun).")
	_check(_count("loadout_changed") == 1, "give_weapon sendet loadout_changed genau einmal.")
	_check(_last("ammo_changed") == [6, -1], "Schrotflinte: 6 im Magazin, Vorrat unendlich.")
	_check(_last("hand_ammo_changed") == [0, 6, 6], "hand_ammo_changed meldet 6 von 6.")
	_check(_weapons.get_owned_weapon_ids() == (["shotgun"] as Array[String]), "Der Spieler hält genau die Schrotflinte.")
	var shotgun_hand: Dictionary = _weapons.get_hands()[0]
	_check(int(shotgun_hand["uid"]) > 0 and shotgun_hand["hands"] == 2, "Die Schrotflinte liegt als Gegenstand im Rucksack und braucht zwei Hände.")
	_check(_game.loadout.size() == 1 and _game.loadout[0]["uid"] == shotgun_hand["uid"], "Game.loadout nennt dieselbe Waffe.")
	_reset_records()
	_check(_weapons.try_fire(), "Die Schrotflinte schießt.")
	_check(target.hits.size() == 8, "8 Schrotkugeln treffen, waren %d." % target.hits.size())
	_check(is_equal_approx(target.total_damage(), 8.0 * 14.0), "8 Kugeln zu je 14 Schaden, waren %s." % target.total_damage())
	_check(_count("bullet_hit") == 8, "Jede Schrotkugel sendet bullet_hit.")
	_check(_count("weapon_fired") == 1, "Ein Schuss sendet ein weapon_fired.")
	_check(_weapons.get_state("shotgun").mag == 5, "Ein Schuss kostet eine Patrone (nicht 8).")
	_check(_last("ammo_changed") == [5, -1], "ammo_changed meldet 5.")
	if not target.hits.is_empty():
		_check(target.hits[0]["info"].get("weapon_uid") == shotgun_hand["uid"] and target.hits[0]["info"].get("weapon") == "shotgun",
			"Die Treffer-Info nennt die uid und die ID der Schrotflinte.")
	# Streuung: Die Kugeln liegen verteilt, aber alle im Streukegel von 5 Grad.
	var eye: Vector3 = _player.get_eye_position()
	var aim: Vector3 = _player.get_aim_direction()
	var spots: Dictionary = {}
	var widest: float = 0.0
	for hit: Dictionary in target.hits:
		var at: Vector3 = hit["info"]["hit_position"]
		spots[at.snappedf(0.001)] = true
		widest = maxf(widest, rad_to_deg(aim.angle_to(at - eye)))
	_check(spots.size() >= 6, "Die Schrotkugeln streuen, verschiedene Einschläge: %d." % spots.size())
	_check(widest <= 5.0 + 0.6 and widest > 0.5, "Alle Kugeln im Streukegel von 5 Grad, weiteste: %s." % widest)
	# Mit Durchschlag trifft jede Kugel auch den Zombie dahinter.
	var behind: Dummy = _add_dummy("W2", Vector3(0.0, 0.0, -5.0), 4.0, 6.0)
	await _settle()
	_game.upgrades.add_levels("pierce", 1)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 8 and behind.hits.size() == 8, "Durchschlag gilt je Schrotkugel.")
	_check(is_equal_approx(behind.total_damage(), 8.0 * 14.0 * 0.85), "Hinteres Ziel: je Kugel 85 %.")
	# Abgesägte Schrotflinte: 5 Kugeln, breiter gestreut, zwei Patronen.
	_weapons.give_weapon("sawed_off")
	_reset_records()
	_check(_weapons.try_fire(), "Die abgesägte Schrotflinte schießt.")
	_check(target.hits.size() == 5 and is_equal_approx(target.total_damage(), 5.0 * 14.0), "5 Kugeln zu je 14 Schaden, waren %d." % target.hits.size())
	_ready_weapon()
	_check(_weapons.try_fire() and _weapons.get_state("sawed_off").mag == 0 and _weapons.get_state("sawed_off").is_reloading,
		"Nach zwei Schüssen ist sie leer und lädt nach.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()
	_check(_weapons.get_owned_weapon_ids() == (["pistol"] as Array[String]) and _weapons.get_current_weapon_id() == "pistol",
		"run_started: nur noch die Pistole.")
	_check(_weapons.get_hands()[0]["uid"] == 0, "run_started: wieder die Dienstpistole mit der uid 0.")


func _test_reload() -> void:
	await _place_player(Vector3.ZERO)
	var pistol: WeaponState = _weapons.get_state("pistol")
	# Volles Magazin: kein Nachladen.
	_reset_records()
	_weapons.start_reload()
	_check(_count("reload_started") == 0 and _count("hand_reload_started") == 0 and not pistol.is_reloading, "Mit vollem Magazin lädt nichts nach.")
	# Nachladen von Hand.
	pistol.mag = 3
	_weapons.start_reload()
	_check(pistol.is_reloading and _weapons.is_reloading(), "start_reload beginnt das Nachladen.")
	_check(_weapons.get_hands()[0]["reloading"] == true, "get_hands meldet das Nachladen.")
	var started: Array = _last("reload_started")
	_check(started.size() == 2 and started[0] == "pistol" and is_equal_approx(started[1], 1.2),
		"reload_started(pistol, 1,2 s), war %s." % [started])
	var hand_started: Array = _last("hand_reload_started")
	_check(hand_started.size() == 2 and hand_started[0] == 0 and is_equal_approx(hand_started[1], 1.2),
		"hand_reload_started(0, 1,2 s), war %s." % [hand_started])
	_check(not _weapons.try_fire() and pistol.mag == 3, "Während des Nachladens fällt kein Schuss.")
	_weapons.start_reload()
	_check(_count("reload_started") == 1 and _count("hand_reload_started") == 1, "Ein zweites start_reload während des Nachladens zählt nicht.")
	await _wait(0.5)
	_check(pistol.is_reloading and _count("reload_finished") == 0, "Nach 0,5 s lädt die Pistole noch.")
	await _wait(0.85)
	_check(not pistol.is_reloading and pistol.mag == 10, "Nach 1,2 s ist das Magazin voll.")
	_check(_received.get("reload_finished", []) == [["pistol"]], "reload_finished(pistol) genau einmal.")
	_check(_received.get("hand_reload_finished", []) == [[0]], "hand_reload_finished(0) genau einmal.")
	_check(_last("ammo_changed") == [10, -1] and _last("hand_ammo_changed") == [0, 10, 10], "Nach dem Nachladen melden beide Signale 10.")
	# Leeres Magazin lädt von selbst nach.
	pistol.mag = 1
	_ready_weapon()
	_reset_records()
	_check(_weapons.try_fire(), "Der letzte Schuss fällt.")
	_check(pistol.mag == 0 and pistol.is_reloading, "Leeres Magazin: Nachladen beginnt von selbst.")
	_check(_count("reload_started") == 1, "Das automatische Nachladen sendet reload_started.")
	_check(_last("ammo_changed") == [0, -1], "ammo_changed meldet das leere Magazin.")
	# Unendliche Munition: Nachladen geht immer wieder, das Magazin wird jedes Mal voll.
	for round_index: int in 4:
		pistol.reload_left = 0.02
		await _wait(0.1)
		_check(pistol.mag == 10 and not pistol.is_reloading, "Nachladen %d füllt das Magazin." % (round_index + 1))
		pistol.mag = 0
		_weapons.start_reload()
		_check(pistol.is_reloading, "Nachladen %d beginnt, obwohl schon viel verschossen wurde." % (round_index + 2))
	pistol.reload_left = 0.02
	await _wait(0.1)
	# Eine leere Waffe, die gerade nicht lädt, beginnt im nächsten Bild von selbst.
	pistol.mag = 0
	_reset_records()
	await _frames(2)
	_check(pistol.is_reloading and _count("hand_reload_started") == 1, "Eine leere Waffe lädt von selbst nach, ohne Schuss und ohne Taste.")
	_check(not _weapons.try_fire() and _count("weapon_fired") == 0, "Mit leerem Magazin fällt kein Schuss.")
	# refill_ammo füllt sofort und beendet das Nachladen.
	_reset_records()
	_weapons.refill_ammo("pistol")
	_check(pistol.mag == 10 and not pistol.is_reloading, "refill_ammo füllt das Magazin sofort.")
	_check(_count("reload_finished") == 1 and _count("hand_reload_finished") == 1, "refill_ammo beendet ein laufendes Nachladen.")
	_check(_last("ammo_changed") == [10, -1], "refill_ammo sendet ammo_changed.")
	_reset_records()
	_weapons.refill_ammo("smg")
	_check(_count("ammo_changed") == 0 and _count("hand_ammo_changed") == 0, "refill_ammo ohne die Waffe tut nichts.")
	# Taste R lädt nach.
	pistol.mag = 5
	await _frames(2)
	_reset_records()
	await _tap("reload")
	_check(pistol.is_reloading and _count("reload_started") == 1, "Taste R lädt nach.")
	_weapons.refill_ammo("pistol")


## Waffen kommen aus dem Rucksack: give_weapon und equip räumen sie ein, einen Wechsel gibt es nicht.
func _test_loadout() -> void:
	_reset_records()
	_weapons.switch_to("smg")
	_check(_weapons.get_current_weapon_id() == "pistol" and _count("weapon_changed") == 0 and _count("loadout_changed") == 0,
		"switch_to tut nichts mehr.")
	_weapons.give_weapon("raketenwerfer")
	_check(_weapons.get_owned_weapon_ids() == (["pistol"] as Array[String]) and _count("loadout_changed") == 0,
		"Unbekannte Waffen werden nicht aufgenommen.")
	_weapons.give_weapon("smg")
	_check(_weapons.get_owned_weapon_ids() == (["smg"] as Array[String]), "give_weapon: Der Spieler hält genau die MP.")
	_check(_last("weapon_changed") == ["smg"] and _last("ammo_changed") == [30, -1], "MP: weapon_changed und 30 Schuss.")
	_check(_weapons.has_weapon("smg") and not _weapons.has_weapon("pistol"), "Die Dienstpistole ist weg, sobald eine Waffe im Rucksack liegt.")
	var smg_uid: int = int(_weapons.get_hands()[0]["uid"])
	_check(_game.backpack.is_placed(smg_uid) and _game.backpack.item(smg_uid)["id"] == "smg" and _game.backpack.item(smg_uid)["level"] == 1,
		"Die MP liegt als gewöhnlicher Gegenstand im Rucksack.")
	# Dieselbe Waffe noch einmal: Sie bleibt dieselbe (gleiche uid), das Magazin bleibt.
	var smg: WeaponState = _weapons.get_state("smg")
	smg.mag = 7
	_weapons.give_weapon("smg")
	_check(int(_weapons.get_hands()[0]["uid"]) == smg_uid and _weapons.get_state("smg") == smg and smg.mag == 7,
		"give_weapon einer gehaltenen Waffe füllt nicht auf.")
	_check((_game.backpack.storage_items() as Array).is_empty(), "Dabei sammelt sich nichts in der Ablage.")
	# Tasten 1 bis 3 und das Mausrad wechseln nichts mehr.
	await _frames(2)
	_reset_records()
	await _tap("weapon_1")
	await _tap("weapon_2")
	await _wheel(MOUSE_BUTTON_WHEEL_UP)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check(_weapons.get_current_weapon_id() == "smg" and _count("weapon_changed") == 0, "Tasten und Mausrad wechseln die Waffe nicht.")
	# Jede der neun Waffen lässt sich in die Hand geben (der Rucksack wächst, wenn sie nicht passt).
	for weapon_id: String in WeaponDefs.ORDER:
		_weapons.give_weapon(weapon_id)
		var hands: Array[Dictionary] = _weapons.get_hands()
		_check(_weapons.get_owned_weapon_ids() == ([weapon_id] as Array[String]), "give_weapon(%s): genau diese Waffe in der Hand." % weapon_id)
		_check(hands.size() == 1 and hands[0]["hands"] == ItemDefs.hands(weapon_id) and hands[0]["mag"] == int(WeaponDefs.get_def(weapon_id)["magazine"]),
			"%s: Hände und volles Magazin stimmen." % weapon_id)
		_check(_game.backpack.hands_used() == ItemDefs.hands(weapon_id), "%s: Im Rucksack liegt nur diese Waffe." % weapon_id)
	# Die MP von vorhin lag in der Ablage: Ihr Zustand ist verfallen, sie kommt mit vollem Magazin wieder.
	_weapons.give_weapon("smg")
	_check(int(_weapons.get_hands()[0]["uid"]) == smg_uid and _weapons.get_state("smg").mag == 30,
		"Eine Waffe aus der Ablage kommt mit vollem Magazin zurück.")
	_game.start_run(11)
	await _settle()


## Beidhändig mit zwei gleichen Waffen: ein Druck, zwei Schüsse, zwei Magazine.
func _test_akimbo() -> void:
	var target: Dummy = _add_dummy("K", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_reset_records()
	_weapons.equip(["pistol", "pistol"] as Array[String])
	var hands: Array[Dictionary] = _weapons.get_hands()
	_check(_weapons.get_owned_weapon_ids() == (["pistol", "pistol"] as Array[String]), "equip: zwei Pistolen in den Händen.")
	_check(hands.size() == 2 and hands[0]["hand"] == 0 and hands[1]["hand"] == 1, "get_hands nennt linke und rechte Hand.")
	if hands.size() < 2:
		await _clear_dummies()
		return
	var left_uid: int = int(hands[0]["uid"])
	var right_uid: int = int(hands[1]["uid"])
	_check(left_uid > 0 and right_uid > 0 and left_uid != right_uid, "Jede Pistole hat ihre eigene uid.")
	_check(_game.loadout.size() == 2 and _game.loadout[0]["uid"] == left_uid and _game.loadout[1]["uid"] == right_uid,
		"Die Hände folgen Game.loadout (links nach rechts im Rucksack).")
	_check(_count("loadout_changed") == 1, "equip sendet loadout_changed genau einmal.")
	_check(_has_record("hand_ammo_changed", [0, 10, 10]) and _has_record("hand_ammo_changed", [1, 10, 10]), "Beide Hände melden ihr Magazin.")
	var left: WeaponState = _weapons.get_state_of(left_uid)
	var right: WeaponState = _weapons.get_state_of(right_uid)
	_check(left != null and right != null and left != right, "Jede Hand hat ihren eigenen Zustand.")
	_check(_weapons.get_state("pistol") == left, "get_state(pistol) liefert die linke Hand.")
	# Ein try_fire: beide schießen.
	_reset_records()
	_check(_weapons.try_fire(), "Beidhändig fällt ein Schuss.")
	_check(_count("weapon_fired") == 2 and _fired("pistol") == 2, "Ein Abzug, zwei Schüsse (weapon_fired zweimal).")
	_check(target.hits.size() == 2 and is_equal_approx(target.total_damage(), 50.0), "Zwei Treffer zu je 25 Schaden.")
	_check(left.mag == 9 and right.mag == 9, "Beide Magazine zählen herunter.")
	if target.hits.size() == 2:
		var first: Dictionary = target.hits[0]["info"]
		var second: Dictionary = target.hits[1]["info"]
		_check(first.get("hand") == 0 and second.get("hand") == 1, "Die Treffer-Info nennt Hand 0 und Hand 1.")
		_check(first.get("weapon_uid") == left_uid and second.get("weapon_uid") == right_uid, "Die Treffer-Info nennt die uid jeder Waffe.")
		_check(first.get("weapon") == "pistol" and second.get("weapon") == "pistol", "Die Treffer-Info nennt die Waffen-ID.")
	_check(_has_record("hand_ammo_changed", [0, 9, 10]) and _has_record("hand_ammo_changed", [1, 9, 10]), "hand_ammo_changed je Hand.")
	_check(_received.get("ammo_changed", []) == [[9, -1]], "Das alte ammo_changed kommt nur für die linke Hand.")
	_check(_journal == ["damage:K", "bullet_hit:K", "weapon_fired", "damage:K", "bullet_hit:K", "weapon_fired"],
		"Erst der ganze Schuss der linken Hand, dann der der rechten. War %s." % [_journal])
	# Ein Tastendruck: wieder zwei Schüsse.
	await _wait(0.3)
	_reset_records()
	await _tap("fire")
	_check(_count("weapon_fired") == 2 and left.mag == 8 and right.mag == 8, "Ein Druck auf die Maustaste feuert beide Pistolen, waren %d Schüsse." % _count("weapon_fired"))
	# Die Mündungen liegen links und rechts der Bildmitte.
	await _frames(20)
	_check(_muzzle_in_view(0).x < -0.01 and _muzzle_in_view(1).x > 0.01, "Linke Mündung links, rechte Mündung rechts, waren %s und %s." % [_muzzle_in_view(0).x, _muzzle_in_view(1).x])
	_check(_muzzle_in_view(0).z < 0.0 and _muzzle_in_view(1).z < 0.0, "Beide Mündungen liegen vor der Kamera.")
	# Nachladen: beide, mit Signalen je Hand. Die alten Signale kommen nur für die linke.
	_reset_records()
	_weapons.start_reload()
	_check(left.is_reloading and right.is_reloading, "start_reload lädt beide Waffen nach.")
	_check(_count("hand_reload_started") == 2 and _count("reload_started") == 1, "hand_reload_started je Hand, reload_started nur links.")
	left.reload_left = 0.02
	right.reload_left = 0.02
	await _wait(0.1)
	_check(left.mag == 10 and right.mag == 10, "Beide Magazine sind wieder voll.")
	_check(_has_record("hand_reload_finished", [0]) and _has_record("hand_reload_finished", [1]) and _count("reload_finished") == 1,
		"hand_reload_finished je Hand, reload_finished nur links.")
	# Eine volle Waffe lädt nicht mit.
	left.mag = 4
	_reset_records()
	_weapons.start_reload()
	_check(left.is_reloading and not right.is_reloading and _received.get("hand_reload_started", []).size() == 1, "Nur die nicht volle Waffe lädt nach.")
	# Die andere Hand schießt weiter, während eine nachlädt.
	_ready_weapon()
	_reset_records()
	_check(_weapons.try_fire() and _count("weapon_fired") == 1, "Während die linke nachlädt, schießt die rechte allein.")
	_check(target.hits.size() == 1 and target.hits[0]["info"].get("hand") == 1, "Der Treffer kommt von der rechten Hand.")
	_check(_weapons.is_reloading(), "is_reloading gilt, sobald irgendeine Hand nachlädt.")
	# Rechts leer geschossen: Nur die rechte beginnt von selbst nachzuladen.
	left.reload_left = 0.02
	await _wait(0.1)
	right.mag = 1
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(right.mag == 0 and right.is_reloading and not left.is_reloading and left.mag == 9, "Die leere rechte Waffe lädt nach, die linke nicht.")
	_check(_received.get("hand_reload_started", []).size() == 1 and _last("hand_reload_started")[0] == 1 and _count("reload_started") == 0,
		"Das Nachladen der rechten Hand sendet nur hand_reload_started(1).")
	# refill_ammo füllt beide Pistolen.
	_weapons.refill_ammo("pistol")
	_check(left.mag == 10 and right.mag == 10 and not right.is_reloading, "refill_ammo füllt jede gehaltene Pistole.")
	# Mehr als zwei Hände gibt es nicht.
	_weapons.equip(["pistol", "pistol", "pistol"] as Array[String])
	_check(_weapons.get_hands().size() == 2, "Drei Pistolen: nur zwei finden eine Hand.")
	await _clear_dummies()


## Beidhändig mit zwei verschiedenen Waffen: jede in ihrer eigenen Schussfolge.
func _test_mixed_akimbo() -> void:
	var target: Dummy = _add_dummy("M", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_weapons.equip(["pistol", "smg"] as Array[String])
	_check(_weapons.get_owned_weapon_ids() == (["pistol", "smg"] as Array[String]), "equip: Pistole links, MP rechts.")
	_check(_weapons.get_current_weapon_id() == "pistol", "get_current_weapon_id nennt die linke Hand.")
	_check(_weapons.has_weapon("pistol") and _weapons.has_weapon("smg"), "has_weapon kennt beide.")
	var pistol: WeaponState = _weapons.get_state("pistol")
	var smg: WeaponState = _weapons.get_state("smg")
	await _frames(2)
	# Maustaste halten: Die Pistole schießt einmal, die MP im Dauerfeuer.
	_reset_records()
	Input.action_press("fire")
	await _wait(0.5)
	Input.action_release("fire")
	await _frames(2)
	_check(_fired("pistol") == 1, "Gehaltene Taste: Die Pistole schießt einmal, waren %d." % _fired("pistol"))
	_check(_fired("smg") >= 5 and _fired("smg") <= 8, "Gehaltene Taste: Die MP schießt etwa 6 Mal, waren %d." % _fired("smg"))
	_check(pistol.mag == 9 and smg.mag == 30 - _fired("smg"), "Jede Waffe verbraucht ihr eigenes Magazin.")
	var hands_seen: Dictionary = {}
	for hit: Dictionary in target.hits:
		hands_seen[String(hit["info"].get("weapon"))] = int(hit["info"].get("hand"))
	_check(hands_seen == {"pistol": 0, "smg": 1}, "Treffer der Pistole tragen Hand 0, die der MP Hand 1. War %s." % [hands_seen])
	_check(is_equal_approx(target.total_damage(), 25.0 + 16.0 * float(_fired("smg"))), "Jede Waffe macht ihren eigenen Schaden.")
	_check(_received.get("ammo_changed", []) == [[9, -1]], "ammo_changed folgt nur der linken Hand (Pistole).")
	# Ein Tastendruck: beide schießen einmal.
	await _wait(0.3)
	_reset_records()
	await _tap("fire")
	_check(_fired("pistol") == 1 and _fired("smg") >= 1, "Ein Druck feuert beide Waffen.")
	# Die MP leer: Sie lädt nach, die Pistole schießt weiter.
	smg.mag = 0
	await _frames(2)
	_check(smg.is_reloading and not pistol.is_reloading, "Die leere MP lädt nach, die Pistole nicht.")
	var smg_reload: Array = _last("hand_reload_started")
	_check(smg_reload.size() == 2 and smg_reload[0] == 1 and is_equal_approx(smg_reload[1], 1.8), "hand_reload_started(1, 1,8 s) für die MP.")
	await _wait(0.3)
	_reset_records()
	await _tap("fire")
	_check(_fired("pistol") == 1 and _fired("smg") == 0, "Während die MP nachlädt, schießt nur die Pistole.")
	# Eine Zweihand-Waffe braucht beide Hände: Die Pistole findet keine mehr.
	_weapons.equip(["shotgun", "pistol"] as Array[String])
	_check(_weapons.get_owned_weapon_ids() == (["shotgun"] as Array[String]), "Neben der Schrotflinte ist keine Hand frei.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Eine Zweihand-Waffe allein.
func _test_two_handed() -> void:
	var target: Dummy = _add_dummy("T", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon("rifle")
	var hands: Array[Dictionary] = _weapons.get_hands()
	_check(hands.size() == 1 and hands[0]["id"] == "rifle" and hands[0]["hands"] == 2 and hands[0]["hand"] == 0,
		"Das Sturmgewehr belegt beide Hände und steht als eine Hand in get_hands.")
	_check(_game.backpack.hands_used() == 2, "Der Rucksack zählt zwei Hände.")
	var view_model: Node3D = _player.get_node("Camera/ViewModel")
	_check(view_model.get_node("Rig/Hand0").visible and not view_model.get_node("Rig/Hand1").visible, "Zu sehen ist nur eine Waffe.")
	_check(view_model.get_node("Rig/Hand0").scale.x > 0.0, "Eine einzelne Waffe wird nicht gespiegelt.")
	await _frames(20)
	_check(_muzzle_in_view(0).x > 0.0 and _muzzle_in_view(0).z < 0.0, "Die Waffe liegt rechts vor der Kamera.")
	# Dauerfeuer mit 9 Schuss je Sekunde.
	_reset_records()
	Input.action_press("fire")
	await _wait(0.5)
	Input.action_release("fire")
	await _frames(2)
	_check(_fired("rifle") >= 4 and _fired("rifle") <= 6, "Sturmgewehr: etwa 5 Schuss in 0,5 s, waren %d." % _fired("rifle"))
	_check(is_equal_approx(target.total_damage(), 24.0 * float(_fired("rifle"))), "Jeder Schuss macht 24 Schaden.")
	# Minigun: 20 Schuss je Sekunde.
	_weapons.give_weapon("minigun")
	await _frames(2)
	_reset_records()
	Input.action_press("fire")
	await _wait(0.5)
	Input.action_release("fire")
	await _frames(2)
	_check(_fired("minigun") >= 9 and _fired("minigun") <= 12, "Minigun: etwa 10 Schuss in 0,5 s, waren %d." % _fired("minigun"))
	_check(_weapons.get_state("minigun").mag == 120 - _fired("minigun"), "Das große Magazin zählt herunter.")
	# Scharfschützengewehr: ein Schuss, sehr hoher Schaden, durchschlägt von selbst nichts.
	var behind: Dummy = _add_dummy("T2", Vector3(0.0, 0.0, -7.0), 4.0, 4.0)
	await _settle()
	_weapons.give_weapon("sniper")
	_reset_records()
	_check(_weapons.try_fire(), "Das Scharfschützengewehr schießt.")
	_check(target.hits.size() == 1 and is_equal_approx(target.total_damage(), 240.0) and behind.hits.is_empty(),
		"240 Schaden am ersten Ziel, nichts dahinter.")
	_check(not _weapons.try_fire(), "Die lange Schussfolge sperrt den nächsten Schuss.")
	# Revolver: eine Hand, harter Treffer.
	_weapons.give_weapon("revolver")
	_reset_records()
	_check(_weapons.try_fire() and target.hits.size() == 1 and is_equal_approx(target.total_damage(), 70.0), "Der Revolver macht 70 Schaden.")
	_check(_weapons.get_hands()[0]["hands"] == 1 and _weapons.get_state("revolver").mag == 5, "Der Revolver braucht eine Hand und hat 6 Schuss.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## build_changed gleicht ab: Waffen, die bleiben, behalten ihr Magazin.
func _test_resync() -> void:
	await _place_player(Vector3.ZERO)
	_weapons.equip(["pistol", "smg"] as Array[String])
	var hands: Array[Dictionary] = _weapons.get_hands()
	var pistol_uid: int = int(hands[0]["uid"])
	var smg_uid: int = int(hands[1]["uid"])
	var pistol: WeaponState = _weapons.get_state_of(pistol_uid)
	var smg: WeaponState = _weapons.get_state_of(smg_uid)
	pistol.mag = 4
	smg.mag = 11
	# Ein anderer Gegenstand kommt dazu: Beide Waffen bleiben, wie sie sind.
	var backpack: RefCounted = _game.backpack
	var extra_uid: int = backpack.add_item("lifesteal", 1)
	_check(backpack.auto_place(extra_uid), "Aufbau: Der Upgrade-Gegenstand passt in den Rucksack.")
	_reset_records()
	_game.sync_build()
	_check(_count("loadout_changed") == 1, "build_changed führt zu loadout_changed.")
	_check(_weapons.get_state_of(pistol_uid) == pistol and _weapons.get_state_of(smg_uid) == smg, "Die Zustände bleiben dieselben.")
	_check(pistol.mag == 4 and smg.mag == 11, "Die Magazine bleiben, wie sie waren.")
	_check(_count("weapon_changed") == 0, "Ohne neue Waffe links kommt kein weapon_changed.")
	_check(_has_record("hand_ammo_changed", [0, 4, 10]) and _has_record("hand_ammo_changed", [1, 11, 30]), "Der Abgleich meldet die Magazine neu.")
	# Ein laufendes Nachladen überlebt den Abgleich.
	_weapons.start_reload()
	_game.sync_build()
	_check(pistol.is_reloading and smg.is_reloading, "Ein laufendes Nachladen überlebt den Abgleich.")
	_check(_weapons.get_hands()[0]["reloading"] == true and float(_weapons.get_hands()[0]["reload_left"]) > 0.0, "get_hands nennt Rest und Dauer des Nachladens.")
	pistol.cancel_reload()
	smg.cancel_reload()
	# Die MP kommt in die Ablage: Die Pistole bleibt mit ihrem Magazin, der Zustand der MP verfällt.
	backpack.store(smg_uid)
	_reset_records()
	_game.sync_build()
	_check(_weapons.get_owned_weapon_ids() == (["pistol"] as Array[String]), "Ohne die MP hält der Spieler nur die Pistole.")
	_check(_weapons.get_state_of(pistol_uid) == pistol and pistol.mag == 4, "Die Pistole behält ihr Magazin.")
	_check(_weapons.get_state_of(smg_uid) == null, "Der Zustand der abgelegten MP ist weg.")
	# Die MP kommt zurück: neuer Zustand mit vollem Magazin, die Pistole unverändert.
	_check(backpack.auto_place(smg_uid), "Aufbau: Die MP passt wieder in den Rucksack.")
	_game.sync_build()
	_check(_weapons.get_state_of(smg_uid) != null and _weapons.get_state_of(smg_uid) != smg and _weapons.get_state_of(smg_uid).mag == 30,
		"Die wieder eingeräumte MP beginnt mit vollem Magazin.")
	_check(_weapons.get_state_of(pistol_uid) == pistol and pistol.mag == 4, "Die Pistole ist weiter unverändert.")
	# Zwei gleiche Waffen kombinieren: Die bleibende (höhere Rarität) behält ihr Magazin.
	var second_uid: int = backpack.add_item("pistol", 1)
	_check(backpack.merge(second_uid, pistol_uid), "Aufbau: Zwei gewöhnliche Pistolen lassen sich kombinieren.")
	_game.sync_build()
	_check(_weapons.get_state_of(pistol_uid) == pistol and pistol.mag == 4 and _weapons.get_hands()[0]["level"] == 2,
		"Die kombinierte Pistole ist Ungewöhnlich und behält ihr Magazin.")
	# Alle Waffen in die Ablage: Der Spieler hält wieder die Dienstpistole (uid 0) mit vollem Magazin.
	backpack.store(pistol_uid)
	backpack.store(smg_uid)
	_reset_records()
	_game.sync_build()
	hands = _weapons.get_hands()
	_check(hands.size() == 1 and hands[0]["uid"] == 0 and hands[0]["id"] == "pistol" and hands[0]["mag"] == 10,
		"Ohne Waffe im Rucksack: Dienstpistole mit der uid 0 und vollem Magazin.")
	_check(_weapons.get_state_of(pistol_uid) == null, "Die abgelegte Pistole hat keinen Zustand mehr.")
	_game.start_run(11)
	await _settle()


## Schaden nach Rarität und Zusatzwerten, Nachladezeit nach Zusatzwerten.
func _test_multipliers() -> void:
	var target: Dummy = _add_dummy("R", Vector3(0.0, 0.0, -5.0), 3.0, 4.0)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -5.0))
	# Rarität: Faktor aus Balance.WEAPON_RARITY_DAMAGE.
	for level: int in [1, 2, 3, 4, 5]:
		var uid: int = _hold_item("pistol", level)
		var factor: float = Balance.WEAPON_RARITY_DAMAGE[level - 1]
		_check(_weapons.get_hands()[0]["uid"] == uid and _weapons.get_hands()[0]["level"] == level, "Die Pistole der Rarität %d ist in der Hand." % level)
		_check(is_equal_approx(_game.weapon_damage_multiplier(uid), factor), "Game nennt den Faktor %s für Rarität %d." % [factor, level])
		_reset_records()
		_check(_weapons.try_fire(), "Die Pistole der Rarität %d schießt." % level)
		_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 25.0 * factor),
			"Rarität %d: 25 mal %s Schaden, war %s." % [level, factor, target.total_damage()])
	_check(is_equal_approx(Balance.WEAPON_RARITY_DAMAGE[4], 2.2), "Legendär: Faktor 2,2.")
	# Kopftreffer und Rarität zusammen.
	_player.look_at_point(Vector3(0.0, 2.7, -4.7))
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 25.0 * 2.0 * 2.2), "Legendär und Kopftreffer: 110 Schaden.")
	_player.look_at_point(Vector3(0.0, 1.2, -5.0))
	# Zusatzwerte für den Spieler als Ganzes (Kandidat): Schaden +20 %, Nachladen 30 % schneller.
	var uid_common: int = _hold_item("pistol", 1)
	_game.upgrades.set_derived({}, [] as Array[String], {"damage": 0.2, "reload": 0.3})
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 30.0), "Schaden +20 %%: 30 statt 25, war %s." % target.total_damage())
	var pistol: WeaponState = _weapons.get_state_of(uid_common)
	_reset_records()
	_weapons.start_reload()
	_check(is_equal_approx(pistol.reload_factor, 0.7) and is_equal_approx(_last("hand_reload_started")[1], 1.2 * 0.7),
		"Nachladen 30 %% schneller: 0,84 s, war %s." % [_last("hand_reload_started")])
	_check(is_equal_approx(_last("reload_started")[1], 1.2 * 0.7), "reload_started nennt dieselbe Dauer.")
	pistol.refill()
	# Der Bonus ist bei 50 % gedeckelt.
	_game.upgrades.set_derived({}, [] as Array[String], {"reload": 0.9})
	pistol.mag = 2
	_reset_records()
	_weapons.start_reload()
	_check(is_equal_approx(_last("hand_reload_started")[1], 0.6), "Mehr als 50 % schneller geht nicht (0,6 s).")
	pistol.refill()
	# Ladehilfe mit Stern auf der Waffe: Sie gilt nur für diese Waffe.
	_weapons.equip(["pistol", "smg"] as Array[String])
	var hands: Array[Dictionary] = _weapons.get_hands()
	var backpack: RefCounted = _game.backpack
	var loader_uid: int = backpack.add_item("speed_loader", 1)
	var placed: bool = false
	for cell: Vector2i in backpack.cells():
		if backpack.place(loader_uid, cell, 0):
			var targets: Array = backpack.star_targets(loader_uid)
			if targets.size() == 1 and targets[0] == hands[1]["uid"]:
				placed = true
				break
			backpack.store(loader_uid)
	_check(placed, "Aufbau: Die Ladehilfe liegt so, dass ihr Stern nur die MP trifft.")
	_game.sync_build()
	var akimbo_pistol: WeaponState = _weapons.get_state("pistol")
	var akimbo_smg: WeaponState = _weapons.get_state("smg")
	akimbo_pistol.mag = 1
	akimbo_smg.mag = 1
	_reset_records()
	_weapons.start_reload()
	_check(_has_record("hand_reload_started", [0, 1.2]), "Die Pistole ohne Stern lädt normal nach (1,2 s). War %s." % [_received.get("hand_reload_started", [])])
	_check(is_equal_approx(akimbo_smg.reload_factor, 0.9) and is_equal_approx(akimbo_smg.reload_left, 1.8 * 0.9),
		"Die MP auf dem Stern lädt 10 %% schneller nach (1,62 s), war %s." % akimbo_smg.reload_left)
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Raketenwerfer: Explosion am Einschlag, Schaden an den Nachbarn.
func _test_rocket() -> void:
	var direct: Dummy = _add_dummy("D", Vector3(0.0, 0.0, -8.0))
	var beside: Dummy = _add_dummy("N", Vector3(2.0, 0.0, -8.0))
	var behind: Dummy = _add_dummy("B", Vector3(0.0, 0.0, -10.5))
	var far: Dummy = _add_dummy("F", Vector3(6.5, 0.0, -8.0))
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon("rocket_launcher")
	var uid: int = int(_weapons.get_hands()[0]["uid"])
	var launcher: WeaponState = _weapons.get_state("rocket_launcher")
	_check(launcher.mag == 1 and _weapons.get_hands()[0]["hands"] == 2, "Der Raketenwerfer hat eine Rakete und braucht zwei Hände.")
	# Durchschlag ändert nichts: Die Rakete explodiert am ersten Ziel.
	_game.upgrades.add_levels("pierce", 3)
	_player.look_at_point(Vector3(0.0, 1.2, -8.0))
	_reset_records()
	_check(_weapons.try_fire(), "Der Raketenwerfer schießt.")
	_check(direct.hits.size() == 1 and direct.hits[0]["info"].get("source") == "bullet" and is_equal_approx(direct.hits[0]["amount"], 250.0),
		"Der direkt getroffene Zombie bekommt 250 Kugelschaden. War %s." % [direct.hits])
	_check(_count("bullet_hit") == 1, "Nur der direkte Treffer sendet bullet_hit.")
	for neighbour: Dummy in [beside, behind]:
		_check(neighbour.hits.size() == 1, "Der Nachbar %s wird von der Explosion getroffen, Treffer: %d." % [neighbour.name, neighbour.hits.size()])
		if neighbour.hits.size() == 1:
			var info: Dictionary = neighbour.hits[0]["info"]
			_check(info.get("source") == "explosion" and is_equal_approx(neighbour.hits[0]["amount"], 150.0),
				"%s: 150 Schaden mit source explosion, war %s." % [neighbour.name, neighbour.hits[0]])
			_check(info.get("weapon_uid") == uid and info.get("weapon") == "rocket_launcher" and info.get("hand") == 0,
				"%s: Die Info der Explosion nennt Waffe, uid und Hand." % neighbour.name)
	_check(far.hits.is_empty(), "Außerhalb des Radius (3,5 m) passiert nichts.")
	_check(_journal.size() == 5 and _journal[0] == "damage:D" and _journal[1] == "bullet_hit:D" and _journal[4] == "weapon_fired",
		"Reihenfolge: direkter Treffer, Explosion, weapon_fired. War %s." % [_journal])
	_check(launcher.mag == 0 and launcher.is_reloading, "Nach der einen Rakete lädt der Werfer von selbst nach.")
	var started: Array = _last("hand_reload_started")
	_check(started.size() == 2 and started[0] == 0 and is_equal_approx(started[1], 2.4), "Nachladen dauert 2,4 s.")
	# Rakete in den Boden zwischen zwei Zombies: beide nehmen Explosionsschaden, keiner Kugelschaden.
	launcher.refill()
	_ready_weapon()
	_player.look_at_point(Vector3(1.0, 0.0, -7.0))
	_reset_records()
	_check(_weapons.try_fire(), "Die zweite Rakete fliegt in den Boden.")
	_check(_count("bullet_hit") == 0, "Ohne direkten Treffer gibt es kein bullet_hit.")
	_check(direct.hits.size() == 1 and direct.hits[0]["info"].get("source") == "explosion"
		and beside.hits.size() == 1 and beside.hits[0]["info"].get("source") == "explosion",
		"Beide Zombies neben dem Einschlag nehmen Explosionsschaden.")
	_check(far.hits.is_empty(), "Der ferne Zombie bleibt verschont.")
	# Rarität und Zusatzschaden gelten auch für die Explosion.
	_game.upgrades.set_derived({}, [] as Array[String], {"damage": 0.2})
	launcher.refill()
	_ready_weapon()
	_player.look_at_point(Vector3(0.0, 1.2, -8.0))
	_reset_records()
	_weapons.try_fire()
	_check(direct.hits.size() == 1 and is_equal_approx(direct.hits[0]["amount"], 300.0) and beside.hits.size() == 1 and is_equal_approx(beside.hits[0]["amount"], 180.0),
		"Schaden +20 %: 300 direkt und 180 aus der Explosion.")
	_game.upgrades.set_derived({}, [] as Array[String], {})
	# Eine Wand schirmt die Explosion ab.
	var wall: StaticBody3D = _add_block("Shield", Vector3(1.0, 1.5, -8.0), Vector3(0.2, 3.0, 3.0))
	await _settle()
	launcher.refill()
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(direct.hits.size() == 1 and beside.hits.is_empty(), "Hinter einer Wand trifft die Explosion nicht, Treffer: %d." % beside.hits.size())
	_check(behind.hits.size() == 1, "Der Zombie ohne Wand davor wird weiter getroffen.")
	wall.queue_free()
	# Ein toter Zombie nimmt keinen Explosionsschaden.
	await _settle()
	beside.is_dead = true
	launcher.refill()
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(beside.hits.is_empty() and behind.hits.size() == 1, "Tote Zombies nimmt die Explosion aus.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


func _test_fire_input() -> void:
	var target: Dummy = _add_dummy("F", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	# Automatisch: Dauerfeuer, solange die Taste gehalten wird (12 Schuss je Sekunde).
	_weapons.give_weapon("smg")
	await _frames(2)
	_reset_records()
	Input.action_press("fire")
	await _wait(0.5)
	Input.action_release("fire")
	await _frames(2)
	var burst: int = _count("weapon_fired")
	_check(burst >= 5 and burst <= 8, "MP: etwa 6 Schuss in 0,5 s Dauerfeuer, waren %d." % burst)
	_check(_weapons.get_state("smg").mag == 30 - burst, "Jeder Schuss kostet eine Kugel.")
	_check(target.hits.size() == burst, "Jeder Schuss der MP trifft das breite Ziel, waren %d von %d." % [target.hits.size(), burst])
	await _wait(0.2)
	_check(_count("weapon_fired") == burst, "Nach dem Loslassen fällt kein Schuss mehr.")
	# Niedrige Bildrate: Bei 10 Bildern je Sekunde ist ein Bild länger als die Schussfolge der MP.
	# Dann fallen in manchen Bildern zwei Schüsse, damit die Rate von 12 je Sekunde stimmt.
	# Der Test treibt den Controller selbst mit Schritten von 0,1 s an (kein echtes Bild dazwischen).
	_weapons.refill_ammo("smg")
	await _frames(2)
	_reset_records()
	Input.action_press("fire")
	await _frames(2)
	_weapons.refill_ammo("smg")
	_reset_records()
	for i: int in 20:
		_weapons.call("_process", 0.1)
	var slow_shots: int = _count("weapon_fired")
	Input.action_release("fire")
	await _frames(2)
	_check(absi(slow_shots - 24) <= 1, "MP bei 10 Bildern/s: 24 Schüsse in 2 s Dauerfeuer, waren %d." % slow_shots)
	_check(_weapons.get_state("smg").mag == 30 - _count("weapon_fired"), "Auch mehrere Schüsse in einem Bild kosten je eine Kugel.")
	# Ein langer Ruckler wird kein Feuerstoß.
	_weapons.refill_ammo("smg")
	Input.action_press("fire")
	await _frames(2)
	_reset_records()
	_weapons.call("_process", 5.0)
	var hitch_shots: int = _count("weapon_fired")
	Input.action_release("fire")
	await _frames(2)
	_check(hitch_shots >= 1 and hitch_shots <= Balance.FIRE_MAX_SHOTS_PER_FRAME,
		"MP nach einem Ruckler von 5 s: höchstens %d Schüsse in einem Bild, waren %d." % [Balance.FIRE_MAX_SHOTS_PER_FRAME, hitch_shots])
	# Halbautomatisch: ein Schuss je Tastendruck.
	_weapons.give_weapon("pistol")
	await _frames(2)
	_reset_records()
	Input.action_press("fire")
	await _wait(0.5)
	Input.action_release("fire")
	await _frames(2)
	_check(_count("weapon_fired") == 1, "Pistole: gehaltene Taste gibt nur einen Schuss, waren %d." % _count("weapon_fired"))
	await _wait(0.25)
	await _tap("fire")
	_check(_count("weapon_fired") == 2, "Pistole: erneuter Druck gibt den nächsten Schuss.")
	# Ein knapp zu früh gedrückter Abzug zählt noch (Puffer).
	await _wait(0.3)
	_reset_records()
	_weapons.try_fire()
	await _wait(WeaponDefs.fire_interval("pistol") - 0.08)
	await _tap("fire")
	# Der gepufferte Schuss fällt erst, wenn die Schussfolge abgelaufen ist: so lange warten
	# (bei hoher Bildrate ist der Druck sonst schneller vorbei als die restlichen 0,08 s).
	await _wait(0.15)
	_check(_count("weapon_fired") == 2, "Ein Druck kurz vor Ablauf der Schussfolge zählt, waren %d Schüsse." % _count("weapon_fired"))
	# Leere Waffe: kein Schuss, keine Meldung über fehlende Munition, sie lädt einfach nach.
	var pistol: WeaponState = _weapons.get_state("pistol")
	pistol.cancel_reload()
	pistol.mag = 0
	_reset_records()
	await _tap("fire")
	_check(_count("weapon_fired") == 0 and pistol.is_reloading, "Leere Pistole schießt nicht, sie lädt nach.")
	_check(_count("banner") == 0, "Munition ist unendlich: Es gibt keine Meldung über leere Munition.")
	_weapons.refill_ammo("pistol")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


func _test_not_playing() -> void:
	_ready_weapon()
	_reset_records()
	_game.set_paused(true)
	_check(not _weapons.try_fire(), "In der Pause fällt kein Schuss.")
	_weapons.start_reload()
	_check(_count("weapon_fired") == 0 and _count("reload_started") == 0, "In der Pause passiert an der Waffe nichts.")
	# Ein Klick, der die Pause beendet, darf keinen Schuss auslösen.
	Input.action_press("fire")
	await _frames(3)
	_game.set_paused(false)
	await _frames(3)
	_check(_count("weapon_fired") == 0, "Der Klick aus dem Menü löst keinen Schuss aus.")
	Input.action_release("fire")
	await _frames(2)
	await _tap("fire")
	_check(_count("weapon_fired") == 1, "Nach dem Loslassen schießt die Waffe wieder.")


func _test_view_model() -> void:
	var view_model: Node3D = _player.get_node("Camera/ViewModel")
	_weapons.give_weapon("shotgun")
	_check(view_model.weapon_id == "shotgun", "Das ViewModel zeigt die Waffe in der Hand.")
	_check(view_model.get_node("Rig/Hand0/Holder/Gun_shotgun").visible and not view_model.get_node("Rig/Hand0/Holder/Gun_pistol").visible,
		"Nur das Modell der Waffe in der Hand ist sichtbar.")
	_check(view_model.get_hand_ids() == (["shotgun"] as Array[String]), "get_hand_ids nennt die gezeigte Waffe.")
	await _frames(2)
	var eye: Vector3 = _player.get_eye_position()
	var muzzle: Vector3 = view_model.get_muzzle_position()
	_check(muzzle.distance_to(eye) < 1.0 and (muzzle - eye).dot(_player.get_aim_direction()) > 0.0,
		"Die Mündung liegt kurz vor der Kamera, Abstand %s." % muzzle.distance_to(eye))
	view_model.set_weapon("pistol")
	_check(view_model.weapon_id == "pistol" and view_model.get_node("Rig/Hand0/Holder/Gun_pistol").visible, "set_weapon zeigt die Pistole.")
	view_model.set_weapon("laserschwert")
	_check(view_model.weapon_id == "pistol", "Eine unbekannte Waffe zeigt nichts Neues.")
	# Jede der neun Waffen hat ihr eigenes Modell mit Mündung vor der Kamera.
	var part_counts: Dictionary = {}
	for weapon_id: String in WeaponDefs.ORDER:
		view_model.set_weapon(weapon_id)
		var gun: Node3D = view_model.get_node_or_null("Rig/Hand0/Holder/Gun_%s" % weapon_id)
		_check(gun != null and gun.visible, "Das Modell von %s ist zu sehen." % weapon_id)
		if gun == null:
			continue
		_check(gun.get_node_or_null("Muzzle") != null and view_model.get_muzzle_node() == gun.get_node("Muzzle"), "%s hat eine Mündung." % weapon_id)
		var meshes: int = gun.find_children("*", "MeshInstance3D", true, false).size()
		_check(meshes >= 8, "%s besteht aus mehreren Teilen, waren %d." % [weapon_id, meshes])
		part_counts[weapon_id] = meshes
		var visible_guns: int = 0
		for child: Node in view_model.get_node("Rig/Hand0/Holder").get_children():
			if (child as Node3D).visible:
				visible_guns += 1
		_check(visible_guns == 1, "Bei %s ist genau ein Modell sichtbar." % weapon_id)
		await _frames(25)
		var in_view: Vector3 = _muzzle_in_view(0)
		_check(in_view.z < -0.05 and in_view.x > 0.0 and absf(in_view.y) < 0.2, "Die Mündung von %s liegt rechts vor der Kamera, war %s." % [weapon_id, in_view])
		view_model.play_fire(0)
		await _frames(2)
		_check(view_model.get_node("Rig/Hand0/Holder").position.is_finite(), "Rückstoß von %s hält das Modell in gültiger Lage." % weapon_id)
	# Beidhändig: zwei Modelle, das linke gespiegelt, jede Hand mit eigenem Rückstoß und Nachladen.
	_weapons.equip(["pistol", "smg"] as Array[String])
	_check(view_model.get_hand_ids() == (["pistol", "smg"] as Array[String]) and view_model.weapon_id == "pistol", "Beidhändig zeigt das ViewModel beide Waffen.")
	_check(view_model.get_node("Rig/Hand0/Holder/Gun_pistol").visible and view_model.get_node("Rig/Hand1/Holder/Gun_smg").visible,
		"Links die Pistole, rechts die MP.")
	_check(view_model.get_node("Rig/Hand0").scale.x < 0.0 and view_model.get_node("Rig/Hand1").scale.x > 0.0 and view_model.get_node("Rig/Hand1").visible,
		"Die linke Waffe ist gespiegelt, die rechte nicht.")
	await _frames(25)
	_check(_muzzle_in_view(0).x < 0.0 and _muzzle_in_view(1).x > 0.0, "Die Mündungen liegen links und rechts.")
	var left_holder: Node3D = view_model.get_node("Rig/Hand0/Holder")
	var right_holder: Node3D = view_model.get_node("Rig/Hand1/Holder")
	var right_rest: float = right_holder.position.z
	var left_rest: float = left_holder.position.z
	view_model.play_fire(1)
	_check(right_holder.position.z > right_rest + 0.02 and absf(left_holder.position.z - left_rest) < 0.005,
		"Der Rückstoß trifft nur die Hand, die schießt.")
	_check(view_model.get_node("Rig/Hand1/Holder/Gun_smg/Muzzle").get_child_count() > 0, "Das Mündungsfeuer entsteht an der Mündung der rechten Hand.")
	_check(view_model.get_node("Rig/Hand0/Holder/Gun_pistol/Muzzle").get_child_count() == 0, "An der linken Mündung blitzt nichts.")
	await _wait(0.5)
	_events.emit_signal("hand_reload_started", 0, 1.0)
	await _wait(0.4)
	_check(absf(left_holder.rotation.z) > 0.3 and absf(right_holder.rotation.z) < 0.1,
		"Beim Nachladen kippt nur die Waffe der Hand, die nachlädt (%s und %s)." % [left_holder.rotation.z, right_holder.rotation.z])
	_events.emit_signal("hand_reload_finished", 0)
	await _wait(0.3)
	_check(absf(left_holder.rotation.z) < 0.1, "Nach dem Nachladen steht die Waffe wieder gerade.")
	# Zurück zu einer Waffe: Die zweite Hand verschwindet.
	_weapons.give_weapon("pistol")
	_check(not view_model.get_node("Rig/Hand1").visible and view_model.get_node("Rig/Hand0").scale.x > 0.0, "Mit einer Waffe ist nur noch die rechte Seite belegt.")
	_ready_weapon()
	_weapons.try_fire()
	await _frames(3)
	_check(view_model.get_node("Rig/Hand0/Holder").position.is_finite(), "Rückstoß hält das Modell in gültiger Lage.")


func _test_health_and_death() -> void:
	_game.start_run(11)
	await _settle()
	_reset_records()
	_player.take_damage(20.0)
	_check(is_equal_approx(_player.hp, 80.0), "20 Schaden: 80 Leben.")
	_check(_received.get("player_damaged", []) == [[20.0]], "player_damaged(20).")
	_check(_last("player_health_changed") == [80.0, 100.0], "player_health_changed(80, 100).")
	_player.take_damage(20.0)
	_check(is_equal_approx(_player.hp, 80.0) and _count("player_damaged") == 1,
		"0,5 s nach einem Treffer ist der Spieler unverwundbar.")
	await _wait(0.3)
	_player.take_damage(20.0)
	_check(is_equal_approx(_player.hp, 80.0), "Nach 0,3 s gilt die Unverwundbarkeit noch.")
	await _wait(0.3)
	_player.take_damage(30.0)
	_check(is_equal_approx(_player.hp, 50.0), "Nach 0,5 s trifft der nächste Schlag: 50 Leben.")
	_player.take_damage(-5.0)
	_check(is_equal_approx(_player.hp, 50.0), "Negativer Schaden wird ignoriert.")
	await _wait(1.0)
	_check(is_equal_approx(_player.hp, 50.0), "Keine automatische Heilung.")
	_player.heal(10.0)
	_check(is_equal_approx(_player.hp, 60.0) and _last("player_health_changed") == [60.0, 100.0], "heal(10): 60 Leben.")
	# Mehr Maximal-Leben heilt um den Zuwachs.
	_game.upgrades.add_levels("max_hp", 2)
	_events.emit_signal("upgrade_chosen", "max_hp", 2)
	_check(is_equal_approx(_player.max_hp, 140.0) and is_equal_approx(_player.hp, 100.0),
		"Stuntdouble Stufe 2: 140 Maximal-Leben, Zuwachs heilt (60 → 100). War %s / %s." % [_player.hp, _player.max_hp])
	_player.heal(1000.0)
	_check(is_equal_approx(_player.hp, 140.0), "heal füllt höchstens bis max_hp.")
	# Tod: genau einmal.
	_reset_records()
	_player.take_damage(500.0)
	_check(_player.is_dead and is_zero_approx(_player.hp), "Tödlicher Schlag: is_dead und 0 Leben.")
	_check(_count("player_died") == 1, "player_died genau einmal.")
	_check(_game.state == _game.State.GAME_OVER, "Der Tod beendet den Lauf.")
	_player.take_damage(50.0)
	_player.heal(50.0)
	_check(_count("player_died") == 1 and is_zero_approx(_player.hp), "Tote nehmen keinen Schaden und heilen nicht.")
	_ready_weapon()
	_check(not _weapons.try_fire(), "Tote schießen nicht.")
	# Neuer Lauf stellt alles wieder her.
	_game.start_run(11)
	await _settle()
	_check(not _player.is_dead and is_equal_approx(_player.hp, 100.0) and is_equal_approx(_player.max_hp, 100.0),
		"run_started: lebendig mit 100 von 100 Leben.")
	_ready_weapon()
	_check(_weapons.try_fire(), "Nach dem Neustart schießt die Pistole wieder.")
	# Auch der zweite Lauf endet mit genau einem player_died.
	await _wait(0.6)
	_player.take_damage(500.0)
	_check(_count("player_died") == 2, "Der zweite Lauf endet mit genau einem weiteren player_died.")
	_game.start_run(11)
	await _settle()


func _test_movement() -> void:
	await _place_player(Vector3(0.0, 0.0, 60.0))
	var start: Vector3 = _player.global_position
	# Gehen.
	Input.action_press("move_forward")
	await _wait(0.5)
	var walk_speed: float = _flat_speed()
	_check(absf(walk_speed - Balance.PLAYER_WALK_SPEED) < 0.15, "Gehen mit 5 m/s, war %s." % walk_speed)
	_check(_player.global_position.z < start.z - 1.5 and absf(_player.global_position.x - start.x) < 0.1,
		"W bewegt in Blickrichtung (-Z).")
	_check(not _player.is_sprinting(), "Ohne Umschalt kein Sprint.")
	# Sprinten.
	Input.action_press("sprint")
	await _wait(0.3)
	_check(absf(_flat_speed() - Balance.PLAYER_SPRINT_SPEED) < 0.15 and _player.is_sprinting(),
		"Sprinten mit 7 m/s, war %s." % _flat_speed())
	Input.action_release("sprint")
	# Turbo-Turnschuhe.
	_game.upgrades.add_levels("speed", 2)
	_events.emit_signal("upgrade_chosen", "speed", 2)
	await _wait(0.3)
	_check(absf(_flat_speed() - Balance.PLAYER_WALK_SPEED * 1.16) < 0.15, "Tempo-Upgrade Stufe 2: 5,8 m/s, war %s." % _flat_speed())
	Input.action_release("move_forward")
	await _wait(0.3)
	_check(_flat_speed() < 0.05, "Ohne Eingabe bleibt der Spieler stehen.")
	# Seitwärts relativ zum Blick.
	_player.look_at_point(_player.global_position + Vector3(10.0, Balance.PLAYER_EYE_HEIGHT, 0.0))
	var before: Vector3 = _player.global_position
	Input.action_press("move_right")
	await _wait(0.3)
	Input.action_release("move_right")
	_check(_player.global_position.z > before.z + 0.5, "Blick nach +X: D bewegt nach +Z.")
	await _wait(0.3)
	# Springen.
	var top: float = 0.0
	Input.action_press("jump")
	for i: int in 40:
		await physics_frame
		top = maxf(top, _player.global_position.y)
	Input.action_release("jump")
	# 4,5² / (2 * 12) = 0,84 m.
	_check(top > 0.7 and top < 0.95, "Sprunghöhe etwa 0,84 m, war %s." % top)
	await _wait(0.6)
	_check(_player.is_on_floor() and absf(_player.global_position.y) < 0.02, "Nach dem Sprung wieder am Boden.")
	_check(absf(_player.get_eye_position().y - Balance.PLAYER_EYE_HEIGHT) < 0.05, "Die Kamera kommt nach der Landung zur Ruhe.")
	# Außerhalb von PLAYING bewegt keine Eingabe.
	_game.set("state", _game.State.MENU)
	before = _player.global_position
	Input.action_press("move_forward")
	Input.action_press("jump")
	await _wait(0.3)
	Input.action_release("move_forward")
	Input.action_release("jump")
	_check(_player.global_position.distance_to(before) < 0.01, "Außerhalb von PLAYING bewegt sich der Spieler nicht.")
	_game.set("state", _game.State.PLAYING)
	_game.start_run(11)
	await _settle()


func _test_steps() -> void:
	# Stufe von 0,2 m: der Spieler läuft ohne Sprung hinauf.
	_add_block("Step", Vector3(100.0, 0.1, -4.0), Vector3(4.0, 0.2, 4.0))
	# Kiste von 0,6 m: zu hoch, hält auf.
	_add_block("Crate", Vector3(120.0, 0.3, -4.0), Vector3(4.0, 0.6, 4.0))
	await _place_player(Vector3(100.0, 0.0, 0.0))
	Input.action_press("move_forward")
	await _wait(0.7)
	Input.action_release("move_forward")
	await _wait(0.2)
	_check(_player.global_position.z < -2.2 and absf(_player.global_position.y - 0.2) < 0.03,
		"Eine Stufe von 0,2 m läuft der Spieler hoch, Position %s." % _player.global_position)
	_check(absf(_player.get_eye_position().y - (0.2 + Balance.PLAYER_EYE_HEIGHT)) < 0.05, "Die Kamera folgt auf die Stufe.")
	await _place_player(Vector3(120.0, 0.0, 0.0))
	Input.action_press("move_forward")
	await _wait(0.7)
	Input.action_release("move_forward")
	await _wait(0.2)
	_check(_player.global_position.z > -1.75 and _player.global_position.y < 0.05,
		"Eine Kiste von 0,6 m hält den Spieler auf, Position %s." % _player.global_position)
	# Bühnenkante von 0,4 m: höher als STEP_HEIGHT, also nur mit Sprung.
	_add_block("Stage", Vector3(200.0, 0.2, -4.0), Vector3(4.0, 0.4, 4.0))
	await _place_player(Vector3(200.0, 0.0, 0.0))
	Input.action_press("move_forward")
	await _wait(0.7)
	_check(_player.global_position.z > -1.75 and _player.global_position.y < 0.05,
		"Die Bühnenkante von 0,4 m hält den Spieler ohne Sprung auf, Position %s." % _player.global_position)
	Input.action_press("jump")
	await _wait(0.8)
	Input.action_release("jump")
	Input.action_release("move_forward")
	await _wait(0.2)
	_check(_player.global_position.z < -2.2 and absf(_player.global_position.y - 0.4) < 0.03,
		"Mit Sprung kommt der Spieler auf die Bühne, Position %s." % _player.global_position)
	# Showtreppe: vier Stufen zu je 0,2 m Höhe und 0,5 m Tiefe, hoch und wieder runter.
	for i: int in range(1, 5):
		var front: float = -2.0 - 0.5 * float(i - 1)
		var back: float = -8.0
		_add_block("Stair%d" % i, Vector3(220.0, 0.1 * float(i), (front + back) * 0.5),
			Vector3(4.0, 0.2 * float(i), front - back))
	await _place_player(Vector3(220.0, 0.0, 0.0))
	Input.action_press("move_forward")
	await _wait(1.2)
	Input.action_release("move_forward")
	await _wait(0.2)
	_check(absf(_player.global_position.y - 0.8) < 0.03 and _player.global_position.z < -3.6,
		"Der Spieler läuft die Treppe hoch (0,8 m), Position %s." % _player.global_position)
	_check(_player.global_position.z < -4.5, "Die Treppe bremst kaum, Position %s." % _player.global_position)
	_player.look_at_point(_player.global_position + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 10.0))
	Input.action_press("move_forward")
	await _wait(1.3)
	Input.action_release("move_forward")
	await _wait(0.3)
	_check(_player.is_on_floor() and absf(_player.global_position.y) < 0.03 and _player.global_position.z > -1.5,
		"Der Spieler läuft die Treppe wieder runter, Position %s." % _player.global_position)


func _test_interaction() -> void:
	var switch: Switch = Switch.new()
	switch.build()
	switch.position = Vector3(140.0, Balance.PLAYER_EYE_HEIGHT, -2.0)
	root.add_child(switch)
	_reset_records()
	await _place_player(Vector3(140.0, 0.0, 0.0))
	_check(_last("interact_prompt_changed") == ["E – Testknopf drücken"],
		"Im Blick und in Reichweite: Hinweis über interact_prompt_changed, war %s." % [_last("interact_prompt_changed")])
	var prompts: int = _count("interact_prompt_changed")
	await _settle()
	_check(_count("interact_prompt_changed") == prompts, "Der Hinweis wird nur bei Änderung gesendet.")
	await _tap("interact")
	await _settle()
	_check(switch.used == 1 and switch.last_user == _player, "Taste E ruft interact(player) genau einmal.")
	# Wegsehen: Hinweis verschwindet, E tut nichts.
	_player.look_at_point(_player.global_position + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 10.0))
	await _settle()
	_check(_last("interact_prompt_changed") == [""], "Ohne Objekt im Blick: leerer Hinweis.")
	await _tap("interact")
	await _settle()
	_check(switch.used == 1, "Ohne Objekt im Blick tut E nichts.")
	# Zu weit weg (Reichweite 2,5 m).
	_reset_records()
	await _place_player(Vector3(140.0, 0.0, 1.0))
	_check(_count("interact_prompt_changed") == 0, "Außerhalb von 2,5 m gibt es keinen Hinweis.")
	# Eine Wand davor verdeckt das Objekt.
	await _place_player(Vector3(140.0, 0.0, 0.0))
	_check(_last("interact_prompt_changed") == ["E – Testknopf drücken"], "Wieder in Reichweite: Hinweis da.")
	var wall: StaticBody3D = _add_block("Cover", Vector3(140.0, 1.5, -1.0), Vector3(2.0, 3.0, 0.1))
	await _settle()
	_check(_last("interact_prompt_changed") == [""], "Eine Wand davor verdeckt das Interaktionsobjekt.")
	wall.queue_free()
	switch.queue_free()
	await _settle()


func _test_mouse_look() -> void:
	await _place_player(Vector3(160.0, 0.0, 0.0))
	var yaw_before: float = _player.rotation.y
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 40.0)
	motion.screen_relative = Vector2(100.0, 40.0)
	Input.parse_input_event(motion)
	await _frames(3)
	_check(absf(angle_difference(yaw_before, _player.rotation.y) + 100.0 * Balance.MOUSE_SENSITIVITY) < 0.001,
		"Maus nach rechts dreht den Spieler nach rechts.")
	_check(absf(_player.get_look_pitch() + 40.0 * Balance.MOUSE_SENSITIVITY) < 0.001, "Maus nach unten senkt den Blick.")
	_check(_player.get_aim_direction().y < -0.05, "Die Blickrichtung zeigt nach unten.")
	var far_up: InputEventMouseMotion = InputEventMouseMotion.new()
	far_up.relative = Vector2(0.0, -5000.0)
	far_up.screen_relative = Vector2(0.0, -5000.0)
	Input.parse_input_event(far_up)
	await _frames(3)
	_check(_player.get_look_pitch() < PI * 0.5 and _player.get_look_pitch() > 1.4, "Der Blick nach oben ist begrenzt.")
	_check(_player.get_camera().global_transform.basis.y.y > 0.0, "Die Kamera kippt nicht über Kopf.")
	_player.look_at_point(Vector3(163.0, 4.6, -4.0))
	var expected: Vector3 = (Vector3(163.0, 4.6, -4.0) - Vector3(160.0, Balance.PLAYER_EYE_HEIGHT, 0.0)).normalized()
	_check(_player.get_aim_direction().distance_to(expected) < 0.01, "look_at_point richtet den Blick auf den Punkt.")
	# Mausempfindlichkeit aus den Einstellungen: doppelter Faktor, doppelte Drehung.
	var settings: GDScript = load("res://scripts/game/settings.gd") as GDScript
	_check(is_equal_approx(float(settings.get("mouse_sensitivity")), 1.0), "Im Test gilt die Standard-Empfindlichkeit (1,0).")
	for factor: float in [2.0, 0.5]:
		settings.call("set_mouse_sensitivity", factor)
		var yaw_start: float = _player.rotation.y
		var sweep: InputEventMouseMotion = InputEventMouseMotion.new()
		sweep.relative = Vector2(50.0, 0.0)
		sweep.screen_relative = Vector2(50.0, 0.0)
		Input.parse_input_event(sweep)
		await _frames(3)
		_check(absf(angle_difference(yaw_start, _player.rotation.y) + 50.0 * Balance.MOUSE_SENSITIVITY * factor) < 0.001,
			"Empfindlichkeit %d Prozent dreht entsprechend weit." % roundi(factor * 100.0))
	settings.call("set_mouse_sensitivity", 1.0)


# --- Helfer ---


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


## Drückt eine Aktion für ein paar Bilder und lässt sie wieder los.
func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(3)
	Input.action_release(action)
	await _frames(2)


## Ein Tick am Mausrad als echtes Eingabe-Ereignis.
func _wheel(button: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(3)


func _flat_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func _hit_counts(dummies: Array[Dummy]) -> Array:
	var counts: Array = []
	for dummy: Dummy in dummies:
		counts.append(dummy.hits.size())
	return counts


func _record(signal_name: String, args: Array) -> void:
	if not _received.has(signal_name):
		_received[signal_name] = []
	(_received[signal_name] as Array).append(args)


func _count(signal_name: String) -> int:
	return (_received.get(signal_name, []) as Array).size()


## Argumente des letzten Signals mit diesem Namen, [] wenn keines kam.
func _last(signal_name: String) -> Array:
	var list: Array = _received.get(signal_name, [])
	if list.is_empty():
		return []
	return list[list.size() - 1]


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
