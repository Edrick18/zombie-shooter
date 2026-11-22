extends SceneTree
## Tests für die Fähigkeiten des Spielers aus Abschnitt 19.2: Sicherheitsglas (Schild) und
## Notausgang (Ausweichsprung), dazu ihre Anzeige im HUD. Aus Abschnitt 22.3 die Zweite Staffel
## (ein tödlicher Treffer tötet nicht, Ladungen je Exemplar, Rückkehr nach geschafften Wellen).
## Baut headless eine kleine Welt (Boden, Spieler) und prüft: ohne Gegenstand bleibt alles wie
## bisher, das Schild fängt Schaden ab und lädt nach der Wartezeit, mehrere Exemplare, Verkauf,
## neuer Lauf, der Sprung mit Strecke, Richtung, Ladungen, Abklingzeit und Unverwundbarkeit,
## Schild-Anzeige und Sprung-Kästchen im HUD.
##
## Startet in _initialize und wartet ein Bild (Autoloads, siehe Architektur 13.7). Die Skripte
## des Spiels werden zur Laufzeit mit load() geholt, weil sie Game und Events benutzen.
##
## Zeiten misst der Test in Spielzeit (Summe der Physikschritte, siehe Clock) und nicht in echter
## Zeit: So gilt dasselbe mit und ohne feste Bildrate. Lange Wartezeiten laufen im Zeitraffer
## (Engine.time_scale macht jeden Physikschritt länger), das Ende jeder Wartezeit und die Sprünge
## selbst in normaler Zeit.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")

## Zeitraffer für lange Wartezeiten und Abstand zum Ziel, ab dem wieder normale Zeit gilt.
const FAST_TIME_SCALE: float = 4.0
const FAST_MARGIN: float = 0.5
const DASH_DISTANCE: float = Balance.DASH_SPEED * Balance.DASH_TIME


## Uhr der Spielzeit: zählt die Dauer aller Physikschritte zusammen (steht in der Pause still,
## wie der Spieler). Hängt vor dem Spieler im Baum und läuft deshalb vor ihm.
class Clock:
	extends Node
	var time: float = 0.0

	func _physics_process(delta: float) -> void:
		time += delta


## Ersatz-Zombie für die Druckwelle der Zweiten Staffel: Er merkt sich Stöße und Schaden.
class PushZombie:
	extends Node3D
	var is_dead: bool = false
	var knockback: Vector3 = Vector3.ZERO
	var damage_taken: float = 0.0

	func _ready() -> void:
		add_to_group("zombies")

	func apply_knockback(impulse: Vector3) -> void:
		knockback += impulse

	func take_damage(amount: float, _info: Dictionary) -> void:
		damage_taken += amount


var _failures := 0
var _checks := 0
var _game: Node
var _events: Node
var _player: CharacterBody3D
## Signalname -> Liste der Argument-Listen, in der Reihenfolge des Eintreffens.
var _received: Dictionary = {}
## Namen der Signale in der Reihenfolge des Eintreffens.
var _journal: Array = []
var _clock: Clock
var _ticks_per_second: int = 60


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
		_ticks_per_second = Engine.physics_ticks_per_second
		_listen()
		_build_world()
		_game.start_run(11)
		await _settle()
		await _test_without_items()
		await _test_shield()
		await _test_shield_general_and_death()
		await _test_dash()
		await _test_revive()
		await _test_hud()
		_release_all_actions()
	Engine.time_scale = 1.0
	if _failures == 0:
		print("test_player_abilities: alle Prüfungen bestanden (%d)." % _checks)
	quit(1 if _failures > 0 else 0)


# --- Aufbau ---


func _listen() -> void:
	_events.connect("player_health_changed", func(hp: float, max_hp: float) -> void: _record("player_health_changed", [hp, max_hp]))
	_events.connect("player_damaged", func(amount: float) -> void: _record("player_damaged", [amount]))
	_events.connect("player_died", func() -> void: _record("player_died", []))
	_events.connect("player_shield_changed", func(shield: float, max_shield: float) -> void: _record("player_shield_changed", [shield, max_shield]))
	_events.connect("dash_charges_changed", func(charges: int, max_charges: int) -> void: _record("dash_charges_changed", [charges, max_charges]))
	_events.connect("player_dashed", func() -> void: _record("player_dashed", []))
	_events.connect("revive_charges_changed", func(charges: int, max_charges: int) -> void: _record("revive_charges_changed", [charges, max_charges]))
	_events.connect("player_revived", func() -> void: _record("player_revived", []))


func _build_world() -> void:
	_clock = Clock.new()
	_clock.name = "TestClock"
	root.add_child(_clock)
	_add_block("Floor", Vector3(0.0, -0.5, 0.0), Vector3(600.0, 1.0, 600.0))
	var player_script: GDScript = load("res://scripts/game/player/player.gd")
	_player = player_script.new()
	root.add_child(_player)


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


func _settle(steps: int = 4) -> void:
	for i: int in steps:
		await physics_frame
	await process_frame


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


## Knoten der Druckwelle (Fx.shockwave) direkt unter der Wurzel: Ringe, Wand und Lichtstoß.
func _shockwave_parts() -> Array[Node]:
	var parts: Array[Node] = []
	for child: Node in root.get_children():
		var node_name: String = String(child.name)
		if child.is_queued_for_deletion():
			continue
		if node_name.contains("Ring") or node_name.contains("Shockwave"):
			parts.append(child)
	return parts


## Wartet so viele Physikschritte in normaler Zeit.
func _ticks(count: int) -> void:
	for i: int in count:
		await physics_frame


## Physikschritte für so viele Sekunden Spielzeit.
func _steps(seconds: float) -> int:
	return roundi(seconds * float(_ticks_per_second))


## Lässt Spielzeit vergehen, bis die Uhr diese Zeit zeigt: erst im Zeitraffer, das letzte Stück in
## normaler Zeit (damit das Ende auf einen Physikschritt genau stimmt).
func _idle_until(time: float) -> void:
	while _clock.time < time - 0.0001:
		Engine.time_scale = FAST_TIME_SCALE if time - _clock.time > FAST_MARGIN else 1.0
		await physics_frame
	Engine.time_scale = 1.0


## Lässt so viele Sekunden Spielzeit vergehen.
func _idle(seconds: float) -> void:
	await _idle_until(_clock.time + seconds)


## Wartet, bis der Ausweichsprung vorbei ist. Gibt die Zahl der Physikschritte zurück.
func _wait_dash_end() -> int:
	var count: int = 0
	while _player.is_dashing() and count < 60:
		await physics_frame
		count += 1
	return count


## Stellt den Spieler an einen Ort, Blick nach -Z, ohne Restbewegung.
func _place_player(feet: Vector3) -> void:
	_player.global_position = feet
	_player.velocity = Vector3.ZERO
	_player.look_at_point(feet + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, -10.0))
	await _settle()


## Legt einen Gegenstand dieser Rarität in den Rucksack und gleicht ab. Gibt die uid zurück.
func _give(item_id: String, level: int) -> int:
	var backpack: RefCounted = _game.backpack
	var uid: int = backpack.add_item(item_id, level)
	_check(uid != -1 and backpack.auto_place(uid), "%s (Rarität %d) passt in den Rucksack." % [item_id, level])
	_game.sync_build()
	return uid


## Drückt eine Aktion für ein paar Bilder und lässt sie wieder los.
func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(3)
	Input.action_release(action)
	await _frames(2)


func _release_all_actions() -> void:
	for action: String in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "dash"]:
		Input.action_release(action)


func _flat_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


# --- Tests ---


## Ohne Gegenstand: kein Schild, kein Sprung, Schaden und Signale wie bisher.
func _test_without_items() -> void:
	_check(is_zero_approx(_player.shield) and is_zero_approx(_player.max_shield), "Ohne Sicherheitsglas gibt es kein Schild.")
	_check(_player.dash_charges == 0 and _player.max_dash_charges == 0, "Ohne Notausgang gibt es keine Sprünge.")
	_check(_only_zero("player_shield_changed"), "Ohne Sicherheitsglas kommt kein Schild-Signal mit Werten.")
	_check(_only_zero("dash_charges_changed"), "Ohne Notausgang kommt kein Sprung-Signal mit Werten.")
	await _place_player(Vector3(0.0, 0.0, 40.0))
	await physics_frame
	_reset_records()
	_player.take_damage(20.0)
	_check(is_equal_approx(_player.hp, 80.0), "Ohne Schild trifft der Schaden das Leben: 80, war %s." % _player.hp)
	_check(_journal == ["player_damaged", "player_health_changed"],
		"Ohne Schild dieselben Signale in derselben Reihenfolge, war %s." % [_journal])
	_check(_received.get("player_damaged", []) == [[20.0]] and _last("player_health_changed") == [80.0, 100.0],
		"player_damaged(20) und player_health_changed(80, 100).")
	# Kein Sprung, weder über die Funktion noch über die Taste.
	var before: Vector3 = _player.global_position
	_check(not _player.try_dash() and not _player.is_dashing(), "Ohne Notausgang macht try_dash nichts.")
	await _tap("dash")
	await _ticks(10)
	_check(_count("player_dashed") == 0 and _player.global_position.distance_to(before) < 0.01,
		"Ohne Notausgang bewegt die Taste Q den Spieler nicht.")
	# Auch nach der Wartezeit lädt nichts, Heilung ändert nur das Leben.
	await _idle(Balance.SHIELD_RECHARGE_DELAY + 1.0)
	_player.heal(10.0)
	_check(is_equal_approx(_player.hp, 90.0) and is_zero_approx(_player.shield), "Ohne Schild: Heilung wie bisher, kein Schild.")
	_check(_only_zero("player_shield_changed") and _only_zero("dash_charges_changed"),
		"Ohne Gegenstände kommen keine Schild- und Sprung-Signale mit Werten.")
	# Ein neuer Lauf ohne Gegenstände bleibt ebenfalls ohne.
	_reset_records()
	_game.start_run(11)
	await _settle()
	_check(_only_zero("player_shield_changed") and _only_zero("dash_charges_changed"),
		"Neuer Lauf ohne Gegenstände: keine Schild- und Sprung-Signale mit Werten.")
	_check(_last("player_health_changed") == [100.0, 100.0], "Neuer Lauf: volles Leben wie bisher.")


## Sicherheitsglas aus dem Rucksack: abfangen, Wartezeit, laden, mehrere Exemplare, Verkauf, neuer Lauf.
func _test_shield() -> void:
	_game.start_run(11)
	await _settle()
	await physics_frame
	_reset_records()
	var first: int = _give("shield", 1)
	_check(is_equal_approx(_player.max_shield, 20.0) and is_zero_approx(_player.shield),
		"Neues Sicherheitsglas: 20 Punkte Höchstwert, das Schild kommt leer. War %s / %s." % [_player.shield, _player.max_shield])
	_check(_last("player_shield_changed") == [0.0, 20.0], "player_shield_changed(0, 20), war %s." % [_last("player_shield_changed")])
	# Ohne Schaden in letzter Zeit lädt es sofort, mit 20 Punkten je Sekunde.
	await _ticks(_steps(0.5))
	_near(_player.shield, 0.5 * Balance.SHIELD_RECHARGE_RATE, 0.7, "Nach 0,5 s sind 10 Punkte geladen")
	await _ticks(_steps(0.75))
	_check(_player.shield == 20.0, "Das Schild lädt bis zum Höchstwert, war %s." % _player.shield)
	_check(_last("player_shield_changed") == [20.0, 20.0], "Das letzte Signal meldet das volle Schild, war %s." % [_last("player_shield_changed")])
	var signals_when_full: int = _count("player_shield_changed")
	await _ticks(20)
	_check(_player.shield == 20.0 and _count("player_shield_changed") == signals_when_full,
		"Ein volles Schild lädt nicht weiter und sendet nichts mehr.")

	# Schaden trifft zuerst das Schild.
	_reset_records()
	_player.take_damage(8.0)
	_check(is_equal_approx(_player.shield, 12.0) and is_equal_approx(_player.hp, 100.0),
		"8 Schaden: Schild 12, Leben 100. War %s / %s." % [_player.shield, _player.hp])
	_check(_journal == ["player_damaged", "player_shield_changed", "player_health_changed"],
		"Signale bei abgefangenem Schaden: damaged, shield, health. War %s." % [_journal])
	_check(_received.get("player_damaged", []) == [[8.0]], "player_damaged meldet den vollen Schaden (8).")
	_check(_last("player_shield_changed") == [12.0, 20.0] and _last("player_health_changed") == [100.0, 100.0],
		"player_shield_changed(12, 20) und player_health_changed(100, 100).")

	# In der Wartezeit lädt nichts.
	await _idle(Balance.SHIELD_RECHARGE_DELAY - 0.5)
	_check(is_equal_approx(_player.shield, 12.0), "0,5 s vor Ablauf der Wartezeit lädt das Schild noch nicht, war %s." % _player.shield)
	# Ein Treffer in der Wartezeit stellt sie neu, auch wenn das Schild ihn ganz abfängt.
	_player.take_damage(4.0)
	_check(is_equal_approx(_player.shield, 8.0) and is_equal_approx(_player.hp, 100.0), "4 Schaden: Schild 8, Leben 100.")
	await _idle(Balance.SHIELD_RECHARGE_DELAY - 0.5)
	_check(is_equal_approx(_player.shield, 8.0),
		"Der Treffer in der Wartezeit stellt sie neu: weiter 8 Punkte, war %s." % _player.shield)
	await _idle(1.0)
	_near(_player.shield, 8.0 + 0.5 * Balance.SHIELD_RECHARGE_RATE, 1.0, "0,5 s nach der Wartezeit sind 10 Punkte dazu geladen")
	await _idle(0.5)
	_check(_player.shield == 20.0, "Danach ist das Schild wieder voll, war %s." % _player.shield)

	# Mehr Schaden als Schild: Der Rest trifft das Leben.
	_reset_records()
	_player.take_damage(30.0)
	_check(is_zero_approx(_player.shield) and is_equal_approx(_player.hp, 90.0),
		"30 Schaden auf 20 Schild: Schild 0, Leben 90. War %s / %s." % [_player.shield, _player.hp])
	_check(_received.get("player_damaged", []) == [[30.0]] and _last("player_shield_changed") == [0.0, 20.0]
		and _last("player_health_changed") == [90.0, 100.0], "Signale beim Überlauf: damaged(30), shield(0, 20), health(90, 100).")
	# Heilung füllt das Schild nicht.
	_reset_records()
	_player.heal(5.0)
	_check(is_equal_approx(_player.hp, 95.0) and is_zero_approx(_player.shield) and _count("player_shield_changed") == 0,
		"Heilung füllt nur das Leben, nie das Schild.")
	# Die Unverwundbarkeit nach einem Treffer gilt weiter, danach trifft Schaden bei leerem Schild das Leben.
	_player.take_damage(10.0)
	_check(is_equal_approx(_player.hp, 95.0), "Kurz nach einem Treffer bleibt der Spieler unverwundbar.")
	await _idle(Balance.PLAYER_HIT_INVULNERABILITY + 0.1)
	_reset_records()
	_player.take_damage(10.0)
	_check(is_equal_approx(_player.hp, 85.0) and is_zero_approx(_player.shield), "Leeres Schild: 10 Schaden gehen ganz auf das Leben.")
	_check(_journal == ["player_damaged", "player_health_changed"], "Leeres Schild: kein Schild-Signal, war %s." % [_journal])

	# Zwei Exemplare zählen zusammen. Der größere Höchstwert füllt nichts von selbst.
	_reset_records()
	var second: int = _give("shield", 2)
	_check(is_equal_approx(_player.max_shield, 50.0) and is_zero_approx(_player.shield),
		"Zwei Exemplare (20 + 30): Höchstwert 50, das Schild bleibt leer. War %s / %s." % [_player.shield, _player.max_shield])
	_check(_last("player_shield_changed") == [0.0, 50.0], "player_shield_changed(0, 50), war %s." % [_last("player_shield_changed")])
	await _idle(Balance.SHIELD_RECHARGE_DELAY + 50.0 / Balance.SHIELD_RECHARGE_RATE + 0.5)
	_check(_player.shield == 50.0, "Das größere Schild lädt bis 50, war %s." % _player.shield)

	# Verkauf: Der kleinere Höchstwert kappt das Schild, ohne Exemplar gibt es keines mehr.
	_reset_records()
	_game.sell_item(second)
	_check(is_equal_approx(_player.max_shield, 20.0) and is_equal_approx(_player.shield, 20.0),
		"Ein Exemplar weniger: Höchstwert 20, Schild auf 20 gekappt. War %s / %s." % [_player.shield, _player.max_shield])
	_check(_last("player_shield_changed") == [20.0, 20.0], "player_shield_changed(20, 20), war %s." % [_last("player_shield_changed")])
	_game.sell_item(first)
	_check(is_zero_approx(_player.max_shield) and is_zero_approx(_player.shield), "Ohne Sicherheitsglas: Schild 0 von 0.")
	_check(_last("player_shield_changed") == [0.0, 0.0], "player_shield_changed(0, 0), war %s." % [_last("player_shield_changed")])
	_reset_records()
	_player.take_damage(5.0)
	_check(is_equal_approx(_player.hp, 80.0) and _count("player_shield_changed") == 0, "Ohne Schild trifft der Schaden wieder das Leben.")

	# Ein neuer Lauf beginnt mit vollem Schild.
	_give("shield", 3)
	_check(is_equal_approx(_player.max_shield, 40.0) and is_zero_approx(_player.shield), "Sicherheitsglas Selten: 40 Punkte, leer.")
	_reset_records()
	_events.emit_signal("run_started")
	_check(_player.shield == 40.0 and _player.max_shield == 40.0, "run_started: volles Schild (40 von 40), war %s / %s." % [_player.shield, _player.max_shield])
	_check(_last("player_shield_changed") == [40.0, 40.0], "run_started meldet das volle Schild, war %s." % [_last("player_shield_changed")])
	_check(is_equal_approx(_player.hp, 100.0), "run_started: volles Leben.")


## Schild über Game.upgrades (ohne Rucksack) und der Tod durch das Schild hindurch.
func _test_shield_general_and_death() -> void:
	_reset_records()
	_game.start_run(11)
	await _settle()
	_check(is_zero_approx(_player.max_shield) and is_zero_approx(_player.shield), "Neuer Lauf ohne Gegenstand: kein Schild mehr.")
	_check(_last("player_shield_changed") == [0.0, 0.0], "Der neue Lauf meldet das verlorene Schild (0, 0).")
	_game.upgrades.add_levels("shield", 2)
	_events.emit_signal("build_changed")
	_check(is_equal_approx(_player.max_shield, 30.0) and is_zero_approx(_player.shield), "Stufe 2 über Game.upgrades: 30 Punkte, leer.")
	_events.emit_signal("run_started")
	_check(_player.shield == 30.0, "run_started füllt das Schild auf 30.")
	_reset_records()
	_player.take_damage(500.0)
	_check(_player.is_dead and is_zero_approx(_player.hp) and is_zero_approx(_player.shield),
		"Tödlicher Schlag durch das Schild: tot, Leben 0, Schild 0.")
	_check(_journal == ["player_damaged", "player_shield_changed", "player_health_changed", "player_died"],
		"Signale beim Tod mit Schild, war %s." % [_journal])
	_check(_received.get("player_damaged", []) == [[500.0]] and _count("player_died") == 1, "player_damaged(500), player_died genau einmal.")
	_check(_game.state == _game.State.GAME_OVER, "Der Tod beendet den Lauf.")


## Notausgang: Strecke, Richtung, Ladungen, Abklingzeit, Unverwundbarkeit, Kamera.
func _test_dash() -> void:
	_game.start_run(11)
	await _settle()
	await _place_player(Vector3(0.0, 0.0, 0.0))
	await physics_frame
	_reset_records()
	var given_time: float = _clock.time
	var first: int = _give("dash", 1)
	_check(_player.max_dash_charges == 1 and _player.dash_charges == 0,
		"Neuer Notausgang: ein Sprung möglich, die Ladung kommt leer. War %d / %d." % [_player.dash_charges, _player.max_dash_charges])
	_check(_last("dash_charges_changed") == [0, 1], "dash_charges_changed(0, 1), war %s." % [_last("dash_charges_changed")])
	_check(not _player.try_dash(), "Ohne Ladung kein Sprung.")
	await _idle_until(given_time + 4.0 - 0.3)
	_check(_player.dash_charges == 0, "Vor Ablauf der Abklingzeit (4 s) ist die Ladung noch nicht da.")
	await _idle_until(given_time + 4.0 + 0.2)
	_check(_player.dash_charges == 1 and _last("dash_charges_changed") == [1, 1],
		"Nach 4 s ist die Ladung da: dash_charges_changed(1, 1), war %s." % [_last("dash_charges_changed")])

	# Sprung ohne Eingabe: geradeaus in Blickrichtung (-Z).
	await _ticks(10)
	var camera: Camera3D = _player.get_camera()
	var base_fov: float = camera.fov
	var start: Vector3 = _player.global_position
	_reset_records()
	var dash_time: float = _clock.time
	_check(_player.try_dash(), "Mit Ladung gelingt der Sprung.")
	_check(_player.is_dashing(), "is_dashing ist während des Sprungs wahr.")
	_check(_player.dash_charges == 0 and _last("dash_charges_changed") == [0, 1], "Der Sprung kostet eine Ladung: dash_charges_changed(0, 1).")
	_check(_count("player_dashed") == 1, "player_dashed kommt genau einmal.")
	_check(not _player.try_dash() and _count("player_dashed") == 1, "Während des Sprungs gibt es keinen zweiten.")
	# Kein Schaden im Sprung.
	_player.take_damage(50.0)
	_check(is_equal_approx(_player.hp, 100.0) and _count("player_damaged") == 0, "Im Sprung nimmt der Spieler keinen Schaden.")
	var max_fov: float = base_fov
	var dash_ticks: int = 0
	while _player.is_dashing() and dash_ticks < 60:
		await physics_frame
		dash_ticks += 1
		max_fov = maxf(max_fov, camera.fov)
	var moved: Vector3 = _player.global_position - start
	_near(-moved.z, DASH_DISTANCE, 0.3, "Sprung ohne Eingabe: Strecke DASH_SPEED * DASH_TIME nach vorn (-Z)")
	_check(absf(moved.x) < 0.05 and absf(moved.y) < 0.05, "Der Sprung geht geradeaus und bleibt am Boden, war %s." % moved)
	_near(float(dash_ticks) / float(_ticks_per_second), Balance.DASH_TIME, 0.035, "Der Sprung dauert DASH_TIME")
	_check(max_fov > base_fov + 2.0, "Das Sichtfeld weitet sich im Sprung, war höchstens %s bei %s." % [max_fov, base_fov])
	# Danach wieder verwundbar, der Spieler rutscht nur kurz nach.
	_player.take_damage(10.0)
	_check(is_equal_approx(_player.hp, 90.0), "Nach dem Sprung nimmt der Spieler wieder Schaden.")
	await _ticks(40)
	var rest: float = start.z - _player.global_position.z
	_check(rest >= -moved.z - 0.01 and rest < DASH_DISTANCE + 0.6, "Nach dem Sprung rutscht der Spieler höchstens kurz nach, war %s m." % rest)
	_check(_flat_speed() < 0.05, "Ohne Eingabe steht der Spieler danach still.")
	await _idle(1.5)
	_near(camera.fov, base_fov, 0.3, "Das Sichtfeld kehrt nach dem Sprung zurück")
	# Abklingzeit: Die Ladung kommt 4 s nach dem Sprung zurück.
	await _idle_until(dash_time + 4.0 - 0.3)
	_check(_player.dash_charges == 0, "3,7 s nach dem Sprung fehlt die Ladung noch.")
	await _idle_until(dash_time + 4.0 + 0.2)
	_check(_player.dash_charges == 1, "4,2 s nach dem Sprung ist die Ladung wieder da.")

	# Sprung mit Eingabe: in Richtung der Bewegungstasten (rechts = +X bei Blick nach -Z).
	await _ticks(5)
	Input.action_press("move_right")
	start = _player.global_position
	_reset_records()
	_check(_player.try_dash(), "Sprung mit gedrückter Taste nach rechts.")
	await _wait_dash_end()
	moved = _player.global_position - start
	_near(moved.x, DASH_DISTANCE, 0.3, "Sprung mit Eingabe: Strecke in Richtung der Eingabe (+X)")
	_check(absf(moved.z) < 0.05, "Der Sprung nach rechts weicht nicht nach vorn oder hinten ab, war %s." % moved)
	Input.action_release("move_right")
	await _ticks(30)

	# Zwei Exemplare: zwei Ladungen, es gilt die kürzere Abklingzeit (2 s bei Legendär).
	_reset_records()
	var second: int = _give("dash", 5)
	_check(_player.max_dash_charges == 2, "Zwei Exemplare geben zwei Sprünge, war %d." % _player.max_dash_charges)
	_check(_player.dash_charges == 0 and _last("dash_charges_changed") == [0, 2],
		"Die zweite Ladung kommt leer: dash_charges_changed(0, 2), war %s." % [_last("dash_charges_changed")])
	# Ein neuer Lauf beginnt mit allen Ladungen.
	_events.emit_signal("run_started")
	_check(_player.dash_charges == 2 and _last("dash_charges_changed") == [2, 2],
		"run_started: alle Ladungen (2 von 2), war %s." % [_last("dash_charges_changed")])
	# Ohne Eingabe folgt der Sprung dem Blick: jetzt nach +X.
	_player.look_at_point(_player.global_position + Vector3(10.0, Balance.PLAYER_EYE_HEIGHT, 0.0))
	await _settle()
	await physics_frame
	_reset_records()
	start = _player.global_position
	dash_time = _clock.time
	_check(_player.try_dash() and _player.dash_charges == 1, "Erster von zwei Sprüngen: eine Ladung bleibt.")
	await _wait_dash_end()
	moved = _player.global_position - start
	_near(moved.x, DASH_DISTANCE, 0.3, "Ohne Eingabe folgt der Sprung dem Blick (+X)")
	_check(absf(moved.z) < 0.05, "Der Sprung in Blickrichtung weicht nicht zur Seite ab, war %s." % moved)
	# Der zweite Sprung über die Taste Q.
	await _tap("dash")
	_check(_count("player_dashed") == 2 and _player.dash_charges == 0, "Die Taste Q löst den zweiten Sprung aus, Ladungen: %d." % _player.dash_charges)
	await _wait_dash_end()
	_check(not _player.try_dash() and _count("player_dashed") == 2, "Ohne Ladung gibt es keinen dritten Sprung.")
	# Die Ladungen kommen nacheinander zurück, jede nach 2 s.
	await _idle_until(dash_time + 2.0 - 0.2)
	_check(_player.dash_charges == 0, "1,8 s nach dem ersten Sprung ist noch keine Ladung zurück.")
	await _idle_until(dash_time + 2.0 + 0.2)
	_check(_player.dash_charges == 1, "Nach 2 s (kürzere Abklingzeit) ist die erste Ladung zurück, war %d." % _player.dash_charges)
	await _idle_until(dash_time + 4.0 - 0.2)
	_check(_player.dash_charges == 1, "Die zweite Ladung lädt erst nach der ersten: nach 3,8 s noch eine.")
	await _idle_until(dash_time + 4.0 + 0.2)
	_check(_player.dash_charges == 2, "Nach 4 s sind beide Ladungen zurück, war %d." % _player.dash_charges)
	_check(_received.get("dash_charges_changed", []) == [[1, 2], [0, 2], [1, 2], [2, 2]],
		"dash_charges_changed der Reihe nach, war %s." % [_received.get("dash_charges_changed", [])])
	await _idle(1.0)
	_check(_player.dash_charges == 2 and _count("dash_charges_changed") == 4, "Volle Ladungen laden nicht weiter.")

	# Außerhalb von PLAYING kein Sprung.
	_reset_records()
	_game.set_paused(true)
	_check(not _player.try_dash() and _player.dash_charges == 2, "In der Pause kein Sprung.")
	Input.action_press("dash")
	await _frames(3)
	Input.action_release("dash")
	await _frames(2)
	_game.set_paused(false)
	await _frames(3)
	_check(_count("player_dashed") == 0 and _player.dash_charges == 2, "Die Taste Q in der Pause löst keinen Sprung aus.")

	# Verkauf: weniger Exemplare, weniger Ladungen. Ohne Notausgang kein Sprung.
	_game.sell_item(second)
	_check(_player.max_dash_charges == 1 and _player.dash_charges == 1 and _last("dash_charges_changed") == [1, 1],
		"Ein Exemplar weniger: eine Ladung von einer, war %s." % [_last("dash_charges_changed")])
	_game.sell_item(first)
	_check(_player.max_dash_charges == 0 and _player.dash_charges == 0 and _last("dash_charges_changed") == [0, 0],
		"Ohne Notausgang: dash_charges_changed(0, 0), war %s." % [_last("dash_charges_changed")])
	_check(not _player.try_dash() and _count("player_dashed") == 0, "Ohne Notausgang kein Sprung mehr.")

	# Tote springen nicht.
	_give("dash", 3)
	_events.emit_signal("run_started")
	_check(_player.dash_charges == 1 and _player.max_dash_charges == 1, "Neuer Notausgang und run_started: eine Ladung.")
	_reset_records()
	_player.take_damage(500.0)
	_check(_player.is_dead, "Der Spieler ist tot.")
	_check(not _player.try_dash() and _count("player_dashed") == 0 and _player.dash_charges == 1, "Tote springen nicht.")
	# Ein neuer Lauf ohne Gegenstand nimmt die Sprünge weg.
	_game.start_run(11)
	await _settle()
	_check(_player.max_dash_charges == 0 and _last("dash_charges_changed") == [0, 0], "Neuer Lauf ohne Gegenstand: keine Sprünge.")


## Ersatz-Zombie an dieser Stelle (Füße).
func _push_zombie(at: Vector3) -> PushZombie:
	var zombie: PushZombie = PushZombie.new()
	zombie.position = at
	root.add_child(zombie)
	return zombie


## Zweite Staffel: leere neue Ladung, Rückkehr nach Wellen, tödlicher Treffer, Druckwelle,
## Unverwundbarkeit, mehrere Exemplare, Verkauf, Ablage, Kombinieren, neuer Lauf.
func _test_revive() -> void:
	_reset_records()
	_game.start_run(11)
	await _settle()
	await _place_player(Vector3(0.0, 0.0, 80.0))
	await physics_frame
	_check(_player.revive_charges == 0 and _player.max_revive_charges == 0 and _player.get_revive_waves_left().is_empty(),
		"Ohne Zweite Staffel gibt es keine Ladung.")
	_check(_only_zero("revive_charges_changed") and _count("player_revived") == 0, "Ohne Zweite Staffel kommt kein Signal mit Werten.")
	_events.emit_signal("wave_cleared", 1)
	_check(_only_zero("revive_charges_changed"), "Ohne Zweite Staffel ändert ein Wellenende nichts.")

	# Neu eingeräumt: Die Ladung kommt leer und wartet ihre Wellen ab (Gewöhnlich: 5).
	_reset_records()
	var waves: int = roundi(UpgradeDefs.value("revive", "waves", 1))
	var common: int = _give("revive", 1)
	_check(_player.max_revive_charges == 1 and _player.revive_charges == 0,
		"Neue Zweite Staffel: eine Ladung, sie kommt leer. War %d / %d." % [_player.revive_charges, _player.max_revive_charges])
	_check(_last("revive_charges_changed") == [0, 1], "revive_charges_changed(0, 1), war %s." % [_last("revive_charges_changed")])
	_check(_player.get_revive_waves_left() == [waves] and waves == 5, "Sie kommt nach %d geschafften Wellen, war %s." % [waves, _player.get_revive_waves_left()])
	for i: int in waves - 1:
		_events.emit_signal("wave_cleared", i + 1)
	_check(_player.revive_charges == 0 and _player.get_revive_waves_left() == [1] and _count("revive_charges_changed") == 1,
		"Nach %d Wellen fehlt noch eine, es kommt kein neues Signal." % (waves - 1))
	_events.emit_signal("wave_cleared", waves)
	_check(_player.revive_charges == 1 and _last("revive_charges_changed") == [1, 1] and _player.get_revive_waves_left() == [0],
		"Nach %d Wellen ist die Ladung bereit: revive_charges_changed(1, 1)." % waves)
	_events.emit_signal("wave_cleared", waves + 1)
	_check(_player.revive_charges == 1 and _count("revive_charges_changed") == 2, "Eine bereite Ladung ändert sich am Wellenende nicht.")

	# Gewöhnlicher Schaden verbraucht keine Ladung.
	_reset_records()
	_player.take_damage(30.0)
	_check(is_equal_approx(_player.hp, 70.0) and _player.revive_charges == 1 and _count("revive_charges_changed") == 0 and _count("player_revived") == 0,
		"Ein gewöhnlicher Treffer verbraucht keine Ladung.")
	await _idle(Balance.PLAYER_HIT_INVULNERABILITY + 0.1)

	# Tödlicher Treffer: Der Spieler steht mit 30 % Leben wieder, die Zombies fliegen weg.
	var feet: Vector3 = _player.global_position
	var radius: float = Balance.REVIVE_SHOCKWAVE_RADIUS
	var front: PushZombie = _push_zombie(feet + Vector3(0.0, 0.0, -3.0))
	var side: PushZombie = _push_zombie(feet + Vector3(radius - 0.2, 0.0, 0.0))
	var outside: PushZombie = _push_zombie(feet + Vector3(0.0, 0.0, -(radius + 0.5)))
	var corpse: PushZombie = _push_zombie(feet + Vector3(-2.0, 0.0, 0.0))
	corpse.is_dead = true
	_reset_records()
	var hit_time: float = _clock.time
	_player.take_damage(500.0)
	var revived_hp: float = _player.max_hp * Balance.REVIVE_HP_SHARE
	_check(not _player.is_dead and is_equal_approx(_player.hp, revived_hp) and is_equal_approx(revived_hp, 30.0),
		"Zweite Staffel: Der tödliche Treffer tötet nicht, das Leben steht auf 30 %%. War %s." % _player.hp)
	_check(_game.state == _game.State.PLAYING and _count("player_died") == 0, "Der Lauf geht weiter, player_died kommt nicht.")
	_check(_journal == ["player_damaged", "player_health_changed", "revive_charges_changed", "player_revived"],
		"Signale beim Aufstehen: damaged, health, revive_charges, revived. War %s." % [_journal])
	_check(_received.get("player_damaged", []) == [[500.0]] and _last("player_health_changed") == [30.0, 100.0],
		"player_damaged(500), player_health_changed meldet schon das neue Leben (30, 100).")
	_check(_player.revive_charges == 0 and _last("revive_charges_changed") == [0, 1] and _player.get_revive_waves_left() == [waves],
		"Die Ladung ist verbraucht und wartet wieder %d Wellen." % waves)
	# Druckwelle: stößt weg, macht keinen Schaden.
	var push: float = Balance.REVIVE_SHOCKWAVE_KNOCKBACK
	_check(front.knockback.distance_to(Vector3(0.0, 0.0, -push)) < 0.01 and side.knockback.distance_to(Vector3(push, 0.0, 0.0)) < 0.01,
		"Die Druckwelle stößt Zombies im Umkreis mit %s m/s vom Spieler weg, war %s." % [push, front.knockback])
	_check(outside.knockback == Vector3.ZERO and corpse.knockback == Vector3.ZERO, "Außerhalb von %s m und bei Toten wirkt sie nicht." % radius)
	_check(is_zero_approx(front.damage_taken) and is_zero_approx(side.damage_taken) and is_zero_approx(Balance.REVIVE_SHOCKWAVE_DAMAGE), "Die Druckwelle macht keinen Schaden.")
	# Die Druckwelle ist zu sehen: Ringe am Boden und eine Wand, die mitläuft. Nur Bild, ohne Kollision.
	var wave_parts: Array[Node] = _shockwave_parts()
	var wave_rings: int = 0
	var wave_bands: int = 0
	var wave_colliders: int = 0
	for part: Node in wave_parts:
		if String(part.name).contains("Ring"):
			wave_rings += 1
		if String(part.name).contains("ShockwaveBand"):
			wave_bands += 1
		if part is CollisionObject3D or not part.find_children("*", "CollisionObject3D", true, false).is_empty():
			wave_colliders += 1
	# (Godot benennt gleichnamige Geschwister um: Am Namen ist nur der erste Ring zu erkennen.)
	_check(wave_rings >= 1 and wave_bands == 1 and wave_colliders == 0,
		"Die Druckwelle ist als Ring mit mitlaufender Wand zu sehen und hat keine Kollision (Ringe %d, Wand %d, mit Kollision %d)." % [wave_rings, wave_bands, wave_colliders])
	# Unverwundbar für REVIVE_INVULNERABILITY Sekunden.
	_check(_player.is_invulnerable(), "Nach dem Aufstehen ist der Spieler unverwundbar.")
	await _idle_until(hit_time + Balance.REVIVE_INVULNERABILITY - 0.2)
	_check(_shockwave_parts().is_empty() or Balance.REVIVE_INVULNERABILITY < 0.8, "Das Bild der Druckwelle hat sich selbst weggeräumt, übrig: %d." % _shockwave_parts().size())
	_player.take_damage(50.0)
	_check(is_equal_approx(_player.hp, revived_hp) and _player.is_invulnerable(), "Kurz vor Ablauf von %s s nimmt er noch keinen Schaden." % Balance.REVIVE_INVULNERABILITY)
	await _idle_until(hit_time + Balance.REVIVE_INVULNERABILITY + 0.1)
	_check(not _player.is_invulnerable(), "Danach ist er wieder verwundbar.")
	_player.take_damage(10.0)
	_check(is_equal_approx(_player.hp, revived_hp - 10.0), "Schaden trifft wieder das Leben.")
	# Ohne bereite Ladung tötet der nächste tödliche Treffer.
	await _idle(Balance.PLAYER_HIT_INVULNERABILITY + 0.1)
	_reset_records()
	_player.take_damage(500.0)
	_check(_player.is_dead and _count("player_died") == 1 and _count("player_revived") == 0 and _game.state == _game.State.GAME_OVER,
		"Ohne bereite Ladung stirbt der Spieler wie bisher.")
	for zombie: PushZombie in [front, side, outside, corpse]:
		zombie.free()

	# Durch das Schild hindurch: Auch dann fängt die Zweite Staffel den Tod ab.
	_game.start_run(11)
	await _settle()
	_give("shield", 1)
	_give("revive", 5)
	_events.emit_signal("run_started")
	await physics_frame
	_check(_player.revive_charges == 1 and _player.max_revive_charges == 1 and _player.shield == 20.0, "run_started: Ladung bereit, Schild voll.")
	_reset_records()
	_player.take_damage(500.0)
	_check(not _player.is_dead and is_zero_approx(_player.shield) and is_equal_approx(_player.hp, 30.0), "Tödlicher Treffer durch das Schild: Schild 0, Leben 30.")
	_check(_journal == ["player_damaged", "player_shield_changed", "player_health_changed", "revive_charges_changed", "player_revived"],
		"Signale mit Schild, war %s." % [_journal])
	_check(_player.get_revive_waves_left() == [roundi(UpgradeDefs.value("revive", "waves", 5))], "Legendär wartet 3 Wellen, war %s." % [_player.get_revive_waves_left()])

	# Zwei Exemplare (Gewöhnlich 5 Wellen, Legendär 3): zwei Ladungen, die schnellere geht zuerst.
	_game.start_run(11)
	await _settle()
	_reset_records()
	common = _give("revive", 1)
	var legendary: int = _give("revive", 5)
	_check(_player.max_revive_charges == 2 and _player.revive_charges == 0 and _player.get_revive_waves_left() == [5, 3],
		"Zwei Exemplare: zwei leere Ladungen, die 5 und 3 Wellen warten. War %s." % [_player.get_revive_waves_left()])
	_events.emit_signal("run_started")
	_check(_player.revive_charges == 2 and _last("revive_charges_changed") == [2, 2] and _player.get_revive_waves_left() == [0, 0],
		"run_started: alle Ladungen bereit (2 von 2).")
	await physics_frame
	_reset_records()
	_player.take_damage(500.0)
	_check(not _player.is_dead and _player.revive_charges == 1 and _player.get_revive_waves_left() == [0, 3],
		"Erster tödlicher Treffer: Die Ladung mit der kürzeren Wartezeit (3 Wellen) geht zuerst. War %s." % [_player.get_revive_waves_left()])
	await _idle(Balance.REVIVE_INVULNERABILITY + 0.1)
	_player.take_damage(500.0)
	_check(not _player.is_dead and _player.revive_charges == 0 and _player.get_revive_waves_left() == [5, 3], "Zweiter tödlicher Treffer: auch die zweite Ladung fängt ihn ab.")
	_check(_count("player_revived") == 2 and _count("player_died") == 0, "player_revived kommt je abgefangenem Treffer.")
	for i: int in 3:
		_events.emit_signal("wave_cleared", i + 1)
	_check(_player.revive_charges == 1 and _player.get_revive_waves_left() == [2, 0], "Nach 3 Wellen ist die legendäre Ladung zurück.")
	for i: int in 2:
		_events.emit_signal("wave_cleared", i + 4)
	_check(_player.revive_charges == 2 and _player.get_revive_waves_left() == [0, 0], "Nach 5 Wellen sind beide zurück.")
	_check(_received.get("revive_charges_changed", []) == [[1, 2], [0, 2], [1, 2], [2, 2]],
		"revive_charges_changed der Reihe nach, war %s." % [_received.get("revive_charges_changed", [])])
	# Verkauf: ein Exemplar weniger, eine Ladung weniger.
	_game.sell_item(legendary)
	_check(_player.max_revive_charges == 1 and _player.revive_charges == 1 and _last("revive_charges_changed") == [1, 1], "Ein Exemplar verkauft: eine Ladung von einer.")
	# Aus- und Einräumen gibt keine Gratis-Ladung.
	await _idle(Balance.REVIVE_INVULNERABILITY + 0.1)
	_player.take_damage(500.0)
	_check(not _player.is_dead and _player.revive_charges == 0, "Die letzte Ladung ist verbraucht.")
	_game.backpack.store(common)
	_game.sync_build()
	_check(_player.max_revive_charges == 0 and _last("revive_charges_changed") == [0, 0], "In der Ablage wirkt die Zweite Staffel nicht.")
	_check(_game.backpack.auto_place(common), "Die Zweite Staffel passt wieder ins Raster.")
	_game.sync_build()
	_check(_player.max_revive_charges == 1 and _player.revive_charges == 0 and _player.get_revive_waves_left() == [5],
		"Wieder eingeräumt kommt die Ladung leer und wartet neu.")
	# Kombinieren: Die Ladung behält ihren Stand, die Wartezeit ist höchstens die der neuen Rarität.
	var spare: int = _game.backpack.add_item("revive", 1)
	_check(_game.backpack.merge(spare, common), "Zwei gewöhnliche Zweite Staffeln lassen sich kombinieren.")
	_game.sync_build()
	var uncommon_waves: int = roundi(UpgradeDefs.value("revive", "waves", 2))
	_check(_player.max_revive_charges == 1 and _player.revive_charges == 0 and _player.get_revive_waves_left() == [uncommon_waves],
		"Kombiniert (Ungewöhnlich): weiter eine leere Ladung, sie wartet %d Wellen. War %s." % [uncommon_waves, _player.get_revive_waves_left()])
	# Über Game.upgrades (ohne Rucksack): Stufe als ein Exemplar.
	_game.start_run(11)
	await _settle()
	_check(_player.max_revive_charges == 0 and _last("revive_charges_changed") == [0, 0], "Neuer Lauf ohne Gegenstand: keine Ladung.")
	_game.upgrades.add_levels("revive", 3)
	_events.emit_signal("build_changed")
	_check(_player.max_revive_charges == 1 and _player.revive_charges == 0, "Stufe 3 über Game.upgrades: eine leere Ladung.")
	_events.emit_signal("run_started")
	_check(_player.revive_charges == 1, "run_started macht sie bereit.")
	# Ein toter Spieler sammelt keine Wellen mehr.
	await physics_frame
	_player.take_damage(500.0)
	await _idle(Balance.REVIVE_INVULNERABILITY + 0.1)
	_player.take_damage(500.0)
	_check(_player.is_dead and _player.revive_charges == 0, "Zweiter tödlicher Treffer ohne Ladung: tot.")
	_game.start_run(11)
	await _settle()
	_check(_player.max_revive_charges == 0 and not _player.is_dead, "Neuer Lauf: wieder ohne Zweite Staffel und am Leben.")


## Schild-Anzeige und Sprung-Kästchen im HUD.
func _test_hud() -> void:
	_game.start_run(11)
	await _settle()
	var hud_script: GDScript = load("res://scripts/ui/hud.gd")
	var hud: Node = hud_script.new()
	root.add_child(hud)
	await _frames(1)
	var shield_box: Control = hud.get("shield_box") as Control
	var shield_label: Label = hud.get("shield_label") as Label
	var shield_max_label: Label = hud.get("shield_max_label") as Label
	var shield_bar: Control = hud.get("shield_bar") as Control
	var dash_box: Control = hud.get("dash_box") as Control
	var dash_pips: Control = hud.get("dash_pips") as Control
	var health_bar: Control = hud.get("health_bar") as Control
	_check(shield_box != null and shield_label != null and shield_max_label != null and shield_bar != null,
		"Das HUD hat shield_box, shield_label, shield_max_label und shield_bar.")
	_check(dash_box != null and dash_pips != null, "Das HUD hat dash_box und dash_pips.")
	if shield_box == null or shield_label == null or shield_max_label == null or shield_bar == null \
			or dash_box == null or dash_pips == null or health_bar == null:
		hud.queue_free()
		return
	# Ohne Gegenstände ist beides aus.
	_check(not shield_box.is_visible_in_tree(), "Ohne Schild ist die Schild-Anzeige aus.")
	_check(not dash_box.is_visible_in_tree(), "Ohne Notausgang ist die Sprung-Anzeige aus.")
	_check((hud.get("health_label") as Label).text == "100", "Das Leben steht weiter da.")

	# Schild über das Signal.
	_events.emit_signal("player_shield_changed", 30.0, 40.0)
	_check(shield_box.is_visible_in_tree(), "Mit Schild ist die Schild-Anzeige zu sehen.")
	_check(shield_label.text == "30" and shield_max_label.text == "/ 40",
		"Schild-Anzeige 30 / 40, war '%s' '%s'." % [shield_label.text, shield_max_label.text])
	_near(float(shield_bar.get("ratio")), 0.75, 0.001, "Der Schild-Balken steht bei drei Vierteln")
	_check(shield_bar.get("fill_color") != health_bar.get("fill_color")
		and shield_label.get_theme_color("font_color") != (hud.get("health_label") as Label).get_theme_color("font_color"),
		"Das Schild hat eine andere Farbe als das Leben.")
	_events.emit_signal("player_shield_changed", 12.4, 40.0)
	_check(shield_label.text == "12", "Angebrochene Schild-Punkte werden abgerundet, war '%s'." % shield_label.text)
	_events.emit_signal("player_shield_changed", 0.0, 40.0)
	_check(shield_box.is_visible_in_tree() and shield_label.text == "0", "Ein leeres Schild bleibt sichtbar und zeigt 0.")
	_near(float(shield_bar.get("ratio")), 0.0, 0.001, "Der Balken eines leeren Schilds ist leer")
	_events.emit_signal("player_shield_changed", 0.0, 0.0)
	_check(not shield_box.is_visible_in_tree(), "Ohne Höchstwert verschwindet die Schild-Anzeige.")

	# Sprünge über das Signal.
	_events.emit_signal("dash_charges_changed", 1, 2)
	_check(dash_box.is_visible_in_tree(), "Mit Notausgang ist die Sprung-Anzeige zu sehen.")
	_check(int(dash_pips.get("max_level")) == 2 and int(dash_pips.get("level")) == 1,
		"Zwei Kästchen, eines gefüllt. War %s von %s." % [dash_pips.get("level"), dash_pips.get("max_level")])
	var width_two: float = dash_pips.size.x
	_events.emit_signal("dash_charges_changed", 3, 3)
	_check(int(dash_pips.get("max_level")) == 3 and int(dash_pips.get("level")) == 3, "Drei Kästchen, alle gefüllt.")
	_check(dash_pips.size.x > width_two, "Mehr Sprünge brauchen mehr Platz.")
	_events.emit_signal("dash_charges_changed", 0, 1)
	_check(dash_box.is_visible_in_tree() and int(dash_pips.get("max_level")) == 1 and int(dash_pips.get("level")) == 0,
		"Ein leeres Kästchen bleibt sichtbar.")
	_events.emit_signal("dash_charges_changed", 0, 0)
	_check(not dash_box.is_visible_in_tree(), "Ohne Notausgang verschwindet die Sprung-Anzeige.")

	# Mit echten Gegenständen: Das HUD folgt dem Spieler.
	_give("shield", 1)
	_give("dash", 1)
	_check(shield_box.is_visible_in_tree() and shield_label.text == "0" and shield_max_label.text == "/ 20",
		"Sicherheitsglas im Rucksack: Anzeige 0 / 20, war '%s' '%s'." % [shield_label.text, shield_max_label.text])
	_check(dash_box.is_visible_in_tree() and int(dash_pips.get("max_level")) == 1 and int(dash_pips.get("level")) == 0,
		"Notausgang im Rucksack: ein leeres Kästchen.")
	_events.emit_signal("run_started")
	await _frames(1)
	_check(shield_label.text == "20" and shield_max_label.text == "/ 20", "run_started: Anzeige 20 / 20, war '%s'." % shield_label.text)
	_near(float(shield_bar.get("ratio")), 1.0, 0.001, "run_started: voller Schild-Balken")
	_check(int(dash_pips.get("level")) == 1 and int(dash_pips.get("max_level")) == 1, "run_started: ein gefülltes Kästchen.")
	# Schaden und Sprung kommen an.
	await physics_frame
	_player.take_damage(5.0)
	_check(shield_label.text == "15", "5 Schaden: Anzeige 15, war '%s'." % shield_label.text)
	_check(_player.try_dash(), "Sprung für die Anzeige.")
	_check(int(dash_pips.get("level")) == 0, "Nach dem Sprung ist das Kästchen leer.")
	await _wait_dash_end()

	# Ein HUD, das erst jetzt entsteht, holt die Werte vom Spieler.
	var late_hud: Node = hud_script.new()
	root.add_child(late_hud)
	await _frames(1)
	var late_shield: Label = late_hud.get("shield_label") as Label
	var late_pips: Control = late_hud.get("dash_pips") as Control
	_check((late_hud.get("shield_box") as Control).is_visible_in_tree() and late_shield.text == "15"
		and (late_hud.get("shield_max_label") as Label).text == "/ 20", "Neues HUD holt das Schild vom Spieler, war '%s'." % late_shield.text)
	_check((late_hud.get("dash_box") as Control).is_visible_in_tree() and int(late_pips.get("max_level")) == 1
		and int(late_pips.get("level")) == 0, "Neues HUD holt die Sprünge vom Spieler.")
	late_hud.queue_free()
	await _frames(2)

	# Ein neuer Lauf ohne Gegenstände blendet beides aus.
	_game.start_run(11)
	await _settle()
	_check(not shield_box.is_visible_in_tree() and not dash_box.is_visible_in_tree(),
		"Neuer Lauf ohne Gegenstände: Schild- und Sprung-Anzeige sind aus.")
	_check((hud.get("health_label") as Label).text == "100", "Neuer Lauf: Leben 100.")
	# Ohne Spieler gelten die Startwerte (kein Schild, keine Sprünge).
	_events.emit_signal("player_shield_changed", 10.0, 20.0)
	_events.emit_signal("dash_charges_changed", 1, 1)
	var saved_player: Node3D = _game.player
	_game.player = null
	_events.emit_signal("run_started")
	_check(not shield_box.is_visible_in_tree() and not dash_box.is_visible_in_tree(), "Ohne Spieler stellt run_started beide Anzeigen aus.")
	_game.player = saved_player
	hud.queue_free()
	await _frames(2)
	hud_script.call("clear_font_cache")
	await _frames(2)


# --- Hilfen ---


func _reset_records() -> void:
	_received.clear()
	_journal.clear()


func _record(signal_name: String, args: Array) -> void:
	if not _received.has(signal_name):
		_received[signal_name] = []
	(_received[signal_name] as Array).append(args)
	_journal.append(signal_name)


func _count(signal_name: String) -> int:
	return (_received.get(signal_name, []) as Array).size()


## Argumente des letzten Signals mit diesem Namen, [] wenn keines kam.
func _last(signal_name: String) -> Array:
	var list: Array = _received.get(signal_name, [])
	if list.is_empty():
		return []
	return list[list.size() - 1]


## Kam dieses Signal gar nicht oder nur mit lauter Nullen?
func _only_zero(signal_name: String) -> bool:
	for args: Array in _received.get(signal_name, []) as Array:
		for value: Variant in args:
			if not is_zero_approx(float(value)):
				return false
	return true


func _near(value: float, expected: float, tolerance: float, message: String) -> void:
	_check(absf(value - expected) <= tolerance, "%s: erwartet %s (± %s), war %s." % [message, expected, tolerance, value])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
