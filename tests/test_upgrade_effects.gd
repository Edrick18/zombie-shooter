extends SceneTree
## Tests für das Upgrade-Modul: UpgradeEffects, Drohne, Kiste, ChestDropper und die Effekte (Fx).
## Läuft headless ohne Hauptszene: Ersatz-Zombies (Gruppe "zombies", Zombie-Schnittstelle aus
## Abschnitt 7) und ein Ersatz-Spieler stehen für die anderen Module.
##
## Geprüft wird je Upgrade eine messbare Wirkung auf Stufe 1 und Stufe 5 mit festem Seed in
## Game.rng, dazu die Synergie Gewitterfront (sicherer Blitz, Obergrenze je Schuss), die
## Obergrenze der Explosionsketten, die Obergrenze des Lebensraubs, die Kiste (Wahl öffnen,
## Angebot anwenden) und die Fallregeln des ChestDroppers.
##
## Abschnitt 18 (mehrfache Wirkung): Kugel-Effekte gelten je Waffe (echter Rucksack mit zwei
## Pistolen, Treffer tragen info["weapon_uid"]), mehrere Exemplare verbinden ihre Werte, jede
## Kameradrohne im Rucksack ist eine eigene Drohne, und die Druckwelle hört auf beide Hände.
## Seit Abschnitt 22 ist die Kameradrohne eine Kamera mit festen Werten: Sie kommt nur noch über
## den Rucksack ins Spiel (Game.cameras), nicht mehr über Game.upgrades.add_levels.
## Die Waffensteuerung ist nicht beteiligt: Die Tests senden bullet_hit selbst.
##
## Abschnitt 19: Gift (Kantinenessen, je Waffe, tickt am echten Zombie aus zombie.gd),
## Trostpflaster (Heilung je Kill), Discokugel (eine kreisende Kugel je Exemplar) und Störsender
## (Elektroschlag im Takt). Die Zeit dieser Effekte treibt der Test selbst an (tick, _step_zombie).
##
## Abschnitt 22: je Eintrag aus Game.cameras ein Kamera-Knoten (Tele, Blitzlicht, Zeitlupe, Regie
## und die Drohne) mit festen Werten, die Zweitkamera für alle fünf, camera_fired, dazu die
## Gegenstände Trockeneis, Querschläger, Kaktus-Requisite, Pausensnack und Requisitenbombe.
##
## Die Autoloads werden über root.get_node geholt und die Spielskripte zur Laufzeit geladen,
## weil ein -s-Skript die Namen Game und Events beim Übersetzen nicht kennt (Abschnitt 13.7).

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")

const SEED: int = 4711
const HUGE_HP: float = 1.0e9
const ZOMBIE_PATH: String = "res://scripts/game/zombies/zombie.gd"


## Ersatz-Zombie mit der Schnittstelle aus Abschnitt 7. Er merkt sich jeden Treffer.
class DummyZombie:
	extends Node3D
	var events: Node = null
	var zombie_type: String = "walker"
	var max_hp: float = 100.0
	var hp: float = 100.0
	var is_dead: bool = false
	var wave: int = 1
	var body_height: float = 1.8
	var body_radius: float = 0.35
	## Jeder Treffer: { "amount": float, "source": String, "info": Dictionary }.
	var hits: Array[Dictionary] = []
	var burn_dps: float = 0.0
	var burn_duration: float = 0.0
	var burn_calls: int = 0
	var poison_dps: float = 0.0
	var poison_duration: float = 0.0
	var poison_calls: int = 0
	var knockback: Vector3 = Vector3.ZERO
	var slow_factor: float = 0.0
	var slow_duration: float = 0.0
	var slow_calls: int = 0
	var mark_bonus: float = 0.0
	var mark_duration: float = 0.0
	var mark_calls: int = 0
	## Dieser Knoten verschwindet sofort, wenn der Zombie stirbt (Zombie weg mitten in einer Schleife).
	var vanishes_with_me: Node = null

	func _ready() -> void:
		add_to_group("zombies")

	func setup(type: String, wave_number: int) -> void:
		zombie_type = type
		wave = wave_number

	func take_damage(amount: float, info: Dictionary) -> void:
		if is_dead or amount <= 0.0:
			return
		hp = maxf(0.0, hp - amount)
		hits.append({"amount": amount, "source": String(info.get("source", "")), "info": info})
		events.emit_signal("zombie_damaged", self, amount, info)
		if hp <= 0.0 and not is_dead:
			is_dead = true
			remove_from_group("zombies")
			if is_instance_valid(vanishes_with_me):
				vanishes_with_me.free()
			events.emit_signal("zombie_killed", self, info)

	func apply_burn(dps: float, duration: float) -> void:
		burn_calls += 1
		burn_dps = dps
		burn_duration = duration

	func apply_poison(dps: float, duration: float) -> void:
		poison_calls += 1
		poison_dps = dps
		poison_duration = duration

	func apply_knockback(impulse: Vector3) -> void:
		knockback += impulse

	func apply_slow(factor: float, duration: float) -> void:
		slow_calls += 1
		slow_factor = factor
		slow_duration = duration

	func is_slowed() -> bool:
		return slow_duration > 0.0

	func apply_mark(bonus: float, duration: float) -> void:
		mark_calls += 1
		mark_bonus = bonus
		mark_duration = duration

	func is_marked() -> bool:
		return mark_duration > 0.0

	func is_burning() -> bool:
		return burn_duration > 0.0

	func is_headshot(_hit_position: Vector3) -> bool:
		return false

	func get_center_position() -> Vector3:
		return global_position + Vector3(0.0, body_height * 0.5, 0.0)

	func count(source: String) -> int:
		var n: int = 0
		for hit: Dictionary in hits:
			if hit["source"] == source:
				n += 1
		return n

	func total(source: String) -> float:
		var sum: float = 0.0
		for hit: Dictionary in hits:
			if hit["source"] == source:
				sum += float(hit["amount"])
		return sum


## Ersatz-Spieler: Leben, Heilung, Blick nach -Z.
class DummyPlayer:
	extends Node3D
	var hp: float = 100.0
	var max_hp: float = 100.0
	var is_dead: bool = false
	var healed: float = 0.0

	func heal(amount: float) -> void:
		healed += amount
		hp = minf(max_hp, hp + amount)

	func take_damage(amount: float) -> void:
		hp = maxf(0.0, hp - amount)

	func get_eye_position() -> Vector3:
		return global_position + Vector3(0.0, 1.6, 0.0)

	func get_aim_direction() -> Vector3:
		return Vector3.FORWARD


var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
var _effects: Node
var _player: DummyPlayer
var _zombie_root: Node3D
var _fx_root: Node3D
var _chest_root: Node3D
var _dropped_chests: Array = []
## Mitschrift für die Tests mit echten Zombies (nur solange _logging an ist): jeder Schaden als
## { "zombie": Node3D, "amount": float, "source": String }, jeder Kill als { "zombie", "source" }
## und die Zahl der bullet_hit-Signale.
var _logging: bool = false
var _damage_log: Array[Dictionary] = []
var _kill_log: Array[Dictionary] = []
var _bullet_hits: int = 0
## Mitschrift der Signale aus Abschnitt 22 (immer an): Signalname -> Liste der Argument-Listen.
## camera_fired [camera_id, position], mine_placed [position], mine_triggered [position],
## explosion [position, radius].
var _signal_log: Dictionary = {}


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum und ihr _ready ist gelaufen.
	await process_frame
	_game = root.get_node_or_null("Game")
	_events = root.get_node_or_null("Events")
	_check(_game != null and _events != null, "Autoloads Game und Events hängen im Baum.")
	if _game == null or _events == null:
		quit(1)
		return
	_build_world()

	_test_value_upgrades()
	_test_chain_lightning()
	_test_bullet_effects_per_weapon()
	_test_bullet_effects_stack()
	_test_general_upgrades_reach_every_weapon()
	await _test_storm_front()
	_test_storm_front_per_weapon()
	_test_burn()
	_test_lifesteal()
	_test_lifesteal_stacks()
	_test_corpse_explosion()
	_test_corpse_explosion_stacks()
	_test_explosion_chain_cap()
	_test_vanishing_zombies()
	_test_reload_shockwave()
	_test_reload_shockwave_hands()
	await _test_drone()
	await _test_drones_per_copy()
	await _test_camera_nodes()
	await _test_cam_tele()
	await _test_cam_flash()
	_test_cam_slow()
	_test_cam_director()
	_test_drone_second()
	_test_frost()
	_test_ricochet()
	_test_thorns()
	_test_snack()
	await _test_mines()
	_test_poison_per_weapon()
	_test_poison_ticks()
	_test_poison_with_other_effects()
	_test_kill_heal()
	await _test_disco_balls()
	_test_disco_ball_hits()
	_test_jammer()
	_test_non_bullet_damage_is_inert()
	await _test_chest()
	await _test_chest_dropper()
	await _test_fx_cleans_up()

	paused = false
	if _failures == 0:
		print("Alle Upgrade-Effekt-Tests bestanden (%d Prüfungen)." % _checks)
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


# --- Aufbau und Hilfen ---

func _build_world() -> void:
	_fx_root = Node3D.new()
	_fx_root.name = "Fx"
	_fx_root.add_to_group("fx_root")
	root.add_child(_fx_root)
	_zombie_root = Node3D.new()
	_zombie_root.name = "Zombies"
	root.add_child(_zombie_root)
	_chest_root = Node3D.new()
	_chest_root.name = "Chests"
	root.add_child(_chest_root)
	_player = DummyPlayer.new()
	_player.name = "Player"
	_player.add_to_group("player")
	root.add_child(_player)
	_game.set("player", _player)
	_effects = (load("res://scripts/game/upgrades/upgrade_effects.gd") as GDScript).new()
	_effects.name = "UpgradeEffects"
	root.add_child(_effects)
	_events.connect("chest_dropped", func(chest: Node3D) -> void: _dropped_chests.append(chest))
	_events.connect("zombie_damaged", _log_damage)
	_events.connect("zombie_killed", _log_kill)
	_events.connect("bullet_hit", _log_bullet_hit)
	_events.connect("camera_fired", func(camera_id: String, position: Vector3) -> void: _note("camera_fired", [camera_id, position]))
	_events.connect("mine_placed", func(position: Vector3) -> void: _note("mine_placed", [position]))
	_events.connect("mine_triggered", func(position: Vector3) -> void: _note("mine_triggered", [position]))
	_events.connect("explosion", func(position: Vector3, radius: float) -> void: _note("explosion", [position, radius]))


func _log_damage(zombie: Node3D, amount: float, info: Dictionary) -> void:
	if _logging:
		_damage_log.append({"zombie": zombie, "amount": amount, "source": String(info.get("source", ""))})


func _log_kill(zombie: Node3D, info: Dictionary) -> void:
	if _logging:
		_kill_log.append({"zombie": zombie, "source": String(info.get("source", ""))})


func _log_bullet_hit(_zombie_hit: Node3D, _damage: float, _info: Dictionary) -> void:
	if _logging:
		_bullet_hits += 1


## Neuer Lauf mit festem Seed, ohne Zombies, Spieler mit halbem Leben am Ursprung.
func _fresh_run(seed_value: int = SEED) -> void:
	for node: Node in _zombie_root.get_children():
		node.free()
	paused = false
	_game.call("start_run", seed_value)
	_player.position = Vector3.ZERO
	_player.max_hp = 100.0
	_player.hp = 50.0
	_player.healed = 0.0
	_player.is_dead = false


func _upgrades() -> RefCounted:
	return _game.get("upgrades") as RefCounted


func _give(upgrade_id: String, level: int) -> void:
	_upgrades().call("add_levels", upgrade_id, level)
	_check(int(_upgrades().call("get_level", upgrade_id)) == level, "%s steht auf Stufe %d." % [upgrade_id, level])


func _zombie(at: Vector3, max_hp: float = HUGE_HP, type: String = "walker") -> DummyZombie:
	var zombie: DummyZombie = DummyZombie.new()
	zombie.events = _events
	zombie.zombie_type = type
	zombie.max_hp = max_hp
	zombie.hp = max_hp
	zombie.position = at
	_zombie_root.add_child(zombie)
	return zombie


func _bullet_info(weapon_id: String = "pistol") -> Dictionary:
	return {"source": "bullet", "headshot": false, "weapon_id": weapon_id, "hit_position": Vector3.ZERO}


## Ein Kugeltreffer wie von der Waffe: erst Schaden, dann bullet_hit.
func _bullet_hit(zombie: DummyZombie, damage: float, weapon_id: String = "pistol") -> void:
	var info: Dictionary = _bullet_info(weapon_id)
	info["hit_position"] = zombie.get_center_position()
	zombie.take_damage(damage, info)
	_events.emit_signal("bullet_hit", zombie, damage, info)


## Ein ganzer Schuss mit einem Treffer: Treffer, danach weapon_fired (Reihenfolge der Waffe).
func _shot(zombie: DummyZombie, damage: float, weapon_id: String = "pistol") -> void:
	_bullet_hit(zombie, damage, weapon_id)
	_events.emit_signal("weapon_fired", weapon_id)


# --- Hilfen für den echten Rucksack (Abschnitt 18) ---

func _backpack() -> RefCounted:
	return _game.get("backpack") as RefCounted


## Legt einen Gegenstand an eine feste Stelle des Rucksacks. Der Start-Rucksack ohne Kandidat hat
## die Felder x 1 bis 4, y 1 bis 3. Danach _sync() rufen.
func _put(id: String, level: int, pos: Vector2i, rot: int) -> int:
	var uid: int = int(_backpack().call("add_item", id, level))
	_check(uid > 0 and bool(_backpack().call("place", uid, pos, rot)),
		"%s (Rarität %d) passt an %s mit Drehung %d." % [id, level, pos, rot])
	return uid


## Räumt einen Gegenstand an die erste passende Stelle. Danach _sync() rufen.
func _auto(id: String, level: int) -> int:
	var uid: int = int(_backpack().call("add_item", id, level))
	_check(uid > 0 and bool(_backpack().call("auto_place", uid)), "%s (Rarität %d) findet einen Platz." % [id, level])
	return uid


func _sync() -> void:
	_game.call("sync_build")


## Zwei Pistolen im frischen Rucksack: links oben (1,1) und rechts unten (3,3). Gibt ihre uids
## zurück, [linke Hand, rechte Hand]. Danach weitere Gegenstände legen und _sync() rufen.
func _two_pistols() -> Array[int]:
	_fresh_run()
	var left: int = _put("pistol", 1, Vector2i(1, 1), 0)
	var right: int = _put("pistol", 1, Vector2i(3, 3), 0)
	return [left, right]


## Wirken die Sterne dieses Gegenstands genau auf diese Waffen?
func _targets_are(item_uid: int, weapon_uids: Array) -> bool:
	var targets: Array = (_backpack().call("star_targets", item_uid) as Array).duplicate()
	var wanted: Array = weapon_uids.duplicate()
	targets.sort()
	wanted.sort()
	if targets.size() != wanted.size():
		return false
	for i: int in targets.size():
		if int(targets[i]) != int(wanted[i]):
			return false
	return true


func _bullet_value(weapon_uid: int, id: String, key: String) -> float:
	return float(_game.call("bullet_value", weapon_uid, id, key))


func _bullet_level(weapon_uid: int, id: String) -> int:
	return int(_game.call("bullet_level", weapon_uid, id))


## Ein ganzer Schuss mit einem Treffer wie von der Waffensteuerung seit Abschnitt 18: Der Treffer
## nennt die Waffe (weapon_uid), danach kommt weapon_fired.
func _weapon_shot(zombie: DummyZombie, damage: float, weapon_uid: int, weapon_id: String = "pistol") -> void:
	var info: Dictionary = _bullet_info(weapon_id)
	info["weapon_uid"] = weapon_uid
	info["weapon"] = weapon_id
	info["hand"] = 0
	info["hit_position"] = zombie.get_center_position()
	zombie.take_damage(damage, info)
	_events.emit_signal("bullet_hit", zombie, damage, info)
	_events.emit_signal("weapon_fired", weapon_id)


func _drones() -> Array:
	return _effects.get("drones") as Array


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: %s" % message)


func _near(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) <= tolerance


# --- Upgrades, deren Wirkung in Game, Spieler oder Waffe sitzt ---

## pierce, max_hp, speed, luck: Das Upgrade-Modul liefert hier nur die Werte. Geprüft wird die
## Kette Game.upgrades -> Wert, den die anderen Module lesen, auf Stufe 1 und 5.
func _test_value_upgrades() -> void:
	var expected: Dictionary = {
		1: {"targets": 1.0, "bonus_hp": 20.0, "speed": 1.08, "points": 110, "chest": 0.04},
		5: {"targets": 5.0, "bonus_hp": 100.0, "speed": 1.40, "points": 150, "chest": 0.08},
	}
	for level: int in [1, 5]:
		_fresh_run()
		_give("pierce", level)
		_give("max_hp", level)
		_give("speed", level)
		_give("luck", level)
		var want: Dictionary = expected[level]
		var upgrades: RefCounted = _upgrades()
		_check(_near(float(upgrades.call("value", "pierce", "targets")), float(want["targets"])),
			"Spezialmunition Stufe %d: %d weitere Ziele." % [level, int(want["targets"])])
		_check(_near(float(upgrades.call("bonus_max_hp")), float(want["bonus_hp"])),
			"Stuntdouble Stufe %d: +%d Maximal-Leben." % [level, int(want["bonus_hp"])])
		_check(_near(float(upgrades.call("speed_multiplier")), float(want["speed"])),
			"Turbo-Turnschuhe Stufe %d: Tempo-Faktor %s." % [level, want["speed"]])
		_game.call("add_points", 100)
		_check(int(_game.get("points")) == int(want["points"]),
			"Publikumsliebling Stufe %d: 100 Punkte werden zu %d, waren %d." % [level, int(want["points"]), int(_game.get("points"))])
		_check(_near(ChestRoller.drop_chance(false, upgrades), float(want["chest"])),
			"Publikumsliebling Stufe %d: Kistenchance %s." % [level, want["chest"]])
		_check(int(upgrades.call("luck_level")) == level, "Glück-Stufe %d für die Seltenheit." % level)
	_check(_near(WeaponDefs.pierce_damage_factor(1), 1.0 - Balance.PIERCE_DAMAGE_FALLOFF),
		"Durchschlag: Das zweite Ziel bekommt 15 % weniger Schaden.")


# --- Kettenblitz ---

func _test_chain_lightning() -> void:
	# Stufe 1: 10 % Chance, 2 Sprünge, 50 % Schaden. Stufe 5: 30 %, 6 Sprünge, 100 %.
	for level: int in [1, 5]:
		_fresh_run()
		_give("chain_lightning", level)
		var jumps: int = int(UpgradeDefs.value("chain_lightning", "jumps", level))
		var factor: float = UpgradeDefs.value("chain_lightning", "damage_factor", level)
		var chance: float = UpgradeDefs.value("chain_lightning", "chance", level)
		var origin: DummyZombie = _zombie(Vector3.ZERO)
		# Eine Reihe im Abstand von 2 m: Der Blitz hüpft die Reihe entlang.
		var line: Array[DummyZombie] = []
		for i: int in 8:
			line.append(_zombie(Vector3(2.0 * float(i + 1), 0.0, 0.0)))
		var far: DummyZombie = _zombie(Vector3(0.0, 0.0, 60.0))
		var shots: int = 2000
		for i: int in shots:
			_shot(origin, 20.0)
		var procs: int = line[0].count("lightning")
		var rate: float = float(procs) / float(shots)
		_check(absf(rate - chance) < 0.03,
			"Starkstrom-Sponsor Stufe %d: Blitz bei etwa %d %% der Treffer, waren %.1f %%." % [level, int(chance * 100.0), rate * 100.0])
		for i: int in line.size():
			var want_hits: int = procs if i < jumps else 0
			_check(line[i].count("lightning") == want_hits,
				"Stufe %d: Zombie %d der Reihe wird %d-mal getroffen, waren %d." % [level, i + 1, want_hits, line[i].count("lightning")])
		_check(procs > 0 and _near(line[0].total("lightning"), float(procs) * 20.0 * factor, 0.01),
			"Stufe %d: Blitzschaden ist %d %% des Kugelschadens." % [level, int(factor * 100.0)])
		_check(origin.count("lightning") == 0, "Stufe %d: Der getroffene Zombie selbst bekommt keinen Blitz." % level)
		_check(far.hits.is_empty(), "Stufe %d: Ein Zombie außer Reichweite bleibt unberührt." % level)

		# Schrotkugeln: Chance mal 0,35.
		var before: int = line[0].count("lightning")
		for i: int in shots:
			_shot(origin, 14.0, "shotgun")
		var pellet_rate: float = float(line[0].count("lightning") - before) / float(shots)
		_check(absf(pellet_rate - chance * Balance.CHAIN_PELLET_CHANCE_FACTOR) < 0.02,
			"Stufe %d: Schrotkugel löst mit %.1f %% aus, waren %.1f %%." % [level, chance * Balance.CHAIN_PELLET_CHANCE_FACTOR * 100.0, pellet_rate * 100.0])

	# Reichweite gilt von Sprung zu Sprung: 5 m, weitere 5 m, dann 7 m (zu weit).
	_fresh_run()
	_give("chain_lightning", 5)
	_give("pierce", 5)
	var start: DummyZombie = _zombie(Vector3.ZERO)
	var first: DummyZombie = _zombie(Vector3(5.0, 0.0, 0.0))
	var second: DummyZombie = _zombie(Vector3(10.0, 0.0, 0.0))
	var third: DummyZombie = _zombie(Vector3(17.0, 0.0, 0.0))
	_shot(start, 30.0)
	_check(first.count("lightning") == 1 and second.count("lightning") == 1,
		"Der Blitz springt vom ersten zum zweiten Zombie weiter (je 5 m).")
	_check(third.count("lightning") == 0, "7 m sind für den nächsten Sprung zu weit.")
	# Ein toter Zombie am Ursprung leitet den Blitz trotzdem weiter.
	var victim: DummyZombie = _zombie(Vector3(0.0, 0.0, 3.0), 10.0)
	var hits_before: int = start.count("lightning")
	_shot(victim, 30.0)
	_check(victim.is_dead and start.count("lightning") == hits_before + 1,
		"Auch ein tödlicher Kugeltreffer löst den Blitz aus.")


# --- Kugel-Effekte je Waffe (Abschnitt 18) ---

## Zwei Pistolen, Kettenblitz und Brand berühren mit ihren Sternen nur die linke: Nur ihre
## Treffer blitzen und zünden. Die rechte Pistole, die Dienstpistole (uid 0) und Treffer ohne
## Waffe (-1 oder gar keine Angabe) bleiben ohne Kugel-Effekt.
func _test_bullet_effects_per_weapon() -> void:
	var pistols: Array[int] = _two_pistols()
	var left: int = pistols[0]
	var right: int = pistols[1]
	var chain: int = _put("chain_lightning", 5, Vector2i(3, 1), 0)
	var burn: int = _put("burn", 2, Vector2i(1, 2), 3)
	_sync()
	var loadout: Array = _game.get("loadout")
	_check(loadout.size() == 2 and int((loadout[0] as Dictionary)["uid"]) == left and int((loadout[1] as Dictionary)["uid"]) == right,
		"Zwei Pistolen in der Hand: links uid %d, rechts uid %d." % [left, right])
	_check(_targets_are(chain, [left]) and _targets_are(burn, [left]),
		"Kettenblitz und Brand berühren mit ihren Sternen nur die linke Pistole.")
	_check(_bullet_level(left, "chain_lightning") == 5 and _bullet_level(left, "burn") == 2,
		"Für die linke Pistole wirken Kettenblitz (5) und Brand (2).")
	for other: int in [right, 0, -1]:
		_check(_bullet_level(other, "chain_lightning") == 0 and _bullet_level(other, "burn") == 0,
			"Für die Waffe %d wirkt kein Kugel-Effekt." % other)
	var chance: float = UpgradeDefs.value("chain_lightning", "chance", 5)
	var burn_percent: float = UpgradeDefs.value("burn", "dps_percent", 2)
	var origin: DummyZombie = _zombie(Vector3.ZERO, 200.0)
	origin.hp = HUGE_HP
	var neighbor: DummyZombie = _zombie(Vector3(2.0, 0.0, 0.0))

	# Die anderen Waffen zuerst: nichts passiert.
	for other: int in [right, 0, -1]:
		for i: int in 300:
			_weapon_shot(origin, 20.0, other)
		_check(neighbor.count("lightning") == 0, "Treffer der Waffe %d lösen keinen Blitz aus, waren %d." % [other, neighbor.count("lightning")])
		_check(origin.burn_calls == 0, "Treffer der Waffe %d zünden niemanden an." % other)
	# Treffer ganz ohne Angabe der Waffe (ältere Abläufe) zählen wie -1.
	for i: int in 300:
		_shot(origin, 20.0)
	_check(neighbor.count("lightning") == 0 and origin.burn_calls == 0, "Treffer ohne weapon_uid bleiben ohne Kugel-Effekt.")

	# Die linke Pistole: Blitz mit der Chance der Stufe 5, Brand mit dem Anteil der Stufe 2.
	var shots: int = 1000
	for i: int in shots:
		_weapon_shot(origin, 20.0, left)
	var rate: float = float(neighbor.count("lightning")) / float(shots)
	_check(absf(rate - chance) < 0.05,
		"Die linke Pistole blitzt bei etwa %d %% der Treffer, waren %.1f %%." % [int(chance * 100.0), rate * 100.0])
	_check(origin.burn_calls == shots and _near(origin.burn_dps, burn_percent * 200.0),
		"Die linke Pistole zündet an: %s Leben je Sekunde, waren %s." % [burn_percent * 200.0, origin.burn_dps])

	# Liegt der Brand in der Ablage, wirkt er auch für die linke Pistole nicht mehr.
	_backpack().call("store", burn)
	_sync()
	var calls_before: int = origin.burn_calls
	_weapon_shot(origin, 20.0, left)
	_check(_bullet_level(left, "burn") == 0 and origin.burn_calls == calls_before, "Ohne den Gegenstand im Raster zündet die linke Pistole nicht mehr.")


## Zwei Exemplare auf derselben Waffe verbinden ihre Werte: Die Chance und die Sprünge des
## Blitzes addieren sich, sein Schadensanteil ist der beste, der Brand addiert sich.
func _test_bullet_effects_stack() -> void:
	# Kettenblitz Gewöhnlich (10 %, 2 Sprünge, 50 %) und Selten (20 %, 4 Sprünge, 70 %).
	var pistols: Array[int] = _two_pistols()
	var left: int = pistols[0]
	var right: int = pistols[1]
	var chain_a: int = _put("chain_lightning", 1, Vector2i(3, 1), 0)
	var chain_b: int = _put("chain_lightning", 3, Vector2i(1, 2), 1)
	_sync()
	_check(_targets_are(chain_a, [left]) and _targets_are(chain_b, [left]), "Beide Kettenblitze wirken auf die linke Pistole.")
	var chance: float = UpgradeDefs.value("chain_lightning", "chance", 1) + UpgradeDefs.value("chain_lightning", "chance", 3)
	var jumps: int = int(UpgradeDefs.value("chain_lightning", "jumps", 1) + UpgradeDefs.value("chain_lightning", "jumps", 3))
	var factor: float = UpgradeDefs.value("chain_lightning", "damage_factor", 3)
	_check(_near(_bullet_value(left, "chain_lightning", "chance"), chance) and _near(chance, 0.30),
		"Zwei Kettenblitze: Die Chancen addieren sich zu 30 %.")
	_check(int(_bullet_value(left, "chain_lightning", "jumps")) == jumps and jumps == 6, "Zwei Kettenblitze: Die Sprünge addieren sich zu 6.")
	_check(_near(_bullet_value(left, "chain_lightning", "damage_factor"), factor), "Zwei Kettenblitze: Der beste Schadensanteil zählt.")
	_check(_near(_bullet_value(right, "chain_lightning", "chance"), 0.0), "Die rechte Pistole hat davon nichts.")
	var origin: DummyZombie = _zombie(Vector3.ZERO)
	var line: Array[DummyZombie] = []
	for i: int in 8:
		line.append(_zombie(Vector3(2.0 * float(i + 1), 0.0, 0.0)))
	for i: int in 300:
		_weapon_shot(origin, 20.0, right)
	_check(line[0].count("lightning") == 0, "Die rechte Pistole blitzt nicht.")
	var shots: int = 1000
	for i: int in shots:
		_weapon_shot(origin, 20.0, left)
	var procs: int = line[0].count("lightning")
	var rate: float = float(procs) / float(shots)
	_check(absf(rate - chance) < 0.05, "Zwei Kettenblitze: Blitz bei etwa 30 %% der Treffer, waren %.1f %%." % (rate * 100.0))
	var jumps_ok: bool = procs > 0
	for i: int in line.size():
		if line[i].count("lightning") != (procs if i < jumps else 0):
			jumps_ok = false
	_check(jumps_ok, "Zwei Kettenblitze: Jeder Blitz springt genau %d Zombies weit." % jumps)
	_check(_near(line[0].total("lightning"), float(procs) * 20.0 * factor, 0.01),
		"Zwei Kettenblitze: Der Blitz macht %d %% des Kugelschadens." % int(factor * 100.0))

	# Brand Gewöhnlich (3 %) und Ungewöhnlich (5 %) auf der linken Pistole: 8 % je Sekunde.
	pistols = _two_pistols()
	left = pistols[0]
	right = pistols[1]
	var burn_a: int = _put("burn", 1, Vector2i(1, 2), 3)
	var burn_b: int = _put("burn", 2, Vector2i(2, 1), 2)
	_sync()
	_check(_targets_are(burn_a, [left]) and _targets_are(burn_b, [left]), "Beide Feuershows wirken auf die linke Pistole.")
	var percent: float = UpgradeDefs.value("burn", "dps_percent", 1) + UpgradeDefs.value("burn", "dps_percent", 2)
	_check(_near(_bullet_value(left, "burn", "dps_percent"), percent) and _near(percent, 0.08), "Zwei Feuershows: Die Anteile addieren sich zu 8 %.")
	var walker: DummyZombie = _zombie(Vector3.ZERO, 200.0)
	_weapon_shot(walker, 10.0, right)
	_check(walker.burn_calls == 0, "Die rechte Pistole zündet nicht an.")
	_weapon_shot(walker, 10.0, left)
	_check(walker.burn_calls == 1 and _near(walker.burn_dps, percent * 200.0),
		"Zwei Feuershows: Der Zombie brennt mit %s Leben je Sekunde, waren %s." % [percent * 200.0, walker.burn_dps])
	# Eine davon verkauft: Es bleibt der Anteil der anderen.
	_game.call("sell_item", burn_b)
	_weapon_shot(walker, 10.0, left)
	_check(_near(walker.burn_dps, UpgradeDefs.value("burn", "dps_percent", 1) * 200.0), "Nach dem Verkauf einer Feuershow zählt nur noch die andere.")


## Von Hand gesetzte Stufen (Game.upgrades.add_levels) gelten allgemein: für jede Waffe, auch für
## die Dienstpistole und für Treffer ohne Angabe der Waffe.
func _test_general_upgrades_reach_every_weapon() -> void:
	var pistols: Array[int] = _two_pistols()
	_sync()
	_give("burn", 2)
	_give("chain_lightning", 5)
	_give("pierce", 5)
	_check(bool(_upgrades().call("has_synergy", "storm_front")), "Allgemein gesetzt: Die Gewitterfront ist aktiv.")
	var percent: float = UpgradeDefs.value("burn", "dps_percent", 2)
	var origin: DummyZombie = _zombie(Vector3.ZERO, 200.0)
	origin.hp = HUGE_HP
	var neighbor: DummyZombie = _zombie(Vector3(2.0, 0.0, 0.0))
	var shots: int = 0
	for weapon_uid: int in [pistols[0], pistols[1], 0, -1]:
		_check(_bullet_level(weapon_uid, "chain_lightning") == 5 and _near(_bullet_value(weapon_uid, "burn", "dps_percent"), percent),
			"Allgemein gesetzte Upgrades gelten für die Waffe %d." % weapon_uid)
		for i: int in 10:
			_weapon_shot(origin, 20.0, weapon_uid)
		shots += 10
		_check(neighbor.count("lightning") == shots, "Waffe %d: Jeder Treffer blitzt (Gewitterfront), waren %d von %d." % [weapon_uid, neighbor.count("lightning"), shots])
		_check(origin.burn_calls == shots and _near(origin.burn_dps, percent * 200.0), "Waffe %d: Jeder Treffer zündet an." % weapon_uid)


# --- Synergie Gewitterfront ---

func _test_storm_front() -> void:
	_fresh_run()
	_give("chain_lightning", 5)
	_give("pierce", 5)
	_check(bool(_upgrades().call("has_synergy", "storm_front")), "Gewitterfront ist aktiv.")
	var origin: DummyZombie = _zombie(Vector3.ZERO)
	var neighbor: DummyZombie = _zombie(Vector3(2.0, 0.0, 0.0))
	var rng: RandomNumberGenerator = _game.get("rng")
	var state_before: int = rng.state

	# Sicher: 50 einzelne Schüsse, 50 Blitze.
	for i: int in 50:
		_shot(origin, 20.0)
	_check(neighbor.count("lightning") == 50, "Gewitterfront: Jeder Kugeltreffer löst sicher einen Blitz aus, waren %d von 50." % neighbor.count("lightning"))
	_check(rng.state == state_before, "Gewitterfront würfelt nicht: Game.rng bleibt unberührt.")

	# Obergrenze: ein Schuss mit 20 Treffern (Schrot mit Durchschlag) gibt höchstens 6 Blitze.
	var cap: int = Balance.STORM_FRONT_MAX_PROCS_PER_SHOT
	var before: int = neighbor.count("lightning")
	for i: int in 20:
		_bullet_hit(origin, 14.0, "shotgun")
	_check(neighbor.count("lightning") - before == cap,
		"Gewitterfront: höchstens %d Blitze je Schuss, waren %d." % [cap, neighbor.count("lightning") - before])
	_check(int(_effects.call("get_lightning_procs_this_shot")) == cap, "Der Zähler steht an der Obergrenze.")
	_events.emit_signal("weapon_fired", "shotgun")
	_check(int(_effects.call("get_lightning_procs_this_shot")) == 0, "weapon_fired beginnt einen neuen Schuss.")

	# Der nächste Schuss darf wieder, auch wenn weapon_fired vor den Treffern kommt.
	before = neighbor.count("lightning")
	_events.emit_signal("weapon_fired", "shotgun")
	for i: int in 20:
		_bullet_hit(origin, 14.0, "shotgun")
	_check(neighbor.count("lightning") - before == cap, "Auch mit weapon_fired vor den Treffern gilt die Grenze je Schuss.")

	# Ohne weapon_fired trennt das Bild die Schüsse: Treffer in einem späteren Bild zählen neu.
	await process_frame
	before = neighbor.count("lightning")
	_bullet_hit(origin, 14.0, "shotgun")
	_check(neighbor.count("lightning") - before == 1, "Ein Treffer in einem späteren Bild gehört zu einem neuen Schuss.")

	# Ein Treffer ohne Nachbarn in Reichweite verbraucht keine Auslösung.
	_events.emit_signal("weapon_fired", "pistol")
	var lonely: DummyZombie = _zombie(Vector3(0.0, 0.0, 80.0))
	_bullet_hit(lonely, 20.0)
	_check(int(_effects.call("get_lightning_procs_this_shot")) == 0, "Ein Blitz ohne Ziel zählt nicht als Auslösung.")


## Gewitterfront je Waffe: Legendärer Kettenblitz berührt beide Pistolen, die legendäre
## Spezialmunition nur die linke. Die linke blitzt sicher (mit Obergrenze je Schuss), die rechte
## würfelt mit der normalen Chance.
func _test_storm_front_per_weapon() -> void:
	_fresh_run()
	var left: int = _put("pistol", 1, Vector2i(1, 1), 0)
	var right: int = _put("pistol", 1, Vector2i(4, 1), 1)
	var pierce: int = _put("pierce", 5, Vector2i(1, 2), 0)
	var chain: int = _put("chain_lightning", 5, Vector2i(3, 1), 0)
	_sync()
	_check(_targets_are(pierce, [left]) and _targets_are(chain, [left, right]),
		"Spezialmunition wirkt auf die linke Pistole, der Kettenblitz auf beide.")
	_check(bool(_upgrades().call("has_synergy", "storm_front")), "Gewitterfront ist aktiv (linke Pistole).")
	var origin: DummyZombie = _zombie(Vector3.ZERO)
	var neighbor: DummyZombie = _zombie(Vector3(2.0, 0.0, 0.0))
	var rng: RandomNumberGenerator = _game.get("rng")
	var state_before: int = rng.state
	for i: int in 40:
		_weapon_shot(origin, 20.0, left)
	_check(neighbor.count("lightning") == 40 and rng.state == state_before,
		"Linke Pistole: Jeder Treffer blitzt sicher und ohne Würfeln, waren %d von 40." % neighbor.count("lightning"))
	# Obergrenze je Schuss gilt weiter.
	var cap: int = Balance.STORM_FRONT_MAX_PROCS_PER_SHOT
	var before: int = neighbor.count("lightning")
	var info: Dictionary = _bullet_info()
	info["weapon_uid"] = left
	for i: int in 20:
		_events.emit_signal("bullet_hit", origin, 20.0, info)
	_events.emit_signal("weapon_fired", "pistol")
	_check(neighbor.count("lightning") - before == cap, "Linke Pistole: höchstens %d Blitze je Schuss." % cap)
	# Die rechte Pistole hat den Kettenblitz, aber keine Spezialmunition: normale Chance.
	var chance: float = UpgradeDefs.value("chain_lightning", "chance", 5)
	before = neighbor.count("lightning")
	var shots: int = 1000
	for i: int in shots:
		_weapon_shot(origin, 20.0, right)
	var rate: float = float(neighbor.count("lightning") - before) / float(shots)
	_check(absf(rate - chance) < 0.05,
		"Rechte Pistole: ohne Spezialmunition blitzt sie nur mit %d %%, waren %.1f %%." % [int(chance * 100.0), rate * 100.0])
	_check(rng.state != state_before, "Rechte Pistole: Der Blitz wird gewürfelt.")


# --- Brand ---

func _test_burn() -> void:
	for level: int in [1, 5]:
		_fresh_run()
		_give("burn", level)
		var percent: float = UpgradeDefs.value("burn", "dps_percent", level)
		var walker: DummyZombie = _zombie(Vector3.ZERO, 200.0)
		var elite: DummyZombie = _zombie(Vector3(3.0, 0.0, 0.0), 400.0, "elite")
		_shot(walker, 10.0)
		_shot(elite, 10.0)
		_check(walker.burn_calls == 1 and _near(walker.burn_dps, percent * 200.0),
			"Feuershow Stufe %d: Schlurfer brennt mit %s Leben je Sekunde, waren %s." % [level, percent * 200.0, walker.burn_dps])
		_check(_near(walker.burn_duration, Balance.BURN_DURATION), "Feuershow Stufe %d: Der Brand dauert 4 s." % level)
		_check(_near(elite.burn_dps, percent * 400.0 * Balance.BURN_ELITE_FACTOR),
			"Feuershow Stufe %d: Elite brennt nur mit dem 0,3-fachen." % level)
		# Ein tödlicher Treffer zündet niemanden mehr an.
		var victim: DummyZombie = _zombie(Vector3(6.0, 0.0, 0.0), 5.0)
		_shot(victim, 10.0)
		_check(victim.is_dead and victim.burn_calls == 0, "Feuershow Stufe %d: Tote brennen nicht." % level)


# --- Lebensraub ---

func _test_lifesteal() -> void:
	for level: int in [1, 5]:
		_fresh_run()
		_give("lifesteal", level)
		var ratio: float = UpgradeDefs.value("lifesteal", "ratio", level)
		var zombie: DummyZombie = _zombie(Vector3.ZERO)
		_shot(zombie, 100.0)
		_check(_near(_player.healed, 100.0 * ratio),
			"Blutspende-Aktion Stufe %d: 100 Schaden heilen %s Leben, waren %s." % [level, 100.0 * ratio, _player.healed])
		# Auch Schaden aus Effekten zählt.
		zombie.take_damage(50.0, {"source": "explosion", "chain_depth": 1})
		_check(_near(_player.healed, 150.0 * ratio), "Blutspende-Aktion Stufe %d: Auch Explosionsschaden heilt." % level)

	# Obergrenze: höchstens 15 Leben je Sekunde.
	_fresh_run()
	_give("lifesteal", 5)
	_player.max_hp = 1000.0
	_player.hp = 100.0
	var target: DummyZombie = _zombie(Vector3.ZERO)
	var cap: float = Balance.LIFESTEAL_MAX_PER_SECOND
	target.take_damage(100.0, {"source": "bullet"})
	_check(_near(_player.healed, 10.0), "Lebensraub: 100 Schaden auf Stufe 5 heilen 10.")
	target.take_damage(1000.0, {"source": "bullet"})
	_check(_near(_player.healed, cap), "Lebensraub: Ein großer Treffer heilt nur bis zur Grenze von 15, waren %s." % _player.healed)
	for i: int in 20:
		target.take_damage(500.0, {"source": "lightning"})
	_check(_near(_player.healed, cap), "Lebensraub: In derselben Sekunde kommt nichts mehr dazu.")
	_check(_near(float(_effects.call("get_lifesteal_budget_left")), 0.0), "Das Kontingent der Sekunde ist verbraucht.")
	_effects.call("tick", 0.5)
	target.take_damage(500.0, {"source": "bullet"})
	_check(_near(_player.healed, cap), "Lebensraub: Nach einer halben Sekunde ist die Grenze noch zu.")
	_effects.call("tick", 0.6)
	target.take_damage(500.0, {"source": "bullet"})
	_check(_near(_player.healed, cap * 2.0), "Lebensraub: In der nächsten Sekunde heilt er wieder bis 15, gesamt %s." % _player.healed)
	# Über viele Sekunden: nie mehr als 15 je Sekunde.
	_player.healed = 0.0
	_effects.call("tick", 1.0)
	for second: int in 5:
		for i: int in 10:
			target.take_damage(400.0, {"source": "bullet"})
		_effects.call("tick", 1.0)
	_check(_near(_player.healed, cap * 5.0), "Lebensraub: 5 Sekunden Dauerfeuer heilen genau 75, waren %s." % _player.healed)
	# Volles Leben: nichts heilen, nichts verbrauchen.
	_effects.call("tick", 1.0)
	_player.hp = _player.max_hp
	_player.healed = 0.0
	target.take_damage(1000.0, {"source": "bullet"})
	_check(_near(_player.healed, 0.0) and _near(float(_effects.call("get_lifesteal_budget_left")), cap),
		"Lebensraub: Bei vollem Leben verfällt kein Kontingent.")
	# Das Fenster beginnt mit der ersten Heilung, nicht mit einem Treffer bei vollem Leben. Sonst
	# liefe es schon und gäbe kurz vor und kurz nach seinem Ende je 15 Leben frei (30 in 0,15 s).
	_effects.call("tick", 0.9)
	_player.hp = _player.max_hp - 400.0
	target.take_damage(1000.0, {"source": "bullet"})
	_check(_near(_player.healed, cap), "Lebensraub: Die erste Heilung nach vollem Leben gibt 15, waren %s." % _player.healed)
	_effects.call("tick", 0.15)
	target.take_damage(1000.0, {"source": "bullet"})
	_check(_near(_player.healed, cap), "Lebensraub: 0,15 s nach der ersten Heilung kommt nichts dazu, gesamt %s." % _player.healed)
	_check(_near(float(_effects.call("get_lifesteal_budget_left")), 0.0), "Lebensraub: Das Fenster der ersten Heilung läuft noch.")
	_effects.call("tick", 0.8)
	target.take_damage(1000.0, {"source": "bullet"})
	_check(_near(_player.healed, cap), "Lebensraub: Auch 0,95 s nach der ersten Heilung ist die Grenze noch zu, gesamt %s." % _player.healed)
	_effects.call("tick", 0.1)
	target.take_damage(1000.0, {"source": "bullet"})
	_check(_near(_player.healed, cap * 2.0), "Lebensraub: Eine Sekunde nach der ersten Heilung beginnt das nächste Fenster, gesamt %s." % _player.healed)
	_player.healed = 0.0
	_effects.call("tick", 1.0)
	# Toter Spieler wird nicht geheilt.
	_player.hp = 10.0
	_player.is_dead = true
	target.take_damage(1000.0, {"source": "bullet"})
	_check(_near(_player.healed, 0.0), "Lebensraub: Ein toter Spieler wird nicht geheilt.")
	_player.is_dead = false


## Zwei Blutspende-Aktionen im Rucksack (Gewöhnlich 2 %, Selten 6 %) heilen zusammen 8 % des
## Schadens, weiter höchstens bis zur Grenze je Sekunde.
func _test_lifesteal_stacks() -> void:
	_fresh_run()
	_auto("lifesteal", 1)
	_auto("lifesteal", 3)
	_sync()
	var ratio: float = UpgradeDefs.value("lifesteal", "ratio", 1) + UpgradeDefs.value("lifesteal", "ratio", 3)
	_check(_near(float(_upgrades().call("value", "lifesteal", "ratio")), ratio) and _near(ratio, 0.08),
		"Zwei Blutspende-Aktionen: Die Anteile addieren sich zu 8 %.")
	_check(int(_upgrades().call("get_level", "lifesteal")) == 3, "Die Übersicht nennt die beste Rarität (3).")
	var zombie: DummyZombie = _zombie(Vector3.ZERO)
	zombie.take_damage(100.0, {"source": "bullet"})
	_check(_near(_player.healed, 100.0 * ratio), "Zwei Blutspende-Aktionen: 100 Schaden heilen 8 Leben, waren %s." % _player.healed)
	zombie.take_damage(1000.0, {"source": "bullet"})
	_check(_near(_player.healed, Balance.LIFESTEAL_MAX_PER_SECOND),
		"Zwei Blutspende-Aktionen: Die Grenze von 15 Leben je Sekunde bleibt, waren %s." % _player.healed)


# --- Konfetti-Explosion ---

func _test_corpse_explosion() -> void:
	for level: int in [1, 5]:
		_fresh_run()
		_give("corpse_explosion", level)
		var chance: float = UpgradeDefs.value("corpse_explosion", "chance", level)
		var radius: float = UpgradeDefs.value("corpse_explosion", "radius", level)
		var percent: float = UpgradeDefs.value("corpse_explosion", "damage_percent", level)
		var inside: DummyZombie = _zombie(Vector3(radius - 0.1, 0.0, 0.0))
		var outside: DummyZombie = _zombie(Vector3(radius + 0.1, 0.0, 0.0))
		var kills: int = 400
		var explosions: int = 0
		var deferred_ok: bool = true
		for i: int in kills:
			var victim: DummyZombie = _zombie(Vector3.ZERO, 200.0)
			var before: int = inside.count("explosion")
			victim.take_damage(500.0, _bullet_info())
			# Noch im selben Aufruf darf nichts explodiert sein.
			if inside.count("explosion") != before:
				deferred_ok = false
			_effects.call("tick", 0.016)
			if inside.count("explosion") > before:
				explosions += 1
			victim.free()
		var rate: float = float(explosions) / float(kills)
		_check(deferred_ok, "Konfetti-Kanone Stufe %d: Die Explosion läuft nie innerhalb von zombie_killed." % level)
		_check(absf(rate - chance) < 0.06,
			"Konfetti-Kanone Stufe %d: etwa %d %% der Toten explodieren, waren %.1f %%." % [level, int(chance * 100.0), rate * 100.0])
		_check(explosions > 0 and _near(inside.total("explosion"), float(explosions) * 200.0 * percent, 0.01),
			"Konfetti-Kanone Stufe %d: Schaden ist %d %% des Maximal-Lebens des Toten." % [level, int(percent * 100.0)])
		_check(outside.count("explosion") == 0, "Konfetti-Kanone Stufe %d: Außerhalb von %s m passiert nichts." % [level, radius])
		var depth_ok: bool = true
		for hit: Dictionary in inside.hits:
			if int((hit["info"] as Dictionary).get("chain_depth", 0)) != 1:
				depth_ok = false
		_check(depth_ok, "Konfetti-Kanone Stufe %d: Die erste Explosion hat chain_depth 1." % level)
		_check(int(_effects.call("get_pending_explosion_count")) == 0, "Keine Explosion bleibt hängen.")


## Zählt, wie viele von kills getöteten Zombies (200 Leben, am Ursprung) explodieren. witness
## steht im Radius und bekommt jede Explosion ab.
func _count_explosions(kills: int, witness: DummyZombie) -> int:
	var explosions: int = 0
	for i: int in kills:
		var victim: DummyZombie = _zombie(Vector3.ZERO, 200.0)
		var before: int = witness.count("explosion")
		victim.take_damage(500.0, _bullet_info())
		_effects.call("tick", 0.016)
		if witness.count("explosion") > before:
			explosions += 1
		victim.free()
	return explosions


## Mehrere Konfetti-Kanonen im Rucksack: Die Chancen addieren sich (höchstens 100 %), Radius und
## Schadensanteil sind die besten.
func _test_corpse_explosion_stacks() -> void:
	# Gewöhnlich (15 %, 3 m, 30 %) und Selten (25 %, 3,5 m, 50 %): 40 %, 3,5 m, 50 %.
	_fresh_run()
	_auto("corpse_explosion", 1)
	_auto("corpse_explosion", 3)
	_sync()
	var upgrades: RefCounted = _upgrades()
	var chance: float = UpgradeDefs.value("corpse_explosion", "chance", 1) + UpgradeDefs.value("corpse_explosion", "chance", 3)
	var radius: float = UpgradeDefs.value("corpse_explosion", "radius", 3)
	var percent: float = UpgradeDefs.value("corpse_explosion", "damage_percent", 3)
	_check(_near(float(upgrades.call("value", "corpse_explosion", "chance")), chance) and _near(chance, 0.40),
		"Zwei Konfetti-Kanonen: Die Chancen addieren sich zu 40 %.")
	_check(_near(float(upgrades.call("value", "corpse_explosion", "radius")), radius)
		and _near(float(upgrades.call("value", "corpse_explosion", "damage_percent")), percent),
		"Zwei Konfetti-Kanonen: Radius und Schadensanteil sind die der besseren.")
	var inside: DummyZombie = _zombie(Vector3(radius - 0.1, 0.0, 0.0))
	var outside: DummyZombie = _zombie(Vector3(radius + 0.1, 0.0, 0.0))
	var kills: int = 400
	var explosions: int = _count_explosions(kills, inside)
	var rate: float = float(explosions) / float(kills)
	_check(absf(rate - chance) < 0.07, "Zwei Konfetti-Kanonen: etwa 40 %% der Toten explodieren, waren %.1f %%." % (rate * 100.0))
	_check(explosions > 0 and _near(inside.total("explosion"), float(explosions) * 200.0 * percent, 0.01),
		"Zwei Konfetti-Kanonen: Schaden ist %d %% des Maximal-Lebens des Toten." % int(percent * 100.0))
	_check(outside.count("explosion") == 0, "Zwei Konfetti-Kanonen: Außerhalb von %s m passiert nichts." % radius)

	# Drei legendäre (je 35 %): zusammen 105 %, die Chance endet bei 100 %.
	_fresh_run()
	for i: int in 3:
		_auto("corpse_explosion", 5)
	_sync()
	_check((_upgrades().call("copies", "corpse_explosion") as Array).size() == 3, "Drei Konfetti-Kanonen wirken.")
	_check(_near(float(_upgrades().call("value", "corpse_explosion", "chance")), 1.0), "Drei legendäre Konfetti-Kanonen: Die Chance endet bei 100 %.")
	var witness: DummyZombie = _zombie(Vector3(1.0, 0.0, 0.0))
	var sure: int = _count_explosions(100, witness)
	_check(sure == 100, "Drei legendäre Konfetti-Kanonen: Jeder Tote explodiert, waren %d von 100." % sure)
	_check(int(_effects.call("get_pending_explosion_count")) == 0, "Keine Explosion bleibt hängen.")


## Ketten: Folgeexplosionen laufen verzögert und höchstens Balance.EXPLOSION_MAX_CHAIN tief.
func _test_explosion_chain_cap() -> void:
	_fresh_run()
	_give("corpse_explosion", 5)
	var max_chain: int = Balance.EXPLOSION_MAX_CHAIN
	var radius: float = UpgradeDefs.value("corpse_explosion", "radius", 5)
	# Eine lange Reihe schwacher Zombies im Abstand von 1 m: Jede Explosion tötet ihre Nachbarn.
	var line: Array[DummyZombie] = []
	for i: int in 400:
		var zombie: DummyZombie = _zombie(Vector3(float(i), 0.0, 0.0), 100.0)
		zombie.hp = 10.0
		line.append(zombie)
	# Zündpunkte weit auseinander, damit sich die Ketten nicht berühren.
	var starts: Array[int] = [40, 120, 200, 280, 360]
	for index: int in starts:
		line[index].take_damage(50.0, _bullet_info())
	var saw_delay: bool = false
	for step: int in 200:
		var pending_before: int = int(_effects.call("get_pending_explosion_count"))
		if pending_before == 0:
			break
		# Ein Schritt, der kürzer ist als die Verzögerung, darf keine Folgeexplosion zünden.
		_effects.call("tick", Balance.EXPLOSION_CHAIN_DELAY * 0.5)
		if int(_effects.call("get_pending_explosion_count")) >= pending_before:
			saw_delay = true
	_check(int(_effects.call("get_pending_explosion_count")) == 0, "Alle Ketten enden.")
	var deepest: int = 0
	var explosion_kills: int = 0
	for zombie: DummyZombie in line:
		for hit: Dictionary in zombie.hits:
			if hit["source"] == "explosion":
				deepest = maxi(deepest, int((hit["info"] as Dictionary).get("chain_depth", 0)))
		if zombie.is_dead:
			explosion_kills += 1
	_check(deepest == max_chain,
		"Ketten erreichen mit diesem Seed die Tiefe %d und gehen nie tiefer, tiefste war %d." % [max_chain, deepest])
	_check(saw_delay, "Folgeexplosionen warten Balance.EXPLOSION_CHAIN_DELAY ab.")
	# Weiter als max_chain Radien kommt keine Kette: Dort lebt alles.
	var reach: float = radius * float(max_chain)
	var survivors_ok: bool = true
	for i: int in line.size():
		var nearest: float = 1.0e9
		for index: int in starts:
			nearest = minf(nearest, absf(float(i - index)))
		if nearest > reach and line[i].is_dead:
			survivors_ok = false
	_check(survivors_ok, "Jenseits von %d Radien um den ersten Toten stirbt niemand." % max_chain)
	_check(explosion_kills > starts.size(), "Die Ketten haben weitere Zombies getötet (%d Tote)." % explosion_kills)

	# Direkt geprüft: Ein Tod durch eine Explosion der höchsten Tiefe zündet nie weiter.
	_fresh_run()
	_give("corpse_explosion", 5)
	for i: int in 300:
		var victim: DummyZombie = _zombie(Vector3.ZERO, 100.0)
		victim.take_damage(500.0, {"source": "explosion", "chain_depth": max_chain})
		victim.free()
	_check(int(_effects.call("get_pending_explosion_count")) == 0,
		"Ein Tod mit chain_depth %d löst keine weitere Explosion aus." % max_chain)
	# Eine Stufe darunter geht es noch einmal weiter, mit der höchsten Tiefe.
	var witness: DummyZombie = _zombie(Vector3(1.0, 0.0, 0.0))
	for i: int in 300:
		var victim: DummyZombie = _zombie(Vector3.ZERO, 100.0)
		victim.take_damage(500.0, {"source": "explosion", "chain_depth": max_chain - 1})
		victim.free()
	_check(int(_effects.call("get_pending_explosion_count")) > 0, "Ein Tod mit chain_depth %d kann noch explodieren." % (max_chain - 1))
	_effects.call("tick", Balance.EXPLOSION_CHAIN_DELAY + 0.01)
	var all_deepest: bool = witness.count("explosion") > 0
	for hit: Dictionary in witness.hits:
		if int((hit["info"] as Dictionary).get("chain_depth", 0)) != max_chain:
			all_deepest = false
	_check(all_deepest, "Die Folgeexplosion trägt chain_depth %d." % max_chain)


## Zombies, die mitten in einer Schleife verschwinden, bringen nichts zum Absturz.
func _test_vanishing_zombies() -> void:
	_fresh_run()
	_give("corpse_explosion", 5)
	_give("chain_lightning", 5)
	_give("pierce", 5)
	_give("reload_shockwave", 5)
	# Explosion: Der erste Tote reißt einen Nachbarn sofort aus dem Baum.
	var survived_rounds: int = 0
	for i: int in 60:
		var trigger: DummyZombie = _zombie(Vector3.ZERO, 100.0)
		var weak: DummyZombie = _zombie(Vector3(1.0, 0.0, 0.0), 100.0)
		weak.hp = 1.0
		var ghost: DummyZombie = _zombie(Vector3(1.5, 0.0, 0.0), 100.0)
		var bystander: DummyZombie = _zombie(Vector3(2.0, 0.0, 0.0))
		weak.vanishes_with_me = ghost
		trigger.take_damage(500.0, _bullet_info())
		_effects.call("tick", 0.016)
		_effects.call("tick", 1.0)
		survived_rounds += 1
		for node: Node in _zombie_root.get_children():
			node.free()
		_check(not is_instance_valid(bystander), "Aufräumen der Runde.")
	_check(survived_rounds == 60, "Explosionen überstehen verschwindende Zombies.")
	# Blitz: Das erste Ziel der Kette reißt das zweite aus dem Baum.
	var origin: DummyZombie = _zombie(Vector3.ZERO)
	var first: DummyZombie = _zombie(Vector3(2.0, 0.0, 0.0), 100.0)
	first.hp = 1.0
	var second: DummyZombie = _zombie(Vector3(4.0, 0.0, 0.0))
	var third: DummyZombie = _zombie(Vector3(6.0, 0.0, 0.0))
	first.vanishes_with_me = second
	_shot(origin, 20.0)
	_check(first.is_dead and not is_instance_valid(second), "Das zweite Ziel ist mitten im Blitz verschwunden.")
	_check(third.count("lightning") == 1, "Der Blitz trifft das dritte Ziel trotzdem.")
	# Druckwelle: Ein Opfer reißt das nächste aus dem Baum.
	for node: Node in _zombie_root.get_children():
		node.free()
	var near: DummyZombie = _zombie(Vector3(1.0, 0.0, 0.0), 100.0)
	near.hp = 1.0
	var gone: DummyZombie = _zombie(Vector3(2.0, 0.0, 0.0))
	var rest: DummyZombie = _zombie(Vector3(3.0, 0.0, 0.0))
	near.vanishes_with_me = gone
	_events.emit_signal("reload_started", "pistol", 1.2)
	_check(near.is_dead and not is_instance_valid(gone) and rest.count("shockwave") == 1,
		"Die Druckwelle übersteht einen verschwindenden Zombie.")
	# Signale ohne Zombie (null) werden verkraftet.
	_events.emit_signal("bullet_hit", null, 20.0, _bullet_info())
	_events.emit_signal("zombie_killed", null, _bullet_info())
	_events.emit_signal("zombie_damaged", null, 20.0, _bullet_info())
	_effects.call("tick", 1.0)
	_check(int(_effects.call("get_pending_explosion_count")) == 0, "Signale ohne Zombie lösen nichts aus.")


# --- Druckwelle beim Nachladen ---

func _test_reload_shockwave() -> void:
	for level: int in [1, 5]:
		_fresh_run()
		_give("reload_shockwave", level)
		_give("burn", 5)
		var radius: float = UpgradeDefs.value("reload_shockwave", "radius", level)
		var base_damage: float = UpgradeDefs.value("reload_shockwave", "damage", level)
		_player.position = Vector3(2.0, 0.0, -3.0)
		var center: Vector3 = _player.position
		var inside: DummyZombie = _zombie(center + Vector3(radius - 0.1, 0.0, 0.0))
		var diagonal: DummyZombie = _zombie(center + Vector3(0.0, 0.0, -1.0))
		var outside: DummyZombie = _zombie(center + Vector3(radius + 0.1, 0.0, 0.0))

		_events.emit_signal("reload_started", "pistol", 1.2)
		_check(inside.count("shockwave") == 1 and _near(inside.total("shockwave"), base_damage),
			"Werbepause Stufe %d: %s Schaden im Radius %s m (Welle 0, Faktor 1), waren %s." % [level, base_damage, radius, inside.total("shockwave")])
		_check(outside.hits.is_empty(), "Werbepause Stufe %d: Außerhalb des Radius passiert nichts." % level)
		_check(_near(inside.knockback.length(), Balance.SHOCKWAVE_KNOCKBACK) and inside.knockback.x > 0.0 and _near(inside.knockback.y, 0.0),
			"Werbepause Stufe %d: Der Zombie wird mit %s m/s vom Spieler weggestoßen." % [level, Balance.SHOCKWAVE_KNOCKBACK])
		_check(diagonal.knockback.z < 0.0 and _near(diagonal.knockback.x, 0.0), "Werbepause Stufe %d: Die Richtung zeigt vom Spieler weg." % level)
		_check(inside.burn_calls == 0, "Werbepause Stufe %d: Die Druckwelle zündet niemanden an (kein Kugeltreffer)." % level)

		# Abklingzeit 3 s.
		_check(_near(float(_effects.call("get_shockwave_cooldown_left")), Balance.SHOCKWAVE_COOLDOWN), "Werbepause Stufe %d: Die Abklingzeit läuft." % level)
		_events.emit_signal("reload_started", "pistol", 1.2)
		_effects.call("tick", Balance.SHOCKWAVE_COOLDOWN - 0.1)
		_events.emit_signal("reload_started", "pistol", 1.2)
		_check(inside.count("shockwave") == 1, "Werbepause Stufe %d: Während der Abklingzeit gibt es keine zweite Welle." % level)
		_effects.call("tick", 0.2)
		_events.emit_signal("reload_started", "pistol", 1.2)
		_check(inside.count("shockwave") == 2, "Werbepause Stufe %d: Nach 3 s kommt die nächste Welle." % level)

		# Effekt-Faktor: Der feste Schaden wächst mit der Welle.
		_effects.call("tick", Balance.SHOCKWAVE_COOLDOWN)
		_game.set("wave", 10)
		var factor: float = WavePlan.effect_factor(10)
		_events.emit_signal("reload_started", "pistol", 1.2)
		_check(factor > 1.0 and _near(float(inside.hits[inside.hits.size() - 1]["amount"]), base_damage * factor, 0.01),
			"Werbepause Stufe %d: In Welle 10 ist der Schaden mal %s." % [level, factor])

	# Ohne Zombie in Reichweite wird die Welle nicht verbraucht.
	_fresh_run()
	_give("reload_shockwave", 1)
	_events.emit_signal("reload_started", "pistol", 1.2)
	_check(_near(float(_effects.call("get_shockwave_cooldown_left")), 0.0), "Eine Welle ohne Treffer startet keine Abklingzeit.")
	# Ohne das Upgrade passiert nichts.
	_fresh_run()
	var untouched: DummyZombie = _zombie(Vector3(1.0, 0.0, 0.0))
	_events.emit_signal("reload_started", "pistol", 1.2)
	_check(untouched.hits.is_empty(), "Ohne Werbepause gibt es keine Druckwelle.")


## Druckwelle mit zwei Händen: Die linke Hand meldet ihr Nachladen über reload_started und
## hand_reload_started(0), die rechte nur über hand_reload_started(1). Ein Nachladen gibt genau
## eine Welle, jede Hand darf sie auslösen, die Abklingzeit gilt für beide zusammen.
func _test_reload_shockwave_hands() -> void:
	# Ohne Zombie in Reichweite beginnt keine Abklingzeit: Hier zeigt sich eine doppelte Welle.
	_fresh_run()
	_give("reload_shockwave", 1)
	_check(int(_effects.call("get_shockwave_count")) == 0, "Ein neuer Lauf beginnt ohne Druckwelle.")
	_events.emit_signal("reload_started", "pistol", 1.2)
	_events.emit_signal("hand_reload_started", 0, 1.2)
	_check(int(_effects.call("get_shockwave_count")) == 1,
		"Linke Hand: altes und neues Signal zusammen geben eine Welle, waren %d." % int(_effects.call("get_shockwave_count")))
	_check(_near(float(_effects.call("get_shockwave_cooldown_left")), 0.0), "Ohne Treffer beginnt keine Abklingzeit.")
	# Auch in umgekehrter Reihenfolge.
	_effects.call("tick", 0.016)
	_events.emit_signal("hand_reload_started", 0, 1.2)
	_events.emit_signal("reload_started", "pistol", 1.2)
	_check(int(_effects.call("get_shockwave_count")) == 2, "Linke Hand: Auch neues vor altem Signal gibt eine Welle.")
	# Die rechte Hand allein löst sie ebenfalls aus.
	_effects.call("tick", 0.016)
	_events.emit_signal("hand_reload_started", 1, 1.2)
	_check(int(_effects.call("get_shockwave_count")) == 3, "Rechte Hand: Ihr Nachladen löst die Welle aus.")
	# Beide Hände laden im selben Augenblick nach: eine Welle.
	_effects.call("tick", 0.016)
	_events.emit_signal("reload_started", "pistol", 1.2)
	_events.emit_signal("hand_reload_started", 0, 1.2)
	_events.emit_signal("hand_reload_started", 1, 1.2)
	_check(int(_effects.call("get_shockwave_count")) == 4, "Beide Hände zugleich: eine Welle, nicht zwei.")

	# Mit Zombie: Schaden, Abklingzeit, und sie gilt für beide Hände.
	_effects.call("tick", 0.016)
	var damage: float = UpgradeDefs.value("reload_shockwave", "damage", 1)
	var zombie: DummyZombie = _zombie(Vector3(1.0, 0.0, 0.0))
	_events.emit_signal("hand_reload_started", 1, 1.2)
	_check(zombie.count("shockwave") == 1 and _near(zombie.total("shockwave"), damage), "Rechte Hand: Die Welle trifft mit %s Schaden." % damage)
	_check(_near(float(_effects.call("get_shockwave_cooldown_left")), Balance.SHOCKWAVE_COOLDOWN), "Rechte Hand: Die Abklingzeit läuft.")
	_effects.call("tick", 1.0)
	_events.emit_signal("reload_started", "pistol", 1.2)
	_events.emit_signal("hand_reload_started", 0, 1.2)
	_events.emit_signal("hand_reload_started", 1, 1.2)
	_check(zombie.count("shockwave") == 1 and int(_effects.call("get_shockwave_count")) == 5,
		"Während der Abklingzeit löst keine Hand eine Welle aus.")
	_effects.call("tick", Balance.SHOCKWAVE_COOLDOWN - 1.0 + 0.1)
	_events.emit_signal("reload_started", "pistol", 1.2)
	_events.emit_signal("hand_reload_started", 0, 1.2)
	_check(zombie.count("shockwave") == 2 and int(_effects.call("get_shockwave_count")) == 6,
		"Nach der Abklingzeit gibt das Nachladen der linken Hand genau eine Welle, Treffer: %d." % zombie.count("shockwave"))
	_effects.call("tick", Balance.SHOCKWAVE_COOLDOWN + 0.1)
	_events.emit_signal("hand_reload_started", 1, 1.2)
	_check(zombie.count("shockwave") == 3, "Nach der Abklingzeit löst auch die rechte Hand wieder aus.")
	# Ohne das Upgrade hört niemand auf die Hände.
	_fresh_run()
	var untouched: DummyZombie = _zombie(Vector3(1.0, 0.0, 0.0))
	_events.emit_signal("hand_reload_started", 0, 1.2)
	_events.emit_signal("hand_reload_started", 1, 1.2)
	_check(untouched.hits.is_empty() and int(_effects.call("get_shockwave_count")) == 0, "Ohne Werbepause gibt es auch mit zwei Händen keine Druckwelle.")

	# Zwei Werbepausen im Rucksack (Gewöhnlich 4 m und 20, Ungewöhnlich 4,5 m und 35): der größere
	# Radius, die Schadenswerte addieren sich.
	_fresh_run()
	_auto("reload_shockwave", 1)
	_auto("reload_shockwave", 2)
	_sync()
	var radius: float = UpgradeDefs.value("reload_shockwave", "radius", 2)
	var sum: float = UpgradeDefs.value("reload_shockwave", "damage", 1) + UpgradeDefs.value("reload_shockwave", "damage", 2)
	var inside: DummyZombie = _zombie(Vector3(radius - 0.1, 0.0, 0.0))
	var outside: DummyZombie = _zombie(Vector3(radius + 0.1, 0.0, 0.0))
	_events.emit_signal("reload_started", "pistol", 1.2)
	_check(inside.count("shockwave") == 1 and _near(inside.total("shockwave"), sum),
		"Zwei Werbepausen: %s Schaden im Radius %s m, waren %s." % [sum, radius, inside.total("shockwave")])
	_check(outside.hits.is_empty(), "Zwei Werbepausen: Außerhalb des größeren Radius passiert nichts.")


# --- Drohne ---

func _test_drone() -> void:
	_fresh_run()
	_effects.call("tick", 0.016)
	_check(_effects.get("drone") == null, "Ohne die Kamera gibt es keine Drohne.")
	for level: int in [1, 5]:
		_fresh_run()
		# Die Kamera liegt im Rucksack. Erst danach die Upgrades von Hand: sync_build setzt sie sonst zurück.
		_auto("drone", level)
		_sync()
		_give("burn", 5)
		_give("chain_lightning", 5)
		_events.emit_signal("upgrade_chosen", "drone", level)
		var drone: Node3D = _effects.get("drone") as Node3D
		_check(is_instance_valid(drone) and drone.is_inside_tree(), "Kameradrohne Stufe %d: Die Drohne fliegt." % level)
		if not is_instance_valid(drone):
			continue
		_check(drone.get_parent() == _fx_root, "Die Drohne hängt im Effekt-Behälter.")
		_check(int(drone.get("level")) == level, "Kameradrohne: Stufe %d ist gesetzt." % level)
		var interval: float = CameraDefs.base("drone", "interval", level)
		var base_damage: float = CameraDefs.base("drone", "damage", level)
		_check(_near(float(drone.call("get_fire_interval")), interval), "Kameradrohne Stufe %d: Takt %s s." % [level, interval])
		_check(_near(drone.global_position.y, Balance.DRONE_HOVER_HEIGHT, 0.3), "Die Drohne schwebt in %s m Höhe." % Balance.DRONE_HOVER_HEIGHT)

		# Kein Ziel in Reichweite: kein Schuss.
		var far: DummyZombie = _zombie(Vector3(0.0, 0.0, -60.0))
		_check(not bool(drone.call("try_fire")), "Kameradrohne Stufe %d: Außerhalb von 15 m schießt sie nicht." % level)
		# Der nähere von zwei Zombies wird getroffen.
		var near: DummyZombie = _zombie(Vector3(0.0, 0.0, -5.0))
		var mid: DummyZombie = _zombie(Vector3(0.0, 0.0, -9.0))
		_check(drone.call("find_target") == near, "Kameradrohne Stufe %d: Sie zielt auf den nächsten Zombie." % level)
		_check(bool(drone.call("try_fire")), "Kameradrohne Stufe %d: Sie schießt." % level)
		_check(near.count("drone") == 1 and _near(near.total("drone"), base_damage),
			"Kameradrohne Stufe %d: %s Schaden mit source drone, waren %s." % [level, base_damage, near.total("drone")])
		_check(mid.hits.is_empty() and far.hits.is_empty(), "Kameradrohne Stufe %d: Nur das nächste Ziel bekommt Schaden." % level)
		_check(near.burn_calls == 0 and mid.count("lightning") == 0, "Drohnenschaden löst weder Brand noch Blitz aus.")
		# Feste Werte (Abschnitt 22.1): Der Effekt-Faktor der Welle ändert den Schaden nicht.
		_game.set("wave", 10)
		drone.call("try_fire")
		_check(WavePlan.effect_factor(10) > 1.2 and _near(float(near.hits[near.hits.size() - 1]["amount"]), base_damage, 0.01),
			"Kameradrohne Stufe %d: Auch in Welle 10 bleibt es beim festen Schaden." % level)
		# Tote sind kein Ziel.
		near.is_dead = true
		_check(drone.call("find_target") == mid, "Kameradrohne: Tote Zombies sind kein Ziel.")
		near.is_dead = false

		# Von selbst: Im Takt der Stufe fallen Schüsse.
		var shots_before: int = near.count("drone")
		var frames: int = 0
		while near.count("drone") == shots_before and frames < 240:
			await physics_frame
			frames += 1
		_check(near.count("drone") > shots_before, "Kameradrohne Stufe %d: Sie schießt von selbst." % level)

	# Die Rarität folgt dem Rucksack, auch ohne upgrade_chosen.
	_fresh_run()
	var weak_uid: int = _auto("drone", 2)
	_sync()
	_effects.call("tick", 0.016)
	var synced: Node3D = _effects.get("drone") as Node3D
	_check(is_instance_valid(synced) and int(synced.get("level")) == 2, "Die Drohne entsteht passend zur Stufe 2.")
	_backpack().call("remove", weak_uid)
	_auto("drone", 5)
	_sync()
	_effects.call("tick", 0.016)
	_check(is_instance_valid(synced) and _near(float(synced.call("get_shot_damage")), CameraDefs.base("drone", "damage", 5)),
		"Mit der neuen Rarität hat sie auch deren Schaden.")
	# Ein Objektiv auf der Kamera: Die Drohne liest die fertigen Werte aus Game.cameras.
	var camera_uid: int = int(((_game.get("cameras") as Array)[0] as Dictionary)["uid"])
	var lens_uid: int = int(_backpack().call("add_item", "cam_lens", 1))
	var lens_placed: bool = false
	for y: int in 5:
		for x: int in 7:
			if not lens_placed and bool(_backpack().call("can_place", lens_uid, Vector2i(x, y), 0)):
				_backpack().call("place", lens_uid, Vector2i(x, y), 0)
				if (_backpack().call("star_targets", lens_uid) as Array).has(camera_uid):
					lens_placed = true
				else:
					_backpack().call("store", lens_uid)
	_check(lens_placed, "Das Objektiv lässt sich neben die Kameradrohne legen.")
	_sync()
	_effects.call("tick", 0.016)
	_check(_effects.get("drone") == synced and _near(float(synced.call("get_shot_damage")), CameraDefs.base("drone", "damage", 5) * 1.2),
		"Mit einem gewöhnlichen Objektiv macht dieselbe Drohne 20 %% mehr Schaden, war %s." % float(synced.call("get_shot_damage")))
	_check(is_instance_valid(synced) and int(synced.get("level")) == 5 and _effects.get("drone") == synced,
		"Dieselbe Drohne steigt auf Stufe 5.")
	# Neuer Lauf: Drohne weg.
	_fresh_run()
	_check(_effects.get("drone") == null, "Ein neuer Lauf entfernt die Drohne.")
	await process_frame
	await process_frame
	_check(not is_instance_valid(synced), "Die alte Drohne ist aus dem Baum verschwunden.")


## Stufen aller Drohnen, sortiert.
func _drone_levels() -> Array:
	var levels: Array = []
	for entry: Variant in _drones():
		levels.append(int((entry as Node3D).get("level")))
	levels.sort()
	return levels


## Stehen alle Drohnen mindestens min_distance auseinander?
func _drones_apart(min_distance: float) -> bool:
	var list: Array = _drones()
	for i: int in list.size():
		for j: int in range(i + 1, list.size()):
			if (list[i] as Node3D).global_position.distance_to((list[j] as Node3D).global_position) < min_distance:
				return false
	return true


## Jede Kameradrohne im Rucksack ist eine eigene Drohne mit ihrer Rarität als Stufe.
func _test_drones_per_copy() -> void:
	# Kein Gegenstand: keine Drohne.
	_fresh_run()
	_sync()
	_effects.call("tick", 0.016)
	_check(_drones().is_empty() and _effects.get("drone") == null, "Ohne Kameradrohne im Rucksack gibt es keine Drohne.")

	# Ein Gegenstand: eine Drohne, schon mit build_changed.
	var item_a: int = _auto("drone", 1)
	_sync()
	var listed: Array = _game.call("cameras_of", "drone")
	_check(listed.size() == 1 and int((listed[0] as Dictionary)["level"]) == 1, "Game.cameras nennt ein Exemplar der Rarität 1.")
	_check(_drones().size() == 1 and _drone_levels() == [1], "Eine Kameradrohne: eine Drohne der Stufe 1.")
	var first: Node3D = _drones()[0] as Node3D
	_check(_effects.get("drone") == first and first.get_parent() == _fx_root and first.is_in_group("drones"),
		"Die erste Drohne steht auch in drone und hängt im Effekt-Behälter.")

	# Drei Gegenstände verschiedener Rarität: drei Drohnen mit diesen Stufen.
	var item_b: int = _auto("drone", 3)
	var item_c: int = _auto("drone", 5)
	_sync()
	var three: Array = _drones().duplicate()
	_check(three.size() == 3 and _drone_levels() == [1, 3, 5], "Drei Kameradrohnen: drei Drohnen der Stufen 1, 3 und 5, waren %s." % [_drone_levels()])
	_check(three.size() == 3 and three[0] == first and _effects.get("drone") == first, "Die schon vorhandene Drohne bleibt dieselbe.")
	if three.size() != 3:
		return
	var second: Node3D = three[1] as Node3D
	var third: Node3D = three[2] as Node3D
	_check(int(second.get("level")) == 3 and int(third.get("level")) == 5, "Die neuen Drohnen haben die Stufen 3 und 5.")
	_check(int(first.get("slot")) == 0 and int(second.get("slot")) == 1 and int(third.get("slot")) == 2, "Jede Drohne hat ihren eigenen Platz.")
	_check(_near(float(second.call("get_fire_interval")), CameraDefs.base("drone", "interval", 3))
		and _near(float(third.call("get_fire_interval")), CameraDefs.base("drone", "interval", 5)), "Jede Drohne schießt im Takt ihrer eigenen Stufe.")
	_check(_drones_apart(1.0), "Die drei Drohnen stehen an verschiedenen Stellen.")
	var heights_ok: bool = true
	for entry: Variant in three:
		if (entry as Node3D).global_position.y < Balance.DRONE_HOVER_HEIGHT - 0.3:
			heights_ok = false
	_check(heights_ok, "Alle Drohnen schweben mindestens in Flughöhe.")
	# Ein weiterer Abgleich ohne Änderung lässt alles, wie es ist.
	_effects.call("tick", 0.016)
	_events.emit_signal("upgrade_chosen", "drone", 5)
	_check(_drones() == three, "Ein Abgleich ohne Änderung behält alle drei Drohnen.")

	# Verschiedene Ziele: Zwei Zombies in Reichweite, drei Drohnen. Die zweite nimmt nicht den
	# Zombie, den die erste gerade beansprucht. Die dritte hat keine freie Wahl mehr.
	var near: DummyZombie = _zombie(Vector3(0.0, 0.0, -5.0))
	var far: DummyZombie = _zombie(Vector3(0.0, 0.0, -9.0))
	_check(first.call("find_target") == near and second.call("find_target") == near, "Ohne Anspruch zielen alle auf den nächsten Zombie.")
	_check(bool(first.call("try_fire")) and near.count("drone") == 1, "Die erste Drohne schießt auf den nächsten Zombie.")
	_check(first.call("get_claimed_target") == near, "Die erste Drohne beansprucht ihr Ziel.")
	_check(second.call("find_target") == far, "Die zweite Drohne weicht auf den anderen Zombie aus.")
	_check(first.call("find_target") == near, "Der eigene Anspruch stört die erste Drohne nicht.")
	_check(bool(second.call("try_fire")) and far.count("drone") == 1 and near.count("drone") == 1, "Die zweite Drohne trifft den anderen Zombie.")
	_check(third.call("find_target") == near and bool(third.call("try_fire")) and near.count("drone") == 2,
		"Sind alle Ziele beansprucht, schießt die dritte Drohne trotzdem (auf den nächsten).")
	# Feste Werte (Abschnitt 22.1): Mehrere Drohnen teilen ihre Kraft nicht mehr. Der Abschlag gilt
	# nur noch für Discokugeln.
	_check(_near(far.total("drone"), CameraDefs.base("drone", "damage", 3)), "Die zweite Drohne macht auch neben zwei anderen den vollen Schaden ihrer Stufe 3, war %s." % far.total("drone"))
	_check(_near(UpgradeDefs.companion_factor(1), 1.0) and _near(UpgradeDefs.companion_factor(4), 0.5) and _near(UpgradeDefs.companion_factor(0), 1.0), "Abschlag: eine Drohne voll, vier Drohnen je die Hälfte.")
	_check(int(second.call("get_companion_count")) == 3, "Die Drohne zählt drei Drohnen.")
	# Nur ein Zombie: Alle schießen auf ihn.
	far.free()
	_check(second.call("find_target") == near, "Gibt es nur ein Ziel, nimmt es auch die zweite Drohne.")
	# Ein totes Ziel gibt den Anspruch frei.
	near.is_dead = true
	_check(first.call("get_claimed_target") == null, "Ein totes Ziel ist nicht mehr beansprucht.")
	near.free()

	# Ein Gegenstand weg (verkauft): genau eine Drohne weniger, die anderen Knoten bleiben.
	_game.call("sell_item", item_b)
	_check(_drones().size() == 2 and _drone_levels() == [1, 5], "Nach dem Verkauf der seltenen Kameradrohne bleiben die Stufen 1 und 5, waren %s." % [_drone_levels()])
	_check(_drones().has(first) and _drones().has(third) and not _drones().has(second), "Die beiden anderen Drohnen sind dieselben Knoten geblieben.")
	_check(second.is_queued_for_deletion() and not first.is_queued_for_deletion() and not third.is_queued_for_deletion(),
		"Nur die Drohne des verkauften Gegenstands verschwindet.")
	_check(int(first.get("slot")) == 0 and int(third.get("slot")) == 1, "Die verbliebenen Drohnen rücken auf.")
	# Ein Gegenstand in die Ablage: wieder eine weniger.
	_backpack().call("store", item_a)
	_sync()
	_check(_drones().size() == 1 and _drones()[0] == third and _effects.get("drone") == third and int(third.get("slot")) == 0,
		"In der Ablage wirkt die Kameradrohne nicht: Es bleibt die legendäre Drohne.")
	_check(first.is_queued_for_deletion(), "Die Drohne des abgelegten Gegenstands verschwindet.")
	# Wieder eingeräumt: eine neue Drohne kommt dazu, die alte bleibt.
	_check(bool(_backpack().call("auto_place", item_a)), "Die Kameradrohne passt wieder ins Raster.")
	_sync()
	_check(_drones().size() == 2 and _drones()[0] == third and _drone_levels() == [1, 5], "Wieder eingeräumt: zwei Drohnen, die legendäre ist dieselbe.")
	var fourth: Node3D = _drones()[1] as Node3D
	_check(fourth != first and _drones_apart(1.0), "Die neue Drohne ist ein neuer Knoten an einem eigenen Platz.")
	# Zwei gleiche kombiniert: aus zwei Drohnen der Stufe 1 wird eine der Stufe 2.
	var item_d: int = int(_backpack().call("add_item", "drone", 1))
	_check(bool(_backpack().call("merge", item_d, item_a)), "Zwei gewöhnliche Kameradrohnen lassen sich kombinieren.")
	_sync()
	_check(_drones().size() == 2 and _drones()[0] == third and _drones()[1] == fourth and int(fourth.get("level")) == 2,
		"Kombiniert: Dieselbe Drohne steigt auf Stufe 2, Stufen %s." % [_drone_levels()])

	# Ein neuer Lauf räumt ab und baut neu auf. Mit Gegenständen im Rucksack entstehen neue Drohnen.
	_events.emit_signal("run_started")
	_check(_drones().size() == 2 and _drone_levels() == [2, 5], "Lauf-Beginn mit zwei Kameradrohnen: wieder zwei Drohnen.")
	_check(not _drones().has(third) and not _drones().has(fourth) and third.is_queued_for_deletion() and fourth.is_queued_for_deletion(),
		"Lauf-Beginn: Die alten Drohnen gehen, neue kommen.")
	var rebuilt: Array = _drones().duplicate()
	# Von selbst: Beide Drohnen schießen, und bei zwei Zombies bekommt jeder etwas ab.
	var target_a: DummyZombie = _zombie(Vector3(0.0, 0.0, -5.0))
	var target_b: DummyZombie = _zombie(Vector3(0.0, 0.0, -9.0))
	var frames: int = 0
	while (target_a.count("drone") == 0 or target_b.count("drone") == 0) and frames < 240:
		await physics_frame
		frames += 1
	_check(target_a.count("drone") > 0 and target_b.count("drone") > 0,
		"Zwei Drohnen verteilen sich von selbst auf zwei Zombies (%d und %d Treffer)." % [target_a.count("drone"), target_b.count("drone")])
	_check(_drones() == rebuilt, "Im laufenden Spiel bleiben die Drohnen dieselben.")
	_check(not is_instance_valid(first) and not is_instance_valid(second) and not is_instance_valid(third), "Die entfernten Drohnen sind aus dem Baum verschwunden.")
	# Ein wirklich neuer Lauf (leerer Rucksack): keine Drohne mehr.
	_fresh_run()
	_check(_drones().is_empty() and _effects.get("drone") == null, "Ein neuer Lauf ohne Kameradrohne hat keine Drohne.")
	await process_frame
	await process_frame
	var leftovers: bool = false
	for entry: Variant in rebuilt:
		if is_instance_valid(entry):
			leftovers = true
	_check(not leftovers and get_nodes_in_group("drones").is_empty(), "Alle Drohnen des alten Laufs sind aus dem Baum verschwunden.")


## Schaden, der nicht von einer Kugel stammt, löst nie Kugel-Effekte aus.
func _test_non_bullet_damage_is_inert() -> void:
	_fresh_run()
	_give("chain_lightning", 5)
	_give("pierce", 5)
	_give("burn", 5)
	var origin: DummyZombie = _zombie(Vector3.ZERO)
	var neighbor: DummyZombie = _zombie(Vector3(2.0, 0.0, 0.0))
	_give("poison", 5)
	_give("frost", 3)
	_give("ricochet", 5)
	for source: String in ["lightning", "burn", "explosion", "shockwave", "drone", "poison", "disco", "jammer",
			"cam_tele", "cam_flash", "cam_slow", "ricochet", "thorns", "mine"]:
		var info: Dictionary = {"source": source, "hit_position": Vector3.ZERO}
		origin.take_damage(20.0, info)
		# Selbst ein fälschlich gesendetes bullet_hit mit fremder Quelle bleibt ohne Wirkung.
		_events.emit_signal("bullet_hit", origin, 20.0, info)
		_events.emit_signal("weapon_fired", "pistol")
	_check(neighbor.hits.is_empty(), "Blitz, Brand, Explosion, Druckwelle, Drohne, Gift, Discokugel und Störsender lösen keinen Kettenblitz aus.")
	_check(origin.burn_calls == 0, "Blitz, Brand, Explosion, Druckwelle, Drohne, Gift, Discokugel und Störsender lösen keinen Brand aus.")
	_check(origin.poison_calls == 0, "Blitz, Brand, Explosion, Druckwelle, Drohne, Gift, Discokugel und Störsender vergiften niemanden.")
	_check(origin.slow_calls == 0 and neighbor.count("ricochet") == 0, "Auch Kameras, Querschläger, Stacheln und Minen lösen weder Trockeneis noch Querschläger aus.")
	# Gegenprobe: Die Kugel tut alles drei.
	_shot(origin, 20.0)
	_check(neighbor.count("lightning") == 1 and origin.burn_calls == 1, "Gegenprobe: Ein Kugeltreffer löst Blitz und Brand aus.")
	_check(origin.poison_calls == 1, "Gegenprobe: Ein Kugeltreffer vergiftet.")
	_check(origin.slow_calls == 1, "Gegenprobe: Ein Kugeltreffer verlangsamt (Trockeneis).")


# --- Hilfen für Abschnitt 19 (echte Zombies, Discokugeln) ---

## Echter Zombie aus zombie.gd mit viel Leben: An ihm tickt das Gift wirklich. Die Tests treiben
## ihn selbst an (_step_zombie), es vergeht dafür kein Bild.
func _real_zombie(at: Vector3, max_hp: float = 1000.0) -> Node3D:
	var zombie: Node3D = (load(ZOMBIE_PATH) as GDScript).new()
	zombie.call("setup", "walker", 1)
	zombie.set("max_hp", max_hp)
	zombie.set("hp", max_hp)
	zombie.position = at
	_zombie_root.add_child(zombie)
	return zombie


## Treibt einen echten Zombie ohne Bilder an: seconds in festen Schritten.
func _step_zombie(zombie: Node, seconds: float, step: float = 0.1) -> void:
	for i: int in roundi(seconds / step):
		if not is_instance_valid(zombie) or zombie.is_queued_for_deletion():
			return
		zombie.call("_physics_process", step)


## Ein Kugeltreffer ohne eigenen Schaden: nur das Signal, wie es die Waffe nach dem Treffer sendet.
## So steht in der Mitschrift allein der Schaden der Effekte.
func _signal_hit(zombie: Node3D, weapon_uid: int) -> void:
	var info: Dictionary = _bullet_info()
	info["weapon_uid"] = weapon_uid
	info["weapon"] = "pistol"
	info["hand"] = 0
	_events.emit_signal("bullet_hit", zombie, 5.0, info)
	_events.emit_signal("weapon_fired", "pistol")


func _start_log() -> void:
	_logging = true
	_damage_log.clear()
	_kill_log.clear()
	_bullet_hits = 0


func _stop_log() -> void:
	_logging = false
	_damage_log.clear()
	_kill_log.clear()


## Summe des mitgeschriebenen Schadens an diesem Zombie aus dieser Quelle.
func _logged(zombie: Node3D, source: String) -> float:
	var sum: float = 0.0
	for entry: Dictionary in _damage_log:
		if entry["zombie"] == zombie and entry["source"] == source:
			sum += float(entry["amount"])
	return sum


## Zahl der mitgeschriebenen Treffer an diesem Zombie aus dieser Quelle.
func _logged_count(zombie: Node3D, source: String) -> int:
	var n: int = 0
	for entry: Dictionary in _damage_log:
		if entry["zombie"] == zombie and entry["source"] == source:
			n += 1
	return n


## Ist der Zombie sichtbar vergiftet (Giftblasen da und sichtbar)?
func _poison_mark_shown(zombie: Node3D) -> bool:
	var mark: Node3D = zombie.get_node_or_null("Body/Poison") as Node3D
	return mark != null and mark.visible


func _balls() -> Array:
	return _effects.get("disco_balls") as Array


## Stelle einer Discokugel für das Spiel (nicht die sichtbare, die zwischen zwei Schritten gleitet).
func _ball_position(ball: Variant) -> Vector3:
	return (ball as Node3D).call("get_orbit_position")


## Dieselbe Stelle auf dem Boden: Dort steht ein Zombie genau unter der Kugel.
func _under(ball: Variant) -> Vector3:
	var at: Vector3 = _ball_position(ball)
	return Vector3(at.x, 0.0, at.z)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Stufen aller Discokugeln, sortiert.
func _ball_levels() -> Array:
	var levels: Array = []
	for entry: Variant in _balls():
		levels.append(int((entry as Node3D).get("level")))
	levels.sort()
	return levels


## Stehen alle Discokugeln im Abstand des Kreises um den Spieler und gleichmäßig verteilt?
func _balls_evenly_spread() -> bool:
	var list: Array = _balls()
	var radius: float = Balance.DISCO_ORBIT_RADIUS
	var count: int = list.size()
	if count == 0:
		return false
	# Abstand zweier Nachbarn auf dem Kreis: Sehne über den Winkel TAU / count.
	var chord: float = 2.0 * radius * sin(PI / float(count))
	for i: int in count:
		if not _near(_flat_distance(_ball_position(list[i]), _player.global_position), radius, 0.005):
			return false
		if count > 1 and not _near(_flat_distance(_ball_position(list[i]), _ball_position(list[(i + 1) % count])), chord, 0.01):
			return false
	return true


func _jammer_left() -> float:
	return float(_effects.call("get_jammer_time_left"))


## Hängt gerade ein Effekt mit diesem Namensteil im Effekt-Behälter?
func _fx_has(name_part: String) -> bool:
	for child: Node in _fx_root.get_children():
		if String(child.name).contains(name_part) and not child.is_queued_for_deletion():
			return true
	return false


# --- Gift (Kantinenessen) ---

## Das Gift gilt je Waffe: Nur Treffer der Waffe, die ein Stern des Kantinenessens berührt,
## vergiften. Geprüft mit Ersatz-Zombies, die den Aufruf apply_poison mitschreiben.
func _test_poison_per_weapon() -> void:
	var pistols: Array[int] = _two_pistols()
	var left: int = pistols[0]
	var right: int = pistols[1]
	# Ein Feld bei (1,2): Der Stern rechts oben liegt auf (2,1), dem zweiten Feld der linken Pistole.
	var poison: int = _put("poison", 2, Vector2i(1, 2), 0)
	_sync()
	_check(_targets_are(poison, [left]), "Das Kantinenessen berührt mit seinen Sternen nur die linke Pistole.")
	_check(_bullet_level(left, "poison") == 2, "Für die linke Pistole wirkt das Gift (Rarität 2).")
	for other: int in [right, 0, -1]:
		_check(_bullet_level(other, "poison") == 0, "Für die Waffe %d wirkt kein Gift." % other)
	var dps: float = UpgradeDefs.value("poison", "dps", 2)
	var target: DummyZombie = _zombie(Vector3(0.0, 0.0, -30.0))
	for other: int in [right, 0, -1]:
		_weapon_shot(target, 5.0, other)
		_check(target.poison_calls == 0, "Treffer der Waffe %d vergiften niemanden." % other)
	_shot(target, 5.0)
	_check(target.poison_calls == 0, "Treffer ohne weapon_uid vergiften niemanden.")
	_weapon_shot(target, 5.0, left)
	_check(target.poison_calls == 1 and _near(target.poison_dps, dps) and _near(target.poison_duration, Balance.POISON_DURATION),
		"Die linke Pistole vergiftet: %s Schaden je Sekunde für %s s, waren %s und %s." % [dps, Balance.POISON_DURATION, target.poison_dps, target.poison_duration])
	# Jeder weitere Treffer meldet sich wieder (der Zombie stellt damit die Zeit neu).
	_weapon_shot(target, 5.0, left)
	_check(target.poison_calls == 2, "Jeder Kugeltreffer vergiftet aufs Neue.")
	# Effekt-Faktor: Der feste Schaden wächst mit der Welle.
	_game.set("wave", 10)
	var factor: float = WavePlan.effect_factor(10)
	_weapon_shot(target, 5.0, left)
	_check(factor > 1.0 and _near(target.poison_dps, dps * factor, 0.001),
		"In Welle 10 ist das Gift mal %s: %s je Sekunde, waren %s." % [factor, dps * factor, target.poison_dps])
	_game.set("wave", 0)
	# Ein tödlicher Treffer vergiftet niemanden mehr.
	var victim: DummyZombie = _zombie(Vector3(3.0, 0.0, -30.0), 5.0)
	_weapon_shot(victim, 10.0, left)
	_check(victim.is_dead and victim.poison_calls == 0, "Tote werden nicht vergiftet.")
	# In der Ablage wirkt das Kantinenessen nicht mehr.
	_backpack().call("store", poison)
	_sync()
	var calls_before: int = target.poison_calls
	_weapon_shot(target, 5.0, left)
	_check(_bullet_level(left, "poison") == 0 and target.poison_calls == calls_before, "Ohne den Gegenstand im Raster vergiftet die linke Pistole nicht mehr.")


## Das Gift am echten Zombie: richtige Summe über die Dauer, ein zweiter Treffer stellt die Zeit
## neu, zwei Exemplare addieren sich, der höhere Wert bleibt, es endet von selbst und verschwindet
## mit dem Zombie.
func _test_poison_ticks() -> void:
	_fresh_run()
	# Ohne Spieler bleiben die echten Zombies stehen und greifen niemanden an.
	_game.set("player", null)
	# Eine Pistole auf (2,2) und (3,2): Die Ecken (1,1) und (4,3) berühren sie mit einem Stern.
	var pistol: int = _put("pistol", 1, Vector2i(2, 2), 0)
	var poison_a: int = _put("poison", 1, Vector2i(1, 1), 0)
	_sync()
	_check(_targets_are(poison_a, [pistol]), "Das Kantinenessen in der Ecke berührt die Pistole.")
	var duration: float = Balance.POISON_DURATION
	var dps: float = UpgradeDefs.value("poison", "dps", 1)
	_check(_near(_bullet_value(pistol, "poison", "dps"), dps), "Ein Kantinenessen: %s Schaden je Sekunde." % dps)
	_start_log()

	# Ein Treffer: dps * Dauer, in Ticks wie der Brand, danach von selbst vorbei.
	var zombie: Node3D = _real_zombie(Vector3(0.0, 0.0, -40.0))
	_check(not bool(zombie.call("is_poisoned")) and not _poison_mark_shown(zombie), "Ein frischer Zombie ist nicht vergiftet.")
	_signal_hit(zombie, pistol)
	_check(bool(zombie.call("is_poisoned")), "Der Kugeltreffer vergiftet den Zombie.")
	_check(_poison_mark_shown(zombie), "Der vergiftete Zombie trägt sichtbare Giftblasen.")
	_check(_damage_log.is_empty(), "Der erste Gift-Tick kommt erst nach dem Tick-Abstand.")
	_step_zombie(zombie, duration * 0.5)
	_check(bool(zombie.call("is_poisoned")) and _near(_logged(zombie, "poison"), dps * duration * 0.5, 0.01),
		"Nach der halben Dauer ist der halbe Giftschaden da: %s, waren %s." % [dps * duration * 0.5, _logged(zombie, "poison")])
	_step_zombie(zombie, duration * 0.5)
	var ticks: int = roundi(duration / Balance.BURN_TICK_INTERVAL)
	_check(_near(_logged(zombie, "poison"), dps * duration, 0.01),
		"Über die ganze Dauer fällt genau dps mal Dauer an: %s, waren %s." % [dps * duration, _logged(zombie, "poison")])
	_check(_logged_count(zombie, "poison") == ticks and _damage_log.size() == ticks,
		"Das Gift tickt %d-mal mit source poison, waren %d von %d Treffern." % [ticks, _logged_count(zombie, "poison"), _damage_log.size()])
	_check(_near(float(zombie.get("hp")), 1000.0 - dps * duration, 0.01), "Dem Zombie fehlt genau der Giftschaden.")
	_check(not bool(zombie.call("is_poisoned")), "Nach Ablauf der Dauer ist das Gift vorbei.")
	_check(not _poison_mark_shown(zombie), "Mit dem Gift verschwinden die Giftblasen.")
	_step_zombie(zombie, 2.0)
	_check(_logged_count(zombie, "poison") == ticks, "Nach dem Ende kommt kein Gift-Tick mehr.")
	_check(_bullet_hits == 1 and _kill_log.is_empty(), "Das Gift sendet kein bullet_hit und hat niemanden getötet.")

	# Ein zweiter Treffer nach 2 s stellt die Zeit neu: insgesamt 2 s + volle Dauer.
	_damage_log.clear()
	_signal_hit(zombie, pistol)
	_step_zombie(zombie, 2.0)
	_signal_hit(zombie, pistol)
	_step_zombie(zombie, duration - 0.1)
	_check(bool(zombie.call("is_poisoned")), "Der zweite Treffer stellt die Zeit neu: Kurz vor Ablauf wirkt das Gift noch.")
	_step_zombie(zombie, 0.2)
	_check(not bool(zombie.call("is_poisoned")), "Das Gift endet die volle Dauer nach dem zweiten Treffer.")
	_check(_near(_logged(zombie, "poison"), dps * (2.0 + duration), 0.01),
		"Zwei Treffer im Abstand von 2 s: %s Giftschaden, waren %s." % [dps * (2.0 + duration), _logged(zombie, "poison")])

	# Effekt-Faktor: In Welle 10 tickt das Gift entsprechend stärker.
	_damage_log.clear()
	_game.set("wave", 10)
	var factor: float = WavePlan.effect_factor(10)
	_signal_hit(zombie, pistol)
	_step_zombie(zombie, duration + 0.5)
	_check(factor > 1.0 and _near(_logged(zombie, "poison"), dps * factor * duration, 0.01),
		"In Welle 10 fällt dps mal Faktor mal Dauer an: %s, waren %s." % [dps * factor * duration, _logged(zombie, "poison")])
	_game.set("wave", 0)

	# Zwei Exemplare auf derselben Waffe addieren ihren Schaden je Sekunde.
	var poison_b: int = _put("poison", 3, Vector2i(4, 3), 0)
	_sync()
	var both: float = dps + UpgradeDefs.value("poison", "dps", 3)
	_check(_targets_are(poison_b, [pistol]) and _near(_bullet_value(pistol, "poison", "dps"), both),
		"Zwei Kantinenessen auf der Pistole: zusammen %s Schaden je Sekunde." % both)
	var second: Node3D = _real_zombie(Vector3(3.0, 0.0, -40.0))
	_damage_log.clear()
	_signal_hit(second, pistol)
	_step_zombie(second, duration + 0.5)
	_check(_near(_logged(second, "poison"), both * duration, 0.01),
		"Zwei Kantinenessen: %s Giftschaden über die Dauer, waren %s." % [both * duration, _logged(second, "poison")])

	# Der höhere Wert bleibt: Erst mit beiden vergiftet, dann nur noch mit dem schwächeren getroffen.
	_damage_log.clear()
	_signal_hit(second, pistol)
	_step_zombie(second, 1.0)
	_game.call("sell_item", poison_b)
	_check(_near(_bullet_value(pistol, "poison", "dps"), dps), "Nach dem Verkauf zählt nur noch das gewöhnliche Kantinenessen.")
	_signal_hit(second, pistol)
	_step_zombie(second, duration + 0.5)
	_check(_near(_logged(second, "poison"), both * (1.0 + duration), 0.01),
		"Ein schwächerer Treffer stellt die Zeit neu, der höhere Schaden bleibt: %s, waren %s." % [both * (1.0 + duration), _logged(second, "poison")])

	# Gift tötet: genau ein Kill mit source poison, danach kein Tick mehr.
	_start_log()
	var weak: Node3D = _real_zombie(Vector3(6.0, 0.0, -40.0), 10.0)
	_signal_hit(weak, pistol)
	_step_zombie(weak, duration)
	_check(bool(weak.get("is_dead")) and _kill_log.size() == 1 and _kill_log[0]["zombie"] == weak and _kill_log[0]["source"] == "poison",
		"Gift kann töten: ein Kill mit source poison, waren %d Kills." % _kill_log.size())
	_check(_logged_count(weak, "poison") == ceili(10.0 / (dps * Balance.BURN_TICK_INTERVAL)), "Nach dem Tod tickt das Gift nicht weiter (Ticks: %d)." % _logged_count(weak, "poison"))
	_check(not bool(weak.call("is_poisoned")) and not _poison_mark_shown(weak), "Der Tote ist nicht mehr vergiftet, die Giftblasen sind weg.")

	# Stirbt ein vergifteter Zombie an etwas anderem, ist das Gift sofort weg.
	_start_log()
	var shot_dead: Node3D = _real_zombie(Vector3(9.0, 0.0, -40.0))
	_signal_hit(shot_dead, pistol)
	_step_zombie(shot_dead, 1.0)
	var ticks_before: int = _logged_count(shot_dead, "poison")
	_check(ticks_before == roundi(1.0 / Balance.BURN_TICK_INTERVAL) and _poison_mark_shown(shot_dead), "Der Zombie ist vergiftet und nimmt Giftschaden.")
	shot_dead.call("take_damage", 5000.0, {"source": "bullet"})
	_check(bool(shot_dead.get("is_dead")) and not bool(shot_dead.call("is_poisoned")) and not _poison_mark_shown(shot_dead),
		"Mit dem Tod endet das Gift, die Giftblasen verschwinden.")
	shot_dead.call("apply_poison", 50.0, duration)
	_check(not bool(shot_dead.call("is_poisoned")), "Ein toter Zombie wird nicht mehr vergiftet.")
	_step_zombie(shot_dead, 0.2)
	_check(_logged_count(shot_dead, "poison") == ticks_before and _kill_log.size() == 1, "Am Toten tickt kein Gift, er stirbt nur einmal.")
	# despawn räumt das Gift ebenfalls weg.
	var removed: Node3D = _real_zombie(Vector3(12.0, 0.0, -40.0))
	_signal_hit(removed, pistol)
	_check(bool(removed.call("is_poisoned")), "Der Zombie ist vor dem Entfernen vergiftet.")
	removed.call("despawn")
	_check(not bool(removed.call("is_poisoned")) and not _poison_mark_shown(removed), "despawn nimmt das Gift weg.")
	# Ungültige Werte tun nichts.
	zombie.call("apply_poison", 0.0, duration)
	zombie.call("apply_poison", 5.0, 0.0)
	_check(not bool(zombie.call("is_poisoned")), "apply_poison ohne Schaden oder ohne Dauer tut nichts.")
	_stop_log()
	for node: Node in _zombie_root.get_children():
		node.free()
	_game.set("player", _player)


## Gift neben den anderen Effekten: Es brennt und wirkt zugleich, und sein Schaden löst keinen
## Kugel-Effekt aus (kein Blitz, keine neue Vergiftung, kein neuer Brand).
func _test_poison_with_other_effects() -> void:
	# Brand und Gift zugleich: Beide ticken unabhängig, die Summen stimmen einzeln.
	_fresh_run()
	_game.set("player", null)
	_give("poison", 1)
	_give("burn", 1)
	var duration: float = Balance.POISON_DURATION
	var poison_total: float = UpgradeDefs.value("poison", "dps", 1) * duration
	var burn_total: float = UpgradeDefs.value("burn", "dps_percent", 1) * 1000.0 * Balance.BURN_DURATION
	_start_log()
	var zombie: Node3D = _real_zombie(Vector3(0.0, 0.0, -40.0))
	_signal_hit(zombie, -1)
	_check(bool(zombie.call("is_poisoned")) and bool(zombie.call("is_burning")), "Ein Treffer vergiftet und zündet an: beides wirkt zugleich.")
	_step_zombie(zombie, 1.0)
	_check(bool(zombie.call("is_poisoned")) and bool(zombie.call("is_burning")) and _poison_mark_shown(zombie)
		and _logged(zombie, "poison") > 0.0 and _logged(zombie, "burn") > 0.0, "Nach 1 s ticken Gift und Brand nebeneinander.")
	_step_zombie(zombie, maxf(duration, Balance.BURN_DURATION) + 0.5)
	_check(_near(_logged(zombie, "poison"), poison_total, 0.01), "Neben dem Brand macht das Gift genau %s Schaden, waren %s." % [poison_total, _logged(zombie, "poison")])
	_check(_near(_logged(zombie, "burn"), burn_total, 0.01), "Neben dem Gift macht der Brand genau %s Schaden, waren %s." % [burn_total, _logged(zombie, "burn")])
	_check(_near(float(zombie.get("hp")), 1000.0 - poison_total - burn_total, 0.01), "Dem Zombie fehlen Gift und Brand zusammen.")
	_check(not bool(zombie.call("is_poisoned")) and not bool(zombie.call("is_burning")), "Beides endet von selbst.")
	_check(_bullet_hits == 1, "Weder Gift noch Brand senden ein bullet_hit.")

	# Gift mit sicherem Blitz (Gewitterfront): Der eine Kugeltreffer blitzt einmal. Die Gift-Ticks
	# danach blitzen nicht, vergiften nicht neu und verlängern damit auch die Dauer nicht.
	_fresh_run()
	_game.set("player", null)
	_give("poison", 1)
	_give("chain_lightning", 5)
	_give("pierce", 5)
	_start_log()
	var origin: Node3D = _real_zombie(Vector3(0.0, 0.0, -40.0))
	var neighbor: DummyZombie = _zombie(Vector3(2.0, 0.0, -40.0))
	_signal_hit(origin, -1)
	_check(neighbor.count("lightning") == 1 and neighbor.poison_calls == 0, "Der Kugeltreffer blitzt einmal auf den Nachbarn, vergiftet ihn aber nicht.")
	_step_zombie(origin, duration - 0.1)
	_check(bool(origin.call("is_poisoned")), "Kurz vor Ablauf wirkt das Gift noch.")
	_step_zombie(origin, 0.2)
	_check(not bool(origin.call("is_poisoned")), "Die Gift-Ticks verlängern das Gift nicht: Es endet nach der Dauer.")
	_check(_near(_logged(origin, "poison"), poison_total, 0.01), "Das Gift hat genau %s Schaden gemacht." % poison_total)
	_check(neighbor.count("lightning") == 1 and neighbor.hits.size() == 1, "Giftschaden löst keinen weiteren Blitz aus, Treffer am Nachbarn: %d." % neighbor.hits.size())
	_check(_bullet_hits == 1, "Es gab nur das eine bullet_hit der Kugel.")
	_stop_log()
	for node: Node in _zombie_root.get_children():
		node.free()
	_game.set("player", _player)


# --- Trostpflaster ---

func _test_kill_heal() -> void:
	var sources: Array[String] = ["bullet", "burn", "poison", "lightning", "explosion", "shockwave", "drone", "disco", "jammer"]
	# Ohne den Gegenstand heilt kein Kill.
	_fresh_run()
	for source: String in sources:
		_zombie(Vector3(0.0, 0.0, -30.0), 10.0).take_damage(50.0, {"source": source})
	_check(_near(_player.healed, 0.0) and _near(_player.hp, 50.0), "Ohne Trostpflaster heilt kein Kill.")

	# Zwei Exemplare (Gewöhnlich 2, Selten 4): Jeder Kill heilt 6, gleich welche Quelle.
	_fresh_run()
	_player.max_hp = 500.0
	var plaster_a: int = _auto("kill_heal", 1)
	_auto("kill_heal", 3)
	_sync()
	var heal: float = UpgradeDefs.value("kill_heal", "heal", 1) + UpgradeDefs.value("kill_heal", "heal", 3)
	_check(_near(float(_upgrades().call("value", "kill_heal", "heal")), heal) and _near(heal, 6.0), "Zwei Trostpflaster: Die Heilung addiert sich zu 6.")
	var kills: int = 0
	for source: String in sources:
		var victim: DummyZombie = _zombie(Vector3(0.0, 0.0, -30.0), 10.0)
		victim.take_damage(50.0, {"source": source})
		kills += 1
		_check(victim.is_dead and _near(_player.healed, heal * float(kills)),
			"Ein Kill durch %s heilt %s Leben, insgesamt %s, waren %s." % [source, heal, heal * float(kills), _player.healed])
	_check(_near(_player.hp, 50.0 + heal * float(kills)), "Das Leben des Spielers ist um die Summe gestiegen.")
	# Ein Treffer, der nicht tötet, heilt nicht.
	var tough: DummyZombie = _zombie(Vector3(0.0, 0.0, -30.0))
	tough.take_damage(50.0, {"source": "bullet"})
	_check(_near(_player.healed, heal * float(kills)), "Ein Treffer ohne Kill heilt nicht.")
	# Ein echter Zombie zählt genauso.
	var real: Node3D = _real_zombie(Vector3(0.0, 0.0, -40.0), 10.0)
	real.call("take_damage", 50.0, {"source": "bullet"})
	kills += 1
	_check(_near(_player.healed, heal * float(kills)), "Auch der Kill eines echten Zombies heilt.")
	real.free()
	# Nie über das Maximal-Leben.
	_player.hp = _player.max_hp - 1.0
	_zombie(Vector3(0.0, 0.0, -30.0), 10.0).take_damage(50.0, {"source": "bullet"})
	_check(_near(_player.hp, _player.max_hp), "Trostpflaster heilt nie über das Maximal-Leben, Leben: %s." % _player.hp)
	_zombie(Vector3(0.0, 0.0, -30.0), 10.0).take_damage(50.0, {"source": "jammer"})
	_check(_near(_player.hp, _player.max_hp), "Bei vollem Leben bleibt es beim Maximal-Leben.")
	# Ein toter Spieler wird nicht geheilt.
	_player.hp = 10.0
	_player.healed = 0.0
	_player.is_dead = true
	_zombie(Vector3(0.0, 0.0, -30.0), 10.0).take_damage(50.0, {"source": "bullet"})
	_check(_near(_player.healed, 0.0), "Ein toter Spieler wird nicht geheilt.")
	_player.is_dead = false
	# Ein Exemplar in der Ablage: Es heilt nur noch das andere.
	_backpack().call("store", plaster_a)
	_sync()
	_zombie(Vector3(0.0, 0.0, -30.0), 10.0).take_damage(50.0, {"source": "bullet"})
	_check(_near(_player.healed, UpgradeDefs.value("kill_heal", "heal", 3)), "Mit einem Trostpflaster in der Ablage heilt nur noch das andere.")


# --- Discokugel ---

## Je Exemplar eine Kugel, gleichmäßig über den Kreis verteilt, mit dem Abgleich der Drohnen.
func _test_disco_balls() -> void:
	var radius: float = Balance.DISCO_ORBIT_RADIUS
	var speed: float = Balance.DISCO_ORBIT_SPEED
	# Kein Gegenstand: keine Kugel.
	_fresh_run()
	_sync()
	_effects.call("tick", 0.016)
	_check(_balls().is_empty() and get_nodes_in_group("disco_balls").is_empty(), "Ohne Discokugel im Rucksack kreist nichts.")

	# Ein Gegenstand: eine Kugel, schon mit build_changed.
	_player.position = Vector3(3.0, 0.0, -2.0)
	var item_a: int = _auto("disco_ball", 2)
	_sync()
	_check((_upgrades().call("copies", "disco_ball") as Array) == [2], "Game.upgrades.copies nennt ein Exemplar der Rarität 2.")
	_check(_balls().size() == 1 and _ball_levels() == [2], "Eine Discokugel im Rucksack: eine Kugel der Stufe 2.")
	if _balls().size() != 1:
		return
	var first: Node3D = _balls()[0] as Node3D
	_check(first.get_parent() == _fx_root and first.is_in_group("disco_balls"), "Die Kugel hängt im Effekt-Behälter und in der Gruppe disco_balls.")
	var at: Vector3 = _ball_position(first)
	_check(_near(_flat_distance(at, _player.global_position), radius, 0.005),
		"Die Kugel steht %s m vom Spieler entfernt, waren %s." % [radius, _flat_distance(at, _player.global_position)])
	_check(at.y - _player.global_position.y > 0.8 and at.y - _player.global_position.y < 1.5, "Die Kugel schwebt etwa in Brusthöhe (%s m)." % (at.y - _player.global_position.y))
	_check(first.global_position.distance_to(at) < 0.001, "Der Knoten steht an der Stelle der Kugel.")
	_check(_near(float(first.call("get_hit_damage")), UpgradeDefs.value("disco_ball", "damage", 2)), "Die Kugel macht den Schaden ihrer Stufe 2.")
	_check(first.get_node_or_null("Spin/Mirror") != null and first.get_node_or_null("Spin/Speck0") != null and first.get_node_or_null("Lights/Light0") != null,
		"Die Kugel besteht aus Spiegelkugel und bunten Lichtflecken.")

	# Sie kreist: Balance.DISCO_ORBIT_SPEED Radiant je Sekunde, immer im selben Abstand.
	var angle_before: float = float(first.call("get_orbit_angle"))
	_effects.call("tick", 0.5)
	var turned: float = fposmod(float(first.call("get_orbit_angle")) - angle_before, TAU)
	_check(_near(turned, speed * 0.5, 0.001), "In 0,5 s kreist die Kugel um %s Radiant weiter, waren %s." % [speed * 0.5, turned])
	_check(_balls_evenly_spread() and _ball_position(first).distance_to(at) > 0.5, "Sie bleibt dabei auf dem Kreis um den Spieler.")
	# Sie folgt dem Spieler.
	_player.position = Vector3(-5.0, 0.0, 4.0)
	_effects.call("tick", 0.016)
	_check(_balls_evenly_spread(), "Die Kugel folgt dem Spieler.")
	# Pause: Die Kugel steht.
	var held_at: Vector3 = _ball_position(first)
	var held_angle: float = float(first.call("get_orbit_angle"))
	_game.call("set_paused", true)
	_effects.call("tick", 0.5)
	_check(_ball_position(first).distance_to(held_at) < 0.0001 and _near(float(first.call("get_orbit_angle")), held_angle, 0.0001), "In der Pause steht die Kugel still.")
	_game.call("set_paused", false)
	_effects.call("tick", 0.1)
	_check(_ball_position(first).distance_to(held_at) > 0.1, "Nach der Pause kreist sie weiter.")

	# Drei Gegenstände: drei Kugeln ihrer Stufen, gleichmäßig über den Kreis verteilt.
	var item_b: int = _auto("disco_ball", 1)
	var item_c: int = _auto("disco_ball", 4)
	_sync()
	var three: Array = _balls().duplicate()
	_check(three.size() == 3 and _ball_levels() == [1, 2, 4], "Drei Discokugeln: drei Kugeln der Stufen 1, 2 und 4, waren %s." % [_ball_levels()])
	if three.size() != 3:
		return
	_check(three[0] == first, "Die schon vorhandene Kugel bleibt dieselbe.")
	var second: Node3D = three[1] as Node3D
	var third: Node3D = three[2] as Node3D
	_check(int(second.get("level")) == 1 and int(third.get("level")) == 4, "Die neuen Kugeln haben die Stufen 1 und 4.")
	_check(int(first.get("slot")) == 0 and int(second.get("slot")) == 1 and int(third.get("slot")) == 2 and int(third.get("count")) == 3, "Jede Kugel hat ihren eigenen Platz auf dem Kreis.")
	_check(_balls_evenly_spread(), "Drei Kugeln stehen an verschiedenen Stellen, gleichmäßig über den Kreis verteilt.")
	_check(_near(_flat_distance(_ball_position(first), _ball_position(second)), radius * sqrt(3.0), 0.01), "Zwei der drei Kugeln stehen %s m auseinander." % (radius * sqrt(3.0)))
	_effects.call("tick", 0.3)
	_effects.call("tick", 0.45)
	_check(_balls_evenly_spread(), "Beim Kreisen bleiben die drei Kugeln gleichmäßig verteilt.")
	# Ein weiterer Abgleich ohne Änderung lässt alles, wie es ist.
	_effects.call("tick", 0.016)
	_events.emit_signal("upgrade_chosen", "disco_ball", 4)
	_events.emit_signal("build_changed")
	_check(_balls() == three, "Ein Abgleich ohne Änderung behält alle drei Kugeln.")

	# Ein Gegenstand weg (verkauft): genau eine Kugel weniger, die anderen Knoten bleiben.
	_game.call("sell_item", item_b)
	_check(_balls().size() == 2 and _ball_levels() == [2, 4], "Nach dem Verkauf der gewöhnlichen Discokugel bleiben die Stufen 2 und 4, waren %s." % [_ball_levels()])
	_check(_balls().has(first) and _balls().has(third) and not _balls().has(second), "Die beiden anderen Kugeln sind dieselben Knoten geblieben.")
	_check(second.is_queued_for_deletion() and not first.is_queued_for_deletion() and not third.is_queued_for_deletion(), "Nur die Kugel des verkauften Gegenstands verschwindet.")
	_check(_balls_evenly_spread() and _near(_flat_distance(_ball_position(first), _ball_position(third)), radius * 2.0, 0.01), "Die beiden verbliebenen Kugeln stehen sich gegenüber.")
	# Ein Gegenstand in die Ablage: wieder eine weniger.
	_backpack().call("store", item_a)
	_sync()
	_check(_balls().size() == 1 and _balls()[0] == third and first.is_queued_for_deletion(), "In der Ablage wirkt die Discokugel nicht: Es bleibt die der Stufe 4.")
	# Wieder eingeräumt: eine neue Kugel kommt dazu.
	_check(bool(_backpack().call("auto_place", item_a)), "Die Discokugel passt wieder ins Raster.")
	_sync()
	_check(_balls().size() == 2 and _balls()[0] == third and _ball_levels() == [2, 4] and _balls()[1] != first, "Wieder eingeräumt: zwei Kugeln, die neue ist ein neuer Knoten.")
	var fourth: Node3D = _balls()[1] as Node3D
	# Die Stufe folgt dem Gegenstand: zwei gleiche kombiniert, dieselbe Kugel steigt auf.
	var item_d: int = int(_backpack().call("add_item", "disco_ball", 2))
	_check(bool(_backpack().call("merge", item_d, item_a)), "Zwei ungewöhnliche Discokugeln lassen sich kombinieren.")
	_sync()
	_check(_balls().size() == 2 and _balls()[1] == fourth and int(fourth.get("level")) == 3, "Kombiniert: Dieselbe Kugel steigt auf Stufe 3, Stufen %s." % [_ball_levels()])

	# Ein neuer Lauf räumt ab und baut neu auf.
	_events.emit_signal("run_started")
	_check(_balls().size() == 2 and _ball_levels() == [3, 4], "Lauf-Beginn mit zwei Discokugeln: wieder zwei Kugeln.")
	_check(not _balls().has(third) and not _balls().has(fourth) and third.is_queued_for_deletion() and fourth.is_queued_for_deletion(), "Lauf-Beginn: Die alten Kugeln gehen, neue kommen.")
	_check(_balls_evenly_spread(), "Auch die neuen Kugeln stehen gleichmäßig auf dem Kreis.")
	var rebuilt: Array = _balls().duplicate()
	# Von selbst: Im laufenden Spiel kreisen die Kugeln und treffen einen Zombie auf dem Kreis.
	var angle_start: float = float((rebuilt[0] as Node3D).call("get_orbit_angle"))
	var post: DummyZombie = _zombie(_player.global_position + Vector3(cos(angle_start + 1.0), 0.0, sin(angle_start + 1.0)) * radius)
	var frames: int = 0
	while post.count("disco") == 0 and frames < 240:
		await physics_frame
		frames += 1
	_check(post.count("disco") > 0, "Im laufenden Spiel trifft eine kreisende Kugel den Zombie auf ihrem Kreis.")
	_check(fposmod(float((rebuilt[0] as Node3D).call("get_orbit_angle")) - angle_start, TAU) > 0.1, "Die Kugeln kreisen von selbst.")
	_check(_balls() == rebuilt, "Im laufenden Spiel bleiben die Kugeln dieselben.")

	# Wiederholung (Abschnitt 19.3): Die Discokugel auf ihrem Stern zählt zweimal, also zwei Kugeln.
	_fresh_run()
	_check(_balls().is_empty(), "Ein neuer Lauf ohne Discokugel hat keine Kugel.")
	_put("disco_ball", 4, Vector2i(2, 1), 0)
	_put("replay", 3, Vector2i(1, 1), 0)
	_sync()
	var copies: Array = (_upgrades().call("copies", "disco_ball") as Array).duplicate()
	copies.sort()
	_check(copies == [3, 4], "Mit der Wiederholung zählt die Discokugel zweimal (Raritäten %s)." % [copies])
	_check(_ball_levels() == copies and _balls_evenly_spread(), "Wiederholung: zwei Kugeln, Stufen %s." % [_ball_levels()])
	var replayed: Array = _balls().duplicate()

	# Ein wirklich neuer Lauf (leerer Rucksack): keine Kugel mehr, alle alten Knoten verschwinden.
	_fresh_run()
	_check(_balls().is_empty(), "Ein neuer Lauf räumt die Kugeln weg.")
	await process_frame
	await process_frame
	var leftovers: bool = false
	for entry: Variant in three + rebuilt + replayed + [fourth]:
		if is_instance_valid(entry):
			leftovers = true
	_check(not leftovers and get_nodes_in_group("disco_balls").is_empty(), "Alle Kugeln des alten Laufs sind aus dem Baum verschwunden.")


## Treffer der Discokugel: Schaden der Stufe an jedem Zombie in Reichweite, am selben Zombie
## höchstens alle Balance.DISCO_HIT_INTERVAL Sekunden je Kugel. Der Test treibt die Zeit selbst an.
func _test_disco_ball_hits() -> void:
	var radius: float = Balance.DISCO_ORBIT_RADIUS
	var reach: float = Balance.DISCO_HIT_RADIUS
	var interval: float = Balance.DISCO_HIT_INTERVAL
	var step: float = 1.0 / 60.0
	_fresh_run()
	_auto("disco_ball", 2)
	_sync()
	if _balls().size() != 1:
		_check(false, "Eine Discokugel kreist.")
		return
	var ball: Node3D = _balls()[0] as Node3D
	var damage: float = UpgradeDefs.value("disco_ball", "damage", 2)
	# Ein Zombie läuft genau unter der Kugel mit, einer steht beim Spieler, einer knapp außerhalb des Kreises.
	var rider: DummyZombie = _zombie(_under(ball))
	var center: DummyZombie = _zombie(Vector3(0.3, 0.0, 0.0))
	var beyond: DummyZombie = _zombie(Vector3(radius + reach + 0.2, 0.0, 0.0))
	# In der Pause trifft die Kugel niemanden.
	_game.call("set_paused", true)
	_effects.call("tick", interval * 2.0)
	_check(rider.hits.is_empty(), "In der Pause macht die Kugel keinen Schaden.")
	_game.call("set_paused", false)
	# Zwei Sekunden in Schritten von 1/60 s: Treffer sofort, dann genau alle 0,5 s.
	var hit_ticks: Array[int] = []
	for i: int in 120:
		var before: int = rider.count("disco")
		_effects.call("tick", step)
		if rider.count("disco") > before:
			hit_ticks.append(i + 1)
		rider.position = _under(ball)
	var per_interval: int = roundi(interval / step)
	_check(rider.count("disco") == 4 and _near(rider.total("disco"), damage * 4.0, 0.001),
		"Zwei Sekunden unter der Kugel: 4 Treffer zu je %s Schaden, waren %d mit zusammen %s." % [damage, rider.count("disco"), rider.total("disco")])
	_check(hit_ticks == [1, 1 + per_interval, 1 + 2 * per_interval, 1 + 3 * per_interval],
		"Der erste Treffer kommt sofort, danach genau alle %s s (Schritte %s)." % [interval, hit_ticks])
	_check(rider.count("disco") == rider.hits.size() and rider.burn_calls == 0 and rider.poison_calls == 0, "Die Kugel trifft mit source disco und löst keinen Kugel-Effekt aus.")
	_check(center.hits.is_empty(), "Ein Zombie beim Spieler ist außer Reichweite der Kugel.")
	_check(beyond.hits.is_empty(), "Ein Zombie knapp außerhalb des Kreises bekommt keinen Schaden.")
	# Effekt-Faktor: Der feste Schaden wächst mit der Welle.
	_game.set("wave", 10)
	var factor: float = WavePlan.effect_factor(10)
	for i: int in per_interval - 1:
		_effects.call("tick", step)
		rider.position = _under(ball)
	_check(rider.count("disco") == 5 and factor > 1.0 and _near(float(rider.hits[rider.hits.size() - 1]["amount"]), damage * factor, 0.01),
		"In Welle 10 ist der Schaden der Kugel mal %s." % factor)
	_game.set("wave", 0)
	# Höhe: Ein Zombie tief unter dem Spieler (anderes Stockwerk) wird nicht getroffen.
	var below: DummyZombie = _zombie(_under(ball) + Vector3(0.0, -6.0, 0.0))
	_effects.call("tick", step)
	_check(below.hits.is_empty(), "Ein Zombie weit unter der Kugel wird nicht getroffen.")
	below.free()
	# Tote sind kein Ziel, und ein Zombie, der mitten im Schritt verschwindet, stört nicht.
	rider.free()
	var weak: DummyZombie = _zombie(_under(ball), 10.0)
	var ghost: DummyZombie = _zombie(_under(ball) + Vector3(0.1, 0.0, 0.0))
	var witness: DummyZombie = _zombie(_under(ball) + Vector3(-0.1, 0.0, 0.0))
	weak.vanishes_with_me = ghost
	_effects.call("tick", 0.0)
	_check(weak.is_dead and not is_instance_valid(ghost) and witness.count("disco") == 1, "Die Kugel tötet, und ein verschwindender Zombie stört den Schritt nicht.")
	_effects.call("tick", interval + step)
	weak.position = _under(ball)
	witness.position = _under(ball)
	_effects.call("tick", 0.0)
	_check(weak.count("disco") == 1 and witness.count("disco") == 2, "Nach der Wartezeit trifft die Kugel den Lebenden wieder, den Toten nicht.")
	weak.free()
	witness.free()
	center.free()
	beyond.free()

	# Die Wartezeit gilt je Kugel: Zwei Kugeln treffen denselben Zombie direkt nacheinander.
	_fresh_run()
	_auto("disco_ball", 1)
	_auto("disco_ball", 3)
	_sync()
	if _balls().size() != 2:
		_check(false, "Zwei Discokugeln kreisen.")
		return
	var ball_a: Node3D = _balls()[0] as Node3D
	var ball_b: Node3D = _balls()[1] as Node3D
	# Zwei Kugeln teilen ihre Kraft: jede macht 1 / Wurzel 2 ihres Schadens.
	var damage_a: float = UpgradeDefs.value("disco_ball", "damage", int(ball_a.get("level"))) * UpgradeDefs.companion_factor(2)
	var damage_b: float = UpgradeDefs.value("disco_ball", "damage", int(ball_b.get("level"))) * UpgradeDefs.companion_factor(2)
	_check(not _near(damage_a, damage_b), "Die beiden Kugeln haben verschiedene Stufen.")
	var hopper: DummyZombie = _zombie(_under(ball_a))
	_effects.call("tick", step)
	_check(hopper.count("disco") == 1 and _near(hopper.total("disco"), damage_a), "Die erste Kugel trifft mit dem Schaden ihrer Stufe (%s)." % damage_a)
	hopper.position = _under(ball_b)
	_effects.call("tick", step)
	_check(hopper.count("disco") == 2 and _near(hopper.total("disco"), damage_a + damage_b),
		"Die zweite Kugel trifft denselben Zombie sofort mit ihrem eigenen Schaden (%s): Die Wartezeit gilt je Kugel." % damage_b)
	hopper.position = _under(ball_a)
	_effects.call("tick", step)
	hopper.position = _under(ball_b)
	_effects.call("tick", step)
	_check(hopper.count("disco") == 2, "Innerhalb der Wartezeit trifft keine der beiden Kugeln denselben Zombie noch einmal.")
	_check(int(ball_a.call("get_waiting_count")) == 1 and int(ball_b.call("get_waiting_count")) == 1, "Jede Kugel merkt sich ihre eigene Wartezeit.")
	hopper.free()

	# Drei Kugeln, ein Zombie fest auf dem Kreis: In einem Umlauf kommt jede Kugel einmal vorbei.
	_fresh_run()
	_auto("disco_ball", 1)
	_auto("disco_ball", 2)
	_auto("disco_ball", 4)
	_sync()
	if _balls().size() != 3:
		_check(false, "Drei Discokugeln kreisen.")
		return
	var sum: float = (UpgradeDefs.value("disco_ball", "damage", 1) + UpgradeDefs.value("disco_ball", "damage", 2) + UpgradeDefs.value("disco_ball", "damage", 4)) * UpgradeDefs.companion_factor(3)
	# In der Lücke zwischen zwei Kugeln: Am Anfang ist keine in Reichweite.
	var gap: float = float((_balls()[0] as Node3D).call("get_orbit_angle")) + PI / 3.0
	var post: DummyZombie = _zombie(Vector3(cos(gap), 0.0, sin(gap)) * radius)
	var outer: DummyZombie = _zombie(Vector3(cos(gap), 0.0, sin(gap)) * (radius + reach + 0.2))
	var inner: DummyZombie = _zombie(Vector3(cos(gap), 0.0, sin(gap)) * (radius - reach - 0.2))
	_effects.call("tick", step)
	_check(post.hits.is_empty(), "In der Lücke zwischen zwei Kugeln trifft zunächst keine.")
	for i: int in ceili(TAU / Balance.DISCO_ORBIT_SPEED / step):
		_effects.call("tick", step)
	_check(post.count("disco") == 3 and _near(post.total("disco"), sum, 0.001),
		"Ein Umlauf mit drei Kugeln: drei Treffer, jede mit dem Schaden ihrer Stufe (zusammen %s), waren %d mit %s." % [sum, post.count("disco"), post.total("disco")])
	_check(outer.hits.is_empty() and inner.hits.is_empty(), "Zombies neben dem Kreis (außen und innen) bleiben unberührt.")
	# Ein toter Spieler: Die Kugeln machen keinen Schaden mehr.
	_player.is_dead = true
	for i: int in ceili(TAU / Balance.DISCO_ORBIT_SPEED / step):
		_effects.call("tick", step)
	_check(post.count("disco") == 3, "Mit totem Spieler treffen die Kugeln niemanden.")
	_player.is_dead = false
	_fresh_run()


# --- Störsender ---

func _test_jammer() -> void:
	var interval: float = Balance.JAMMER_INTERVAL
	var step: float = 1.0 / 60.0
	# Ohne den Gegenstand passiert nichts.
	_fresh_run()
	var idle: DummyZombie = _zombie(Vector3(1.0, 0.0, 0.0))
	_effects.call("tick", interval * 3.0)
	_check(idle.hits.is_empty() and _near(_jammer_left(), interval), "Ohne Störsender gibt es keinen Elektroschlag.")

	# Zwei Exemplare (Gewöhnlich 30 und 4 m, Selten 60 und 5 m): 90 Schaden im Umkreis von 5 m.
	_fresh_run()
	var jammer_a: int = _auto("jammer", 1)
	_auto("jammer", 3)
	_sync()
	var radius: float = UpgradeDefs.value("jammer", "radius", 3)
	var damage: float = UpgradeDefs.value("jammer", "damage", 1) + UpgradeDefs.value("jammer", "damage", 3)
	_check(_near(float(_upgrades().call("value", "jammer", "radius")), radius) and _near(float(_upgrades().call("value", "jammer", "damage")), damage),
		"Zwei Störsender: der größere Radius (%s m), der Schaden addiert sich (%s)." % [radius, damage])
	_player.position = Vector3(2.0, 0.0, -3.0)
	var center: Vector3 = _player.position
	var inside: DummyZombie = _zombie(center + Vector3(radius - 0.1, 0.0, 0.0))
	var near: DummyZombie = _zombie(center + Vector3(0.0, 0.0, -1.0))
	var outside: DummyZombie = _zombie(center + Vector3(radius + 0.1, 0.0, 0.0))
	_check(_near(_jammer_left(), interval), "Ein neuer Lauf beginnt mit dem vollen Abstand von %s s." % interval)
	_effects.call("tick", interval - 0.1)
	_check(inside.hits.is_empty() and near.hits.is_empty() and _near(_jammer_left(), 0.1), "Vor Ablauf des Abstands schlägt der Störsender nicht zu.")
	_effects.call("tick", 0.2)
	_check(inside.count("jammer") == 1 and near.count("jammer") == 1 and _near(inside.total("jammer"), damage) and _near(near.total("jammer"), damage),
		"Nach %s s: %s Schaden an jedem Zombie im Umkreis (Welle 0, Faktor 1), waren %s." % [interval, damage, inside.total("jammer")])
	_check(inside.hits.size() == 1 and inside.burn_calls == 0 and inside.poison_calls == 0, "Der Schlag trägt source jammer und löst keinen Kugel-Effekt aus.")
	_check(outside.hits.is_empty(), "Außerhalb von %s m passiert nichts." % radius)
	_check(_near(_jammer_left(), interval), "Nach dem Schlag beginnt der Abstand neu.")
	_check(_fx_has("Lightning") and _fx_has("Ring"), "Der Schlag ist zu sehen: Blitze und ein Ring.")
	# In kleinen Schritten: genau nach dem Abstand der nächste Schlag.
	var steps: int = roundi(interval / step)
	for i: int in steps - 1:
		_effects.call("tick", step)
	_check(inside.count("jammer") == 1, "Einen Schritt vor Ablauf ist der nächste Schlag noch nicht da.")
	_effects.call("tick", step)
	_check(inside.count("jammer") == 2 and near.count("jammer") == 2 and outside.hits.is_empty(), "Genau nach %s s kommt der nächste Schlag." % interval)

	# Niemand im Umkreis: Der Schlag verfällt nicht, er wartet.
	inside.position = center + Vector3(radius + 3.0, 0.0, 0.0)
	near.position = center + Vector3(0.0, 0.0, -radius - 3.0)
	_effects.call("tick", interval + 1.0)
	_check(inside.count("jammer") == 2 and near.count("jammer") == 2 and outside.hits.is_empty(), "Ohne Zombie im Umkreis schlägt der Störsender nicht zu.")
	_check(_near(_jammer_left(), 0.0), "Der Schlag ist fällig und wartet.")
	_effects.call("tick", 2.0)
	_check(inside.count("jammer") == 2 and _near(_jammer_left(), 0.0), "Er wartet, solange niemand kommt.")
	inside.position = center + Vector3(0.0, 0.0, radius - 0.2)
	_effects.call("tick", step)
	_check(inside.count("jammer") == 3 and near.count("jammer") == 2, "Sobald ein Zombie in den Umkreis kommt, löst der wartende Schlag aus.")
	_check(_near(_jammer_left(), interval), "Danach beginnt der Abstand neu.")
	_effects.call("tick", step)
	_check(inside.count("jammer") == 3, "Der wartende Schlag löst nur einmal aus.")

	# Pause: Die Uhr steht.
	_effects.call("tick", 1.0)
	var left_before: float = _jammer_left()
	_game.call("set_paused", true)
	_effects.call("tick", interval * 2.0)
	_check(inside.count("jammer") == 3 and _near(_jammer_left(), left_before), "In der Pause läuft die Uhr des Störsenders nicht und er schlägt nicht zu.")
	_game.call("set_paused", false)
	_effects.call("tick", left_before + 0.01)
	_check(inside.count("jammer") == 4, "Nach der Pause läuft die Uhr weiter.")

	# Effekt-Faktor: Der feste Schaden wächst mit der Welle.
	_game.set("wave", 10)
	var factor: float = WavePlan.effect_factor(10)
	_effects.call("tick", interval)
	_check(inside.count("jammer") == 5 and factor > 1.0 and _near(float(inside.hits[inside.hits.size() - 1]["amount"]), damage * factor, 0.01),
		"In Welle 10 ist der Schaden des Störsenders mal %s." % factor)
	_game.set("wave", 0)
	# Ein toter Spieler sendet nicht. Lebt er wieder, kommt der wartende Schlag.
	_player.is_dead = true
	_effects.call("tick", interval + 0.1)
	_check(inside.count("jammer") == 5, "Ein toter Spieler löst keinen Elektroschlag aus.")
	_player.is_dead = false
	_effects.call("tick", step)
	_check(inside.count("jammer") == 6, "Der Schlag hat gewartet.")
	# Ein Opfer reißt ein anderes mitten im Schlag aus dem Baum: kein Absturz, der Rest wird getroffen.
	var weak: DummyZombie = _zombie(center + Vector3(1.0, 0.0, 0.0), 10.0)
	var ghost: DummyZombie = _zombie(center + Vector3(1.5, 0.0, 0.0))
	var rest: DummyZombie = _zombie(center + Vector3(2.0, 0.0, 0.0))
	weak.vanishes_with_me = ghost
	_effects.call("tick", interval)
	_check(weak.is_dead and not is_instance_valid(ghost) and rest.count("jammer") == 1 and inside.count("jammer") == 7,
		"Der Störsender übersteht einen verschwindenden Zombie.")

	# Ein Exemplar in der Ablage: Es zählt nur noch das andere.
	_backpack().call("store", jammer_a)
	_sync()
	_effects.call("tick", interval)
	_check(_near(float(rest.hits[rest.hits.size() - 1]["amount"]), UpgradeDefs.value("jammer", "damage", 3)), "Mit einem Störsender in der Ablage schlägt nur noch der andere zu.")
	# Ein neuer Lauf setzt die Uhr zurück.
	_effects.call("tick", 1.5)
	_check(_near(_jammer_left(), interval - 1.5), "Die Uhr läuft (noch %s s)." % _jammer_left())
	_events.emit_signal("run_started")
	_check(_near(_jammer_left(), interval), "Ein neuer Lauf setzt die Uhr des Störsenders zurück.")
	# Fällig und wartend, dann neuer Lauf: Auch dann beginnt der Abstand neu.
	inside.position = center + Vector3(radius + 3.0, 0.0, 0.0)
	rest.position = center + Vector3(radius + 3.0, 0.0, 2.0)
	_effects.call("tick", interval + 1.0)
	_check(_near(_jammer_left(), 0.0), "Der Schlag wartet wieder.")
	_fresh_run()
	_check(_near(_jammer_left(), interval), "Auch ein wartender Schlag ist mit dem neuen Lauf vergessen.")


# --- Hilfen für Abschnitt 22 (Kameras, neue Gegenstände) ---

## Vergrößert den Rucksack: Reisekoffer (6 Felder), Sporttasche (4) und zwei Jutebeutel (je 2).
## Neben den Start-Rucksack ohne Kandidat passt nur ein Reisekoffer.
func _bag() -> void:
	for id: String in ["bag_large", "bag_medium", "bag_small", "bag_small"]:
		var uid: int = int(_backpack().call("add_item", id, 1))
		_check(uid > 0 and bool(_backpack().call("auto_place", uid)), "Das Rucksack-Teil %s vergrößert den Rucksack." % id)


## Legt einen Stern-Gegenstand so in den Rucksack, dass seine Sterne genau auf den Gegenstand
## target_uid wirken (und auf keinen anderen). Probiert dafür alle Stellen und Drehungen durch.
## Danach _sync() rufen.
func _put_on(id: String, level: int, target_uid: int) -> int:
	var uid: int = int(_backpack().call("add_item", id, level))
	for rot: int in 4:
		for y: int in Balance.BACKPACK_ROWS:
			for x: int in Balance.BACKPACK_COLS:
				if not bool(_backpack().call("can_place", uid, Vector2i(x, y), rot)):
					continue
				_backpack().call("place", uid, Vector2i(x, y), rot)
				if _targets_are(uid, [target_uid]):
					_check(true, "")
					return uid
				_backpack().call("store", uid)
	_check(false, "%s (Rarität %d) lässt sich mit dem Stern auf den Gegenstand %d legen." % [id, level, target_uid])
	return uid


## Alle Kamera-Knoten (Drohnen zuerst), in der Reihenfolge ihrer Plätze.
func _all_cams() -> Array:
	return _effects.get("cameras") as Array


## Die Knoten eines Kameratyps.
func _cams(camera_id: String) -> Array:
	return _effects.call("camera_nodes", camera_id) as Array


## Der erste Knoten eines Kameratyps, null wenn es keinen gibt.
func _cam(camera_id: String) -> Node3D:
	var nodes: Array = _cams(camera_id)
	return nodes[0] as Node3D if not nodes.is_empty() else null


## Schreibt ein Signal mit (siehe _build_world).
func _note(signal_name: String, args: Array) -> void:
	if not _signal_log.has(signal_name):
		_signal_log[signal_name] = []
	(_signal_log[signal_name] as Array).append(args)


## Alle mitgeschriebenen Signale dieses Namens (je Signal die Liste seiner Argumente).
func _noted(signal_name: String) -> Array:
	return _signal_log.get(signal_name, []) as Array


## Wie oft sich dieser Kameratyp über camera_fired gemeldet hat.
func _fired(camera_id: String) -> int:
	var n: int = 0
	for args: Array in _noted("camera_fired"):
		if String(args[0]) == camera_id:
			n += 1
	return n


## Derselbe Punkt auf Bodenhöhe.
func _ground(at: Vector3) -> Vector3:
	return Vector3(at.x, 0.0, at.z)


## Versatz in der Waagerechten: degrees ist der Winkel zur Richtung -Z, positiv nach +X.
func _polar(degrees: float, distance: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(sin(angle) * distance, 0.0, -cos(angle) * distance)


## Wand auf Lage 1 (Welt). Mitte und Größe in Metern. Danach zwei Physik-Schritte warten.
func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TestWall"
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


## Echter Zombie eines Typs aus zombie.gd mit viel Leben (für Verlangsamung und Markierung).
func _real_zombie_of(type: String, at: Vector3) -> Node3D:
	var zombie: Node3D = (load(ZOMBIE_PATH) as GDScript).new()
	zombie.call("setup", type, 1)
	zombie.set("max_hp", HUGE_HP)
	zombie.set("hp", HUGE_HP)
	zombie.position = at
	_zombie_root.add_child(zombie)
	return zombie


## Stehen alle diese Knoten mindestens min_distance auseinander?
func _nodes_apart(nodes: Array, min_distance: float) -> bool:
	for i: int in nodes.size():
		for j: int in range(i + 1, nodes.size()):
			if (nodes[i] as Node3D).global_position.distance_to((nodes[j] as Node3D).global_position) < min_distance:
				return false
	return true


## Hat jeder Eintrag aus Game.cameras genau einen Knoten, der seine Werte liest, und steht jeder
## Knoten auf dem Platz seiner Stelle in der Liste?
func _cameras_match_entries() -> bool:
	var entries: Array = _game.get("cameras") as Array
	var nodes: Array = _all_cams()
	if entries.size() != nodes.size():
		return false
	var seen: Dictionary = {}
	for i: int in nodes.size():
		var node: Node3D = nodes[i] as Node3D
		if not is_instance_valid(node) or node.is_queued_for_deletion() or int(node.get("slot")) != i:
			return false
		var stats: Dictionary = node.get("stats")
		var key: String = String(stats.get("key", ""))
		if key.is_empty() or seen.has(key):
			return false
		# Derselbe Eintrag (nicht nur ein gleicher): Die Kamera liest aus Game.cameras.
		if not is_same(stats, _game.call("camera_entry", key)):
			return false
		seen[key] = true
	return true


## Letzter Treffer eines Ersatz-Zombies: sein Betrag.
func _last_amount(zombie: DummyZombie) -> float:
	return float(zombie.hits[zombie.hits.size() - 1]["amount"]) if not zombie.hits.is_empty() else 0.0


# --- Kameras: ein Knoten je Eintrag, Plätze ---

## Je Eintrag aus Game.cameras gibt es genau einen Knoten des passenden Typs. Alle teilen sich
## die Plätze um den Spieler (Drohnen zuerst) und lesen ihre Werte aus ihrem Eintrag.
func _test_camera_nodes() -> void:
	_fresh_run()
	_effects.call("tick", 0.016)
	_check(_all_cams().is_empty(), "Ohne Kamera im Rucksack gibt es keinen Kamera-Knoten.")
	_bag()
	var levels: Dictionary = {"drone": 4, "cam_tele": 2, "cam_flash": 3, "cam_slow": 1, "cam_director": 5}
	var uids: Dictionary = {}
	for id: String in CameraDefs.ORDER:
		uids[id] = _auto(id, int(levels[id]))
	_sync()
	var all: Array = _all_cams().duplicate()
	_check(all.size() == 5 and (_game.get("cameras") as Array).size() == 5, "Fünf Kameras im Rucksack: fünf Knoten, waren %d." % all.size())
	if all.size() != 5:
		return
	for i: int in CameraDefs.ORDER.size():
		var id: String = CameraDefs.ORDER[i]
		var level: int = int(levels[id])
		var nodes: Array = _cams(id)
		_check(nodes.size() == 1, "%s: genau ein Knoten, waren %d." % [id, nodes.size()])
		if nodes.size() != 1:
			continue
		var node: Node3D = nodes[0] as Node3D
		_check(all[i] == node and int(node.get("slot")) == i, "%s steht auf Platz %d (Drohnen zuerst, dann die Reihenfolge der Typen)." % [id, i])
		_check(node.get_parent() == _fx_root and int(node.get("level")) == level, "%s hängt im Effekt-Behälter und hat die Rarität %d." % [id, level])
		if id == "drone":
			_check(node.is_in_group("drones") and _effects.get("drone") == node, "Die Drohne ist weiter die Drohne.")
		else:
			_check(String(node.get("camera_id")) == id and node.is_in_group("cameras"), "%s kennt seinen Typ und steht in der Gruppe cameras." % id)
		_check(is_same(node.get("stats"), _game.call("camera_entry", "%d:0" % int(uids[id]))), "%s liest seinen Eintrag aus Game.cameras." % id)
		_check(_near(float(node.call("get_fire_interval")), CameraDefs.base(id, "interval", level))
			and _near(float(node.call("get_range")), CameraDefs.base(id, "range", level))
			and _near(float(node.call("get_shot_damage")), CameraDefs.base(id, "damage", level)),
			"%s: Takt, Reichweite und Schaden der Rarität %d." % [id, level])
	_check(_cameras_match_entries(), "Jeder Eintrag hat genau einen Knoten.")
	_check(_nodes_apart(all, 1.0), "Die fünf Kameras stehen an verschiedenen Stellen (nicht ineinander).")
	var heights_ok: bool = true
	for entry: Variant in all:
		if (entry as Node3D).global_position.y < Balance.DRONE_HOVER_HEIGHT - 0.3:
			heights_ok = false
	_check(heights_ok, "Alle Kameras schweben mindestens in Flughöhe.")
	# Ein Abgleich ohne Änderung lässt alles, wie es ist.
	_effects.call("tick", 0.016)
	_events.emit_signal("upgrade_chosen", "cam_tele", 2)
	_check(_all_cams() == all, "Ein Abgleich ohne Änderung behält alle Knoten.")

	# Eine zweite Kamera desselben Typs: ein Knoten mehr, die Plätze dahinter rücken.
	var director: Node3D = _cam("cam_director")
	var first_slow: Node3D = _cam("cam_slow")
	_auto("cam_slow", 4)
	_sync()
	var slows: Array = _cams("cam_slow")
	_check(_all_cams().size() == 6 and slows.size() == 2 and slows[0] == first_slow and int((slows[1] as Node3D).get("level")) == 4,
		"Eine zweite Zeitlupen-Kamera: ein zweiter Knoten der Rarität 4, der erste bleibt.")
	_check(_cam("cam_director") == director and int(director.get("slot")) == 5, "Die Regie-Kamera rückt einen Platz weiter.")
	_check(_cameras_match_entries(), "Sechs Kameras: sechs Einträge, sechs Plätze.")
	# Die verdrängte Kamera gleitet an ihren neuen Platz: Kurz darauf steht wieder jede für sich.
	await create_timer(1.2).timeout
	_check(_nodes_apart(_all_cams(), 1.0), "Nach dem Aufrücken stehen die sechs Kameras wieder an verschiedenen Stellen.")

	# Kamera-Gegenstände: Die Knoten lesen die neuen fertigen Werte, ohne neu zu entstehen.
	var tele: Node3D = _cam("cam_tele")
	_put_on("cam_lens", 1, int(uids["cam_tele"]))
	_sync()
	var lens: float = UpgradeDefs.value("cam_lens", "bonus", 1)
	_check(_cam("cam_tele") == tele and _near(float(tele.call("get_shot_damage")), CameraDefs.base("cam_tele", "damage", 2) * (1.0 + lens), 0.01),
		"Objektiv auf der Tele-Kamera: derselbe Knoten macht %d %% mehr Schaden." % roundi(lens * 100.0))
	_auto("cam_uplink", 2)
	_sync()
	var uplink: float = UpgradeDefs.value("cam_uplink", "bonus", 2)
	var drone: Node3D = _effects.get("drone") as Node3D
	_check(_near(float(drone.call("get_shot_damage")), CameraDefs.base("drone", "damage", 4) * (1.0 + uplink), 0.01)
		and _near(float(drone.call("get_fire_interval")), CameraDefs.base("drone", "interval", 4) / (1.0 + uplink)),
		"Sendeleitung: Die Drohne schießt stärker und schneller.")
	_check(_near(float(tele.call("get_shot_damage")), CameraDefs.base("cam_tele", "damage", 2) * (1.0 + lens + uplink), 0.01)
		and _near(float(director.call("get_fire_interval")), CameraDefs.base("cam_director", "interval", 5) / (1.0 + uplink)),
		"Sendeleitung: Sie wirkt auf alle Kameras (Tele mit Objektiv, Regie im Takt).")
	_check(_cameras_match_entries(), "Nach den Kamera-Gegenständen hat weiter jeder Eintrag seinen Knoten.")

	# Eine Kamera in die Ablage: ihr Knoten verschwindet, die anderen rücken auf.
	_backpack().call("store", int(uids["cam_tele"]))
	_sync()
	_check(tele.is_queued_for_deletion() and _cams("cam_tele").is_empty() and _all_cams().size() == 5,
		"In der Ablage wirkt die Tele-Kamera nicht: Ihr Knoten verschwindet.")
	_check(_cam("cam_director") == director and int(director.get("slot")) == 4 and _cameras_match_entries(), "Die anderen Kameras bleiben und rücken auf.")

	# Wiederholung auf einer Kamera: ein zweites Exemplar mit eigenem Eintrag.
	var flash: Node3D = _cam("cam_flash")
	_put_on("replay", 3, int(uids["cam_flash"]))
	_sync()
	var flashes: Array = _cams("cam_flash")
	_check(flashes.size() == 2 and flashes[0] == flash, "Wiederholung auf der Blitzlicht-Kamera: ein zweiter Knoten.")
	if flashes.size() == 2:
		var keys: Array = [String(((flashes[0] as Node3D).get("stats") as Dictionary)["key"]), String(((flashes[1] as Node3D).get("stats") as Dictionary)["key"])]
		keys.sort()
		_check(keys == ["%d:0" % int(uids["cam_flash"]), "%d:1" % int(uids["cam_flash"])], "Beide Exemplare haben ihren eigenen Eintrag, waren %s." % [keys])
	_check(_cameras_match_entries(), "Mit der Wiederholung hat weiter jeder Eintrag genau einen Knoten.")

	# Neuer Lauf mit denselben Gegenständen: alle Knoten neu. Leerer Rucksack: keine Kamera.
	var before: Array = _all_cams().duplicate()
	_events.emit_signal("run_started")
	var rebuilt: Array = _all_cams()
	var kept_any: bool = false
	for entry: Variant in before:
		if rebuilt.has(entry) or not (entry as Node3D).is_queued_for_deletion():
			kept_any = true
	_check(rebuilt.size() == before.size() and not kept_any and _cameras_match_entries(), "Lauf-Beginn: Die alten Kameras gehen, neue kommen.")
	_fresh_run()
	_check(_all_cams().is_empty() and _cams("cam_flash").is_empty(), "Ein neuer Lauf ohne Kamera hat keinen Kamera-Knoten.")
	await process_frame
	await process_frame
	_check(get_nodes_in_group("cameras").is_empty() and get_nodes_in_group("drones").is_empty(), "Alle Kameras des alten Laufs sind aus dem Baum verschwunden.")


# --- Tele-Kamera ---

func _test_cam_tele() -> void:
	for level: int in [1, 5]:
		_fresh_run()
		_auto("cam_tele", level)
		_sync()
		_give("burn", 5)
		_give("chain_lightning", 5)
		var cam: Node3D = _cam("cam_tele")
		_check(cam != null, "Tele-Kamera Rarität %d: Der Knoten ist da." % level)
		if cam == null:
			continue
		var damage: float = CameraDefs.base("cam_tele", "damage", level)
		var pierce: int = int(CameraDefs.base("cam_tele", "pierce", level))
		var reach: float = CameraDefs.base("cam_tele", "range", level)
		_check(not bool(cam.call("try_fire")), "Tele-Kamera Rarität %d: Ohne Ziel fällt kein Schuss." % level)
		var at: Vector3 = _ground(cam.global_position)
		# Fünf Zombies in einer Linie von der Kamera weg, einer daneben, einer außer Reichweite.
		var line: Array[DummyZombie] = []
		for i: int in 5:
			line.append(_zombie(at + Vector3(0.0, 0.0, -5.0 - 3.0 * float(i))))
		var beside: DummyZombie = _zombie(at + Vector3(2.5, 0.0, -8.0))
		var far: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -reach - 2.0))
		var fired_before: int = _fired("cam_tele")
		_check(cam.call("find_target") == line[0], "Tele-Kamera Rarität %d: Sie zielt auf den nächsten Zombie." % level)
		_check(bool(cam.call("try_fire")), "Tele-Kamera Rarität %d: Sie schießt." % level)
		var line_ok: bool = true
		for i: int in line.size():
			var want: int = 1 if i <= pierce else 0
			if line[i].count("cam_tele") != want or line[i].hits.size() != want or (want == 1 and not _near(line[i].total("cam_tele"), damage)):
				line_ok = false
		_check(line_ok, "Tele-Kamera Rarität %d: %s Schaden (source cam_tele) am Ziel und an %d weiteren in der Linie, nicht mehr." % [level, damage, pierce])
		_check(beside.hits.is_empty() and far.hits.is_empty(), "Tele-Kamera Rarität %d: Neben der Linie und außerhalb von %s m trifft sie nicht." % [level, reach])
		_check(line[0].burn_calls == 0 and line[1].burn_calls == 0, "Der Schaden der Tele-Kamera löst keinen Kugel-Effekt aus.")
		_check(_fired("cam_tele") == fired_before + 1, "Tele-Kamera: camera_fired kommt genau einmal je Schuss.")
		var last_fired: Array = _noted("camera_fired")[_noted("camera_fired").size() - 1]
		_check((last_fired[1] as Vector3).distance_to(cam.global_position) < 0.01, "camera_fired nennt den Ort der Kamera.")
		_check(_fx_has("Beam"), "Der Schuss ist als Strahl zu sehen.")
		# Feste Werte: Der Effekt-Faktor der Welle ändert nichts.
		_game.set("wave", 10)
		cam.call("try_fire")
		_check(_near(_last_amount(line[0]), damage, 0.01), "Tele-Kamera Rarität %d: Auch in Welle 10 bleibt es beim festen Schaden." % level)
		_game.set("wave", 0)
		# Von selbst im Takt.
		var shots_before: int = line[0].count("cam_tele")
		var frames: int = 0
		while line[0].count("cam_tele") == shots_before and frames < 300:
			await physics_frame
			frames += 1
		_check(line[0].count("cam_tele") > shots_before, "Tele-Kamera Rarität %d: Sie schießt von selbst." % level)
		_check(float(cam.call("get_cooldown_left")) > CameraDefs.base("cam_tele", "interval", level) - 0.3, "Nach dem Schuss wartet sie ihren Takt ab.")

	# Zweitkamera: ein zweiter Schuss mit dem Anteil auf ein anderes Ziel, auch er mit Durchschlag.
	_fresh_run()
	_bag()
	var tele_uid: int = _auto("cam_tele", 1)
	_put_on("cam_second", 2, tele_uid)
	_sync()
	var second_cam: Node3D = _cam("cam_tele")
	var share: float = UpgradeDefs.value("cam_second", "share", 2)
	var base_damage: float = CameraDefs.base("cam_tele", "damage", 1)
	_check(second_cam != null and _near(float(second_cam.call("get_second_share")), share), "Zweitkamera auf der Tele-Kamera: Anteil %s." % share)
	if second_cam == null:
		return
	var spot: Vector3 = _ground(second_cam.global_position)
	var first: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -5.0))
	var behind: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -8.0))
	var third: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -11.0))
	var side: DummyZombie = _zombie(spot + Vector3(-6.0, 0.0, 0.0))
	var side_behind: DummyZombie = _zombie(spot + Vector3(-9.0, 0.0, 0.0))
	var fired: int = _fired("cam_tele")
	_check(bool(second_cam.call("try_fire")), "Tele-Kamera mit Zweitkamera schießt.")
	_check(first.count("cam_tele") == 1 and behind.count("cam_tele") == 1 and _near(first.total("cam_tele"), base_damage) and _near(behind.total("cam_tele"), base_damage),
		"Der erste Schuss trifft das Ziel und einen dahinter mit vollem Schaden.")
	_check(third.hits.is_empty(), "Gewöhnlich schlägt nur einmal durch.")
	_check(side.count("cam_tele") == 1 and side_behind.count("cam_tele") == 1 and _near(side.total("cam_tele"), base_damage * share) and _near(side_behind.total("cam_tele"), base_damage * share),
		"Der zweite Schuss trifft ein anderes Ziel und einen dahinter mit %d %% des Schadens, war %s." % [roundi(share * 100.0), side.total("cam_tele")])
	_check(_fired("cam_tele") == fired + 1, "Auch mit Zweitkamera kommt camera_fired einmal je Schuss.")
	# Eine Wand in der Linie hält den Schuss auf.
	side.free()
	side_behind.free()
	third.free()
	var wall: StaticBody3D = _wall(spot + Vector3(0.0, 1.5, -6.5), Vector3(4.0, 4.0, 0.3))
	await physics_frame
	await physics_frame
	var first_before: int = first.count("cam_tele")
	var behind_before: int = behind.count("cam_tele")
	second_cam.call("try_fire")
	_check(first.count("cam_tele") == first_before + 1 and behind.count("cam_tele") == behind_before, "Hinter einer Wand trifft die Tele-Kamera nicht.")
	first.free()
	await physics_frame
	_check(second_cam.call("find_target") == null and not bool(second_cam.call("try_fire")), "Ohne Sichtlinie schießt die Tele-Kamera nicht.")
	wall.free()


# --- Blitzlicht-Kamera ---

func _test_cam_flash() -> void:
	var cone: float = CameraDefs.FLASH_CONE_DEG
	for level: int in [1, 5]:
		_fresh_run()
		_auto("cam_flash", level)
		_sync()
		var cam: Node3D = _cam("cam_flash")
		_check(cam != null, "Blitzlicht-Kamera Rarität %d: Der Knoten ist da." % level)
		if cam == null:
			continue
		var damage: float = CameraDefs.base("cam_flash", "damage", level)
		var reach: float = CameraDefs.base("cam_flash", "range", level)
		_check(_near(float(cam.call("get_value", "cone_deg")), cone) and _near(cone, 90.0), "Der Kegel hat 90 Grad.")
		_check(not bool(cam.call("try_fire")), "Blitzlicht-Kamera Rarität %d: Ohne Ziel blitzt sie nicht." % level)
		var at: Vector3 = _ground(cam.global_position)
		var ahead: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -4.0))
		var inside: DummyZombie = _zombie(at + _polar(cone * 0.5 - 5.0, 5.0))
		var outside: DummyZombie = _zombie(at + _polar(cone * 0.5 + 5.0, 5.0))
		var far_in: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -(reach - 0.6)))
		var far_out: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -(reach + 0.3)))
		var behind: DummyZombie = _zombie(at + Vector3(0.0, 0.0, 5.0))
		var fired_before: int = _fired("cam_flash")
		_check(bool(cam.call("try_fire")), "Blitzlicht-Kamera Rarität %d: Sie blitzt." % level)
		_check((cam.call("get_flash_direction") as Vector3).distance_to(Vector3.FORWARD) < 0.01, "Sie dreht sich zum nächsten Zombie.")
		var hit_ok: bool = true
		for zombie: DummyZombie in [ahead, inside, far_in]:
			if zombie.count("cam_flash") != 1 or zombie.hits.size() != 1 or not _near(zombie.total("cam_flash"), damage):
				hit_ok = false
		_check(hit_ok, "Blitzlicht-Kamera Rarität %d: %s Schaden (source cam_flash) an allen im Kegel bis %s m." % [level, damage, reach])
		_check(outside.hits.is_empty() and behind.hits.is_empty(), "Neben und hinter dem Kegel trifft der Blitz nicht.")
		_check(far_out.hits.is_empty(), "Außerhalb der Reichweite trifft der Blitz nicht.")
		_check(_fired("cam_flash") == fired_before + 1, "Blitzlicht-Kamera: camera_fired kommt einmal je Blitz.")
		_check(_fx_has("FlashWedge") and _fx_has("Burst"), "Der Blitz ist zu sehen: Fächer am Boden und Aufleuchten.")
		_check(is_zero_approx(float(cam.call("get_second_flash_left"))), "Ohne Zweitkamera wartet kein zweiter Blitz.")
		# Ein näherer Zombie seitlich: Der Kegel dreht sich mit.
		var close: DummyZombie = _zombie(at + Vector3(2.0, 0.0, 0.0))
		_game.set("wave", 10)
		cam.call("try_fire")
		_game.set("wave", 0)
		_check(close.count("cam_flash") == 1 and outside.count("cam_flash") == 1, "Der Blitz geht zum jetzt nächsten Zombie, der Kegel dreht sich mit.")
		_check(ahead.count("cam_flash") == 1 and inside.count("cam_flash") == 1, "Wer jetzt außerhalb des Kegels steht, bekommt nichts ab.")
		_check(_near(_last_amount(close), damage, 0.01), "Blitzlicht-Kamera Rarität %d: Auch in Welle 10 bleibt es beim festen Schaden." % level)

	# Zweitkamera: zweiter Blitz nach CameraDefs.SECOND_FLASH_DELAY mit dem Anteil. Die Kamera
	# blitzt hier von selbst (ihr Takt beginnt sofort), der Test misst die Physik-Schritte dazwischen.
	_fresh_run()
	_bag()
	var flash_uid: int = _auto("cam_flash", 2)
	_put_on("cam_second", 3, flash_uid)
	_sync()
	var second_cam: Node3D = _cam("cam_flash")
	var share: float = UpgradeDefs.value("cam_second", "share", 3)
	var base_damage: float = CameraDefs.base("cam_flash", "damage", 2)
	_check(second_cam != null and _near(float(second_cam.call("get_second_share")), share), "Zweitkamera auf der Blitzlicht-Kamera: Anteil %s." % share)
	if second_cam == null:
		return
	var target: DummyZombie = _zombie(_ground(second_cam.global_position) + Vector3(0.0, 0.0, -4.0))
	var fired: int = _fired("cam_flash")
	var frames: int = 0
	while target.count("cam_flash") == 0 and frames < 120:
		await physics_frame
		frames += 1
	_check(target.count("cam_flash") == 1 and _near(target.total("cam_flash"), base_damage), "Der erste Blitz macht den vollen Schaden.")
	_check(float(second_cam.call("get_second_flash_left")) > 0.0, "Der zweite Blitz ist vorgemerkt.")
	var ticks: int = 0
	while target.count("cam_flash") < 2 and ticks < 120:
		await physics_frame
		ticks += 1
	var waited: float = float(ticks) / float(Engine.physics_ticks_per_second)
	_check(target.count("cam_flash") == 2 and _near(_last_amount(target), base_damage * share, 0.01),
		"Der zweite Blitz macht %d %% des Schadens, war %s." % [roundi(share * 100.0), _last_amount(target)])
	_check(absf(waited - CameraDefs.SECOND_FLASH_DELAY) <= 0.05, "Der zweite Blitz kommt nach %s s, waren %s s." % [CameraDefs.SECOND_FLASH_DELAY, waited])
	_check(_fired("cam_flash") == fired + 2, "Jeder der beiden Blitze meldet sich über camera_fired.")
	for i: int in 30:
		await physics_frame
	_check(target.count("cam_flash") == 2, "Danach wartet die Kamera ihren Takt ab.")


# --- Zeitlupen-Kamera ---

func _test_cam_slow() -> void:
	for level: int in [1, 5]:
		_fresh_run()
		_auto("cam_slow", level)
		_sync()
		var cam: Node3D = _cam("cam_slow")
		_check(cam != null, "Zeitlupen-Kamera Rarität %d: Der Knoten ist da." % level)
		if cam == null:
			continue
		var damage: float = CameraDefs.base("cam_slow", "damage", level)
		var slow: float = CameraDefs.base("cam_slow", "slow", level)
		var reach: float = CameraDefs.base("cam_slow", "range", level)
		_check(not bool(cam.call("try_fire")), "Zeitlupen-Kamera Rarität %d: Ohne Ziel fällt kein Schuss." % level)
		var at: Vector3 = _ground(cam.global_position)
		var near: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -4.0))
		var mid: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -8.0))
		var far: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -reach - 1.0))
		var fired_before: int = _fired("cam_slow")
		_check(bool(cam.call("try_fire")), "Zeitlupen-Kamera Rarität %d: Sie schießt." % level)
		_check(near.count("cam_slow") == 1 and near.hits.size() == 1 and _near(near.total("cam_slow"), damage),
			"Zeitlupen-Kamera Rarität %d: %s Schaden (source cam_slow) am nächsten Zombie." % [level, damage])
		_check(near.slow_calls == 1 and _near(near.slow_factor, slow) and _near(near.slow_duration, CameraDefs.SLOW_DURATION),
			"Zeitlupen-Kamera Rarität %d: Er ist %s s lang %d %% langsamer." % [level, CameraDefs.SLOW_DURATION, roundi(slow * 100.0)])
		_check(mid.hits.is_empty() and mid.slow_calls == 0 and far.hits.is_empty(), "Nur ein Ziel wird getroffen, außer Reichweite keines.")
		_check(_fired("cam_slow") == fired_before + 1 and _fx_has("Beam"), "Der Schuss meldet sich über camera_fired und ist zu sehen.")
		# Der nächste Schuss geht auf einen Zombie, der noch nicht verlangsamt ist.
		_game.set("wave", 10)
		cam.call("try_fire")
		_game.set("wave", 0)
		_check(mid.count("cam_slow") == 1 and mid.slow_calls == 1 and near.count("cam_slow") == 1, "Zuerst kommen Zombies dran, die noch nicht verlangsamt sind.")
		_check(_near(mid.total("cam_slow"), damage, 0.01), "Zeitlupen-Kamera Rarität %d: Auch in Welle 10 bleibt es beim festen Schaden." % level)
		cam.call("try_fire")
		_check(near.count("cam_slow") == 2 and near.slow_calls == 2, "Sind alle verlangsamt, trifft sie wieder den nächsten.")
		# Ein tödlicher Schuss verlangsamt niemanden mehr.
		near.free()
		mid.free()
		var weak: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -3.0), damage * 0.5)
		cam.call("try_fire")
		_check(weak.is_dead and weak.slow_calls == 0, "Tote werden nicht verlangsamt.")
		weak.free()
		# Am echten Zombie: Er läuft wirklich langsamer, Elite nur halb so stark.
		var walker: Node3D = _real_zombie_of("walker", at + Vector3(0.0, 0.0, -4.0))
		cam.call("try_fire")
		_check(bool(walker.call("is_slowed")) and _near(float(walker.call("get_speed_factor")), 1.0 - slow), "Echter Zombie: Lauftempo mal %s." % (1.0 - slow))
		walker.free()
		var elite: Node3D = _real_zombie_of("elite", at + Vector3(0.0, 0.0, -4.0))
		cam.call("try_fire")
		_check(_near(float(elite.call("get_speed_factor")), 1.0 - slow * Balance.SLOW_ELITE_FACTOR), "Elite: nur die halbe Verlangsamung.")

	# Zweitkamera: ein zweites Ziel mit dem Anteil an Schaden und Verlangsamung.
	_fresh_run()
	_bag()
	var slow_uid: int = _auto("cam_slow", 3)
	_put_on("cam_second", 1, slow_uid)
	_sync()
	var second_cam: Node3D = _cam("cam_slow")
	var share: float = UpgradeDefs.value("cam_second", "share", 1)
	if second_cam == null:
		_check(false, "Zeitlupen-Kamera mit Zweitkamera: Der Knoten ist da.")
		return
	var spot: Vector3 = _ground(second_cam.global_position)
	var first: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -4.0))
	var second: DummyZombie = _zombie(spot + Vector3(3.0, 0.0, -6.0))
	var third: DummyZombie = _zombie(spot + Vector3(-3.0, 0.0, -9.0))
	var fired: int = _fired("cam_slow")
	second_cam.call("try_fire")
	var want_damage: float = CameraDefs.base("cam_slow", "damage", 3)
	var want_slow: float = CameraDefs.base("cam_slow", "slow", 3)
	_check(_near(first.total("cam_slow"), want_damage) and _near(first.slow_factor, want_slow), "Das erste Ziel bekommt die volle Wirkung.")
	_check(second.count("cam_slow") == 1 and _near(second.total("cam_slow"), want_damage * share) and _near(second.slow_factor, want_slow * share)
		and _near(second.slow_duration, CameraDefs.SLOW_DURATION),
		"Das zweite Ziel bekommt %d %% von Schaden und Verlangsamung, waren %s und %s." % [roundi(share * 100.0), second.total("cam_slow"), second.slow_factor])
	_check(third.hits.is_empty() and _fired("cam_slow") == fired + 1, "Ein drittes Ziel gibt es nicht, camera_fired kommt einmal.")


# --- Regie-Kamera ---

func _test_cam_director() -> void:
	for level: int in [1, 5]:
		_fresh_run()
		_auto("cam_director", level)
		_sync()
		var cam: Node3D = _cam("cam_director")
		_check(cam != null, "Regie-Kamera Rarität %d: Der Knoten ist da." % level)
		if cam == null:
			continue
		var mark: float = CameraDefs.base("cam_director", "mark", level)
		var reach: float = CameraDefs.base("cam_director", "range", level)
		_check(is_zero_approx(float(cam.call("get_shot_damage"))), "Die Regie-Kamera macht keinen Schaden.")
		_check(not bool(cam.call("try_fire")), "Regie-Kamera Rarität %d: Ohne Ziel markiert sie nichts." % level)
		var at: Vector3 = _ground(cam.global_position)
		var walker: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -4.0))
		var other: DummyZombie = _zombie(at + Vector3(2.0, 0.0, -6.0))
		var elite: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -9.0), HUGE_HP, "elite")
		var far_elite: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -reach - 1.0), HUGE_HP, "elite")
		var fired_before: int = _fired("cam_director")
		_check(bool(cam.call("try_fire")), "Regie-Kamera Rarität %d: Sie markiert." % level)
		_check(elite.mark_calls == 1 and _near(elite.mark_bonus, mark) and _near(elite.mark_duration, CameraDefs.MARK_DURATION),
			"Regie-Kamera Rarität %d: zuerst die Elite, %s s lang %d %% mehr Schaden." % [level, CameraDefs.MARK_DURATION, roundi(mark * 100.0)])
		_check(walker.mark_calls == 0 and other.mark_calls == 0 and far_elite.mark_calls == 0, "Nur ein Zombie wird markiert, außer Reichweite keiner.")
		_check(_fired("cam_director") == fired_before + 1 and _fx_has("Beam"), "Die Markierung meldet sich über camera_fired und ist als Strahl zu sehen.")
		cam.call("try_fire")
		_check(walker.mark_calls == 1 and elite.mark_calls == 1, "Danach kommt der nächste unmarkierte Zombie dran.")
		cam.call("try_fire")
		_check(other.mark_calls == 1 and walker.mark_calls == 1 and elite.mark_calls == 1, "Und dann der andere unmarkierte.")
		cam.call("try_fire")
		_check(elite.mark_calls == 2 and walker.mark_calls == 1, "Sind alle markiert, erneuert sie zuerst die Elite.")
		_check(walker.hits.is_empty() and other.hits.is_empty() and elite.hits.is_empty(), "Kein Zombie nimmt Schaden von der Regie-Kamera.")
		# Am echten Zombie: Markierte nehmen aus jeder Quelle mehr Schaden.
		walker.free()
		other.free()
		elite.free()
		far_elite.free()
		var real: Node3D = _real_zombie_of("walker", at + Vector3(0.0, 0.0, -4.0))
		cam.call("try_fire")
		_start_log()
		real.call("take_damage", 100.0, {"source": "bullet"})
		_check(bool(real.call("is_marked")) and _near(_logged(real, "bullet"), 100.0 * (1.0 + mark), 0.01),
			"Echter Zombie: 100 Schaden werden zu %s." % (100.0 * (1.0 + mark)))
		_stop_log()

	# Im Takt (Schritte von Hand): Die gewöhnliche Regie-Kamera hält eine Elite dauerhaft markiert,
	# denn ihre Markierung (4 s) liefe vor dem nächsten Auslösen (3 s später) ab.
	_fresh_run()
	_auto("cam_director", 1)
	_sync()
	var slow_cam: Node3D = _cam("cam_director")
	if slow_cam != null:
		var spot: Vector3 = _ground(slow_cam.global_position)
		var near: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -4.0))
		var boss: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -9.0), HUGE_HP, "elite")
		for i: int in 65:
			slow_cam.call("_physics_process", 0.1)
		_check(boss.mark_calls == 3 and near.mark_calls == 0, "In 6,5 s markiert sie die Elite dreimal und sonst niemanden, waren %d und %d." % [boss.mark_calls, near.mark_calls])
	# Die legendäre löst öfter aus (alle 1,8 s): Zwischen zwei Markierungen der Elite ist ein anderer dran.
	_fresh_run()
	_auto("cam_director", 5)
	_sync()
	var fast_cam: Node3D = _cam("cam_director")
	if fast_cam != null:
		var spot: Vector3 = _ground(fast_cam.global_position)
		var near: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -4.0))
		var boss: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -9.0), HUGE_HP, "elite")
		for i: int in 60:
			fast_cam.call("_physics_process", 0.1)
		_check(boss.mark_calls == 2 and near.mark_calls == 2, "Legendär in 6 s: Elite und Schlurfer abwechselnd, je zweimal, waren %d und %d." % [boss.mark_calls, near.mark_calls])

	# Zweitkamera: Ein zweiter Zombie wird markiert, mit dem Anteil am Mehr-Schaden.
	_fresh_run()
	_bag()
	var director_uid: int = _auto("cam_director", 3)
	_put_on("cam_second", 2, director_uid)
	_sync()
	var second_cam: Node3D = _cam("cam_director")
	var share: float = UpgradeDefs.value("cam_second", "share", 2)
	if second_cam == null:
		_check(false, "Regie-Kamera mit Zweitkamera: Der Knoten ist da.")
		return
	var place: Vector3 = _ground(second_cam.global_position)
	var first: DummyZombie = _zombie(place + Vector3(0.0, 0.0, -4.0))
	var second: DummyZombie = _zombie(place + Vector3(0.0, 0.0, -7.0))
	var chief: DummyZombie = _zombie(place + Vector3(3.0, 0.0, -9.0), HUGE_HP, "elite")
	var fired: int = _fired("cam_director")
	second_cam.call("try_fire")
	var want: float = CameraDefs.base("cam_director", "mark", 3)
	_check(chief.mark_calls == 1 and _near(chief.mark_bonus, want), "Die Elite bekommt die volle Markierung.")
	_check(first.mark_calls == 1 and _near(first.mark_bonus, want * share) and _near(first.mark_duration, CameraDefs.MARK_DURATION),
		"Ein zweiter Zombie wird mit %d %% des Mehr-Schadens markiert, war %s." % [roundi(share * 100.0), first.mark_bonus])
	_check(second.mark_calls == 0 and _fired("cam_director") == fired + 1, "Ein dritter wird nicht markiert, camera_fired kommt einmal.")


# --- Kameradrohne mit Zweitkamera ---

func _test_drone_second() -> void:
	_fresh_run()
	_bag()
	var drone_uid: int = _auto("drone", 3)
	_put_on("cam_second", 2, drone_uid)
	_sync()
	var drone: Node3D = _effects.get("drone") as Node3D
	var share: float = UpgradeDefs.value("cam_second", "share", 2)
	var damage: float = CameraDefs.base("drone", "damage", 3)
	_check(is_instance_valid(drone) and _near(float(drone.call("get_second_share")), share), "Zweitkamera auf der Drohne: Anteil %s." % share)
	if not is_instance_valid(drone):
		return
	var at: Vector3 = _ground(drone.global_position)
	var only: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -5.0))
	var fired: int = _fired("drone")
	_check(bool(drone.call("try_fire")) and only.count("drone") == 1 and _near(only.total("drone"), damage), "Mit nur einem Ziel gibt es nur einen Treffer.")
	_check(_fired("drone") == fired + 1, "Die Drohne meldet sich über camera_fired.")
	var second: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -9.0))
	var third: DummyZombie = _zombie(at + Vector3(0.0, 0.0, -12.0))
	drone.call("try_fire")
	_check(only.count("drone") == 2 and _near(_last_amount(only), damage), "Das erste Ziel bekommt den vollen Schaden.")
	_check(second.count("drone") == 1 and _near(second.total("drone"), damage * share),
		"Das zweite Ziel bekommt %d %% des Schadens, war %s." % [roundi(share * 100.0), second.total("drone")])
	_check(third.hits.is_empty() and _fired("drone") == fired + 2, "Ein drittes Ziel gibt es nicht, camera_fired kommt einmal je Schuss.")
	_check(drone.call("get_claimed_target") == only, "Beansprucht ist nur das erste Ziel.")
	# Ohne Zweitkamera bleibt es bei einem Ziel.
	_fresh_run()
	_auto("drone", 3)
	_sync()
	var plain: Node3D = _effects.get("drone") as Node3D
	var spot: Vector3 = _ground(plain.global_position)
	var a: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -5.0))
	var b: DummyZombie = _zombie(spot + Vector3(0.0, 0.0, -9.0))
	plain.call("try_fire")
	_check(a.count("drone") == 1 and b.hits.is_empty() and is_zero_approx(float(plain.call("get_second_share"))), "Ohne Zweitkamera trifft die Drohne nur ein Ziel.")


# --- Trockeneis ---

func _test_frost() -> void:
	var pistols: Array[int] = _two_pistols()
	var left: int = pistols[0]
	var right: int = pistols[1]
	_put_on("frost", 2, left)
	_sync()
	var slow: float = UpgradeDefs.value("frost", "slow", 2)
	_check(_bullet_level(left, "frost") == 2 and _bullet_level(right, "frost") == 0, "Trockeneis wirkt nur für die linke Pistole.")
	var target: DummyZombie = _zombie(Vector3(0.0, 0.0, -5.0))
	_weapon_shot(target, 10.0, right)
	_shot(target, 10.0)
	_check(target.slow_calls == 0, "Treffer der rechten Pistole und Treffer ohne Waffe verlangsamen nicht.")
	_weapon_shot(target, 10.0, left)
	_check(target.slow_calls == 1 and _near(target.slow_factor, slow) and _near(target.slow_duration, Balance.FROST_DURATION),
		"Trockeneis: Ein Treffer der linken Pistole macht %d %% langsamer für %s s." % [roundi(slow * 100.0), Balance.FROST_DURATION])
	var victim: DummyZombie = _zombie(Vector3(3.0, 0.0, -5.0), 5.0)
	_weapon_shot(victim, 10.0, left)
	_check(victim.is_dead and victim.slow_calls == 0, "Trockeneis: Tote werden nicht verlangsamt.")
	# Am echten Zombie, Elite mit halber Wirkung.
	var walker: Node3D = _real_zombie_of("walker", Vector3(0.0, 0.0, -8.0))
	var elite: Node3D = _real_zombie_of("elite", Vector3(3.0, 0.0, -8.0))
	_signal_hit(walker, left)
	_signal_hit(elite, left)
	_signal_hit(elite, right)
	_check(_near(float(walker.call("get_speed_factor")), 1.0 - slow) and _near(float(elite.call("get_speed_factor")), 1.0 - slow * Balance.SLOW_ELITE_FACTOR),
		"Echte Zombies: Schlurfer mal %s, Elite mal %s." % [1.0 - slow, 1.0 - slow * Balance.SLOW_ELITE_FACTOR])
	# Zwei Exemplare auf derselben Waffe: Der stärkste Wert zählt.
	_bag()
	_put_on("frost", 4, left)
	_sync()
	var strong: float = UpgradeDefs.value("frost", "slow", 4)
	_weapon_shot(target, 10.0, left)
	_check(_near(_bullet_value(left, "frost", "slow"), strong) and _near(target.slow_factor, strong), "Zwei Trockeneis: Der stärkere Wert (%d %%) zählt." % roundi(strong * 100.0))
	# Allgemein gesetzt gilt es für jede Waffe.
	_fresh_run()
	_give("frost", 5)
	var any: DummyZombie = _zombie(Vector3(0.0, 0.0, -5.0))
	_shot(any, 10.0)
	_check(any.slow_calls == 1 and _near(any.slow_factor, UpgradeDefs.value("frost", "slow", 5)), "Allgemein gesetztes Trockeneis gilt für jeden Kugeltreffer.")


# --- Querschläger ---

func _test_ricochet() -> void:
	var pistols: Array[int] = _two_pistols()
	var left: int = pistols[0]
	var right: int = pistols[1]
	_put_on("burn", 2, left)
	_put_on("ricochet", 5, left)
	_sync()
	var chance: float = UpgradeDefs.value("ricochet", "chance", 5)
	var factor: float = Balance.RICOCHET_DAMAGE_FACTOR
	_check(_near(_bullet_value(left, "ricochet", "chance"), chance) and _bullet_level(right, "ricochet") == 0, "Der Querschläger wirkt nur für die linke Pistole.")
	var origin: DummyZombie = _zombie(Vector3.ZERO)
	var neighbor: DummyZombie = _zombie(Vector3(2.0, 0.0, 0.0))
	var further: DummyZombie = _zombie(Vector3(-4.0, 0.0, 0.0))
	var far: DummyZombie = _zombie(Vector3(0.0, 0.0, Balance.RICOCHET_RADIUS + 3.0))
	var rng: RandomNumberGenerator = _game.get("rng")
	var state_before: int = rng.state
	for i: int in 200:
		_weapon_shot(origin, 20.0, right)
	_check(neighbor.hits.is_empty() and rng.state == state_before, "Die rechte Pistole hat keinen Querschläger und würfelt nicht.")
	var shots: int = 1000
	for i: int in shots:
		_weapon_shot(origin, 20.0, left)
	var jumps: int = neighbor.count("ricochet")
	var rate: float = float(jumps) / float(shots)
	_check(absf(rate - chance) < 0.05, "Querschläger Legendär: springt bei etwa %d %% der Treffer, waren %.1f %%." % [roundi(chance * 100.0), rate * 100.0])
	_check(jumps > 0 and _near(neighbor.total("ricochet"), float(jumps) * 20.0 * factor, 0.01) and neighbor.hits.size() == jumps,
		"Der Querschläger macht %d %% des Kugelschadens mit source ricochet." % roundi(factor * 100.0))
	_check(further.hits.is_empty() and far.hits.is_empty(), "Nur der nächste Zombie im Umkreis bekommt den Querschläger.")
	_check(origin.count("ricochet") == 0 and neighbor.burn_calls == 0, "Der Querschläger springt nicht zurück und löst keinen Kugel-Effekt aus.")
	_check(origin.burn_calls == shots, "Gegenprobe: Die Kugeln der linken Pistole selbst zünden an.")
	_check(_fx_has("Beam"), "Der Querschläger ist als Strich zu sehen.")
	# Außerhalb des Umkreises springt nichts.
	neighbor.position = Vector3(Balance.RICOCHET_RADIUS + 0.5, 0.0, 0.0)
	further.position = Vector3(-Balance.RICOCHET_RADIUS - 0.5, 0.0, 0.0)
	for i: int in 100:
		_weapon_shot(origin, 20.0, left)
	_check(neighbor.count("ricochet") == jumps and further.hits.is_empty(), "Außerhalb von %s m gibt es keinen Querschläger." % Balance.RICOCHET_RADIUS)
	# Zwei legendäre Exemplare: Die Chance endet bei 100 %.
	pistols = _two_pistols()
	left = pistols[0]
	_put_on("ricochet", 5, left)
	_put_on("ricochet", 5, left)
	_sync()
	_check(_near(_bullet_value(left, "ricochet", "chance"), 1.0), "Zwei legendäre Querschläger: 100 % Chance.")
	origin = _zombie(Vector3.ZERO)
	neighbor = _zombie(Vector3(2.0, 0.0, 0.0))
	var before: int = neighbor.count("ricochet")
	for i: int in 50:
		_weapon_shot(origin, 20.0, left)
	_check(neighbor.count("ricochet") == before + 50, "Mit 100 % springt jeder Treffer.")
	var victim: DummyZombie = _zombie(Vector3(0.0, 0.0, 2.0), 10.0)
	before = neighbor.count("ricochet") + origin.count("ricochet")
	_weapon_shot(victim, 30.0, left)
	_check(victim.is_dead and neighbor.count("ricochet") + origin.count("ricochet") == before + 1, "Auch ein tödlicher Kugeltreffer springt weiter.")


# --- Kaktus-Requisite ---

func _test_thorns() -> void:
	# Ohne den Gegenstand passiert nichts.
	_fresh_run()
	var idle: DummyZombie = _zombie(Vector3(1.0, 0.0, 0.0))
	_events.emit_signal("player_damaged", 10.0)
	_effects.call("tick", 0.016)
	_check(idle.hits.is_empty(), "Ohne Kaktus-Requisite passiert bei einem Treffer nichts.")

	_fresh_run()
	_bag()
	var thorns_a: int = _auto("thorns", 1)
	_auto("thorns", 3)
	_sync()
	var damage: float = UpgradeDefs.value("thorns", "damage", 1) + UpgradeDefs.value("thorns", "damage", 3)
	var radius: float = Balance.THORNS_RADIUS
	_player.position = Vector3(1.0, 0.0, 2.0)
	var center: Vector3 = _player.position
	var inside: DummyZombie = _zombie(center + Vector3(radius - 0.1, 0.0, 0.0))
	var close: DummyZombie = _zombie(center + Vector3(0.0, 0.0, -1.0))
	var outside: DummyZombie = _zombie(center + Vector3(radius + 0.1, 0.0, 0.0))
	_effects.call("tick", 1.0)
	_check(inside.hits.is_empty(), "Ohne Treffer am Spieler stechen die Stacheln nicht.")
	_events.emit_signal("player_damaged", 15.0)
	_check(inside.hits.is_empty() and close.hits.is_empty(), "Die Stacheln wirken nicht mitten im Signal, sondern im nächsten Schritt.")
	_effects.call("tick", 0.016)
	_check(inside.count("thorns") == 1 and close.count("thorns") == 1 and _near(inside.total("thorns"), damage) and _near(close.total("thorns"), damage),
		"Kaktus-Requisite: %s Schaden (source thorns, zwei Exemplare) an allen im Umkreis von %s m, waren %s." % [damage, radius, inside.total("thorns")])
	_check(outside.hits.is_empty(), "Außerhalb des Umkreises passiert nichts.")
	_check(inside.hits.size() == 1 and inside.burn_calls == 0, "Die Stacheln lösen keinen Kugel-Effekt aus.")
	_check(_fx_has("Beam"), "Die Stacheln sind zu sehen.")
	_effects.call("tick", 0.016)
	_check(inside.count("thorns") == 1, "Ein Treffer löst die Stacheln nur einmal aus.")
	# Zwei Treffer im selben Schritt: ein Stich.
	_events.emit_signal("player_damaged", 5.0)
	_events.emit_signal("player_damaged", 5.0)
	_effects.call("tick", 0.016)
	_check(inside.count("thorns") == 2, "Mehrere Treffer im selben Schritt geben einen Stich.")
	# Effekt-Faktor der Welle.
	_game.set("wave", 10)
	var factor: float = WavePlan.effect_factor(10)
	_events.emit_signal("player_damaged", 5.0)
	_effects.call("tick", 0.016)
	_check(factor > 1.0 and _near(_last_amount(inside), damage * factor, 0.01), "In Welle 10 ist der Schaden der Stacheln mal %s." % factor)
	_game.set("wave", 0)
	# Ein toter Spieler sticht nicht.
	_player.is_dead = true
	_events.emit_signal("player_damaged", 500.0)
	_effects.call("tick", 0.016)
	_check(inside.count("thorns") == 3, "Ein toter Spieler sticht nicht mehr.")
	_player.is_dead = false
	_effects.call("tick", 0.016)
	_check(inside.count("thorns") == 3, "Der verfallene Stich kommt auch später nicht nach.")
	# Ein Exemplar in der Ablage: Es zählt nur noch das andere.
	_backpack().call("store", thorns_a)
	_sync()
	_events.emit_signal("player_damaged", 5.0)
	_effects.call("tick", 0.016)
	_check(_near(_last_amount(inside), UpgradeDefs.value("thorns", "damage", 3)), "Mit einem Kaktus in der Ablage sticht nur noch der andere.")


# --- Pausensnack ---

func _test_snack() -> void:
	_fresh_run()
	_events.emit_signal("wave_cleared", 1)
	_check(_near(_player.healed, 0.0), "Ohne Pausensnack heilt das Wellenende hier nichts.")
	_auto("snack", 2)
	_auto("snack", 5)
	_sync()
	var heal: float = UpgradeDefs.value("snack", "heal", 2) + UpgradeDefs.value("snack", "heal", 5)
	_player.max_hp = 200.0
	_player.hp = 20.0
	_events.emit_signal("wave_cleared", 1)
	_check(_near(_player.healed, heal) and _near(_player.hp, 20.0 + heal), "Pausensnack: Zwei Exemplare heilen am Wellenende zusammen %s, waren %s." % [heal, _player.healed])
	_events.emit_signal("wave_cleared", 2)
	_check(_near(_player.healed, heal * 2.0), "Jedes Wellenende heilt aufs Neue.")
	_player.is_dead = true
	_events.emit_signal("wave_cleared", 3)
	_check(_near(_player.healed, heal * 2.0), "Ein toter Spieler wird nicht geheilt.")
	_player.is_dead = false


# --- Requisitenbombe ---

func _mines() -> Array:
	return _effects.get("mines") as Array


func _mine_count() -> int:
	return int(_effects.call("get_mine_count"))


func _mine_left() -> float:
	return float(_effects.call("get_mine_time_left"))


func _test_mines() -> void:
	var step: float = 1.0 / 60.0
	var limit: int = Balance.MINE_MAX_ACTIVE
	var arm_time: float = float((load("res://scripts/game/upgrades/mine.gd") as GDScript).get_script_constant_map()["ARM_TIME"])
	# Ohne den Gegenstand passiert nichts.
	_fresh_run()
	var placed_before: int = _noted("mine_placed").size()
	_effects.call("tick", 30.0)
	_check(_mine_count() == 0 and _near(_mine_left(), 0.0) and _noted("mine_placed").size() == placed_before, "Ohne Requisitenbombe wird keine Mine gelegt.")

	_fresh_run()
	_bag()
	var item: int = _auto("mine", 3)
	_sync()
	var interval: float = UpgradeDefs.value("mine", "interval", 3)
	var damage: float = UpgradeDefs.value("mine", "damage", 3)
	_player.position = Vector3.ZERO
	_effects.call("tick", step)
	_check(_mine_count() == 0 and _near(_mine_left(), interval - step), "Neu eingeräumt wartet die Requisitenbombe einen vollen Abstand von %s s." % interval)
	_effects.call("tick", interval - 0.2)
	_check(_mine_count() == 0, "Vor Ablauf des Abstands liegt keine Mine.")
	_effects.call("tick", 0.3)
	_check(_mine_count() == 1 and _noted("mine_placed").size() == placed_before + 1 and _near(_mine_left(), interval), "Nach %s s liegt die erste Mine, der Abstand beginnt neu." % interval)
	if _mine_count() != 1:
		return
	var first: Node3D = _mines()[0] as Node3D
	_check(first.get_parent() == _fx_root and first.is_in_group("mines") and first.global_position.distance_to(_player.global_position) < 0.01,
		"Die Mine liegt an den Füßen des Spielers im Effekt-Behälter.")
	_check((_noted("mine_placed")[_noted("mine_placed").size() - 1][0] as Vector3).distance_to(first.global_position) < 0.01, "mine_placed nennt den Ort der Mine.")
	_check(_near(float(first.get("damage")), damage), "Die Mine trägt den Schaden %s." % damage)
	# Bleibt der Spieler stehen, wartet die nächste Mine: Sie stapeln sich nicht.
	_effects.call("tick", interval + 1.0)
	_check(_mine_count() == 1 and _near(_mine_left(), 0.0), "Auf demselben Fleck wird keine zweite Mine gelegt, sie wartet.")
	_player.position = Vector3(2.0, 0.0, 0.0)
	_effects.call("tick", step)
	_check(_mine_count() == 2 and _near(_mine_left(), interval), "Ein Schritt zur Seite: Die wartende Mine kommt sofort.")
	# Bis zur Obergrenze.
	for i: int in range(2, limit):
		_player.position = Vector3(2.0 * float(i), 0.0, 0.0)
		_effects.call("tick", interval)
	_check(_mine_count() == limit, "Es liegen %d Minen." % limit)
	_player.position = Vector3(2.0 * float(limit), 0.0, 0.0)
	var triggered_before: int = _noted("mine_triggered").size()
	var explosions_before: int = _noted("explosion").size()
	_effects.call("tick", interval + 1.0)
	_check(_mine_count() == limit and _near(_mine_left(), 0.0) and _noted("mine_placed").size() == placed_before + limit,
		"Mehr als %d Minen gibt es nicht: Die nächste wartet auf Platz." % limit)
	_check(_mines()[0] == first and not first.is_queued_for_deletion(), "Die älteste Mine weicht nicht.")
	_check(_noted("mine_triggered").size() == triggered_before and _noted("explosion").size() == explosions_before, "Ohne Zombie geht keine Mine hoch.")

	# Auslösen: Ein Zombie kommt der ältesten Mine nahe.
	var mine_at: Vector3 = first.global_position
	var victim: DummyZombie = _zombie(mine_at + Vector3(0.0, 0.0, Balance.MINE_TRIGGER_RADIUS + 0.2))
	var edge: DummyZombie = _zombie(mine_at + Vector3(0.0, 0.0, -(Balance.MINE_RADIUS - 0.1)))
	var outside: DummyZombie = _zombie(mine_at + Vector3(0.0, 0.0, -(Balance.MINE_RADIUS + 0.2)))
	_effects.call("tick", step)
	_check(victim.hits.is_empty() and _noted("mine_triggered").size() == triggered_before, "Außerhalb von %s m löst die Mine nicht aus." % Balance.MINE_TRIGGER_RADIUS)
	victim.position = mine_at + Vector3(0.0, 0.0, Balance.MINE_TRIGGER_RADIUS - 0.1)
	_effects.call("tick", step)
	_check(victim.count("mine") == 1 and _near(victim.total("mine"), damage) and edge.count("mine") == 1 and _near(edge.total("mine"), damage),
		"Die Mine explodiert: %s Schaden (source mine) an allen im Umkreis von %s m, waren %s." % [damage, Balance.MINE_RADIUS, victim.total("mine")])
	_check(outside.hits.is_empty(), "Außerhalb des Radius trifft die Explosion nicht.")
	_check(victim.hits.size() == 1 and victim.burn_calls == 0, "Die Explosion der Mine löst keinen Kugel-Effekt aus.")
	_check(_noted("mine_triggered").size() == triggered_before + 1
		and (_noted("mine_triggered")[_noted("mine_triggered").size() - 1][0] as Vector3).distance_to(mine_at) < 0.01, "mine_triggered nennt den Ort der Mine.")
	var blast: Array = _noted("explosion")[_noted("explosion").size() - 1] if _noted("explosion").size() > explosions_before else [Vector3.INF, 0.0]
	_check(_noted("explosion").size() == explosions_before + 1 and _near(float(blast[1]), Balance.MINE_RADIUS) and (blast[0] as Vector3).distance_to(mine_at) < 1.0,
		"Die Explosion meldet sich über Events.explosion mit dem Radius %s." % Balance.MINE_RADIUS)
	_check(first.is_queued_for_deletion() and not _mines().has(first) and _fx_has("Explosion"), "Die Mine ist weg, die Explosion ist zu sehen.")
	# Jetzt ist Platz: Die wartende Mine fällt sofort.
	_check(_mine_count() == limit and _noted("mine_placed").size() == placed_before + limit + 1, "Sobald Platz ist, wird die wartende Mine gelegt.")
	var fresh: Node3D = _mines()[_mines().size() - 1] as Node3D
	_check(fresh.global_position.distance_to(_player.global_position) < 0.01 and not bool(fresh.call("is_armed")), "Sie liegt beim Spieler und ist noch nicht scharf.")
	# Eine frische Mine ist erst nach kurzer Zeit scharf.
	var stander: DummyZombie = _zombie(fresh.global_position + Vector3(0.0, 0.0, 0.5))
	_effects.call("tick", arm_time * 0.5)
	_check(stander.hits.is_empty(), "Eine frisch gelegte Mine geht nicht sofort hoch.")
	_effects.call("tick", arm_time)
	_check(stander.count("mine") == 1 and _mine_count() == limit - 1, "Nach %s s ist sie scharf und explodiert." % arm_time)

	# Pause: Die Minen ruhen. Danach mit dem Effekt-Faktor der Welle.
	var second: Node3D = _mines()[0] as Node3D
	var walker: DummyZombie = _zombie(second.global_position + Vector3(0.0, 0.0, 0.6))
	_game.call("set_paused", true)
	_effects.call("tick", 1.0)
	_check(walker.hits.is_empty() and _mine_count() == limit - 1, "In der Pause löst keine Mine aus.")
	_game.call("set_paused", false)
	_game.set("wave", 10)
	var factor: float = WavePlan.effect_factor(10)
	_effects.call("tick", step)
	_check(factor > 1.0 and walker.count("mine") == 1 and _near(walker.total("mine"), damage * factor, 0.01), "In Welle 10 ist der Schaden der Mine mal %s." % factor)
	_game.set("wave", 0)

	# Ein toter Spieler legt nichts.
	for node: Node in _zombie_root.get_children():
		node.free()
	_player.position = Vector3(40.0, 0.0, 0.0)
	_player.is_dead = true
	var count_before: int = _mine_count()
	_effects.call("tick", interval + 1.0)
	_check(_mine_count() == count_before, "Ein toter Spieler legt keine Mine.")
	_player.is_dead = false
	_effects.call("tick", step)
	_check(_mine_count() == count_before + 1, "Lebt er wieder, fällt die wartende Mine.")
	# Zwei Exemplare: der kürzere Abstand, der Schaden addiert sich.
	var item_b: int = _auto("mine", 5)
	_sync()
	var short_interval: float = UpgradeDefs.value("mine", "interval", 5)
	var both: float = damage + UpgradeDefs.value("mine", "damage", 5)
	_effects.call("tick", step)
	_check(_mine_left() <= short_interval, "Zwei Requisitenbomben: Es gilt der kürzere Abstand von %s s." % short_interval)
	_player.position = Vector3(44.0, 0.0, 0.0)
	_effects.call("tick", short_interval)
	var newest: Node3D = _mines()[_mines().size() - 1] as Node3D
	_check(_mine_count() == count_before + 2 and _near(float(newest.get("damage")), both), "Die neue Mine trägt den Schaden beider Exemplare (%s)." % both)
	# Ohne den Gegenstand bleiben die liegenden Minen liegen und zünden weiter, neue kommen nicht.
	_backpack().call("store", item)
	_backpack().call("store", item_b)
	_sync()
	_player.position = Vector3(48.0, 0.0, 0.0)
	_effects.call("tick", short_interval + 1.0)
	_check(_mine_count() == count_before + 2 and _near(_mine_left(), 0.0), "Ohne Requisitenbombe im Raster kommt keine neue Mine, die liegenden bleiben.")
	var late: DummyZombie = _zombie(newest.global_position + Vector3(0.0, 0.0, 0.5))
	_effects.call("tick", step)
	_check(late.count("mine") == 1 and _near(late.total("mine"), both) and _mine_count() == count_before + 1, "Eine liegende Mine zündet auch dann noch mit ihrem Schaden.")
	# Neuer Lauf: Alle Minen verschwinden, ohne zu explodieren.
	var lying: Array = _mines().duplicate()
	var explosions: int = _noted("explosion").size()
	_events.emit_signal("run_started")
	var all_gone: bool = true
	for entry: Variant in lying:
		if not (entry as Node3D).is_queued_for_deletion():
			all_gone = false
	_check(_mine_count() == 0 and all_gone and not lying.is_empty() and _noted("explosion").size() == explosions, "Ein neuer Lauf räumt alle Minen weg, ohne Explosion.")
	_fresh_run()
	await process_frame
	await process_frame
	_check(get_nodes_in_group("mines").is_empty(), "Alle Minen sind aus dem Baum verschwunden.")


# --- Kiste ---

## Index des ersten Upgrade-Gegenstands im Angebot einer Kiste (jede Kiste hat mindestens einen).
func _first_upgrade_offer(offers: Array) -> int:
	for i: int in offers.size():
		if UpgradeDefs.has(String((offers[i] as Dictionary).get("id", ""))):
			return i
	return 0


func _test_chest() -> void:
	# Gewählte Gegenstände räumen sich in diesem Test selbst ein.
	_game.set("auto_pack", true)
	_fresh_run()
	var chest_script: GDScript = load("res://scripts/game/upgrades/chest.gd") as GDScript
	var state_playing: int = 1
	var state_choosing: int = 2
	var gold: Area3D = chest_script.new()
	gold.call("setup", Balance.RARITY_GOLD)
	gold.position = Vector3(1.0, 0.0, 0.0)
	_chest_root.add_child(gold)
	var bronze: Area3D = chest_script.new()
	bronze.call("setup", Balance.RARITY_BRONZE)
	bronze.position = Vector3(1.2, 0.0, 0.0)
	_chest_root.add_child(bronze)
	_check(gold.is_in_group("chests") and bronze.is_in_group("chests"), "Kisten sind in der Gruppe chests.")
	_check(gold.collision_layer == Balance.LAYER_PICKUPS and gold.collision_mask == Balance.MASK_CHEST, "Kiste: Lage 4, Maske 2.")
	_check(int(gold.get("rarity")) == Balance.RARITY_GOLD and not bool(gold.get("is_collected")), "Kiste: Seltenheit Gold, noch nicht aufgesammelt.")
	_check(gold.get_node_or_null("Shape") != null and gold.get_node_or_null("Body") != null, "Kiste: Knoten Shape und Body sind da.")

	# Aufsammeln öffnet die Wahl.
	gold.call("collect")
	_check(int(_game.get("state")) == state_choosing and paused, "Aufsammeln öffnet die Kistenwahl und pausiert.")
	_check(bool(gold.get("is_collected")) and not gold.is_in_group("chests"), "Die Kiste gilt als aufgesammelt.")
	var offers: Array = _game.get("current_offers")
	_check(offers.size() == Balance.CHEST_OFFER_COUNT and int(_game.get("current_rarity")) == Balance.RARITY_GOLD, "Drei Angebote einer Gold-Kiste liegen bereit.")
	# Zweite Kiste im selben Bild: bleibt liegen.
	bronze.call("collect")
	_check(not bool(bronze.get("is_collected")) and bronze.is_in_group("chests") and is_instance_valid(bronze),
		"Eine zweite Kiste bleibt liegen, solange die Wahl offen ist.")
	_check(int(_game.get("current_rarity")) == Balance.RARITY_GOLD, "Die offene Wahl bleibt die der ersten Kiste.")
	# Angebot anwenden: Game.upgrades ändert sich.
	var gold_pick: int = _first_upgrade_offer(offers)
	var offer: Dictionary = offers[gold_pick]
	_check(String(offer.get("kind", "")) == ChestRoller.KIND_ITEM, "Die Kiste bietet Gegenstände an.")
	_game.call("choose_offer", gold_pick)
	_check(int(_game.get("state")) == state_playing and not paused, "Nach der Wahl läuft das Spiel weiter.")
	_check(int(_upgrades().call("get_level", String(offer["id"]))) == 3 and int(offer["level"]) == 3,
		"Gold gibt einen Gegenstand der Stufe 3: %s wirkt mit Stufe 3." % String(offer["id"]))
	await process_frame
	await process_frame
	_check(not is_instance_valid(gold), "Die aufgesammelte Kiste ist verschwunden.")

	# Pause: Kiste bleibt liegen.
	_game.call("set_paused", true)
	bronze.call("collect")
	_check(not bool(bronze.get("is_collected")), "In der Pause öffnet sich keine Kiste.")
	_game.call("set_paused", false)
	# Jetzt geht sie auf, und nur einmal.
	bronze.call("collect")
	_check(bool(bronze.get("is_collected")) and int(_game.get("state")) == state_choosing and int(_game.get("current_rarity")) == Balance.RARITY_BRONZE,
		"Danach öffnet sich die zweite Kiste.")
	var bronze_pick: int = _first_upgrade_offer(_game.get("current_offers") as Array)
	var bronze_offer: Dictionary = (_game.get("current_offers") as Array)[bronze_pick]
	var level_before: int = int(_upgrades().call("get_level", String(bronze_offer["id"])))
	_game.call("choose_offer", bronze_pick)
	_check(int(_upgrades().call("get_level", String(bronze_offer["id"]))) == mini(level_before + 1, Balance.UPGRADE_MAX_LEVEL),
		"Bronze gibt eine Stufe.")
	bronze.call("collect")
	_check(int(_game.get("state")) == state_playing, "Eine Kiste öffnet sich nie zweimal.")
	await process_frame
	await process_frame
	_game.set("auto_pack", false)


# --- ChestDropper ---

func _test_chest_dropper() -> void:
	var dropper: Node = (load("res://scripts/game/upgrades/chest_dropper.gd") as GDScript).new()
	dropper.name = "ChestDropper"
	dropper.set("chest_parent", _chest_root)
	root.add_child(dropper)

	# Elite: immer eine Kiste, am Ort des Toten.
	_fresh_run()
	_dropped_chests.clear()
	_events.emit_signal("wave_started", 2, 15)
	for i: int in 20:
		var elite: DummyZombie = _zombie(Vector3(float(i) * 3.0, 0.0, 5.0), 10.0, "elite")
		elite.set_meta("wave_spawn", true)
		elite.take_damage(50.0, _bullet_info())
	_check(_dropped_chests.size() == 20, "Jede Elite lässt eine Kiste fallen, waren %d von 20." % _dropped_chests.size())
	var first_chest: Node3D = _dropped_chests[0] as Node3D
	_check(is_instance_valid(first_chest) and first_chest.get_parent() == _chest_root and first_chest.is_in_group("chests"),
		"Die Kiste liegt im Behälter Chests.")
	_check(is_instance_valid(first_chest) and first_chest.global_position.distance_to(Vector3(0.0, 0.0, 5.0)) < 0.01,
		"Die Kiste liegt am Ort des Toten.")
	var rarities_ok: bool = true
	for chest: Variant in _dropped_chests:
		var rarity: int = int((chest as Node).get("rarity"))
		if rarity < Balance.RARITY_BRONZE or rarity > Balance.RARITY_GOLD:
			rarities_ok = false
	_check(rarities_ok, "Jede Kiste hat eine gültige Seltenheit.")
	# Zwei Tote an derselben Stelle: Die Kisten stapeln sich nicht.
	var twin: DummyZombie = _zombie(Vector3(0.0, 0.0, 5.0), 10.0, "elite")
	twin.take_damage(50.0, _bullet_info())
	var twin_chest: Node3D = _dropped_chests[_dropped_chests.size() - 1] as Node3D
	_check(twin_chest.global_position.distance_to(first_chest.global_position) > 1.0, "Zwei Kisten liegen nicht aufeinander.")

	# Neuer Lauf räumt Kisten weg.
	_fresh_run()
	_check(get_nodes_in_group("chests").is_empty(), "Ein neuer Lauf räumt liegen gebliebene Kisten weg.")

	# Normale Zombies: 3 % (Stufe 0), mit Glück 5 mehr 8 %.
	for luck: int in [0, 5]:
		_fresh_run()
		if luck > 0:
			_give("luck", luck)
		_dropped_chests.clear()
		_events.emit_signal("wave_started", 3, 5000)
		var kills: int = 3000
		for i: int in kills:
			var walker: DummyZombie = _zombie(Vector3(float(i % 50) * 3.0, 0.0, float(i / 50) * 3.0), 10.0)
			walker.set_meta("wave_spawn", true)
			walker.take_damage(50.0, _bullet_info())
			walker.free()
		var want: float = Balance.CHEST_DROP_CHANCE_NORMAL + 0.01 * float(luck)
		var rate: float = float(_dropped_chests.size()) / float(kills)
		_check(absf(rate - want) < 0.015, "Normale Zombies lassen mit %.0f %% eine Kiste fallen (Glück %d), waren %.1f %%." % [want * 100.0, luck, rate * 100.0])

	# Welle 1: Der letzte Zombie lässt sicher eine Kiste fallen. Fremde Zombies zählen nicht mit.
	var total: int = 10
	var sure_drops: int = 0
	for round_index: int in 30:
		_fresh_run(SEED + round_index)
		_dropped_chests.clear()
		_events.emit_signal("wave_started", Balance.GUARANTEED_CHEST_WAVE, total)
		var stranger: DummyZombie = _zombie(Vector3(0.0, 0.0, -20.0), 10.0)
		stranger.take_damage(50.0, _bullet_info())
		var before_last: int = 0
		for i: int in total:
			var walker: DummyZombie = _zombie(Vector3(float(i) * 3.0, 0.0, 9.0), 10.0)
			walker.set_meta("wave_spawn", true)
			if i == total - 1:
				before_last = _dropped_chests.size()
			walker.take_damage(50.0, _bullet_info())
		if _dropped_chests.size() == before_last + 1:
			var last_chest: Node3D = _dropped_chests[_dropped_chests.size() - 1] as Node3D
			if last_chest.global_position.distance_to(Vector3(float(total - 1) * 3.0, 0.0, 9.0)) < 0.01:
				sure_drops += 1
		# wave_cleared danach bringt keine zweite sichere Kiste.
		var after_last: int = _dropped_chests.size()
		_events.emit_signal("wave_cleared", Balance.GUARANTEED_CHEST_WAVE)
		if _dropped_chests.size() != after_last:
			sure_drops = -1000
	_check(sure_drops == 30, "Welle 1: Der letzte Zombie lässt in jedem von 30 Läufen genau eine Kiste fallen.")
	# Netz: Fehlt die Zählung (kein Zombie trägt wave_spawn), fällt die Kiste bei wave_cleared.
	_fresh_run()
	_dropped_chests.clear()
	_events.emit_signal("wave_started", Balance.GUARANTEED_CHEST_WAVE, 3)
	_events.emit_signal("wave_cleared", Balance.GUARANTEED_CHEST_WAVE)
	_check(_dropped_chests.size() == 1, "Welle 1 endet nie ohne Kiste: wave_cleared holt sie nach.")
	_events.emit_signal("wave_cleared", Balance.GUARANTEED_CHEST_WAVE)
	_check(_dropped_chests.size() == 1, "Die sichere Kiste gibt es nur einmal.")

	# spawn_chest: legt genau dort ab und meldet chest_dropped.
	_fresh_run()
	_dropped_chests.clear()
	var placed: Node3D = dropper.call("spawn_chest", Vector3(4.0, 0.0, -2.0), Balance.RARITY_SILVER)
	_check(is_instance_valid(placed) and _dropped_chests.size() == 1 and _dropped_chests[0] == placed, "spawn_chest sendet chest_dropped.")
	_check(placed.global_position.distance_to(Vector3(4.0, 0.0, -2.0)) < 0.01 and int(placed.get("rarity")) == Balance.RARITY_SILVER,
		"spawn_chest legt eine Silber-Kiste an den gewünschten Ort.")
	_fresh_run()
	dropper.queue_free()
	await process_frame
	await process_frame


# --- Effekte räumen sich selbst weg ---

func _test_fx_cleans_up() -> void:
	_fresh_run()
	var fx: GDScript = load("res://scripts/game/fx/fx.gd") as GDScript
	var holder: Node3D = Node3D.new()
	_fx_root.add_child(holder)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	holder.add_child(mesh)
	_check(fx.call("root_of", holder) == _fx_root, "Fx.root_of findet den Behälter der Gruppe fx_root.")
	_check(fx.call("root_of", null) == null, "Fx.root_of(null) gibt null zurück.")
	fx.call("tracer", _fx_root, Vector3.ZERO, Vector3(0.0, 1.0, -10.0), Color.YELLOW)
	fx.call("muzzle_flash", holder)
	fx.call("lightning", _fx_root, PackedVector3Array([Vector3.ZERO, Vector3(3.0, 1.0, 0.0), Vector3(3.0, 1.0, 4.0)]))
	fx.call("explosion", _fx_root, Vector3(1.0, 1.0, 1.0), 3.5, Color.HOT_PINK)
	fx.call("confetti", _fx_root, Vector3(1.0, 1.0, 1.0))
	fx.call("shockwave", _fx_root, Vector3.ZERO, 5.0)
	fx.call("damage_number", _fx_root, Vector3(0.0, 2.0, 0.0), 37.4, Color.WHITE)
	fx.call("hit_flash", mesh, Color.WHITE)
	_check(mesh.material_override != null, "hit_flash färbt das Mesh ein.")
	# Die Bilder aus Abschnitt 22 (upgrade_fx.gd) räumen sich genauso weg.
	var upgrade_fx: GDScript = load("res://scripts/game/upgrades/upgrade_fx.gd") as GDScript
	upgrade_fx.call("beam", _fx_root, Vector3.ZERO, Vector3(0.0, 1.0, -6.0), Color.CYAN, 0.08, 0.3)
	upgrade_fx.call("flash_wedge", _fx_root, Vector3.ZERO, Vector3.FORWARD, 7.0, 90.0, Color.WHITE)
	upgrade_fx.call("burst", _fx_root, Vector3(0.0, 2.0, 0.0), Color.WHITE, 0.8)
	upgrade_fx.call("spikes", _fx_root, Vector3.ZERO, 2.5, Color.GREEN)
	_check(_fx_has("Beam") and _fx_has("FlashWedge") and _fx_has("Burst"), "Strahl, Blitzlicht-Fächer und Aufleuchten hängen im Behälter.")
	_check(_fx_root.get_child_count() > 5, "Die Effekte hängen im Behälter.")
	# Ungültige Eltern: nichts tun, nicht abstürzen.
	var loose: Node3D = Node3D.new()
	fx.call("tracer", null, Vector3.ZERO, Vector3.ONE, Color.RED)
	fx.call("tracer", loose, Vector3.ZERO, Vector3.ONE, Color.RED)
	fx.call("muzzle_flash", null)
	fx.call("lightning", null, PackedVector3Array([Vector3.ZERO, Vector3.ONE]))
	fx.call("lightning", _fx_root, PackedVector3Array([Vector3.ZERO]))
	fx.call("lightning", _fx_root, PackedVector3Array([Vector3.ONE, Vector3.ONE]))
	fx.call("explosion", loose, Vector3.ZERO, 2.0, Color.RED)
	fx.call("confetti", null, Vector3.ZERO)
	fx.call("shockwave", loose, Vector3.ZERO, 2.0)
	fx.call("damage_number", null, Vector3.ZERO, 5.0, Color.RED)
	fx.call("hit_flash", null, Color.RED)
	upgrade_fx.call("beam", null, Vector3.ZERO, Vector3.ONE, Color.RED, 0.05, 0.2)
	upgrade_fx.call("beam", loose, Vector3.ZERO, Vector3.ONE, Color.RED, 0.05, 0.2)
	upgrade_fx.call("beam", _fx_root, Vector3.ONE, Vector3.ONE, Color.RED, 0.05, 0.2)
	upgrade_fx.call("flash_wedge", loose, Vector3.ZERO, Vector3.FORWARD, 7.0, 90.0, Color.WHITE)
	upgrade_fx.call("flash_wedge", _fx_root, Vector3.ZERO, Vector3.ZERO, 0.0, 90.0, Color.WHITE)
	upgrade_fx.call("burst", null, Vector3.ZERO, Color.WHITE, 0.5)
	upgrade_fx.call("spikes", loose, Vector3.ZERO, 2.5, Color.GREEN)
	_check(loose.get_child_count() == 0, "Ein Knoten außerhalb des Baums bekommt keinen Effekt.")
	loose.free()
	await create_timer(2.2).timeout
	_check(holder.get_child_count() == 1 and mesh.material_override == null, "Mündungsfeuer ist weg, das Mesh hat sein Material zurück.")
	holder.free()
	_check(_fx_root.get_child_count() == 0, "Alle Effekte haben sich selbst weggeräumt, übrig: %d." % _fx_root.get_child_count())
