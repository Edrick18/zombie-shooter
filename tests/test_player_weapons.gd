extends SceneTree
## Tests für das Modul Spieler: player.gd, weapon_controller.gd, view_model.gd.
## Baut headless eine kleine Welt (Boden, Spieler, Ersatz-Zombies auf Lage 3 in Gruppe "zombies")
## und prüft Schaden, Kopftreffer, Durchschlag mit Schadensabfall, Schrotkugeln, Magazin und
## unendliche Munition, Nachladen, Waffen aus dem Rucksack (eine Hand, zwei Hände, beidhändig),
## Abgleich bei build_changed, Faktoren für Schaden und Nachladen, Raketen-Explosion, Signale je
## Hand, Leben, Tod, Bewegung, Stufen und Interaktion. Dazu die Gegenstände je Waffe aus
## Abschnitt 19.1 mit dem echten Rucksack: Zugabe, Glücksrad, Überlänge, Teleprompter,
## Schnelldurchlauf, jeweils nur für die Waffe auf den Sternen. Dazu die zehn Waffen aus Abschnitt
## 22.2: Salve, eingebauter Durchschlag, eingebauter Blitz, Granate im Bogen, Flammenkegel mit
## Brand, Dauerstrahl, Treffer-Punkte von Flamme und Strahl, Eröffnungsgag und Schlusspointe, die
## zehn neuen Modelle (auch in der zweiten Hand).
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
	## Jeder Brand, den die Waffe setzt: [Schaden je Sekunde, Dauer].
	var burns: Array = []
	## Gemeinsames Protokoll des Tests (Reihenfolge von Schaden und Signalen).
	var journal: Array = []
	## Gesetzt (Autoload Events): Der Ersatz-Zombie meldet Schaden wie ein echter über
	## zombie_damaged, damit Game seine Treffer-Punkte vergibt.
	var events: Node = null

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
		if events != null:
			events.emit_signal("zombie_damaged", self, amount, info)

	func apply_burn(dps: float, duration: float) -> void:
		burns.append([dps, duration])

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
## Punkte, die das letzte Dauerfeuer aus _burst gebracht hat.
var _burst_points: int = 0


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
		await _test_burst()
		await _test_builtin_pierce()
		await _test_tesla()
		await _test_grenade()
		await _test_flame()
		await _test_beam()
		await _test_extra_shot()
		await _test_crit()
		await _test_big_mag()
		await _test_scope()
		await _test_fire_rate_item()
		await _test_items_per_hand()
		await _test_opener()
		await _test_punchline()
		await _test_magazine_items_per_hand()
		await _test_fire_input()
		await _test_not_playing()
		await _test_view_model()
		await _test_new_models()
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
	_events.connect("explosion", func(at: Vector3, radius: float) -> void: _record("explosion", [at, radius]))


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


## Neuer Lauf mit genau diesen Waffen an festen Stellen im Rucksack (ohne Kandidat hat er die
## Felder x 1 bis 4, y 1 bis 3). Je Eintrag [Waffen-ID, Feld] oder [Waffen-ID, Feld, Rarität].
## Gibt die uids in derselben Reihenfolge zurück. Abgeglichen wird noch nicht: Erst kommen die
## Gegenstände (_attach), dann _game.sync_build().
func _pack_weapons(weapons: Array) -> Array[int]:
	_game.start_run(11)
	var backpack: RefCounted = _game.backpack
	var uids: Array[int] = []
	for entry: Array in weapons:
		var uid: int = backpack.add_item(String(entry[0]), int(entry[2]) if entry.size() > 2 else 1)
		_check(backpack.place(uid, entry[1] as Vector2i, 0), "Aufbau: %s passt auf das Feld %s." % [entry[0], entry[1]])
		uids.append(uid)
	return uids


## Räumt einen Stern-Gegenstand so ein, dass seine Sterne genau diese Waffen treffen (geprüft mit
## star_targets): die erste passende Stelle, erst ungedreht, dann gedreht. Gibt seine uid zurück.
## Abgeglichen wird nicht.
func _attach(item_id: String, level: int, weapon_uids: Array[int]) -> int:
	var backpack: RefCounted = _game.backpack
	var wanted: Array = []
	for weapon_uid: int in weapon_uids:
		wanted.append(weapon_uid)
	wanted.sort()
	var uid: int = backpack.add_item(item_id, level)
	for rot: int in 4:
		for cell: Vector2i in backpack.cells():
			if not backpack.place(uid, cell, rot):
				continue
			var targets: Array = []
			for target_uid: int in backpack.star_targets(uid):
				targets.append(target_uid)
			targets.sort()
			if targets == wanted:
				return uid
			backpack.store(uid)
	_check(false, "Aufbau: %s findet keine Stelle, an der seine Sterne genau die Waffen %s treffen." % [item_id, wanted])
	return uid


## Leuchtspuren, die gerade in der Welt hängen: dünne, lang gezogene Quader direkt unter der
## Wurzel (Fx.tracer). Am Namen sind sie nicht zu erkennen, Godot benennt gleichnamige Knoten um.
func _tracer_count() -> int:
	var count: int = 0
	for child: Node in root.get_children():
		var beam: MeshInstance3D = child as MeshInstance3D
		if beam == null or beam.is_queued_for_deletion() or not beam.mesh is BoxMesh:
			continue
		var axes: Basis = beam.global_transform.basis
		if axes.z.length() > 1.0 and axes.x.length() < 0.1:
			count += 1
	return count


## Winkel in Grad zwischen der Blickrichtung und dem Einschlag eines Treffers.
func _hit_angle(hit: Dictionary) -> float:
	var at: Vector3 = hit["info"]["hit_position"]
	return rad_to_deg(_player.get_aim_direction().angle_to(at - _player.get_eye_position()))


## Treffer eines Ersatz-Zombies mit dieser Marke in der Info ("extra" oder "crit").
func _flagged(dummy: Dummy, flag: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit: Dictionary in dummy.hits:
		if bool(hit["info"].get(flag, false)):
			result.append(hit)
	return result


## Treffer eines Ersatz-Zombies aus dieser Hand.
func _hits_of_hand(dummy: Dummy, hand: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit: Dictionary in dummy.hits:
		if int(hit["info"].get("hand", -1)) == hand:
			result.append(hit)
	return result


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
			dummy.burns.clear()


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


# --- Die zehn Waffen aus Abschnitt 22.2 ---


## Treibt die Waffensteuerung selbst mit festen Schritten an (kein echtes Bild dazwischen, kein
## gedrückter Abzug): Salven laufen weiter, Strahl und Flamme laufen aus.
func _step(seconds: float, delta: float = 1.0 / 60.0) -> void:
	var left: float = seconds
	while left > 0.000001:
		_weapons.call("_process", minf(delta, left))
		left -= delta


## Wartet in Physik-Schritten, bis mindestens count Explosionen gemeldet sind (höchstens
## max_steps Schritte). Gibt die gewarteten Schritte zurück.
func _until_explosions(count: int, max_steps: int = 420) -> int:
	var steps: int = 0
	while _count("explosion") < count and steps < max_steps:
		await physics_frame
		steps += 1
	return steps


## Granaten, die gerade fliegen (Knoten mit dem Skript grenade.gd direkt unter der Wurzel).
func _grenade_count() -> int:
	var count: int = 0
	for child: Node in root.get_children():
		if child.has_method("point_at") and not child.is_queued_for_deletion() and not bool(child.call("is_done")):
			count += 1
	return count


## Blitze, die gerade in der Welt hängen (Fx.lightning: ein Netz aus ImmediateMesh unter der Wurzel).
func _lightning_count() -> int:
	var count: int = 0
	for child: Node in root.get_children():
		var arc: MeshInstance3D = child as MeshInstance3D
		if arc != null and not arc.is_queued_for_deletion() and arc.mesh is ImmediateMesh:
			count += 1
	return count


## Treffer eines Ersatz-Zombies mit dieser Schadensquelle.
func _hits_from(dummy: Dummy, source: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit: Dictionary in dummy.hits:
		if String(hit["info"].get("source", "")) == source:
			result.append(hit)
	return result


## Höchste Schussrate einer automatischen Kugelwaffe: So viele Treffer-Punkte je Sekunde gibt
## eine normale Automatikwaffe höchstens (mal Balance.POINTS_BULLET_HIT).
func _max_auto_rate() -> float:
	var best: float = 0.0
	for weapon_id: String in WeaponDefs.ORDER:
		if WeaponDefs.mode(weapon_id) == WeaponDefs.MODE_BULLET and WeaponDefs.is_automatic(weapon_id):
			best = maxf(best, float(WeaponDefs.get_def(weapon_id)["fire_rate"]))
	return best


## Salve (Dreierpack): Ein Abzug gibt drei Schüsse im Abstand burst_interval, jeder ein ganzer Schuss.
func _test_burst() -> void:
	var id: String = "burst_pistol"
	var target: Dummy = _add_dummy("S", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon(id)
	var state: WeaponState = _weapons.get_state(id)
	var size: int = WeaponDefs.burst(id)
	var gap: float = WeaponDefs.burst_interval(id)
	var damage: float = WeaponDefs.bullet_damage(id, false)
	var magazine: int = WeaponDefs.magazine_size(id)
	_check(state != null and size == 3 and gap > 0.0 and gap * float(size) < WeaponDefs.fire_interval(id),
		"Aufbau: Der Dreierpack gibt 3 Schüsse je Abzug, die Salve ist kürzer als die Schussfolge.")
	if state == null:
		await _clear_dummies()
		return
	_reset_records()
	_check(_weapons.try_fire(), "Der Dreierpack schießt.")
	_check(_count("weapon_fired") == 1 and state.mag == magazine - 1 and state.is_bursting(),
		"Der Abzug gibt sofort den ersten Schuss, die Salve läuft. Schüsse: %d." % _count("weapon_fired"))
	_weapons.call("_process", gap * 0.5)
	_check(_count("weapon_fired") == 1, "Vor Ablauf des Abstands fällt kein zweiter Schuss.")
	_weapons.call("_process", gap * 0.6)
	_check(_count("weapon_fired") == 2 and state.mag == magazine - 2, "Nach dem Abstand folgt der zweite Schuss von selbst, waren %d." % _count("weapon_fired"))
	_weapons.call("_process", gap)
	_check(_count("weapon_fired") == size and state.mag == magazine - size and not state.is_bursting(),
		"Nach zwei Abständen ist die Salve aus drei Schüssen vorbei, waren %d." % _count("weapon_fired"))
	_step(gap * 3.0)
	_check(_count("weapon_fired") == size and _fired(id) == size, "Nach der Salve fällt kein weiterer Schuss.")
	_check(target.hits.size() == size, "Jeder Schuss der Salve trifft, waren %d." % target.hits.size())
	for hit: Dictionary in target.hits:
		_check(is_equal_approx(hit["amount"], damage) and hit["info"].get("weapon") == id and hit["info"].get("source") == "bullet",
			"Jeder Schuss der Salve macht den Kugelschaden (%s), war %s." % [damage, hit["amount"]])
	_check(_journal == ["damage:S", "bullet_hit:S", "weapon_fired", "damage:S", "bullet_hit:S", "weapon_fired", "damage:S", "bullet_hit:S", "weapon_fired"],
		"Jeder Schuss der Salve: Schaden, bullet_hit, weapon_fired. War %s." % [_journal])
	_check(_received.get("hand_ammo_changed", []) == [[0, magazine - 1, magazine], [0, magazine - 2, magazine], [0, magazine - 3, magazine]],
		"hand_ammo_changed kommt für jede Kugel der Salve, war %s." % [_received.get("hand_ammo_changed", [])])
	# Die Schussfolge zählt von Salve zu Salve.
	_check(not _weapons.try_fire() and _count("weapon_fired") == size, "Vor Ablauf der Schussfolge beginnt keine neue Salve.")
	_step(WeaponDefs.fire_interval(id))
	_check(_weapons.try_fire() and _count("weapon_fired") == size + 1, "Nach der Schussfolge beginnt die nächste Salve.")
	# Ein langes Bild: Die beiden restlichen Schüsse fallen im selben Schritt.
	_weapons.call("_process", gap * float(size) + 0.05)
	_check(_count("weapon_fired") == size * 2 and state.mag == magazine - size * 2,
		"Bei einem langen Bild fallen die restlichen Schüsse der Salve zusammen, waren %d." % _count("weapon_fired"))
	# Das Magazin reicht nicht: Die Salve ist kürzer, danach wird nachgeladen.
	_step(WeaponDefs.fire_interval(id))
	state.mag = 2
	_reset_records()
	_check(_weapons.try_fire(), "Mit zwei Kugeln beginnt eine Salve.")
	_step(gap * 4.0)
	_check(_count("weapon_fired") == 2 and state.mag == 0 and state.is_reloading,
		"Mit zwei Kugeln hat die Salve zwei Schüsse und endet im Nachladen, waren %d." % _count("weapon_fired"))
	# Nachladen bricht die Salve ab.
	_weapons.refill_ammo(id)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_weapons.start_reload()
	_step(gap * 4.0)
	_check(_count("weapon_fired") == 1 and state.is_reloading and not state.is_bursting(), "Nachladen bricht die laufende Salve ab.")
	# Mit der Maustaste: ein Druck, eine Salve. Gehaltene Taste gibt keine zweite.
	_weapons.refill_ammo(id)
	_ready_weapon()
	await _frames(2)
	_reset_records()
	Input.action_press("fire")
	await _wait(WeaponDefs.fire_interval(id) * 2.5)
	Input.action_release("fire")
	await _frames(2)
	_check(_count("weapon_fired") == size, "Gehaltene Taste: genau eine Salve (%d Schüsse), waren %d." % [size, _count("weapon_fired")])
	# Zugabe: Jeder Schuss der Salve bringt seine Zusatzkugel mit, Munition kostet nur die Salve.
	_weapons.refill_ammo(id)
	_game.upgrades.add_levels("extra_shot", 1)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_step(gap * 4.0)
	_check(_count("weapon_fired") == size and target.hits.size() == size * 2 and _flagged(target, "extra").size() == size,
		"Salve mit Zugabe: %d Schüsse, %d Treffer, davon %d Zusatzkugeln. Waren %d, %d und %d." % [
			size, size * 2, size, _count("weapon_fired"), target.hits.size(), _flagged(target, "extra").size()])
	_check(state.mag == magazine - size, "Die Zusatzkugeln der Salve kosten keine Munition.")
	# Beidhändig: Jede Hand gibt ihre eigene Salve.
	_weapons.equip([id, id] as Array[String])
	var hands: Array[Dictionary] = _weapons.get_hands()
	_check(hands.size() == 2, "Aufbau: zwei Dreierpacks in den Händen.")
	if hands.size() == 2:
		# Die Waffe von eben behält ihr Magazin: beide auffüllen.
		_weapons.refill_ammo(id)
		_ready_weapon()
		_reset_records()
		_check(_weapons.try_fire() and _count("weapon_fired") == 2, "Beidhändig gibt der Abzug zwei erste Schüsse.")
		_step(gap * 4.0)
		_check(_count("weapon_fired") == size * 2, "Beidhändig fallen zwei Salven (%d Schüsse), waren %d." % [size * 2, _count("weapon_fired")])
		_check(_hits_of_hand(target, 0).size() == size and _hits_of_hand(target, 1).size() == size,
			"Jede Hand trifft mit ihrer ganzen Salve, waren %d und %d." % [_hits_of_hand(target, 0).size(), _hits_of_hand(target, 1).size()])
		_check(_weapons.get_state_of(int(hands[0]["uid"])).mag == magazine - size and _weapons.get_state_of(int(hands[1]["uid"])).mag == magazine - size,
			"Beide Magazine zählen um die Salve herunter.")
	# Ohne Erlaubnis zu handeln (Pause) bricht die Salve ab.
	_step(WeaponDefs.fire_interval(id))
	_reset_records()
	_weapons.try_fire()
	_game.set_paused(true)
	_step(gap * 4.0)
	_game.set_paused(false)
	_check(_count("weapon_fired") == mini(hands.size(), 2) and not _weapons.get_state(id).is_bursting(), "In der Pause läuft keine Salve weiter.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Eingebauter Durchschlag (Bühnenbau, Zielgerade): kommt zum Durchschlag aus Gegenständen dazu.
func _test_builtin_pierce() -> void:
	var line: Array[Dummy] = []
	for i: int in 6:
		line.append(_add_dummy("L%d" % i, Vector3(0.0, 0.0, -4.0 - 1.5 * float(i))))
	await _place_player(Vector3.ZERO)
	# Ohne eingebauten Durchschlag trifft eine neue Kugelwaffe nur den Vordersten.
	_check(WeaponDefs.pierce("lmg") == 0, "Aufbau: Die Marathonsendung durchschlägt von sich aus nichts.")
	_weapons.give_weapon("lmg")
	_reset_records()
	_weapons.try_fire()
	_check(_hit_counts(line) == [1, 0, 0, 0, 0, 0], "Marathonsendung: nur der Vorderste, war %s." % [_hit_counts(line)])
	# Bühnenbau: ein weiteres Ziel, mit Schadensabfall.
	var nail_pierce: int = WeaponDefs.pierce("nail_gun")
	_check(nail_pierce == 1, "Aufbau: Der Bühnenbau durchschlägt einen weiteren Zombie.")
	_weapons.give_weapon("nail_gun")
	var nail_uid: int = int(_weapons.get_hands()[0]["uid"])
	_reset_records()
	_check(_weapons.try_fire(), "Der Bühnenbau schießt.")
	_check(_hit_counts(line) == [1, 1, 0, 0, 0, 0], "Bühnenbau: zwei Zombies je Nagel, war %s." % [_hit_counts(line)])
	_check(is_equal_approx(line[0].total_damage(), WeaponDefs.bullet_damage("nail_gun", false, 0))
		and is_equal_approx(line[1].total_damage(), WeaponDefs.bullet_damage("nail_gun", false, 1))
		and line[1].total_damage() < line[0].total_damage(),
		"Bühnenbau: voller Schaden vorn, Abfall dahinter. Waren %s und %s." % [line[0].total_damage(), line[1].total_damage()])
	_check(_count("bullet_hit") == 2 and _count("weapon_fired") == 1, "Zwei Treffer, ein Schuss.")
	if line[1].hits.size() == 1:
		_check(line[1].hits[0]["info"].get("weapon_uid") == nail_uid and line[1].hits[0]["info"].get("source") == "bullet",
			"Auch der durchschlagene Zombie ist ein Kugeltreffer der Waffe.")
	# Der Durchschlag aus Gegenständen kommt dazu.
	_game.upgrades.add_levels("pierce", 2)
	var item_pierce: int = int(_game.bullet_value(nail_uid, "pierce", "targets"))
	_check(item_pierce >= 1, "Aufbau: Die Spezialmunition gibt weitere Ziele (%d)." % item_pierce)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	var expected: Array = []
	for i: int in line.size():
		expected.append(1 if i <= nail_pierce + item_pierce else 0)
	_check(_hit_counts(line) == expected, "Eingebauter Durchschlag plus Gegenstand: %s erwartet, war %s." % [expected, _hit_counts(line)])
	# Zielgerade: drei weitere Ziele, ohne Streuung.
	var bolt_pierce: int = WeaponDefs.pierce("crossbow")
	_check(bolt_pierce == 3, "Aufbau: Die Zielgerade durchschlägt drei weitere Zombies.")
	_weapons.give_weapon("crossbow")
	_reset_records()
	_check(_weapons.try_fire(), "Die Zielgerade schießt.")
	_check(_hit_counts(line) == [1, 1, 1, 1, 0, 0], "Zielgerade: vier Zombies je Bolzen, war %s." % [_hit_counts(line)])
	for i: int in 4:
		_check(is_equal_approx(line[i].total_damage(), WeaponDefs.bullet_damage("crossbow", false, i)),
			"Zielgerade, Ziel %d: %s Schaden erwartet, war %s." % [i + 1, WeaponDefs.bullet_damage("crossbow", false, i), line[i].total_damage()])
	_check(_weapons.get_state("crossbow").mag == 0 and _weapons.get_state("crossbow").is_reloading, "Ein Bolzen je Magazin: Danach wird nachgeladen.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Eingebauter Blitz (Kurzschluss): Jeder Treffer springt auf weitere Zombies im Umkreis.
func _test_tesla() -> void:
	var id: String = "tesla"
	var jumps: int = WeaponDefs.arc_jumps(id)
	var factor: float = WeaponDefs.arc_factor(id)
	var reach: float = WeaponDefs.arc_radius(id)
	_check(jumps == 3 and factor > 0.0 and factor < 1.0 and reach > 2.5, "Aufbau: Der Kurzschluss springt dreimal mit einem Anteil des Schadens.")
	# Eine Reihe quer zur Blickrichtung, je 2 m Abstand: getroffen wird der erste, der Blitz
	# springt der Reihe nach weiter. Für den fünften reichen die Sprünge nicht.
	var row: Array[Dummy] = []
	for i: int in jumps + 2:
		row.append(_add_dummy("T%d" % i, Vector3(2.0 * float(i), 0.0, -6.0)))
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon(id)
	var uid: int = int(_weapons.get_hands()[0]["uid"])
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	var damage: float = WeaponDefs.bullet_damage(id, false)
	_reset_records()
	var bolts_before: int = _lightning_count()
	_check(_weapons.try_fire(), "Der Kurzschluss schießt.")
	_check(row[0].hits.size() == 1 and is_equal_approx(row[0].hits[0]["amount"], damage) and row[0].hits[0]["info"].get("source") == "bullet",
		"Der getroffene Zombie bekommt den Kugelschaden (%s) und keinen Blitz dazu. War %s." % [damage, row[0].hits])
	for i: int in range(1, jumps + 1):
		_check(row[i].hits.size() == 1, "Der Blitz springt auf Zombie %d, Treffer: %d." % [i, row[i].hits.size()])
		if row[i].hits.size() == 1:
			var info: Dictionary = row[i].hits[0]["info"]
			_check(is_equal_approx(row[i].hits[0]["amount"], damage * factor), "Sprung %d: %s Schaden erwartet, war %s." % [i, damage * factor, row[i].hits[0]["amount"]])
			_check(info.get("source") == "lightning" and info.get("arc") == true, "Sprung %d hat die Quelle lightning und die Marke arc." % i)
			_check(info.get("weapon_uid") == uid and info.get("weapon") == id and info.get("weapon_id") == id and info.get("hand") == 0
				and info.get("extra") == false and info.get("crit") == false and info.has("hit_position"),
				"Sprung %d nennt Waffe, uid, Hand, extra und crit. War %s." % [i, info])
	_check(row[jumps + 1].hits.is_empty(), "Nach %d Sprüngen ist Schluss: Der letzte Zombie bleibt verschont." % jumps)
	_check(_count("bullet_hit") == 1, "Nur der Kugeltreffer sendet bullet_hit, die Sprünge nicht. Waren %d." % _count("bullet_hit"))
	_check(_journal == ["damage:T0", "bullet_hit:T0", "damage:T1", "damage:T2", "damage:T3", "weapon_fired"],
		"Erst der Treffer, dann die Sprünge von nah nach fern, dann weapon_fired. War %s." % [_journal])
	_check(_lightning_count() - bolts_before == 2, "Sichtbar: ein Blitz für den Schuss und einer für die Sprünge, neu waren %d." % (_lightning_count() - bolts_before))
	# Kopftreffer: Die Sprünge rechnen mit dem Schaden des Treffers.
	_ready_weapon()
	_reset_records()
	_player.look_at_point(Vector3(0.0, 2.6, -5.7))
	_weapons.try_fire()
	var head_damage: float = WeaponDefs.bullet_damage(id, true)
	_check(row[0].hits.size() == 1 and is_equal_approx(row[0].hits[0]["amount"], head_damage)
		and row[1].hits.size() == 1 and is_equal_approx(row[1].hits[0]["amount"], head_damage * factor),
		"Kopftreffer: %s am Ziel und %s je Sprung." % [head_damage, head_damage * factor])
	# Ein toter Zombie wird übersprungen, ein Schuss in die Wand springt nicht.
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	row[1].is_dead = true
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(row[1].hits.is_empty() and row[2].hits.size() == 1 and row[4].hits.size() == 1,
		"Ein toter Zombie nimmt keinen Sprung und verbraucht keinen. Treffer: %s." % [_hit_counts(row)])
	row[1].is_dead = false
	_ready_weapon()
	_reset_records()
	bolts_before = _lightning_count()
	_player.look_at_point(Vector3(-6.0, 0.0, -3.0))
	_weapons.try_fire()
	_check(_hit_counts(row) == [0, 0, 0, 0, 0], "Ein Schuss in den Boden löst keinen Sprung aus, war %s." % [_hit_counts(row)])
	_check(_lightning_count() - bolts_before == 1, "Auch der Schuss ins Leere ist als Blitz zu sehen.")
	await _clear_dummies()
	# Umkreis: Ein Zombie knapp außerhalb wird nicht erreicht, einer knapp innerhalb schon.
	var hit: Dummy = _add_dummy("TA", Vector3(0.0, 0.0, -6.0))
	var outside: Dummy = _add_dummy("TB", Vector3(reach + 0.6, 0.0, -6.0))
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(hit.hits.size() == 1 and outside.hits.is_empty(), "Außerhalb des Umkreises (%s m) springt der Blitz nicht." % reach)
	outside.position = Vector3(reach - 0.3, 0.0, -6.0)
	await _settle()
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(outside.hits.size() == 1 and outside.hits[0]["info"].get("source") == "lightning", "Innerhalb des Umkreises springt er.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Granate (Knalleffekt): fliegt im Bogen, Direkttreffer und Explosion am Einschlag.
func _test_grenade() -> void:
	var id: String = "grenade_launcher"
	var speed: float = WeaponDefs.projectile_speed(id)
	var gravity: float = WeaponDefs.projectile_gravity(id)
	var radius: float = float(WeaponDefs.get_def(id)["explosion_radius"])
	var blast: float = float(WeaponDefs.get_def(id)["explosion_damage"])
	var direct_damage: float = WeaponDefs.bullet_damage(id, false)
	_check(WeaponDefs.mode(id) == WeaponDefs.MODE_GRENADE and speed > 0.0 and gravity > 0.0 and radius > 0.0,
		"Aufbau: Der Knalleffekt wirft Granaten mit Tempo, Schwerkraft und Explosion.")
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon(id)
	var uid: int = int(_weapons.get_hands()[0]["uid"])
	var state: WeaponState = _weapons.get_state(id)
	var magazine: int = WeaponDefs.magazine_size(id)
	# Waagerechter Wurf aus Augenhöhe: Die Granate fällt nach sqrt(2h/g) Sekunden auf den Boden.
	var eye: Vector3 = _player.get_eye_position()
	var fall_time: float = sqrt(2.0 * eye.y / gravity)
	var landing: Vector3 = Vector3(eye.x, 0.0, eye.z - speed * fall_time)
	var near: Dummy = _add_dummy("GN", landing + Vector3(1.5, 0.0, 0.0))
	var side: Dummy = _add_dummy("GS", landing + Vector3(-(radius + 3.0), 0.0, 0.0))
	# In gerader Linie hinter dem Einschlag: Eine Kugel träfe ihn, die Granate fällt vorher.
	var straight: Dummy = _add_dummy("GF", Vector3(0.0, 0.0, landing.z - radius - 6.0))
	await _settle()
	_reset_records()
	_check(_weapons.try_fire(), "Der Knalleffekt schießt.")
	_check(_count("weapon_fired") == 1 and state.mag == magazine - 1, "Ein Schuss, eine Granate aus dem Magazin.")
	_check(_grenade_count() == 1, "Nach dem Schuss fliegt eine Granate, waren %d." % _grenade_count())
	_check(_count("explosion") == 0 and near.hits.is_empty(), "Die Granate ist unterwegs: noch keine Explosion.")
	var steps: int = await _until_explosions(1)
	_check(_count("explosion") == 1, "Die Granate explodiert am Boden.")
	if _count("explosion") == 1:
		var at: Vector3 = _last("explosion")[0]
		_check(is_equal_approx(_last("explosion")[1], radius), "Events.explosion nennt den Radius der Waffe.")
		_check(at.y < 0.3 and at.y > -0.01, "Die Explosion liegt am Boden, Höhe war %s." % at.y)
		# Die Streuung (0,5 Grad) verschiebt den Einschlag um höchstens etwa 0,4 m.
		_check(Vector2(at.x - landing.x, at.z - landing.z).length() < 0.7,
			"Wurfparabel: Einschlag bei %s erwartet, war %s." % [landing, at])
		_check(absf(float(steps) / 60.0 - fall_time) < 0.08, "Flugzeit etwa %s s, waren %s s." % [fall_time, float(steps) / 60.0])
	_check(near.hits.size() == 1 and near.hits[0]["info"].get("source") == "explosion" and is_equal_approx(near.hits[0]["amount"], blast),
		"Der Zombie neben dem Einschlag nimmt den Explosionsschaden (%s). War %s." % [blast, near.hits])
	if near.hits.size() == 1:
		var info: Dictionary = near.hits[0]["info"]
		_check(info.get("weapon_uid") == uid and info.get("weapon") == id and info.get("weapon_id") == id and info.get("hand") == 0
			and info.get("extra") == false and info.get("crit") == false, "Die Info der Explosion nennt Waffe, uid und Hand. War %s." % [info])
	_check(side.hits.is_empty(), "Außerhalb des Radius passiert nichts.")
	_check(straight.hits.is_empty(), "Die Granate fliegt im Bogen: Der Zombie in gerader Linie dahinter bleibt verschont.")
	_check(_count("bullet_hit") == 0, "Ohne Direkttreffer gibt es kein bullet_hit.")
	await _settle()
	_check(_grenade_count() == 0, "Nach der Explosion ist die Granate weg (sie prallt nicht ab).")
	await _wait(0.4)
	_check(_count("explosion") == 1, "Eine Granate, eine Explosion.")
	# Schräg nach oben geworfen fliegt sie weiter: Wurfweite aus Winkel, Tempo und Schwerkraft.
	var elevation: float = deg_to_rad(30.0)
	_player.look_at_point(eye + Vector3(0.0, sin(elevation), -cos(elevation)) * 10.0)
	var rise: float = speed * sin(elevation)
	var long_time: float = (rise + sqrt(rise * rise + 2.0 * gravity * eye.y)) / gravity
	var long_range: float = speed * cos(elevation) * long_time
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	steps = await _until_explosions(1)
	_check(_count("explosion") == 1 and long_range > speed * fall_time + 5.0, "Auch die hoch geworfene Granate explodiert.")
	if _count("explosion") == 1:
		var far_at: Vector3 = _last("explosion")[0]
		_check(absf(-far_at.z - long_range) < 1.2 and absf(far_at.x) < 0.8,
			"30 Grad nach oben: Wurfweite %s m erwartet, war %s m." % [long_range, -far_at.z])
		_check(absf(float(steps) / 60.0 - long_time) < 0.1, "Flugzeit etwa %s s, waren %s s." % [long_time, float(steps) / 60.0])
	await _clear_dummies()
	# Direkttreffer: Kugelschaden am getroffenen Zombie, Explosion an den anderen.
	var direct: Dummy = _add_dummy("GD", Vector3(0.0, 0.0, -5.0))
	var beside: Dummy = _add_dummy("GB", Vector3(2.0, 0.0, -5.0))
	var corpse: Dummy = _add_dummy("GC", Vector3(0.0, 0.0, -3.0))
	corpse.is_dead = true
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.4, -5.0))
	_weapons.refill_ammo(id)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(_journal == ["weapon_fired"], "Beim Schuss selbst trifft noch nichts, war %s." % [_journal])
	await _until_explosions(1)
	_check(corpse.hits.is_empty(), "Die Granate fliegt durch einen toten Zombie hindurch.")
	_check(direct.hits.size() == 1 and direct.hits[0]["info"].get("source") == "bullet" and is_equal_approx(direct.hits[0]["amount"], direct_damage),
		"Direkttreffer: %s Kugelschaden und kein Explosionsschaden dazu. War %s." % [direct_damage, direct.hits])
	if direct.hits.size() == 1:
		var direct_info: Dictionary = direct.hits[0]["info"]
		_check(direct_info.get("weapon_uid") == uid and direct_info.get("weapon") == id and direct_info.get("mode") == WeaponDefs.MODE_GRENADE
			and direct_info.get("hand") == 0 and direct_info.get("extra") == false and direct_info.get("crit") == false and direct_info.get("scored") == true,
			"Die Info des Direkttreffers nennt Waffe, uid, Hand und die Schussart. War %s." % [direct_info])
	_check(_count("bullet_hit") == 1 and _last("bullet_hit")[0] == direct, "Der Direkttreffer sendet bullet_hit.")
	_check(beside.hits.size() == 1 and beside.hits[0]["info"].get("source") == "explosion" and is_equal_approx(beside.hits[0]["amount"], blast),
		"Der Nachbar nimmt den Explosionsschaden. War %s." % [beside.hits])
	_check(_journal == ["weapon_fired", "damage:GD", "bullet_hit:GD", "damage:GB"], "Reihenfolge: Schuss, später Direkttreffer und Explosion. War %s." % [_journal])
	# Der Schadensfaktor der Waffe gilt für Treffer und Explosion.
	_game.upgrades.set_derived({}, [] as Array[String], {"damage": 0.2})
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	await _until_explosions(1)
	_check(direct.hits.size() == 1 and is_equal_approx(direct.hits[0]["amount"], direct_damage * 1.2)
		and beside.hits.size() == 1 and is_equal_approx(beside.hits[0]["amount"], blast * 1.2),
		"Schaden +20 %%: %s direkt und %s aus der Explosion." % [direct_damage * 1.2, blast * 1.2])
	_game.upgrades.set_derived({}, [] as Array[String], {})
	await _clear_dummies()
	# An der Wand: Die Granate explodiert dort, die Wand schirmt ab, was dahinter steht.
	var wall: StaticBody3D = _add_block("GWall", Vector3(0.0, 2.0, -4.0), Vector3(8.0, 4.0, 0.2))
	var front: Dummy = _add_dummy("GV", Vector3(1.6, 0.0, -3.0))
	var hidden: Dummy = _add_dummy("GH", Vector3(0.0, 0.0, -5.0))
	await _place_player(Vector3.ZERO)
	_weapons.refill_ammo(id)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	await _until_explosions(1)
	_check(_count("explosion") == 1, "Die Granate explodiert an der Wand.")
	if _count("explosion") == 1:
		var wall_at: Vector3 = _last("explosion")[0]
		_check(absf(wall_at.z + 3.9) < 0.3 and wall_at.y > 1.0, "Die Explosion liegt an der Wand, war %s." % wall_at)
	_check(front.hits.size() == 1 and front.hits[0]["info"].get("source") == "explosion", "Der Zombie vor der Wand wird getroffen.")
	_check(hidden.hits.is_empty(), "Der Zombie hinter der Wand bleibt verschont.")
	await _wait(0.4)
	_check(_count("explosion") == 1 and _grenade_count() == 0, "Die Granate prallt nicht ab: eine Explosion, dann ist sie weg.")
	# Zugabe: eine zweite Granate, die keine Munition kostet.
	_game.upgrades.add_levels("extra_shot", 1)
	_weapons.refill_ammo(id)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(_grenade_count() == 2 and state.mag == magazine - 1, "Mit Zugabe fliegen zwei Granaten für eine aus dem Magazin, waren %d." % _grenade_count())
	await _until_explosions(2)
	_check(_count("explosion") == 2 and front.hits.size() == 2, "Beide Granaten explodieren, Explosionen: %d." % _count("explosion"))
	_check(_flagged(front, "extra").size() == 1, "Die Explosion der Zusatzgranate trägt extra = true.")
	# Ein neuer Lauf: Was noch fliegt, verschwindet ohne Wirkung.
	wall.queue_free()
	await _clear_dummies()
	_weapons.refill_ammo(id)
	_ready_weapon()
	_weapons.try_fire()
	_reset_records()
	_game.start_run(11)
	await _wait(0.8)
	_check(_count("explosion") == 0 and _grenade_count() == 0, "Ein neuer Lauf räumt fliegende Granaten weg, ohne Explosion.")
	await _settle()


## Flamme (Heiße Phase): Jeder Stoß trifft alle Zombies im Kegel und setzt sie in Brand.
func _test_flame() -> void:
	var id: String = "flamethrower"
	var reach: float = WeaponDefs.reach(id)
	var cone: float = WeaponDefs.cone_deg(id)
	var damage: float = WeaponDefs.bullet_damage(id, false)
	var body: float = Balance.ZOMBIE_RADIUS
	_check(WeaponDefs.mode(id) == WeaponDefs.MODE_FLAME and reach > 3.0 and reach < Balance.WEAPON_RANGE and cone > 0.0
		and WeaponDefs.burn_dps(id) > 0.0 and WeaponDefs.burn_time(id) > 0.0, "Aufbau: Die Heiße Phase hat Kegel, Reichweite und Brand.")
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon(id)
	var uid: int = int(_weapons.get_hands()[0]["uid"])
	var state: WeaponState = _weapons.get_state(id)
	var magazine: int = WeaponDefs.magazine_size(id)
	var near: Dummy = _add_dummy("FN", Vector3(0.0, 0.0, -3.0))
	# Schräg im Kegel (60 % des halben Winkels) und am Ende der Flamme.
	var inside_x: float = 6.0 * tan(deg_to_rad(cone * 0.6))
	var inside: Dummy = _add_dummy("FI", Vector3(inside_x, 0.0, -6.0))
	var edge: Dummy = _add_dummy("FE", Vector3(0.0, 0.0, -(reach + body * 0.5)))
	# Neben dem Kegel (auch mit Körperradius) und hinter dem Ende der Flamme.
	var outside: Dummy = _add_dummy("FO", Vector3(-(5.0 * tan(deg_to_rad(cone)) + body + 0.8), 0.0, -5.0))
	var beyond: Dummy = _add_dummy("FB", Vector3(1.0, 0.0, -(reach + body + 1.0)))
	var behind: Dummy = _add_dummy("FH", Vector3(0.0, 0.0, 2.0))
	var burning: Array[Dummy] = [near, inside, edge]
	for dummy: Dummy in _dummies:
		dummy.events = _events
	await _settle()
	_reset_records()
	var points_before: int = _game.points
	_check(_weapons.try_fire(), "Die Heiße Phase gibt einen Stoß.")
	for dummy: Dummy in burning:
		_check(dummy.hits.size() == 1 and is_equal_approx(dummy.hits[0]["amount"], damage), "%s steht im Kegel und nimmt %s Schaden. War %s." % [dummy.name, damage, dummy.hits])
		_check(dummy.burns == [[WeaponDefs.burn_dps(id), WeaponDefs.burn_time(id)]],
			"%s brennt mit den festen Werten der Waffe (%s je Sekunde für %s s). War %s." % [dummy.name, WeaponDefs.burn_dps(id), WeaponDefs.burn_time(id), dummy.burns])
	for dummy: Dummy in [outside, beyond, behind] as Array[Dummy]:
		_check(dummy.hits.is_empty() and dummy.burns.is_empty(), "%s steht nicht im Kegel und bleibt verschont." % dummy.name)
	_check(_journal == ["damage:FN", "bullet_hit:FN", "damage:FI", "bullet_hit:FI", "damage:FE", "bullet_hit:FE", "weapon_fired"],
		"Ein Stoß trifft von nah nach fern, je Zombie Schaden und bullet_hit, dann weapon_fired. War %s." % [_journal])
	_check(_count("weapon_fired") == 1 and state.mag == magazine - 1, "Ein Stoß kostet eine Ladung, egal wie viele brennen.")
	# Jeder Treffer meldet sich wie eine Kugel: bullet_hit mit source "bullet" und weapon_uid.
	_check(_count("bullet_hit") == 3, "Jeder Zombie im Kegel sendet bullet_hit, waren %d." % _count("bullet_hit"))
	for args: Array in _received.get("bullet_hit", []):
		var hit_info: Dictionary = args[2]
		_check(hit_info.get("source") == "bullet" and hit_info.get("weapon_uid") == uid and hit_info.get("weapon") == id and hit_info.get("weapon_id") == id
			and hit_info.get("hand") == 0 and hit_info.get("extra") == false and hit_info.get("crit") == false and hit_info.get("headshot") == false
			and hit_info.get("mode") == WeaponDefs.MODE_FLAME and hit_info.has("hit_position") and is_equal_approx(args[1], damage),
			"bullet_hit der Flamme trägt die Schlüssel eines Kugeltreffers. War %s." % [hit_info])
	# Treffer-Punkte: nur der erste Zombie je Stoß zählt als Kugeltreffer.
	_check(near.hits[0]["info"].get("source") == "bullet" and near.hits[0]["info"].get("scored") == true,
		"Der erste Zombie des Stoßes ist der Punkte-Treffer (source bullet).")
	_check(inside.hits[0]["info"].get("source") == WeaponDefs.MODE_FLAME and inside.hits[0]["info"].get("scored") == false
		and edge.hits[0]["info"].get("source") == WeaponDefs.MODE_FLAME, "Die weiteren Zombies nehmen den Schaden mit source flame (ohne Treffer-Punkte).")
	_check(_game.points - points_before == Balance.POINTS_BULLET_HIT,
		"Ein Stoß durch drei Zombies gibt einmal Treffer-Punkte (%d), waren %d." % [Balance.POINTS_BULLET_HIT, _game.points - points_before])
	# Sichtbare Flamme von der Mündung bis zum Ende des Kegels.
	var flame: Node3D = _weapons.get_stream(0)
	_check(flame != null and flame.is_inside_tree() and bool(flame.call("is_active")), "Nach dem Stoß brennt eine sichtbare Flamme.")
	if flame != null:
		var particles: CPUParticles3D = flame.get_node_or_null("Particles") as CPUParticles3D
		_check(particles != null and particles.emitting and particles.visible, "Die Flamme stößt Partikel aus.")
		_check(is_equal_approx(particles.spread, cone), "Die Flamme öffnet sich so weit wie der Kegel.")
		var view_model: Node3D = _player.get_node("Camera/ViewModel")
		_check((flame.call("get_from") as Vector3).distance_to(view_model.get_muzzle_position(0)) < 0.02, "Die Flamme beginnt an der Mündung.")
		var flame_end: Vector3 = _player.get_eye_position() + _player.get_aim_direction() * reach
		_check((flame.call("get_to") as Vector3).distance_to(flame_end) < 0.05, "Die Flamme reicht bis zum Ende des Kegels, war %s." % [flame.call("get_to")])
		_step(0.5)
		_check(not bool(flame.call("is_active")) and not particles.emitting, "Ohne weiteren Stoß geht die Flamme aus.")
	# Dauerfeuer: 15 Stöße je Sekunde, Treffer-Punkte höchstens wie bei einer Automatikwaffe.
	var pulses: int = await _burst(id, 60, 1.0 / 60.0)
	var rate: float = float(WeaponDefs.get_def(id)["fire_rate"])
	_check(absi(pulses - _burst_shots(rate, 60, 1.0 / 60.0)) <= 1, "Dauerfeuer: %d Stöße in 1 s erwartet, waren %d." % [_burst_shots(rate, 60, 1.0 / 60.0), pulses])
	_check(near.hits.size() == pulses and inside.hits.size() == pulses and state.mag == magazine - pulses, "Jeder Stoß trifft jeden Zombie im Kegel und kostet eine Ladung.")
	_check(_hits_from(near, "bullet").size() == pulses and _hits_from(inside, "bullet").is_empty() and _hits_from(edge, "bullet").is_empty(),
		"Je Stoß genau ein Punkte-Treffer.")
	_check(_burst_points == pulses * Balance.POINTS_BULLET_HIT,
		"Eine Sekunde Flamme durch drei Zombies: %d Treffer-Punkte, waren %d." % [pulses * Balance.POINTS_BULLET_HIT, _burst_points])
	_check(float(pulses) <= _max_auto_rate() + 1.0, "Das sind nicht mehr Punkte-Treffer je Sekunde als bei der schnellsten Automatikwaffe (%s)." % _max_auto_rate())
	# Eine Wand verdeckt: Sichtlinie nicht durch Wände.
	var wall: StaticBody3D = _add_block("FWall", Vector3(inside_x, 1.5, -4.5), Vector3(1.0, 3.0, 0.2))
	await _settle()
	_weapons.refill_ammo(id)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(inside.hits.is_empty() and inside.burns.is_empty(), "Hinter einer Wand trifft die Flamme nicht.")
	_check(near.hits.size() == 1 and edge.hits.size() == 1, "Die Zombies mit freier Sicht brennen weiter.")
	wall.queue_free()
	# Eine Wand in Blickrichtung: Die sichtbare Flamme endet dort.
	var stop: StaticBody3D = _add_block("FStop", Vector3(0.0, 1.5, -4.0), Vector3(1.0, 3.0, 0.2))
	await _settle()
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(near.hits.size() == 1 and edge.hits.is_empty(), "Die Wand in Blickrichtung schützt, was dahinter steht.")
	if flame != null:
		_check(absf((flame.call("get_to") as Vector3).z + 3.9) < 0.05, "Die sichtbare Flamme endet an der Wand, war %s." % [flame.call("get_to")])
	stop.queue_free()
	# Tote Zombies brennen nicht, der Schadensfaktor der Waffe gilt.
	await _settle()
	near.is_dead = true
	_game.upgrades.set_derived({}, [] as Array[String], {"damage": 0.2})
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(near.hits.is_empty() and inside.hits.size() == 1 and is_equal_approx(inside.hits[0]["amount"], damage * 1.2),
		"Tote nimmt die Flamme aus, Schaden +20 %% gilt (%s)." % (damage * 1.2))
	_check(inside.hits.size() == 1 and inside.hits[0]["info"].get("source") == "bullet", "Ohne den Toten ist der nächste Zombie der Punkte-Treffer.")
	near.is_dead = false
	_game.upgrades.set_derived({}, [] as Array[String], {})
	# Zugabe: ein zweiter Stoß mit dem Anteil der Zugabe, weiter nur ein Punkte-Treffer.
	_game.upgrades.add_levels("extra_shot", 1)
	var share: float = _game.bullet_value(uid, "extra_shot", "damage_factor")
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(near.hits.size() == 2 and is_equal_approx(near.hits[1]["amount"], damage * share) and near.hits[1]["info"].get("extra") == true,
		"Zugabe: ein zweiter Stoß mit %s Schaden und extra = true. War %s." % [damage * share, near.hits])
	_check(_hits_from(near, "bullet").size() + _hits_from(inside, "bullet").size() + _hits_from(edge, "bullet").size() == 1,
		"Auch mit Zugabe gibt ein Schuss nur einen Punkte-Treffer.")
	# Mit einer anderen Waffe verschwindet die Flamme ganz.
	_weapons.give_weapon("pistol")
	await _frames(3)
	_check(not is_instance_valid(flame) and _weapons.get_stream(0) == null, "Ohne die Waffe gibt es keine Flamme mehr.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Strahl (Rotlicht): Jeder Treffer geht durch alle Zombies in der Linie bis zur Wand.
func _test_beam() -> void:
	var id: String = "beam"
	var damage: float = WeaponDefs.bullet_damage(id, false)
	var count: int = 20
	_check(WeaponDefs.mode(id) == WeaponDefs.MODE_BEAM and WeaponDefs.pierce(id) == WeaponDefs.PIERCE_ALL, "Aufbau: Das Rotlicht ist ein Strahl durch alle Zombies.")
	var line: Array[Dummy] = []
	for i: int in count:
		line.append(_add_dummy("B%d" % i, Vector3(0.0, 0.0, -3.0 - float(i))))
	for dummy: Dummy in line:
		dummy.events = _events
	var back_wall: StaticBody3D = _add_block("BWall", Vector3(0.0, 2.0, -30.0), Vector3(8.0, 4.0, 0.2))
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon(id)
	var uid: int = int(_weapons.get_hands()[0]["uid"])
	var state: WeaponState = _weapons.get_state(id)
	var magazine: int = WeaponDefs.magazine_size(id)
	await _settle()
	_reset_records()
	var tracers_before: int = _tracer_count()
	var points_before: int = _game.points
	_check(_weapons.try_fire(), "Das Rotlicht gibt einen Treffer.")
	var all_hit: bool = true
	var all_full: bool = true
	for dummy: Dummy in line:
		all_hit = all_hit and dummy.hits.size() == 1
		all_full = all_full and dummy.hits.size() == 1 and is_equal_approx(dummy.hits[0]["amount"], damage)
	_check(all_hit, "Ein Treffer geht durch alle %d Zombies in der Linie, war %s." % [count, _hit_counts(line)])
	_check(all_full, "Der Strahl verliert keinen Schaden: jeder nimmt %s." % damage)
	_check(_count("bullet_hit") == count and _count("weapon_fired") == 1 and state.mag == magazine - 1, "Jeder Zombie sendet bullet_hit, der Treffer kostet eine Ladung.")
	var all_bullet: bool = true
	for args: Array in _received.get("bullet_hit", []):
		var hit_info: Dictionary = args[2]
		all_bullet = (all_bullet and hit_info.get("source") == "bullet" and hit_info.get("weapon_uid") == uid and hit_info.get("weapon") == id
			and hit_info.get("weapon_id") == id and hit_info.get("hand") == 0 and hit_info.get("extra") == false and hit_info.get("crit") == false
			and hit_info.get("mode") == WeaponDefs.MODE_BEAM and hit_info.has("hit_position") and hit_info.has("headshot"))
	_check(all_bullet, "bullet_hit des Strahls trägt die Schlüssel eines Kugeltreffers.")
	_check(line[0].hits[0]["info"].get("source") == "bullet" and line[0].hits[0]["info"].get("scored") == true, "Der erste Zombie ist der Punkte-Treffer.")
	var others_beam: bool = true
	for i: int in range(1, count):
		others_beam = others_beam and line[i].hits[0]["info"].get("source") == WeaponDefs.MODE_BEAM and line[i].hits[0]["info"].get("scored") == false
	_check(others_beam, "Alle weiteren nehmen den Schaden mit source beam (ohne Treffer-Punkte).")
	_check(_game.points - points_before == Balance.POINTS_BULLET_HIT,
		"Ein Treffer durch %d Zombies gibt einmal Treffer-Punkte, waren %d." % [count, _game.points - points_before])
	_check(_tracer_count() == tracers_before, "Der Strahl hat keine Leuchtspur je Treffer.")
	# Sichtbarer Dauerstrahl von der Mündung bis zur Wand.
	var beam: Node3D = _weapons.get_stream(0)
	var view_model: Node3D = _player.get_node("Camera/ViewModel")
	_check(beam != null and beam.is_inside_tree() and beam.visible and bool(beam.call("is_active")), "Solange gefeuert wird, steht ein sichtbarer Strahl.")
	if beam != null:
		_check((beam.call("get_from") as Vector3).distance_to(view_model.get_muzzle_position(0)) < 0.02, "Der Strahl beginnt an der Mündung.")
		var beam_end: Vector3 = beam.call("get_to")
		_check(absf(beam_end.z + 29.9) < 0.05 and absf(beam_end.x) < 0.05, "Der Strahl endet an der Wand, war %s." % beam_end)
		_check((beam.get_node("Glow") as MeshInstance3D).visible and (beam.get_node("Core") as MeshInstance3D).visible, "Mantel und Kern des Strahls sind zu sehen.")
		# Zwischen zwei Treffern folgt der Strahl dem Blick.
		_player.look_at_point(_player.get_eye_position() + Vector3(4.0, 0.0, -10.0))
		_weapons.call("_process", 0.01)
		var turned: Vector3 = ((beam.call("get_to") as Vector3) - _player.get_eye_position()).normalized()
		_check(bool(beam.call("is_active")) and turned.dot(_player.get_aim_direction()) > 0.9999, "Der Strahl folgt dem Blick.")
		_step(0.5)
		_check(not bool(beam.call("is_active")) and not beam.visible, "Ohne weiteren Treffer geht der Strahl aus.")
	_player.look_at_point(_player.get_eye_position() + Vector3(0.0, 0.0, -10.0))
	# Dauerfeuer: 20 Treffer je Sekunde, je Treffer ein Punkte-Treffer.
	var pulses: int = await _burst(id, 60, 1.0 / 60.0)
	var rate: float = float(WeaponDefs.get_def(id)["fire_rate"])
	_check(absi(pulses - _burst_shots(rate, 60, 1.0 / 60.0)) <= 1, "Dauerfeuer: %d Treffer in 1 s erwartet, waren %d." % [_burst_shots(rate, 60, 1.0 / 60.0), pulses])
	_check(line[0].hits.size() == pulses and line[count - 1].hits.size() == pulses and state.mag == magazine - pulses, "Jeder Treffer geht durch die ganze Linie.")
	_check(_burst_points == pulses * Balance.POINTS_BULLET_HIT,
		"Eine Sekunde Strahl durch %d Zombies: %d Treffer-Punkte, waren %d." % [count, pulses * Balance.POINTS_BULLET_HIT, _burst_points])
	_check(float(pulses) <= _max_auto_rate() + 1.0, "Das sind nicht mehr Punkte-Treffer je Sekunde als bei der schnellsten Automatikwaffe (%s)." % _max_auto_rate())
	# Eine Wand hält den Strahl auf.
	var wall: StaticBody3D = _add_block("BStop", Vector3(0.0, 2.0, -5.5), Vector3(4.0, 4.0, 0.1))
	await _settle()
	_weapons.refill_ammo(id)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	var expected: Array = []
	for i: int in count:
		expected.append(1 if i < 3 else 0)
	_check(_hit_counts(line) == expected, "Eine Wand hält den Strahl auf: nur die drei davor, war %s." % [_hit_counts(line)])
	if beam != null:
		_check(absf((beam.call("get_to") as Vector3).z + 5.45) < 0.05, "Der sichtbare Strahl endet an der Wand, war %s." % [beam.call("get_to")])
	wall.queue_free()
	await _settle()
	# Kopftreffer und tote Zombies: Der Strahl ist eine Linie wie eine Kugel.
	line[0].is_dead = true
	_player.look_at_point(Vector3(0.0, 2.75, -3.7))
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(line[0].hits.is_empty(), "Durch einen toten Zombie geht der Strahl hindurch.")
	_check(line[1].hits.size() == 1 and line[1].hits[0]["info"].get("headshot") == true
		and is_equal_approx(line[1].hits[0]["amount"], WeaponDefs.bullet_damage(id, true)),
		"Ein Strahl durch den Kopf zählt als Kopftreffer (%s). War %s." % [WeaponDefs.bullet_damage(id, true), line[1].hits])
	_check(line[1].hits.size() == 1 and line[1].hits[0]["info"].get("source") == "bullet", "Ohne den Toten ist der nächste Zombie der Punkte-Treffer.")
	line[0].is_dead = false
	back_wall.queue_free()
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Eröffnungsgag (opener): Der Schuss aus dem vollen Magazin macht mehr Schaden.
func _test_opener() -> void:
	var target: Dummy = _add_dummy("O", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_game.upgrades.add_levels("opener", 1)
	var pistol: WeaponState = _weapons.get_state("pistol")
	var uid: int = int(_weapons.get_hands()[0]["uid"])
	var bonus: float = _game.bullet_value(uid, "opener", "bonus")
	var base: float = WeaponDefs.bullet_damage("pistol", false)
	_check(bonus > 0.0 and pistol.mag == pistol.magazine_size(), "Aufbau: Eröffnungsgag wirkt, das Magazin ist voll.")
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], base * (1.0 + bonus)) and target.hits[0]["info"].get("opener") == true,
		"Die erste Kugel des Magazins macht %s Schaden und trägt opener = true. War %s." % [base * (1.0 + bonus), target.hits])
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], base) and target.hits[0]["info"].get("opener") == false,
		"Die zweite Kugel macht den normalen Schaden (%s). War %s." % [base, target.hits])
	# Nach dem Nachladen ist die nächste Kugel wieder die erste.
	_weapons.start_reload()
	pistol.reload_left = 0.02
	await _wait(0.1)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(pistol.mag == pistol.magazine_size() - 1 and target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], base * (1.0 + bonus)),
		"Nach dem Nachladen ist die nächste Kugel wieder stärker.")
	# Schrot: Der erste Schuss zählt, also alle seine Schrotkugeln.
	_weapons.give_weapon("shotgun")
	_game.upgrades.add_levels("opener", 2)
	var shotgun_uid: int = int(_weapons.get_hands()[0]["uid"])
	var shotgun_bonus: float = _game.bullet_value(shotgun_uid, "opener", "bonus")
	var pellets: int = int(WeaponDefs.get_def("shotgun")["pellets"])
	var pellet: float = WeaponDefs.bullet_damage("shotgun", false)
	_check(shotgun_bonus > bonus, "Aufbau: Die bessere Rarität gibt mehr Zuschlag.")
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == pellets and is_equal_approx(target.total_damage(), float(pellets) * pellet * (1.0 + shotgun_bonus)),
		"Schrot: Alle %d Schrotkugeln des ersten Schusses sind stärker, Schaden war %s." % [pellets, target.total_damage()])
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == pellets and is_equal_approx(target.total_damage(), float(pellets) * pellet), "Schrot: Der zweite Schuss ist normal.")
	# Salve: Nur die erste Kugel der ersten Salve zählt.
	_weapons.give_weapon("burst_pistol")
	_game.upgrades.add_levels("opener", 1)
	var burst_base: float = WeaponDefs.bullet_damage("burst_pistol", false)
	_reset_records()
	_weapons.try_fire()
	_step(WeaponDefs.burst_interval("burst_pistol") * 4.0)
	_check(target.hits.size() == 3 and is_equal_approx(target.hits[0]["amount"], burst_base * (1.0 + bonus))
		and is_equal_approx(target.hits[1]["amount"], burst_base) and is_equal_approx(target.hits[2]["amount"], burst_base),
		"Salve: nur die erste Kugel ist stärker. War %s." % [target.hits])
	# Zugabe: Die Zusatzkugel des ersten Schusses rechnet mit dem stärkeren Schaden.
	_weapons.give_weapon("pistol")
	_game.upgrades.add_levels("opener", 1)
	_game.upgrades.add_levels("extra_shot", 1)
	var pistol_uid: int = int(_weapons.get_hands()[0]["uid"])
	var share: float = _game.bullet_value(pistol_uid, "extra_shot", "damage_factor")
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 2 and is_equal_approx(target.hits[1]["amount"], base * (1.0 + bonus) * share),
		"Die Zusatzkugel des ersten Schusses macht %s. War %s." % [base * (1.0 + bonus) * share, target.hits])
	await _clear_dummies()
	# Strahl: Der erste Treffer des Magazins ist stärker, für jeden Zombie in der Linie.
	var first: Dummy = _add_dummy("O1", Vector3(0.0, 0.0, -4.0))
	var second: Dummy = _add_dummy("O2", Vector3(0.0, 0.0, -6.0))
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon("beam")
	_game.upgrades.add_levels("opener", 1)
	var beam_base: float = WeaponDefs.bullet_damage("beam", false)
	_reset_records()
	_weapons.try_fire()
	_check(first.hits.size() == 1 and is_equal_approx(first.hits[0]["amount"], beam_base * (1.0 + bonus))
		and second.hits.size() == 1 and is_equal_approx(second.hits[0]["amount"], beam_base * (1.0 + bonus)),
		"Strahl: Der erste Treffer des Magazins ist für die ganze Linie stärker.")
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(first.hits.size() == 1 and is_equal_approx(first.hits[0]["amount"], beam_base), "Strahl: Der zweite Treffer ist normal.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Schlusspointe (punchline): Der Schuss, der das Magazin leert, explodiert am Einschlag.
func _test_punchline() -> void:
	var radius: float = Balance.PUNCHLINE_RADIUS
	var hit: Dummy = _add_dummy("PA", Vector3(0.0, 0.0, -6.0))
	var beside: Dummy = _add_dummy("PB", Vector3(2.0, 0.0, -6.0))
	var far: Dummy = _add_dummy("PC", Vector3(radius + 3.0, 0.0, -6.0))
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	_game.upgrades.add_levels("punchline", 1)
	var pistol: WeaponState = _weapons.get_state("pistol")
	var uid: int = int(_weapons.get_hands()[0]["uid"])
	var blast: float = _game.bullet_value(uid, "punchline", "damage") * _game.effect_factor()
	var base: float = WeaponDefs.bullet_damage("pistol", false)
	_check(blast > 0.0, "Aufbau: Die Schlusspointe hat Schaden (%s)." % blast)
	# Die vorletzte Kugel explodiert nicht.
	pistol.mag = 2
	_reset_records()
	_weapons.try_fire()
	_check(_count("explosion") == 0 and hit.hits.size() == 1 and beside.hits.is_empty(), "Die vorletzte Kugel explodiert nicht.")
	# Die letzte Kugel explodiert am Einschlag.
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(pistol.mag == 0 and _count("explosion") == 1, "Die letzte Kugel des Magazins explodiert, Explosionen: %d." % _count("explosion"))
	if _count("explosion") == 1:
		var at: Vector3 = _last("explosion")[0]
		_check(is_equal_approx(_last("explosion")[1], radius), "Events.explosion nennt den Radius der Schlusspointe (%s)." % radius)
		_check(at.distance_to(Vector3(0.0, 1.2, -5.7)) < 0.4, "Die Explosion liegt am Einschlag, war %s." % at)
	_check(hit.hits.size() == 2 and is_equal_approx(hit.hits[0]["amount"], base) and hit.hits[0]["info"].get("source") == "bullet"
		and is_equal_approx(hit.hits[1]["amount"], blast) and hit.hits[1]["info"].get("source") == "explosion",
		"Der getroffene Zombie nimmt die Kugel (%s) und die Explosion (%s). War %s." % [base, blast, hit.hits])
	_check(beside.hits.size() == 1 and is_equal_approx(beside.hits[0]["amount"], blast), "Der Nachbar nimmt die Explosion (%s). War %s." % [blast, beside.hits])
	if beside.hits.size() == 1:
		var info: Dictionary = beside.hits[0]["info"]
		_check(info.get("source") == "explosion" and info.get("punchline") == true and info.get("weapon_uid") == uid and info.get("weapon") == "pistol"
			and info.get("weapon_id") == "pistol" and info.get("hand") == 0 and info.get("extra") == false and info.get("crit") == false,
			"Die Info der Schlusspointe: source explosion, Marke punchline, Waffe, uid, Hand. War %s." % [info])
	_check(far.hits.is_empty(), "Außerhalb des Radius passiert nichts.")
	_check(_count("bullet_hit") == 1, "Die Explosion sendet kein bullet_hit.")
	_check(_journal.size() == 5 and _journal[0] == "damage:PA" and _journal[1] == "bullet_hit:PA" and _journal[4] == "weapon_fired",
		"Reihenfolge: Treffer, Explosion, weapon_fired. War %s." % [_journal])
	_check(pistol.is_reloading, "Danach wird nachgeladen.")
	# Einschlag in der Welt: Die Explosion liegt dort, kein Kugeltreffer.
	_weapons.refill_ammo("pistol")
	pistol.mag = 1
	_ready_weapon()
	_player.look_at_point(Vector3(1.0, 0.0, -5.0))
	_reset_records()
	_weapons.try_fire()
	_check(_count("explosion") == 1 and _count("bullet_hit") == 0, "Auch am Boden explodiert die letzte Kugel.")
	_check(hit.hits.size() == 1 and hit.hits[0]["info"].get("source") == "explosion" and beside.hits.size() == 1,
		"Beide Zombies neben dem Einschlag nehmen die Explosion.")
	# Eine Wand schirmt ab, ein Schuss ins Leere explodiert nicht.
	var wall: StaticBody3D = _add_block("PWall", Vector3(1.0, 1.5, -6.0), Vector3(0.2, 3.0, 3.0))
	await _settle()
	_weapons.refill_ammo("pistol")
	pistol.mag = 1
	_ready_weapon()
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	_reset_records()
	_weapons.try_fire()
	_check(hit.hits.size() == 2 and beside.hits.is_empty(), "Hinter einer Wand trifft die Schlusspointe nicht.")
	wall.queue_free()
	await _settle()
	_weapons.refill_ammo("pistol")
	pistol.mag = 1
	_ready_weapon()
	_player.look_at_point(_player.get_eye_position() + Vector3(0.0, 10.0, -1.0))
	_reset_records()
	_weapons.try_fire()
	_check(_count("explosion") == 0, "Ohne Einschlag (Schuss in den Himmel) gibt es keine Explosion.")
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	# Höhere Rarität: mehr Schaden.
	_game.upgrades.add_levels("punchline", 2)
	var strong: float = _game.bullet_value(uid, "punchline", "damage") * _game.effect_factor()
	_weapons.refill_ammo("pistol")
	pistol.mag = 1
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(strong > blast and beside.hits.size() == 1 and is_equal_approx(beside.hits[0]["amount"], strong), "Seltene Schlusspointe: %s Schaden, war %s." % [strong, beside.hits])
	await _clear_dummies()
	# Schrot: Der letzte Schuss explodiert einmal, nicht je Schrotkugel.
	var wide: Dummy = _add_dummy("PW", Vector3(0.0, 0.0, -4.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon("shotgun")
	_game.upgrades.add_levels("punchline", 1)
	var shotgun: WeaponState = _weapons.get_state("shotgun")
	var pellets: int = int(WeaponDefs.get_def("shotgun")["pellets"])
	shotgun.mag = 1
	_reset_records()
	_weapons.try_fire()
	_check(_count("explosion") == 1 and _hits_from(wide, "bullet").size() == pellets and _hits_from(wide, "explosion").size() == 1,
		"Schrot: %d Schrotkugeln, eine Explosion. Explosionen: %d." % [pellets, _count("explosion")])
	# Salve: Nur die letzte Kugel des Magazins explodiert.
	_weapons.give_weapon("burst_pistol")
	_game.upgrades.add_levels("punchline", 1)
	var burst: WeaponState = _weapons.get_state("burst_pistol")
	burst.mag = 3
	_reset_records()
	_weapons.try_fire()
	_check(_count("explosion") == 0, "Salve: Die erste von drei Kugeln explodiert nicht.")
	_step(WeaponDefs.burst_interval("burst_pistol") * 1.1)
	_check(_count("weapon_fired") == 2 and _count("explosion") == 0, "Salve: Die zweite auch nicht.")
	_step(WeaponDefs.burst_interval("burst_pistol") * 2.0)
	_check(_count("weapon_fired") == 3 and _count("explosion") == 1 and burst.mag == 0, "Salve: Die dritte leert das Magazin und explodiert.")
	# Strahl: Der letzte Treffer explodiert am ersten Zombie. Zusammen mit dem Eröffnungsgag auf
	# einer Waffe mit einem Schuss je Magazin gilt beides für jeden Schuss.
	_weapons.give_weapon("crossbow")
	_game.upgrades.add_levels("punchline", 1)
	_game.upgrades.add_levels("opener", 1)
	var bolt_uid: int = int(_weapons.get_hands()[0]["uid"])
	var bolt: float = WeaponDefs.bullet_damage("crossbow", false) * (1.0 + _game.bullet_value(bolt_uid, "opener", "bonus"))
	_reset_records()
	_weapons.try_fire()
	_check(_count("explosion") == 1 and _hits_from(wide, "bullet").size() == 1 and is_equal_approx(_hits_from(wide, "bullet")[0]["amount"], bolt),
		"Zielgerade: Der eine Bolzen ist erster und letzter Schuss zugleich (stärker und Explosion).")
	# Granate: Die letzte Granate des Magazins bringt die Schlusspointe mit an ihren Einschlag.
	_weapons.give_weapon("grenade_launcher")
	_game.upgrades.add_levels("punchline", 1)
	var launcher_uid: int = int(_weapons.get_hands()[0]["uid"])
	_weapons.get_state("grenade_launcher").mag = 1
	_reset_records()
	_weapons.try_fire()
	_check(_count("explosion") == 0, "Granate: Die Schlusspointe wartet auf den Einschlag.")
	await _until_explosions(2)
	var pointe: Array[Dictionary] = _hits_from(wide, "explosion")
	_check(_count("explosion") == 2 and _hits_from(wide, "bullet").size() == 1 and pointe.size() == 1,
		"Granate: Direkttreffer, eigene Explosion und Schlusspointe am Einschlag. Explosionen: %d, Treffer: %s." % [_count("explosion"), wide.hits])
	if pointe.size() == 1:
		_check(pointe[0]["info"].get("punchline") == true and pointe[0]["info"].get("weapon_uid") == launcher_uid
			and is_equal_approx(pointe[0]["amount"], _game.bullet_value(launcher_uid, "punchline", "damage") * _game.effect_factor()),
			"Granate: Den direkt Getroffenen trifft nur die Schlusspointe als Explosion. War %s." % [pointe[0]])
	await _clear_dummies()
	var first: Dummy = _add_dummy("P1", Vector3(0.0, 0.0, -4.0))
	var second: Dummy = _add_dummy("P2", Vector3(0.0, 0.0, -6.0))
	await _place_player(Vector3.ZERO)
	_weapons.give_weapon("beam")
	_game.upgrades.add_levels("punchline", 1)
	_weapons.get_state("beam").mag = 1
	_reset_records()
	_weapons.try_fire()
	_check(_count("explosion") == 1 and (_last("explosion")[0] as Vector3).distance_to(Vector3(0.0, 1.6, -3.7)) < 0.4,
		"Strahl: Der letzte Treffer explodiert einmal am ersten Zombie, war %s." % [_received.get("explosion", [])])
	_check(_hits_from(first, "explosion").size() == 1 and _hits_from(second, "explosion").size() == 1, "Beide Zombies im Radius nehmen die Explosion.")
	# Flamme ohne Zombie im Kegel: Die Schlusspointe zündet am Ende der Flamme.
	first.position = Vector3(0.0, 0.0, 12.0)
	second.position = Vector3(1.0, 0.0, -WeaponDefs.reach("flamethrower") - 1.5)
	await _settle()
	_weapons.give_weapon("flamethrower")
	_game.upgrades.add_levels("punchline", 1)
	_weapons.get_state("flamethrower").mag = 1
	_reset_records()
	_weapons.try_fire()
	_check(_count("explosion") == 1 and absf((_last("explosion")[0] as Vector3).z + WeaponDefs.reach("flamethrower")) < 0.3,
		"Flamme ohne Treffer: Explosion am Ende der Flamme, war %s." % [_received.get("explosion", [])])
	_check(_hits_from(second, "explosion").size() == 1 and _hits_from(second, "bullet").is_empty(), "Der Zombie hinter dem Flammenende nimmt nur die Explosion.")
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Eröffnungsgag und Schlusspointe mit dem echten Rucksack: Sie gelten nur für die Waffe auf
## ihren Sternen.
func _test_magazine_items_per_hand() -> void:
	var uids: Array[int] = _pack_weapons([["pistol", Vector2i(1, 1)], ["pistol", Vector2i(3, 3)]])
	var left_uid: int = uids[0]
	var right_uid: int = uids[1]
	_attach("opener", 1, [left_uid] as Array[int])
	_attach("punchline", 1, [right_uid] as Array[int])
	_game.sync_build()
	var target: Dummy = _add_dummy("M", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	var left: WeaponState = _weapons.get_state_of(left_uid)
	var right: WeaponState = _weapons.get_state_of(right_uid)
	_check(left != null and right != null, "Aufbau: beide Pistolen sind in der Hand.")
	if left == null or right == null:
		await _clear_dummies()
		return
	var bonus: float = _game.bullet_value(left_uid, "opener", "bonus")
	var base: float = WeaponDefs.bullet_damage("pistol", false)
	_check(bonus > 0.0 and _game.bullet_level(right_uid, "opener") == 0 and _game.bullet_level(left_uid, "punchline") == 0
		and _game.bullet_level(right_uid, "punchline") > 0, "Aufbau: Eröffnungsgag nur links, Schlusspointe nur rechts.")
	_reset_records()
	_weapons.try_fire()
	var left_hits: Array[Dictionary] = _hits_of_hand(target, 0)
	var right_hits: Array[Dictionary] = _hits_of_hand(target, 1)
	_check(left_hits.size() == 1 and is_equal_approx(left_hits[0]["amount"], base * (1.0 + bonus)) and left_hits[0]["info"].get("opener") == true,
		"Links: Die erste Kugel ist stärker.")
	_check(right_hits.size() == 1 and is_equal_approx(right_hits[0]["amount"], base) and right_hits[0]["info"].get("opener") == false,
		"Rechts ohne Eröffnungsgag: normaler Schaden.")
	left.mag = 1
	right.mag = 1
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	var blasts: Array[Dictionary] = _hits_from(target, "explosion")
	_check(_count("explosion") == 1 and blasts.size() == 1, "Nur die rechte Pistole explodiert mit ihrer letzten Kugel, Explosionen: %d." % _count("explosion"))
	if blasts.size() == 1:
		_check(blasts[0]["info"].get("weapon_uid") == right_uid and blasts[0]["info"].get("hand") == 1
			and is_equal_approx(blasts[0]["amount"], _game.bullet_value(right_uid, "punchline", "damage") * _game.effect_factor()),
			"Die Explosion gehört zur rechten Waffe. War %s." % [blasts[0]])
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Die zehn neuen Modelle: eigene Modelle mit Rückstoß und Lage, auch in der zweiten Hand.
func _test_new_models() -> void:
	var view_model: Node3D = _player.get_node("Camera/ViewModel")
	var recoil: Dictionary = view_model.RECOIL
	var offsets: Dictionary = view_model.WEAPON_OFFSETS
	var silent: Array = view_model.NO_MUZZLE_FLASH
	var new_ids: Array[String] = ["burst_pistol", "nail_gun", "machine_pistol", "crossbow", "grenade_launcher",
		"flamethrower", "beam", "tesla", "lmg", "auto_shotgun"]
	for weapon_id: String in WeaponDefs.ORDER:
		_check(recoil.has(weapon_id) and offsets.has(weapon_id), "%s hat Einträge in RECOIL und WEAPON_OFFSETS." % weapon_id)
	for weapon_id: String in new_ids:
		_check(WeaponDefs.has(weapon_id), "Aufbau: %s ist eine Waffe." % weapon_id)
	# Jedes Modell ist anders gebaut: Die Maße seiner Teile kommen bei keiner zweiten Waffe vor.
	var signatures: Dictionary = {}
	for weapon_id: String in WeaponDefs.ORDER:
		view_model.set_weapon(weapon_id)
		var gun: Node3D = view_model.get_node("Rig/Hand0/Holder/Gun_%s" % weapon_id)
		var sizes: Array = []
		for mesh_node: Node in gun.find_children("*", "MeshInstance3D", true, false):
			sizes.append(str(((mesh_node as MeshInstance3D).mesh.get_aabb().size).snappedf(0.001)))
		sizes.sort()
		var signature: String = ",".join(sizes)
		_check(not signatures.has(signature), "%s hat ein eigenes Modell (nicht das von %s)." % [weapon_id, signatures.get(signature, "")])
		signatures[signature] = weapon_id
	# Rückstoß und Mündungsfeuer je neuer Waffe.
	for weapon_id: String in new_ids:
		view_model.set_weapon(weapon_id)
		await _frames(25)
		var holder: Node3D = view_model.get_node("Rig/Hand0/Holder")
		var muzzle: Node3D = view_model.get_muzzle_node(0)
		var rest: float = holder.position.z
		view_model.play_fire(0)
		_check(holder.position.z > rest, "%s hat Rückstoß (der Platzhalter hatte keinen)." % weapon_id)
		_check((muzzle.get_child_count() > 0) != silent.has(weapon_id), "%s: Mündungsfeuer nur bei Waffen mit Pulver, Kinder der Mündung: %d." % [weapon_id, muzzle.get_child_count()])
		await _frames(8)
	# In der zweiten Hand und gespiegelt in der linken (nur Einhand-Waffen können das).
	for weapon_id: String in new_ids:
		if ItemDefs.hands(weapon_id) != 1:
			continue
		view_model.set_loadout(["pistol", weapon_id])
		var right_gun: Node3D = view_model.get_node_or_null("Rig/Hand1/Holder/Gun_%s" % weapon_id)
		_check(right_gun != null and right_gun.visible and view_model.get_node("Rig/Hand1").visible, "%s ist in der zweiten Hand zu sehen." % weapon_id)
		if right_gun != null:
			_check(right_gun.find_children("*", "MeshInstance3D", true, false).size() >= 8 and right_gun.get_node_or_null("Muzzle") != null,
				"%s hat auch in der zweiten Hand sein ganzes Modell mit Mündung." % weapon_id)
		await _frames(25)
		_check(_muzzle_in_view(1).x > 0.01 and _muzzle_in_view(1).z < -0.05 and _muzzle_in_view(0).x < -0.01,
			"%s rechts, Pistole links: Mündungen bei %s und %s." % [weapon_id, _muzzle_in_view(1), _muzzle_in_view(0)])
		var right_holder: Node3D = view_model.get_node("Rig/Hand1/Holder")
		var right_rest: float = right_holder.position.z
		view_model.play_fire(1)
		_check(right_holder.position.z > right_rest, "%s hat auch in der zweiten Hand Rückstoß." % weapon_id)
		view_model.set_loadout([weapon_id, "pistol"])
		var left_gun: Node3D = view_model.get_node_or_null("Rig/Hand0/Holder/Gun_%s" % weapon_id)
		_check(left_gun != null and left_gun.visible and view_model.get_node("Rig/Hand0").scale.x < 0.0, "%s liegt gespiegelt in der linken Hand." % weapon_id)
		await _frames(25)
		_check(_muzzle_in_view(0).x < -0.01 and _muzzle_in_view(0).z < -0.05, "%s links: Mündung links vor der Kamera, war %s." % [weapon_id, _muzzle_in_view(0)])
	# Armbrust: Nach dem Schuss ist der Bolzen weg und die Sehne entspannt, nach dem Nachladen wieder da.
	view_model.set_weapon("crossbow")
	await _frames(3)
	var bolt: Node3D = view_model.get_node("Rig/Hand0/Holder/Gun_crossbow/Bolt")
	var drawn: Node3D = view_model.get_node("Rig/Hand0/Holder/Gun_crossbow/String")
	var loose: Node3D = view_model.get_node("Rig/Hand0/Holder/Gun_crossbow/String Loose")
	_check(bolt.visible and drawn.visible and not loose.visible, "Armbrust geladen: Bolzen und gespannte Sehne.")
	view_model.play_fire(0)
	await _frames(2)
	_check(not bolt.visible and not drawn.visible and loose.visible, "Armbrust nach dem Schuss: kein Bolzen, entspannte Sehne.")
	_events.emit_signal("hand_reload_started", 0, 0.2)
	await _wait(0.3)
	_events.emit_signal("hand_reload_finished", 0)
	await _frames(2)
	_check(bolt.visible and drawn.visible and not loose.visible, "Armbrust nach dem Nachladen: wieder geladen.")
	# Granatwerfer: Die Trommel dreht sich je Schuss eine Kammer weiter.
	view_model.set_weapon("grenade_launcher")
	await _frames(3)
	var drum: Node3D = view_model.get_node("Rig/Hand0/Holder/Gun_grenade_launcher/Drum")
	var drum_before: float = drum.rotation.z
	view_model.play_fire(0)
	await _wait(0.4)
	_check(absf(angle_difference(drum_before, drum.rotation.z)) > 1.0, "Granatwerfer: Die Trommel dreht sich je Schuss weiter.")
	# Die Waffensteuerung zeigt die neuen Waffen auch wirklich: beidhändig über den Rucksack.
	_weapons.equip(["machine_pistol", "grenade_launcher"] as Array[String])
	var held: Array[String] = _weapons.get_owned_weapon_ids()
	_check(held.size() == 2 and view_model.get_hand_ids() == held, "Beidhändig mit zwei neuen Waffen: Das ViewModel zeigt beide, war %s." % [view_model.get_hand_ids()])
	if held.size() == 2:
		_check(view_model.get_node("Rig/Hand0/Holder/Gun_%s" % held[0]).visible and view_model.get_node("Rig/Hand1/Holder/Gun_%s" % held[1]).visible,
			"Beide neuen Modelle sind zu sehen.")
	_weapons.give_weapon("pistol")


## Zugabe (extra_shot): Zusatzkugeln je Schuss, ohne Munition, mit einem Anteil am Kugelschaden.
func _test_extra_shot() -> void:
	var uids: Array[int] = _pack_weapons([["pistol", Vector2i(3, 3)]])
	var pistol_uid: int = uids[0]
	var item_uid: int = _attach("extra_shot", 1, [pistol_uid] as Array[int])
	_game.sync_build()
	var target: Dummy = _add_dummy("X", Vector3(0.0, 0.0, -6.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	var pistol: WeaponState = _weapons.get_state_of(pistol_uid)
	_check(pistol != null, "Aufbau: Die Pistole aus dem Rucksack ist in der Hand.")
	if pistol == null:
		await _clear_dummies()
		return
	_check(is_equal_approx(_game.bullet_value(pistol_uid, "extra_shot", "shots"), 1.0)
		and is_equal_approx(_game.bullet_value(pistol_uid, "extra_shot", "damage_factor"), 0.5),
		"Aufbau: Die gewöhnliche Zugabe gibt der Pistole 1 Zusatzkugel mit 50 %.")
	_reset_records()
	var tracers_before: int = _tracer_count()
	_check(_weapons.try_fire(), "Die Pistole mit Zugabe schießt.")
	_check(target.hits.size() == 2, "Ein Schuss mit Zugabe trifft zweimal, waren %d." % target.hits.size())
	if target.hits.size() == 2:
		var normal: Dictionary = target.hits[0]
		var extra: Dictionary = target.hits[1]
		_check(is_equal_approx(normal["amount"], 25.0) and normal["info"].get("extra") == false,
			"Erst die normale Kugel: 25 Schaden, extra ist false. War %s." % [normal])
		_check(is_equal_approx(extra["amount"], 12.5), "Die Zusatzkugel macht 50 %% des Kugelschadens (12,5), war %s." % extra["amount"])
		_check(extra["info"].get("extra") == true, "Die Treffer-Info der Zusatzkugel trägt extra = true.")
		_check(extra["info"].get("source") == "bullet" and extra["info"].get("weapon_uid") == pistol_uid and extra["info"].get("weapon") == "pistol"
			and extra["info"].get("weapon_id") == "pistol" and extra["info"].get("hand") == 0 and extra["info"].get("headshot") == false,
			"Die Zusatzkugel ist ein Kugeltreffer derselben Waffe und Hand. War %s." % [extra["info"]])
		_check(normal["info"].get("crit") == false and extra["info"].get("crit") == false, "Ohne Glücksrad ist kein Treffer kritisch.")
		var gap: float = (normal["info"]["hit_position"] as Vector3).distance_to(extra["info"]["hit_position"] as Vector3)
		_check(gap > 0.001 and gap < 0.3, "Die Zusatzkugel fliegt leicht versetzt, Abstand der Einschläge: %s m." % gap)
	_check(_count("bullet_hit") == 2, "Beide Kugeln senden bullet_hit, waren %d." % _count("bullet_hit"))
	if _count("bullet_hit") == 2:
		var args: Array = _last("bullet_hit")
		_check(is_equal_approx(args[1], 12.5) and (args[2] as Dictionary).get("extra") == true, "bullet_hit der Zusatzkugel trägt 12,5 Schaden und extra = true.")
	_check(_journal == ["damage:X", "bullet_hit:X", "damage:X", "bullet_hit:X", "weapon_fired"],
		"Reihenfolge: normale Kugel, Zusatzkugel, dann weapon_fired. War %s." % [_journal])
	_check(_count("weapon_fired") == 1, "Die Zusatzkugel ist kein eigener Schuss (weapon_fired einmal).")
	_check(pistol.mag == 9 and _last("hand_ammo_changed") == [0, 9, 10], "Die Zusatzkugel kostet keine Munition (9 von 10), waren %d." % pistol.mag)
	_check(_tracer_count() - tracers_before == 2, "Jede Kugel hat ihre eigene Leuchtspur, neu waren %d." % (_tracer_count() - tracers_before))
	# Legendär: Die Zusatzkugel macht den vollen Schaden.
	_game.backpack.remove(item_uid)
	item_uid = _attach("extra_shot", 5, [pistol_uid] as Array[int])
	_game.sync_build()
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 2 and is_equal_approx(target.hits[1]["amount"], 25.0) and target.hits[1]["info"].get("extra") == true,
		"Legendäre Zugabe: Die Zusatzkugel macht 100 % (25).")
	# Zwei Exemplare (Gewöhnlich und Selten): zwei Zusatzkugeln, der bessere Anteil (70 %) zählt.
	_game.backpack.remove(item_uid)
	_attach("extra_shot", 1, [pistol_uid] as Array[int])
	_attach("extra_shot", 3, [pistol_uid] as Array[int])
	_game.sync_build()
	_check(is_equal_approx(_game.bullet_value(pistol_uid, "extra_shot", "shots"), 2.0), "Aufbau: Zwei Exemplare geben 2 Zusatzkugeln.")
	var mag_before: int = pistol.mag
	_ready_weapon()
	_reset_records()
	tracers_before = _tracer_count()
	_weapons.try_fire()
	_check(target.hits.size() == 3, "Zwei Exemplare: ein Schuss, drei Treffer, waren %d." % target.hits.size())
	if target.hits.size() == 3:
		_check(is_equal_approx(target.hits[0]["amount"], 25.0) and is_equal_approx(target.hits[1]["amount"], 17.5) and is_equal_approx(target.hits[2]["amount"], 17.5),
			"Normale Kugel 25, beide Zusatzkugeln 17,5. Schaden zusammen: %s." % target.total_damage())
		_check(target.hits[0]["info"].get("extra") == false and target.hits[1]["info"].get("extra") == true and target.hits[2]["info"].get("extra") == true,
			"Nur die beiden Zusatzkugeln tragen extra = true.")
	_check(pistol.mag == mag_before - 1 and _count("weapon_fired") == 1, "Auch zwei Zusatzkugeln kosten keine Munition.")
	_check(_tracer_count() - tracers_before == 3, "Drei Kugeln, drei Leuchtspuren.")
	await _clear_dummies()
	# Rarität der Waffe und Kopftreffer gelten für die Zusatzkugel wie für die normale.
	uids = _pack_weapons([["pistol", Vector2i(3, 3), 3]])
	_attach("extra_shot", 1, [uids[0]] as Array[int])
	_game.sync_build()
	target = _add_dummy("X2", Vector3(0.0, 0.0, -6.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 2 and is_equal_approx(target.hits[0]["amount"], 37.5) and is_equal_approx(target.hits[1]["amount"], 18.75),
		"Seltene Pistole (mal 1,5): 37,5 und 18,75. Schaden zusammen: %s." % target.total_damage())
	# Kopf des 4 m hohen Zombies: ab 3,12 m.
	_player.look_at_point(Vector3(0.0, 3.56, -5.7))
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 2 and is_equal_approx(target.hits[0]["amount"], 75.0) and is_equal_approx(target.hits[1]["amount"], 37.5)
		and target.hits[1]["info"].get("headshot") == true, "Kopftreffer: 75 und 37,5. Schaden zusammen: %s." % target.total_damage())
	await _clear_dummies()
	# Schrot: eine einzelne Zusatzkugel je Schuss, nicht je Schrotkugel.
	uids = _pack_weapons([["shotgun", Vector2i(1, 3)]])
	_attach("extra_shot", 1, [uids[0]] as Array[int])
	_game.sync_build()
	target = _add_dummy("XS", Vector3(0.0, 0.0, -3.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_reset_records()
	tracers_before = _tracer_count()
	_check(_weapons.try_fire(), "Die Schrotflinte mit Zugabe schießt.")
	_check(target.hits.size() == 9, "8 Schrotkugeln und 1 Zusatzkugel treffen, waren %d." % target.hits.size())
	_check(_flagged(target, "extra").size() == 1, "Genau eine Kugel ist die Zusatzkugel, waren %d." % _flagged(target, "extra").size())
	if target.hits.size() == 9:
		_check(target.hits[8]["info"].get("extra") == true and is_equal_approx(target.hits[8]["amount"], 7.0),
			"Die Zusatzkugel kommt zuletzt und macht 50 %% einer Schrotkugel (7), war %s." % target.hits[8]["amount"])
	_check(is_equal_approx(target.total_damage(), 8.0 * 14.0 + 7.0), "Schaden zusammen 119, war %s." % target.total_damage())
	_check(_weapons.get_state_of(uids[0]).mag == 5 and _count("weapon_fired") == 1, "Der Schuss kostet eine Patrone.")
	_check(_tracer_count() - tracers_before == 9, "Neun Kugeln, neun Leuchtspuren.")
	await _clear_dummies()
	# Raketenwerfer: eine zweite Rakete mit eigener Explosion, beides mit 50 %.
	uids = _pack_weapons([["rocket_launcher", Vector2i(1, 2)]])
	_attach("extra_shot", 1, [uids[0]] as Array[int])
	_game.sync_build()
	var direct: Dummy = _add_dummy("D", Vector3(0.0, 0.0, -8.0))
	var beside: Dummy = _add_dummy("N", Vector3(2.0, 0.0, -8.0))
	var far: Dummy = _add_dummy("F", Vector3(6.5, 0.0, -8.0))
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -8.0))
	var launcher: WeaponState = _weapons.get_state_of(uids[0])
	_reset_records()
	_check(_weapons.try_fire(), "Der Raketenwerfer mit Zugabe schießt.")
	_check(direct.hits.size() == 2, "Beide Raketen treffen den Zombie direkt, Treffer: %d." % direct.hits.size())
	if direct.hits.size() == 2:
		_check(is_equal_approx(direct.hits[0]["amount"], 250.0) and direct.hits[0]["info"].get("extra") == false and direct.hits[0]["info"].get("source") == "bullet",
			"Die erste Rakete: 250 Kugelschaden.")
		_check(is_equal_approx(direct.hits[1]["amount"], 125.0) and direct.hits[1]["info"].get("extra") == true and direct.hits[1]["info"].get("source") == "bullet",
			"Die Zusatzrakete: 125 Kugelschaden mit extra = true. War %s." % [direct.hits[1]])
	_check(beside.hits.size() == 2, "Der Nachbar bekommt zwei Explosionen ab, Treffer: %d." % beside.hits.size())
	if beside.hits.size() == 2:
		_check(is_equal_approx(beside.hits[0]["amount"], 150.0) and beside.hits[0]["info"].get("source") == "explosion" and beside.hits[0]["info"].get("extra") == false,
			"Die Explosion der ersten Rakete: 150.")
		_check(is_equal_approx(beside.hits[1]["amount"], 75.0) and beside.hits[1]["info"].get("source") == "explosion" and beside.hits[1]["info"].get("extra") == true,
			"Die Explosion der Zusatzrakete: 75 mit extra = true. War %s." % [beside.hits[1]])
	_check(far.hits.is_empty(), "Außerhalb des Radius trifft auch die Zusatzrakete nicht.")
	_check(_count("bullet_hit") == 2 and _count("weapon_fired") == 1, "Zwei direkte Treffer, ein Schuss.")
	_check(_journal == ["damage:D", "bullet_hit:D", "damage:N", "damage:D", "bullet_hit:D", "damage:N", "weapon_fired"],
		"Erst die ganze erste Rakete, dann die Zusatzrakete. War %s." % [_journal])
	_check(launcher.mag == 0 and launcher.is_reloading, "Beide Raketen kosten zusammen eine Rakete aus dem Magazin.")
	await _clear_dummies()
	# Allgemein gesetzt (ohne Rucksack) gilt die Zugabe für jede Waffe. Das Scharfschützengewehr
	# streut nicht: Die normale Kugel fliegt genau geradeaus, die Zusatzkugel höchstens 1,5 Grad daneben.
	_game.start_run(11)
	await _settle()
	_weapons.give_weapon("sniper")
	_game.upgrades.add_levels("extra_shot", 5)
	_game.upgrades.add_levels("pierce", 1)
	var front: Dummy = _add_dummy("S1", Vector3(0.0, 0.0, -6.0), 4.0, 4.0)
	var behind: Dummy = _add_dummy("S2", Vector3(0.0, 0.0, -8.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	_reset_records()
	_weapons.try_fire()
	_check(front.hits.size() == 2 and behind.hits.size() == 2, "Durchschlag gilt auch für die Zusatzkugel, Treffer: %d und %d." % [front.hits.size(), behind.hits.size()])
	if front.hits.size() == 2 and behind.hits.size() == 2:
		_check(is_equal_approx(front.hits[1]["amount"], 240.0) and is_equal_approx(behind.hits[1]["amount"], 240.0 * 0.85)
			and behind.hits[1]["info"].get("extra") == true, "Zusatzkugel mit 100 %: 240 vorn, 204 dahinter.")
		_check(_hit_angle(front.hits[0]) < 0.05, "Die normale Kugel fliegt genau geradeaus, Abweichung %s Grad." % _hit_angle(front.hits[0]))
		var offset: float = _hit_angle(front.hits[1])
		_check(offset > 0.01 and offset <= WeaponDefs.EXTRA_SHOT_SPREAD_DEG + 0.05, "Die Zusatzkugel fliegt höchstens 1,5 Grad versetzt, waren %s Grad." % offset)
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Glücksrad (crit): je Kugel ein Wurf, kritische Treffer zählen doppelt.
func _test_crit() -> void:
	# Vier legendäre Exemplare auf der Pistole: 4 mal 30 % endet bei 100 %.
	var uids: Array[int] = _pack_weapons([["pistol", Vector2i(2, 2)]])
	var pistol_uid: int = uids[0]
	for i: int in 4:
		_attach("crit", 5, [pistol_uid] as Array[int])
	_game.sync_build()
	var target: Dummy = _add_dummy("C", Vector3(0.0, 0.0, -6.0), 1.8)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 0.9, -5.7))
	_check(is_equal_approx(_game.bullet_value(pistol_uid, "crit", "chance"), 1.0), "Aufbau: Vier legendäre Glücksräder ergeben 100 %% Chance, war %s." % _game.bullet_value(pistol_uid, "crit", "chance"))
	for shot: int in 3:
		_ready_weapon()
		_reset_records()
		_weapons.try_fire()
		_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 50.0) and target.hits[0]["info"].get("crit") == true,
			"Chance 100 %%: Schuss %d ist kritisch (50 Schaden, crit = true)." % (shot + 1))
		_check(_count("bullet_hit") == 1 and is_equal_approx(_last("bullet_hit")[1], 50.0), "bullet_hit trägt den doppelten Schaden.")
	_player.look_at_point(Vector3(0.0, 1.62, -5.7))
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 100.0) and target.hits[0]["info"].get("headshot") == true
		and target.hits[0]["info"].get("crit") == true, "Kritischer Kopftreffer: 25 mal 2 mal 2 = 100.")
	await _clear_dummies()
	# Jede Schrotkugel und jede Zusatzkugel würfelt für sich (hier allgemein gesetzt, Chance 100 %).
	_game.start_run(11)
	await _settle()
	_weapons.give_weapon("shotgun")
	_game.upgrades.set_derived({"crit": 5, "extra_shot": 1}, [] as Array[String], {}, {"crit": [5, 5, 5, 5], "extra_shot": [1]})
	target = _add_dummy("CS", Vector3(0.0, 0.0, -3.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 9 and _flagged(target, "crit").size() == 9, "Alle 9 Kugeln sind kritisch, waren %d von %d." % [_flagged(target, "crit").size(), target.hits.size()])
	_check(is_equal_approx(target.total_damage(), 8.0 * 28.0 + 14.0), "8 Schrotkugeln zu 28 und die Zusatzkugel zu 14, zusammen war es %s." % target.total_damage())
	if target.hits.size() == 9:
		_check(target.hits[8]["info"].get("extra") == true and target.hits[8]["info"].get("crit") == true and is_equal_approx(target.hits[8]["amount"], 14.0),
			"Die Zusatzkugel ist zugleich kritisch: 14 mal 0,5 mal 2.")
	await _clear_dummies()
	# Eine kritische Rakete: Auch ihre Explosion zählt doppelt.
	_weapons.give_weapon("rocket_launcher")
	_game.upgrades.set_derived({"crit": 5}, [] as Array[String], {}, {"crit": [5, 5, 5, 5]})
	var direct: Dummy = _add_dummy("CD", Vector3(0.0, 0.0, -8.0))
	var beside: Dummy = _add_dummy("CN", Vector3(2.0, 0.0, -8.0))
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -8.0))
	_reset_records()
	_weapons.try_fire()
	_check(direct.hits.size() == 1 and is_equal_approx(direct.hits[0]["amount"], 500.0) and direct.hits[0]["info"].get("crit") == true, "Kritische Rakete: 500 direkt.")
	_check(beside.hits.size() == 1 and is_equal_approx(beside.hits[0]["amount"], 300.0) and beside.hits[0]["info"].get("crit") == true
		and beside.hits[0]["info"].get("source") == "explosion", "Die Explosion der kritischen Rakete: 300 mit crit = true.")
	await _clear_dummies()
	# Chance 0: Schaden wie immer, und der Zufall bleibt unberührt. Je Kugel verbraucht die Pistole
	# genau zwei Zufallszahlen (Streuung), ein Wurf für den kritischen Treffer kommt nicht dazu.
	_game.start_run(77)
	await _settle()
	target = _add_dummy("C0", Vector3(0.0, 0.0, -6.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	_reset_records()
	var reference: RandomNumberGenerator = RandomNumberGenerator.new()
	reference.state = _game.rng.state
	for shot: int in 5:
		_ready_weapon()
		_weapons.try_fire()
		reference.randf()
		reference.randf()
	_check(_game.rng.state == reference.state, "Ohne Glücksrad verbraucht ein Schuss nur die zwei Zufallszahlen der Streuung.")
	var plain_ok: bool = target.hits.size() == 5
	for hit: Dictionary in target.hits:
		if not is_equal_approx(hit["amount"], 25.0) or bool(hit["info"].get("crit", false)):
			plain_ok = false
	_check(plain_ok, "Chance 0: fünf Treffer zu je 25 Schaden, keiner kritisch.")
	# Das Scharfschützengewehr streut nicht: ohne Glücksrad gar kein Zufall.
	_weapons.give_weapon("sniper")
	var state_before: int = _game.rng.state
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 240.0) and _game.rng.state == state_before,
		"Ein Schuss ohne Streuung und ohne Glücksrad verbraucht keine Zufallszahl.")
	# Chance 30 % (allgemein gesetzt): Der dritte Wurf je Kugel entscheidet, genau wie ein
	# Vergleichs-Zufall mit demselben Anfang.
	_game.start_run(77)
	await _settle()
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -6.0))
	_game.upgrades.add_levels("crit", 5)
	var chance: float = _game.bullet_value(0, "crit", "chance")
	_check(is_equal_approx(chance, 0.3), "Aufbau: Ein legendäres Glücksrad gibt 30 %% Chance, war %s." % chance)
	_reset_records()
	reference.state = _game.rng.state
	for shot: int in 20:
		_weapons.refill_ammo("pistol")
		_ready_weapon()
		_weapons.try_fire()
	var expected_crits: Array[bool] = []
	for shot: int in 20:
		reference.randf()
		reference.randf()
		expected_crits.append(reference.randf() < chance)
	_check(_game.rng.state == reference.state, "Mit Glücksrad kommt je Kugel genau ein Wurf dazu.")
	_check(target.hits.size() == 20, "Alle 20 Schüsse treffen, waren %d." % target.hits.size())
	var rolls_ok: bool = target.hits.size() == 20
	var crits: int = 0
	for index: int in mini(target.hits.size(), 20):
		var hit: Dictionary = target.hits[index]
		var crit: bool = bool(hit["info"].get("crit", false))
		if crit:
			crits += 1
		if crit != expected_crits[index] or not is_equal_approx(hit["amount"], 50.0 if crit else 25.0):
			rolls_ok = false
	_check(rolls_ok, "Jeder Treffer ist genau dann kritisch (50 statt 25), wenn sein Wurf unter 30 % liegt.")
	_check(crits > 0 and crits < 20, "Bei 30 %% sind manche Treffer kritisch und manche nicht, kritisch waren %d von 20." % crits)
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Überlänge (big_mag): größeres Magazin, das sich nicht von selbst füllt.
func _test_big_mag() -> void:
	var uids: Array[int] = _pack_weapons([["pistol", Vector2i(2, 2)]])
	var pistol_uid: int = uids[0]
	_game.sync_build()
	await _place_player(Vector3.ZERO)
	var pistol: WeaponState = _weapons.get_state_of(pistol_uid)
	_check(pistol != null and pistol.mag == 10 and _weapons.get_hands()[0]["magazine"] == 10, "Ohne Überlänge: 10 von 10.")
	if pistol == null:
		return
	pistol.mag = 7
	var item_uid: int = _attach("big_mag", 1, [pistol_uid] as Array[int])
	_reset_records()
	_game.sync_build()
	_check(_weapons.get_state_of(pistol_uid) == pistol, "Die Pistole behält beim Abgleich ihren Zustand.")
	_check(pistol.magazine_size() == 13 and _weapons.get_hands()[0]["magazine"] == 13, "Überlänge +30 %%: Magazingröße 13, war %d." % pistol.magazine_size())
	_check(pistol.mag == 7 and _weapons.get_hands()[0]["mag"] == 7, "Das größere Magazin wird nicht geschenkt gefüllt (7 bleiben), waren %d." % pistol.mag)
	_check(_has_record("hand_ammo_changed", [0, 7, 13]), "Der Abgleich meldet 7 von 13. War %s." % [_received.get("hand_ammo_changed", [])])
	_check(not pistol.is_reloading, "Die Waffe lädt deshalb nicht von selbst nach.")
	# Nachladen füllt bis zur neuen Größe.
	_weapons.start_reload()
	_check(pistol.is_reloading, "Mit 7 von 13 lässt sich nachladen.")
	pistol.reload_left = 0.02
	await _wait(0.1)
	_check(pistol.mag == 13 and _last("hand_ammo_changed") == [0, 13, 13], "Nachladen füllt auf 13, waren %d." % pistol.mag)
	# 13 Schüsse, erst dann ist das Magazin leer.
	var shots: int = 0
	for i: int in 13:
		_ready_weapon()
		if _weapons.try_fire():
			shots += 1
		if i == 9:
			_check(pistol.mag == 3 and not pistol.is_reloading, "Nach 10 Schüssen sind noch 3 im Magazin.")
	_check(shots == 13 and pistol.mag == 0 and pistol.is_reloading, "Erst der 13. Schuss leert das Magazin, Schüsse: %d." % shots)
	pistol.reload_left = 0.02
	await _wait(0.1)
	_check(pistol.mag == 13, "Auch das Nachladen von selbst füllt auf 13.")
	# Der Gegenstand kommt in die Ablage: Das Magazin schrumpft, der Rest verfällt.
	_game.backpack.store(item_uid)
	_reset_records()
	_game.sync_build()
	_check(pistol.magazine_size() == 10 and pistol.mag == 10, "Ohne Überlänge: Größe 10 und höchstens 10 Kugeln, waren %d." % pistol.mag)
	_check(_has_record("hand_ammo_changed", [0, 10, 10]), "Der Abgleich meldet 10 von 10.")
	_game.backpack.remove(item_uid)
	# Legendär (+100 %) auf ein angebrochenes Magazin: Die 4 Kugeln bleiben.
	pistol.mag = 4
	item_uid = _attach("big_mag", 5, [pistol_uid] as Array[int])
	_game.sync_build()
	_check(pistol.magazine_size() == 20 and pistol.mag == 4, "Legendäre Überlänge: Größe 20, die 4 Kugeln bleiben.")
	# Kleiner werden kappt nur, was nicht mehr passt: 18 Kugeln, neue Größe 13.
	pistol.mag = 18
	_game.backpack.remove(item_uid)
	item_uid = _attach("big_mag", 1, [pistol_uid] as Array[int])
	_game.sync_build()
	_check(pistol.magazine_size() == 13 and pistol.mag == 13, "Von 20 auf 13: 18 Kugeln werden 13, waren %d." % pistol.mag)
	pistol.mag = 5
	_game.sync_build()
	_check(pistol.mag == 5, "Ein Abgleich ohne Änderung lässt das Magazin, wie es ist.")
	# Eine Waffe, die neu in die Hand kommt, beginnt mit vollem größerem Magazin.
	uids = _pack_weapons([["pistol", Vector2i(2, 2)]])
	pistol_uid = uids[0]
	_attach("big_mag", 3, [pistol_uid] as Array[int])
	_reset_records()
	_game.sync_build()
	pistol = _weapons.get_state_of(pistol_uid)
	_check(pistol.mag == 16 and pistol.magazine_size() == 16, "Neue Waffe mit seltener Überlänge (+60 %%): 16 von 16, waren %d." % pistol.mag)
	_check(_last("hand_ammo_changed") == [0, 16, 16] and _last("ammo_changed") == [16, -1], "Die Signale melden das volle größere Magazin.")
	# Zwei Exemplare addieren sich: +60 % und +30 % ergeben 19.
	_attach("big_mag", 1, [pistol_uid] as Array[int])
	_game.sync_build()
	_check(pistol.magazine_size() == 19 and pistol.mag == 16, "Zwei Exemplare: Größe 19, die 16 Kugeln bleiben. War %d von %d." % [pistol.mag, pistol.magazine_size()])
	_weapons.refill_ammo("pistol")
	_check(pistol.mag == 19, "refill_ammo füllt bis zur neuen Größe.")
	# Allgemein gesetzt (ohne Rucksack): gilt nach refresh_weapon_stats, spätestens beim nächsten Schuss.
	_game.start_run(11)
	await _settle()
	_game.upgrades.add_levels("big_mag", 1)
	_reset_records()
	_weapons.refresh_weapon_stats()
	_check(_weapons.get_hands()[0]["magazine"] == 13 and _weapons.get_hands()[0]["mag"] == 10 and _has_record("hand_ammo_changed", [0, 10, 13]),
		"refresh_weapon_stats übernimmt von Hand gesetzte Werte und meldet 10 von 13.")
	_game.start_run(11)
	await _settle()
	_game.upgrades.add_levels("big_mag", 5)
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(_last("hand_ammo_changed") == [0, 9, 20], "Ohne refresh gilt der Wert ab dem nächsten Schuss (9 von 20). War %s." % [_last("hand_ammo_changed")])
	_game.start_run(11)
	await _settle()


## Schießt mehrmals auf das breite Ziel und nennt die größte Abweichung eines Einschlags von der
## Blickrichtung in Grad.
func _widest_angle(target: Dummy, weapon_id: String, shots: int) -> float:
	var widest: float = 0.0
	for i: int in shots:
		_weapons.refill_ammo(weapon_id)
		_ready_weapon()
		target.hits.clear()
		_weapons.try_fire()
		for hit: Dictionary in target.hits:
			widest = maxf(widest, _hit_angle(hit))
	return widest


## Teleprompter (scope): halbe Streuung, stärkere Kopftreffer.
func _test_scope() -> void:
	var uids: Array[int] = _pack_weapons([["pistol", Vector2i(2, 2)]])
	var pistol_uid: int = uids[0]
	_game.sync_build()
	_check(is_equal_approx(_weapons.get_spread_of(pistol_uid), 0.5), "Ohne Teleprompter streut die Pistole 0,5 Grad.")
	_check(_weapons.get_spread_of(9999) == 0.0, "get_spread_of einer nicht gehaltenen Waffe ist 0.")
	var scope_uid: int = _attach("scope", 1, [pistol_uid] as Array[int])
	_game.sync_build()
	_check(_game.bullet_level(pistol_uid, "scope") == 1 and is_equal_approx(_weapons.get_spread_of(pistol_uid), 0.25),
		"Mit Teleprompter streut die Pistole nur 0,25 Grad, war %s." % _weapons.get_spread_of(pistol_uid))
	# 1,8 m hoch: Kopf ab 1,404 m.
	var target: Dummy = _add_dummy("T", Vector3(0.0, 0.0, -6.0), 1.8)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.62, -5.7))
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 62.5) and target.hits[0]["info"].get("headshot") == true,
		"Kopftreffer mit Teleprompter (+25 %%): 25 mal 2 mal 1,25 = 62,5, war %s." % target.total_damage())
	_player.look_at_point(Vector3(0.0, 0.9, -5.7))
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 25.0), "Körpertreffer bleiben bei 25, war %s." % target.total_damage())
	# Legendär: +75 %.
	_game.backpack.remove(scope_uid)
	scope_uid = _attach("scope", 5, [pistol_uid] as Array[int])
	_game.sync_build()
	_player.look_at_point(Vector3(0.0, 1.62, -5.7))
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 87.5), "Legendärer Teleprompter: 25 mal 2 mal 1,75 = 87,5, war %s." % target.total_damage())
	# Zwei Exemplare: Der Kopftreffer-Zusatz addiert sich, die Streuung wird nur einmal halbiert.
	_attach("scope", 1, [pistol_uid] as Array[int])
	_game.sync_build()
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	_check(target.hits.size() == 1 and is_equal_approx(target.hits[0]["amount"], 100.0), "Zwei Teleprompter (+75 %% und +25 %%): 100, war %s." % target.total_damage())
	_check(is_equal_approx(_weapons.get_spread_of(pistol_uid), 0.25), "Die Streuung wird nur einmal halbiert.")
	await _clear_dummies()
	# Gemessen an der abgesägten Schrotflinte (8 Grad): ohne Teleprompter bis 8 Grad, mit bis 4 Grad.
	uids = _pack_weapons([["sawed_off", Vector2i(1, 3)]])
	_game.sync_build()
	target = _add_dummy("TW", Vector3(0.0, 0.0, -3.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	var plain: float = _widest_angle(target, "sawed_off", 8)
	_check(plain > 4.3 and plain <= 8.3, "Ohne Teleprompter liegen die 40 Kugeln in 8 Grad und nicht alle in 4, weiteste: %s." % plain)
	_attach("scope", 1, [uids[0]] as Array[int])
	_game.sync_build()
	_check(is_equal_approx(_weapons.get_spread_of(uids[0]), 4.0), "Mit Teleprompter nennt get_spread_of 4 Grad.")
	var scoped: float = _widest_angle(target, "sawed_off", 8)
	_check(scoped > 2.0 and scoped <= 4.3, "Mit Teleprompter liegen alle 40 Kugeln in 4 Grad, weiteste: %s." % scoped)
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Hält den Abzug und treibt die Waffensteuerung selbst mit festen Schritten an (kein echtes Bild
## dazwischen). So hängt die Zahl der Schüsse nicht von der Bildrate des Tests ab. Gibt die
## Schüsse zurück.
func _burst(weapon_id: String, steps: int, delta: float) -> int:
	Input.action_press("fire")
	await _frames(2)
	_weapons.refill_ammo(weapon_id)
	_ready_weapon()
	_reset_records()
	var points_before: int = _game.points
	for i: int in steps:
		_weapons.call("_process", delta)
	var shots: int = _count("weapon_fired")
	_burst_points = _game.points - points_before
	Input.action_release("fire")
	await _frames(2)
	return shots


## Schüsse, die bei Dauerfeuer mit dieser Schussrate in steps Schritten genau fallen: der erste im
## ersten Schritt, danach einer je Schussfolge.
func _burst_shots(rate: float, steps: int, delta: float) -> int:
	return floori(float(steps - 1) * delta * rate + 0.0001) + 1


## Schnelldurchlauf (fire_rate): mehr Schüsse in derselben Zeit.
func _test_fire_rate_item() -> void:
	var uids: Array[int] = _pack_weapons([["smg", Vector2i(2, 2)]])
	var smg_uid: int = uids[0]
	_game.sync_build()
	var target: Dummy = _add_dummy("R", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	var smg: WeaponState = _weapons.get_state_of(smg_uid)
	_check(smg != null and smg.fire_rate_factor == 1.0, "Ohne Schnelldurchlauf: Schussrate normal.")
	if smg == null:
		await _clear_dummies()
		return
	# 1,5 s Dauerfeuer in Schritten von 1/60 s: 12 Schuss je Sekunde ergeben 18 Schüsse.
	var base_shots: int = await _burst("smg", 90, 1.0 / 60.0)
	_check(_burst_shots(12.0, 90, 1.0 / 60.0) == 18 and absi(base_shots - 18) <= 1, "MP ohne Schnelldurchlauf: 18 Schüsse in 1,5 s, waren %d." % base_shots)
	var item_uid: int = _attach("fire_rate", 5, [smg_uid] as Array[int])
	_game.sync_build()
	_check(_weapons.get_state_of(smg_uid) == smg and is_equal_approx(smg.fire_rate_factor, 1.3) and is_equal_approx(smg.fire_interval(), 1.0 / 15.6),
		"Legendärer Schnelldurchlauf: 30 %% schneller (15,6 Schuss je Sekunde), Faktor war %s." % smg.fire_rate_factor)
	var fast_shots: int = await _burst("smg", 90, 1.0 / 60.0)
	var fast_expected: int = _burst_shots(15.6, 90, 1.0 / 60.0)
	_check(fast_expected == 24 and absi(fast_shots - fast_expected) <= 1, "MP mit Schnelldurchlauf: 24 Schüsse in 1,5 s, waren %d." % fast_shots)
	_check(fast_shots >= base_shots + 4, "In derselben Zeit fallen mehr Schüsse: %d statt %d." % [fast_shots, base_shots])
	_check(smg.mag == 30 - fast_shots and target.hits.size() == fast_shots, "Jeder Schuss kostet eine Kugel und trifft.")
	# Auch bei 10 Bildern je Sekunde stimmt die schnellere Rate (mehrere Schüsse je Bild).
	var slow_shots: int = await _burst("smg", 15, 0.1)
	_check(absi(slow_shots - _burst_shots(15.6, 15, 0.1)) <= 1, "MP mit Schnelldurchlauf bei 10 Bildern/s: %d Schüsse in 1,5 s erwartet, waren %d." % [_burst_shots(15.6, 15, 0.1), slow_shots])
	# Zwei Exemplare addieren sich: +30 % und +10 % ergeben 16,8 Schuss je Sekunde.
	var second_uid: int = _attach("fire_rate", 1, [smg_uid] as Array[int])
	_game.sync_build()
	_check(is_equal_approx(smg.fire_rate_factor, 1.4), "Zwei Exemplare: Faktor 1,4, war %s." % smg.fire_rate_factor)
	var double_shots: int = await _burst("smg", 90, 1.0 / 60.0)
	_check(absi(double_shots - _burst_shots(16.8, 90, 1.0 / 60.0)) <= 1, "Zwei Exemplare: %d Schüsse in 1,5 s erwartet, waren %d." % [_burst_shots(16.8, 90, 1.0 / 60.0), double_shots])
	# Ohne die Gegenstände gilt wieder die normale Rate.
	_game.backpack.store(item_uid)
	_game.backpack.store(second_uid)
	_game.sync_build()
	_check(smg.fire_rate_factor == 1.0, "Ohne Schnelldurchlauf ist der Faktor wieder 1.")
	var after_shots: int = await _burst("smg", 90, 1.0 / 60.0)
	_check(absi(after_shots - 18) <= 1, "Danach wieder 18 Schüsse in 1,5 s, waren %d." % after_shots)
	# Eine halbautomatische Waffe schießt mit dem Gegenstand ebenfalls früher wieder.
	uids = _pack_weapons([["pistol", Vector2i(2, 2)]])
	_attach("fire_rate", 5, [uids[0]] as Array[int])
	_game.sync_build()
	await _place_player(Vector3.ZERO)
	var pistol: WeaponState = _weapons.get_state_of(uids[0])
	_check(_weapons.try_fire() and is_equal_approx(pistol.cooldown_left, 0.2 / 1.3), "Pistole mit Schnelldurchlauf: 0,154 s bis zum nächsten Schuss, war %s." % pistol.cooldown_left)
	await _clear_dummies()
	_game.start_run(11)
	await _settle()


## Beidhändig: Ein Gegenstand wirkt nur für die Waffe, die auf seinen Sternen liegt.
func _test_items_per_hand() -> void:
	var uids: Array[int] = _pack_weapons([["pistol", Vector2i(1, 1)], ["pistol", Vector2i(3, 3)]])
	var left_uid: int = uids[0]
	var right_uid: int = uids[1]
	_attach("extra_shot", 1, [right_uid] as Array[int])
	_attach("big_mag", 1, [left_uid] as Array[int])
	_attach("fire_rate", 1, [right_uid] as Array[int])
	_attach("crit", 5, [left_uid] as Array[int])
	_game.sync_build()
	var target: Dummy = _add_dummy("B", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -5.0))
	var hands: Array[Dictionary] = _weapons.get_hands()
	_check(hands.size() == 2 and hands[0]["uid"] == left_uid and hands[1]["uid"] == right_uid, "Aufbau: zwei Pistolen, die linke zuerst.")
	if hands.size() < 2:
		await _clear_dummies()
		return
	var left: WeaponState = _weapons.get_state_of(left_uid)
	var right: WeaponState = _weapons.get_state_of(right_uid)
	# Überlänge nur links.
	_check(hands[0]["magazine"] == 13 and hands[0]["mag"] == 13, "Die linke Pistole (auf dem Stern der Überlänge) hat 13 Schuss. War %s." % [hands[0]])
	_check(hands[1]["magazine"] == 10 and hands[1]["mag"] == 10, "Die rechte Pistole bleibt bei 10 Schuss. War %s." % [hands[1]])
	# Schnelldurchlauf nur rechts.
	_check(left.fire_rate_factor == 1.0 and is_equal_approx(right.fire_rate_factor, 1.1), "Nur die rechte Pistole schießt 10 %% schneller (%s und %s)." % [left.fire_rate_factor, right.fire_rate_factor])
	# Glücksrad nur links, Zugabe nur rechts.
	_check(is_equal_approx(_game.bullet_value(left_uid, "crit", "chance"), 0.3) and _game.bullet_value(right_uid, "crit", "chance") == 0.0,
		"Aufbau: Das Glücksrad wirkt nur für die linke Pistole.")
	_check(_game.bullet_value(left_uid, "extra_shot", "shots") == 0.0 and is_equal_approx(_game.bullet_value(right_uid, "extra_shot", "shots"), 1.0),
		"Aufbau: Die Zugabe wirkt nur für die rechte Pistole.")
	var left_ok: bool = true
	var right_ok: bool = true
	var left_crits: int = 0
	for volley: int in 20:
		_weapons.refill_ammo("pistol")
		_ready_weapon()
		_reset_records()
		_weapons.try_fire()
		var left_hits: Array[Dictionary] = _hits_of_hand(target, 0)
		var right_hits: Array[Dictionary] = _hits_of_hand(target, 1)
		if left_hits.size() != 1 or bool(left_hits[0]["info"].get("extra", false)) or left_hits[0]["info"].get("weapon_uid") != left_uid:
			left_ok = false
		else:
			var crit: bool = bool(left_hits[0]["info"].get("crit", false))
			if crit:
				left_crits += 1
			if not is_equal_approx(left_hits[0]["amount"], 50.0 if crit else 25.0):
				left_ok = false
		if right_hits.size() != 2:
			right_ok = false
		else:
			var normal: Dictionary = right_hits[0]
			var extra: Dictionary = right_hits[1]
			if not is_equal_approx(normal["amount"], 25.0) or bool(normal["info"].get("extra", false)) or bool(normal["info"].get("crit", false)):
				right_ok = false
			if not is_equal_approx(extra["amount"], 12.5) or extra["info"].get("extra") != true or bool(extra["info"].get("crit", false)) or extra["info"].get("weapon_uid") != right_uid:
				right_ok = false
	_check(left_ok, "Links: je Schuss eine Kugel ohne Zugabe, 25 Schaden oder kritisch 50.")
	_check(left_crits > 0 and left_crits < 20, "Links sind manche Treffer kritisch, waren %d von 20." % left_crits)
	_check(right_ok, "Rechts: je Schuss eine normale Kugel (25) und eine Zusatzkugel (12,5), nie kritisch.")
	_check(_has_record("hand_ammo_changed", [0, 12, 13]) and _has_record("hand_ammo_changed", [1, 9, 10]), "Die Magazine zählen je Hand: 12 von 13 und 9 von 10.")
	# Nachladen füllt jede Hand auf ihre eigene Größe.
	left.mag = 1
	right.mag = 1
	_weapons.start_reload()
	left.reload_left = 0.02
	right.reload_left = 0.02
	await _wait(0.1)
	_check(left.mag == 13 and right.mag == 10, "Nachladen: links 13, rechts 10. War %d und %d." % [left.mag, right.mag])
	await _clear_dummies()
	# Teleprompter nur rechts: Streuung und Kopftreffer ändern sich nur dort.
	uids = _pack_weapons([["pistol", Vector2i(1, 1)], ["pistol", Vector2i(3, 3)]])
	left_uid = uids[0]
	right_uid = uids[1]
	var scope_uid: int = _attach("scope", 1, [right_uid] as Array[int])
	_game.sync_build()
	_check(is_equal_approx(_weapons.get_spread_of(left_uid), 0.5) and is_equal_approx(_weapons.get_spread_of(right_uid), 0.25),
		"Nur die rechte Pistole streut weniger (%s und %s)." % [_weapons.get_spread_of(left_uid), _weapons.get_spread_of(right_uid)])
	target = _add_dummy("BH", Vector3(0.0, 0.0, -6.0), 1.8)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.62, -5.7))
	_reset_records()
	_weapons.try_fire()
	var head_left: Array[Dictionary] = _hits_of_hand(target, 0)
	var head_right: Array[Dictionary] = _hits_of_hand(target, 1)
	_check(head_left.size() == 1 and is_equal_approx(head_left[0]["amount"], 50.0), "Kopftreffer links: 50 wie immer.")
	_check(head_right.size() == 1 and is_equal_approx(head_right[0]["amount"], 62.5), "Kopftreffer rechts mit Teleprompter: 62,5.")
	# Der Teleprompter wandert zur linken Pistole: Jetzt ist es umgekehrt.
	_game.backpack.remove(scope_uid)
	_attach("scope", 1, [left_uid] as Array[int])
	_game.sync_build()
	_check(is_equal_approx(_weapons.get_spread_of(left_uid), 0.25) and is_equal_approx(_weapons.get_spread_of(right_uid), 0.5),
		"Nach dem Umräumen streut nur die linke Pistole weniger.")
	_ready_weapon()
	_reset_records()
	_weapons.try_fire()
	head_left = _hits_of_hand(target, 0)
	head_right = _hits_of_hand(target, 1)
	_check(head_left.size() == 1 and is_equal_approx(head_left[0]["amount"], 62.5) and head_right.size() == 1 and is_equal_approx(head_right[0]["amount"], 50.0),
		"Nach dem Umräumen: Kopftreffer links 62,5, rechts 50.")
	await _clear_dummies()
	# Allgemein gesetzte Werte (ohne Rucksack-Gegenstand) gelten für beide Hände.
	_game.start_run(11)
	await _settle()
	_weapons.equip(["pistol", "pistol"] as Array[String])
	_game.upgrades.add_levels("extra_shot", 1)
	_game.upgrades.add_levels("big_mag", 1)
	_game.upgrades.add_levels("fire_rate", 5)
	_game.upgrades.add_levels("scope", 1)
	_weapons.refresh_weapon_stats()
	target = _add_dummy("BA", Vector3(0.0, 0.0, -5.0), 4.0, 4.0)
	await _place_player(Vector3.ZERO)
	_player.look_at_point(Vector3(0.0, 1.2, -5.0))
	hands = _weapons.get_hands()
	_check(hands.size() == 2 and hands[0]["magazine"] == 13 and hands[1]["magazine"] == 13, "Allgemein gesetzt: beide Magazine haben 13 Schuss.")
	if hands.size() == 2:
		_check(is_equal_approx(_weapons.get_state_of(int(hands[0]["uid"])).fire_rate_factor, 1.3) and is_equal_approx(_weapons.get_state_of(int(hands[1]["uid"])).fire_rate_factor, 1.3),
			"Allgemein gesetzt: beide Hände schießen 30 % schneller.")
		_check(is_equal_approx(_weapons.get_spread_of(int(hands[0]["uid"])), 0.25) and is_equal_approx(_weapons.get_spread_of(int(hands[1]["uid"])), 0.25),
			"Allgemein gesetzt: beide Hände streuen weniger.")
	_reset_records()
	_weapons.try_fire()
	_check(_hits_of_hand(target, 0).size() == 2 and _hits_of_hand(target, 1).size() == 2 and _flagged(target, "extra").size() == 2,
		"Allgemein gesetzt: jede Hand schießt eine Zusatzkugel, Treffer: %d." % target.hits.size())
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
