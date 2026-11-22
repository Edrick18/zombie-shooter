extends SceneTree
## Messlatte für die Bildrate in schweren, wiederholbaren Lagen (kein Test, nicht headless).
## Anders als perf_game.gd (das Ruckler beim ersten Auftreten sucht) misst dieses Skript den
## Dauerzustand: wie lange ein Bild in einer späten Welle dauert und wohin die Zeit geht.
##
## Aufruf (es erscheint ein Spielfenster, etwa 90 s):
##   Godot_v4.7-stable_win64_console.exe --audio-driver Dummy --path "<Projekt>" -s res://tests/perf_late.gd
## Das Fenster nimmt keine Eingaben an sich, und Tasten und Maus lösen im Spiel nichts aus: Wer
## währenddessen am Rechner arbeitet, verändert die Lage nicht. Läuft daneben das Spiel selbst
## (ZombieShooter.exe), taugen die Zahlen nichts.
##
## Lagen (jede einige Sekunden):
##   a  leere Bühne, Blick in den Raum
##   b  späte Welle: 48 Zombies gemischt laufen auf den Spieler zu, der Spieler steht und schaut
##      in die Horde
##   c  wie b mit Dauerfeuer (Applausmaschine, dann Flammenwerfer, dann Raketen)
##   d  wie c mit zehn Kameras gemischter Typen, Discokugel, Störsender, Minen, alle vier Räume
##      offen (27 Lichter)
##   p  wie d, aber pausiert und ohne Bildschirm darüber (Vergleichswert für e und f: Dasselbe Bild
##      wird gezeichnet, nichts rechnet)
##   e  Rucksack-Bildschirm offen mit vollem Raster und 30 Gegenständen im Regal
##   f  Kistenwahl offen
##
## Je Lage: Zahl der Bilder, mittlere Bildzeit, Bilder je Sekunde, 1-%-Tief (Mittel der
## langsamsten 1 % der Bilder), längstes Bild. Dazu die Zerlegung eines Bilds:
##   Skript   Zeit vom Beginn des Verarbeitungsschritts bis zum letzten _process eines Knotens
##            (alle _process im Baum, also GDScript und was es an Engine-Arbeit auslöst)
##   Physik   Zeit aller _physics_process (mit move_and_slide), auf jedes Bild umgelegt, dahinter
##            die Zeit je Physikschritt
##   Server   Physik- und Navigationsserver nach den Knoten, auf jedes Bild umgelegt
##   Zeichnen der Rest: Tweens, Zeichnen, Warten auf die Grafikkarte, Bildwechsel
## und die Monitore von Godot (größter Wert der letzten Sekunde bei den Zeiten, Mittel über die
## Bilder bei Zeichenaufrufen, Objekten und Dreiecken).
##
## Die Lage wiederholt sich von Lauf zu Lauf: fester Zufall (seed und run_seed), feste Plätze,
## feste Körper der Zombies (look_seed), der Blick schwenkt nach der Spielzeit. Wer dem Spieler
## zu nahe kommt, wird ans hintere Ende der Horde zurückgesetzt, wer stirbt, wird ersetzt: So
## bleiben es 48 Zombies vor der Kamera, solange gemessen wird. Der Spieler wird geheilt.
##
## Einstellungen: Das Skript liest die gespeicherten Einstellungen des Nutzers (settings.cfg),
## schreibt sie aber nie. Abweichende Werte gelten nur für diesen Lauf.
##
## Zusätze hinter "--" (mehrere durch Leerzeichen getrennt):
##   lagen=abcdpef    nur diese Lagen (b, c und d bauen aufeinander auf: d ohne c geht, e und f
##                    nehmen als Hintergrund, was davor lief)
##   sek=1.0          Faktor auf die Dauer jeder Lage
##   groesse=1920x1080  Fenstergröße (Standard 1920x1080, das Betriebssystem kann sie begrenzen)
##   msaa=0..3        Kantenglättung statt des gespeicherten Werts (0 aus, 3 = 8-fach)
##   skala=0.75       „Auflösung 3D“ statt des gespeicherten Werts
##   aus=a,b,c        Verdächtige abschalten, um ihre Kosten als Differenz zu messen:
##                    schatten (Schattenlicht), gluehen, dunst, lichter (alle Punktlichter und
##                    Scheinwerfer), koerper (Zombie-Körper unsichtbar, Logik läuft), logik
##                    (Zombies rechnen keine Physik, Körper sichtbar), anim (Zombies ohne _process),
##                    balken (Lebensbalken der Elite), hud, effekte (Behälter Fx unsichtbar), kameras
##                    (Lage d ohne Kameras), ton (Knoten Sfx entfernt), pfad (keine Wegsuche),
##                    abstand (keine Trennungskräfte), level (Studio unsichtbar), waffe (Waffe in
##                    der Hand unsichtbar), zombies (Lagen b bis d ohne Zombies)
##   ruhig=Pfad,Pfad  Knoten unter Main (z. B. Hud oder Level/Show), deren _process nicht läuft:
##                    So lässt sich die Rechenzeit eines einzelnen Skripts als Differenz messen.
##   versteckt=Pfad,Pfad  Knoten unter Main (z. B. Hud/Root/Fps oder Level/Audience), die
##                    unsichtbar sind: So lassen sich die Kosten eines Teils der Szene messen.
##   inventur         druckt nach jeder Lage, welche Knoten-Arten am häufigsten im Baum hängen
##   bilder=<name>    speichert je Lage ein Bildschirmfoto nach res://_shots/perf_<name>_<lage>.png.
##                    Für vergleichbare Bilder mit --fixed-fps 60 starten und "takt" angeben.
##   takt             wartet nach Bildern statt nach echter Zeit (60 Bilder = 1 s). Nur zusammen mit
##                    --fixed-fps 60 sinnvoll: Dann ist jeder Lauf Bild für Bild gleich.
##   spur=<Datei>     schreibt je Physikschritt eine Zeile mit dem Stand des Spiels in die Datei
##                    (Lage aller Zombies als Prüfsumme, Summe ihrer Leben, Stand von Game.rng,
##                    Kills, Kisten). Mit --fixed-fps 60, "takt" und "aus=ton" liefern zwei Läufe
##                    dieselbe Datei: So lässt sich prüfen, ob eine Änderung am Code das Verhalten
##                    der Zombies oder den Schaden verändert hat. (Mit Ton nicht: Das Raunen des
##                    Publikums läuft nach echter Zeit und verbraucht dabei Zufallszahlen.)
##   kurz             nur die Tabellenzeilen "PERF|..." drucken (für Auswertung mit einem Skript)
##
## Spalten einer Zeile "PERF|": Lage, Bilder, Mittel ms, Bilder je Sekunde, 1-%-Tief ms, längstes
## Bild ms, Skript ms, Physik ms, Server ms, Zeichnen und Rest ms, Zeichenaufrufe, Objekte,
## Dreiecke, Knoten, Zombies, Physik ms je Schritt, Server ms je Schritt.
##
## Das Skript beendet sich immer: nach der letzten Lage, bei einem Fehler über das Zeitlimit.

const Balance := preload("res://scripts/core/balance.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const Settings := preload("res://scripts/game/settings.gd")

const MAIN_SCENE: String = "res://scenes/main.tscn"
## Erst zur Laufzeit geladen: zombie.gd benutzt die Autoloads, die es beim Laden dieses Skripts noch nicht gibt.
const ZOMBIE_SCRIPT: String = "res://scripts/game/zombies/zombie.gd"
const DEFAULT_WINDOW: Vector2i = Vector2i(1920, 1080)
const TIME_LIMIT: float = 400.0
const RUN_SEED: int = 4
const RANDOM_SEED: int = 20261122
## Welle, aus der die Zombies stammen (Leben, Tempo): In Welle 22 leben zum ersten Mal 48 zugleich.
const LATE_WAVE: int = 22
const ZOMBIE_COUNT: int = 48
const ELITE_SLOTS: Array[int] = [11, 35]
## Jeder dritte Platz ist ein Sprinter (Welle 22: 35 % Sprinter).
const SPRINTER_EVERY: int = 3
## Raster der Plätze vor dem Spieler (Bühnenboden, Weltkoordinaten). Plätze, die nicht auf dem
## Navigationsnetz liegen (Kulissen), entfallen.
const SLOT_X_FROM: float = -10.0
const SLOT_X_STEP: float = 2.0
const SLOT_COLUMNS: int = 11
const SLOT_ROWS: Array[float] = [-4.6, -3.4, -2.2, -1.0, 0.2, 1.4]
const SLOT_NAV_TOLERANCE: float = 0.12
## Plätze der hinteren beiden Reihen: Dorthin kommt, wer dem Spieler zu nahe war oder ersetzt wird.
const BACK_SLOT_COUNT: int = 2 * SLOT_COLUMNS
## Wer näher als so viele Meter am Spieler steht, wird nach hinten gesetzt.
const TREADMILL_DISTANCE: float = 2.4
## Blick: auf diesen Punkt, dazu ein Schwenk nach links und rechts.
const LOOK_TARGET: Vector3 = Vector3(0.0, 0.9, -3.0)
const SWEEP_DEGREES: float = 22.0
const SWEEP_SPEED: float = 0.9
const AMMO_REFILL_INTERVAL: float = 0.5
const SETTLE_TIME: float = 1.5
const TICKS_PER_SECOND: float = 60.0
## Die Zeit-Monitore von Godot wechseln einmal je Sekunde: so lange nach Messbeginn warten.
const MONITOR_DELAY_USEC: int = 2100000
## Felder im Rucksack (7 x 5): Die Waffe liegt immer im Block links oben, jeder andere Gegenstand
## in seinem festen Bereich. So passen alle drei Waffen der Messung nacheinander an dieselbe Stelle.
const WEAPON_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
]
## Gegenstände der Lage d: [id, Rarität, erlaubte Felder]. Zehn Kameras (drei Drohnen, vier
## Zeitlupen-Kameras, je eine Tele-, Blitz- und Regie-Kamera), Discokugel, Störsender, Mine.
const BUILD_ITEMS: Array = [
	["cam_flash", 2, [Vector2i(4, 0), Vector2i(5, 0), Vector2i(4, 1), Vector2i(5, 1)]],
	["disco_ball", 3, [Vector2i(6, 0), Vector2i(6, 1)]],
	["cam_tele", 2, [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]],
	["drone", 1, [Vector2i(3, 2), Vector2i(4, 2)]],
	["drone", 2, [Vector2i(5, 2), Vector2i(6, 2)]],
	["cam_director", 2, [Vector2i(0, 3), Vector2i(1, 3), Vector2i(0, 4)]],
	["jammer", 3, [Vector2i(2, 3), Vector2i(2, 4), Vector2i(1, 4)]],
	["drone", 3, [Vector2i(3, 3), Vector2i(4, 3)]],
	["mine", 3, [Vector2i(3, 4), Vector2i(4, 4)]],
	["cam_slow", 1, [Vector2i(5, 3)]],
	["cam_slow", 2, [Vector2i(6, 3)]],
	["cam_slow", 3, [Vector2i(5, 4)]],
	["cam_slow", 4, [Vector2i(6, 4)]],
]
## 30 Gegenstände für das Regal (Lage e): [id, Rarität, kaputt].
const SHELF_ITEMS: Array = [
	["pistol", 1, false], ["revolver", 2, true], ["smg", 1, false], ["shotgun", 3, false], ["rifle", 2, true],
	["sniper", 1, false], ["tesla", 2, false], ["lmg", 1, true], ["crossbow", 3, false], ["beam", 2, false],
	["drone", 4, false], ["cam_tele", 1, true], ["cam_flash", 1, false], ["cam_slow", 5, false], ["cam_director", 3, false],
	["lifesteal", 1, false], ["max_hp", 2, true], ["corpse_explosion", 3, false], ["reload_shockwave", 1, false], ["speed", 4, false],
	["luck", 2, false], ["kill_heal", 1, true], ["dash", 3, false], ["thorns", 2, false], ["snack", 1, false],
	["cam_uplink", 2, false], ["mine", 1, true], ["jammer", 1, false], ["disco_ball", 1, false], ["burst_pistol", 4, false],
]
const SCENE_ORDER: String = "abcdpef"
const SCENE_NAMES: Dictionary = {
	"a": "a leere Bühne",
	"b": "b 48 Zombies",
	"c": "c 48 Zombies, Dauerfeuer",
	"c1": "c1 Applausmaschine",
	"c2": "c2 Flammenwerfer",
	"c3": "c3 Raketen",
	"d": "d Dauerfeuer, 10 Kameras, alles offen",
	"p": "p wie d, pausiert",
	"e": "e Rucksack offen",
	"f": "f Kistenwahl offen",
}
const FIRE_WEAPONS: Array[String] = ["minigun", "flamethrower", "rocket_launcher"]


## Letzter Knoten in der Reihenfolge von _process und _physics_process: stoppt die Zeit, wenn alle
## anderen Knoten fertig sind.
class EndProbe:
	extends Node
	var process_end_usec: int = 0
	var physics_end_usec: int = 0

	func _init() -> void:
		name = "PerfEndProbe"
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 1000000
		process_physics_priority = 1000000

	func _process(_delta: float) -> void:
		process_end_usec = Time.get_ticks_usec()

	func _physics_process(_delta: float) -> void:
		physics_end_usec = Time.get_ticks_usec()


var _game: Node
var _events: Node
var _main: Node
var _probe: EndProbe
var _scenes: String = SCENE_ORDER
var _time_factor: float = 1.0
var _window_size: Vector2i = DEFAULT_WINDOW
var _off: Dictionary = {}
var _shot_tag: String = ""
var _by_frames: bool = false
var _brief: bool = false
var _still: PackedStringArray = PackedStringArray()
var _hidden: PackedStringArray = PackedStringArray()
var _inventory: bool = false
var _trace_path: String = ""
var _trace_file: FileAccess = null
var _trace_tick: int = 0
var _keep_alive: bool = false

# --- Messung: je Bild ein Eintrag, solange _recording an ist ---
var _recording: bool = false
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _script_ms: PackedFloat32Array = PackedFloat32Array()
var _draw_calls: PackedFloat32Array = PackedFloat32Array()
var _objects: PackedFloat32Array = PackedFloat32Array()
var _primitives: PackedFloat32Array = PackedFloat32Array()
var _physics_ms_total: float = 0.0
var _server_ms_total: float = 0.0
var _physics_ticks: int = 0
var _monitor_process: float = 0.0
var _monitor_physics: float = 0.0
var _monitor_navigation: float = 0.0
var _last_frame_usec: int = 0
var _record_start_usec: int = 0
var _physics_start_usec: int = 0
## Ende des letzten Physikschritts der Knoten, 0 = seit dem letzten Zeitpunkt keiner.
var _physics_open_usec: int = 0
var _frames_seen: int = 0

# --- Lage ---
var _slots: Array[Vector3] = []
var _next_back_slot: int = 0
var _next_look_seed: int = 1
var _horde_on: bool = false
var _fire_on: bool = false
var _sweep_on: bool = false
var _scene_time: float = 0.0
var _refill_left: float = 0.0
var _weapon_id: String = ""
var _weapon_uid: int = -1
var _wanted_types: Dictionary = {}


func _initialize() -> void:
	create_timer(TIME_LIMIT, true, false, true).timeout.connect(_on_time_limit)
	_read_args()
	_run()


func _process(delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	_close_physics_span(now)
	if _recording and _last_frame_usec > 0 and _probe != null:
		_frame_ms.append(float(now - _last_frame_usec) / 1000.0)
		# Die Zeit der Knoten des vorigen Bilds: von dessen Beginn bis zu seinem letzten _process.
		_script_ms.append(maxf(0.0, float(_probe.process_end_usec - _last_frame_usec) / 1000.0))
		_draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		_primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		# Die Zeit-Monitore nennen den größten Wert der letzten vollen Sekunde: erst lesen, wenn
		# diese Sekunde ganz in der Messung liegt (sonst zählt der Aufbau der Lage mit).
		if now - _record_start_usec > MONITOR_DELAY_USEC:
			_monitor_process = maxf(_monitor_process, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_monitor_physics = maxf(_monitor_physics, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			_monitor_navigation = maxf(_monitor_navigation, Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0)
	_last_frame_usec = now
	_frames_seen += 1
	if not paused:
		_scene_time += delta
	_drive(delta)
	return false


func _physics_process(_delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	_close_physics_span(now)
	_physics_start_usec = now
	_drive_physics()
	# Der eigene Knoten läuft als letzter: Dort endet die Zeit der Knoten für diesen Schritt.
	_probe_physics_pending = true
	return false


var _probe_physics_pending: bool = false


## Schließt einen offenen Physikschritt ab: Die Knoten liefen von _physics_start_usec bis zum
## Stempel des letzten Knotens, danach rechneten die Server bis jetzt.
func _close_physics_span(now: int) -> void:
	if not _probe_physics_pending or _probe == null:
		return
	_probe_physics_pending = false
	var end: int = _probe.physics_end_usec
	if end < _physics_start_usec:
		# Der letzte Knoten lief nicht (Baum pausiert und Knoten noch nicht im Baum): nichts zu messen.
		return
	if _recording:
		_physics_ms_total += float(end - _physics_start_usec) / 1000.0
		_server_ms_total += float(now - end) / 1000.0
		_physics_ticks += 1


func _on_time_limit() -> void:
	printerr("FEHLER: Zeitlimit von %d s überschritten, Messung abgebrochen." % int(TIME_LIMIT))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit(2)


func _read_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		var key: String = parts[0]
		var value: String = parts[1] if parts.size() > 1 else ""
		match key:
			"lagen": _scenes = value
			"sek": _time_factor = maxf(0.05, value.to_float())
			"groesse":
				var size: PackedStringArray = value.split("x")
				if size.size() == 2:
					_window_size = Vector2i(size[0].to_int(), size[1].to_int())
			"msaa": _off["__msaa"] = clampi(value.to_int(), 0, 3)
			"skala": _off["__scale"] = clampf(value.to_float(), 0.25, 1.0)
			"aus":
				for name: String in value.split(",", false):
					_off[name] = true
			"ruhig":
				for path: String in value.split(",", false):
					_still.append(path)
			"versteckt":
				for path: String in value.split(",", false):
					_hidden.append(path)
			"inventur": _inventory = true
			"spur": _trace_path = value
			"bilder": _shot_tag = value
			"takt": _by_frames = true
			"kurz": _brief = true


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("FEHLER: perf_late.gd braucht echte Grafik (ohne --headless starten).")
		quit(2)
		return
	_game = root.get_node("Game")
	# Dieses Werkzeug darf den echten Spielstand (Konto, Pakete) nie anfassen.
	_game.set("progress_file_enabled", false)
	(_game.get("progress") as RefCounted).set("unlock_all", true)
	_game.set("broken_loot", false)
	_game.set("auto_pack", true)
	_events = root.get_node("Events")
	# Einstellungen des Nutzers lesen (nie schreiben), Abweichungen gelten nur für diesen Lauf.
	Settings.ensure_loaded()
	if _off.has("__msaa"):
		Settings.set_msaa(int(_off["__msaa"]))
	if _off.has("__scale"):
		Settings.render_scale = float(_off["__scale"])
	if _by_frames:
		# Bildschirmfotos: Die FPS-Anzeige zeigt in jedem Lauf andere Zahlen.
		Settings.set_show_fps(false)
	root.mode = Window.MODE_WINDOWED
	root.size = _window_size
	_shield_from_user()
	if not _trace_path.is_empty():
		_trace_file = FileAccess.open(_trace_path, FileAccess.WRITE)
		if _trace_file == null:
			printerr("FEHLER: %s lässt sich nicht schreiben." % _trace_path)
	seed(RANDOM_SEED)
	_probe = EndProbe.new()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.set("run_seed", RUN_SEED)
	_main.set("character_select_enabled", false)
	root.add_child(_main)
	current_scene = _main
	root.add_child(_probe)
	_wave_manager().set("auto_start", false)
	_player().set_process_input(false)
	_apply_static_switches()
	# Der Lauf beginnt erst nach dem Vorwärmen (State PLAYING = 1).
	while int(_game.get("state")) != 1:
		await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_keep_alive = true
	_game.set("wave", LATE_WAVE)
	root.size = _window_size
	await _wait(0.5)
	_collect_slots()
	_print_header()
	_place_player()
	_prepare_backpack()

	if _scenes.contains("a"):
		await _wait(SETTLE_TIME)
		await _measure("a", 4.0)
	if _scenes.contains("b") or _scenes.contains("c") or _scenes.contains("d"):
		_start_horde()
	if _scenes.contains("b"):
		await _wait(SETTLE_TIME)
		await _measure("b", 8.0)
	if _scenes.contains("c"):
		await _fire_scene("c", 5.0, true)
	if _scenes.contains("d"):
		_open_rooms()
		_add_build_items()
		await _wait(SETTLE_TIME)
		await _fire_scene("d", 5.0, false)
	_fire_on = false
	if _scenes.contains("p"):
		paused = true
		await _wait(0.3)
		await _measure("p", 3.0)
		paused = false
	if _scenes.contains("e"):
		await _backpack_scene()
	if _scenes.contains("f"):
		await _chest_scene()

	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _trace_file != null:
		_trace_file.close()
		_trace_file = null
	quit(0)


## Die Messung und der Mensch am Rechner sollen einander nicht stören: Das Fenster nimmt keine
## Eingaben an sich, und keine Taste und kein Mausklick löst im Spiel etwas aus (ein Klick ins
## Fenster hätte sonst geschossen und die Lage verändert). Gilt nur für diesen Programmlauf.
func _shield_from_user() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	for action: StringName in InputMap.get_actions():
		InputMap.action_erase_events(action)


# --- Lagen --------------------------------------------------------------------------------------

## Dauerfeuer mit den drei Waffen nacheinander. split: jede Waffe zusätzlich einzeln ausgeben.
func _fire_scene(key: String, seconds_each: float, split: bool) -> void:
	_fire_on = true
	_sweep_on = true
	var all_frames: PackedFloat32Array = PackedFloat32Array()
	var totals: Dictionary = {}
	for index: int in FIRE_WEAPONS.size():
		_take_weapon(FIRE_WEAPONS[index])
		await _wait(0.4)
		_begin_recording()
		await _wait(seconds_each)
		_recording = false
		if split:
			_report("%s%d" % [key, index + 1], false)
		all_frames.append_array(_frame_ms)
		_accumulate(totals)
	_restore(all_frames, totals)
	_report(key, true)
	await _shot(key)


func _backpack_scene() -> void:
	var pack: BackpackState = _game.get("backpack") as BackpackState
	for entry: Array in SHELF_ITEMS:
		pack.call("add_item", String(entry[0]), int(entry[1]), bool(entry[2]))
	_game.call("open_backpack")
	await _wait(0.3)
	var screen: Node = _main.get("backpack_screen") as Node
	# Der Zeiger steht auf einem eingeräumten Gegenstand: Die Karte mit den Werten ist offen.
	var placed: Array = pack.call("placed_items")
	if not placed.is_empty():
		var rect: Rect2 = screen.call("item_rect", int((placed[0] as Dictionary)["uid"]))
		screen.call("set_pointer", rect.get_center())
	await _wait(0.5)
	await _measure("e", 4.0)
	_game.call("close_backpack")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(0.2)


func _chest_scene() -> void:
	_game.call("open_chest", Balance.RARITY_GOLD)
	await _wait(1.0)
	await _measure("f", 4.0)
	(_main.get("chest_choice") as Node).call("close")


# --- Aufbau der Lage ----------------------------------------------------------------------------

func _place_player() -> void:
	var player: CharacterBody3D = _player()
	player.global_position = _spawn_point()
	player.velocity = Vector3.ZERO
	player.call("look_at_point", LOOK_TARGET)


## Plätze auf dem Bühnenboden, von hinten nach vorn. Nur Plätze auf dem Navigationsnetz (dort
## steht keine Kulisse, und der Boden liegt auf Höhe 0).
func _collect_slots() -> void:
	var region: NavigationRegion3D = (_main.get("level_info") as Dictionary)["nav_region"]
	var map: RID = region.get_navigation_map()
	_slots.clear()
	for z: float in SLOT_ROWS:
		for column: int in SLOT_COLUMNS:
			var wanted: Vector3 = Vector3(SLOT_X_FROM + SLOT_X_STEP * float(column), 0.0, z)
			var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map, wanted)
			if absf(snapped.y) < 0.2 and Vector2(snapped.x - wanted.x, snapped.z - wanted.z).length() < SLOT_NAV_TOLERANCE:
				_slots.append(wanted)


## Leert den Rucksack und vergrößert ihn auf das volle Raster. Die Waffen der Messung kommen
## später in den Block links oben.
func _prepare_backpack() -> void:
	var pack: BackpackState = _game.get("backpack") as BackpackState
	for entry: Dictionary in (pack.call("placed_items") as Array).duplicate():
		pack.call("remove", int(entry["uid"]))
	for entry: Dictionary in (pack.call("storage_items") as Array).duplicate():
		pack.call("remove", int(entry["uid"]))
	for _attempt: int in Balance.BACKPACK_COLS * Balance.BACKPACK_ROWS:
		if int(pack.call("cell_count")) >= Balance.BACKPACK_COLS * Balance.BACKPACK_ROWS:
			break
		var bag_uid: int = int(pack.call("add_item", "bag_tiny", 1))
		if not bool(pack.call("auto_place", bag_uid)):
			pack.call("remove", bag_uid)
			break
	if int(pack.call("cell_count")) < Balance.BACKPACK_COLS * Balance.BACKPACK_ROWS:
		print("Hinweis: Der Rucksack hat nur %d Felder." % int(pack.call("cell_count")))
	_take_weapon("pistol")


## Nimmt die Waffe aus dem Rucksack und legt die neue in den Block links oben.
func _take_weapon(weapon_id: String) -> void:
	var pack: BackpackState = _game.get("backpack") as BackpackState
	if _weapon_uid != -1:
		pack.call("remove", _weapon_uid)
	_weapon_uid = int(pack.call("add_item", weapon_id, 1))
	_weapon_id = weapon_id
	if not _place_in(_weapon_uid, weapon_id, WEAPON_CELLS):
		print("Hinweis: %s passt nicht in den Rucksack." % weapon_id)
	_game.call("sync_build")
	_weapons().call("refill_ammo", weapon_id)
	_refill_left = AMMO_REFILL_INTERVAL


## Räumt einen Gegenstand so ein, dass alle seine Felder in allowed liegen.
func _place_in(uid: int, id: String, allowed: Array) -> bool:
	var pack: BackpackState = _game.get("backpack") as BackpackState
	for rot: int in 4:
		for y: int in range(-2, Balance.BACKPACK_ROWS + 2):
			for x: int in range(-2, Balance.BACKPACK_COLS + 2):
				var cells: Array[Vector2i] = BackpackState.shape_at(id, Vector2i(x, y), rot)
				var inside: bool = not cells.is_empty()
				for cell: Vector2i in cells:
					if not allowed.has(cell):
						inside = false
						break
				if inside and bool(pack.call("place", uid, Vector2i(x, y), rot)):
					return true
	return false


func _add_build_items() -> void:
	var pack: BackpackState = _game.get("backpack") as BackpackState
	for entry: Array in BUILD_ITEMS:
		var id: String = String(entry[0])
		if _off.has("kameras") and ItemDefs.is_camera(id):
			continue
		var uid: int = int(pack.call("add_item", id, int(entry[1])))
		if not _place_in(uid, id, entry[2] as Array):
			print("Hinweis: %s fand keinen Platz im Rucksack." % id)
			pack.call("remove", uid)
	_game.call("sync_build")


func _open_rooms() -> void:
	for room: Dictionary in (_main.get("level_info") as Dictionary)["rooms"]:
		(room["door"] as Node).call("open")


func _start_horde() -> void:
	_sweep_on = true
	if _off.has("zombies"):
		return
	_horde_on = true
	_wanted_types = {"walker": 0, "sprinter": 0, "elite": 0}
	for index: int in mini(ZOMBIE_COUNT, _slots.size()):
		var type: String = _type_of_slot(index)
		_wanted_types[type] = int(_wanted_types[type]) + 1
		_spawn(type, _slots[index])
	_next_back_slot = 0


func _type_of_slot(index: int) -> String:
	if ELITE_SLOTS.has(index):
		return "elite"
	return "sprinter" if index % SPRINTER_EVERY == 1 else "walker"


## Wie zombie_spawner.spawn, aber mit festem Platz und festem Körper (look_seed).
func _spawn(type: String, at: Vector3) -> void:
	var zombie: CharacterBody3D = (load(ZOMBIE_SCRIPT) as GDScript).new() as CharacterBody3D
	zombie.call("setup", type, LATE_WAVE)
	zombie.set("look_seed", _next_look_seed)
	_next_look_seed += 1
	zombie.position = at
	var to_player: Vector3 = _player().global_position - at
	zombie.rotation.y = atan2(-to_player.x, -to_player.z)
	(_main.get("zombies_root") as Node3D).add_child(zombie)
	_events.emit_signal("zombie_spawned", zombie)
	_apply_zombie_switches(zombie)


func _back_slot() -> Vector3:
	var slot: Vector3 = _slots[_next_back_slot % mini(BACK_SLOT_COUNT, _slots.size())]
	_next_back_slot += 1
	return slot


# --- Steuerung je Bild und je Physikschritt -----------------------------------------------------

func _drive(delta: float) -> void:
	if not is_instance_valid(_main) or paused:
		return
	var player: CharacterBody3D = _player()
	# Nur heilen, wenn Leben fehlt: Jedes heal meldet player_health_changed, und das HUD rechnet
	# dann neu. In jedem Bild gerufen, mäße die Messung vor allem sich selbst.
	if _keep_alive and is_instance_valid(player) and float(player.get("hp")) < float(player.get("max_hp")):
		player.call("heal", 1000.0)
	if _sweep_on:
		var yaw: float = deg_to_rad(SWEEP_DEGREES) * sin(_scene_time * SWEEP_SPEED)
		var eye: Vector3 = _spawn_point() + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 0.0)
		var to_target: Vector3 = (LOOK_TARGET - eye).rotated(Vector3.UP, yaw)
		player.call("look_at_point", eye + to_target)
	if _fire_on:
		_refill_left -= delta
		if _refill_left <= 0.0:
			_refill_left = AMMO_REFILL_INTERVAL
			_weapons().call("refill_ammo", _weapon_id)
		_weapons().call("try_fire")
		var choice: Node = _main.get("chest_choice") as Node
		if bool(choice.call("is_open")):
			choice.call("choose", 0)


func _drive_physics() -> void:
	if not _horde_on or paused or not is_instance_valid(_main):
		return
	if _trace_file != null:
		_write_trace()
	var origin: Vector3 = _player().global_position
	var alive: Dictionary = {"walker": 0, "sprinter": 0, "elite": 0}
	for node: Node in get_nodes_in_group("zombies"):
		var zombie: CharacterBody3D = node as CharacterBody3D
		if zombie == null or bool(zombie.get("is_dead")):
			continue
		var type_now: String = String(zombie.get("zombie_type"))
		alive[type_now] = int(alive[type_now]) + 1
		var offset: Vector3 = zombie.global_position - origin
		offset.y = 0.0
		if offset.length_squared() < TREADMILL_DISTANCE * TREADMILL_DISTANCE:
			zombie.call("teleport_to", _back_slot())
			_apply_zombie_switches(zombie)
	for type: String in alive:
		for _missing: int in int(_wanted_types[type]) - int(alive[type]):
			_spawn(type, _back_slot())
	# Kisten bleiben liegen und werden nie eingesammelt: Mehr als acht braucht die Messung nicht.
	var chests: Array[Node] = get_nodes_in_group("chests")
	for index: int in chests.size() - 8:
		chests[index].remove_from_group("chests")
		chests[index].queue_free()


## Eine Zeile je Physikschritt für den Vergleich zweier Läufe (siehe "spur" im Kopf).
func _write_trace() -> void:
	_trace_tick += 1
	var places: Array = []
	var hp_sum: float = 0.0
	for node: Node in get_nodes_in_group("zombies"):
		places.append((node as Node3D).global_position.snapped(Vector3(0.001, 0.001, 0.001)))
		hp_sum += float(node.get("hp"))
	_trace_file.store_line("%d lage=%d zombies=%d leben=%.2f rng=%d kills=%d kisten=%d" % [
		_trace_tick, hash(places), places.size(), hp_sum, (_game.get("rng") as RandomNumberGenerator).state,
		int(_game.get("kills")), get_nodes_in_group("chests").size()])


# --- Schalter -----------------------------------------------------------------------------------

## Schalter, die einmal nach dem Aufbau gelten.
func _apply_static_switches() -> void:
	var level: Node3D = _main.get("level_root") as Node3D
	if _off.has("schatten"):
		for node: Node in level.find_children("*", "DirectionalLight3D", true, false):
			(node as DirectionalLight3D).shadow_enabled = false
	if _off.has("gluehen") or _off.has("dunst"):
		var world: WorldEnvironment = level.get_node("Environment") as WorldEnvironment
		if _off.has("gluehen"):
			world.environment.glow_enabled = false
		if _off.has("dunst"):
			world.environment.fog_enabled = false
	if _off.has("lichter"):
		for node: Node in level.find_children("*", "OmniLight3D", true, false):
			(node as Light3D).light_energy = 0.0
			(node as Light3D).visible = false
			node.set_script(null)
		for node: Node in level.find_children("*", "SpotLight3D", true, false):
			(node as Light3D).visible = false
		(level.get_node("Lights") as Node3D).visible = false
	if _off.has("level"):
		for child: Node in level.get_children():
			if child is Node3D and not (child is WorldEnvironment) and child.name != "Lights":
				(child as Node3D).visible = false
	if _off.has("hud"):
		(_main.get("hud") as CanvasLayer).visible = false
	if _off.has("effekte"):
		(_main.get("fx_root") as Node3D).visible = false
	if _off.has("ton"):
		var sfx: Node = _main.get("sfx") as Node
		if is_instance_valid(sfx):
			sfx.queue_free()
	for path: String in _still:
		var node: Node = _main.get_node_or_null(path)
		if node == null:
			print("Hinweis: Knoten %s gibt es nicht." % path)
		else:
			node.set_process(false)
	for path: String in _hidden:
		var node: Node = _main.get_node_or_null(path)
		if node == null or not ("visible" in node):
			print("Hinweis: Knoten %s gibt es nicht oder er lässt sich nicht verstecken." % path)
		else:
			node.set("visible", false)
	if _off.has("waffe"):
		var view_model: Node3D = _player().find_child("ViewModel", true, false) as Node3D
		if view_model != null:
			view_model.visible = false


## Schalter je Zombie (auch für jeden, der später ersetzt wird).
func _apply_zombie_switches(zombie: CharacterBody3D) -> void:
	if _off.has("koerper"):
		var body: Node3D = zombie.call("get_body") as Node3D
		if body != null:
			body.visible = false
	if _off.has("logik"):
		zombie.set_physics_process(false)
	if _off.has("anim"):
		zombie.set_process(false)
	if _off.has("balken"):
		var bar: Node3D = zombie.get_node_or_null("HealthBar") as Node3D
		if bar != null:
			bar.visible = false
	if _off.has("pfad"):
		zombie.set("_repath_left", 1.0e9)
	if _off.has("abstand"):
		zombie.set("_separation_left", 1.0e9)


# --- Messen und Ausgeben ------------------------------------------------------------------------

func _begin_recording() -> void:
	_frame_ms.clear()
	_script_ms.clear()
	_draw_calls.clear()
	_objects.clear()
	_primitives.clear()
	_physics_ms_total = 0.0
	_server_ms_total = 0.0
	_physics_ticks = 0
	_monitor_process = 0.0
	_monitor_physics = 0.0
	_monitor_navigation = 0.0
	_record_start_usec = Time.get_ticks_usec()
	_recording = true


func _measure(key: String, seconds: float) -> void:
	_begin_recording()
	await _wait(seconds)
	_recording = false
	_report(key, true)
	await _shot(key)


## Merkt die Summen einer Teilmessung, damit mehrere zusammen ausgegeben werden können.
func _accumulate(totals: Dictionary) -> void:
	# Gepackte Felder sind Werte: lesen, verlängern, zurückschreiben.
	var parts: Dictionary = {"script": _script_ms, "calls": _draw_calls, "objects": _objects, "prims": _primitives}
	for key: String in parts:
		var joined: PackedFloat32Array = totals.get(key, PackedFloat32Array())
		joined.append_array(parts[key] as PackedFloat32Array)
		totals[key] = joined
	totals["physics"] = float(totals.get("physics", 0.0)) + _physics_ms_total
	totals["server"] = float(totals.get("server", 0.0)) + _server_ms_total
	totals["ticks"] = int(totals.get("ticks", 0)) + _physics_ticks
	totals["m_process"] = maxf(float(totals.get("m_process", 0.0)), _monitor_process)
	totals["m_physics"] = maxf(float(totals.get("m_physics", 0.0)), _monitor_physics)
	totals["m_navigation"] = maxf(float(totals.get("m_navigation", 0.0)), _monitor_navigation)


func _restore(frames: PackedFloat32Array, totals: Dictionary) -> void:
	_frame_ms = frames
	_script_ms = totals["script"]
	_draw_calls = totals["calls"]
	_objects = totals["objects"]
	_primitives = totals["prims"]
	_physics_ms_total = totals["physics"]
	_server_ms_total = totals["server"]
	_physics_ticks = totals["ticks"]
	_monitor_process = totals["m_process"]
	_monitor_physics = totals["m_physics"]
	_monitor_navigation = totals["m_navigation"]


func _report(key: String, main_line: bool) -> void:
	var count: int = _frame_ms.size()
	if count == 0:
		print("%-40s keine Bilder" % String(SCENE_NAMES.get(key, key)))
		return
	var sorted: PackedFloat32Array = _frame_ms.duplicate()
	sorted.sort()
	var total: float = 0.0
	for ms: float in sorted:
		total += ms
	var mean: float = total / float(count)
	var slow_count: int = maxi(1, count / 100)
	var slow_total: float = 0.0
	for index: int in slow_count:
		slow_total += sorted[count - 1 - index]
	var low: float = slow_total / float(slow_count)
	var worst: float = sorted[count - 1]
	var script: float = _mean(_script_ms)
	var physics: float = _physics_ms_total / float(count)
	var server: float = _server_ms_total / float(count)
	var per_tick: float = _physics_ms_total / float(maxi(_physics_ticks, 1))
	var server_per_tick: float = _server_ms_total / float(maxi(_physics_ticks, 1))
	var draw: float = maxf(0.0, mean - script - physics - server)
	var zombies: int = get_nodes_in_group("zombies").size()
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("PERF|%s|%d|%.3f|%.1f|%.3f|%.2f|%.3f|%.3f|%.3f|%.3f|%.0f|%.0f|%.0f|%d|%d|%.3f|%.3f" % [
		key, count, mean, 1000.0 / mean, low, worst, script, physics, server, draw,
		_mean(_draw_calls), _mean(_objects), _mean(_primitives), nodes, zombies, per_tick, server_per_tick])
	if _brief:
		return
	print("%-40s Bilder %5d | Mittel %6.3f ms = %6.1f B/s | 1-%%-Tief %6.2f ms = %5.1f B/s | längstes %6.1f ms" % [
		String(SCENE_NAMES.get(key, key)), count, mean, 1000.0 / mean, low, 1000.0 / low, worst])
	if not main_line:
		return
	print("    Zerlegung je Bild: Skript %.3f ms | Physik %.3f ms (je Schritt %.2f) | Server %.3f ms (je Schritt %.2f) | Zeichnen und Rest %.3f ms" % [
		script, physics, per_tick, server, server_per_tick, draw])
	print("    Monitore (größter Wert einer Sekunde): Verarbeitung %.2f ms | Physik %.2f ms | Navigation %.2f ms" % [
		_monitor_process, _monitor_physics, _monitor_navigation])
	print("    Zeichenaufrufe %.0f | Objekte %.0f | Dreiecke %.0f | Knoten %d | Zombies %d" % [
		_mean(_draw_calls), _mean(_objects), _mean(_primitives), nodes, zombies])
	if _inventory:
		_print_inventory()


## Druckt die häufigsten Knoten-Arten im Baum, getrennt nach den Behältern unter Main.
func _print_inventory() -> void:
	for child: Node in _main.get_children():
		var counts: Dictionary = {}
		_count_nodes(child, counts)
		var total: int = 0
		var keys: Array = counts.keys()
		for key: String in keys:
			total += int(counts[key])
		if total < 20:
			continue
		keys.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
		var parts: PackedStringArray = PackedStringArray()
		for key: String in keys.slice(0, 6):
			parts.append("%s %d" % [key, int(counts[key])])
		print("    %-14s %5d Knoten: %s" % [child.name, total, ", ".join(parts)])


func _count_nodes(node: Node, counts: Dictionary) -> void:
	var key: String = node.get_class()
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		key += " (unsichtbar)"
	counts[key] = int(counts.get(key, 0)) + 1
	for child: Node in node.get_children():
		_count_nodes(child, counts)


func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _print_header() -> void:
	if _brief:
		return
	var switches: PackedStringArray = PackedStringArray()
	for key: String in _off:
		if not key.begins_with("__"):
			switches.append(key)
	print("Fenster %d x %d (gewünscht %d x %d), Bildschirm %d x %d, Kantenglättung %s, Auflösung 3D %d %%, VSync %s, Grenze %d, Sichtfeld %d" % [
		root.size.x, root.size.y, _window_size.x, _window_size.y,
		DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y,
		Settings.MSAA_NAMES[Settings.msaa], int(round(Settings.render_scale * 100.0)),
		"an" if Settings.vsync else "aus", Settings.fps_limit, int(Settings.fov)])
	print("Abgeschaltet: %s | Plätze: %d | Zeitfaktor %.2f%s" % [
		", ".join(switches) if not switches.is_empty() else "nichts", _slots.size(), _time_factor,
		" | Takt nach Bildern" if _by_frames else ""])


## Speichert ein Bildschirmfoto der Lage, wenn "bilder=<name>" angegeben ist.
func _shot(key: String) -> void:
	if _shot_tag.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "res://_shots/perf_%s_%s.png" % [_shot_tag, key]
	if image.save_png(path) != OK:
		printerr("FEHLER: %s konnte nicht gespeichert werden." % path)
	elif not _brief:
		print("    gespeichert: %s (%d x %d)" % [path, image.get_width(), image.get_height()])


## Wartet echte Sekunden (mal Zeitfaktor), mit "takt" stattdessen Bilder. Läuft auch pausiert.
func _wait(seconds: float) -> void:
	if _by_frames:
		for _frame: int in maxi(1, int(round(seconds * _time_factor * TICKS_PER_SECOND))):
			await process_frame
		return
	var until: int = Time.get_ticks_usec() + int(seconds * _time_factor * 1000000.0)
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
