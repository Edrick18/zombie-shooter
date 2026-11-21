extends SceneTree
## Messung der Bildzeiten mit echter Grafik (kein Test, nicht headless). Stellt die Situationen
## nach, in denen das Spiel ruckeln kann (Kiste erscheint, Kiste wird geöffnet, Trefferzahlen,
## Effekte, viele Zombies), und druckt je Situation: Zahl der Bilder, mittlere Bildzeit, längstes
## Bild und Zahl der Bilder über 25 ms. Jede Situation läuft zweimal: Das erste Mal zeigt den
## Ruckler beim ersten Zeichnen (Shader, Schrift), das zweite Mal den Dauerzustand.
##
## Aufruf (es erscheint kurz ein Spielfenster):
##   Godot_v4.7-stable_win64_console.exe --disable-vsync --path "<Projekt>" -s res://tests/perf_game.gd
## Zusätze hinter "--":
##   nowarm   das Vorwärmen (scripts/game/warmup.gd) überspringen, zum Nachmessen ohne
##   record   am Ende alle gesehenen Material-Arten nach res://data/shader_warmup.json schreiben.
##            Das ist die Liste, die mit dem Spiel ausgeliefert und beim Start vorgewärmt wird.
##            Nach neuen Inhalten (Gegner, Effekte, Waffen) einmal neu aufnehmen.
##
## Das Skript beendet sich immer: nach der letzten Messung, bei einem Fehler über das Zeitlimit.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")
const ShaderKeep := preload("res://scripts/game/fx/shader_keep.gd")

const MAIN_SCENE: String = "res://scenes/main.tscn"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const TIME_LIMIT: float = 150.0
const SPIKE_MS: float = 25.0
const KILL_INFO: Dictionary = {"source": "drone"}

var _game: Node
var _events: Node
var _main: Node
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _last_usec: int = 0
var _keep_alive: bool = false
var _worst_overall: float = 0.0
var _spike_total: int = 0


func _initialize() -> void:
	create_timer(TIME_LIMIT, true, false, true).timeout.connect(_on_time_limit)
	_run()


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	if _last_usec > 0:
		_frame_ms.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	if _keep_alive and is_instance_valid(_main):
		var player: Node = _main.get("player") as Node
		if is_instance_valid(player):
			player.call("heal", 1000.0)
	return false


func _on_time_limit() -> void:
	printerr("FEHLER: Zeitlimit von %d s überschritten, Messung abgebrochen." % int(TIME_LIMIT))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit(2)


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("FEHLER: perf_game.gd braucht echte Grafik (ohne --headless starten).")
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	_game = root.get_node("Game")
	_events = root.get_node("Events")
	var load_start: int = Time.get_ticks_msec()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	if OS.get_cmdline_user_args().has("nowarm"):
		_main.set("warmup_enabled", false)
		print("Vorwärmen: aus")
	_main.set("run_seed", 4)
	_main.set("character_select_enabled", false)
	# Gegenstände aus Kisten räumen sich selbst ein (kein Rucksack-Bildschirm in der Messung).
	_game.set("auto_pack", true)
	root.add_child(_main)
	current_scene = _main
	_wave_manager().set("auto_start", false)
	_player().set_process_input(false)
	# Der Lauf beginnt erst nach dem Vorwärmen (State PLAYING = 1).
	while int(_game.get("state")) != 1:
		await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_keep_alive = true
	await process_frame
	await process_frame
	print("Start bis zum Spielbeginn: %d ms, bekannte Material-Arten: %d" % [
		Time.get_ticks_msec() - load_start, ShaderKeep.known_count()])
	_place(_spawn_point(), _spawn_point() + Vector3(0.0, 1.2, -10.0))
	await _measure("Start (erste Sekunde)", 1.0)
	await _measure("Leeres Studio", 2.0)

	var front: Vector3 = _spawn_point() + Vector3(0.0, 0.0, -4.0)
	var dropper: Node = _main.get("chest_dropper") as Node
	var fx: GDScript = load("res://scripts/game/fx/fx.gd") as GDScript
	var fx_root: Node = get_first_node_in_group("fx_root")

	# --- Kiste erscheint ---
	for rarity: int in [Balance.RARITY_BRONZE, Balance.RARITY_SILVER, Balance.RARITY_GOLD]:
		for pass_index: int in 2:
			dropper.call("spawn_chest", front + Vector3(float(rarity) * 1.5 - 1.5, 0.0, float(pass_index)), rarity)
			await _measure("Kiste erscheint, Seltenheit %d, Mal %d" % [rarity, pass_index + 1], 0.8)
	await _clear_field()

	# --- Kiste wird geöffnet (Wahl erscheint), danach Wahl getroffen ---
	for pass_index: int in 3:
		var rarity: int = [Balance.RARITY_SILVER, Balance.RARITY_GOLD, Balance.RARITY_BRONZE][pass_index]
		var chest: Node = dropper.call("spawn_chest", front, rarity) as Node
		await _wait(0.6)
		_frame_ms.clear()
		chest.call("collect")
		await _measure("Kiste geöffnet (Wahl erscheint), Mal %d" % (pass_index + 1), 1.2, false)
		(_main.get("chest_choice") as Node).call("choose", 0)
		await _measure("Wahl getroffen (HUD, Jubel), Mal %d" % (pass_index + 1), 1.2)

	# --- Trefferzahlen: viele verschiedene Beträge ---
	for pass_index: int in 2:
		_frame_ms.clear()
		for i: int in 30:
			fx.call("damage_number", fx_root, front + Vector3(randf_range(-2.0, 2.0), 1.2, 0.0),
				8.0 + float(i) * 7.0, Color(1.0, 0.9, 0.3))
			await process_frame
		await _measure("30 Trefferzahlen mit verschiedenen Beträgen, Mal %d" % (pass_index + 1), 0.5, false)
		await _wait(0.8)

	# --- Einzelne Effekte ---
	for pass_index: int in 2:
		fx.call("explosion", fx_root, front + Vector3(0.0, 1.0, 0.0), 3.0, Color(1.0, 0.5, 0.1))
		await _measure("Explosion, Mal %d" % (pass_index + 1), 0.6)
		fx.call("lightning", fx_root, PackedVector3Array([front + Vector3(-2.0, 1.0, 0.0), front + Vector3(0.0, 1.4, 0.0), front + Vector3(2.0, 1.0, 0.0)]))
		await _measure("Blitz, Mal %d" % (pass_index + 1), 0.5)
		fx.call("confetti", fx_root, front + Vector3(0.0, 1.0, 0.0))
		await _measure("Konfetti, Mal %d" % (pass_index + 1), 0.6)
		fx.call("shockwave", fx_root, front, 5.0)
		await _measure("Druckwelle, Mal %d" % (pass_index + 1), 0.6)

	# --- Zombies: erscheinen, sterben ---
	for pass_index: int in 2:
		for type: String in ["walker", "sprinter", "elite"]:
			var zombie: Node3D = _spawn(type, front + Vector3(randf_range(-1.5, 1.5), 0.0, -2.0))
			await _measure("Zombie %s erscheint, Mal %d" % [type, pass_index + 1], 0.5)
			zombie.call("take_damage", 20.0, {"source": "bullet"})
			await _measure("Zombie %s getroffen, Mal %d" % [type, pass_index + 1], 0.4)
			zombie.call("take_damage", 1.0e9, KILL_INFO)
			await _measure("Zombie %s stirbt, Mal %d" % [type, pass_index + 1], 0.8)
	await _clear_field()

	# --- Volle Welle mit Dauerfeuer und allen Effekten ---
	_set_upgrades({"chain_lightning": 5, "pierce": 5, "corpse_explosion": 5, "burn": 3, "drone": 3, "reload_shockwave": 2})
	await _wait(1.5)
	_game.call("add_points", 5000)
	_weapons().call("give_weapon", "shotgun")
	_weapons().call("give_weapon", "smg")
	_wave_manager().call("start_wave", 8)
	await _measure("Welle 8 läuft an (Zombies erscheinen)", 4.0)
	_frame_ms.clear()
	var fire_start: int = Time.get_ticks_msec()
	var until: int = fire_start + 8000
	var weapon_order: Array[String] = ["smg", "shotgun", "pistol", "smg"]
	var weapon_index: int = -1
	while Time.get_ticks_msec() < until:
		# Alle zwei Sekunden die Waffe wechseln, damit jede Waffe ihre Effekte zeigt.
		@warning_ignore("integer_division")
		var wanted: int = mini((Time.get_ticks_msec() - fire_start) / 2000, weapon_order.size() - 1)
		if wanted != weapon_index:
			weapon_index = wanted
			_weapons().call("give_weapon", weapon_order[weapon_index])
			_weapons().call("refill_ammo", weapon_order[weapon_index])
		var target: Node3D = _nearest_zombie()
		if target != null:
			_player().call("look_at_point", target.call("get_center_position"))
		_weapons().call("try_fire")
		if bool((_main.get("chest_choice") as Node).call("is_open")):
			(_main.get("chest_choice") as Node).call("choose", 0)
		await process_frame
	await _measure("Welle 8, Dauerfeuer mit allen Waffen und Effekten (8 s)", 0.1, false)
	print("Zombies am Leben: %d, Knoten im Baum: %d, Objekte: %d" % [
		get_nodes_in_group("zombies").size(), get_node_count(),
		int(Performance.get_monitor(Performance.OBJECT_COUNT))])
	print("Zeichenaufrufe: %d, Videospeicher: %d MB, Texturspeicher: %d MB" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0)])

	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("GESAMT: längstes Bild %.1f ms, Bilder über %d ms: %d, Material-Arten: %d" % [
		_worst_overall, int(SPIKE_MS), _spike_total, ShaderKeep.known_count()])
	if OS.get_cmdline_user_args().has("record"):
		if ShaderKeep.save_list(ShaderKeep.SHIPPED_LIST):
			print("Liste gespeichert: %s" % ShaderKeep.SHIPPED_LIST)
		else:
			printerr("FEHLER: %s konnte nicht geschrieben werden." % ShaderKeep.SHIPPED_LIST)
	quit(0)


# --- Hilfen -----------------------------------------------------------------------------------

## Wartet echte Sekunden und druckt danach die Bildzeiten seit dem letzten Leeren.
func _measure(label: String, seconds: float, clear_first: bool = true) -> void:
	if clear_first:
		_frame_ms.clear()
	await _wait(seconds)
	var count: int = _frame_ms.size()
	if count == 0:
		print("%-62s keine Bilder" % label)
		return
	var total: float = 0.0
	var worst: float = 0.0
	var spikes: int = 0
	for ms: float in _frame_ms:
		total += ms
		worst = maxf(worst, ms)
		if ms > SPIKE_MS:
			spikes += 1
	_worst_overall = maxf(_worst_overall, worst)
	_spike_total += spikes
	print("%-62s Bilder %4d | Mittel %5.2f ms | längstes %6.1f ms | über %d ms: %d" % [
		label, count, total / float(count), worst, int(SPIKE_MS), spikes])


## Wartet echte Zeit (läuft auch bei pausiertem Baum).
func _wait(seconds: float) -> void:
	var until: int = Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < until:
		await process_frame


func _player() -> CharacterBody3D:
	return _main.get("player") as CharacterBody3D


func _weapons() -> Node:
	return _player().call("get_weapon_controller") as Node


func _wave_manager() -> Node:
	return _main.get("wave_manager") as Node


func _spawn_point() -> Vector3:
	return (_main.get("level_info") as Dictionary)["player_spawn"]


func _place(at: Vector3, look_at: Vector3) -> void:
	var player: CharacterBody3D = _player()
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.call("look_at_point", look_at)


func _spawn(type: String, at: Vector3, wave: int = 3) -> Node3D:
	var zombie: Node3D = (_main.get("spawner") as Node).call("spawn", type, wave) as Node3D
	zombie.call("teleport_to", at)
	return zombie


func _nearest_zombie() -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	var origin: Vector3 = _player().global_position
	for node: Node in get_nodes_in_group("zombies"):
		var zombie: Node3D = node as Node3D
		if zombie == null or bool(zombie.get("is_dead")):
			continue
		var distance: float = origin.distance_squared_to(zombie.global_position)
		if distance < best_distance:
			best_distance = distance
			best = zombie
	return best


func _clear_field() -> void:
	for node: Node in get_nodes_in_group("zombies"):
		node.call("despawn")
	for node: Node in get_nodes_in_group("chests"):
		node.remove_from_group("chests")
		node.queue_free()
	await _wait(0.1)


func _set_upgrades(levels: Dictionary) -> void:
	var state: UpgradeState = UpgradeState.new()
	for id: String in levels:
		state.add_levels(id, int(levels[id]))
	_game.set("upgrades", state)
	for id: String in levels:
		_events.emit_signal("upgrade_chosen", id, int(levels[id]))
	for synergy_id: String in state.check_new_synergies():
		_events.emit_signal("synergy_unlocked", synergy_id)
	_player().call("refresh_stats")
