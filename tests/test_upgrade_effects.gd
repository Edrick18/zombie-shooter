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
## Die Waffensteuerung ist nicht beteiligt: Die Tests senden bullet_hit selbst.
##
## Die Autoloads werden über root.get_node geholt und die Spielskripte zur Laufzeit geladen,
## weil ein -s-Skript die Namen Game und Events beim Übersetzen nicht kennt (Abschnitt 13.7).

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")

const SEED: int = 4711
const HUGE_HP: float = 1.0e9


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
	var knockback: Vector3 = Vector3.ZERO
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

	func apply_knockback(impulse: Vector3) -> void:
		knockback += impulse

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
	_check(_effects.get("drone") == null, "Ohne das Upgrade gibt es keine Drohne.")
	for level: int in [1, 5]:
		_fresh_run()
		_give("burn", 5)
		_give("chain_lightning", 5)
		_give("drone", level)
		_events.emit_signal("upgrade_chosen", "drone", level)
		var drone: Node3D = _effects.get("drone") as Node3D
		_check(is_instance_valid(drone) and drone.is_inside_tree(), "Kameradrohne Stufe %d: Die Drohne fliegt." % level)
		if not is_instance_valid(drone):
			continue
		_check(drone.get_parent() == _fx_root, "Die Drohne hängt im Effekt-Behälter.")
		_check(int(drone.get("level")) == level, "Kameradrohne: Stufe %d ist gesetzt." % level)
		var interval: float = UpgradeDefs.value("drone", "interval", level)
		var base_damage: float = UpgradeDefs.value("drone", "damage", level)
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
		# Effekt-Faktor.
		_game.set("wave", 10)
		drone.call("try_fire")
		_check(_near(float(near.hits[near.hits.size() - 1]["amount"]), base_damage * WavePlan.effect_factor(10), 0.01),
			"Kameradrohne Stufe %d: In Welle 10 wächst der Schaden mit dem Effekt-Faktor." % level)
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

	# Stufe folgt dem Upgrade, auch ohne upgrade_chosen.
	_fresh_run()
	_give("drone", 2)
	_effects.call("tick", 0.016)
	var synced: Node3D = _effects.get("drone") as Node3D
	_check(is_instance_valid(synced) and int(synced.get("level")) == 2, "Die Drohne entsteht passend zur Stufe 2.")
	_upgrades().call("add_levels", "drone", 3)
	_effects.call("tick", 0.016)
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
	_check((_upgrades().call("copies", "drone") as Array) == [1], "Game.upgrades.copies nennt ein Exemplar der Rarität 1.")
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
	_check(_near(float(second.call("get_fire_interval")), UpgradeDefs.value("drone", "interval", 3))
		and _near(float(third.call("get_fire_interval")), UpgradeDefs.value("drone", "interval", 5)), "Jede Drohne schießt im Takt ihrer eigenen Stufe.")
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
	_check(_near(far.total("drone"), UpgradeDefs.value("drone", "damage", 3)) , "Die zweite Drohne macht den Schaden ihrer Stufe 3.")
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
	for source: String in ["lightning", "burn", "explosion", "shockwave", "drone"]:
		var info: Dictionary = {"source": source, "hit_position": Vector3.ZERO}
		origin.take_damage(20.0, info)
		# Selbst ein fälschlich gesendetes bullet_hit mit fremder Quelle bleibt ohne Wirkung.
		_events.emit_signal("bullet_hit", origin, 20.0, info)
		_events.emit_signal("weapon_fired", "pistol")
	_check(neighbor.hits.is_empty(), "Blitz, Brand, Explosion, Druckwelle und Drohne lösen keinen Kettenblitz aus.")
	_check(origin.burn_calls == 0, "Blitz, Brand, Explosion, Druckwelle und Drohne lösen keinen Brand aus.")
	# Gegenprobe: Die Kugel tut beides.
	_shot(origin, 20.0)
	_check(neighbor.count("lightning") == 1 and origin.burn_calls == 1, "Gegenprobe: Ein Kugeltreffer löst Blitz und Brand aus.")


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
	_check(loose.get_child_count() == 0, "Ein Knoten außerhalb des Baums bekommt keinen Effekt.")
	loose.free()
	await create_timer(2.2).timeout
	_check(holder.get_child_count() == 1 and mesh.material_override == null, "Mündungsfeuer ist weg, das Mesh hat sein Material zurück.")
	holder.free()
	_check(_fx_root.get_child_count() == 0, "Alle Effekte haben sich selbst weggeräumt, übrig: %d." % _fx_root.get_child_count())
