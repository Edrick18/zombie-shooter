extends SceneTree
## Tests für das Modul Zombies: zombie.gd, zombie_spawner.gd, wave_manager.gd.
## Baut eine eigene kleine Welt (Boden, Spawnpunkte, Ersatz-Spieler), damit der Test nicht von
## Level, Spieler oder Oberfläche abhängt.
##
## Zeit: Der Test wartet nur für Bewegung auf echte Bilder. Alles andere (Brand, Wellen,
## Countdown, Festhänge-Sicherung) treibt er selbst an, indem er _physics_process bzw. _process
## mit festen Schritten aufruft. So läuft er schnell und bei jeder Bildrate gleich.
##
## Die Autoloads holt er über root.get_node, die Modul-Skripte lädt er erst zur Laufzeit
## (ein -s-Skript kennt Game und Events beim Übersetzen noch nicht).

const Balance := preload("res://scripts/core/balance.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")

const ZOMBIE_PATH: String = "res://scripts/game/zombies/zombie.gd"
const SPAWNER_PATH: String = "res://scripts/game/zombies/zombie_spawner.gd"
const WAVE_MANAGER_PATH: String = "res://scripts/game/zombies/wave_manager.gd"
const EPSILON: float = 0.01


## Ersatz-Spieler: merkt sich Schläge und Heilung.
class FakePlayer:
	extends Node3D
	var hp: float = 100.0
	var max_hp: float = 100.0
	var is_dead: bool = false
	var hits: Array[float] = []
	var healed: float = 0.0

	func take_damage(amount: float) -> void:
		hits.append(amount)

	func heal(amount: float) -> void:
		healed += amount


var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
var _zombie_script: GDScript
var _world: Node3D
var _zombies_root: Node3D
var _player: FakePlayer
var _spawner: Node
var _waves: Node
var _zone1: Array[Marker3D] = []
var _zone2: Array[Marker3D] = []

var _damaged: Array[Dictionary] = []
var _killed: Array[Dictionary] = []
var _spawned: Array[Node3D] = []
var _wave_started: Array[Array] = []
var _wave_cleared: Array[int] = []
var _left: Array[int] = []
var _ticks: Array[int] = []
var _banners: Array[String] = []
## Wird in zombie_killed geprüft: Greift ein Empfänger den Toten noch einmal an, darf nichts passieren.
var _hit_again_on_kill: bool = false


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum und ihr _ready ist gelaufen.
	await process_frame
	_game = root.get_node_or_null("Game")
	_events = root.get_node_or_null("Events")
	_zombie_script = load(ZOMBIE_PATH) as GDScript
	_check(_game != null and _events != null, "Autoloads Game und Events hängen im Baum.")
	_check(_zombie_script != null, "zombie.gd lädt.")
	if _game != null and _events != null and _zombie_script != null:
		_build_world()
		_listen()
		_game.call("start_run", 11)
		_game.set("player", _player)
		_test_setup_and_shape()
		await _test_damage_and_death()
		_test_burn()
		_test_elite_burn_factor()
		await _test_slow_and_mark()
		await _test_knockback_and_separation()
		await _test_chase_and_attack()
		await _test_no_attack_through_wall()
		_test_spawner()
		_test_wave_flow()
		_test_planned_counts()
		_test_max_alive()
		_test_game_over_and_restart()
		_test_stuck_safety()
		_test_count_repair()
		await _test_navigation_and_hop()
		paused = false
		_world.queue_free()
		await process_frame
	if _failures == 0:
		print("Alle Zombie- und Wellen-Tests bestanden (%d Prüfungen)." % _checks)
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


# --- Aufbau ----------------------------------------------------------------------------------

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "TestWorld"
	root.add_child(_world)
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = Balance.LAYER_WORLD
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_to_group("nav_source")
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	floor_body.add_child(shape)
	_world.add_child(floor_body)
	_zombies_root = Node3D.new()
	_zombies_root.name = "Zombies"
	_world.add_child(_zombies_root)
	_player = FakePlayer.new()
	_player.name = "Player"
	_world.add_child(_player)
	_zone1.append(_add_spawn(Vector3(-12.0, 0.0, -9.0), 1, true))
	_zone1.append(_add_spawn(Vector3(12.0, 0.0, -9.0), 1, true))
	_zone1.append(_add_spawn(Vector3(0.0, 0.0, -13.0), 1, true))
	_zone2.append(_add_spawn(Vector3(-7.0, 0.0, 15.0), 2, false))
	_zone2.append(_add_spawn(Vector3(7.0, 0.0, 15.0), 2, false))
	_spawner = (load(SPAWNER_PATH) as GDScript).new()
	_spawner.name = "ZombieSpawner"
	_spawner.set("zombie_parent", _zombies_root)
	_world.add_child(_spawner)
	_waves = (load(WAVE_MANAGER_PATH) as GDScript).new()
	_waves.name = "WaveManager"
	_waves.set("spawner", _spawner)
	_waves.set("auto_start", false)
	_world.add_child(_waves)


func _add_spawn(position: Vector3, zone: int, active: bool) -> Marker3D:
	var marker: Marker3D = Marker3D.new()
	marker.position = position
	marker.set_meta("zone", zone)
	marker.set_meta("active", active)
	marker.add_to_group("zombie_spawns")
	_world.add_child(marker)
	return marker


func _listen() -> void:
	_events.connect("zombie_damaged", _on_zombie_damaged)
	_events.connect("zombie_killed", _on_zombie_killed)
	_events.connect("zombie_spawned", func(zombie: Node3D) -> void: _spawned.append(zombie))
	_events.connect("wave_started", func(wave: int, total: int) -> void: _wave_started.append([wave, total]))
	_events.connect("wave_cleared", func(wave: int) -> void: _wave_cleared.append(wave))
	_events.connect("zombies_left_changed", func(left: int) -> void: _left.append(left))
	_events.connect("intermission_tick", func(seconds: int) -> void: _ticks.append(seconds))
	_events.connect("banner", func(text: String) -> void: _banners.append(text))


func _on_zombie_damaged(zombie: Node3D, amount: float, info: Dictionary) -> void:
	_damaged.append({"zombie": zombie, "amount": amount, "info": info})


func _on_zombie_killed(zombie: Node3D, info: Dictionary) -> void:
	_killed.append({
		"zombie": zombie,
		"info": info,
		"valid": is_instance_valid(zombie),
		"type": String(zombie.get("zombie_type")) if is_instance_valid(zombie) else "",
	})
	if _hit_again_on_kill and is_instance_valid(zombie):
		zombie.call("take_damage", 5.0, {"source": "explosion"})


func _clear_log() -> void:
	_damaged.clear()
	_killed.clear()
	_spawned.clear()
	_wave_started.clear()
	_wave_cleared.clear()
	_left.clear()
	_ticks.clear()
	_banners.clear()


func _make_zombie(type: String, wave: int, position: Vector3) -> CharacterBody3D:
	var zombie: CharacterBody3D = _zombie_script.new()
	zombie.call("setup", type, wave)
	zombie.position = position
	_zombies_root.add_child(zombie)
	return zombie


## Treibt einen Zombie ohne echte Bilder an: seconds in festen Schritten.
func _step_zombie(zombie: Node, seconds: float, step: float = 0.1) -> void:
	for i: int in roundi(seconds / step):
		if not is_instance_valid(zombie) or zombie.is_queued_for_deletion():
			return
		zombie.call("_physics_process", step)


## Treibt den WaveManager ohne echte Bilder an.
func _step_waves(seconds: float, step: float = 0.1) -> void:
	for i: int in roundi(seconds / step):
		_waves.call("_process", step)


func _alive_zombies() -> Array[Node]:
	return get_nodes_in_group("zombies")


func _kill(zombie: Node) -> void:
	if is_instance_valid(zombie):
		zombie.call("take_damage", float(zombie.get("max_hp")) * 10.0, {"source": "bullet"})


func _remove_all_zombies() -> void:
	for node: Node in _alive_zombies():
		node.call("despawn")


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Der aktive oder inaktive Spawnpunkt, der dieser Stelle am nächsten liegt.
func _nearest_spawn(position: Vector3) -> Marker3D:
	var best: Marker3D = null
	var best_distance: float = INF
	for marker: Marker3D in _zone1 + _zone2:
		var distance: float = _flat_distance(marker.global_position, position)
		if distance < best_distance:
			best_distance = distance
			best = marker
	return best


# --- Zombie ----------------------------------------------------------------------------------

func _test_setup_and_shape() -> void:
	_game.set("player", null)
	var walker: CharacterBody3D = _make_zombie("walker", 1, Vector3(20.0, 0.0, 20.0))
	_check_near(float(walker.get("max_hp")), 60.0, "Schlurfer Welle 1 hat 60 Leben.")
	_check_near(float(walker.get("hp")), 60.0, "Schlurfer startet mit vollem Leben.")
	_check_near(float(walker.get("move_speed")), 1.6, "Schlurfer Welle 1 läuft 1,6 m/s.")
	_check_near(float(walker.get("attack_damage")), 20.0, "Schlurfer schlägt mit 20.")
	_check(walker.is_in_group("zombies"), "Lebender Zombie ist in der Gruppe zombies.")
	_check(walker.collision_layer == Balance.LAYER_ZOMBIES, "Zombie liegt auf Lage 3.")
	_check(walker.collision_mask == Balance.MASK_ZOMBIE, "Zombie hat die Maske 1 + 2 + 3.")
	_check(walker.get_node_or_null("Shape") is CollisionShape3D, "Zombie hat den Knoten Shape.")
	_check(walker.get_node_or_null("Body") is MeshInstance3D, "Zombie hat den Knoten Body.")
	_check(walker.get_node_or_null("NavAgent") is NavigationAgent3D, "Zombie hat einen NavigationAgent3D.")
	_check(walker.get_node_or_null("Body/ArmL") != null and walker.get_node_or_null("Body/ArmR") != null,
			"Zombie hat zwei Arme.")

	var late_walker: CharacterBody3D = _make_zombie("walker", 5, Vector3(22.0, 0.0, 20.0))
	_check_near(float(late_walker.get("max_hp")), WavePlan.zombie_hp("walker", 5), "Schlurfer Welle 5: Leben nach WavePlan.")
	_check_near(float(late_walker.get("move_speed")), 2.0, "Schlurfer Welle 5 läuft 2,0 m/s.")
	var sprinter: CharacterBody3D = _make_zombie("sprinter", 3, Vector3(24.0, 0.0, 20.0))
	_check_near(float(sprinter.get("max_hp")), 35.0 * WavePlan.hp_factor(3), "Sprinter Welle 3: Leben nach WavePlan.")
	_check_near(float(sprinter.get("move_speed")), 5.0, "Sprinter läuft 5,0 m/s.")
	_check_near(float(sprinter.get("attack_damage")), 15.0, "Sprinter schlägt mit 15.")
	var unknown: CharacterBody3D = _make_zombie("clown", 1, Vector3(26.0, 0.0, 20.0))
	_check(String(unknown.get("zombie_type")) == "walker", "Unbekannter Typ wird zum Schlurfer.")

	var elite: CharacterBody3D = _make_zombie("elite", 2, Vector3(28.0, 0.0, 20.0))
	_check_near(float(elite.get("max_hp")), 400.0 * WavePlan.hp_factor(2), "Elite Welle 2: Leben nach WavePlan.")
	_check_near(float(elite.get("attack_damage")), 35.0, "Elite schlägt mit 35.")
	_check_near(float(elite.get("body_height")), Balance.ZOMBIE_HEIGHT * 1.3, "Elite ist 1,3-mal so hoch.")
	_check_near(float(elite.get("body_radius")), Balance.ZOMBIE_RADIUS * 1.3, "Elite ist 1,3-mal so breit.")
	_check(elite.get_node_or_null("Glow") is OmniLight3D, "Elite hat ein Licht.")
	_check(walker.get_node_or_null("Glow") == null, "Schlurfer hat kein Licht.")
	var elite_capsule: CapsuleShape3D = (elite.get_node("Shape") as CollisionShape3D).shape as CapsuleShape3D
	_check(elite_capsule != null and is_equal_approx(elite_capsule.height, Balance.ZOMBIE_HEIGHT * 1.3),
			"Kollisionskapsel der Elite reicht über die ganze Körperhöhe.")

	# Kopftreffer-Regel und Lage des sichtbaren Kopfs.
	for zombie: CharacterBody3D in [walker, sprinter, elite]:
		var height: float = float(zombie.get("body_height"))
		var feet: Vector3 = zombie.global_position
		var limit: float = height * Balance.HEADSHOT_HEIGHT_RATIO
		var label: String = String(zombie.get("zombie_type"))
		_check(bool(zombie.call("is_headshot", feet + Vector3(0.0, limit + 0.02, 0.0))), "%s: knapp über der Grenze ist ein Kopftreffer." % label)
		_check(not bool(zombie.call("is_headshot", feet + Vector3(0.0, limit - 0.02, 0.0))), "%s: knapp unter der Grenze ist kein Kopftreffer." % label)
		# Aufricht-Animation zu Ende laufen lassen, dann steht der Kopf an seinem Platz.
		zombie.call("_process", 1.0)
		var head: Node3D = zombie.get_node("Body/Head") as Node3D
		var head_height: float = head.global_position.y - feet.y
		_check(head_height > limit and head_height < height, "%s: Der sichtbare Kopf liegt im Kopftreffer-Bereich (%.2f von %.2f)." % [label, head_height, height])
		_check(_flat_distance(head.global_position, feet) < float(zombie.get("body_radius")),
				"%s: Der sichtbare Kopf bleibt über der Kollisionskapsel." % label)
		var center: Vector3 = zombie.call("get_center_position")
		_check_near(center.y - feet.y, height * 0.5, "%s: get_center_position ist die Körpermitte." % label)
	_remove_all_zombies()
	_game.set("player", _player)


func _test_damage_and_death() -> void:
	_game.set("player", null)
	_clear_log()
	var zombie: CharacterBody3D = _make_zombie("walker", 1, Vector3(20.0, 0.0, 0.0))
	var hit: Dictionary = {"source": "bullet", "headshot": false, "weapon_id": "pistol"}
	zombie.call("take_damage", 25.0, hit)
	_check_near(float(zombie.get("hp")), 35.0, "25 Schaden lassen 35 Leben übrig.")
	_check(_damaged.size() == 1, "Ein Treffer sendet zombie_damaged genau einmal.")
	if _damaged.size() == 1:
		_check(_damaged[0]["zombie"] == zombie and is_equal_approx(_damaged[0]["amount"], 25.0), "zombie_damaged trägt Zombie und Betrag.")
		_check(_damaged[0]["info"] == hit, "zombie_damaged reicht info unverändert weiter.")
	zombie.call("take_damage", 0.0, hit)
	zombie.call("take_damage", -5.0, hit)
	_check(_damaged.size() == 1 and is_equal_approx(float(zombie.get("hp")), 35.0), "Beträge <= 0 werden ignoriert.")
	_check(_killed.is_empty() and not bool(zombie.get("is_dead")), "Der Zombie lebt noch.")

	# Tödlicher Treffer mit Überschaden. Ein Empfänger schlägt im selben Moment noch einmal zu.
	_hit_again_on_kill = true
	var kill_hit: Dictionary = {"source": "bullet", "headshot": true, "weapon_id": "pistol"}
	zombie.call("take_damage", 100.0, kill_hit)
	_hit_again_on_kill = false
	_check(bool(zombie.get("is_dead")), "Nach dem tödlichen Treffer ist is_dead true.")
	_check_near(float(zombie.get("hp")), 0.0, "Das Leben fällt nicht unter 0.")
	_check(_damaged.size() == 2, "Der tödliche Treffer sendet zombie_damaged, der Schlag auf den Toten nicht.")
	if _damaged.size() >= 2:
		_check(is_equal_approx(_damaged[1]["amount"], 100.0), "zombie_damaged trägt den unveränderten Betrag (Überschaden).")
	_check(_killed.size() == 1, "zombie_killed kommt genau einmal (ist %d)." % _killed.size())
	if _killed.size() == 1:
		_check(_killed[0]["zombie"] == zombie and _killed[0]["info"] == kill_hit, "zombie_killed trägt Zombie und info.")
		_check(bool(_killed[0]["valid"]) and _killed[0]["type"] == "walker", "In zombie_killed ist der Knoten noch gültig und lesbar.")
	_check(not zombie.is_in_group("zombies"), "Der Tote verlässt die Gruppe zombies sofort.")
	_check(zombie.collision_layer == 0 and zombie.collision_mask == 0, "Die Kollision des Toten ist aus.")
	zombie.call("take_damage", 50.0, hit)
	zombie.call("apply_burn", 20.0, 4.0)
	zombie.call("apply_knockback", Vector3(5.0, 0.0, 0.0))
	_check(_damaged.size() == 2 and _killed.size() == 1, "Ein toter Zombie nimmt keinen Schaden und stirbt nie zweimal.")
	_check(not bool(zombie.call("is_burning")), "Ein toter Zombie fängt kein Feuer.")
	_check(is_instance_valid(zombie) and not zombie.is_queued_for_deletion(), "Während der Todesanimation existiert der Knoten noch.")
	_step_zombie(zombie, Balance.ZOMBIE_DEATH_TIME + 0.2, 0.05)
	await process_frame
	await process_frame
	_check(not is_instance_valid(zombie), "Nach der Todesanimation ist der Zombie entfernt.")
	_check(_killed.size() == 1, "Auch danach bleibt es bei einem zombie_killed.")

	# despawn: weg ohne Belohnung.
	_clear_log()
	var silent: CharacterBody3D = _make_zombie("walker", 1, Vector3(20.0, 0.0, 0.0))
	silent.call("despawn")
	_check(_killed.is_empty() and _damaged.is_empty(), "despawn sendet weder zombie_killed noch zombie_damaged.")
	_check(not silent.is_in_group("zombies") and bool(silent.get("is_dead")), "despawn nimmt den Zombie sofort aus der Gruppe.")
	await process_frame
	_check(not is_instance_valid(silent), "despawn entfernt den Knoten.")
	_game.set("player", _player)


func _test_burn() -> void:
	_game.set("player", null)
	_clear_log()
	var interval: float = Balance.BURN_TICK_INTERVAL
	var zombie: CharacterBody3D = _make_zombie("walker", 1, Vector3(20.0, 0.0, 0.0))
	zombie.call("apply_burn", 10.0, 4.0)
	_check(bool(zombie.call("is_burning")), "apply_burn setzt den Zombie in Brand.")
	_check(_damaged.is_empty(), "Der erste Tick kommt erst nach dem Tick-Abstand.")
	_step_zombie(zombie, 4.0)
	var expected_ticks: int = roundi(4.0 / interval)
	_check(_damaged.size() == expected_ticks, "4 s Brand ergeben %d Ticks (sind %d)." % [expected_ticks, _damaged.size()])
	var all_burn: bool = true
	for entry: Dictionary in _damaged:
		var info: Dictionary = entry["info"]
		if String(info.get("source", "")) != "burn" or not is_equal_approx(entry["amount"], 10.0 * interval):
			all_burn = false
	_check(all_burn, "Jeder Tick läuft über take_damage mit source burn und dps * Tick-Abstand.")
	_check_near(float(zombie.get("hp")), 20.0, "10 Schaden je Sekunde über 4 s kosten 40 Leben.")
	_check(not bool(zombie.call("is_burning")), "Nach Ablauf der Dauer brennt der Zombie nicht mehr.")
	_step_zombie(zombie, 2.0)
	_check(_damaged.size() == expected_ticks, "Nach dem Brand kommt kein Tick mehr.")

	# Brand, der zwischen zwei Ticks endet: Der Rest kommt anteilig.
	_clear_log()
	zombie.call("apply_burn", 10.0, 0.75)
	_step_zombie(zombie, 1.5, 0.05)
	_check_near(float(zombie.get("hp")), 12.5, "0,75 s Brand mit 10 je Sekunde kosten genau 7,5 Leben.")

	# Brand tötet: genau ein Kill mit source burn, danach kein Tick mehr.
	_clear_log()
	var victim: CharacterBody3D = _make_zombie("walker", 1, Vector3(22.0, 0.0, 0.0))
	victim.call("apply_burn", 100.0, 4.0)
	_step_zombie(victim, 3.0)
	_check(bool(victim.get("is_dead")), "Brand kann töten.")
	_check(_killed.size() == 1, "Tod durch Brand sendet zombie_killed genau einmal (ist %d)." % _killed.size())
	if _killed.size() == 1:
		var kill_info: Dictionary = _killed[0]["info"]
		_check(String(kill_info.get("source", "")) == "burn", "Der Kill trägt source burn.")
	_check(_damaged.size() == 2, "Nach dem Tod tickt der Brand nicht weiter (Ticks: %d)." % _damaged.size())

	# Erneuern: Die Dauer beginnt neu, der höhere dps bleibt.
	_clear_log()
	var tough: CharacterBody3D = _make_zombie("elite", 1, Vector3(24.0, 0.0, 0.0))
	tough.call("apply_burn", 10.0, 4.0)
	_step_zombie(tough, 2.0)
	_check_near(float(tough.get("hp")), 380.0, "Nach 2 s Brand fehlen 20 Leben.")
	tough.call("apply_burn", 4.0, 4.0)
	_step_zombie(tough, 3.9)
	_check(bool(tough.call("is_burning")), "Ein neuer Aufruf erneuert die Dauer.")
	_step_zombie(tough, 1.0)
	_check(not bool(tough.call("is_burning")), "Der erneuerte Brand endet 4 s nach dem zweiten Aufruf.")
	_check_near(float(tough.get("hp")), 340.0, "Der schwächere Brand ersetzt den stärkeren nicht (6 s mit 10 je Sekunde).")
	tough.call("apply_burn", 10.0, 4.0)
	_step_zombie(tough, 1.0)
	tough.call("apply_burn", 30.0, 4.0)
	_step_zombie(tough, 5.0)
	_check_near(float(tough.get("hp")), 340.0 - 10.0 - 120.0, "Der höhere dps gewinnt ab dem zweiten Aufruf.")
	tough.call("apply_burn", 0.0, 4.0)
	tough.call("apply_burn", 5.0, 0.0)
	_check(not bool(tough.call("is_burning")), "apply_burn ohne dps oder ohne Dauer tut nichts.")
	_remove_all_zombies()
	_game.set("player", _player)


func _test_elite_burn_factor() -> void:
	_game.set("player", null)
	_clear_log()
	var percent: float = 0.12
	var walker: CharacterBody3D = _make_zombie("walker", 1, Vector3(20.0, 0.0, 0.0))
	var elite: CharacterBody3D = _make_zombie("elite", 1, Vector3(23.0, 0.0, 0.0))
	var walker_dps: float = walker.call("get_burn_dps", percent)
	var elite_dps: float = elite.call("get_burn_dps", percent)
	_check_near(walker_dps, 60.0 * percent, "Schlurfer brennt mit dem vollen Anteil seines Maximal-Lebens.")
	_check_near(elite_dps, 400.0 * percent * Balance.BURN_ELITE_FACTOR, "Elite brennt nur mit dem Elite-Faktor (0,3).")
	elite.call("apply_burn", elite_dps, Balance.BURN_DURATION)
	_step_zombie(elite, Balance.BURN_DURATION + 0.5)
	_check_near(float(elite.get("hp")), 400.0 - elite_dps * Balance.BURN_DURATION,
			"Elite verliert über die Brand-Dauer genau dps * Dauer (apply_burn rechnet keinen eigenen Faktor dazu).")
	_check(not bool(elite.get("is_dead")), "Eine Elite übersteht einen Brand der Stufe 5.")
	_remove_all_zombies()
	_game.set("player", _player)


## Abschnitt 22: Verlangsamung (Trockeneis, Zeitlupen-Kamera) und Markierung (Regie-Kamera).
func _test_slow_and_mark() -> void:
	_game.set("player", null)
	_clear_log()
	# --- Verlangsamung: Regeln ---
	var walker: CharacterBody3D = _make_zombie("walker", 1, Vector3(20.0, 0.0, 0.0))
	_check(not bool(walker.call("is_slowed")) and is_equal_approx(float(walker.call("get_speed_factor")), 1.0), "Ohne Verlangsamung läuft der Zombie mit vollem Tempo.")
	var base_speed: float = float(walker.get("move_speed"))
	walker.call("apply_slow", 0.3, 2.0)
	_check(bool(walker.call("is_slowed")), "apply_slow verlangsamt den Zombie.")
	_check_near(float(walker.call("get_speed_factor")), 0.7, "30 % langsamer: Faktor 0,7.")
	_check_near(float(walker.get("move_speed")), base_speed, "move_speed bleibt der Grundwert, die Verlangsamung steckt im Faktor.")
	# Die stärkste gilt, eine schwächere ändert sie nicht.
	walker.call("apply_slow", 0.5, 2.0)
	_check_near(float(walker.call("get_speed_factor")), 0.5, "Eine stärkere Verlangsamung ersetzt die schwächere.")
	walker.call("apply_slow", 0.2, 2.0)
	_check_near(float(walker.call("get_speed_factor")), 0.5, "Eine schwächere ändert die stärkere nicht (kein Addieren).")
	# Jeder neue Aufruf stellt die Zeit neu.
	_step_zombie(walker, 1.5)
	walker.call("apply_slow", 0.2, 2.0)
	_step_zombie(walker, 1.5)
	_check(bool(walker.call("is_slowed")), "Ein neuer Aufruf stellt die Zeit neu: nach 3 s noch langsam.")
	_check_near(float(walker.call("get_speed_factor")), 0.5, "Solange sie läuft, gilt weiter die stärkste.")
	_step_zombie(walker, 0.7)
	_check(not bool(walker.call("is_slowed")) and is_equal_approx(float(walker.call("get_speed_factor")), 1.0), "2 s nach dem letzten Aufruf ist die Verlangsamung vorbei.")
	# Danach beginnt eine neue mit ihrem eigenen Wert.
	walker.call("apply_slow", 0.2, 2.0)
	_check_near(float(walker.call("get_speed_factor")), 0.8, "Nach dem Ablauf zählt wieder der neue Wert.")
	_step_zombie(walker, 2.2)
	# Ungültige Werte und die Obergrenze.
	walker.call("apply_slow", 0.0, 2.0)
	walker.call("apply_slow", 0.3, 0.0)
	walker.call("apply_slow", -0.5, 2.0)
	_check(not bool(walker.call("is_slowed")), "apply_slow ohne Wirkung oder ohne Dauer tut nichts.")
	walker.call("apply_slow", 5.0, 2.0)
	_check_near(float(walker.call("get_speed_factor")), 1.0 - Balance.SLOW_MAX, "Kein Zombie wird um mehr als SLOW_MAX langsamer.")
	# Elite: halbe Wirkung.
	var elite: CharacterBody3D = _make_zombie("elite", 1, Vector3(24.0, 0.0, 0.0))
	elite.call("apply_slow", 0.3, 2.0)
	_check_near(float(elite.call("get_speed_factor")), 1.0 - 0.3 * Balance.SLOW_ELITE_FACTOR, "Elite spürt nur die halbe Verlangsamung (Faktor 0,85).")
	_check(_damaged.is_empty(), "Verlangsamen macht keinen Schaden.")

	# --- Markierung: Regeln ---
	_clear_log()
	var target: CharacterBody3D = _make_zombie("elite", 1, Vector3(28.0, 0.0, 0.0))
	_check(not bool(target.call("is_marked")) and is_equal_approx(float(target.call("get_damage_factor")), 1.0), "Ohne Markierung gilt der einfache Schaden.")
	target.call("take_damage", 10.0, {"source": "bullet"})
	_check_near(float(target.get("hp")), 390.0, "Unmarkiert kosten 10 Schaden 10 Leben.")
	target.call("apply_mark", 0.25, 4.0)
	_check(bool(target.call("is_marked")), "apply_mark markiert den Zombie.")
	_check_near(float(target.call("get_damage_factor")), 1.25, "25 % Mehr-Schaden: Faktor 1,25.")
	var mark: Node3D = target.get_node_or_null("Mark") as Node3D
	_check(mark != null and mark.visible, "Über einem markierten Zombie steht das Zeichen.")
	_damaged.clear()
	target.call("take_damage", 10.0, {"source": "bullet"})
	_check_near(float(target.get("hp")), 377.5, "Markiert kosten 10 Schaden 12,5 Leben.")
	_check(_damaged.size() == 1 and is_equal_approx(float(_damaged[0]["amount"]), 12.5), "zombie_damaged meldet den erhöhten Betrag.")
	# Aus jeder Quelle: auch der Brand.
	target.call("apply_burn", 10.0, 1.0)
	_step_zombie(target, 1.2)
	_check_near(float(target.get("hp")), 377.5 - 12.5, "Auch Brand macht an Markierten 25 % mehr.")
	# Die stärkste gilt, eine schwächere ändert sie nicht, die Zeit beginnt neu.
	target.call("apply_mark", 0.5, 4.0)
	_check_near(float(target.call("get_damage_factor")), 1.5, "Eine stärkere Markierung ersetzt die schwächere.")
	target.call("apply_mark", 0.2, 4.0)
	_check_near(float(target.call("get_damage_factor")), 1.5, "Eine schwächere ändert die stärkere nicht.")
	_step_zombie(target, 3.0)
	target.call("apply_mark", 0.2, 4.0)
	_step_zombie(target, 3.0)
	_check(bool(target.call("is_marked")), "Ein neuer Aufruf stellt die Zeit neu: nach 6 s noch markiert.")
	_step_zombie(target, 1.2)
	_check(not bool(target.call("is_marked")) and is_equal_approx(float(target.call("get_damage_factor")), 1.0), "4 s nach dem letzten Aufruf ist die Markierung vorbei.")
	_check(mark != null and not mark.visible, "Das Zeichen verschwindet mit der Markierung.")
	var hp_before: float = float(target.get("hp"))
	target.call("take_damage", 10.0, {"source": "drone"})
	_check_near(float(target.get("hp")), hp_before - 10.0, "Danach gilt wieder der einfache Schaden.")
	target.call("apply_mark", 0.0, 4.0)
	target.call("apply_mark", 0.3, 0.0)
	_check(not bool(target.call("is_marked")), "apply_mark ohne Wirkung oder ohne Dauer tut nichts.")
	# Tod räumt beides ab, ein toter Zombie nimmt nichts mehr an.
	var victim: CharacterBody3D = _make_zombie("walker", 1, Vector3(32.0, 0.0, 0.0))
	victim.call("apply_slow", 0.4, 5.0)
	victim.call("apply_mark", 0.4, 5.0)
	victim.call("take_damage", 1000.0, {"source": "bullet"})
	_check(bool(victim.get("is_dead")) and not bool(victim.call("is_slowed")) and not bool(victim.call("is_marked")), "Mit dem Tod enden Verlangsamung und Markierung.")
	victim.call("apply_slow", 0.4, 5.0)
	victim.call("apply_mark", 0.4, 5.0)
	_check(not bool(victim.call("is_slowed")) and not bool(victim.call("is_marked")), "Ein toter Zombie wird weder verlangsamt noch markiert.")
	_remove_all_zombies()

	# --- Verlangsamung: wirklich langsamer unterwegs ---
	_player.position = Vector3.ZERO
	_player.is_dead = false
	_game.set("player", _player)
	var fast: CharacterBody3D = _make_zombie("walker", 1, Vector3(30.0, 0.0, -8.0))
	var slow: CharacterBody3D = _make_zombie("walker", 1, Vector3(30.0, 0.0, 8.0))
	for i: int in 20:
		await physics_frame
	slow.call("apply_slow", 0.5, 60.0)
	var fast_start: Vector3 = fast.global_position
	var slow_start: Vector3 = slow.global_position
	for i: int in 120:
		await physics_frame
	var fast_way: float = _flat_distance(fast.global_position, fast_start)
	var slow_way: float = _flat_distance(slow.global_position, slow_start)
	_check(fast_way > 1.5, "Der unverlangsamte Schlurfer kommt voran (%.2f m)." % fast_way)
	_check(slow_way > fast_way * 0.35 and slow_way < fast_way * 0.65, "Mit 50 %% Verlangsamung schafft er etwa die halbe Strecke (%.2f m gegen %.2f m)." % [slow_way, fast_way])
	_remove_all_zombies()
	_player.hits.clear()
	_game.set("player", _player)


func _test_knockback_and_separation() -> void:
	_game.set("player", null)
	var zombie: CharacterBody3D = _make_zombie("walker", 1, Vector3(20.0, 0.0, 5.0))
	for i: int in 6:
		await physics_frame
	var start_x: float = zombie.global_position.x
	zombie.call("apply_knockback", Vector3(6.0, 0.0, 0.0))
	for i: int in 50:
		await physics_frame
	_check(zombie.global_position.x - start_x > 1.0, "Rückstoß schiebt den Zombie weg (%.2f m)." % (zombie.global_position.x - start_x))
	var settled_x: float = zombie.global_position.x
	for i: int in 30:
		await physics_frame
	_check(absf(zombie.global_position.x - settled_x) < 0.8, "Der Rückstoß klingt ab.")
	_check(zombie.global_position.y > -0.5 and zombie.global_position.y < 0.5, "Der Zombie steht nach dem Stoß wieder auf dem Boden.")

	# Zwei Zombies am selben Fleck rücken auseinander.
	var first: CharacterBody3D = _make_zombie("walker", 1, Vector3(-20.0, 0.0, 5.0))
	var second: CharacterBody3D = _make_zombie("walker", 1, Vector3(-20.0, 0.0, 5.0))
	for i: int in 60:
		await physics_frame
	var gap: float = _flat_distance(first.global_position, second.global_position)
	_check(gap > 0.5, "Zombies am selben Fleck stoßen einander ab (Abstand %.2f m)." % gap)
	_remove_all_zombies()
	_game.set("player", _player)


func _test_chase_and_attack() -> void:
	_player.position = Vector3.ZERO
	_player.is_dead = false
	_player.hits.clear()
	_game.set("player", _player)
	# Ohne Navigationsnetz läuft der Zombie geradeaus auf den Spieler zu.
	var zombie: CharacterBody3D = _make_zombie("sprinter", 3, Vector3(5.0, 0.0, 0.0))
	var saw_windup: bool = false
	var windup_before_hit: bool = false
	var frames: int = 0
	while _player.hits.is_empty() and frames < 600:
		await physics_frame
		frames += 1
		if bool(zombie.call("is_winding_up")):
			saw_windup = true
			if _player.hits.is_empty():
				windup_before_hit = true
	var reached: float = _flat_distance(zombie.global_position, _player.global_position)
	_check(reached < float(zombie.call("get_attack_range")) + 0.3, "Der Zombie läuft zum Spieler (Abstand %.2f m)." % reached)
	_check(saw_windup and windup_before_hit, "Vor dem Schlag holt der Zombie sichtbar aus.")
	_check(_player.hits.size() == 1, "Der Schlag trifft den Spieler einmal (Treffer: %d)." % _player.hits.size())
	if _player.hits.size() >= 1:
		_check_near(_player.hits[0], 15.0, "Der Sprinter-Schlag macht 15 Schaden.")
	# Direkt nach dem Schlag ist Pause: in der nächsten halben Sekunde kein zweiter Treffer.
	for i: int in 30:
		await physics_frame
	_check(_player.hits.size() == 1, "Nach dem Schlag folgt die Pause.")
	# Ein toter Spieler wird nicht mehr geschlagen.
	_player.is_dead = true
	for i: int in 120:
		await physics_frame
	_check(_player.hits.size() <= 2, "Der Zombie schlägt nicht im Dauerfeuer.")
	var hits_when_dead: int = _player.hits.size()
	for i: int in 120:
		await physics_frame
	_check(_player.hits.size() == hits_when_dead, "Ein toter Spieler wird nicht mehr geschlagen.")
	_player.is_dead = false

	# Ausweichen: Wer während des Ausholens weggeht, wird nicht getroffen.
	_remove_all_zombies()
	_player.hits.clear()
	var walker: CharacterBody3D = _make_zombie("walker", 1, Vector3(1.2, 0.0, 0.0))
	frames = 0
	while not bool(walker.call("is_winding_up")) and frames < 120:
		await physics_frame
		frames += 1
	_check(bool(walker.call("is_winding_up")), "In Reichweite holt der Zombie aus.")
	_player.position = Vector3(-6.0, 0.0, 0.0)
	for i: int in 45:
		await physics_frame
	_check(_player.hits.is_empty(), "Wer während des Ausholens ausweicht, wird nicht getroffen.")
	_player.position = Vector3.ZERO
	_remove_all_zombies()
	await process_frame


## Kein Schlag durch Wände: Spieler und Zombie lehnen beidseitig an einer 0,4 m dicken Wand
## (Abstand 1,1 m, also in Reichweite). Ohne freie Sicht darf der Zombie weder ausholen noch
## treffen. Eine hüfthohe Deckung dagegen schützt nicht, darüber reicht er hinweg.
func _test_no_attack_through_wall() -> void:
	_remove_all_zombies()
	_player.is_dead = false
	_player.hits.clear()
	_game.set("player", _player)
	var wall_x: float = 40.0
	var gap: float = 0.2 + Balance.ZOMBIE_RADIUS
	var wall: StaticBody3D = _add_block(Vector3(wall_x, 1.5, 0.0), Vector3(0.4, 3.0, 8.0))
	wall.remove_from_group("nav_source")
	for i: int in 2:
		await physics_frame
	_player.position = Vector3(wall_x + gap, 0.0, 0.0)
	var lurker: CharacterBody3D = _make_zombie("sprinter", 3, Vector3(wall_x - gap, 0.0, 0.0))
	var start_gap: float = _flat_distance(lurker.global_position, _player.global_position)
	_check(start_gap < float(lurker.call("get_attack_range")) * Balance.ZOMBIE_ATTACK_STOP_RANGE_FACTOR,
		"Aufbau: Zombie und Spieler stehen beidseitig der Wand in Schlagweite (%.2f m)." % start_gap)
	var wound_up: bool = false
	for i: int in 240:
		await physics_frame
		if bool(lurker.call("is_winding_up")):
			wound_up = true
	_check(_player.hits.is_empty(), "Durch eine Wand trifft kein Schlag (Treffer: %d)." % _player.hits.size())
	_check(not wound_up, "Ohne freie Sicht holt der Zombie nicht aus.")
	_check(lurker.global_position.x < wall_x, "Der Zombie steht noch auf seiner Seite der Wand.")
	# Gegenprobe: Ohne die Wand trifft derselbe Zombie von derselben Stelle.
	_player.hits.clear()
	wall.queue_free()
	var frames: int = 0
	while _player.hits.is_empty() and frames < 180:
		await physics_frame
		frames += 1
	_check(_player.hits.size() == 1, "Gegenprobe: Ohne Wand trifft der Schlag (Treffer: %d)." % _player.hits.size())
	_remove_all_zombies()
	_player.hits.clear()

	# Die Wand taucht während des Ausholens auf (der Spieler tritt hinter eine Ecke): kein Treffer.
	_player.position = Vector3(wall_x + gap, 0.0, 20.0)
	var striker: CharacterBody3D = _make_zombie("walker", 1, Vector3(wall_x - gap, 0.0, 20.0))
	frames = 0
	while not bool(striker.call("is_winding_up")) and frames < 180:
		await physics_frame
		frames += 1
	_check(bool(striker.call("is_winding_up")), "Aufbau: Bei freier Sicht holt der Zombie aus.")
	var late_wall: StaticBody3D = _add_block(Vector3(wall_x, 1.5, 20.0), Vector3(0.4, 3.0, 8.0))
	late_wall.remove_from_group("nav_source")
	for i: int in 60:
		await physics_frame
	_check(_player.hits.is_empty(), "Verschwindet der Spieler beim Ausholen hinter einer Wand, trifft der Schlag nicht.")
	late_wall.queue_free()
	_remove_all_zombies()
	_player.hits.clear()

	# Hüfthohe Deckung (0,9 m): Über sie reicht der Zombie hinweg.
	var crate: StaticBody3D = _add_block(Vector3(wall_x, 0.45, -20.0), Vector3(0.4, 0.9, 8.0))
	crate.remove_from_group("nav_source")
	for i: int in 2:
		await physics_frame
	_player.position = Vector3(wall_x + gap, 0.0, -20.0)
	_make_zombie("walker", 1, Vector3(wall_x - gap, 0.0, -20.0))
	frames = 0
	while _player.hits.is_empty() and frames < 180:
		await physics_frame
		frames += 1
	_check(_player.hits.size() == 1, "Über eine hüfthohe Deckung hinweg trifft der Schlag (Treffer: %d)." % _player.hits.size())
	crate.queue_free()
	_remove_all_zombies()
	_player.position = Vector3.ZERO
	_player.hits.clear()
	await process_frame


# --- Spawner ---------------------------------------------------------------------------------

func _test_spawner() -> void:
	_clear_log()
	_player.position = Vector3.ZERO
	var active: Array = _spawner.call("get_active_spawns")
	_check(active.size() == 3, "Vor dem Öffnen der Tür sind nur die 3 Spawnpunkte der Zone 1 aktiv (sind %d)." % active.size())
	var all_zone1: bool = true
	for marker: Marker3D in active:
		if int(marker.get_meta("zone")) != 1:
			all_zone1 = false
	_check(all_zone1, "get_active_spawns liefert vor dem Öffnen keinen Punkt der Zone 2.")

	var elite: Node3D = _spawner.call("spawn", "elite", 4)
	_check(is_instance_valid(elite) and String(elite.get("zombie_type")) == "elite" and int(elite.get("wave")) == 4,
			"spawn gibt einen Zombie des Typs für die Welle zurück.")
	_check_near(float(elite.get("max_hp")), WavePlan.zombie_hp("elite", 4), "Der gespawnte Zombie hat das Leben der Welle.")
	_check(_spawned.size() == 1 and _spawned[0] == elite, "spawn sendet zombie_spawned.")
	_check(elite.get_parent() == _zombies_root, "Neue Zombies hängen im Behälter zombie_parent.")
	_check(int(_spawner.call("alive_count")) == 1, "alive_count zählt die lebenden Zombies.")
	elite.call("despawn")

	# Viele Spawns: nur Zone 1, nie derselbe Punkt zweimal hintereinander, alle Punkte kommen dran.
	var used: Dictionary = {}
	var zone2_used: bool = false
	var repeated: bool = false
	var off_marker: bool = false
	var previous: Marker3D = null
	for i: int in 60:
		var zombie: Node3D = _spawner.call("spawn", "walker", 1)
		var marker: Marker3D = _nearest_spawn(zombie.global_position)
		if _flat_distance(marker.global_position, zombie.global_position) > 0.6:
			off_marker = true
		if int(marker.get_meta("zone")) != 1:
			zone2_used = true
		if marker == previous:
			repeated = true
		previous = marker
		used[marker] = true
		zombie.call("despawn")
	_check(not off_marker, "Zombies erscheinen an einem Spawnpunkt.")
	_check(not zone2_used, "Solange die Tür zu ist, erscheint kein Zombie in Zone 2.")
	_check(not repeated, "Nie derselbe Spawnpunkt zweimal hintereinander.")
	_check(used.size() == 3, "Alle aktiven Spawnpunkte werden benutzt.")

	# Der Spieler steht direkt an einem Spawnpunkt: Dort erscheint niemand.
	_player.position = _zone1[0].global_position + Vector3(1.0, 0.0, 1.0)
	var next_to_player: bool = false
	for i: int in 40:
		var zombie: Node3D = _spawner.call("spawn", "walker", 1)
		if _nearest_spawn(zombie.global_position) == _zone1[0]:
			next_to_player = true
		zombie.call("despawn")
	_check(not next_to_player, "Der Spawnpunkt direkt neben dem Spieler wird gemieden.")

	# Tür offen (door.open() setzt Meta active an den Punkten ihrer Zone): Zone 2 spielt mit.
	for marker: Marker3D in _zone2:
		marker.set_meta("active", true)
	active = _spawner.call("get_active_spawns")
	_check(active.size() == 5, "Nach dem Öffnen sind alle 5 Spawnpunkte aktiv (sind %d)." % active.size())
	_player.position = Vector3(0.0, 0.0, 4.0)
	var zone2_count: int = 0
	for i: int in 80:
		var zombie: Node3D = _spawner.call("spawn", "walker", 1)
		if int(_nearest_spawn(zombie.global_position).get_meta("zone")) == 2:
			zone2_count += 1
		zombie.call("despawn")
	_check(zone2_count > 0, "Nach dem Öffnen erscheinen Zombies auch in Zone 2 (%d von 80)." % zone2_count)
	for marker: Marker3D in _zone2:
		marker.set_meta("active", false)
	_player.position = Vector3.ZERO
	_check(int(_spawner.call("alive_count")) == 0, "despawn nimmt Zombies sofort aus der Zählung.")


# --- Wellen ----------------------------------------------------------------------------------

func _test_wave_flow() -> void:
	_game.call("start_run", 3)
	_game.set("player", _player)
	_player.healed = 0.0
	_clear_log()
	_waves.set("auto_start", false)
	_check_near(float(_waves.call("get_countdown")), Balance.FIRST_WAVE_DELAY, "Nach run_started läuft der Countdown zur ersten Welle (4 s).")
	_check(int(_waves.get("current_wave")) == 0 and not bool(_waves.get("is_wave_active")), "Vor der ersten Welle: Welle 0, nicht aktiv.")
	_step_waves(8.0)
	_check(_wave_started.is_empty() and _ticks.is_empty(), "Mit auto_start = false beginnt keine Welle von selbst.")

	_waves.set("auto_start", true)
	_step_waves(Balance.FIRST_WAVE_DELAY - 0.3)
	_check(_wave_started.is_empty(), "Die erste Welle beginnt nicht vor Ablauf der 4 s.")
	_step_waves(0.5)
	_check(_ticks == [4, 3, 2, 1, 0], "intermission_tick zählt 4, 3, 2, 1, 0 (ist %s)." % str(_ticks))
	_check(_wave_started.size() == 1 and _wave_started[0] == [1, 10], "wave_started(1, 10) kommt einmal (ist %s)." % str(_wave_started))
	_check(int(_waves.get("current_wave")) == 1 and bool(_waves.get("is_wave_active")), "Welle 1 läuft.")
	_check(int(_waves.get("zombies_left")) == 10 and _left == [10], "zombies_left_changed(10) zum Wellenbeginn.")
	_check(_banners.size() == 1 and _banners[0].begins_with("Welle 1"), "Das Banner nennt die Welle (ist %s)." % str(_banners))
	_check(float(_waves.call("get_countdown")) < 0.0, "Während der Welle läuft kein Countdown.")

	# Spawn-Takt: sofort einer, dann alle spawn_interval Sekunden einer.
	var interval: float = WavePlan.spawn_interval(1)
	_step_waves(interval * 0.5)
	_check(_spawned.size() == 1, "Der erste Zombie erscheint sofort, der zweite erst nach dem Spawn-Abstand (sind %d)." % _spawned.size())
	_step_waves(interval * 9.0 + 1.0)
	_check(_spawned.size() == 10, "Welle 1 lässt 10 Zombies erscheinen (sind %d)." % _spawned.size())
	_step_waves(5.0)
	_check(_spawned.size() == 10, "Danach erscheint keiner mehr.")
	var all_walkers: bool = true
	var all_marked: bool = true
	for zombie: Node3D in _spawned:
		if String(zombie.get("zombie_type")) != "walker" or int(zombie.get("wave")) != 1:
			all_walkers = false
		if not bool(zombie.get_meta("wave_spawn", false)):
			all_marked = false
	_check(all_walkers, "Welle 1 besteht aus Schlurfern der Welle 1.")
	_check(all_marked, "Zombies der Welle tragen Meta wave_spawn.")
	_check(int(_waves.get("zombies_left")) == 10, "Erscheinen ändert zombies_left nicht.")

	# Ein fremder Zombie (nicht vom WaveManager) zählt nicht mit.
	var stranger: Node3D = _spawner.call("spawn", "walker", 1)
	_kill(stranger)
	_check(int(_waves.get("zombies_left")) == 10, "Ein Zombie ohne wave_spawn zählt nicht zur Welle.")

	_left.clear()
	var wave_zombies: Array[Node3D] = _spawned.duplicate()
	wave_zombies.erase(stranger)
	for i: int in wave_zombies.size():
		if i == wave_zombies.size() - 1:
			_check(_wave_cleared.is_empty(), "wave_cleared kommt erst nach dem letzten Kill.")
		_kill(wave_zombies[i])
	_check(_left == [9, 8, 7, 6, 5, 4, 3, 2, 1, 0], "zombies_left_changed zählt je Kill herunter (ist %s)." % str(_left))
	_check(_wave_cleared == [1], "wave_cleared(1) kommt genau einmal (ist %s)." % str(_wave_cleared))
	_check(not bool(_waves.get("is_wave_active")), "Nach dem letzten Kill ist die Welle vorbei.")
	_check_near(_player.healed, Balance.WAVE_END_HEAL, "Am Wellenende heilt der Spieler um 25.")
	_check_near(float(_waves.call("get_countdown")), Balance.INTERMISSION_SECONDS, "Danach läuft die Pause von 12 s.")
	_check(_banners.size() == 2 and _banners[1].contains("Welle 1"), "Das Wellenende hat ein eigenes Banner.")

	# Pause: Ticks 12 bis 0, dann Welle 2 mit einer Elite.
	_clear_log()
	_step_waves(Balance.INTERMISSION_SECONDS - 0.3)
	_check(_wave_started.is_empty(), "Welle 2 beginnt nicht vor Ablauf der Pause.")
	_step_waves(0.5)
	_check(_ticks == [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0], "Die Pause zählt 12 bis 0 (ist %s)." % str(_ticks))
	var total: int = WavePlan.total_count(2)
	_check(_wave_started.size() == 1 and _wave_started[0] == [2, total], "wave_started(2, %d) nach der Pause (ist %s)." % [total, str(_wave_started)])
	_check(_banners.size() >= 1 and _banners[0].begins_with("Welle 2"), "Banner zu Welle 2.")
	_remove_all_zombies()


func _test_planned_counts() -> void:
	_game.call("start_run", 4)
	_game.set("player", _player)
	_waves.set("auto_start", false)
	for wave: int in [3, 2]:
		_clear_log()
		_waves.call("start_wave", wave)
		var plan: Array[String] = WavePlan.spawn_list(wave)
		_check(_wave_started.size() == 1 and _wave_started[0] == [wave, plan.size()], "start_wave(%d) sendet wave_started mit %d Zombies." % [wave, plan.size()])
		_step_waves(WavePlan.spawn_interval(wave) * float(plan.size()) + 2.0)
		var types: Array[String] = []
		for zombie: Node3D in _spawned:
			types.append(String(zombie.get("zombie_type")))
		_check(types == plan, "Welle %d erscheint in der Reihenfolge des Wellenplans (%d von %d)." % [wave, types.size(), plan.size()])
		_check(types.count("walker") == WavePlan.walker_count(wave) and types.count("sprinter") == WavePlan.sprinter_count(wave)
				and types.count("elite") == WavePlan.elite_count(wave), "Welle %d: Anzahl je Typ stimmt." % wave)
		_check(int(_waves.call("get_queued_count")) == 0 and int(_waves.call("get_wave_alive_count")) == plan.size(),
				"Welle %d: alle erschienen, alle am Leben." % wave)
		var elite_hp_ok: bool = true
		for zombie: Node3D in _spawned:
			if not is_equal_approx(float(zombie.get("max_hp")), WavePlan.zombie_hp(String(zombie.get("zombie_type")), wave)):
				elite_hp_ok = false
		_check(elite_hp_ok, "Welle %d: Leben aller Zombies nach WavePlan." % wave)
		for zombie: Node3D in _spawned.duplicate():
			_kill(zombie)
		_check(_wave_cleared == [wave], "Welle %d endet, wenn alle tot sind." % wave)
		_check(_killed.size() == plan.size(), "Welle %d: ein zombie_killed je Zombie." % wave)
	_remove_all_zombies()


func _test_max_alive() -> void:
	_game.call("start_run", 5)
	_game.set("player", _player)
	_waves.set("auto_start", false)
	_clear_log()
	var wave: int = 6
	var total: int = WavePlan.total_count(wave)
	_check(total > Balance.MAX_ZOMBIES_ALIVE, "Welle 6 hat mehr Zombies als gleichzeitig leben dürfen.")
	_waves.call("start_wave", wave)
	var interval: float = WavePlan.spawn_interval(wave)
	var peak: int = 0
	for i: int in roundi((interval * float(Balance.MAX_ZOMBIES_ALIVE) + 6.0) / 0.1):
		_waves.call("_process", 0.1)
		peak = maxi(peak, _alive_zombies().size())
	_check(peak == Balance.MAX_ZOMBIES_ALIVE, "Es leben höchstens 24 Zombies gleichzeitig (Höchststand %d)." % peak)
	_check(_spawned.size() == Balance.MAX_ZOMBIES_ALIVE, "Bei 24 Lebenden wartet der Rest (erschienen: %d)." % _spawned.size())
	_check(int(_waves.call("get_queued_count")) == total - Balance.MAX_ZOMBIES_ALIVE, "Der Rest der Welle wartet in der Schlange.")
	_check(int(_waves.get("zombies_left")) == total, "Wartende zählen zu zombies_left.")

	# Platz schaffen: Es rückt nach, aber wieder nur bis 24.
	var alive: Array[Node] = _alive_zombies()
	for i: int in 3:
		_kill(alive[i])
	_waves.call("_process", 0.1)
	_check(_alive_zombies().size() == Balance.MAX_ZOMBIES_ALIVE - 2, "Sobald Platz ist, rückt genau einer nach, kein Schwall.")
	for i: int in roundi((interval * 3.0 + 2.0) / 0.1):
		_waves.call("_process", 0.1)
		peak = maxi(peak, _alive_zombies().size())
	_check(_alive_zombies().size() == Balance.MAX_ZOMBIES_ALIVE and peak == Balance.MAX_ZOMBIES_ALIVE, "Nach den Kills füllt die Welle wieder auf 24 auf.")

	# Rest der Welle: töten, nachrücken lassen, bis alles durch ist.
	var rounds: int = 0
	while bool(_waves.get("is_wave_active")) and rounds < 40:
		rounds += 1
		for node: Node in _alive_zombies():
			_kill(node)
		for i: int in roundi((interval + 0.2) / 0.1):
			_waves.call("_process", 0.1)
			peak = maxi(peak, _alive_zombies().size())
	_check(_wave_cleared == [wave], "Auch eine Welle über der Obergrenze endet sauber.")
	_check(_spawned.size() == total and _killed.size() == total, "Alle %d Zombies der Welle sind erschienen und gestorben (%d / %d)." % [total, _spawned.size(), _killed.size()])
	_check(peak == Balance.MAX_ZOMBIES_ALIVE, "Die Obergrenze wurde nie überschritten.")
	_remove_all_zombies()


func _test_game_over_and_restart() -> void:
	_game.call("start_run", 6)
	_game.set("player", _player)
	_waves.set("auto_start", false)
	_clear_log()
	_waves.call("start_wave", 2)
	_step_waves(4.0)
	var before: int = _spawned.size()
	_check(before >= 2 and int(_spawner.call("alive_count")) == before, "Welle 2 läuft, Zombies sind da.")
	_game.call("end_run")
	_check(not bool(_waves.get("is_wave_active")), "Bei Game Over ist die Welle nicht mehr aktiv.")
	_check(float(_waves.call("get_countdown")) < 0.0, "Bei Game Over läuft kein Countdown.")
	_step_waves(10.0)
	_check(_spawned.size() == before, "Nach Game Over erscheint kein Zombie mehr.")
	_check(_wave_cleared.is_empty(), "Game Over sendet kein wave_cleared.")

	# Neuer Lauf in derselben Szene: alte Zombies weg, alles auf Anfang.
	_clear_log()
	_game.call("start_run", 7)
	_game.set("player", _player)
	_check(int(_spawner.call("alive_count")) == 0, "Ein neuer Lauf räumt die alten Zombies sofort weg.")
	_check(_killed.is_empty(), "Das Aufräumen gibt keine Kills.")
	_check(int(_waves.get("current_wave")) == 0 and int(_waves.get("zombies_left")) == 0, "Ein neuer Lauf beginnt bei Welle 0.")
	_check_near(float(_waves.call("get_countdown")), Balance.FIRST_WAVE_DELAY, "Ein neuer Lauf startet den Countdown zur ersten Welle.")
	_waves.set("auto_start", true)
	_step_waves(Balance.FIRST_WAVE_DELAY + 0.5)
	_check(_wave_started.size() == 1 and _wave_started[0] == [1, 10], "Der neue Lauf beginnt wieder mit Welle 1.")
	_waves.set("auto_start", false)
	_remove_all_zombies()


func _test_stuck_safety() -> void:
	_game.call("start_run", 8)
	_game.set("player", _player)
	_player.position = Vector3.ZERO
	_waves.set("auto_start", false)
	_clear_log()
	_waves.call("start_wave", 1)
	_step_waves(3.5)
	_check(_spawned.size() >= 2, "Die Welle läuft.")
	if _spawned.is_empty():
		return

	# Aus der Welt gefallen: kommt an einen Spawnpunkt zurück, lebt weiter, zählt weiter.
	var fallen: Node3D = _spawned[0]
	fallen.global_position = Vector3(3.0, -60.0, 3.0)
	_step_waves(1.5)
	_check(is_instance_valid(fallen) and not bool(fallen.get("is_dead")), "Ein gefallener Zombie wird nicht einfach gelöscht.")
	if is_instance_valid(fallen):
		_check(fallen.global_position.y > -1.0, "Ein gefallener Zombie kommt in die Welt zurück (y = %.1f)." % fallen.global_position.y)
		var marker: Marker3D = _nearest_spawn(fallen.global_position)
		_check(_flat_distance(marker.global_position, fallen.global_position) < 0.1 and int(marker.get_meta("zone")) == 1,
				"Er steht danach an einem aktiven Spawnpunkt.")
	_check(int(_waves.get("zombies_left")) == 10 and _killed.is_empty(), "Die Rettung ändert die Zählung nicht.")

	# Unerreichbar: Ohne echte Bilder bewegt sich hier kein Zombie. Alle stehen fern vom Spieler
	# und kommen nie an. Die Welle muss trotzdem enden, ohne Kills und ohne Punkte.
	var points_before: int = int(_game.get("points"))
	var kills_before: int = int(_game.get("kills"))
	var simulated: float = 0.0
	while bool(_waves.get("is_wave_active")) and simulated < 400.0:
		_step_waves(1.0, 0.5)
		simulated += 1.0
	_check(not bool(_waves.get("is_wave_active")) and _wave_cleared == [1],
			"Eine Welle mit unerreichbaren Zombies endet von selbst (nach %.0f s)." % simulated)
	_check(_killed.is_empty(), "Die Auflösung sendet kein zombie_killed.")
	_check(int(_game.get("points")) == points_before and int(_game.get("kills")) == kills_before, "Die Auflösung gibt weder Punkte noch Kills.")
	_check(int(_waves.get("zombies_left")) == 0 and int(_spawner.call("alive_count")) == 0, "Danach ist kein Zombie der Welle mehr da.")
	_check_near(float(_waves.call("get_countdown")), Balance.INTERMISSION_SECONDS, "Danach läuft die normale Pause.")

	# Ein Zombie beim Spieler gilt nicht als festhängend, auch wenn er steht.
	_clear_log()
	_waves.call("start_wave", 1)
	_step_waves(0.3)
	if not _spawned.is_empty():
		var close: Node3D = _spawned[0]
		close.global_position = Vector3(1.5, 0.0, 0.0)
		_step_waves(60.0, 0.5)
		_check(is_instance_valid(close) and not bool(close.get("is_dead")), "Ein Zombie beim Spieler wird nicht weggeräumt.")
		if is_instance_valid(close):
			_check(_flat_distance(close.global_position, Vector3(1.5, 0.0, 0.0)) < 0.5, "Ein Zombie beim Spieler wird nicht umgesetzt.")
	_remove_all_zombies()


func _test_count_repair() -> void:
	_game.call("start_run", 9)
	_game.set("player", _player)
	_waves.set("auto_start", false)
	_clear_log()
	_waves.call("start_wave", 1)
	_step_waves(WavePlan.spawn_interval(1) * 10.0 + 1.0)
	_check(_spawned.size() == 10, "Welle 1 ist vollständig erschienen.")
	if _spawned.size() < 10:
		return
	# Ein Zombie verschwindet ohne zombie_killed (jemand ruft queue_free). Die Zahl wird berichtigt.
	_spawned[0].queue_free()
	_step_waves(4.0)
	_check(int(_waves.get("zombies_left")) == 9, "Verschwindet ein Zombie ohne Kill, wird zombies_left berichtigt (ist %d)." % int(_waves.get("zombies_left")))
	for i: int in range(1, 10):
		_kill(_spawned[i])
	_check(_wave_cleared == [1], "Die Welle endet trotzdem.")
	# Neue Welle, während eine läuft: Die alten Zombies zählen nicht mehr.
	_clear_log()
	_waves.call("start_wave", 1)
	_step_waves(3.0)
	var old_zombies: Array[Node3D] = _spawned.duplicate()
	_clear_log()
	_waves.call("start_wave", 2)
	for zombie: Node3D in old_zombies:
		_kill(zombie)
	_check(int(_waves.get("zombies_left")) == WavePlan.total_count(2), "Zombies einer abgebrochenen Welle zählen nicht für die neue.")
	_remove_all_zombies()


# --- Wegfindung ------------------------------------------------------------------------------

func _add_block(position: Vector3, size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = Balance.LAYER_WORLD
	body.collision_mask = 0
	body.position = position
	body.add_to_group("nav_source")
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	return body


func _test_navigation_and_hop() -> void:
	_game.call("start_run", 10)
	_game.set("player", _player)
	_waves.set("auto_start", false)
	_remove_all_zombies()
	# Eine Wand zwischen Zombie und Spieler, dazu ein gebackenes Navigationsnetz: Der Zombie muss
	# außen herum laufen. Geradeaus bliebe er an der Wand hängen.
	var wall: StaticBody3D = _add_block(Vector3(5.0, 1.5, 30.0), Vector3(1.0, 3.0, 12.0))
	var region: NavigationRegion3D = NavigationRegion3D.new()
	var nav_mesh: NavigationMesh = NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = "nav_source"
	nav_mesh.agent_radius = 0.5
	region.navigation_mesh = nav_mesh
	_world.add_child(region)
	region.bake_navigation_mesh(false)
	_check(nav_mesh.get_polygon_count() > 0, "Das Navigationsnetz der Testwelt wurde gebacken.")
	for i: int in 4:
		await physics_frame
	_player.position = Vector3(10.0, 0.0, 30.0)
	_player.is_dead = false
	_player.hits.clear()
	var runner: CharacterBody3D = _make_zombie("sprinter", 3, Vector3(0.0, 0.0, 30.0))
	var widest: float = 0.0
	var frames: int = 0
	while _player.hits.is_empty() and frames < 720:
		await physics_frame
		frames += 1
		widest = maxf(widest, absf(runner.global_position.z - 30.0))
	_check(not _player.hits.is_empty(), "Mit Navigationsnetz erreicht der Zombie den Spieler hinter der Wand (nach %d Bildern)." % frames)
	_check(widest > 5.0, "Der Zombie läuft um die Wand herum (seitlicher Ausschlag %.1f m)." % widest)
	runner.call("despawn")
	wall.queue_free()
	region.queue_free()
	for i: int in 4:
		await physics_frame

	# Niedrige Kante ohne Navigationsnetz: Der Spieler steht auf einer 0,4 m hohen Bühne
	# (Balance.STAGE_HEIGHT), der Zombie springt hinauf.
	var stage: StaticBody3D = _add_block(Vector3(-10.0, Balance.STAGE_HEIGHT * 0.5, 30.0), Vector3(6.0, Balance.STAGE_HEIGHT, 6.0))
	for i: int in 2:
		await physics_frame
	_player.position = Vector3(-10.0, Balance.STAGE_HEIGHT, 30.0)
	_player.hits.clear()
	var climber: CharacterBody3D = _make_zombie("walker", 1, Vector3(-5.0, 0.0, 30.4))
	frames = 0
	while _player.hits.is_empty() and frames < 900:
		await physics_frame
		frames += 1
	_check(not _player.hits.is_empty(), "Der Zombie kommt auf die Bühne und erreicht den Spieler (nach %d Bildern)." % frames)
	_check(climber.global_position.y > Balance.STAGE_HEIGHT - 0.1, "Der Zombie steht danach auf der Bühne (y = %.2f)." % climber.global_position.y)
	climber.call("despawn")
	stage.queue_free()
	_player.position = Vector3.ZERO
	_player.hits.clear()
	await process_frame


# --- Hilfen ----------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)


func _check_near(actual: float, expected: float, message: String) -> void:
	_checks += 1
	if absf(actual - expected) > EPSILON:
		_failures += 1
		printerr("FEHLER: %s (erwartet %.3f, ist %.3f)" % [message, expected, actual])
