extends RefCounted
## Einstellungen des Spielers, die über das Programmende hinaus gelten: Mausempfindlichkeit,
## Sichtfeld, Fenstermodus, VSync, Bildraten-Grenze, Auflösungs-Skalierung, Kantenglättung und
## die FPS-Anzeige.
## Gespeichert in user://settings.cfg (unter Windows: %APPDATA%\Godot\app_userdata\Zombie-Shooter).
##
## Nur statische Funktionen und Werte. Einbinden mit preload.
## Jeder Wert hat einen Setter, der ihn auf den erlaubten Bereich begrenzt. apply_video überträgt
## die Grafikwerte auf Fenster und Engine. Das Sichtfeld liest der Spieler selbst (jedes Bild),
## die FPS-Anzeige liest das HUD.
## Headless (Tests) wird die Datei des Nutzers weder gelesen noch geschrieben, und apply_video
## tut nichts: Tests laufen immer mit den Standardwerten. Mit einem eigenen Pfad lassen sich
## load_from und save_to trotzdem testen.

const Balance := preload("res://scripts/core/balance.gd")

const PATH: String = "user://settings.cfg"
const SECTION_INPUT: String = "eingabe"
const SECTION_VIDEO: String = "grafik"

## Die Mausempfindlichkeit ist ein Faktor auf Balance.MOUSE_SENSITIVITY: 1.0 = 100 %.
const MOUSE_SENSITIVITY_DEFAULT: float = 1.0
const MOUSE_SENSITIVITY_MIN: float = 0.1
const MOUSE_SENSITIVITY_MAX: float = 3.0
const MOUSE_SENSITIVITY_STEP: float = 0.05

## Sichtfeld in Grad (senkrecht). Standard ist Balance.PLAYER_FOV.
const FOV_MIN: float = 60.0
const FOV_MAX: float = 110.0
const FOV_STEP: float = 1.0

## Fenstermodus: Index in WINDOW_MODE_NAMES.
const WINDOW_WINDOWED: int = 0
const WINDOW_BORDERLESS: int = 1
const WINDOW_EXCLUSIVE: int = 2
const WINDOW_MODE_NAMES: Array[String] = ["Fenster", "Vollbild randlos", "Vollbild exklusiv"]

## Bildraten-Grenze in Bildern je Sekunde, 0 = keine Grenze.
const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144, 165, 240]

## Auflösungs-Skalierung der 3D-Ansicht: 1.0 = volle Auflösung, kleiner = schneller und unschärfer.
const RENDER_SCALE_MIN: float = 0.5
const RENDER_SCALE_MAX: float = 1.0
const RENDER_SCALE_STEP: float = 0.05

## Kantenglättung (MSAA): Index in MSAA_NAMES, entspricht Viewport.MSAA_*.
const MSAA_NAMES: Array[String] = ["Aus", "2-fach", "4-fach", "8-fach"]

static var mouse_sensitivity: float = MOUSE_SENSITIVITY_DEFAULT
static var fov: float = Balance.PLAYER_FOV
static var window_mode: int = WINDOW_WINDOWED
static var vsync: bool = true
static var fps_limit: int = 0
static var render_scale: float = 1.0
static var msaa: int = 0
static var show_fps: bool = false
static var _loaded: bool = false


## Lädt die Einstellungen einmal je Programmlauf. Headless passiert nichts.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if _uses_user_file():
		load_from(PATH)


## Setzt die Mausempfindlichkeit (auf den erlaubten Bereich und das Raster begrenzt).
static func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(snappedf(value, MOUSE_SENSITIVITY_STEP), MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)


static func set_fov(value: float) -> void:
	fov = clampf(snappedf(value, FOV_STEP), FOV_MIN, FOV_MAX)


static func set_window_mode(value: int) -> void:
	window_mode = clampi(value, 0, WINDOW_MODE_NAMES.size() - 1)


static func set_vsync(value: bool) -> void:
	vsync = value


## Nimmt nur Werte aus FPS_LIMITS an, alles andere wird zum nächstliegenden erlaubten Wert.
static func set_fps_limit(value: int) -> void:
	var best: int = FPS_LIMITS[0]
	for limit: int in FPS_LIMITS:
		if absi(limit - value) < absi(best - value):
			best = limit
	fps_limit = best


static func set_render_scale(value: float) -> void:
	render_scale = clampf(snappedf(value, RENDER_SCALE_STEP), RENDER_SCALE_MIN, RENDER_SCALE_MAX)


static func set_msaa(value: int) -> void:
	msaa = clampi(value, 0, MSAA_NAMES.size() - 1)


static func set_show_fps(value: bool) -> void:
	show_fps = value


## Wert einer Einstellung über ihren Namen (so heißt auch die Variable), null bei fremdem Namen.
static func get_value(id: String) -> Variant:
	match id:
		"mouse_sensitivity": return mouse_sensitivity
		"fov": return fov
		"window_mode": return window_mode
		"vsync": return vsync
		"fps_limit": return fps_limit
		"render_scale": return render_scale
		"msaa": return msaa
		"show_fps": return show_fps
	return null


## Setzt eine Einstellung über ihren Namen. Der Wert läuft durch den Setter (Begrenzung).
static func set_value(id: String, value: Variant) -> void:
	match id:
		"mouse_sensitivity": set_mouse_sensitivity(float(value))
		"fov": set_fov(float(value))
		"window_mode": set_window_mode(int(value))
		"vsync": set_vsync(bool(value))
		"fps_limit": set_fps_limit(int(value))
		"render_scale": set_render_scale(float(value))
		"msaa": set_msaa(int(value))
		"show_fps": set_show_fps(bool(value))


## Stellt alle Werte auf den Standard zurück (speichert nicht).
static func reset_to_defaults() -> void:
	mouse_sensitivity = MOUSE_SENSITIVITY_DEFAULT
	fov = Balance.PLAYER_FOV
	window_mode = WINDOW_WINDOWED
	vsync = true
	fps_limit = 0
	render_scale = 1.0
	msaa = 0
	show_fps = false


## Überträgt die Grafikwerte auf das Fenster und die Engine. window ist das Hauptfenster
## (get_window() eines Knotens im Baum). Headless passiert nichts.
static func apply_video(window: Window) -> void:
	if not _uses_user_file():
		return
	var wanted_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_WINDOWED
	if window_mode == WINDOW_BORDERLESS:
		wanted_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	elif window_mode == WINDOW_EXCLUSIVE:
		wanted_mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var current_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	# Ein maximiertes Fenster bleibt maximiert: Nur zwischen Fenster und Vollbild wird umgeschaltet.
	var is_fullscreen: bool = current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if wanted_mode != current_mode and (is_fullscreen or wanted_mode != DisplayServer.WINDOW_MODE_WINDOWED):
		DisplayServer.window_set_mode(wanted_mode)
	var wanted_vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != wanted_vsync:
		DisplayServer.window_set_vsync_mode(wanted_vsync)
	Engine.max_fps = fps_limit
	if is_instance_valid(window):
		window.scaling_3d_scale = render_scale
		window.msaa_3d = msaa as Viewport.MSAA


## Speichert in die Datei des Nutzers. Headless passiert nichts.
static func save() -> void:
	if _uses_user_file():
		save_to(PATH)


## Liest die Einstellungen aus path. Fehlt die Datei oder ein Wert, bleibt der aktuelle Wert.
static func load_from(path: String) -> bool:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return false
	set_mouse_sensitivity(_number(config, SECTION_INPUT, "mausempfindlichkeit", mouse_sensitivity))
	set_fov(_number(config, SECTION_VIDEO, "sichtfeld", fov))
	set_window_mode(int(_number(config, SECTION_VIDEO, "fenstermodus", float(window_mode))))
	set_vsync(_flag(config, SECTION_VIDEO, "vsync", vsync))
	set_fps_limit(int(_number(config, SECTION_VIDEO, "bildraten_grenze", float(fps_limit))))
	set_render_scale(_number(config, SECTION_VIDEO, "aufloesung_skalierung", render_scale))
	set_msaa(int(_number(config, SECTION_VIDEO, "kantenglaettung", float(msaa))))
	set_show_fps(_flag(config, SECTION_VIDEO, "fps_anzeige", show_fps))
	return true


## Schreibt die Einstellungen nach path.
static func save_to(path: String) -> bool:
	var config: ConfigFile = ConfigFile.new()
	# Vorhandene Datei zuerst laden, damit fremde Einträge erhalten bleiben.
	config.load(path)
	config.set_value(SECTION_INPUT, "mausempfindlichkeit", mouse_sensitivity)
	config.set_value(SECTION_VIDEO, "sichtfeld", fov)
	config.set_value(SECTION_VIDEO, "fenstermodus", window_mode)
	config.set_value(SECTION_VIDEO, "vsync", vsync)
	config.set_value(SECTION_VIDEO, "bildraten_grenze", fps_limit)
	config.set_value(SECTION_VIDEO, "aufloesung_skalierung", render_scale)
	config.set_value(SECTION_VIDEO, "kantenglaettung", msaa)
	config.set_value(SECTION_VIDEO, "fps_anzeige", show_fps)
	return config.save(path) == OK


## Zahl aus der Datei. Steht dort etwas anderes als eine Zahl, gilt fallback.
static func _number(config: ConfigFile, section: String, key: String, fallback: float) -> float:
	var value: Variant = config.get_value(section, key, fallback)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


static func _flag(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value: Variant = config.get_value(section, key, fallback)
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	return fallback


static func _uses_user_file() -> bool:
	return DisplayServer.get_name() != "headless"
