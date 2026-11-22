extends SceneTree
## Bildschirmfotos mit echter Grafik (kein Test, nicht headless). Stellt typische Situationen
## über die öffentlichen Schnittstellen nach und speichert je Situation ein PNG.
##
## Aufruf (Fenster 1280 x 720, es erscheint kurz ein Spielfenster):
##   Godot_v4.7-stable_win64_console.exe --path "<Projekt>" -s res://tests/capture_game.gd -- <Zielordner>
## Ohne Zielordner landen die Bilder in user://shots.
##
## Bilder: 00 Ladebild, 01 Startblick, 02 Welle mit Elite, 03 Feuer aus der Nähe, 04 Kisten am Boden,
## 05a/05b Kistenwahl (Silber, Gold mit Trostpreisen), 06 HUD mit sechs Upgrades, Synergie und
## wenig Leben, 06b der Moment eines Treffers, 07 Blitz/Explosion/Konfetti, 08 Backstage mit Wandkauf, 09a Tür mit Hinweis,
## 09b Wandkauf Schrotflinte mit Hinweis, 10 Pausemenü, 11 Game Over.
##
## Das Skript beendet sich immer: nach dem letzten Bild, bei einem Fehler über das Zeitlimit.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")

const MAIN_SCENE: String = "res://scenes/main.tscn"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
## Nach so vielen echten Sekunden bricht das Skript ab (Exit-Code 2).
const TIME_LIMIT: float = 120.0
const SEED: int = 4
const KILL_INFO: Dictionary = {"source": "drone"}

var _game: Node
var _events: Node
var _main: Node
var _out_dir: String = "user://shots"
var _saved: int = 0
var _failed: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	# Wächter: läuft auch bei pausiertem Baum und beendet das Skript in jedem Fall.
	create_timer(TIME_LIMIT, true, false, true).timeout.connect(_on_time_limit)
	_run()


func _on_time_limit() -> void:
	printerr("FEHLER: Zeitlimit von %d s überschritten, Aufnahme abgebrochen." % int(TIME_LIMIT))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit(2)


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("FEHLER: capture_game.gd braucht echte Grafik (ohne --headless starten).")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	_game = root.get_node("Game")
	# Dieses Werkzeug darf den echten Spielstand (Konto, Pakete) nie anfassen.
	_game.set("progress_file_enabled", false)
	(_game.get("progress") as RefCounted).set("unlock_all", true)
	# Fundstücke kommen hier heil an: Die Messung räumt selbst ein und repariert nichts.
	_game.set("broken_loot", false)
	_events = root.get_node("Events")
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	if _main == null or _main.get_script() == null or not _main.has_method("_build_world"):
		printerr("FEHLER: Die Hauptszene lädt nicht (Skriptfehler?), Aufnahme abgebrochen.")
		quit(2)
		return
	_main.set("run_seed", SEED)
	_main.set("warmup_enabled", false)
	_main.set("character_select_enabled", false)
	# Gegenstände aus Kisten räumen sich selbst ein, der Rucksack hat eigene Bilder.
	_game.set("auto_pack", true)
	root.add_child(_main)
	current_scene = _main
	_wave_manager().set("auto_start", false)
	# Die Maus des Nutzers soll weder gefangen sein noch die Kamera drehen.
	_player().set_process_input(false)
	_free_mouse()
	await _wait(0.5)

	await _shot_loading()
	await _shot_start()
	await _shot_wave()
	await _shot_door()
	await _shot_backstage()
	await _shot_firing()
	await _shot_chests()
	await _shot_choice()
	await _shot_hud_build()
	await _shot_effects()
	await _shot_pause()
	await _shot_game_over()

	paused = false
	_free_mouse()
	print("%d Bilder gespeichert in %s" % [_saved, _out_dir])
	quit(1 if _failed > 0 else 0)


# --- Hilfen -----------------------------------------------------------------------------------

func _free_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Wartet Spielzeit in Sekunden (Summe der Bildzeiten, läuft auch bei pausiertem Baum). Ein
## Ruckler beim ersten Zeichnen eines Effekts verkürzt die Wartezeit damit nicht: Animationen
## sind danach so weit, wie es die Zahl sagt.
func _wait(seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		await process_frame
		left -= root.get_process_delta_time()


func _save(file_name: String) -> void:
	_free_mouse()
	if root.size != WINDOW_SIZE or root.mode != Window.MODE_WINDOWED:
		# Jemand (oder das Betriebssystem) hat das Fenster verändert: zurück auf das Maß.
		root.mode = Window.MODE_WINDOWED
		root.size = WINDOW_SIZE
		await process_frame
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(file_name + ".png")
	var error: Error = image.save_png(path)
	if error != OK:
		_failed += 1
		printerr("FEHLER: %s konnte nicht gespeichert werden (%d)." % [path, error])
		return
	_saved += 1
	print("gespeichert: %s (%d x %d)" % [path, image.get_width(), image.get_height()])


func _player() -> CharacterBody3D:
	return _main.get("player") as CharacterBody3D


func _weapons() -> Node:
	return _player().call("get_weapon_controller") as Node


func _wave_manager() -> Node:
	return _main.get("wave_manager") as Node


func _spawn_point() -> Vector3:
	return (_main.get("level_info") as Dictionary)["player_spawn"]


func _door() -> Node3D:
	return (_main.get("level_info") as Dictionary)["door"] as Node3D


## Stellt den Spieler an eine Stelle und richtet den Blick aus.
func _place(at: Vector3, look_at: Vector3) -> void:
	var player: CharacterBody3D = _player()
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.call("look_at_point", look_at)
	_free_mouse()


func _spawn(type: String, at: Vector3, wave: int = 3) -> Node3D:
	var zombie: Node3D = (_main.get("spawner") as Node).call("spawn", type, wave) as Node3D
	zombie.call("teleport_to", at)
	return zombie


func _clear_field() -> void:
	for node: Node in get_nodes_in_group("zombies"):
		node.call("despawn")
	for node: Node in get_nodes_in_group("chests"):
		node.remove_from_group("chests")
		node.queue_free()
	await _wait(0.1)


## Erzwingt einen Upgrade-Stand und meldet ihn wie im Spiel (HUD, Spieler, Drohne).
func _set_upgrades(levels: Dictionary) -> void:
	levels = levels.duplicate()
	if levels.has("drone"):
		# Kameras sind keine Upgrades mehr: Die Drohne kommt über den Rucksack (Abschnitt 22.7).
		var pack: RefCounted = _game.get("backpack") as RefCounted
		if int(pack.call("highest_level", "drone")) == 0:
			pack.call("auto_place", int(pack.call("add_item", "drone", int(levels["drone"]))))
			_game.call("sync_build")
		levels.erase("drone")
	var state: UpgradeState = UpgradeState.new()
	for id: String in levels:
		state.add_levels(id, int(levels[id]))
	_game.set("upgrades", state)
	for id: String in levels:
		_events.emit_signal("upgrade_chosen", id, int(levels[id]))
	for synergy_id: String in state.check_new_synergies():
		_events.emit_signal("synergy_unlocked", synergy_id)
	_player().call("refresh_stats")


# --- Situationen ------------------------------------------------------------------------------

func _shot_loading() -> void:
	# Das Ladebild des Vorwärmens (im echten Start nur kurz zu sehen).
	var warmup: Node = (load("res://scripts/game/warmup.gd") as GDScript).new() as Node
	var overlay: Node = warmup.call("_build_overlay") as Node
	root.add_child(overlay)
	await _wait(0.2)
	await _save("00_loading")
	overlay.queue_free()
	warmup.free()
	await _wait(0.1)


func _shot_start() -> void:
	_place(_spawn_point(), _spawn_point() + Vector3(0.0, 1.9, -10.0))
	_wave_manager().set("auto_start", true)
	await _wait(1.6)
	_wave_manager().set("auto_start", false)
	_player().call("look_at_point", _spawn_point() + Vector3(0.0, 1.9, -10.0))
	await _save("01_start")


func _shot_wave() -> void:
	_place(_spawn_point(), _spawn_point() + Vector3(0.0, 1.5, -10.0))
	_wave_manager().call("start_wave", 3)
	# Eine Gruppe kommt von der Bühne und über die Showtreppe, die Elite vorneweg.
	_spawn("elite", Vector3(0.6, 0.0, -1.2))
	for at: Vector3 in [Vector3(-2.2, 0.0, -0.6), Vector3(2.6, 0.0, -1.8), Vector3(-0.8, 0.0, -2.6),
			Vector3(-3.6, 0.4, -6.0), Vector3(1.8, 0.4, -6.4), Vector3(4.2, 0.0, 1.5)]:
		_spawn("walker", at)
	for at: Vector3 in [Vector3(-3.0, 0.4, -7.0), Vector3(3.0, 0.4, -6.5)]:
		_spawn("sprinter", at)
	await _wait(0.7)
	_player().call("heal", 1000.0)
	_player().call("look_at_point", Vector3(0.3, 1.4, -1.5))
	await _save("02_wave")


func _shot_firing() -> void:
	await _clear_field()
	_place(_spawn_point(), _spawn_point() + Vector3(0.0, 1.4, -10.0))
	_game.call("add_points", 1500)
	_weapons().call("give_weapon", "smg")
	var front: Node3D = _spawn("walker", _spawn_point() + Vector3(0.3, 0.0, -3.2))
	_spawn("walker", _spawn_point() + Vector3(-1.6, 0.0, -4.4))
	_spawn("sprinter", _spawn_point() + Vector3(1.9, 0.0, -5.0))
	await _wait(0.7)
	# Ein paar Schüsse Dauerfeuer, das Bild entsteht im Bild eines Schusses.
	var shots: int = 0
	for _i: int in 60:
		_player().call("heal", 1000.0)
		if is_instance_valid(front) and not bool(front.get("is_dead")):
			_player().call("look_at_point", front.call("get_center_position") + Vector3(0.0, 0.25, 0.0))
		if bool(_weapons().call("try_fire")):
			shots += 1
			if shots >= 3:
				break
		await process_frame
	await _save("03_firing")


func _shot_chests() -> void:
	await _clear_field()
	_place(_spawn_point(), Vector3(0.0, 0.9, -1.5))
	var dropper: Node = _main.get("chest_dropper") as Node
	dropper.call("spawn_chest", Vector3(0.0, 0.0, -1.5), Balance.RARITY_GOLD)
	dropper.call("spawn_chest", Vector3(-3.8, 0.0, 2.4), Balance.RARITY_SILVER)
	dropper.call("spawn_chest", Vector3(3.0, 0.4, -6.5), Balance.RARITY_BRONZE)
	await _wait(1.4)
	_player().call("look_at_point", Vector3(-0.4, 0.9, -1.5))
	await _save("04_chest")


func _shot_choice() -> void:
	await _clear_field()
	_set_upgrades({"burn": 2})
	_game.call("open_chest", Balance.RARITY_SILVER)
	await _wait(1.2)
	await _save("05a_choice")
	(_main.get("chest_choice") as Node).call("choose", 0)
	await _wait(0.2)
	# Fast alles ausgebaut: Die Gold-Kiste hat nur noch ein Upgrade und zwei Trostpreise.
	_set_upgrades({"chain_lightning": 5, "pierce": 5, "burn": 5, "drone": 5, "speed": 5, "luck": 2})
	await _wait(0.2)
	_game.call("open_chest", Balance.RARITY_GOLD)
	await _wait(1.2)
	await _save("05b_choice_gold")
	(_main.get("chest_choice") as Node).call("choose", 1)
	await _wait(0.2)


func _shot_hud_build() -> void:
	await _clear_field()
	_place(_spawn_point(), _spawn_point() + Vector3(0.0, 1.4, -10.0))
	_set_upgrades({"chain_lightning": 5, "pierce": 5, "burn": 3, "drone": 2, "reload_shockwave": 1, "luck": 4})
	_weapons().call("give_weapon", "smg")
	_spawn("walker", Vector3(-1.5, 0.0, -1.5))
	_spawn("sprinter", Vector3(1.2, 0.0, -2.2))
	_spawn("elite", Vector3(0.2, 0.4, -6.0))
	await _wait(0.3)
	var player: CharacterBody3D = _player()
	# Wenig Leben: ein Treffer, dessen Aufblitzen bis zum Bild abgeklungen ist. Zu sehen ist der
	# dauerhafte rote Rand bei wenig Leben.
	player.set("hp", 45.0)
	player.call("take_damage", 20.0)
	# Magazin fast leer schießen (Hinweis auf wenig Munition).
	var weapon_state: RefCounted = _weapons().call("get_state", "smg")
	for _i: int in 200:
		if weapon_state == null or int(weapon_state.get("mag")) <= 7:
			break
		player.call("look_at_point", Vector3(0.0, 1.3, -3.0))
		_weapons().call("try_fire")
		await process_frame
	await _wait(0.8)
	player.call("look_at_point", Vector3(0.0, 1.3, -3.0))
	await _save("06_hud_build")
	# Dazu der Moment eines Treffers: roter Rand und Kamera-Wackeln.
	player.call("heal", 30.0)
	player.call("take_damage", 20.0)
	await _wait(0.06)
	await _save("06b_hit")


func _shot_effects() -> void:
	await _clear_field()
	_place(_spawn_point(), _spawn_point() + Vector3(0.0, 1.3, -10.0))
	_set_upgrades({"chain_lightning": 5, "pierce": 5, "corpse_explosion": 5, "burn": 3})
	# Der Jubel der Upgrade-Wahl (Konfetti vor der Nase) soll vorbei sein.
	await _wait(1.8)
	_player().call("heal", 1000.0)
	_weapons().call("give_weapon", "pistol")
	_weapons().call("refill_ammo", "pistol")
	var effects: Node = _main.get("upgrade_effects") as Node
	var group: Array[Node3D] = []
	for at: Vector3 in [Vector3(-0.2, 0.0, 0.2), Vector3(1.6, 0.0, -0.4), Vector3(-1.9, 0.0, -0.6),
			Vector3(0.4, 0.0, -1.9), Vector3(2.8, 0.0, -2.2), Vector3(-2.6, 0.0, -2.4)]:
		group.append(_spawn("walker", at, 6))
	await _wait(0.6)
	# Opfer am Rand töten, bis eines explodiert (35 % je Kill). Die Explosion zündet im nächsten
	# Physik-Schritt, dann kommt der Schuss mit dem sicheren Blitz der Gewitterfront.
	var tries: int = 0
	while int(effects.call("get_pending_explosion_count")) == 0 and tries < 30:
		tries += 1
		var victim: Node3D = _spawn("walker", Vector3(0.9, 0.0, -1.1), 6)
		victim.call("take_damage", 1.0e9, KILL_INFO)
	await physics_frame
	await physics_frame
	for zombie: Node3D in group:
		if is_instance_valid(zombie) and not bool(zombie.get("is_dead")):
			_player().call("look_at_point", zombie.call("get_center_position"))
			_weapons().call("try_fire")
			break
	await _save("07_effects")


func _shot_door() -> void:
	await _clear_field()
	_player().call("heal", 1000.0)
	_game.call("add_points", 820)
	var door: Node3D = _door()
	_place(door.global_position + Vector3(-2.3, 0.0, 0.5), door.global_position + Vector3(0.0, 1.6, 0.0))
	await _wait(0.6)
	_player().call("look_at_point", door.global_position + Vector3(0.0, 1.6, 0.0))
	await _save("09a_door")


func _shot_backstage() -> void:
	var door: Node3D = _door()
	door.call("open")
	_game.call("add_points", 400)
	# Blick vom Eingang quer durch den Backstage-Raum.
	var room_center: Vector3 = door.global_position + Vector3(7.0, 1.2, 0.5)
	var stand: Vector3 = Vector3(door.global_position.x + 2.2, 0.0, door.global_position.z - 2.4)
	_place(stand, room_center)
	_spawn("walker", Vector3(door.global_position.x + 9.0, 0.0, door.global_position.z + 1.0), 4)
	await _wait(2.6)
	_player().call("heal", 1000.0)
	_player().call("look_at_point", room_center)
	await _save("08_backstage")


func _shot_pause() -> void:
	await _clear_field()
	_place(_spawn_point(), _spawn_point() + Vector3(0.0, 1.5, -10.0))
	_set_upgrades({"burn": 2, "drone": 3, "speed": 1})
	await _wait(1.8)
	(_main.get("pause_menu") as Node).call("open")
	await _wait(0.8)
	await _save("10_pause")
	# Einstellungen mit eingeschalteter FPS-Anzeige. Der Wert wird vor dem Schließen wieder so
	# gesetzt, wie er war: Die Aufnahme darf die Einstellungen des Nutzers nicht verändern.
	var settings: GDScript = load("res://scripts/game/settings.gd") as GDScript
	var fps_before: bool = bool(settings.get("show_fps"))
	settings.call("set_show_fps", true)
	(_main.get("pause_menu") as Node).call("open_settings")
	await _wait(0.8)
	await _save("10b_settings")
	settings.call("set_show_fps", fps_before)
	(_main.get("pause_menu") as Node).call("close_settings")
	(_main.get("pause_menu") as Node).call("resume")
	await _wait(0.2)


func _shot_game_over() -> void:
	_set_upgrades({"chain_lightning": 5, "pierce": 5, "burn": 3, "drone": 2, "max_hp": 1, "luck": 4})
	_events.emit_signal("wave_started", 7, 34)
	_events.emit_signal("zombies_left_changed", 12)
	_game.set("kills", 183)
	_spawn("walker", _spawn_point() + Vector3(0.4, 0.0, -1.4), 7)
	_spawn("elite", _spawn_point() + Vector3(-1.2, 0.0, -2.2), 7)
	await _wait(1.8)
	var player: CharacterBody3D = _player()
	player.call("take_damage", 100000.0)
	if not bool(player.get("is_dead")):
		# Unverwundbarkeit nach einem Zombie-Schlag: kurz warten und noch einmal.
		await _wait(Balance.PLAYER_HIT_INVULNERABILITY + 0.1)
		player.call("take_damage", 100000.0)
	await _wait(1.5)
	await _save("11_game_over")
