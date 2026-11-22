extends RefCounted
## Einstellungen des Spielers, die über das Programmende hinaus gelten: Lautstärke (gesamt, Musik,
## Geräusche), Mausempfindlichkeit, Sichtfeld, Fenstermodus, VSync, Bildraten-Grenze,
## Auflösungs-Skalierung, Kantenglättung, Grafik-Unterbau und die FPS-Anzeige.
## Gespeichert in user://settings.cfg (unter Windows: %APPDATA%\Godot\app_userdata\Zombie-Shooter).
## Der Grafik-Unterbau steht als einziger Wert in einer eigenen Datei (user://start.cfg), weil die
## Engine ihn schon vor dem ersten Skript braucht: project.godot nennt diese Datei unter
## application/config/project_settings_override, Godot liest sie beim Start selbst.
##
## Nur statische Funktionen und Werte. Einbinden mit preload.
## Jeder Wert hat einen Setter, der ihn auf den erlaubten Bereich begrenzt. apply_video überträgt
## die Grafikwerte auf Fenster und Engine, apply_audio die drei Lautstärken auf die Busse Master,
## Music und Sfx (und legt die Busse an, falls es sie noch nicht gibt, siehe audio_buses.gd). Das
## Sichtfeld liest der Spieler selbst (jedes Bild), die FPS-Anzeige liest das HUD.
## Headless (Tests) wird die Datei des Nutzers weder gelesen noch geschrieben, und apply_video
## tut nichts (apply_audio wirkt auch dort): Tests laufen immer mit den Standardwerten. Mit einem eigenen Pfad lassen sich
## load_from und save_to trotzdem testen.

const Balance := preload("res://scripts/core/balance.gd")
const AudioBuses := preload("res://scripts/game/audio/audio_buses.gd")

const PATH: String = "user://settings.cfg"
## Startdatei für die Engine (siehe oben). Muss so heißen wie in project.godot.
const START_PATH: String = "user://start.cfg"
const START_SECTION: String = "rendering"
const START_KEY: String = "gl_compatibility/driver.windows"
const SECTION_INPUT: String = "eingabe"
const SECTION_VIDEO: String = "grafik"
const SECTION_AUDIO: String = "ton"

## Gesamtlautstärke: 0.0 = stumm, 1.0 = volle Lautstärke.
const MASTER_VOLUME_DEFAULT: float = 0.8
const MASTER_VOLUME_MIN: float = 0.0
const MASTER_VOLUME_MAX: float = 1.0
const MASTER_VOLUME_STEP: float = 0.05
## Nummer des Master-Busses im AudioServer.
const MASTER_BUS: int = 0
## Lautstärke der Musik (Bus Music) und der Geräusche (Bus Sfx mit dem Hall-Bus darunter), jeweils
## 0.0 = stumm bis 1.0 = voll, im selben Raster wie die Gesamtlautstärke. Die Musik steht mit
## Absicht unter den Geräuschen: Sie soll tragen, nicht übertönen.
const MUSIC_VOLUME_DEFAULT: float = 0.7
const SFX_VOLUME_DEFAULT: float = 1.0

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

## Auflösungs-Skalierung der 3D-Ansicht: 1.0 = volle Auflösung, kleiner = unschärfer. Schneller wird
## es dadurch mit dem Treiber ANGLE nicht: Jeder Wert unter 1.0 kostete in der Messung etwa 9 ms je
## Bild zusätzlich (tests/perf_late.gd mit "skala=0.75"), mit dem OpenGL-Treiber der Grafikkarte nichts.
const RENDER_SCALE_MIN: float = 0.5
const RENDER_SCALE_MAX: float = 1.0
const RENDER_SCALE_STEP: float = 0.05

## Kantenglättung (MSAA): Index in MSAA_NAMES, entspricht Viewport.MSAA_*.
const MSAA_NAMES: Array[String] = ["Aus", "2-fach", "4-fach", "8-fach"]

## Grafik-Unterbau: Index in DRIVER_IDS. Wirkt erst beim nächsten Programmstart.
## Sicher = ANGLE (Direct3D 11): startet sofort (Vorwärmen etwa 0,3 s), kein Shader-Ruckler.
## Schnell = OpenGL-Treiber der Grafikkarte: gemessen 2- bis 3-fache Bildrate, dafür dauert das
## Vorwärmen bei jedem Start 10 bis 15 s (docs/ARCHITEKTUR.md Abschnitt 15, 28 und 29).
const DRIVER_SAFE: int = 0
const DRIVER_FAST: int = 1
const DRIVER_IDS: Array[String] = ["opengl3_angle", "opengl3"]
const DRIVER_NAMES: Array[String] = ["Sicher", "Schnell"]

static var master_volume: float = MASTER_VOLUME_DEFAULT
static var music_volume: float = MUSIC_VOLUME_DEFAULT
static var sfx_volume: float = SFX_VOLUME_DEFAULT
static var mouse_sensitivity: float = MOUSE_SENSITIVITY_DEFAULT
static var fov: float = Balance.PLAYER_FOV
static var window_mode: int = WINDOW_WINDOWED
static var vsync: bool = true
static var fps_limit: int = 0
static var render_scale: float = 1.0
static var msaa: int = 0
static var graphics_driver: int = DRIVER_SAFE
static var show_fps: bool = false
static var _loaded: bool = false


## Lädt die Einstellungen einmal je Programmlauf. Headless passiert nichts.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if _uses_user_file():
		load_from(PATH)
		load_start_from(START_PATH)


## Setzt die Gesamtlautstärke (0.0 bis 1.0, im Raster von 0.05). Wirkt erst mit apply_audio.
static func set_master_volume(value: float) -> void:
	master_volume = clampf(snappedf(value, MASTER_VOLUME_STEP), MASTER_VOLUME_MIN, MASTER_VOLUME_MAX)


## Setzt die Lautstärke der Musik (0.0 bis 1.0, im Raster von 0.05). Wirkt erst mit apply_audio.
static func set_music_volume(value: float) -> void:
	music_volume = clampf(snappedf(value, MASTER_VOLUME_STEP), MASTER_VOLUME_MIN, MASTER_VOLUME_MAX)


## Setzt die Lautstärke der Geräusche (0.0 bis 1.0, im Raster von 0.05). Wirkt erst mit apply_audio.
static func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(snappedf(value, MASTER_VOLUME_STEP), MASTER_VOLUME_MIN, MASTER_VOLUME_MAX)


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


## Wählt den Grafik-Unterbau für den nächsten Programmstart (DRIVER_SAFE oder DRIVER_FAST).
static func set_graphics_driver(value: int) -> void:
	graphics_driver = clampi(value, 0, DRIVER_IDS.size() - 1)


## Mit welchem Unterbau läuft das Programm gerade? (Alles außer dem OpenGL-Treiber zählt als sicher.)
static func active_driver() -> int:
	if RenderingServer.get_current_rendering_driver_name() == DRIVER_IDS[DRIVER_FAST]:
		return DRIVER_FAST
	return DRIVER_SAFE


## Ist ein anderer Unterbau gewählt, als gerade läuft? Dann gilt die Wahl erst nach einem Neustart.
static func restart_needed() -> bool:
	return graphics_driver != active_driver()


static func set_show_fps(value: bool) -> void:
	show_fps = value


## Wert einer Einstellung über ihren Namen (so heißt auch die Variable), null bei fremdem Namen.
static func get_value(id: String) -> Variant:
	match id:
		"master_volume": return master_volume
		"music_volume": return music_volume
		"sfx_volume": return sfx_volume
		"mouse_sensitivity": return mouse_sensitivity
		"fov": return fov
		"window_mode": return window_mode
		"vsync": return vsync
		"fps_limit": return fps_limit
		"render_scale": return render_scale
		"msaa": return msaa
		"graphics_driver": return graphics_driver
		"show_fps": return show_fps
	return null


## Setzt eine Einstellung über ihren Namen. Der Wert läuft durch den Setter (Begrenzung).
static func set_value(id: String, value: Variant) -> void:
	match id:
		"master_volume": set_master_volume(float(value))
		"music_volume": set_music_volume(float(value))
		"sfx_volume": set_sfx_volume(float(value))
		"mouse_sensitivity": set_mouse_sensitivity(float(value))
		"fov": set_fov(float(value))
		"window_mode": set_window_mode(int(value))
		"vsync": set_vsync(bool(value))
		"fps_limit": set_fps_limit(int(value))
		"render_scale": set_render_scale(float(value))
		"msaa": set_msaa(int(value))
		"graphics_driver": set_graphics_driver(int(value))
		"show_fps": set_show_fps(bool(value))


## Stellt alle Werte auf den Standard zurück (speichert nicht).
static func reset_to_defaults() -> void:
	master_volume = MASTER_VOLUME_DEFAULT
	music_volume = MUSIC_VOLUME_DEFAULT
	sfx_volume = SFX_VOLUME_DEFAULT
	mouse_sensitivity = MOUSE_SENSITIVITY_DEFAULT
	fov = Balance.PLAYER_FOV
	window_mode = WINDOW_WINDOWED
	vsync = true
	fps_limit = 0
	render_scale = 1.0
	msaa = 0
	graphics_driver = DRIVER_SAFE
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


## Überträgt die Lautstärken auf die Busse: gesamt auf Master, Musik auf Music, Geräusche auf Sfx
## (bei 0 ist der Bus stumm geschaltet). Legt die Busse und ihre Effekte an, falls es sie noch
## nicht gibt. Wirkt anders als apply_video auch headless.
static func apply_audio() -> void:
	AudioBuses.ensure()
	AudioBuses.set_bus_level(AudioBuses.MASTER, master_volume)
	AudioBuses.set_bus_level(AudioBuses.MUSIC, music_volume)
	AudioBuses.set_bus_level(AudioBuses.SFX, sfx_volume)


## Speichert in die Dateien des Nutzers (Einstellungen und Startdatei). Headless passiert nichts.
static func save() -> void:
	if _uses_user_file():
		save_to(PATH)
		save_start_to(START_PATH)


## Liest den gewählten Grafik-Unterbau aus der Startdatei. Fehlt die Datei oder steht dort ein
## fremder Name, bleibt der aktuelle Wert.
static func load_start_from(path: String) -> bool:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return false
	var index: int = DRIVER_IDS.find(str(config.get_value(START_SECTION, START_KEY, "")))
	if index >= 0:
		set_graphics_driver(index)
	return true


## Schreibt den gewählten Grafik-Unterbau in die Startdatei (das Format einer Godot-Projektdatei:
## Abschnitt rendering, Schlüssel gl_compatibility/driver.windows).
static func save_start_to(path: String) -> bool:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(START_SECTION, START_KEY, DRIVER_IDS[graphics_driver])
	return config.save(path) == OK


## Liest die Einstellungen aus path. Fehlt die Datei oder ein Wert, bleibt der aktuelle Wert.
static func load_from(path: String) -> bool:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return false
	set_master_volume(_number(config, SECTION_AUDIO, "lautstaerke", master_volume))
	set_music_volume(_number(config, SECTION_AUDIO, "musik", music_volume))
	set_sfx_volume(_number(config, SECTION_AUDIO, "geraeusche", sfx_volume))
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
	config.set_value(SECTION_AUDIO, "lautstaerke", master_volume)
	config.set_value(SECTION_AUDIO, "musik", music_volume)
	config.set_value(SECTION_AUDIO, "geraeusche", sfx_volume)
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
