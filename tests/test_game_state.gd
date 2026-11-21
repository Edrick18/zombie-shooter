extends SceneTree
## Tests für die Autoloads Game und Events und für die Projekteinstellungen:
## InputMap, Kollisionslagen, Signalliste, Punkte-Regeln, Kistenwahl, Pause, Game Over, Neustart.
##
## Startet in _initialize und wartet ein Bild: Erst dann hängen die Autoloads im Baum und haben
## ihr _ready hinter sich. Sie werden über root.get_node geholt, weil ein -s-Skript die Namen
## Game und Events beim Übersetzen nicht kennt.

const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")


## Ersatz-Zombie: Game liest nur zombie_type.
class FakeZombie:
	extends Node3D
	var zombie_type: String = "walker"


## Ersatz-Spieler: merkt sich die Heilung.
class FakePlayer:
	extends Node3D
	var healed: float = 0.0

	func heal(amount: float) -> void:
		healed += amount


var _failures := 0
var _game: Node
var _events: Node
## Signalname -> Liste der Argument-Listen, in der Reihenfolge des Eintreffens.
var _received: Dictionary = {}


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
		_test_project_settings()
		_test_input_map()
		_test_event_signals()
		_test_initial_and_start()
		_test_points()
		_test_hit_and_kill_points()
		_test_wave_tracking()
		_test_chest_choice()
		_test_synergy_signal()
		_test_consolation_prizes()
		_test_pause()
		_test_end_run()
		_test_restart()
		paused = false

	if _failures == 0:
		print("Alle Spielzustand-Tests bestanden.")
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


func _listen() -> void:
	_events.connect("points_changed", func(total: int) -> void: _record("points_changed", [total]))
	_events.connect("run_started", func() -> void: _record("run_started", []))
	_events.connect("chest_opened", func(rarity: int, offers: Array) -> void: _record("chest_opened", [rarity, offers]))
	_events.connect("upgrade_chosen", func(id: String, level: int) -> void: _record("upgrade_chosen", [id, level]))
	_events.connect("synergy_unlocked", func(id: String) -> void: _record("synergy_unlocked", [id]))
	_events.connect("game_over", func(stats: Dictionary) -> void: _record("game_over", [stats]))
	_events.connect("backpack_opened", func(uid: int) -> void: _record("backpack_opened", [uid]))
	_events.connect("backpack_closed", func() -> void: _record("backpack_closed", []))


func _record(signal_name: String, args: Array) -> void:
	if not _received.has(signal_name):
		_received[signal_name] = []
	(_received[signal_name] as Array).append(args)


func _count(signal_name: String) -> int:
	return (_received.get(signal_name, []) as Array).size()


func _last(signal_name: String) -> Array:
	var list: Array = _received.get(signal_name, [])
	return list[list.size() - 1] if not list.is_empty() else []


func _test_project_settings() -> void:
	_check(ProjectSettings.get_setting("application/config/name") == "Zombie-Shooter", "Projektname ist Zombie-Shooter.")
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn", "Hauptszene ist scenes/main.tscn.")
	_check(ResourceLoader.exists("res://scenes/main.tscn"), "Die Hauptszene existiert.")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "Renderer gl_compatibility.")
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 1280 and int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 720, "Fenster 1280 x 720.")
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items", "Stretch-Modus canvas_items.")
	_check(ProjectSettings.get_setting("display/window/stretch/aspect") == "expand", "Stretch-Aspekt expand.")
	_check(String(ProjectSettings.get_setting("autoload/Events")).ends_with("res://scripts/autoload/events.gd"), "Autoload Events eingetragen.")
	_check(String(ProjectSettings.get_setting("autoload/Game")).ends_with("res://scripts/autoload/game.gd"), "Autoload Game eingetragen.")
	var layers: Array[String] = ["world", "player", "zombies", "pickups", "interactables", "player_block"]
	for i: int in layers.size():
		var setting: String = "layer_names/3d_physics/layer_%d" % (i + 1)
		_check(ProjectSettings.get_setting(setting) == layers[i], "Kollisionslage %d heißt %s, war '%s'." % [i + 1, layers[i], ProjectSettings.get_setting(setting)])
	_check(Balance.LAYER_WORLD == 1 and Balance.LAYER_PLAYER == 2 and Balance.LAYER_ZOMBIES == 4 and Balance.LAYER_PICKUPS == 8 and Balance.LAYER_INTERACTABLES == 16 and Balance.LAYER_PLAYER_BLOCK == 32, "Bitwerte der Lagen 1 bis 6.")
	_check(Balance.MASK_PLAYER == 37 and Balance.MASK_ZOMBIE == 7 and Balance.MASK_SHOT == 5 and Balance.MASK_INTERACT == 17 and Balance.MASK_CHEST == 2, "Masken laut Abschnitt 4.")


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


## Jede Aktion aus Abschnitt 5 existiert und reagiert auf genau ihre Taste (von jedem Gerät).
func _test_input_map() -> void:
	var expected: Dictionary = {
		"move_forward": _key(KEY_W),
		"move_back": _key(KEY_S),
		"move_left": _key(KEY_A),
		"move_right": _key(KEY_D),
		"jump": _key(KEY_SPACE),
		"sprint": _key(KEY_SHIFT),
		"fire": _mouse(MOUSE_BUTTON_LEFT),
		"reload": _key(KEY_R),
		"interact": _key(KEY_E),
		"weapon_next": _mouse(MOUSE_BUTTON_WHEEL_UP),
		"weapon_prev": _mouse(MOUSE_BUTTON_WHEEL_DOWN),
		"weapon_1": _key(KEY_1),
		"weapon_2": _key(KEY_2),
		"weapon_3": _key(KEY_3),
		"pause": _key(KEY_ESCAPE),
		"backpack": _key(KEY_TAB),
	}
	for action: String in expected:
		_check(InputMap.has_action(action), "Eingabe-Aktion %s fehlt." % action)
		if not InputMap.has_action(action):
			continue
		_check(InputMap.action_get_events(action).size() == 1, "Aktion %s hat genau eine Belegung." % action)
		var event: InputEvent = expected[action]
		_check(InputMap.event_is_action(event, action), "Aktion %s reagiert auf ihre Taste." % action)
		for device: int in [0, 1, 16, 32]:
			event.device = device
			_check(InputMap.event_is_action(event, action), "Aktion %s reagiert auch auf Gerät %d." % [action, device])
		for other: String in expected:
			if other != action:
				_check(not InputMap.event_is_action(event, other), "Die Taste von %s löst nicht %s aus." % [action, other])


## Events hat genau die Signale aus Abschnitt 6 mit der richtigen Zahl an Argumenten.
func _test_event_signals() -> void:
	var expected: Dictionary = {
		"points_changed": 1, "banner": 1, "wave_started": 2, "wave_cleared": 1,
		"intermission_tick": 1, "zombies_left_changed": 1, "zombie_spawned": 1,
		"zombie_damaged": 3, "zombie_killed": 2, "bullet_hit": 3,
		"player_health_changed": 2, "player_damaged": 1, "player_died": 0,
		"weapon_changed": 1, "ammo_changed": 2, "weapon_fired": 1,
		"reload_started": 2, "reload_finished": 1, "chest_dropped": 1, "chest_opened": 2,
		"upgrade_chosen": 2, "synergy_unlocked": 1, "interact_prompt_changed": 1,
		"game_over": 1, "run_started": 0,
		"build_changed": 0, "backpack_opened": 1, "backpack_closed": 0,
		"loadout_changed": 0, "hand_ammo_changed": 3, "hand_reload_started": 2, "hand_reload_finished": 1,
	}
	var found: Dictionary = {}
	for entry: Dictionary in (_events.get_script() as Script).get_script_signal_list():
		found[String(entry["name"])] = (entry["args"] as Array).size()
	for signal_name: String in expected:
		_check(found.has(signal_name), "Signal %s fehlt in Events." % signal_name)
		if found.has(signal_name):
			_check(int(found[signal_name]) == int(expected[signal_name]), "Signal %s hat %d Argumente, erwartet %d." % [signal_name, found[signal_name], expected[signal_name]])
	for signal_name: String in found:
		_check(expected.has(signal_name), "Signal %s steht nicht im Vertrag." % signal_name)
	_check(found.size() == 32, "Events hat genau 32 Signale, waren %d." % found.size())


func _test_initial_and_start() -> void:
	var state_enum: Dictionary = _game.State
	_check(state_enum.keys() == ["MENU", "PLAYING", "CHOOSING", "PAUSED", "GAME_OVER", "PACKING"], "State hat MENU, PLAYING, CHOOSING, PAUSED, GAME_OVER, PACKING.")
	_check(_game.state == _game.State.MENU, "Vor dem Start ist der State MENU.")
	_check(_game.upgrades != null and _game.rng != null, "Upgrades und Zufall sind schon vor dem Start vorhanden.")
	_check(_game.player == null, "Ohne Spieler ist Game.player null.")
	_game.points = 123
	_game.kills = 4
	_game.wave = 3
	_game.total_points_earned = 999
	_game.upgrades.add_levels("burn", 2)
	var old_upgrades: RefCounted = _game.upgrades
	var runs_before: int = _count("run_started")
	_game.start_run(42)
	_check(_game.state == _game.State.PLAYING, "Nach start_run ist der State PLAYING.")
	_check(not paused, "Nach start_run ist die Pause aus.")
	_check(_game.points == 0 and _game.kills == 0 and _game.wave == 0 and _game.total_points_earned == 0, "start_run setzt Punkte, Kills und Welle zurück.")
	_check(_game.upgrades != old_upgrades and _game.upgrades.owned_ids().is_empty(), "start_run legt die Upgrades neu an.")
	_check(_count("run_started") == runs_before + 1, "start_run sendet run_started genau einmal.")
	_check(_last("points_changed") == [0], "start_run sendet points_changed(0).")
	var first_roll: int = _game.rng.randi()
	_game.start_run(42)
	_check(_game.rng.randi() == first_roll, "Gleicher Seed ergibt denselben Zufall.")
	_game.start_run(43)
	_check(_game.rng.randi() != first_roll, "Anderer Seed ergibt anderen Zufall.")
	_game.start_run()
	_check(_game.state == _game.State.PLAYING, "start_run ohne Seed läuft auch.")


func _test_points() -> void:
	_game.start_run(1)
	_check(not _game.can_afford(1) and _game.can_afford(0), "Mit 0 Punkten ist nur Gratis bezahlbar.")
	_check(not _game.spend_points(10) and _game.points == 0, "Ohne Punkte kein Kauf.")
	var changes: int = _count("points_changed")
	_game.add_points(100)
	_check(_game.points == 100 and _game.total_points_earned == 100, "add_points schreibt gut.")
	_check(_count("points_changed") == changes + 1 and _last("points_changed") == [100], "add_points sendet points_changed mit dem Stand.")
	_game.add_points(0)
	_game.add_points(-50)
	_check(_game.points == 100 and _count("points_changed") == changes + 1, "0 oder negative Punkte ändern nichts.")
	_check(_game.can_afford(100) and not _game.can_afford(101) and not _game.can_afford(-1), "can_afford prüft den Stand.")
	_check(_game.spend_points(60) and _game.points == 40, "spend_points zieht ab.")
	_check(_last("points_changed") == [40], "spend_points sendet points_changed.")
	_check(_game.total_points_earned == 100, "Ausgeben ändert die verdienten Punkte nicht.")
	_check(not _game.spend_points(41) and _game.points == 40, "Zu teuer: nichts passiert.")
	_check(not _game.spend_points(-5) and _game.points == 40, "Negativer Preis: nichts passiert.")
	_check(_game.spend_points(40) and _game.points == 0, "Genau passend geht.")
	# Punkte-Faktor aus dem Upgrade "luck".
	_game.upgrades.add_levels("luck", 1)
	_game.add_points(10)
	_check(_game.points == 11, "Glück 1: 10 Punkte werden 11, waren %d." % _game.points)
	_game.upgrades.add_levels("luck", 4)
	_game.add_points(60)
	_check(_game.points == 11 + 90, "Glück 5: 60 Punkte werden 90, Stand war %d." % _game.points)
	_check(_game.total_points_earned == 100 + 11 + 90, "Verdiente Punkte zählen mit Faktor.")


func _test_hit_and_kill_points() -> void:
	_game.start_run(2)
	var walker: FakeZombie = FakeZombie.new()
	var elite: FakeZombie = FakeZombie.new()
	elite.zombie_type = "elite"
	var sprinter: FakeZombie = FakeZombie.new()
	sprinter.zombie_type = "sprinter"
	_events.emit_signal("zombie_damaged", walker, 25.0, {"source": "bullet"})
	_check(_game.points == 10, "Kugeltreffer gibt 10 Punkte, waren %d." % _game.points)
	_events.emit_signal("zombie_damaged", walker, 999.0, {"source": "bullet", "headshot": true})
	_check(_game.points == 20, "Treffer-Punkte hängen nicht vom Schaden ab.")
	for source: String in ["lightning", "burn", "explosion", "shockwave", "drone"]:
		_events.emit_signal("zombie_damaged", walker, 25.0, {"source": source})
	_events.emit_signal("zombie_damaged", walker, 25.0, {})
	_check(_game.points == 20, "Nur Kugeln geben Treffer-Punkte, Stand war %d." % _game.points)
	_check(_game.kills == 0, "Treffer zählen nicht als Kill.")

	_game.start_run(2)
	_events.emit_signal("zombie_killed", walker, {"source": "bullet"})
	_check(_game.points == 60 and _game.kills == 1, "Kill gibt 60 Punkte, waren %d." % _game.points)
	_events.emit_signal("zombie_killed", sprinter, {"source": "bullet", "headshot": true})
	_check(_game.points == 60 + 90 and _game.kills == 2, "Kopfschuss-Kill gibt 90 Punkte, Stand war %d." % _game.points)
	_events.emit_signal("zombie_killed", elite, {"source": "bullet"})
	_check(_game.points == 150 + 150 and _game.kills == 3, "Elite-Kill gibt 150 statt 60, Stand war %d." % _game.points)
	_events.emit_signal("zombie_killed", elite, {"source": "bullet", "headshot": true})
	_check(_game.points == 300 + 180 and _game.kills == 4, "Elite-Kopfschuss-Kill gibt 180, Stand war %d." % _game.points)
	_events.emit_signal("zombie_killed", walker, {"source": "burn"})
	_check(_game.points == 480 + 60 and _game.kills == 5, "Kills durch Effekte geben Kill-Punkte, Stand war %d." % _game.points)
	_events.emit_signal("zombie_killed", null, {"source": "explosion"})
	_check(_game.points == 540 + 60 and _game.kills == 6, "Ein schon verschwundener Zombie zählt als normaler Kill.")

	# Ein ganzer Kugel-Kill mit Glück 5: Treffer 10 und Kill 60, beide mal 1,5.
	_game.start_run(2)
	_game.upgrades.add_levels("luck", 5)
	_events.emit_signal("zombie_damaged", walker, 25.0, {"source": "bullet"})
	_events.emit_signal("zombie_killed", walker, {"source": "bullet"})
	_check(_game.points == 15 + 90, "Mit Glück 5 geben Treffer 15 und Kill 90, Stand war %d." % _game.points)
	walker.free()
	elite.free()
	sprinter.free()


func _test_wave_tracking() -> void:
	_game.start_run(3)
	_check(_game.wave == 0, "Vor der ersten Welle ist wave 0.")
	_check(is_equal_approx(_game.effect_factor(), 1.0), "Effekt-Faktor vor der ersten Welle ist 1.")
	_events.emit_signal("wave_started", 4, 22)
	_check(_game.wave == 4, "wave_started setzt Game.wave.")
	_events.emit_signal("wave_started", 10, 49)
	_check(is_equal_approx(_game.effect_factor(), 1.56), "Effekt-Faktor in Welle 10 ist 1,56, war %s." % _game.effect_factor())
	_check(_game.is_playing(), "is_playing im State PLAYING.")


func _test_chest_choice() -> void:
	_game.start_run(4)
	var opened_before: int = _count("chest_opened")
	var chosen_before: int = _count("upgrade_chosen")
	_game.open_chest(1)
	_check(_game.state == _game.State.CHOOSING, "open_chest: State CHOOSING.")
	_check(paused, "open_chest pausiert das Spiel.")
	_check(not _game.is_playing(), "In der Kistenwahl läuft das Spiel nicht.")
	_check(_count("chest_opened") == opened_before + 1, "open_chest sendet chest_opened genau einmal.")
	var args: Array = _last("chest_opened")
	_check(int(args[0]) == 1, "chest_opened nennt die Seltenheit.")
	var offers: Array = args[1]
	_check(offers.size() == 3 and offers == _game.current_offers, "chest_opened liefert die 3 Angebote aus Game.current_offers.")
	_check(_game.current_rarity == 1, "Game.current_rarity ist gesetzt.")
	for offer: Dictionary in offers:
		_check(offer["kind"] == "item" and int(offer["owned_level"]) == 0, "Die Kiste bietet Gegenstände an, die noch keiner hat: %s." % [offer])
		var wanted_level: int = 2 if ItemDefs.is_upgrade(String(offer["id"])) else 1
		_check(int(offer["level"]) == wanted_level, "Silber-Kiste: Upgrade-Gegenstände auf Stufe 2, alles andere 1: %s." % [offer])

	_game.open_chest(2)
	_check(_count("chest_opened") == opened_before + 1 and _game.current_rarity == 1, "Eine zweite Kiste öffnet sich während der Wahl nicht.")
	_game.set_paused(false)
	_check(_game.state == _game.State.CHOOSING and paused, "Das Pausemenü greift in der Kistenwahl nicht.")
	_game.choose_offer(3)
	_game.choose_offer(-1)
	_check(_game.state == _game.State.CHOOSING and _count("upgrade_chosen") == chosen_before, "Ein ungültiger Index ändert nichts.")

	# Die Wahl legt den Gegenstand in die Ablage und öffnet den Rucksack.
	var picked: Dictionary = offers[1]
	var picked_id: String = String(picked["id"])
	var opened_packs: int = _count("backpack_opened")
	_game.choose_offer(1)
	_check(_game.state == _game.State.PACKING and paused, "Nach der Wahl: PACKING, weiter pausiert.")
	_check(_count("backpack_opened") == opened_packs + 1, "backpack_opened kam genau einmal.")
	var uid: int = int(_last("backpack_opened")[0])
	_check(String(_game.backpack.item(uid).get("id", "")) == picked_id and not _game.backpack.is_placed(uid), "Der gewählte Gegenstand liegt in der Ablage.")
	_check(_game.current_offers.is_empty(), "Nach der Wahl sind die Angebote leer.")
	_check(_count("upgrade_chosen") == chosen_before, "Vor dem Einräumen kommt kein upgrade_chosen.")
	_game.set_paused(false)
	_check(_game.state == _game.State.PACKING and paused, "Das Pausemenü greift bei offenem Rucksack nicht.")
	_game.open_chest(0)
	_check(_game.state == _game.State.PACKING, "Bei offenem Rucksack öffnet sich keine Kiste.")
	_check(_game.backpack.auto_place(uid), "Der Gegenstand lässt sich einräumen.")
	_game.sync_build()
	_check(_game.close_backpack(), "close_backpack schließt den Rucksack.")
	_check(_game.state == _game.State.PLAYING and not paused, "Nach dem Schließen: PLAYING, Pause aus.")
	_check(_count("backpack_closed") >= 1, "backpack_closed kam.")
	if ItemDefs.is_upgrade(picked_id):
		_check(_game.upgrades.get_level(picked_id) == 2, "Das gewählte Upgrade wirkt mit Stufe 2.")
		_check(_last("upgrade_chosen") == [picked_id, 2], "upgrade_chosen nennt ID und neue Stufe, war %s." % [_last("upgrade_chosen")])
		_check(_count("upgrade_chosen") == chosen_before + 1, "upgrade_chosen kam genau einmal.")
	else:
		_check(_count("upgrade_chosen") == chosen_before, "Verstärker und Rucksack-Teile senden kein upgrade_chosen.")
	var owned_before: int = _game.upgrades.owned_ids().size()
	_game.choose_offer(0)
	_check(_game.upgrades.owned_ids().size() == owned_before and _game.state == _game.State.PLAYING, "Ohne offene Kiste bewirkt choose_offer nichts.")

	# Gold-Kiste: Upgrade-Gegenstände auf Stufe 3. Mit auto_pack geht es ohne Rucksack weiter.
	_game.start_run(4)
	_game.auto_pack = true
	_game.open_chest(2)
	var gold_index: int = 0
	for i: int in _game.current_offers.size():
		if ItemDefs.is_upgrade(String(_game.current_offers[i]["id"])):
			gold_index = i
	var gold: Dictionary = _game.current_offers[gold_index]
	_check(ItemDefs.is_upgrade(String(gold["id"])) and int(gold["level"]) == 3, "Gold bietet einen Upgrade-Gegenstand der Stufe 3 an.")
	_game.choose_offer(gold_index)
	_check(_game.state == _game.State.PLAYING and not paused, "Mit auto_pack läuft das Spiel nach der Wahl sofort weiter.")
	_check(_game.upgrades.get_level(String(gold["id"])) == 3, "Das Upgrade wirkt mit Stufe 3.")
	_check(_last("upgrade_chosen") == [String(gold["id"]), 3], "upgrade_chosen meldet Stufe 3.")
	# Derselbe Gegenstand in derselben Rarität noch einmal: Die beiden werden zu einem der
	# nächsten Rarität kombiniert (Selten + Selten = Episch).
	_game.open_chest(2)
	_game.current_offers[0] = {"kind": "item", "id": String(gold["id"]), "level": 3, "owned_level": 3}
	_game.choose_offer(0)
	_check(_game.upgrades.get_level(String(gold["id"])) == 4, "Zwei Seltene werden Episch.")
	_check(_game.backpack.placed_items().size() == 1, "Kombiniert bleibt es ein Gegenstand.")
	_check(_last("upgrade_chosen") == [String(gold["id"]), 4], "upgrade_chosen meldet die neue Rarität.")
	# Eine andere Rarität lässt sich nicht kombinieren: Der Gegenstand liegt dann einzeln daneben.
	_game.open_chest(0)
	_game.current_offers[0] = {"kind": "item", "id": String(gold["id"]), "level": 1, "owned_level": 4}
	_game.choose_offer(0)
	_check(_game.backpack.placed_items().size() == 2 and _game.upgrades.get_level(String(gold["id"])) == 4, "Gewöhnlich neben Episch: zwei Gegenstände, es zählt der bessere.")
	# Kette: Zwei Gewöhnliche werden Ungewöhnlich und kombinieren sich gleich weiter, wenn schon
	# ein Ungewöhnlicher daliegt.
	_game.start_run(4)
	var chain_id: String = "luck"
	for chain_level: int in [2, 1, 1]:
		_game.open_chest(0)
		_game.current_offers[0] = {"kind": "item", "id": chain_id, "level": chain_level, "owned_level": 0}
		_game.choose_offer(0)
	_check(_game.backpack.placed_items().size() == 1 and _game.upgrades.get_level(chain_id) == 3, "Ungewöhnlich, Gewöhnlich, Gewöhnlich ergibt mit auto_pack einen Seltenen.")

	# Seltenheit außerhalb 0 bis 2 wird begrenzt.
	_game.start_run(4)
	_game.open_chest(7)
	_check(_game.current_rarity == 2, "Seltenheit 7 zählt als Gold.")
	_game.choose_offer(0)
	_check(_game.state == _game.State.PLAYING, "Mit auto_pack läuft das Spiel weiter.")
	_game.auto_pack = false


func _test_synergy_signal() -> void:
	_game.start_run(5)
	_game.auto_pack = true
	# Blitz Legendär und Durchschlag Episch liegen nebeneinander: Ein zweiter epischer Durchschlag
	# aus der Kiste macht ihn Legendär.
	# Der Rucksack ohne Kandidat hat die Felder (1, 1) bis (4, 3). Beide Gegenstände wirken über
	# ihre Sterne auf die Pistole.
	var pistol: int = _game.backpack.add_item("pistol", 1)
	var chain: int = _game.backpack.add_item("chain_lightning", 5)
	var pierce: int = _game.backpack.add_item("pierce", 4)
	_check(_game.backpack.place(pistol, Vector2i(2, 2), 0) and _game.backpack.place(chain, Vector2i(1, 2), 0) and _game.backpack.place(pierce, Vector2i(2, 3), 0), "Pistole, Blitz und Durchschlag einräumen.")
	_game.sync_build()
	_check(_count("synergy_unlocked") == 0 and not _game.upgrades.has_synergy("storm_front"), "Mit Durchschlag 4 gibt es noch keine Synergie.")
	_game.open_chest(0)
	_game.current_offers[0] = {"kind": "item", "id": "pierce", "level": 4, "owned_level": 4}
	_game.choose_offer(0)
	_check(_game.upgrades.get_level("pierce") == 5, "pierce steht auf Stufe 5.")
	_check(_count("synergy_unlocked") == 1 and _last("synergy_unlocked") == ["storm_front"], "synergy_unlocked(storm_front) kam genau einmal.")
	_check(_game.upgrades.has_synergy("storm_front"), "Die Gewitterfront ist aktiv.")
	_game.open_chest(0)
	_game.choose_offer(0)
	_check(_count("synergy_unlocked") == 1, "Die Synergie wird kein zweites Mal gemeldet.")
	_game.auto_pack = false


func _test_consolation_prizes() -> void:
	# Trostpreise kommen nur, wenn die Auswahl an Gegenständen nicht für 3 reicht. Hier werden
	# sie von Hand ins Angebot gelegt.
	_game.start_run(6)
	var fake_player: FakePlayer = FakePlayer.new()
	_game.player = fake_player
	var chosen_before: int = _count("upgrade_chosen")

	_game.open_chest(2)
	_game.current_offers[0] = {"kind": "points", "amount": 500}
	_game.choose_offer(0)
	_check(_game.points == 500 and _game.total_points_earned == 500, "Punkte-Trostpreis gibt genau 500 (ohne Glück-Faktor), waren %d." % _game.points)
	_check(_game.state == _game.State.PLAYING and not paused, "Nach dem Trostpreis läuft das Spiel weiter.")

	_game.open_chest(0)
	_game.current_offers[1] = {"kind": "heal", "amount": 50}
	_game.choose_offer(1)
	_check(is_equal_approx(fake_player.healed, 50.0), "Heil-Trostpreis heilt den Spieler um 50, war %s." % fake_player.healed)
	_check(_game.points == 500, "Heilung gibt keine Punkte.")
	_check(_count("upgrade_chosen") == chosen_before, "Trostpreise senden kein upgrade_chosen.")

	# Ohne Spieler stürzt die Heilung nicht ab.
	_game.player = null
	_game.open_chest(0)
	_game.current_offers[1] = {"kind": "heal", "amount": 50}
	_game.choose_offer(1)
	_check(_game.state == _game.State.PLAYING, "Heil-Trostpreis ohne Spieler ist harmlos.")
	# Ein schon freigegebener Spieler ebenso.
	_game.player = fake_player
	fake_player.free()
	_game.open_chest(0)
	_game.current_offers[1] = {"kind": "heal", "amount": 50}
	_game.choose_offer(1)
	_check(_game.state == _game.State.PLAYING, "Heil-Trostpreis mit freigegebenem Spieler ist harmlos.")
	_game.player = null


func _test_pause() -> void:
	_game.start_run(7)
	_game.set_paused(false)
	_check(_game.state == _game.State.PLAYING and not paused, "Weiter ohne Pause ändert nichts.")
	_game.set_paused(true)
	_check(_game.state == _game.State.PAUSED and paused, "set_paused(true): PAUSED und Baum pausiert.")
	_game.set_paused(true)
	_check(_game.state == _game.State.PAUSED and paused, "Doppelt pausieren ändert nichts.")
	_game.open_chest(0)
	_check(_game.state == _game.State.PAUSED, "In der Pause öffnet sich keine Kiste.")
	_game.set_paused(false)
	_check(_game.state == _game.State.PLAYING and not paused, "set_paused(false): PLAYING und Baum läuft.")


func _test_end_run() -> void:
	_game.start_run(8)
	_game.upgrades.add_levels("drone", 2)
	_game.upgrades.add_levels("chain_lightning", 5)
	_game.upgrades.add_levels("pierce", 5)
	_events.emit_signal("wave_started", 5, 26)
	_game.add_points(700)
	_game.spend_points(500)
	_events.emit_signal("zombie_killed", null, {"source": "bullet"})
	var overs: int = _count("game_over")
	_events.emit_signal("player_died")
	_check(_game.state == _game.State.GAME_OVER, "player_died führt zu GAME_OVER.")
	_check(paused, "Game Over pausiert das Spiel.")
	_check(_count("game_over") == overs + 1, "game_over kam genau einmal.")
	var stats: Dictionary = _last("game_over")[0]
	for key: String in ["wave", "kills", "points", "upgrades"]:
		_check(stats.has(key), "stats hat den Schlüssel %s." % key)
	_check(int(stats["wave"]) == 5 and int(stats["kills"]) == 1, "stats: Welle 5, 1 Kill, war %s." % [stats])
	_check(int(stats["points"]) == 760, "stats: 760 verdiente Punkte (Ausgaben zählen nicht ab), waren %s." % stats["points"])
	var rows: Array = stats["upgrades"]
	_check(rows.size() == 3 and rows[0] == {"id": "drone", "name": "Kameradrohne", "level": 2}, "stats: Upgrades als id, name, level, war %s." % [rows])
	_check(stats.get("synergies", []) == (["storm_front"] as Array[String]), "stats nennt die Synergie.")
	_check(stats == _game.get_stats(), "get_stats liefert dieselbe Statistik.")
	_game.end_run()
	_events.emit_signal("player_died")
	_check(_count("game_over") == overs + 1, "Ein zweites Ende sendet kein zweites game_over.")
	_game.set_paused(false)
	_check(_game.state == _game.State.GAME_OVER and paused, "Das Pausemenü hebt Game Over nicht auf.")
	_game.open_chest(0)
	_check(_game.state == _game.State.GAME_OVER, "Im Game Over öffnet sich keine Kiste.")


func _test_restart() -> void:
	_check(_game.state == _game.State.GAME_OVER and paused, "Ausgangslage: Game Over mit Pause.")
	var runs_before: int = _count("run_started")
	# Ohne aktuelle Szene beginnt restart_run sofort einen neuen Lauf.
	_game.restart_run()
	_check(not paused, "restart_run hebt die Pause auf.")
	_check(_game.state == _game.State.PLAYING, "restart_run ohne Szene: gleich wieder PLAYING.")
	_check(_game.points == 0 and _game.kills == 0 and _game.wave == 0 and _game.upgrades.owned_ids().is_empty(), "restart_run setzt den Lauf zurück.")
	_check(_count("run_started") == runs_before + 1, "restart_run ohne Szene sendet run_started.")
	_check(_game.player == null, "restart_run vergisst den alten Spieler.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
