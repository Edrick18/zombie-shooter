extends SceneTree
## Gesamttest: lädt scenes/main.tscn headless als aktuelle Szene und spielt einen kleinen Lauf
## über die öffentlichen Schnittstellen der Module (Abschnitt 13.7), ohne Ersatz-Knoten.
##
## Geprüft wird der Reihe nach:
##   Aufbau, Schuss -> Kill -> Punkte, Elite -> Kiste -> Wahl -> Upgrade, alle zehn Upgrades mit
##   erzwungener Stufe im echten Spiel, Synergie bei 5 + 5, Tür (echter Blick-Strahl und Taste E)
##   mit Spawns der Zone 2 und Pfaden von jedem aktiven Spawnpunkt, Waffenfund, zweiter Lauf in derselben
##   Szene, drei ganze Wellen mit einem schummelnden Spieler (heilt sich, schießt mit der echten
##   Waffe), Tod -> Game Over mit Statistik, Neustart (Szene neu geladen) -> sauberer zweiter Lauf.
##
## Der Test läuft im Zeitraffer (Engine.time_scale), damit drei Wellen in wenigen Sekunden durch
## sind. Godot streckt dabei nur den Zeitschritt der Physik, deshalb erhöht der Test zugleich
## Engine.physics_ticks_per_second: Die Physik rechnet weiter in Schritten von 1/60 s Spielzeit,
## nur eben mehr davon je echter Sekunde.

const Balance := preload("res://scripts/core/balance.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")

const MAIN_SCENE: String = "res://scenes/main.tscn"
const SEED: int = 7
const TIME_SCALE: float = 6.0
## Physik-Schritte je Sekunde Spielzeit (Voreinstellung von Godot).
const SIM_TICKS_PER_SECOND: int = 60
## Der ganze Test darf höchstens so lange dauern (echte Sekunden), sonst bricht er ab.
const TIME_LIMIT_MSEC: int = 100000
const STATE_PLAYING: int = 1
const STATE_CHOOSING: int = 2
const STATE_GAME_OVER: int = 4
const KILL_INFO: Dictionary = {"source": "drone"}
const HUGE_DAMAGE: float = 1.0e9
const WAVES_TO_SURVIVE: int = 3

var _game: Node
var _events: Node
var _main: Node
var _failures: int = 0
var _checks: int = 0
var _started_msec: int = 0
var _timed_out: bool = false
## Mitschrift der Signale: Name -> Array von Einträgen (je Signal ein Dictionary).
var _log: Dictionary = {}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_started_msec = Time.get_ticks_msec()
	_game = root.get_node("Game")
	# Kisten räumen sich in diesem Test selbst ein (kein Rucksack-Bildschirm).
	if _game != null:
		_game.set("auto_pack", true)
	_events = root.get_node("Events")
	_connect_log()
	Engine.time_scale = TIME_SCALE
	Engine.physics_ticks_per_second = roundi(float(SIM_TICKS_PER_SECOND) * TIME_SCALE)
	Engine.max_physics_steps_per_frame = 32

	await _start_main()
	await _test_boot()
	await _test_shoot_kill_points()
	await _test_elite_chest_choice()
	await _test_upgrade_effects()
	await _test_synergy()
	await _test_door_and_wall_buys()
	await _test_second_run_same_scene()
	await _test_three_waves()
	await _test_death_and_game_over()
	await _test_restart_is_clean()

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = SIM_TICKS_PER_SECOND
	paused = false
	for action: String in ["move_forward", "interact"]:
		Input.action_release(action)
	if _timed_out:
		_failures += 1
		printerr("FEHLER: Zeitlimit von %d s überschritten." % int(TIME_LIMIT_MSEC / 1000.0))
	if _failures == 0:
		print("Gesamttest bestanden (%d Prüfungen)." % _checks)
	else:
		printerr("%d Prüfung(en) im Gesamttest fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


# --- Aufbau und Hilfen ------------------------------------------------------------------------

func _connect_log() -> void:
	_events.connect("run_started", func() -> void: _note("run_started", {}))
	_events.connect("wave_started", func(wave: int, total: int) -> void: _note("wave_started", {"wave": wave, "total": total}))
	_events.connect("wave_cleared", func(wave: int) -> void: _note("wave_cleared", {"wave": wave, "alive": get_nodes_in_group("zombies").size(), "kills": int(_game.get("kills"))}))
	_events.connect("intermission_tick", func(left: int) -> void: _note("intermission_tick", {"left": left}))
	_events.connect("zombie_spawned", func(zombie: Node3D) -> void: _note("zombie_spawned", {"id": zombie.get_instance_id(), "type": String(zombie.get("zombie_type"))}))
	_events.connect("zombie_damaged", func(zombie: Node3D, amount: float, info: Dictionary) -> void:
		_note("zombie_damaged", {"id": zombie.get_instance_id(), "amount": amount, "source": String(info.get("source", ""))}))
	_events.connect("zombie_killed", func(zombie: Node3D, info: Dictionary) -> void:
		_note("zombie_killed", {"id": zombie.get_instance_id(), "source": String(info.get("source", "")), "type": String(zombie.get("zombie_type"))}))
	_events.connect("bullet_hit", func(zombie: Node3D, damage: float, info: Dictionary) -> void:
		_note("bullet_hit", {"id": zombie.get_instance_id(), "damage": damage, "headshot": bool(info.get("headshot", false))}))
	_events.connect("player_damaged", func(amount: float) -> void: _note("player_damaged", {"amount": amount}))
	_events.connect("player_died", func() -> void: _note("player_died", {}))
	_events.connect("chest_dropped", func(chest: Node3D) -> void: _note("chest_dropped", {"id": chest.get_instance_id()}))
	_events.connect("chest_opened", func(rarity: int, offers: Array) -> void: _note("chest_opened", {"rarity": rarity, "offers": offers.size()}))
	_events.connect("upgrade_chosen", func(id: String, level: int) -> void: _note("upgrade_chosen", {"id": id, "level": level}))
	_events.connect("synergy_unlocked", func(id: String) -> void: _note("synergy_unlocked", {"id": id}))
	_events.connect("interact_prompt_changed", func(text: String) -> void: _note("prompt", {"text": text}))
	_events.connect("game_over", func(stats: Dictionary) -> void: _note("game_over", {"stats": stats}))


func _note(signal_name: String, entry: Dictionary) -> void:
	if not _log.has(signal_name):
		_log[signal_name] = []
	(_log[signal_name] as Array).append(entry)


func _count(signal_name: String) -> int:
	return (_log.get(signal_name, []) as Array).size()


## Einträge eines Signals ab dem Index from.
func _since(signal_name: String, from: int) -> Array:
	return (_log.get(signal_name, []) as Array).slice(from)


func _start_main() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set("run_seed", SEED)
	root.add_child(_main)
	current_scene = _main
	# Wellen erst, wenn der Test sie will.
	(_main.get("wave_manager") as Node).set("auto_start", false)
	await _physics(4)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: %s" % message)


func _near(a: float, b: float, tolerance: float = 0.01) -> bool:
	return absf(a - b) <= tolerance


func _out_of_time() -> bool:
	if Time.get_ticks_msec() - _started_msec > TIME_LIMIT_MSEC:
		_timed_out = true
	return _timed_out


func _physics(steps: int) -> void:
	for _i: int in steps:
		if _out_of_time():
			return
		await physics_frame


func _frames(count: int) -> void:
	for _i: int in count:
		if _out_of_time():
			return
		await process_frame


## Wartet höchstens sim_seconds Spielzeit (Physik-Schritte), bis die Bedingung gilt.
func _wait_until(condition: Callable, sim_seconds: float) -> bool:
	var steps: int = ceili(sim_seconds * float(SIM_TICKS_PER_SECOND))
	for _i: int in steps:
		if bool(condition.call()):
			return true
		if _out_of_time():
			return false
		await physics_frame
	return bool(condition.call())


func _player() -> CharacterBody3D:
	return _main.get("player") as CharacterBody3D


func _weapons() -> Node:
	return _player().call("get_weapon_controller") as Node


func _state() -> int:
	return int(_game.get("state"))


func _points() -> int:
	return int(_game.get("points"))


func _upgrades() -> UpgradeState:
	return _game.get("upgrades") as UpgradeState


func _spawn_point() -> Vector3:
	return (_main.get("level_info") as Dictionary)["player_spawn"]


## Spieler zurück auf den Startpunkt, Blick zur Bühne (-Z), volles Leben, volle Pistole.
func _reset_player() -> void:
	var player: CharacterBody3D = _player()
	player.global_position = _spawn_point()
	player.velocity = Vector3.ZERO
	player.call("look_at_point", _spawn_point() + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, -10.0))
	player.call("heal", 100000.0)
	# Nur umrüsten, wenn der Spieler etwas anderes hält: give_weapon gleicht den Build ab und
	# würde von Hand gesetzte Upgrades (_set_upgrades) überschreiben.
	if String(_weapons().call("get_current_weapon_id")) != "pistol" or (_weapons().call("get_owned_weapon_ids") as Array).size() != 1:
		_weapons().call("give_weapon", "pistol")
	_weapons().call("refill_ammo", "pistol")


## Alle Zombies und Kisten ohne Belohnung weg.
func _clear_field() -> void:
	for node: Node in get_nodes_in_group("zombies"):
		node.call("despawn")
	for node: Node in get_nodes_in_group("chests"):
		node.remove_from_group("chests")
		node.queue_free()
	await _physics(2)


## Erzwingt einen Upgrade-Stand: neue UpgradeState mit genau diesen Stufen. Die Module erfahren
## es wie im Spiel über upgrade_chosen (Spieler liest Werte neu, Drohne gleicht sich ab).
func _set_upgrades(levels: Dictionary) -> void:
	var state: UpgradeState = UpgradeState.new()
	for id: String in levels:
		state.add_levels(id, int(levels[id]))
	state.check_new_synergies()
	_game.set("upgrades", state)
	for id: String in levels:
		_events.emit_signal("upgrade_chosen", id, int(levels[id]))
	_player().call("refresh_stats")
	await _physics(2)


## Erzeugt einen Zombie über den echten Spawner und stellt ihn an eine Stelle.
func _spawn(type: String, at: Vector3, wave: int = 1) -> Node3D:
	var zombie: Node3D = (_main.get("spawner") as Node).call("spawn", type, wave) as Node3D
	zombie.call("teleport_to", at)
	return zombie


func _alive(zombie: Variant) -> bool:
	return is_instance_valid(zombie) and not bool((zombie as Node).get("is_dead"))


## Zielt auf einen Punkt und schießt mit der echten Waffe, sobald sie schussbereit ist.
func _fire_at(target: Vector3) -> bool:
	var weapons: Node = _weapons()
	var ready: bool = await _wait_until(func() -> bool:
		var weapon_state: RefCounted = weapons.call("get_state", String(weapons.call("get_current_weapon_id")))
		return weapon_state != null and bool(weapon_state.call("can_fire")), 4.0)
	if not ready:
		return false
	_player().call("look_at_point", target)
	return bool(weapons.call("try_fire"))


func _damage_from(source: String, zombie_id: int, from: int) -> Array:
	var result: Array = []
	for entry: Dictionary in _since("zombie_damaged", from):
		if String(entry["source"]) == source and (zombie_id == 0 or int(entry["id"]) == zombie_id):
			result.append(entry)
	return result


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- 1. Aufbau --------------------------------------------------------------------------------

func _test_boot() -> void:
	_check(_state() == STATE_PLAYING, "Nach dem Laden läuft das Spiel (State PLAYING).")
	_check(not paused, "Nach dem Laden ist keine Pause.")
	_check(_count("run_started") == 1, "run_started kam genau einmal.")
	for member: String in ["level_root", "zombies_root", "chests_root", "fx_root", "player", "spawner",
			"upgrade_effects", "chest_dropper", "wave_manager", "hud", "chest_choice", "pause_menu", "game_over"]:
		_check(is_instance_valid(_main.get(member)), "main.%s ist da." % member)
	var player: CharacterBody3D = _player()
	_check(_game.get("player") == player, "Game.player ist der Spieler.")
	_check(_flat_distance(player.global_position, _spawn_point()) < 0.05, "Der Spieler steht am Startpunkt.")
	_check(_near(float(player.get("hp")), Balance.PLAYER_MAX_HP), "Der Spieler hat volles Leben.")
	_check(player.collision_mask == Balance.MASK_PLAYER, "Die Maske des Spielers ist MASK_PLAYER (mit Spieler-Sperre).")
	_check(String(_weapons().call("get_current_weapon_id")) == "pistol", "Startwaffe ist die Pistole.")
	_check(get_nodes_in_group("zombies").is_empty() and get_nodes_in_group("chests").is_empty(), "Am Anfang gibt es weder Zombies noch Kisten.")
	var spawns: Array[Node] = get_nodes_in_group("zombie_spawns")
	_check(spawns.size() == 11, "Das Level hat 11 Spawnpunkte: 3 auf der Bühne, 2 je Raum (sind %d)." % spawns.size())
	var active: int = 0
	for node: Node in spawns:
		if bool(node.get_meta("active", true)):
			active += 1
	_check(active == 3, "Vor der Tür sind 3 Spawnpunkte aktiv (sind %d)." % active)
	# Der Spieler fällt nicht durch den Boden.
	await _physics(20)
	_check(absf(player.global_position.y) < 0.05 and player.is_on_floor(), "Der Spieler steht auf dem Boden (y = %.3f)." % player.global_position.y)


# --- 2. Schuss, Kill, Punkte ------------------------------------------------------------------

func _test_shoot_kill_points() -> void:
	_reset_player()
	var points_before: int = _points()
	var kills_before: int = int(_game.get("kills"))
	var hits_before: int = _count("bullet_hit")
	var walker: Node3D = _spawn("walker", Vector3(0.0, 0.0, 1.0))
	await _physics(3)
	var walker_id: int = walker.get_instance_id()
	_check(_near(float(walker.get("hp")), 60.0), "Schlurfer der Welle 1 hat 60 Leben.")
	var shots: int = 0
	while _alive(walker) and shots < 6:
		if await _fire_at(walker.call("get_center_position")):
			shots += 1
		else:
			break
	_check(shots == 3, "Drei Körpertreffer der Pistole töten einen Schlurfer (gebraucht: %d)." % shots)
	_check(_count("bullet_hit") - hits_before == 3, "Je Treffer kam bullet_hit.")
	var kill_entries: Array = _since("zombie_killed", _count("zombie_killed") - 1)
	_check(not kill_entries.is_empty() and int(kill_entries[0]["id"]) == walker_id and String(kill_entries[0]["source"]) == "bullet",
			"zombie_killed kam für den Schlurfer mit source bullet.")
	var expected: int = 3 * Balance.POINTS_BULLET_HIT + Balance.POINTS_KILL
	_check(_points() - points_before == expected, "3 Treffer + Kill geben %d Punkte (waren %d)." % [expected, _points() - points_before])
	_check(int(_game.get("kills")) - kills_before == 1, "Der Kill wurde gezählt.")
	_check(not walker.is_in_group("zombies"), "Der Tote hat die Gruppe zombies verlassen.")
	var gone: bool = await _wait_until(func() -> bool: return not is_instance_id_valid(walker_id), 2.0)
	_check(gone, "Der tote Zombie verschwindet nach der Todesanimation.")

	# Kopfschüsse: doppelter Schaden und Bonus-Punkte.
	_reset_player()
	points_before = _points()
	var second: Node3D = _spawn("walker", Vector3(0.0, 0.0, 1.0))
	await _physics(3)
	hits_before = _count("bullet_hit")
	shots = 0
	while _alive(second) and shots < 6:
		if await _fire_at(second.call("get_head_position")):
			shots += 1
		else:
			break
	_check(shots == 2, "Zwei Kopfschüsse töten einen Schlurfer (gebraucht: %d)." % shots)
	var head_hits: Array = _since("bullet_hit", hits_before)
	_check(head_hits.size() == 2 and bool(head_hits[0]["headshot"]) and _near(float(head_hits[0]["damage"]), 50.0),
			"Der Kopfschuss macht 50 Schaden.")
	expected = 2 * Balance.POINTS_BULLET_HIT + Balance.POINTS_KILL + Balance.POINTS_HEADSHOT_KILL_BONUS
	_check(_points() - points_before == expected, "Kopfschuss-Kill gibt %d Punkte (waren %d)." % [expected, _points() - points_before])
	await _clear_field()


# --- 3. Elite, Kiste, Wahl --------------------------------------------------------------------

func _test_elite_chest_choice() -> void:
	_reset_player()
	var drops_before: int = _count("chest_dropped")
	var points_before: int = _points()
	var elite: Node3D = _spawn("elite", Vector3(0.0, 0.0, -1.0), 2)
	await _physics(3)
	_check(String(elite.get("zombie_type")) == "elite" and float(elite.get("max_hp")) > 400.0, "Die Elite der Welle 2 hat mehr als 400 Leben.")
	elite.call("take_damage", HUGE_DAMAGE, KILL_INFO)
	await _physics(3)
	_check(_count("chest_dropped") - drops_before == 1, "Die Elite lässt genau eine Kiste fallen.")
	_check(_points() - points_before == Balance.POINTS_ELITE_KILL, "Elite-Kill gibt %d Punkte (waren %d)." % [Balance.POINTS_ELITE_KILL, _points() - points_before])
	var chests: Array[Node] = get_nodes_in_group("chests")
	_check(chests.size() == 1, "Es liegt eine Kiste (sind %d)." % chests.size())
	if chests.is_empty():
		return
	var chest: Node3D = chests[0] as Node3D
	_check(chest.get_parent() == _main.get("chests_root"), "Die Kiste hängt im Behälter Chests.")
	_check(_flat_distance(chest.global_position, Vector3(0.0, 0.0, -1.0)) < 2.0 and absf(chest.global_position.y) < 0.1,
			"Die Kiste liegt am Boden beim toten Zombie (%s)." % str(chest.global_position))
	_check(_state() == STATE_PLAYING, "Die Kiste bleibt liegen, bis der Spieler hineinläuft.")

	# Der Spieler läuft hinein (echte Area3D der Kiste).
	var opened_before: int = _count("chest_opened")
	_player().global_position = chest.global_position
	var opened: bool = await _wait_until(func() -> bool: return _state() == STATE_CHOOSING, 2.0)
	_check(opened, "Hineinlaufen öffnet die Kistenwahl (State CHOOSING).")
	if not opened:
		return
	_check(paused, "Die Kistenwahl pausiert das Spiel.")
	_check(_count("chest_opened") - opened_before == 1, "chest_opened kam genau einmal.")
	var choice: Node = _main.get("chest_choice") as Node
	_check(bool(choice.call("is_open")), "Der Bildschirm der Kistenwahl ist offen.")
	var offers: Array = _game.get("current_offers")
	_check(offers.size() == 3, "Die Kiste bietet 3 Angebote.")
	_check((choice.get("cards") as Array).size() == 3, "Die Kistenwahl zeigt 3 Karten.")
	# Jede Kiste bietet Gegenstände an, mindestens einer davon ist ein Upgrade-Gegenstand.
	var pick: int = -1
	var has_upgrade: bool = false
	for i: int in offers.size():
		_check(String((offers[i] as Dictionary).get("kind", "")) == "item", "Die Kiste bietet Gegenstände an.")
		var offered_id: String = String((offers[i] as Dictionary).get("id", ""))
		if UpgradeDefs.has(offered_id):
			has_upgrade = true
			# Gegenstände mit Sternen wirken erst mit einer Waffe darauf: Für die Prüfung der
			# Wirkung zählt einer, der für den Spieler als Ganzes gilt.
			if pick == -1 and not ItemDefs.has_stars(offered_id):
				pick = i
	_check(has_upgrade, "Mindestens ein Angebot ist ein Upgrade-Gegenstand.")
	if pick == -1:
		# Die Kiste bot nur Stern-Gegenstände an: Karte 1 für diese Prüfung durch einen ersetzen,
		# der für sich wirkt.
		pick = 0
		offers[0] = {"kind": "item", "id": "lifesteal", "level": int((offers[0] as Dictionary).get("level", 1)), "owned_level": 0}
	var offer: Dictionary = offers[pick]
	var chosen_before: int = _count("upgrade_chosen")
	# Der Gesamttest räumt selbst ein (Game.auto_pack), der Rucksack-Bildschirm bleibt zu.
	choice.call("choose", pick)
	_check(_state() == STATE_PLAYING and not paused, "Nach der Wahl läuft das Spiel weiter.")
	_check(not bool(choice.call("is_open")), "Die Kistenwahl ist wieder zu.")
	var id: String = String(offer.get("id", ""))
	_check(_upgrades().get_level(id) == int(offer.get("level", -1)), "Das gewählte Upgrade %s hat die angebotene Stufe." % id)
	_check(_count("upgrade_chosen") - chosen_before == 1, "upgrade_chosen kam genau einmal.")
	await _frames(2)
	_check((_main.get("hud") as Node).get("buff_rows") != null, "Das HUD hat die Buff-Anzeige.")
	await _physics(3)
	_check(get_nodes_in_group("chests").is_empty(), "Die aufgesammelte Kiste ist weg.")
	await _clear_field()


# --- 4. Alle zehn Upgrades im echten Spiel ----------------------------------------------------

func _test_upgrade_effects() -> void:
	await _effect_pierce()
	await _effect_chain_lightning()
	await _effect_burn()
	await _effect_lifesteal()
	await _effect_max_hp()
	await _effect_corpse_explosion()
	await _effect_reload_shockwave()
	await _effect_drone()
	await _effect_speed()
	await _effect_luck()
	await _set_upgrades({})
	await _clear_field()
	_reset_player()


func _row_of_three() -> Array[Node3D]:
	var row: Array[Node3D] = []
	for z: float in [2.0, 0.5, -1.0]:
		row.append(_spawn("walker", Vector3(0.0, 0.0, z)))
	return row


func _effect_pierce() -> void:
	await _set_upgrades({})
	_reset_player()
	var row: Array[Node3D] = _row_of_three()
	await _physics(3)
	var before: int = _count("bullet_hit")
	_check(await _fire_at(row[0].call("get_center_position")), "Schuss ohne Durchschlag fällt.")
	_check(_count("bullet_hit") - before == 1, "Ohne Spezialmunition trifft eine Kugel einen Zombie.")
	await _clear_field()

	await _set_upgrades({"pierce": 5})
	_reset_player()
	row = _row_of_three()
	await _physics(3)
	before = _count("bullet_hit")
	_check(await _fire_at(row[0].call("get_center_position")), "Schuss mit Durchschlag fällt.")
	var hits: Array = _since("bullet_hit", before)
	_check(hits.size() == 3, "Spezialmunition 5: eine Kugel trifft alle drei Zombies in der Reihe (Treffer: %d)." % hits.size())
	if hits.size() == 3:
		_check(_near(float(hits[0]["damage"]), 25.0) and _near(float(hits[1]["damage"]), 21.25) and _near(float(hits[2]["damage"]), 18.0625),
				"Jedes weitere Ziel bekommt 15 %% weniger Schaden (%s)." % str(hits))
	await _clear_field()


func _effect_chain_lightning() -> void:
	# Mit der Gewitterfront (beide auf 5) kommt der Blitz sicher: so ist die Prüfung kein Glücksspiel.
	await _set_upgrades({"chain_lightning": 5, "pierce": 5})
	_reset_player()
	var target: Node3D = _spawn("walker", Vector3(0.0, 0.0, 2.0))
	var neighbour: Node3D = _spawn("walker", Vector3(2.5, 0.0, 2.0))
	await _physics(3)
	var before: int = _count("zombie_damaged")
	_check(await _fire_at(target.call("get_center_position")), "Schuss für den Kettenblitz fällt.")
	var bolts: Array = _damage_from("lightning", neighbour.get_instance_id(), before)
	_check(bolts.size() == 1, "Starkstrom-Sponsor: Der Blitz springt auf den Nachbarn (Treffer: %d)." % bolts.size())
	if not bolts.is_empty():
		_check(_near(float(bolts[0]["amount"]), 25.0), "Blitz auf Stufe 5 macht 100 %% des Kugelschadens.")
	_check(_damage_from("lightning", target.get_instance_id(), before).is_empty(), "Der getroffene Zombie selbst bekommt keinen Blitz.")
	await _clear_field()


func _effect_burn() -> void:
	await _set_upgrades({"burn": 5})
	_reset_player()
	var target: Node3D = _spawn("walker", Vector3(0.0, 0.0, -1.0))
	await _physics(3)
	var target_id: int = target.get_instance_id()
	var before: int = _count("zombie_damaged")
	_check(await _fire_at(target.call("get_center_position")), "Schuss für den Brand fällt.")
	_check(bool(target.call("is_burning")), "Feuershow: Der getroffene Zombie brennt.")
	var ticked: bool = await _wait_until(func() -> bool: return _damage_from("burn", target_id, before).size() >= 2, 3.0)
	_check(ticked, "Der Brand tickt (source burn).")
	var ticks: Array = _damage_from("burn", target_id, before)
	if not ticks.is_empty():
		# 12 % von 60 Leben je Sekunde, alle 0,5 s.
		_check(_near(float(ticks[0]["amount"]), 3.6), "Ein Brand-Tick macht 3,6 Schaden (war %.2f)." % float(ticks[0]["amount"]))
	await _clear_field()


func _effect_lifesteal() -> void:
	await _set_upgrades({"lifesteal": 5})
	_reset_player()
	var player: CharacterBody3D = _player()
	player.set("hp", 50.0)
	var target: Node3D = _spawn("walker", Vector3(0.0, 0.0, 1.0))
	await _physics(3)
	_check(await _fire_at(target.call("get_center_position")), "Schuss für den Lebensraub fällt.")
	_check(_near(float(player.get("hp")), 52.5), "Blutspende-Aktion 5: 25 Schaden heilen 2,5 Leben (Leben: %.2f)." % float(player.get("hp")))
	await _clear_field()


func _effect_max_hp() -> void:
	await _set_upgrades({})
	_reset_player()
	var player: CharacterBody3D = _player()
	player.set("hp", 40.0)
	await _set_upgrades({"max_hp": 3})
	_check(_near(float(player.get("max_hp")), 160.0), "Stuntdouble 3: Maximal-Leben 160 (ist %.1f)." % float(player.get("max_hp")))
	_check(_near(float(player.get("hp")), 100.0), "Der Zuwachs heilt sofort (Leben: %.1f)." % float(player.get("hp")))
	await _set_upgrades({})
	_check(_near(float(player.get("max_hp")), 100.0), "Ohne das Upgrade gilt wieder 100.")


func _effect_corpse_explosion() -> void:
	await _set_upgrades({"corpse_explosion": 5})
	_reset_player()
	var neighbour: Node3D = _spawn("elite", Vector3(0.0, 0.0, -1.0))
	await _physics(3)
	var neighbour_id: int = neighbour.get_instance_id()
	var before: int = _count("zombie_damaged")
	var exploded: bool = false
	var tries: int = 0
	# 35 % Chance je Kill: 40 Versuche schlagen praktisch nie alle fehl.
	while not exploded and tries < 40 and _alive(neighbour):
		tries += 1
		var victim: Node3D = _spawn("walker", Vector3(1.6, 0.0, -1.0))
		await _physics(2)
		victim.call("take_damage", HUGE_DAMAGE, KILL_INFO)
		await _physics(3)
		exploded = not _damage_from("explosion", neighbour_id, before).is_empty()
	_check(exploded, "Konfetti-Kanone 5: Ein getöteter Zombie explodiert und trifft den Nachbarn (%d Versuche)." % tries)
	var blasts: Array = _damage_from("explosion", neighbour_id, before)
	if not blasts.is_empty():
		_check(_near(float(blasts[0]["amount"]), 45.0), "Die Explosion macht 75 %% von 60 Leben (war %.1f)." % float(blasts[0]["amount"]))
	await _clear_field()


func _effect_reload_shockwave() -> void:
	await _set_upgrades({"reload_shockwave": 5})
	_reset_player()
	var player: CharacterBody3D = _player()
	var target: Node3D = _spawn("elite", Vector3(0.0, 0.0, 2.0))
	await _physics(3)
	var target_id: int = target.get_instance_id()
	_check(await _fire_at(target.call("get_center_position")), "Schuss vor dem Nachladen fällt.")
	var before: int = _count("zombie_damaged")
	var distance_before: float = _flat_distance(target.global_position, player.global_position)
	_weapons().call("start_reload")
	var waves: Array = _damage_from("shockwave", target_id, before)
	_check(waves.size() == 1, "Werbepause: Nachladen löst die Druckwelle aus (Treffer: %d)." % waves.size())
	if not waves.is_empty():
		_check(_near(float(waves[0]["amount"]), 80.0 * float(_game.call("effect_factor"))), "Die Druckwelle macht 80 mal Effekt-Faktor.")
	await _physics(30)
	if _alive(target):
		var distance_after: float = _flat_distance(target.global_position, player.global_position)
		_check(distance_after > distance_before + 1.0, "Die Druckwelle stößt den Zombie weg (%.2f -> %.2f m)." % [distance_before, distance_after])
	_check(float((_main.get("upgrade_effects") as Node).call("get_shockwave_cooldown_left")) > 0.0, "Die Druckwelle hat danach Abklingzeit.")
	await _clear_field()


func _effect_drone() -> void:
	await _set_upgrades({})
	# Seit Abschnitt 22 ist die Kameradrohne eine Kamera: Sie kommt über den Rucksack ins Spiel
	# (Game.cameras), nicht mehr über Game.upgrades.
	var backpack: RefCounted = _game.get("backpack")
	var drone_uid: int = int(backpack.call("add_item", "drone", 5))
	_check(drone_uid > 0 and bool(backpack.call("auto_place", drone_uid)), "Die Kameradrohne passt in den Rucksack.")
	_game.call("sync_build")
	_reset_player()
	var effects: Node = _main.get("upgrade_effects") as Node
	var has_drone: bool = await _wait_until(func() -> bool: return is_instance_valid(effects.get("drone")), 1.0)
	_check(has_drone, "Kameradrohne: Die Drohne erscheint.")
	if has_drone:
		_check((effects.get("drone") as Node).get_parent() == _main.get("fx_root"), "Die Drohne hängt im Behälter Fx.")
	var target: Node3D = _spawn("walker", Vector3(0.0, 0.0, 0.0))
	var kills_before: int = _count("zombie_killed")
	var killed: bool = await _wait_until(func() -> bool:
		for entry: Dictionary in _since("zombie_killed", kills_before):
			if String(entry["source"]) == "drone":
				return true
		return false, 6.0)
	_check(killed, "Die Drohne tötet einen Zombie (source drone).")
	_check(not _alive(target), "Das Ziel der Drohne ist tot.")
	backpack.call("remove", drone_uid)
	_game.call("sync_build")
	await _set_upgrades({})
	await _physics(3)
	_check(not is_instance_valid(effects.get("drone")), "Ohne die Kamera im Rucksack verschwindet die Drohne.")
	await _clear_field()


## Läuft eine Weile geradeaus (echte Eingabe) und gibt das erreichte Tempo zurück.
func _measure_walk_speed() -> float:
	_reset_player()
	await _physics(5)
	Input.action_press("move_forward")
	await _physics(36)
	var velocity: Vector3 = _player().velocity
	Input.action_release("move_forward")
	await _physics(20)
	return Vector2(velocity.x, velocity.z).length()


func _effect_speed() -> void:
	await _set_upgrades({})
	var base: float = await _measure_walk_speed()
	_check(_near(base, Balance.PLAYER_WALK_SPEED, 0.2), "Gehtempo ohne Upgrade ist 5 m/s (war %.2f)." % base)
	await _set_upgrades({"speed": 5})
	var fast: float = await _measure_walk_speed()
	_check(_near(fast, Balance.PLAYER_WALK_SPEED * 1.4, 0.25), "Turbo-Turnschuhe 5: Tempo 7 m/s (war %.2f)." % fast)
	await _set_upgrades({})


func _effect_luck() -> void:
	await _set_upgrades({"luck": 5})
	_reset_player()
	var before: int = _points()
	_game.call("add_points", 100)
	_check(_points() - before == 150, "Publikumsliebling 5: 100 Punkte werden zu 150 (waren %d)." % (_points() - before))
	var target: Node3D = _spawn("walker", Vector3(0.0, 0.0, -1.0))
	await _physics(2)
	before = _points()
	target.call("take_damage", HUGE_DAMAGE, KILL_INFO)
	_check(_points() - before == 90, "Ein Kill gibt mit Glück 90 statt 60 Punkte (waren %d)." % (_points() - before))
	await _clear_field()


# --- 5. Synergie bei 5 + 5 --------------------------------------------------------------------

func _test_synergy() -> void:
	await _set_upgrades({"chain_lightning": 5, "pierce": 3})
	# check_new_synergies lief schon in _set_upgrades: Noch fehlt Spezialmunition 5.
	_check(not _upgrades().has_synergy("storm_front"), "Mit 5 + 3 gibt es noch keine Gewitterfront.")
	var unlocked_before: int = _count("synergy_unlocked")
	# Eine Silber-Kiste bietet Spezialmunition 3 -> 5 an: der echte Weg über Game.choose_offer.
	var offers: Array[Dictionary] = [{"kind": "upgrade", "id": "pierce", "from_level": 3, "to_level": 5}]
	_game.set("current_offers", offers)
	_game.set("current_rarity", Balance.RARITY_SILVER)
	_game.set("state", STATE_CHOOSING)
	_game.call("choose_offer", 0)
	_check(_state() == STATE_PLAYING, "Nach der Wahl läuft das Spiel.")
	_check(_upgrades().get_level("pierce") == 5, "Spezialmunition steht auf 5.")
	_check(_upgrades().has_synergy("storm_front"), "Starkstrom-Sponsor 5 + Spezialmunition 5 = Gewitterfront.")
	var unlocked: Array = _since("synergy_unlocked", unlocked_before)
	_check(unlocked.size() == 1 and String(unlocked[0]["id"]) == "storm_front", "synergy_unlocked(storm_front) kam genau einmal.")
	_check((_game.call("get_stats") as Dictionary)["synergies"] == ["storm_front"], "Die Statistik nennt die Synergie.")
	await _frames(2)
	_check((_main.get("hud") as Node).get("buff_rows").get_node_or_null("Buff_synergy_storm_front") != null, "Die Buff-Anzeige des HUD zeigt die Gewitterfront.")
	_check(_upgrades().free_slots() == Balance.UPGRADE_MAX_SLOTS - 2, "Die Synergie belegt keinen Platz.")
	await _set_upgrades({})
	await _clear_field()


# --- 6. Tür und Waffenfund ---------------------------------------------------------------------

func _all_spawns_reach(target: Vector3, label: String) -> void:
	var map: RID = _player().get_world_3d().navigation_map
	for node: Node in get_nodes_in_group("zombie_spawns"):
		if not bool(node.get_meta("active", true)):
			continue
		var marker: Node3D = node as Node3D
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, marker.global_position, target, true)
		var reaches: bool = path.size() >= 2 and _flat_distance(path[path.size() - 1], target) < 0.6
		_check(reaches, "Von %s führt ein Pfad zum Spieler (%s)." % [marker.name, label])


## Der Spieler lehnt an der Backstage-Seite der Wand zwischen Bühne und Backstage, ein Zombie
## kommt aus Gang C. Jeder Schlag muss von der Backstage-Seite kommen (der Zombie läuft durch
## die Tür), keiner durch die Wand.
func _wall_lean_attack(type: String, door: Node3D) -> void:
	var player: CharacterBody3D = _player()
	var wall_east_face: float = door.global_position.x + 0.2
	player.global_position = Vector3(wall_east_face + Balance.PLAYER_RADIUS + 0.01, 0.0, -1.0)
	player.velocity = Vector3.ZERO
	player.call("heal", 100000.0)
	var spawn_c: Node3D = _main.get_node_or_null("Level/Entrances/Entrance_C/Spawn_C") as Node3D
	_check(spawn_c != null, "Es gibt den Spawnpunkt Spawn_C.")
	if spawn_c == null:
		return
	await _physics(3)
	var zombie: Node3D = _spawn(type, spawn_c.global_position, 3)
	var seen: int = _count("player_damaged")
	var through_wall: int = 0
	var from_backstage: int = 0
	var steps: int = 30 * SIM_TICKS_PER_SECOND
	for _i: int in steps:
		if _out_of_time() or not _alive(zombie) or from_backstage >= 2:
			break
		await physics_frame
		var now: int = _count("player_damaged")
		if now > seen:
			seen = now
			if zombie.global_position.x < wall_east_face:
				through_wall += 1
			else:
				from_backstage += 1
			player.call("heal", 100000.0)
	_check(through_wall == 0, "Kein Schlag durch die Wand zwischen Bühne und Backstage (%s, Treffer durch die Wand: %d)." % [type, through_wall])
	_check(from_backstage >= 1, "Der Zombie läuft durch die Tür und schlägt von der Backstage-Seite zu (%s, Treffer: %d)." % [type, from_backstage])
	await _clear_field()


func _test_door_and_wall_buys() -> void:
	await _set_upgrades({})
	_reset_player()
	var player: CharacterBody3D = _player()
	var door: Node3D = (_main.get("level_info") as Dictionary)["door"] as Node3D
	_check(door == _main.get_node_or_null("Level/Door"), "Die Tür ist der Knoten Level/Door.")
	_check(not bool(door.get("is_open")), "Die Tür ist anfangs zu.")
	_game.call("spend_points", _points())
	_game.call("add_points", Balance.DOOR_COST)

	# Der Spieler stellt sich vor die Tür und schaut sie an: echter Blick-Strahl, echte Taste E.
	player.global_position = door.global_position + Vector3(-1.7, 0.0, 0.0)
	player.call("look_at_point", door.global_position + Vector3(0.0, 1.5, 0.0))
	var prompted: bool = await _wait_until(func() -> bool:
		var prompts: Array = _log.get("prompt", [])
		return not prompts.is_empty() and String(prompts[prompts.size() - 1]["text"]).contains("Backstage"), 1.0)
	_check(prompted, "Der Blick auf die Tür zeigt den Hinweis.")
	var prompts_now: Array = _log.get("prompt", [])
	if not prompts_now.is_empty():
		var text: String = String(prompts_now[prompts_now.size() - 1]["text"])
		_check(text == "E – Backstage öffnen (%d)" % Balance.DOOR_COST, "Der Hinweis lädt zum Kauf ein (\"%s\")." % text)
	await process_frame
	Input.action_press("interact")
	var opened: bool = await _wait_until(func() -> bool: return bool(door.get("is_open")), 1.0)
	Input.action_release("interact")
	_check(opened, "Taste E öffnet die Tür.")
	_check(_points() == 0, "Die Tür hat %d Punkte gekostet (Rest %d)." % [Balance.DOOR_COST, _points()])
	# Nur die Eingänge der Bühne (Zone 1) und des gekauften Raums (Zone 2) sind aktiv.
	for node: Node in get_nodes_in_group("zombie_spawns"):
		var zone: int = int(node.get_meta("zone", 1))
		if zone <= 2:
			_check(bool(node.get_meta("active", false)), "Nach dem Öffnen ist %s aktiv." % node.name)
		else:
			_check(not bool(node.get_meta("active", true)), "%s (Zone %d) bleibt aus, solange der Raum zu ist." % [node.name, zone])
	_check((_main.get("spawner") as Node).call("get_active_spawns").size() == 5, "Der Spawner kennt jetzt 5 aktive Spawnpunkte.")
	await _physics(5)

	# Von jedem Spawnpunkt gibt es einen Weg zum Spieler, in beiden Zonen.
	_all_spawns_reach(_spawn_point(), "Bühne")
	var backstage: Vector3 = door.global_position + Vector3(7.0, 0.0, -1.0)
	_all_spawns_reach(backstage, "Backstage")
	# Der Spieler kann wirklich durch die Türöffnung laufen.
	player.global_position = door.global_position + Vector3(-1.7, 0.0, 0.0)
	player.call("look_at_point", door.global_position + Vector3(5.0, Balance.PLAYER_EYE_HEIGHT, 0.0))
	await _physics(3)
	Input.action_press("move_forward")
	var through: bool = await _wait_until(func() -> bool: return player.global_position.x > door.global_position.x + 1.5, 3.0)
	Input.action_release("move_forward")
	_check(through, "Der Spieler läuft durch die offene Tür in den Backstage-Bereich (x = %.2f)." % player.global_position.x)

	# Kein Schlag durch die Wand: Der Spieler lehnt im Backstage an der Wand zur Bühne, die Zombies
	# aus Gang C laufen auf der anderen Seite an genau dieser Wand entlang zur Tür.
	for type: String in ["sprinter", "elite"]:
		await _wall_lean_attack(type, door)
	_reset_player()

	# Wandkäufe gibt es nicht mehr (Abschnitt 22): Waffen kommen aus Kisten und vom Kandidaten.
	var weapons: Node = _weapons()
	var backpack: RefCounted = _game.get("backpack") as RefCounted
	for node: Node in (_main.get_node("Level") as Node).get_children():
		_check(not String(node.name).begins_with("WallBuy"), "Im Level gibt es keinen Wandkauf mehr (%s)." % node.name)
	# Eine gefundene Waffe kommt als gewöhnlicher Gegenstand in den Rucksack (Game.auto_pack räumt ein).
	for weapon_id: String in ["shotgun", "smg"]:
		_game.call("grant_item", weapon_id, 1)
		_check(int(backpack.call("highest_level", weapon_id)) == 1, "%s liegt als gewöhnlicher Gegenstand im Rucksack." % weapon_id)
		_check(_state() == STATE_PLAYING, "Mit auto_pack läuft das Spiel nach dem Fund weiter.")
		await _frames(2)
	_check(int(backpack.call("hands_used")) <= 2, "Der Spieler hält höchstens zwei Hände voll.")
	# Für die folgenden Prüfungen die Schrotflinte in die Hand nehmen.
	weapons.call("give_weapon", "shotgun")
	await _frames(2)
	_check(String(weapons.call("get_current_weapon_id")) == "shotgun", "Die Schrotflinte ist in der Hand.")
	var shotgun_state: RefCounted = weapons.call("get_state", "shotgun")
	_check(shotgun_state != null and int(shotgun_state.get("mag")) == int(shotgun_state.call("magazine_size")) and int(shotgun_state.get("mag")) >= int(WeaponDefs.get_def("shotgun")["magazine"]),
			"Die Schrotflinte hat ein volles Magazin.")

	# Die Schrotflinte trifft mit mehreren Kugeln.
	_reset_player()
	weapons.call("give_weapon", "shotgun")
	var target: Node3D = _spawn("elite", Vector3(0.0, 0.0, 2.5))
	await _physics(3)
	var hits_before: int = _count("bullet_hit")
	_check(await _fire_at(target.call("get_center_position")), "Die Schrotflinte schießt auf die Elite.")
	var pellets: int = _count("bullet_hit") - hits_before
	_check(pellets >= 4 and pellets <= 8, "Aus 2,5 m treffen die meisten der 8 Schrotkugeln (Treffer: %d)." % pellets)
	await _clear_field()


# --- 7. Zweiter Lauf in derselben Szene -------------------------------------------------------

func _test_second_run_same_scene() -> void:
	# Vorher: Upgrades, Waffen, offene Tür, ein Zombie und eine Kiste.
	var old_backpack: RefCounted = _game.get("backpack")
	var old_drone: int = int(old_backpack.call("add_item", "drone", 1))
	_check(old_drone > 0 and bool(old_backpack.call("auto_place", old_drone)), "Die Kameradrohne passt in den Rucksack.")
	_game.call("sync_build")
	await _set_upgrades({"max_hp": 2})
	_check(is_instance_valid((_main.get("upgrade_effects") as Node).get("drone")), "Vor dem neuen Lauf fliegt eine Drohne.")
	_spawn("walker", Vector3(0.0, 0.0, -1.0))
	(_main.get("chest_dropper") as Node).call("spawn_chest", Vector3(3.0, 0.0, 3.0), Balance.RARITY_GOLD)
	await _physics(3)
	var runs_before: int = _count("run_started")
	_game.call("start_run", SEED)
	await _physics(4)
	_check(_count("run_started") - runs_before == 1, "start_run sendet run_started.")
	_check(get_nodes_in_group("zombies").is_empty() and (_main.get("zombies_root") as Node).get_child_count() == 0, "Der neue Lauf hat keine alten Zombies.")
	_check(get_nodes_in_group("chests").is_empty() and (_main.get("chests_root") as Node).get_child_count() == 0, "Der neue Lauf hat keine alten Kisten.")
	_check(_upgrades().owned_ids().is_empty(), "Der neue Lauf hat keine Upgrades.")
	_check(not is_instance_valid((_main.get("upgrade_effects") as Node).get("drone")), "Die Drohne ist weg.")
	_check(_points() == 0 and int(_game.get("kills")) == 0 and int(_game.get("wave")) == 0, "Punkte, Kills und Welle stehen auf 0.")
	var player: CharacterBody3D = _player()
	_check(_near(float(player.get("hp")), 100.0) and _near(float(player.get("max_hp")), 100.0), "Der Spieler hat wieder 100 von 100 Leben.")
	_check(_flat_distance(player.global_position, _spawn_point()) < 0.05, "Der Spieler steht wieder am Startpunkt.")
	_check(_weapons().call("get_owned_weapon_ids") == ["pistol"], "Der Spieler trägt nur noch die Pistole.")
	var door: Node3D = (_main.get("level_info") as Dictionary)["door"] as Node3D
	_check(not bool(door.get("is_open")) and door.is_in_group("interactables"), "Die Tür ist wieder zu.")
	_check((_main.get("spawner") as Node).call("get_active_spawns").size() == 3, "Die Spawnpunkte der Zone 2 sind wieder aus.")
	_check((_main.get("hud") as Node).get("buff_rows").get_child_count() == 0, "Die Buff-Anzeige des HUD ist leer.")
	var blocked: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			door.global_position + Vector3(-2.0, 1.0, 0.0), door.global_position + Vector3(2.0, 1.0, 0.0), Balance.LAYER_WORLD))
	_check(blocked.get("collider") == door, "Die geschlossene Tür versperrt den Durchgang wieder.")


# --- 8. Drei ganze Wellen ---------------------------------------------------------------------

## Der nächste lebende Zombie, den der Spieler vom Auge aus sehen kann (nur die Welt verdeckt).
func _visible_target() -> Node3D:
	var player: CharacterBody3D = _player()
	var eye: Vector3 = player.call("get_eye_position")
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var best: Node3D = null
	var best_distance: float = INF
	for node: Node in get_nodes_in_group("zombies"):
		var zombie: Node3D = node as Node3D
		if not _alive(zombie):
			continue
		var center: Vector3 = zombie.call("get_center_position")
		var distance: float = eye.distance_to(center)
		if distance >= best_distance:
			continue
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, center, Balance.MASK_LINE_OF_SIGHT)
		if space.intersect_ray(query).is_empty():
			best = zombie
			best_distance = distance
	return best


func _waves_cleared() -> int:
	var highest: int = 0
	for entry: Dictionary in _log.get("wave_cleared", []):
		highest = maxi(highest, int(entry["wave"]))
	return highest


func _test_three_waves() -> void:
	_log["wave_started"] = []
	_log["wave_cleared"] = []
	_log["intermission_tick"] = []
	var manager: Node = _main.get("wave_manager") as Node
	var player: CharacterBody3D = _player()
	var damage_before: int = _count("player_damaged")
	var spawned_before: int = _count("zombie_spawned")
	manager.set("auto_start", true)

	# Countdown, Welle 1 beginnt, der erste Zombie erscheint.
	var started: bool = await _wait_until(func() -> bool: return _count("wave_started") >= 1, Balance.FIRST_WAVE_DELAY + 2.0)
	_check(started, "Welle 1 beginnt nach dem Countdown von selbst.")
	_check(_count("intermission_tick") >= 4, "Der Countdown vor Welle 1 tickt (Ticks: %d)." % _count("intermission_tick"))
	_check(int(_game.get("wave")) == 1, "Game.wave ist 1.")
	var first_wave: Array = _log.get("wave_started", [])
	if not first_wave.is_empty():
		_check(int(first_wave[0]["total"]) == WavePlan.total_count(1), "Welle 1 meldet %d Zombies." % WavePlan.total_count(1))
	var has_zombie: bool = await _wait_until(func() -> bool: return not get_nodes_in_group("zombies").is_empty(), 3.0)
	_check(has_zombie, "Der Spawner bringt den ersten Zombie.")
	if not has_zombie:
		return
	var first: Node3D = get_nodes_in_group("zombies")[0] as Node3D
	_check(bool(first.get_meta("wave_spawn", false)), "Zombies der Welle tragen Meta wave_spawn.")
	var first_id: int = first.get_instance_id()
	var start_distance: float = _flat_distance(first.global_position, player.global_position)
	_check(start_distance > 7.0, "Zombies erscheinen nicht direkt beim Spieler (%.1f m)." % start_distance)

	# Der Spieler tut nichts: Die Zombies kommen heran und schlagen zu.
	var approached: bool = await _wait_until(func() -> bool:
		var zombie: Node3D = instance_from_id(first_id) as Node3D if is_instance_id_valid(first_id) else null
		return zombie == null or _flat_distance(zombie.global_position, player.global_position) < start_distance - 4.0, 12.0)
	_check(approached and is_instance_id_valid(first_id), "Der Zombie läuft auf den Spieler zu.")
	var got_hit: bool = await _wait_until(func() -> bool: return _count("player_damaged") > damage_before, 25.0)
	_check(got_hit, "Ein Zombie erreicht den Spieler und schlägt zu.")
	_check(float(player.get("hp")) < Balance.PLAYER_MAX_HP, "Der Schlag kostet Leben (Leben: %.0f)." % float(player.get("hp")))

	# Ab jetzt schummelt der Spieler: Er heilt sich in jedem Schritt und schießt mit der echten
	# Pistole auf den nächsten sichtbaren Zombie. Kisten nimmt er, wie sie kommen.
	var choice: Node = _main.get("chest_choice") as Node
	var weapons: Node = _weapons()
	var max_steps: int = SIM_TICKS_PER_SECOND * 240
	var steps: int = 0
	var chests_taken: int = 0
	while _waves_cleared() < WAVES_TO_SURVIVE and steps < max_steps and not _out_of_time():
		steps += 1
		if _state() == STATE_CHOOSING:
			choice.call("choose", 0)
			chests_taken += 1
		elif _state() == STATE_PLAYING:
			player.call("heal", 100000.0)
			var target: Node3D = _visible_target()
			if target != null:
				player.call("look_at_point", target.call("get_center_position"))
				weapons.call("try_fire")
		else:
			break
		await physics_frame
	_check(_waves_cleared() >= WAVES_TO_SURVIVE, "Drei Wellen wurden überstanden (geschafft: %d, State %d, nach %.0f s Spielzeit)." % [_waves_cleared(), _state(), float(steps) / 60.0])
	manager.set("auto_start", false)

	var starts: Array = _log.get("wave_started", [])
	var clears: Array = _log.get("wave_cleared", [])
	var expected_kills: int = 0
	for wave: int in range(1, WAVES_TO_SURVIVE + 1):
		expected_kills += WavePlan.total_count(wave)
		var start_count: int = 0
		for entry: Dictionary in starts:
			if int(entry["wave"]) == wave:
				start_count += 1
				_check(int(entry["total"]) == WavePlan.total_count(wave), "Welle %d meldet %d Zombies." % [wave, WavePlan.total_count(wave)])
		_check(start_count == 1, "Welle %d begann genau einmal (war %d)." % [wave, start_count])
		for entry: Dictionary in clears:
			if int(entry["wave"]) == wave:
				_check(int(entry["alive"]) == 0, "Am Ende von Welle %d lebt kein Zombie mehr (waren %d)." % [wave, int(entry["alive"])])
	_check(clears.size() == WAVES_TO_SURVIVE, "wave_cleared kam je Welle einmal (war %d)." % clears.size())
	if clears.size() >= WAVES_TO_SURVIVE:
		var kills_at_end: int = int(clears[WAVES_TO_SURVIVE - 1]["kills"])
		_check(kills_at_end == expected_kills, "Nach drei Wellen stehen %d Kills (waren %d): kein Zombie ging verloren." % [expected_kills, kills_at_end])
	_check(int(manager.get("zombies_left")) == 0 and not bool(manager.get("is_wave_active")), "Der WaveManager steht zwischen den Wellen.")
	_check(float(manager.call("get_countdown")) > 0.0, "Der Countdown zur nächsten Welle läuft.")
	_check(_count("chest_dropped") > 0, "In drei Wellen fielen Kisten (sichere Kiste der Welle 1, Elite).")
	print("  Wellen 1-3: %.0f s Spielzeit, %d Kills, %d Punkte, %d Kisten gewählt, Upgrades %s" % [
		float(steps) / float(SIM_TICKS_PER_SECOND), int(_game.get("kills")), int(_game.get("total_points_earned")), chests_taken, str(_upgrades().summary())])


# --- 9. Tod und Game Over ---------------------------------------------------------------------

func _test_death_and_game_over() -> void:
	if _state() != STATE_PLAYING:
		_check(false, "Vor dem Tod-Test läuft das Spiel nicht (State %d)." % _state())
		return
	var player: CharacterBody3D = _player()
	var died_before: int = _count("player_died")
	var over_before: int = _count("game_over")
	# Vier Schlurfer rund um den Spieler, niemand schießt, niemand heilt.
	for offset: Vector3 in [Vector3(1.3, 0.0, 0.0), Vector3(-1.3, 0.0, 0.0), Vector3(0.0, 0.0, 1.3), Vector3(0.0, 0.0, -1.3)]:
		_spawn("walker", player.global_position + offset, 3)
	var over: bool = await _wait_until(func() -> bool: return _state() == STATE_GAME_OVER, 90.0)
	_check(over, "Ohne Gegenwehr stirbt der Spieler: State GAME_OVER.")
	if not over:
		return
	_check(bool(player.get("is_dead")) and float(player.get("hp")) <= 0.0, "Der Spieler ist tot.")
	_check(_count("player_died") - died_before == 1, "player_died kam genau einmal.")
	_check(_count("game_over") - over_before == 1, "game_over kam genau einmal.")
	_check(paused, "Game Over pausiert das Spiel.")
	var screen: Node = _main.get("game_over") as Node
	_check(bool(screen.call("is_open")), "Der Game-Over-Bildschirm ist offen.")
	var stats: Dictionary = (_since("game_over", _count("game_over") - 1)[0] as Dictionary)["stats"]
	_check(int(stats.get("wave", -1)) == WAVES_TO_SURVIVE, "Die Statistik nennt Welle %d (war %s)." % [WAVES_TO_SURVIVE, str(stats.get("wave"))])
	_check(int(stats.get("kills", -1)) == int(_game.get("kills")) and int(stats["kills"]) > 0, "Die Statistik nennt die Kills (%s)." % str(stats.get("kills")))
	_check(int(stats.get("points", -1)) == int(_game.get("total_points_earned")) and int(stats["points"]) > 0, "Die Statistik nennt die verdienten Punkte (%s)." % str(stats.get("points")))
	_check((stats.get("upgrades", []) as Array).size() == _upgrades().owned_ids().size(), "Die Statistik nennt die Upgrades.")
	_check((screen.get("stats") as Dictionary) == stats, "Der Bildschirm zeigt genau diese Statistik.")
	_check((screen.get("wave_value_label") as Label).text.contains(str(WAVES_TO_SURVIVE)), "Der Bildschirm zeigt die Welle.")
	# Nach dem Tod passiert nichts mehr.
	var weapons: Node = _weapons()
	_check(not bool(weapons.call("try_fire")), "Ein Toter schießt nicht.")
	player.call("take_damage", 50.0)
	_check(_count("player_died") - died_before == 1, "Ein Toter stirbt nicht noch einmal.")


# --- 10. Neustart -----------------------------------------------------------------------------

func _test_restart_is_clean() -> void:
	var old_id: int = _main.get_instance_id()
	_main = null
	var connections_before: int = _events.get_signal_connection_list("zombie_killed").size()
	_game.call("restart_run")
	var reloaded: bool = await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and not is_instance_id_valid(old_id) \
			and _state() == STATE_PLAYING and is_instance_valid(_game.get("player")), 5.0)
	_check(reloaded, "Neustart lädt die Szene neu und startet einen Lauf.")
	if not reloaded:
		return
	_main = current_scene
	(_main.get("wave_manager") as Node).set("auto_start", false)
	await _physics(4)
	_check(not paused, "Nach dem Neustart ist keine Pause.")
	_check(get_nodes_in_group("main").size() == 1, "Es gibt genau eine Hauptszene.")
	_check(get_nodes_in_group("player").size() == 1, "Es gibt genau einen Spieler.")
	_check(get_nodes_in_group("zombies").is_empty(), "Nach dem Neustart gibt es keine Zombies.")
	_check(get_nodes_in_group("chests").is_empty(), "Nach dem Neustart gibt es keine Kisten.")
	_check(_upgrades().owned_ids().is_empty() and _upgrades().active_synergies().is_empty(), "Nach dem Neustart gibt es keine Upgrades.")
	_check(_points() == 0 and int(_game.get("kills")) == 0 and int(_game.get("wave")) == 0 and int(_game.get("total_points_earned")) == 0,
			"Punkte, Kills und Welle stehen auf 0.")
	var player: CharacterBody3D = _player()
	_check(not bool(player.get("is_dead")) and _near(float(player.get("hp")), 100.0) and _near(float(player.get("max_hp")), 100.0), "Der Spieler lebt mit 100 von 100.")
	_check(_weapons().call("get_owned_weapon_ids") == ["pistol"], "Der Spieler trägt nur die Pistole.")
	_check((_main.get("spawner") as Node).call("get_active_spawns").size() == 3, "Nur die Spawnpunkte der Zone 1 sind aktiv.")
	_check(not bool((_main.get("game_over") as Node).call("is_open")), "Der Game-Over-Bildschirm ist zu.")
	_check((_main.get("fx_root") as Node).get_node_or_null("Drone") == null, "Es gibt keine Drohne.")
	_check((_main.get("hud") as Node).get("buff_rows").get_child_count() == 0, "Die Buff-Anzeige ist leer.")
	var connections_after: int = _events.get_signal_connection_list("zombie_killed").size()
	_check(connections_after == connections_before, "Kein Empfänger von zombie_killed blieb doppelt zurück (%d -> %d)." % [connections_before, connections_after])

	# Ein Kill gibt genau einmal Punkte und zählt genau einmal.
	var target: Node3D = _spawn("walker", Vector3(0.0, 0.0, 1.0))
	await _physics(3)
	var kills_logged: int = _count("zombie_killed")
	target.call("take_damage", HUGE_DAMAGE, {"source": "bullet", "headshot": false, "weapon_id": "pistol"})
	_check(_points() == Balance.POINTS_BULLET_HIT + Balance.POINTS_KILL, "Ein Kugel-Kill gibt nach dem Neustart genau %d Punkte (waren %d)." % [Balance.POINTS_BULLET_HIT + Balance.POINTS_KILL, _points()])
	_check(int(_game.get("kills")) == 1, "Der Kill zählt genau einmal.")
	_check(_count("zombie_killed") - kills_logged == 1, "zombie_killed kam genau einmal.")
	# Die Wellen laufen im neuen Lauf wieder an.
	var starts_before: int = _count("wave_started")
	(_main.get("wave_manager") as Node).set("auto_start", true)
	var started: bool = await _wait_until(func() -> bool: return _count("wave_started") > starts_before, Balance.FIRST_WAVE_DELAY + 2.0)
	_check(started and int(_game.get("wave")) == 1, "Im neuen Lauf beginnt wieder Welle 1.")
	(_main.get("wave_manager") as Node).set("auto_start", false)
