extends SceneTree
## Tests für den Ton: die Dateien in res://audio, das Modul scripts/game/audio/sfx.gd, die Musik
## (music.gd), die Busse (audio_buses.gd) und die Lautstärke-Einstellungen
## (scripts/game/settings.gd, Regler in scripts/ui/settings_menu.gd).
## Headless gibt es kein Ausgabegerät, die Spieler-Knoten arbeiten trotzdem. Das Modul startet
## sie headless von sich aus nicht (playback_enabled), dieser Test schaltet sie ein und wartet am
## Ende, bis alles verklungen ist: Sonst meldet Godot beim Beenden verlorene Objekte.
## Geprüft wird über get_play_count, welches Geräusch wie oft gestartet wurde.
## Die Datei des Nutzers (user://settings.cfg) wird weder gelesen noch geschrieben.

const TEMP_SETTINGS: String = "user://test_audio_settings_tmp.cfg"
const TEMP_WAV: String = "user://test_audio_tmp.wav"
const AUDIO_DIR: String = "res://audio/"
const WEAPON_IDS: Array[String] = ["pistol", "revolver", "smg", "sawed_off", "shotgun", "rifle", "sniper",
	"minigun", "rocket_launcher",
	"burst_pistol", "nail_gun", "machine_pistol", "crossbow", "grenade_launcher", "flamethrower", "beam",
	"tesla", "lmg", "auto_shotgun"]
## Waffen, die als Dauerstrom feuern: Ihr Geräusch hat einen Mindestabstand.
const STREAM_WEAPON_IDS: Array[String] = ["flamethrower", "beam"]
## Kameratyp -> Geräusch bei camera_fired.
const CAMERA_SOUNDS: Dictionary = {
	"drone": "drone_shot",
	"cam_tele": "cam_tele",
	"cam_flash": "cam_flash",
	"cam_slow": "cam_slow",
	"cam_director": "cam_director",
}
## Schadensquellen, die bei zombie_damaged kein Geräusch haben (Kameras klingen über camera_fired,
## die Mine über explosion, der Rest ist von sich aus stumm).
const SILENT_SOURCES: Array[String] = ["drone", "cam_tele", "cam_flash", "cam_slow", "cam_director", "mine",
	"burn", "poison", "disco", "frost"]
const GROANS: Array[String] = ["zombie_groan_1", "zombie_groan_2", "zombie_groan_3"]
## Alle Geräusche, die es geben muss (Dateiname ohne Endung).
const REQUIRED: Array[String] = [
	"shot_pistol", "shot_revolver", "shot_smg", "shot_sawed_off", "shot_shotgun", "shot_rifle",
	"shot_sniper", "shot_minigun", "shot_rocket_launcher",
	"reload_start", "reload_done", "hit", "headshot",
	"zombie_death", "zombie_groan_1", "zombie_groan_2", "zombie_groan_3", "elite_roar",
	"player_hurt", "shield_hit", "shield_recharge", "dash",
	"chest_drop", "chest_open", "card_chosen", "upgrade", "synergy",
	"backpack_open", "backpack_close", "item_sold", "purchase",
	"wave_start", "wave_cleared", "countdown_tick", "game_over",
	"ui_hover", "ui_click", "explosion", "lightning", "drone_shot",
	# Ausbau 3.
	"shot_burst_pistol", "shot_nail_gun", "shot_machine_pistol", "shot_crossbow", "shot_grenade_launcher",
	"shot_flamethrower", "shot_beam", "shot_tesla", "shot_lmg", "shot_auto_shotgun",
	"cam_tele", "cam_flash", "cam_slow", "cam_director",
	"mine_placed", "mine_triggered", "player_revived", "pack_unlocked", "bank_coins", "ricochet", "thorns",
	# Ausbau 4.
	"step", "land", "heartbeat", "crowd_cheer", "crowd_gasp", "crowd_aww",
	"item_repaired", "item_scrapped", "material_gain",
]
## Geräusche mit mehreren Dateien (name.wav, name_2.wav ...) und ihre Zahl.
const VARIANTS: Dictionary = {
	"shot_pistol": 3, "shot_smg": 3, "shot_rifle": 3, "shot_minigun": 3, "shot_burst_pistol": 3,
	"shot_nail_gun": 3, "shot_machine_pistol": 3, "shot_lmg": 3, "shot_auto_shotgun": 3,
	"hit": 3, "zombie_death": 3, "explosion": 3, "step": 4,
}
## Musik: Spur in music.gd -> [Datei, Schleife?].
const MUSIC_LAYERS: Dictionary = {
	"menu": ["music_menu", true],
	"calm": ["music_calm", true],
	"wave": ["music_wave", true],
	"late": ["music_late", true],
	"game_over": ["music_game_over", false],
}
## Die Musikdateien dürfen zusammen höchstens so groß sein (Bytes).
const MUSIC_MAX_BYTES: int = 12 * 1024 * 1024
## Die Schleife des Publikums.
const AMBIENCE_FILE: String = "crowd_murmur"
const MIN_LENGTH: float = 0.03
const MAX_LENGTH: float = 2.5
const MAX_SHOT_LENGTH: float = 0.41
## Wartezeit, nach der jeder Mindestabstand zwischen zwei gleichen Geräuschen vorbei ist
## (außer bei game_over, das nur einmal geprüft wird).
const GAP_WAIT: float = 0.6
## Wartezeit für die Geräusche mit einer Sekunde Mindestabstand (bank_coins, player_revived, game_over).
const LONG_GAP_WAIT: float = 1.1
## Dauerfeuer im Test: so viele Schüsse im Abstand von so vielen Sekunden (20 je Sekunde über 2 s).
const STREAM_SHOTS: int = 40
const STREAM_SHOT_INTERVAL: float = 0.05

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
var _settings: GDScript
var _sfx_script: GDScript
var _sfx: Node
var _zombie_script: GDScript


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum.
	await process_frame
	_game = root.get_node("Game")
	_events = root.get_node("Events")
	_settings = load("res://scripts/game/settings.gd") as GDScript
	_sfx_script = load("res://scripts/game/audio/sfx.gd") as GDScript
	_test_files()
	_test_music_files()
	_test_volume_setting()
	await _test_start()
	_test_loading()
	await _test_music()
	_test_variants()
	_test_shots()
	await _test_fight_signals()
	await _test_player_signals()
	await _test_show_signals()
	await _test_cameras()
	await _test_items_and_progress()
	await _test_points_and_cards()
	await _test_groans()
	_test_movement()
	_test_heartbeat()
	await _test_crowd_and_materials()
	await _test_limits()
	await _test_stream_fire()
	await _test_buttons()
	await _test_volume_menu()
	# Musik und Raunen laufen als Schleifen: abstellen, anhalten, dann auf Stille warten.
	_sfx.set("playback_enabled", false)
	(_sfx.get("music") as Node).set("playback_enabled", false)
	_sfx.call("stop_all")
	await _wait_silent()
	_check(not _loops_playing(), "Nach stop_all laufen weder Musik noch Raunen.")
	_settings.call("reset_to_defaults")
	_settings.call("apply_audio")
	paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_WAV))
	if _failures == 0:
		print("Alle %d Prüfungen für den Ton bestanden." % _checks)
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


# --- Dateien ------------------------------------------------------------------------------------

func _test_files() -> void:
	for id: String in REQUIRED:
		var path: String = AUDIO_DIR + id + ".wav"
		_check(FileAccess.file_exists(path + ".import"), "Import-Notiz fehlt: %s.import" % path)
		if not ResourceLoader.exists(path):
			_check(false, "Tondatei fehlt oder ist nicht eingelesen: " + path)
			continue
		var stream: AudioStream = load(path) as AudioStream
		_check(stream != null, "Tondatei lädt nicht als AudioStream: " + path)
		if stream == null:
			continue
		var length: float = stream.get_length()
		_check(length >= MIN_LENGTH and length <= MAX_LENGTH, "%s: Länge %.3f s liegt nicht zwischen %.2f und %.1f s." % [id, length, MIN_LENGTH, MAX_LENGTH])
		if id.begins_with("shot_"):
			_check(length <= MAX_SHOT_LENGTH, "%s: Ein Schuss ist höchstens 0,4 s lang, war %.3f s." % [id, length])
	for weapon_id: String in WEAPON_IDS:
		_check(REQUIRED.has("shot_" + weapon_id), "Für die Waffe %s fehlt ein Schuss in der Liste." % weapon_id)
	# Jede Waffe des Spiels hat ihren eigenen Schuss.
	var weapon_defs: GDScript = load("res://scripts/core/weapon_defs.gd") as GDScript
	var all_weapons: Array = weapon_defs.call("all_ids")
	_check(all_weapons.size() == WEAPON_IDS.size(), "Das Spiel hat %d Waffen, der Test kennt %d." % [all_weapons.size(), WEAPON_IDS.size()])
	for weapon_id: String in all_weapons:
		_check(FileAccess.file_exists(AUDIO_DIR + "shot_" + weapon_id + ".wav"), "Für die Waffe %s fehlt die Datei shot_%s.wav." % [weapon_id, weapon_id])
	# Jeder Kameratyp des Spiels hat sein Geräusch.
	var camera_defs: GDScript = load("res://scripts/core/camera_defs.gd") as GDScript
	var all_cameras: Array = camera_defs.call("all_ids")
	_check(all_cameras.size() == CAMERA_SOUNDS.size(), "Das Spiel hat %d Kameratypen, der Test kennt %d." % [all_cameras.size(), CAMERA_SOUNDS.size()])
	for camera_id: String in all_cameras:
		_check(CAMERA_SOUNDS.has(camera_id), "Für den Kameratyp %s fehlt ein Geräusch." % camera_id)
	for camera_id: String in CAMERA_SOUNDS:
		_check(REQUIRED.has(str(CAMERA_SOUNDS[camera_id])), "Das Geräusch des Kameratyps %s fehlt in der Liste." % camera_id)
	# Varianten: Jede weitere Datei ist da, eingelesen und etwa so lang wie die erste.
	for id: String in VARIANTS:
		_check(REQUIRED.has(id), "Das Geräusch %s mit Varianten fehlt in der Liste." % id)
		var first: AudioStream = load(AUDIO_DIR + id + ".wav") as AudioStream
		for number: int in range(2, int(VARIANTS[id]) + 1):
			var path: String = "%s%s_%d.wav" % [AUDIO_DIR, id, number]
			_check(FileAccess.file_exists(path + ".import") and ResourceLoader.exists(path), "Die Variante fehlt oder ist nicht eingelesen: " + path)
			if not ResourceLoader.exists(path):
				continue
			var variant: AudioStream = load(path) as AudioStream
			_check(variant != null and first != null, "Die Variante lädt nicht: " + path)
			if variant == null or first == null:
				continue
			_check(variant.get_length() >= MIN_LENGTH and variant.get_length() <= MAX_LENGTH, "%s: Länge %.3f s liegt nicht im erlaubten Bereich." % [path, variant.get_length()])
			_check(absf(variant.get_length() - first.get_length()) <= 0.25, "%s: Die Variante ist etwa so lang wie die erste Datei (%.3f s gegen %.3f s)." % [path, variant.get_length(), first.get_length()])
			if id.begins_with("shot_"):
				_check(variant.get_length() <= MAX_SHOT_LENGTH, "%s: Ein Schuss ist höchstens 0,4 s lang, war %.3f s." % [path, variant.get_length()])


## Musik und die Schleife des Publikums: Dateien da, eingelesen, Schleifen als Schleife geladen.
func _test_music_files() -> void:
	var total_bytes: int = 0
	var loop_ends: Dictionary = {}
	for layer: String in MUSIC_LAYERS:
		var file_name: String = str((MUSIC_LAYERS[layer] as Array)[0])
		var loops: bool = bool((MUSIC_LAYERS[layer] as Array)[1])
		var path: String = AUDIO_DIR + file_name + ".wav"
		_check(FileAccess.file_exists(path + ".import") and ResourceLoader.exists(path), "Musikdatei fehlt oder ist nicht eingelesen: " + path)
		if not ResourceLoader.exists(path):
			continue
		total_bytes += FileAccess.get_file_as_bytes(path).size()
		var wav: AudioStreamWAV = load(path) as AudioStreamWAV
		_check(wav != null, "Musikdatei lädt nicht als AudioStreamWAV: " + path)
		if wav == null:
			continue
		_check(wav.stereo, "%s ist Stereo." % file_name)
		_check(wav.mix_rate == 22050, "%s hat 22050 Hz, war %d." % [file_name, wav.mix_rate])
		_check(wav.format == AudioStreamWAV.FORMAT_16_BITS, "%s ist unkomprimiert eingelesen (Format %d)." % [file_name, wav.format])
		_check(wav.get_length() >= 5.0 and wav.get_length() <= 60.0, "%s: Länge %.2f s liegt nicht zwischen 5 und 60 s." % [file_name, wav.get_length()])
		if loops:
			_check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s ist als Schleife geladen (loop_mode %d)." % [file_name, wav.loop_mode])
			_check(wav.loop_begin == 0, "%s: Die Schleife beginnt am Anfang, war %d." % [file_name, wav.loop_begin])
			var frames: int = roundi(wav.get_length() * float(wav.mix_rate))
			_check(wav.loop_end > 0 and wav.loop_end <= frames and wav.loop_end >= frames - 8, "%s: Die Schleife endet am Dateiende (Ende %d von %d Werten)." % [file_name, wav.loop_end, frames])
			loop_ends[layer] = wav.loop_end
		else:
			_check(wav.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s ist keine Schleife." % file_name)
	_check(total_bytes > 0 and total_bytes <= MUSIC_MAX_BYTES, "Die Musik ist zusammen höchstens 12 MB groß, war %.2f MB." % (float(total_bytes) / 1048576.0))
	# Die drei Spuren der Spielmusik laufen gemeinsam: gleiche Länge oder ein ganzes Vielfaches.
	if loop_ends.has("calm") and loop_ends.has("wave") and loop_ends.has("late"):
		_check(int(loop_ends["wave"]) == int(loop_ends["late"]), "music_wave und music_late sind gleich lang.")
		_check(int(loop_ends["wave"]) % int(loop_ends["calm"]) == 0, "music_wave ist ein ganzes Vielfaches von music_calm lang (%d und %d Werte)." % [int(loop_ends["wave"]), int(loop_ends["calm"])])
		# 126 Schläge je Minute bei 22050 Hz: Ein Takt hat genau 42000 Werte.
		_check(int(loop_ends["calm"]) % 42000 == 0 and int(loop_ends["wave"]) % 42000 == 0, "Die Spielmusik ist ganze Takte lang.")
	if loop_ends.has("menu"):
		_check(int(loop_ends["menu"]) % 50400 == 0, "Die Menümusik ist ganze Takte lang (105 Schläge je Minute: 50400 Werte je Takt).")
	var murmur_path: String = AUDIO_DIR + AMBIENCE_FILE + ".wav"
	_check(ResourceLoader.exists(murmur_path), "Die Schleife des Publikums fehlt oder ist nicht eingelesen: " + murmur_path)
	if ResourceLoader.exists(murmur_path):
		var murmur: AudioStreamWAV = load(murmur_path) as AudioStreamWAV
		_check(murmur != null and murmur.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Das Raunen des Publikums ist als Schleife geladen.")
		if murmur != null:
			_check(murmur.loop_begin == 0 and murmur.loop_end > 0, "Das Raunen hat Schleifenpunkte.")
			_check(murmur.get_length() >= 4.0, "Das Raunen ist mindestens 4 s lang, war %.2f s." % murmur.get_length())
	# Eine Datei ohne Schleifenpunkte wird im Code zur Schleife erklärt, eine mit bleibt, wie sie ist.
	var loader: GDScript = load("res://scripts/game/audio/audio_loader.gd") as GDScript
	var plain: AudioStreamWAV = AudioStreamWAV.new()
	plain.format = AudioStreamWAV.FORMAT_16_BITS
	plain.mix_rate = 22050
	var silence: PackedByteArray = PackedByteArray()
	silence.resize(2 * 2205)
	plain.data = silence
	_check(not bool(loader.call("is_loop", plain)), "Eine frische Datei ist keine Schleife.")
	_check(bool(loader.call("ensure_loop", plain)), "ensure_loop macht eine Datei ohne Schleifenpunkte zur Schleife.")
	_check(plain.loop_mode == AudioStreamWAV.LOOP_FORWARD and plain.loop_begin == 0 and plain.loop_end == 2205, "Die ganze Datei ist dann die Schleife (Ende %d)." % plain.loop_end)
	plain.loop_end = 1000
	loader.call("ensure_loop", plain)
	_check(plain.loop_end == 1000, "Vorhandene Schleifenpunkte bleiben stehen.")
	_check(not bool(loader.call("ensure_loop", null)), "ensure_loop ohne Datei meldet false.")


# --- Lautstärke-Einstellung -----------------------------------------------------------------------

func _volume() -> float:
	return float(_settings.get("master_volume"))


func _master_db() -> float:
	return AudioServer.get_bus_volume_db(0)


func _bus_db(bus_name: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus_name))


func _bus_mute(bus_name: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus_name))


func _test_volume_setting() -> void:
	_settings.call("reset_to_defaults")
	_near(_volume(), 0.8, "Standard-Lautstärke 0,8.")
	_settings.call("set_master_volume", 5.0)
	_near(_volume(), 1.0, "Lautstärke höchstens 1,0.")
	_settings.call("set_master_volume", -1.0)
	_near(_volume(), 0.0, "Lautstärke mindestens 0,0.")
	_settings.call("set_master_volume", 0.33)
	_near(_volume(), 0.35, "Lautstärke rastet im Raster von 0,05 ein.")
	_settings.call("set_value", "master_volume", 0.6)
	_near(_volume(), 0.6, "set_value setzt die Lautstärke über ihren Namen.")
	_near(float(_settings.call("get_value", "master_volume")), 0.6, "get_value liefert die Lautstärke.")
	# Durch die Datei und zurück.
	_settings.call("set_master_volume", 0.45)
	_check(bool(_settings.call("save_to", TEMP_SETTINGS)), "save_to schreibt die Lautstärke.")
	var written: ConfigFile = ConfigFile.new()
	written.load(TEMP_SETTINGS)
	_check(written.has_section_key("ton", "lautstaerke"), "Die Lautstärke steht im Abschnitt ton unter lautstaerke.")
	_settings.call("reset_to_defaults")
	_check(bool(_settings.call("load_from", TEMP_SETTINGS)), "load_from liest die Datei.")
	_near(_volume(), 0.45, "Die gespeicherte Lautstärke kommt zurück.")
	# Unsinn in der Datei: Text wird übergangen, eine zu große Zahl begrenzt.
	var config: ConfigFile = ConfigFile.new()
	config.set_value("ton", "lautstaerke", "laut")
	config.save(TEMP_SETTINGS)
	_settings.call("load_from", TEMP_SETTINGS)
	_near(_volume(), 0.45, "Text statt Zahl ändert die Lautstärke nicht.")
	config.set_value("ton", "lautstaerke", 7.0)
	config.save(TEMP_SETTINGS)
	_settings.call("load_from", TEMP_SETTINGS)
	_near(_volume(), 1.0, "Eine zu große Lautstärke aus der Datei wird begrenzt.")
	# Eine alte Datei ohne den Abschnitt lässt den Wert stehen.
	_settings.call("set_master_volume", 0.7)
	var old_file: ConfigFile = ConfigFile.new()
	old_file.set_value("eingabe", "mausempfindlichkeit", 1.0)
	old_file.save(TEMP_SETTINGS)
	_settings.call("load_from", TEMP_SETTINGS)
	_near(_volume(), 0.7, "Fehlt die Lautstärke in der Datei, bleibt der aktuelle Wert.")
	# apply_audio wirkt auch headless auf den Master-Bus.
	_settings.call("set_master_volume", 0.5)
	_settings.call("apply_audio")
	_check(absf(_master_db() - linear_to_db(0.5)) < 0.01, "apply_audio setzt den Master-Bus auf %.2f dB, war %.2f dB." % [linear_to_db(0.5), _master_db()])
	_check(not AudioServer.is_bus_mute(0), "Bei 50 Prozent ist der Master-Bus nicht stumm.")
	_settings.call("set_master_volume", 0.0)
	_settings.call("apply_audio")
	_check(AudioServer.is_bus_mute(0), "Bei 0 Prozent ist der Master-Bus stumm.")
	_settings.call("set_master_volume", 1.0)
	_settings.call("apply_audio")
	_check(not AudioServer.is_bus_mute(0), "Über 0 Prozent ist der Master-Bus wieder zu hören.")
	_check(absf(_master_db()) < 0.01, "Bei 100 Prozent steht der Master-Bus auf 0 dB, war %.2f dB." % _master_db())
	_settings.call("reset_to_defaults")
	_near(_volume(), 0.8, "reset_to_defaults stellt die Lautstärke zurück.")
	# Musik und Geräusche: eigene Werte, eigene Busse.
	_near(float(_settings.get("music_volume")), 0.7, "Standard-Lautstärke der Musik 0,7.")
	_near(float(_settings.get("sfx_volume")), 1.0, "Standard-Lautstärke der Geräusche 1,0.")
	for id: String in ["music_volume", "sfx_volume"]:
		_settings.call("set_value", id, 9.0)
		_near(float(_settings.call("get_value", id)), 1.0, "%s höchstens 1,0." % id)
		_settings.call("set_value", id, -3.0)
		_near(float(_settings.call("get_value", id)), 0.0, "%s mindestens 0,0." % id)
		_settings.call("set_value", id, 0.58)
		_near(float(_settings.call("get_value", id)), 0.6, "%s rastet im Raster von 0,05 ein." % id)
	_settings.call("set_music_volume", 0.25)
	_settings.call("set_sfx_volume", 0.55)
	_settings.call("set_master_volume", 0.9)
	_check(bool(_settings.call("save_to", TEMP_SETTINGS)), "save_to schreibt alle drei Lautstärken.")
	var saved: ConfigFile = ConfigFile.new()
	saved.load(TEMP_SETTINGS)
	_near(float(saved.get_value("ton", "musik", -1.0)), 0.25, "Die Musik-Lautstärke steht im Abschnitt ton unter musik.")
	_near(float(saved.get_value("ton", "geraeusche", -1.0)), 0.55, "Die Geräusch-Lautstärke steht im Abschnitt ton unter geraeusche.")
	_settings.call("reset_to_defaults")
	_settings.call("load_from", TEMP_SETTINGS)
	_near(float(_settings.get("music_volume")), 0.25, "Die gespeicherte Musik-Lautstärke kommt zurück.")
	_near(float(_settings.get("sfx_volume")), 0.55, "Die gespeicherte Geräusch-Lautstärke kommt zurück.")
	_near(_volume(), 0.9, "Die Gesamtlautstärke kommt mit zurück.")
	# Jeder Wert wirkt auf seinen eigenen Bus und nur auf den.
	_settings.call("apply_audio")
	_check(AudioServer.get_bus_index("Music") != -1 and AudioServer.get_bus_index("Sfx") != -1, "apply_audio legt die Busse Music und Sfx an.")
	_check(absf(_bus_db("Music") - linear_to_db(0.25)) < 0.01, "Die Musik-Lautstärke steht auf dem Bus Music (erwartet %.2f dB, war %.2f dB)." % [linear_to_db(0.25), _bus_db("Music")])
	_check(absf(_bus_db("Sfx") - linear_to_db(0.55)) < 0.01, "Die Geräusch-Lautstärke steht auf dem Bus Sfx (erwartet %.2f dB, war %.2f dB)." % [linear_to_db(0.55), _bus_db("Sfx")])
	_check(absf(_master_db() - linear_to_db(0.9)) < 0.01, "Die Gesamtlautstärke steht weiter auf dem Master-Bus.")
	_check(absf(_bus_db("Reverb")) < 0.01, "Der Hall-Bus bleibt auf 0 dB: Er hängt am Bus Sfx.")
	_settings.call("set_music_volume", 0.0)
	_settings.call("apply_audio")
	_check(_bus_mute("Music") and not _bus_mute("Sfx") and not AudioServer.is_bus_mute(0), "Musik auf 0: Nur der Bus Music ist stumm.")
	_settings.call("set_music_volume", 0.4)
	_settings.call("set_sfx_volume", 0.0)
	_settings.call("apply_audio")
	_check(_bus_mute("Sfx") and not _bus_mute("Music"), "Geräusche auf 0: Nur der Bus Sfx ist stumm.")
	# Eine alte Datei ohne die neuen Werte lässt sie stehen.
	var old_audio: ConfigFile = ConfigFile.new()
	old_audio.set_value("ton", "lautstaerke", 0.5)
	old_audio.save(TEMP_SETTINGS)
	_settings.call("set_sfx_volume", 0.8)
	_settings.call("load_from", TEMP_SETTINGS)
	_near(float(_settings.get("music_volume")), 0.4, "Fehlt die Musik-Lautstärke in der Datei, bleibt der aktuelle Wert.")
	_near(float(_settings.get("sfx_volume")), 0.8, "Fehlt die Geräusch-Lautstärke in der Datei, bleibt der aktuelle Wert.")
	_settings.call("reset_to_defaults")
	_settings.call("apply_audio")
	_near(float(_settings.get("music_volume")), 0.7, "reset_to_defaults stellt die Musik zurück.")
	_near(float(_settings.get("sfx_volume")), 1.0, "reset_to_defaults stellt die Geräusche zurück.")
	_check(not _bus_mute("Music") and not _bus_mute("Sfx"), "Mit dem Standard sind beide Busse zu hören.")
	_check(absf(_bus_db("Music") - linear_to_db(0.7)) < 0.01 and absf(_bus_db("Sfx")) < 0.01, "Mit dem Standard steht Music auf -3,1 dB und Sfx auf 0 dB.")


# --- Start des Moduls -----------------------------------------------------------------------------

func _test_start() -> void:
	# Die Lautstärke wird beim Start des Moduls übertragen.
	_settings.call("set_master_volume", 0.4)
	var buses_before: int = AudioServer.bus_count
	_sfx = _sfx_script.new() as Node
	_sfx.name = "Sfx"
	_check(not bool(_sfx.get("playback_enabled")), "Headless startet das Modul von sich aus keine Spieler.")
	# In diesem Test sollen die Spieler wirklich laufen.
	_sfx.set("playback_enabled", true)
	root.add_child(_sfx)
	await process_frame
	_check(absf(_master_db() - linear_to_db(0.4)) < 0.01, "Das Modul überträgt die Lautstärke beim Start (erwartet %.2f dB, war %.2f dB)." % [linear_to_db(0.4), _master_db()])
	var bus: int = AudioServer.get_bus_index("Sfx")
	_check(bus != -1, "Das Modul legt den Bus Sfx an.")
	if bus != -1:
		_check(AudioServer.get_bus_send(bus) == &"Master", "Der Bus Sfx geht in den Master-Bus.")
	# Der Aufbau der Busse: Master <- Sfx <- Reverb, Master <- Music.
	var room_bus: int = AudioServer.get_bus_index("Reverb")
	var music_bus: int = AudioServer.get_bus_index("Music")
	_check(room_bus != -1 and music_bus != -1, "Es gibt die Busse Reverb und Music.")
	if room_bus != -1 and music_bus != -1:
		_check(AudioServer.get_bus_send(room_bus) == &"Sfx", "Der Hall-Bus geht in den Bus Sfx.")
		_check(AudioServer.get_bus_send(music_bus) == &"Master", "Der Bus Music geht in den Master-Bus.")
	_check(AudioServer.bus_count == 4, "Es gibt genau vier Busse (Master, Sfx, Reverb, Music), waren %d." % AudioServer.bus_count)
	_check(AudioServer.bus_count <= buses_before + 3, "Es kommen höchstens drei Busse dazu.")
	# Die Effekte: Begrenzer auf dem Master, Nachhall auf Reverb, Tiefpass auf Music.
	var buses: GDScript = load("res://scripts/game/audio/audio_buses.gd") as GDScript
	var limiter: AudioEffectHardLimiter = buses.call("limiter") as AudioEffectHardLimiter
	_check(limiter != null, "Auf dem Master-Bus sitzt ein Begrenzer.")
	if limiter != null:
		_check(limiter.ceiling_db <= -0.3 and limiter.ceiling_db >= -3.0, "Die Decke des Begrenzers liegt knapp unter 0 dBFS, war %.2f." % limiter.ceiling_db)
		_check(absf(limiter.pre_gain_db) < 0.01, "Der Begrenzer verstärkt nicht vor.")
		_check(AudioServer.is_bus_effect_enabled(0, 0), "Der Begrenzer ist eingeschaltet.")
	var room: AudioEffectReverb = buses.call("reverb") as AudioEffectReverb
	_check(room != null, "Auf dem Hall-Bus sitzt ein Nachhall.")
	if room != null:
		_check(absf(room.dry - 1.0) < 0.01, "Der Nachhall lässt das Original voll durch.")
		_check(room.wet > 0.02 and room.wet <= 0.3, "Der Nachhall ist dezent (Anteil %.2f)." % room.wet)
		_check(room.room_size > 0.1 and room.room_size <= 0.7, "Der Raum ist ein Studio, keine Halle (Größe %.2f)." % room.room_size)
	var filter: AudioEffectLowPassFilter = buses.call("music_filter") as AudioEffectLowPassFilter
	_check(filter != null, "Auf dem Bus Music sitzt ein Tiefpass.")
	_check(not bool(buses.call("is_music_filter_on")), "Der Tiefpass der Musik ist anfangs aus (Musik läuft unverändert).")
	# Geräusche mit Ort laufen über den Hall-Bus, die anderen zunächst über Sfx.
	for child: Node in _sfx.get_children():
		if child is AudioStreamPlayer3D:
			_check((child as AudioStreamPlayer3D).bus == &"Reverb", "Spieler mit Ort hängen am Hall-Bus.")
		elif child is AudioStreamPlayer:
			_check((child as AudioStreamPlayer).bus == &"Sfx", "Spieler ohne Ort hängen anfangs am Bus Sfx.")
	_check(_sfx.process_mode == Node.PROCESS_MODE_ALWAYS, "Das Modul läuft auch bei pausiertem Baum.")
	# Die Musik ist ein Kind des Moduls und bekommt dessen Schalter für die Spieler.
	var music: Node = _sfx.get("music") as Node
	_check(music != null and music.get_parent() == _sfx and music.name == &"Music", "Das Modul legt die Musik als Kind Music an.")
	if music != null:
		_check(bool(music.get("playback_enabled")), "Die Musik übernimmt playback_enabled vom Modul.")
		_check(music.process_mode == Node.PROCESS_MODE_ALWAYS, "Die Musik läuft auch bei pausiertem Baum.")
		for child: Node in music.get_children():
			_check(child is AudioStreamPlayer and (child as AudioStreamPlayer).bus == &"Music", "Die Abspieler der Musik hängen am Bus Music.")
	# Ein zweiter Knoten (nach einem Neustart der Szene) legt weder Busse noch Effekte doppelt an.
	var bus_count: int = AudioServer.bus_count
	var effects: int = AudioServer.get_bus_effect_count(0) + AudioServer.get_bus_effect_count(room_bus) + AudioServer.get_bus_effect_count(music_bus)
	var second: Node = _sfx_script.new() as Node
	root.add_child(second)
	_check(AudioServer.bus_count == bus_count, "Ein zweites Modul legt keinen zweiten Bus an.")
	_check(AudioServer.get_bus_effect_count(0) + AudioServer.get_bus_effect_count(room_bus) + AudioServer.get_bus_effect_count(music_bus) == effects, "Ein zweites Modul legt keinen Effekt doppelt an.")
	_check(effects == 3, "Es gibt genau drei Effekte (Begrenzer, Nachhall, Tiefpass), waren %d." % effects)
	_check(not bool((second.get("music") as Node).get("playback_enabled")), "Headless startet auch die Musik von sich aus keine Abspieler.")
	second.free()
	_settings.call("reset_to_defaults")
	_settings.call("apply_audio")


func _test_loading() -> void:
	var ids: Array = _sfx.call("sound_ids")
	for id: String in REQUIRED:
		_check(ids.has(id), "sound_ids kennt %s nicht." % id)
		_check(bool(_sfx.call("has_sound", id)), "Das Modul hat %s nicht geladen." % id)
		_check(_count(id) == 0, "%s wurde schon vor dem ersten Signal gestartet." % id)
	_check(ids.size() == REQUIRED.size(), "sound_ids hat %d Einträge, erwartet %d." % [ids.size(), REQUIRED.size()])
	# Varianten: so viele Dateien geladen wie in der Tabelle, alle anderen Geräusche genau eine.
	var table: Dictionary = _sfx_script.get_script_constant_map().get("SOUNDS", {})
	for id: String in REQUIRED:
		var wanted: int = int(VARIANTS.get(id, 1))
		_check(int((table.get(id, {}) as Dictionary).get("variants", 1)) == wanted, "%s: Die Tabelle nennt %d Varianten." % [id, wanted])
		_check(int(_sfx.call("get_variant_count", id)) == wanted, "%s: %d Varianten geladen, erwartet %d." % [id, int(_sfx.call("get_variant_count", id)), wanted])
		_check(int(_sfx.call("get_last_variant", id)) == -1, "%s: Vor dem ersten Start ist keine Variante gemerkt." % id)
	_check(int(_sfx.call("get_variant_count", "gibt_es_nicht")) == 0, "Ein fremder Name hat keine Varianten.")
	_check(str(_sfx_script.call("variant_file", "hit", 0)) == "hit" and str(_sfx_script.call("variant_file", "hit", 2)) == "hit_3", "Die Varianten heißen name, name_2, name_3.")
	# Ein fremder Name ist harmlos.
	_check(not bool(_sfx.call("has_sound", "gibt_es_nicht")), "Ein fremder Name gilt nicht als geladen.")
	_sfx.call("play", "gibt_es_nicht")
	_sfx.call("play_at", "gibt_es_nicht", Vector3(1.0, 2.0, 3.0))
	_sfx.call("play", "gibt_es_nicht", -6.0)
	_check(_count("gibt_es_nicht") == 0, "Ein fremder Name wird nicht gezählt.")
	# Eine fehlende Datei gibt null, ohne Fehlermeldung.
	_check(_sfx.call("_load_stream", AUDIO_DIR + "gibt_es_nicht.wav") == null, "Eine fehlende Datei lädt als null.")
	# Eine rohe WAV-Datei ohne Import wird direkt gelesen.
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(AUDIO_DIR + "hit.wav")
	_check(not raw.is_empty(), "Die rohe Datei hit.wav ist lesbar.")
	var file: FileAccess = FileAccess.open(TEMP_WAV, FileAccess.WRITE)
	if file != null and not raw.is_empty():
		file.store_buffer(raw)
		file.close()
		var direct: AudioStream = _sfx.call("_load_stream", TEMP_WAV) as AudioStream
		_check(direct != null, "Eine WAV-Datei ohne Import wird direkt gelesen.")
		if direct != null:
			_check(direct.get_length() > MIN_LENGTH and direct.get_length() < 0.2, "Die direkt gelesene Datei hat die Länge von hit.wav, war %.3f s." % direct.get_length())
		# Frisch kopiertes Projekt: Die Import-Notiz ist da, die eingelesene Datei aber nicht.
		# Auch dann wird die rohe Datei genommen (load würde hier eine Fehlermeldung drucken).
		var note: ConfigFile = ConfigFile.new()
		note.set_value("remap", "importer", "wav")
		note.set_value("remap", "path", "res://.godot/imported/gibt_es_nicht.sample")
		note.save(TEMP_WAV + ".import")
		_check(not bool(_sfx.call("_is_imported", TEMP_WAV)), "Eine Import-Notiz ohne eingelesene Datei gilt nicht als eingelesen.")
		_check(_sfx.call("_load_stream", TEMP_WAV) != null, "Ohne eingelesene Datei wird die rohe WAV-Datei gelesen.")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_WAV + ".import"))
	_check(bool(_sfx.call("_is_imported", AUDIO_DIR + "hit.wav")), "Die eingelesene Datei hit.wav wird als eingelesen erkannt.")
	# Die öffentlichen Aufrufe starten ein Geräusch.
	var before: int = _count("dash")
	_sfx.call("play", "dash")
	_sfx.call("play_at", "dash", Vector3(3.0, 1.0, -2.0), -3.0)
	_check(_count("dash") == before + 2, "play und play_at starten das Geräusch.")
	_check(_playing_count(false) >= 1, "play startet einen Spieler ohne Ort.")
	_check(_playing_count(true) >= 1, "play_at startet einen Spieler mit Ort.")
	var placed: bool = false
	for child: Node in _sfx.get_children():
		if child is AudioStreamPlayer3D and (child as AudioStreamPlayer3D).global_position.is_equal_approx(Vector3(3.0, 1.0, -2.0)):
			placed = true
	_check(placed, "play_at stellt den Spieler an die gewünschte Stelle.")


# --- Musik ----------------------------------------------------------------------------------------

func _music() -> Node:
	return _sfx.get("music") as Node


func _track() -> String:
	return str(_music().call("get_track"))


func _gain(layer: String) -> float:
	return float(_music().call("get_layer_gain", layer))


func _music_player(player_name: String) -> AudioStreamPlayer:
	return _music().get_node(player_name) as AudioStreamPlayer


## Lautstärke einer Spur der Spielmusik im gemeinsamen Abspieler (dB).
func _stem_db(index: int) -> float:
	var stems: AudioStreamSynchronized = _music_player("Stems").stream as AudioStreamSynchronized
	return stems.get_sync_stream_volume(index) if stems != null else 0.0


## Welches Stück wann läuft, Überblenden, Dämpfen in Pause, Kistenwahl und Rucksack, Zurückdrängen.
## Die Zeit wird mit advance von Hand vorgestellt: Zwischen einem Auslöser und der Prüfung der
## halben Blende liegt kein Bild, die echte Zeit kann das Ergebnis also nicht verschieben.
func _test_music() -> void:
	var music: Node = _music()
	var consts: Dictionary = (music.get_script() as GDScript).get_script_constant_map()
	var fade: float = float(consts.get("FADE_TIME", 0.0))
	var muffle_time: float = float(consts.get("MUFFLE_TIME", 0.0))
	var muffle_db: float = float(consts.get("MUFFLE_DB", 0.0))
	var muffle_cutoff: float = float(consts.get("MUFFLE_CUTOFF", 0.0))
	var layers: Dictionary = consts.get("LAYERS", {})
	var buses: GDScript = load("res://scripts/game/audio/audio_buses.gd") as GDScript
	_check(fade >= 0.5 and fade <= 2.0, "Ein Wechsel blendet in etwa einer Sekunde über, war %.2f s." % fade)
	_check(int(consts.get("LATE_WAVE", 0)) == 10, "Die Zusatzspur kommt ab Welle 10.")
	_check(muffle_db < -2.0 and muffle_cutoff >= 300.0 and muffle_cutoff <= 3000.0, "Gedämpft heißt leiser (%.1f dB) und dumpfer (Tiefpass bei %.0f Hz)." % [muffle_db, muffle_cutoff])
	_check(layers.size() == MUSIC_LAYERS.size(), "Die Musik kennt %d Spuren, erwartet %d." % [layers.size(), MUSIC_LAYERS.size()])
	for layer: String in MUSIC_LAYERS:
		var loops: bool = bool((MUSIC_LAYERS[layer] as Array)[1])
		_check(layers.has(layer) and str((layers.get(layer, {}) as Dictionary).get("file", "")) == str((MUSIC_LAYERS[layer] as Array)[0]), "Die Spur %s spielt die Datei %s." % [layer, str((MUSIC_LAYERS[layer] as Array)[0])])
		_check(bool(music.call("has_layer", layer)), "Die Musik hat die Spur %s geladen." % layer)
		var wav: AudioStreamWAV = music.call("get_layer_stream", layer) as AudioStreamWAV
		if wav != null:
			_check((wav.loop_mode == AudioStreamWAV.LOOP_FORWARD) == loops, "Die Spur %s ist %s geladen." % [layer, "als Schleife" if loops else "ohne Schleife"])
		_check(float((layers.get(layer, {}) as Dictionary).get("db", 1.0)) <= 0.0, "Die Spur %s hat eine Lautstärke in der Tabelle." % layer)
	var stems: AudioStreamSynchronized = _music_player("Stems").stream as AudioStreamSynchronized
	_check(stems != null and stems.stream_count == 3, "Die drei Spuren der Spielmusik laufen gemeinsam in einem Abspieler.")
	# Menü: vor dem ersten Lauf.
	_check(int(_game.get("state")) == 0, "Vor dem ersten Lauf ist der State MENU.")
	_check(_track() == "menu", "Im State MENU läuft die Menümusik, war: " + _track())
	_check(not bool(music.call("is_muffled")), "Im Menü ist die Musik nicht gedämpft.")
	music.call("advance", fade + 0.1)
	_near(_gain("menu"), 1.0, "Die Menümusik ist nach der Blende voll da.")
	_check(not bool(music.call("is_fading")), "Die Blende endet.")
	_check(_music_player("Menu").playing, "Der Abspieler der Menümusik läuft.")
	_check(not _music_player("Stems").playing and not _music_player("GameOver").playing, "Im Menü läuft sonst nichts.")
	_check(absf(_music_player("Menu").volume_db - float((layers["menu"] as Dictionary)["db"])) < 0.01, "Die Menümusik hat ihre Lautstärke aus der Tabelle (%.1f dB)." % _music_player("Menu").volume_db)
	# Lauf beginnt: Pause vor der ersten Welle, ruhige Musik. Die Blende läuft.
	_game.call("start_run", 3)
	_check(_track() == "calm", "Nach run_started läuft die ruhige Musik, war: " + _track())
	_check(bool(music.call("is_fading")), "Direkt nach dem Wechsel läuft eine Blende.")
	_near(_gain("calm"), 0.0, "Das neue Stück beginnt bei null.")
	_near(_gain("menu"), 1.0, "Das alte Stück ist am Anfang der Blende noch voll da.")
	music.call("advance", fade * 0.5)
	_check(absf(_gain("calm") - 0.5) < 0.01 and absf(_gain("menu") - 0.5) < 0.01, "Nach der halben Zeit stehen beide Stücke auf der Hälfte (%.2f und %.2f)." % [_gain("calm"), _gain("menu")])
	_check(bool(music.call("is_fading")), "Mitten in der Blende meldet is_fading true.")
	_check(_music_player("Stems").playing and _music_player("Menu").playing, "Während der Blende laufen beide Abspieler.")
	# Gleiche Leistung: In der Mitte ist jedes Stück 3 dB unter seinem Tabellenwert.
	_check(absf(_stem_db(0) - (float((layers["calm"] as Dictionary)["db"]) - 3.01)) < 0.1, "In der Mitte der Blende ist das neue Stück 3 dB leiser, war %.2f dB." % _stem_db(0))
	music.call("advance", fade * 0.5 + 0.01)
	_near(_gain("calm"), 1.0, "Nach der ganzen Zeit ist das neue Stück voll da.")
	_near(_gain("menu"), 0.0, "Nach der ganzen Zeit ist das alte Stück weg.")
	_check(not bool(music.call("is_fading")), "Die Blende endet nach FADE_TIME.")
	_check(_music_player("Stems").playing and not _music_player("Menu").playing, "Nach der Blende läuft nur noch die Spielmusik.")
	_check(absf(_stem_db(0) - float((layers["calm"] as Dictionary)["db"])) < 0.01 and _stem_db(1) <= -79.0 and _stem_db(2) <= -79.0, "In der Pause ist nur die ruhige Spur zu hören.")
	# Welle beginnt: treibende Musik. Die Fanfare drängt die Musik kurz zurück.
	_near(float(music.call("get_duck_db")), 0.0, "Ohne lautes Ereignis ist die Musik nicht zurückgedrängt.")
	_events.emit_signal("wave_started", 1, 12)
	_check(_track() == "wave", "Nach wave_started läuft die Musik der Welle, war: " + _track())
	music.call("advance", 0.1)
	var wave_start_duck: float = float((_sfx_script.get_script_constant_map().get("SOUNDS", {}) as Dictionary)["wave_start"]["duck"])
	_check(absf(float(music.call("get_duck_db")) - wave_start_duck) < 0.01, "Die Fanfare drängt die Musik um %.0f dB zurück, war %.2f dB." % [wave_start_duck, float(music.call("get_duck_db"))])
	_check(absf(_music_player("Stems").volume_db - wave_start_duck) < 0.01, "Das Zurückdrängen steht auf dem Abspieler der Spielmusik.")
	music.call("advance", fade)
	_check(is_equal_approx(_gain("wave"), 1.0) and is_equal_approx(_gain("calm"), 0.0) and is_equal_approx(_gain("late"), 0.0), "In der Welle ist nur die Spur wave zu hören.")
	for _i: int in 40:
		music.call("advance", 0.1)
	_near(float(music.call("get_duck_db")), 0.0, "Nach der Fanfare kommt die Musik von selbst zurück.")
	# Welle geschafft: zurück zur ruhigen Musik, das Publikum jubelt.
	var cheers: int = _count("crowd_cheer")
	_events.emit_signal("wave_cleared", 1)
	_check(_track() == "calm", "Nach wave_cleared läuft wieder die ruhige Musik, war: " + _track())
	_check(_count("crowd_cheer") == cheers + 1, "Bei geschaffter Welle jubelt das Publikum.")
	music.call("advance", fade + 0.01)
	_check(is_equal_approx(_gain("calm"), 1.0) and is_equal_approx(_gain("wave"), 0.0), "Die Blende zurück zur ruhigen Musik endet.")
	# Ab Welle 10: wave und die Zusatzspur zusammen.
	_events.emit_signal("wave_started", 10, 60)
	_check(_track() == "late", "Ab Welle 10 läuft das dichtere Stück, war: " + _track())
	music.call("advance", fade + 0.01)
	_check(is_equal_approx(_gain("wave"), 1.0) and is_equal_approx(_gain("late"), 1.0) and is_equal_approx(_gain("calm"), 0.0), "Ab Welle 10 laufen wave und die Zusatzspur zusammen.")
	_check(absf(_stem_db(1) - float((layers["wave"] as Dictionary)["db"])) < 0.01 and absf(_stem_db(2) - float((layers["late"] as Dictionary)["db"])) < 0.01, "Beide Spuren haben ihre Lautstärke aus der Tabelle.")
	_events.emit_signal("wave_cleared", 10)
	_events.emit_signal("wave_started", 9, 50)
	_check(_track() == "wave", "Unter Welle 10 läuft das einfache Stück, war: " + _track())
	music.call("advance", fade + 0.01)
	_check(is_equal_approx(_gain("wave"), 1.0) and is_equal_approx(_gain("late"), 0.0), "Die Zusatzspur blendet wieder aus.")
	for _i: int in 40:
		music.call("advance", 0.1)
	# Pause, Rucksack, Kistenwahl: dasselbe Stück, leiser und dumpfer, kein Stopp.
	_check(not bool(buses.call("is_music_filter_on")), "Im laufenden Spiel ist der Tiefpass der Musik aus.")
	_game.call("set_paused", true)
	_check(int(_game.get("state")) == 3 and bool(music.call("is_muffled")), "In der Pause soll die Musik gedämpft sein.")
	_check(_track() == "wave", "In der Pause bleibt das Stück dasselbe, war: " + _track())
	_near(float(music.call("get_muffle")), 0.0, "Die Dämpfung beginnt bei null.")
	music.call("advance", muffle_time + 0.01)
	_near(float(music.call("get_muffle")), 1.0, "Die Dämpfung ist nach MUFFLE_TIME ganz da.")
	_check(bool(buses.call("is_music_filter_on")), "Gedämpft ist der Tiefpass auf dem Bus Music an.")
	var filter: AudioEffectLowPassFilter = buses.call("music_filter") as AudioEffectLowPassFilter
	_check(filter != null and absf(filter.cutoff_hz - muffle_cutoff) < 1.0, "Der Tiefpass steht auf %.0f Hz, war %.0f Hz." % [muffle_cutoff, filter.cutoff_hz if filter != null else -1.0])
	_check(_music_player("Stems").playing, "In der Pause läuft die Musik weiter.")
	_check(absf(_music_player("Stems").volume_db - muffle_db) < 0.01, "In der Pause ist die Musik %.0f dB leiser, war %.2f dB." % [muffle_db, _music_player("Stems").volume_db])
	_game.call("set_paused", false)
	_check(not bool(music.call("is_muffled")), "Nach der Pause soll die Musik wieder offen sein.")
	music.call("advance", muffle_time + 0.01)
	_near(float(music.call("get_muffle")), 0.0, "Die Dämpfung geht nach der Pause ganz zurück.")
	_check(not bool(buses.call("is_music_filter_on")), "Offen ist der Tiefpass wieder aus.")
	_check(absf(_music_player("Stems").volume_db) < 0.01, "Nach der Pause hat die Musik wieder ihre volle Lautstärke.")
	_game.call("open_backpack")
	_check(int(_game.get("state")) == 5 and bool(music.call("is_muffled")) and _track() == "wave", "Bei offenem Rucksack ist die Musik gedämpft und läuft weiter.")
	_game.call("close_backpack")
	_check(not bool(music.call("is_muffled")), "Nach dem Rucksack ist die Musik wieder offen.")
	_game.set("auto_pack", true)
	_game.call("open_chest", 0)
	_check(int(_game.get("state")) == 2 and bool(music.call("is_muffled")) and _track() == "wave", "In der Kistenwahl ist die Musik gedämpft und läuft weiter.")
	_game.call("choose_offer", 0)
	_game.set("auto_pack", false)
	_check(int(_game.get("state")) == 1 and not bool(music.call("is_muffled")), "Nach der Kistenwahl ist die Musik wieder offen.")
	music.call("advance", muffle_time + 0.01)
	paused = false
	# Zurückdrängen: Explosion, eigener Aufruf, Grenze.
	for _i: int in 40:
		music.call("advance", 0.1)
	_near(float(music.call("get_duck_db")), 0.0, "Vor der Explosion ist die Musik nicht zurückgedrängt.")
	_events.emit_signal("explosion", Vector3(3.0, 1.0, 2.0), 3.0)
	music.call("advance", 0.1)
	_check(float(music.call("get_duck_db")) <= -4.9, "Eine Explosion drängt die Musik zurück, war %.2f dB." % float(music.call("get_duck_db")))
	music.call("duck", -40.0, 0.5)
	music.call("advance", 0.2)
	var floor_db: float = float(consts.get("DUCK_FLOOR_DB", 0.0))
	_check(absf(float(music.call("get_duck_db")) - floor_db) < 0.01, "Mehr als %.0f dB wird die Musik nie zurückgedrängt, war %.2f dB." % [floor_db, float(music.call("get_duck_db"))])
	for _i: int in 60:
		music.call("advance", 0.1)
	_near(float(music.call("get_duck_db")), 0.0, "Die Musik kommt nach dem Zurückdrängen ganz zurück.")
	music.call("duck", 3.0, 1.0)
	music.call("duck", -6.0, 0.0)
	music.call("advance", 0.1)
	_near(float(music.call("get_duck_db")), 0.0, "Ein Wert über 0 dB oder ohne Dauer drängt nichts zurück.")
	# Game Over: der Abgesang, sofort voll, danach die Menümusik. Das Publikum ist enttäuscht.
	var awws: int = _count("crowd_aww")
	_game.call("end_run")
	_check(int(_game.get("state")) == 4 and _track() == "game_over", "Bei Game Over läuft der Abgesang, war: " + _track())
	_check(_count("crowd_aww") == awws + 1, "Bei Game Over ist das Publikum enttäuscht.")
	music.call("advance", 0.05)
	_near(_gain("game_over"), 1.0, "Der Abgesang beginnt ohne Blende.")
	_check(_music_player("GameOver").playing, "Der Abspieler des Abgesangs läuft.")
	_check(not bool(music.call("is_muffled")), "Bei Game Over ist die Musik nicht gedämpft.")
	music.call("advance", fade)
	_near(_gain("wave"), 0.0, "Die Musik der Welle blendet bei Game Over aus.")
	_check(not _music_player("Stems").playing, "Nach dem Ausblenden hält die Spielmusik an.")
	_check(_track() == "game_over", "Der Abgesang läuft noch.")
	music.call("advance", 30.0)
	_check(_track() == "menu", "Nach dem Abgesang läuft die Menümusik, war: " + _track())
	music.call("advance", fade + 0.01)
	_check(is_equal_approx(_gain("menu"), 1.0) and is_equal_approx(_gain("game_over"), 0.0), "Die Blende zur Menümusik endet.")
	_check(_music_player("Menu").playing and not _music_player("GameOver").playing, "Nach dem Abgesang läuft nur die Menümusik.")
	# Neuer Lauf: wieder die ruhige Musik, der Abgesang ist vergessen.
	paused = false
	_game.call("start_run", 3)
	_check(_track() == "calm", "Ein neuer Lauf beginnt mit der ruhigen Musik, war: " + _track())
	music.call("advance", fade + 0.01)
	_check(not bool(music.call("is_fading")), "Auch diese Blende endet.")
	# Ein unbekannter Name ist harmlos.
	_near(_gain("gibt_es_nicht"), 0.0, "Eine fremde Spur hat die Blende 0.")
	_check(not bool(music.call("has_layer", "gibt_es_nicht")), "Eine fremde Spur gilt nicht als geladen.")
	await _pause(LONG_GAP_WAIT)


## Varianten: nie zweimal dieselbe hintereinander, auf Dauer kommen alle vor.
func _test_variants() -> void:
	var loaded: Dictionary = _sfx.get("_variants")
	for id: String in VARIANTS:
		var total: int = int(VARIANTS[id])
		var files: Array = loaded.get(id, [])
		var distinct: Dictionary = {}
		for stream: Variant in files:
			distinct[stream] = true
		_check(distinct.size() == total, "%s: %d verschiedene Dateien geladen, erwartet %d." % [id, distinct.size(), total])
		var seen: Dictionary = {}
		var repeats: int = 0
		var last: int = -2
		for _i: int in 60:
			var stream: AudioStream = _sfx.call("_pick_variant", id) as AudioStream
			var index: int = int(_sfx.call("get_last_variant", id))
			_check(index >= 0 and index < total and files[index] == stream, "%s: Die gemerkte Variante ist die gespielte." % id)
			if index == last:
				repeats += 1
			last = index
			seen[index] = true
		_check(repeats == 0, "%s: nie zweimal dieselbe Variante hintereinander, waren %d Wiederholungen." % [id, repeats])
		_check(seen.size() == total, "%s: In 60 Starts kommen alle %d Varianten vor, waren %d." % [id, total, seen.size()])
	# Der echte Weg: Schüsse wechseln die Variante bei jedem Schuss und zählen unter einem Namen.
	var shots: int = _count("shot_smg")
	var last_shot: int = int(_sfx.call("get_last_variant", "shot_smg"))
	var changed: int = 0
	for _i: int in 12:
		_events.emit_signal("weapon_fired", "smg")
		var now: int = int(_sfx.call("get_last_variant", "shot_smg"))
		if now != last_shot:
			changed += 1
		last_shot = now
	_check(changed == 12, "Zwölf Schüsse wechseln zwölfmal die Variante, waren %d Wechsel." % changed)
	_check(_count("shot_smg") == shots + 12, "Alle Varianten zählen unter dem Namen des Geräuschs.")
	# Ein Geräusch ohne Varianten bleibt bei seiner einen Datei.
	_sfx.call("play", "dash")
	_check(int(_sfx.call("get_last_variant", "dash")) == 0, "Ein Geräusch ohne Varianten spielt immer Datei 0.")
	# Stöhnen: drei eigene Geräusche, nie dasselbe zweimal hintereinander.
	var last_groan: String = ""
	var groan_repeats: int = 0
	var groans_seen: Dictionary = {}
	for _i: int in 40:
		var groan: String = str(_sfx.call("_next_groan"))
		if groan == last_groan:
			groan_repeats += 1
		last_groan = groan
		groans_seen[groan] = true
	_check(groan_repeats == 0, "Nie zweimal dasselbe Stöhnen hintereinander, waren %d Wiederholungen." % groan_repeats)
	_check(groans_seen.size() == GROANS.size(), "In 40 Lauten kommen alle drei Stöhn-Geräusche vor.")
	# Schüsse laufen über den Hall-Bus, Treffer und Menü trocken über Sfx.
	_events.emit_signal("weapon_fired", "revolver")
	_check(_bus_of_playing("shot_revolver") == &"Reverb", "Ein Schuss läuft über den Hall-Bus.")
	_sfx.call("play", "headshot")
	_check(_bus_of_playing("headshot") == &"Sfx", "Der Kopfschuss-Akzent läuft trocken über den Bus Sfx.")


# --- Signale --------------------------------------------------------------------------------------

func _test_shots() -> void:
	for weapon_id: String in WEAPON_IDS:
		var id: String = "shot_" + weapon_id
		_expect_only(id, func() -> void: _events.emit_signal("weapon_fired", weapon_id), "weapon_fired(%s)" % weapon_id)
	var pistol_before: int = _count("shot_pistol")
	_events.emit_signal("weapon_fired", "wasserpistole")
	_check(_count("shot_pistol") == pistol_before + 1, "Eine unbekannte Waffe klingt wie die Pistole.")


func _test_fight_signals() -> void:
	var zombie: Node3D = _fake_zombie("walker", Vector3(4.0, 0.0, -3.0))
	var elite: Node3D = _fake_zombie("elite", Vector3(-3.0, 0.0, -6.0))
	_expect("reload_start", 1, func() -> void: _events.emit_signal("hand_reload_started", 0, 1.2), "hand_reload_started")
	_expect("reload_done", 1, func() -> void: _events.emit_signal("hand_reload_finished", 0), "hand_reload_finished")
	_expect("hit", 1, func() -> void: _events.emit_signal("bullet_hit", zombie, 10.0, {"source": "bullet"}), "bullet_hit")
	# Kill ohne und mit Kopfschuss.
	var headshots: int = _count("headshot")
	_expect("zombie_death", 1, func() -> void: _events.emit_signal("zombie_killed", zombie, {"source": "bullet"}), "zombie_killed")
	_check(_count("headshot") == headshots, "Ein Kill ohne Kopfschuss hat keinen Kopfschuss-Akzent.")
	await _pause(GAP_WAIT)
	_expect("headshot", 1, func() -> void: _events.emit_signal("zombie_killed", zombie, {"source": "bullet", "headshot": true}), "zombie_killed mit Kopfschuss")
	# Elite erscheint, normale Zombies brüllen nicht.
	_expect("elite_roar", 0, func() -> void: _events.emit_signal("zombie_spawned", zombie), "zombie_spawned (normal)")
	_expect("elite_roar", 1, func() -> void: _events.emit_signal("zombie_spawned", elite), "zombie_spawned (Elite)")
	# Schaden je Quelle.
	var at: Dictionary = {"hit_position": Vector3(2.0, 1.0, -2.0)}
	_expect("explosion", 1, func() -> void: _events.emit_signal("zombie_damaged", zombie, 50.0, _with(at, "explosion")), "zombie_damaged (explosion)")
	_expect("lightning", 1, func() -> void: _events.emit_signal("zombie_damaged", zombie, 20.0, _with(at, "lightning")), "zombie_damaged (lightning)")
	# Neue Quellen aus Ausbau 3: Querschläger am Treffer, Dornen am Zombie.
	_expect_only("ricochet", func() -> void: _events.emit_signal("zombie_damaged", zombie, 8.0, _with(at, "ricochet")), "zombie_damaged (ricochet)")
	_check(_playing_at("ricochet", Vector3(2.0, 1.0, -2.0)), "Der Querschläger erklingt am Ort des Treffers.")
	_expect_only("thorns", func() -> void: _events.emit_signal("zombie_damaged", zombie, 8.0, {"source": "thorns"}), "zombie_damaged (thorns)")
	_check(_playing_at("thorns", Vector3(4.0, 1.4, -3.0)), "Die Dornen erklingen am Zombie.")
	# Kameras, Mine und stille Quellen lösen hier nichts aus (auch der Drohnenschuss nicht mehr:
	# Er kommt über camera_fired).
	for source: String in SILENT_SOURCES:
		_expect_silent(func() -> void: _events.emit_signal("zombie_damaged", zombie, 5.0, _with(at, source)), "zombie_damaged (%s)" % source)
		_expect_silent(func() -> void: _events.emit_signal("zombie_damaged", zombie, 5.0, {"source": source}), "zombie_damaged (%s, ohne Ort)" % source)
	var explosions: int = _count("explosion")
	var lightnings: int = _count("lightning")
	_events.emit_signal("zombie_damaged", zombie, 5.0, {"source": "burn"})
	_events.emit_signal("zombie_damaged", zombie, 5.0, {"source": "poison"})
	_events.emit_signal("zombie_damaged", zombie, 5.0, {"source": "bullet", "weapon_id": "pistol"})
	_check(_count("explosion") == explosions and _count("lightning") == lightnings, "Brand, Gift und Pistolenkugeln lösen keine Effekt-Geräusche aus.")
	await _pause(GAP_WAIT)
	_expect("explosion", 1, func() -> void: _events.emit_signal("zombie_damaged", zombie, 50.0, {"source": "bullet", "weapon_id": "rocket_launcher"}), "Raketentreffer")
	await _pause(GAP_WAIT)
	# Eine Granate explodiert am Treffer wie die Rakete.
	_expect_only("explosion", func() -> void: _events.emit_signal("zombie_damaged", zombie, 60.0, {"source": "bullet", "weapon_id": "grenade_launcher"}), "Granatentreffer")
	# Die anderen neuen Waffen explodieren nicht.
	for weapon_id: String in ["burst_pistol", "nail_gun", "machine_pistol", "crossbow", "flamethrower", "beam", "tesla", "lmg", "auto_shotgun"]:
		_expect_silent(func() -> void: _events.emit_signal("zombie_damaged", zombie, 9.0, {"source": "bullet", "weapon_id": weapon_id}), "zombie_damaged (bullet, %s)" % weapon_id)
	await _pause(GAP_WAIT)
	_expect("explosion", 1, func() -> void: _events.emit_signal("zombie_damaged", zombie, 5.0, {"source": "shockwave"}), "zombie_damaged (shockwave)")
	await _pause(GAP_WAIT)
	_expect("explosion", 1, func() -> void: _events.emit_signal("explosion", Vector3(2.0, 1.0, -2.0), 3.5), "explosion (auch ohne Treffer)")
	_expect("lightning", 1, func() -> void: _events.emit_signal("zombie_damaged", zombie, 5.0, {"source": "jammer"}), "zombie_damaged (jammer)")
	zombie.free()
	elite.free()


func _test_player_signals() -> void:
	_events.emit_signal("run_started")
	# Ohne Schild tut jeder Treffer weh.
	var shield_hits: int = _count("shield_hit")
	_expect("player_hurt", 1, func() -> void: _events.emit_signal("player_damaged", 10.0), "player_damaged ohne Schild")
	_check(_count("shield_hit") == shield_hits, "Ohne Schild gibt es kein Schild-Geräusch.")
	await _pause(GAP_WAIT)
	# Das Schild lädt: ein Geräusch beim ersten Anstieg, nicht bei jedem weiteren Schritt.
	_events.emit_signal("player_shield_changed", 0.0, 50.0)
	_expect("shield_recharge", 1, func() -> void: _events.emit_signal("player_shield_changed", 5.0, 50.0), "Schild beginnt zu laden")
	await _pause(GAP_WAIT)
	var recharges: int = _count("shield_recharge")
	_events.emit_signal("player_shield_changed", 20.0, 50.0)
	_events.emit_signal("player_shield_changed", 50.0, 50.0)
	_check(_count("shield_recharge") == recharges, "Lädt das Schild weiter, kommt kein neues Geräusch.")
	# Ein Treffer, den das Schild ganz abfängt: nur das Schild klingt.
	var hurts: int = _count("player_hurt")
	shield_hits = _count("shield_hit")
	_events.emit_signal("player_damaged", 20.0)
	_events.emit_signal("player_shield_changed", 30.0, 50.0)
	_check(_count("shield_hit") == shield_hits + 1, "Ein Treffer aufs Schild klingt am Schild.")
	_check(_count("player_hurt") == hurts, "Fängt das Schild alles ab, tut es nicht weh.")
	await _pause(GAP_WAIT)
	# Mehr Schaden als Schild: beides.
	shield_hits = _count("shield_hit")
	_events.emit_signal("player_damaged", 45.0)
	_events.emit_signal("player_shield_changed", 0.0, 50.0)
	_check(_count("player_hurt") == hurts + 1, "Mehr Schaden als Schild tut weh.")
	_check(_count("shield_hit") == shield_hits + 1, "Auch der durchschlagende Treffer klingt am Schild.")
	await _pause(GAP_WAIT)
	# Nach dem Treffer lädt es wieder: neues Geräusch.
	_expect("shield_recharge", 1, func() -> void: _events.emit_signal("player_shield_changed", 3.0, 50.0), "Schild lädt nach einem Treffer wieder")
	_expect("dash", 1, func() -> void: _events.emit_signal("player_dashed"), "player_dashed")
	_events.emit_signal("run_started")


func _test_show_signals() -> void:
	var chest: Node3D = Node3D.new()
	chest.position = Vector3(-2.0, 0.0, 5.0)
	root.add_child(chest)
	_expect("chest_drop", 1, func() -> void: _events.emit_signal("chest_dropped", chest), "chest_dropped")
	_expect("chest_open", 1, func() -> void: _events.emit_signal("chest_opened", 1, []), "chest_opened")
	_expect("upgrade", 1, func() -> void: _events.emit_signal("upgrade_chosen", "burn", 2), "upgrade_chosen")
	_expect("synergy", 1, func() -> void: _events.emit_signal("synergy_unlocked", "test"), "synergy_unlocked")
	_expect("wave_start", 1, func() -> void: _events.emit_signal("wave_started", 3, 20), "wave_started")
	_expect("wave_cleared", 1, func() -> void: _events.emit_signal("wave_cleared", 3), "wave_cleared")
	_expect("backpack_open", 1, func() -> void: _events.emit_signal("backpack_opened", -1), "backpack_opened")
	_expect("backpack_close", 1, func() -> void: _events.emit_signal("backpack_closed"), "backpack_closed")
	_expect("game_over", 1, func() -> void: _events.emit_signal("game_over", {}), "game_over")
	# Der Countdown tickt nur in den letzten drei Sekunden.
	var ticks: int = _count("countdown_tick")
	for seconds: int in [8, 4, 0]:
		_events.emit_signal("intermission_tick", seconds)
	_check(_count("countdown_tick") == ticks, "Außerhalb der letzten drei Sekunden tickt nichts.")
	for seconds: int in [3, 2, 1]:
		_expect("countdown_tick", 1, func() -> void: _events.emit_signal("intermission_tick", seconds), "intermission_tick(%d)" % seconds)
		await _pause(0.3)
	chest.free()
	await _pause(GAP_WAIT)


## Kameras: camera_fired spielt je Typ genau ein Geräusch am Ort der Kamera.
func _test_cameras() -> void:
	await _pause(GAP_WAIT)
	var zombie: Node3D = _fake_zombie("walker", Vector3(3.0, 0.0, 4.0))
	var index: int = 0
	for camera_id: String in CAMERA_SOUNDS:
		var sound_id: String = str(CAMERA_SOUNDS[camera_id])
		var at: Vector3 = Vector3(6.0 + float(index), 2.5, -4.0)
		index += 1
		_expect_only(sound_id, func() -> void: _events.emit_signal("camera_fired", camera_id, at), "camera_fired(%s)" % camera_id)
		_check(_playing_at(sound_id, at), "camera_fired(%s) erklingt am Ort der Kamera." % camera_id)
	_expect_silent(func() -> void: _events.emit_signal("camera_fired", "gibt_es_nicht", Vector3.ZERO), "camera_fired mit unbekanntem Typ")
	await _pause(GAP_WAIT)
	# Ein ganzer Schuss wie im Spiel: Die Kamera meldet den Schuss und der Zombie den Schaden.
	# Jedes Geräusch erklingt dabei genau einmal, der Drohnenschuss also nicht doppelt.
	for camera_id: String in ["drone", "cam_tele", "cam_flash", "cam_slow"]:
		var sound_id: String = str(CAMERA_SOUNDS[camera_id])
		var shot: Callable = func() -> void:
			_events.emit_signal("camera_fired", camera_id, Vector3(1.0, 2.0, 1.0))
			_events.emit_signal("zombie_damaged", zombie, 15.0, {"source": camera_id, "hit_position": Vector3(3.0, 1.0, 4.0)})
		_expect_only(sound_id, shot, "Schuss der Kamera %s mit Treffer" % camera_id)
	# Auch der Schaden zuerst und die Meldung danach ergeben nur ein Geräusch.
	await _pause(GAP_WAIT)
	var hit_first: Callable = func() -> void:
		_events.emit_signal("zombie_damaged", zombie, 15.0, {"source": "drone", "hit_position": Vector3(3.0, 1.0, 4.0)})
		_events.emit_signal("camera_fired", "drone", Vector3(1.0, 2.0, 1.0))
	_expect_only("drone_shot", hit_first, "Treffer der Drohne, dann ihre Meldung")
	# Zehn Kameras eines Typs im selben Bild: höchstens ein paar Geräusche (Mindestabstand).
	await _pause(GAP_WAIT)
	for camera_id: String in CAMERA_SOUNDS:
		var sound_id: String = str(CAMERA_SOUNDS[camera_id])
		var before: int = _count(sound_id)
		for i: int in 10:
			_events.emit_signal("camera_fired", camera_id, Vector3(float(i), 2.0, 0.0))
		_check(_count(sound_id) - before == 1, "Zehn Kameras %s im selben Bild klingen wie eine, waren %d Starts." % [camera_id, _count(sound_id) - before])
	zombie.free()
	await _pause(GAP_WAIT)


## Requisitenbombe, Zweite Staffel, Pakete und Konto.
func _test_items_and_progress() -> void:
	var zombie: Node3D = _fake_zombie("walker", Vector3(-5.0, 0.0, 7.0))
	var at: Vector3 = Vector3(-5.0, 0.1, 7.0)
	_expect_only("mine_placed", func() -> void: _events.emit_signal("mine_placed", at), "mine_placed")
	_check(_playing_at("mine_placed", at), "mine_placed erklingt am Ort der Mine.")
	_expect_only("mine_triggered", func() -> void: _events.emit_signal("mine_triggered", at), "mine_triggered")
	_check(_playing_at("mine_triggered", at), "mine_triggered erklingt am Ort der Mine.")
	await _pause(GAP_WAIT)
	# Eine ganze Auslösung wie im Spiel: Warnton, Explosion, Schaden an drei Zombies.
	var triggers: int = _count("mine_triggered")
	var explosions: int = _count("explosion")
	var total: int = _total_count()
	_events.emit_signal("mine_triggered", at)
	_events.emit_signal("explosion", at, 3.0)
	for _i: int in 3:
		_events.emit_signal("zombie_damaged", zombie, 80.0, {"source": "mine", "hit_position": at})
	_check(_count("mine_triggered") == triggers + 1, "Eine ausgelöste Mine piept einmal.")
	_check(_count("explosion") == explosions + 1, "Eine ausgelöste Mine explodiert einmal, waren %d Explosionen." % (_count("explosion") - explosions))
	_check(_total_count() == total + 2, "Eine ausgelöste Mine startet genau Warnton und Explosion, waren %d Starts." % (_total_count() - total))
	# Zweite Staffel und Paketkauf.
	_expect_only("player_revived", func() -> void: _events.emit_signal("player_revived"), "player_revived")
	_check(_playing_count(false) >= 1, "Die Fanfare der Zweiten Staffel hat keinen Ort.")
	_expect_only("pack_unlocked", func() -> void: _events.emit_signal("pack_unlocked", "camera_team"), "pack_unlocked")
	# Konto: Nur eine Gutschrift über 0 klimpert.
	await _pause(LONG_GAP_WAIT)
	_expect_silent(func() -> void: _events.emit_signal("bank_changed", 500, 0), "bank_changed mit Gutschrift 0")
	_expect_silent(func() -> void: _events.emit_signal("bank_changed", 300, -2000), "bank_changed beim Kauf (negativer Betrag)")
	_expect_only("bank_coins", func() -> void: _events.emit_signal("bank_changed", 1418, 1418), "bank_changed mit Gutschrift")
	_check(_playing_count(false) >= 1, "Das Münzgeräusch hat keinen Ort.")
	# Ein Kauf wie in Game.buy_pack: erst pack_unlocked, dann bank_changed mit dem negativen Preis.
	await _pause(LONG_GAP_WAIT)
	var purchase: Callable = func() -> void:
		_events.emit_signal("pack_unlocked", "camera_team")
		_events.emit_signal("bank_changed", 3668, -2000)
	_expect_only("pack_unlocked", purchase, "Kauf eines Pakets")
	# Der echte Weg über Game: Ein Lauf mit Punkten endet, die Gutschrift klimpert einmal.
	_game.call("start_run", 3)
	await _pause(LONG_GAP_WAIT)
	_game.call("add_points", 700)
	var coins: int = _count("bank_coins")
	_game.call("end_run")
	var gained: int = int(_game.get("last_bank_gain"))
	_check(gained > 0, "Ein Lauf mit 700 Punkten bringt eine Gutschrift, war %d." % gained)
	_check(_count("bank_coins") == coins + 1, "Game.end_run mit Gutschrift startet bank_coins einmal, war %d mal." % (_count("bank_coins") - coins))
	# Ein Lauf ohne Punkte: Gutschrift 0, kein Münzgeräusch.
	paused = false
	_game.call("start_run", 3)
	await _pause(LONG_GAP_WAIT)
	coins = _count("bank_coins")
	_game.call("end_run")
	_check(int(_game.get("last_bank_gain")) == 0, "Ein Lauf ohne Punkte bringt keine Gutschrift.")
	_check(_count("bank_coins") == coins, "Game.end_run ohne Gutschrift bleibt ohne Münzgeräusch.")
	paused = false
	zombie.free()
	await _pause(LONG_GAP_WAIT)


func _test_points_and_cards() -> void:
	_game.call("start_run", 3)
	var purchases: int = _count("purchase")
	var sold: int = _count("item_sold")
	_game.call("add_points", 2000)
	_check(_count("purchase") == purchases and _count("item_sold") == sold, "Punkte verdienen im Spiel ist weder Kauf noch Verkauf.")
	_expect("purchase", 1, func() -> void: _game.call("spend_points", 500), "Punkte ausgeben im Spiel (Tür, Wandkauf)")
	# Rucksack: Punkte, die bei offenem Rucksack dazukommen, sind ein Verkauf.
	_expect("backpack_open", 1, func() -> void: _game.call("open_backpack"), "Game.open_backpack")
	_check(int(_game.get("state")) == 5, "Der Rucksack ist offen (State PACKING).")
	_expect("item_sold", 1, func() -> void: _events.emit_signal("points_changed", int(_game.get("points")) + 40), "Punkte bei offenem Rucksack")
	_expect("backpack_close", 1, func() -> void: _game.call("close_backpack"), "Game.close_backpack")
	_check(_count("purchase") == purchases + 1, "Der Verkauf zählt nicht als Kauf.")
	# Ein neuer Lauf setzt die Punkte zurück: kein Kauf.
	purchases = _count("purchase")
	_game.call("start_run", 3)
	_check(_count("purchase") == purchases, "Der Punktestand eines neuen Laufs ist kein Kauf.")
	await _pause(GAP_WAIT)
	# Kistenwahl: Sobald eine Karte genommen ist, erklingt card_chosen.
	_game.set("auto_pack", true)
	_expect("chest_open", 1, func() -> void: _game.call("open_chest", 0), "Game.open_chest")
	await process_frame
	await process_frame
	var cards: int = _count("card_chosen")
	_check(int(_game.get("state")) == 2, "Die Kistenwahl ist offen (State CHOOSING).")
	_game.call("choose_offer", 0)
	await process_frame
	await process_frame
	_check(_count("card_chosen") == cards + 1, "Nach der Wahl einer Karte erklingt card_chosen (war %d mal)." % (_count("card_chosen") - cards))
	_game.set("auto_pack", false)
	paused = false
	await _pause(GAP_WAIT)


func _test_groans() -> void:
	_game.call("start_run", 3)
	var listener: Node3D = Node3D.new()
	root.add_child(listener)
	var player_before: Variant = _game.get("player")
	_game.set("player", listener)
	var far: Node3D = Node3D.new()
	far.position = Vector3(200.0, 0.0, 0.0)
	root.add_child(far)
	far.add_to_group("zombies")
	var before: int = _groan_count()
	_sfx.call("_tick_groans", 10.0)
	_check(_groan_count() == before, "Zombies weit weg stöhnen nicht.")
	var near: Node3D = Node3D.new()
	near.position = Vector3(5.0, 0.0, 2.0)
	root.add_child(near)
	near.add_to_group("zombies")
	_sfx.call("_tick_groans", 10.0)
	_check(_groan_count() == before + 1, "Ein Zombie in der Nähe stöhnt.")
	# Danach ist mindestens 1,5 Sekunden Ruhe.
	for _i: int in 14:
		_sfx.call("_tick_groans", 0.1)
	_check(_groan_count() == before + 1, "Zwischen zwei Lauten liegen mindestens 1,5 Sekunden.")
	_sfx.call("_tick_groans", 3.0)
	_check(_groan_count() == before + 2, "Nach spätestens 4 Sekunden stöhnt wieder einer.")
	_game.set("player", player_before if is_instance_valid(player_before) else null)
	near.free()
	far.free()
	listener.free()


# --- Schritte, Landen, Herzschlag, Publikum, Material ---------------------------------------------

## Ein Knoten, der für das Ton-Modul wie der Spieler aussieht: velocity, is_on_floor, is_dashing,
## is_dead. Das Modul liest nur diese Werte über Game.player.
func _fake_player() -> Node3D:
	var script: GDScript = GDScript.new()
	script.source_code = "extends Node3D\nvar velocity: Vector3 = Vector3.ZERO\nvar on_floor: bool = true\nvar dashing: bool = false\nvar is_dead: bool = false\nfunc is_on_floor() -> bool:\n\treturn on_floor\nfunc is_dashing() -> bool:\n\treturn dashing\n"
	script.reload()
	var walker: Node3D = Node3D.new()
	walker.set_script(script)
	root.add_child(walker)
	return walker


## Stellt die Schritte um seconds Sekunden vor (in Schritten von 1/60 s) und gibt zurück, wie
## viele Schritt-Geräusche dabei gestartet sind.
func _walk(seconds: float) -> int:
	var before: int = _count("step")
	for _i: int in roundi(seconds * 60.0):
		_sfx.call("_tick_movement", 1.0 / 60.0)
	return _count("step") - before


## Schritte nur beim Laufen am Boden, im Takt der Geschwindigkeit. Landen nach einem Sprung.
## Alles ohne Warten: Die Zeit wird von Hand vorgestellt, die echte Zeit spielt keine Rolle.
func _test_movement() -> void:
	paused = false
	_game.call("start_run", 3)
	var consts: Dictionary = _sfx_script.get_script_constant_map()
	var stride: float = float(consts.get("STEP_STRIDE", 0.0))
	var first_share: float = float(consts.get("STEP_FIRST_SHARE", 0.0))
	var min_speed: float = float(consts.get("STEP_MIN_SPEED", 0.0))
	var min_fall: float = float(consts.get("LAND_MIN_FALL_SPEED", 0.0))
	_check(stride >= 1.2 and stride <= 2.6, "Ein Schritt ist etwa 1,8 m lang, war %.2f m." % stride)
	_check(float((consts.get("SOUNDS", {}) as Dictionary)["step"]["gap"]) == 0.0, "Schritte haben keinen Mindestabstand: Den Takt gibt der Weg vor.")
	var player_before: Variant = _game.get("player")
	# Ohne Spieler: nichts, kein Fehler.
	_game.set("player", null)
	_check(_walk(1.0) == 0, "Ohne Spieler gibt es keine Schritte.")
	var walker: Node3D = _fake_player()
	_game.set("player", walker)
	var lands: int = _count("land")
	var total: int = _total_count()
	# Stehen.
	_check(_walk(2.0) == 0, "Im Stehen gibt es keine Schritte.")
	# Schleichen unter der Schwelle.
	walker.set("velocity", Vector3(min_speed * 0.5, 0.0, 0.0))
	_check(_walk(3.0) == 0, "Unter %.1f m/s gibt es keine Schritte." % min_speed)
	# Gehen mit 5 m/s über 2 s = 10 m. Der erste Schritt kommt nach dem Rest des ersten Wegs.
	walker.set("velocity", Vector3(3.0, 0.0, 4.0))
	var walked: int = _walk(2.0)
	var expected_walk: int = floori((10.0 - stride * (1.0 - first_share)) / stride) + 1
	_check(absi(walked - expected_walk) <= 1, "Gehen mit 5 m/s über 2 s ergibt etwa %d Schritte, waren %d." % [expected_walk, walked])
	_check(_bus_of_playing("step") == &"Reverb", "Schritte laufen über den Hall-Bus.")
	var step_db: float = float((consts.get("SOUNDS", {}) as Dictionary)["step"]["db"])
	_check(absf(_volume_of_playing("step") - step_db) < 0.01, "Schritte beim Gehen haben die Grundlautstärke (%.1f dB)." % _volume_of_playing("step"))
	# Sprinten mit 7 m/s: mehr Schritte in derselben Zeit, und lauter.
	walker.set("velocity", Vector3(0.0, 0.0, 0.0))
	_walk(0.5)
	walker.set("velocity", Vector3(7.0, 0.0, 0.0))
	var sprinted: int = _walk(2.0)
	var expected_sprint: int = floori((14.0 - stride * (1.0 - first_share)) / stride) + 1
	_check(absi(sprinted - expected_sprint) <= 1, "Sprinten mit 7 m/s über 2 s ergibt etwa %d Schritte, waren %d." % [expected_sprint, sprinted])
	_check(sprinted > walked, "Beim Sprinten kommen die Schritte schneller (%d gegen %d)." % [sprinted, walked])
	_check(_volume_of_playing("step") > step_db + 0.5, "Schritte beim Sprinten sind lauter.")
	_check(_count("land") == lands, "Laufen am Boden ist kein Landen.")
	_check(_total_count() - total == walked + sprinted, "Beim Laufen startet nichts anderes als Schritte.")
	# In der Luft: keine Schritte, auch bei voller Fahrt.
	walker.set("on_floor", false)
	walker.set("velocity", Vector3(7.0, 2.0, 0.0))
	_check(_walk(1.0) == 0, "In der Luft gibt es keine Schritte.")
	# Landen nach einem Sprung (fällt mit 4,5 m/s): ein Landen, danach wieder Schritte.
	walker.set("velocity", Vector3(7.0, -4.5, 0.0))
	_walk(0.1)
	walker.set("on_floor", true)
	walker.set("velocity", Vector3(7.0, 0.0, 0.0))
	var after_landing: int = _walk(1.0)
	_check(_count("land") == lands + 1, "Aufkommen nach einem Sprung ist einmal zu hören, war %d mal." % (_count("land") - lands))
	_check(after_landing >= 2, "Nach dem Landen laufen die Schritte weiter, waren %d." % after_landing)
	_check(_bus_of_playing("land") == &"Reverb", "Das Landen läuft über den Hall-Bus.")
	# Eine kleine Stufe (fällt mit weniger als der Schwelle) ist kein Landen.
	walker.set("on_floor", false)
	walker.set("velocity", Vector3(5.0, -min_fall * 0.5, 0.0))
	_walk(0.1)
	walker.set("on_floor", true)
	walker.set("velocity", Vector3(5.0, 0.0, 0.0))
	_walk(0.2)
	_check(_count("land") == lands + 1, "Eine kleine Stufe ist kein Landen.")
	# Im Ausweichsprung (16 m/s am Boden): keine Schritte.
	walker.set("dashing", true)
	walker.set("velocity", Vector3(16.0, 0.0, 0.0))
	_check(_walk(1.0) == 0, "Im Ausweichsprung gibt es keine Schritte.")
	walker.set("dashing", false)
	# Tot: nichts mehr.
	walker.set("is_dead", true)
	walker.set("velocity", Vector3(5.0, 0.0, 0.0))
	_check(_walk(1.0) == 0, "Ein toter Spieler macht keine Schritte.")
	walker.set("is_dead", false)
	# Über _process: nur im laufenden Spiel. Bei offenem Rucksack (State PACKING) bleibt es still.
	var steps: int = _count("step")
	_sfx.call("_process", 1.0)
	_check(_count("step") > steps, "Im laufenden Spiel zählt _process die Schritte.")
	_game.call("open_backpack")
	steps = _count("step")
	for _i: int in 5:
		_sfx.call("_process", 1.0)
	_check(_count("step") == steps, "Bei offenem Rucksack gibt es keine Schritte.")
	_game.call("close_backpack")
	# Ein Knoten ohne velocity und is_on_floor (kein Spieler) ist harmlos.
	var plain: Node3D = Node3D.new()
	root.add_child(plain)
	_game.set("player", plain)
	_check(_walk(1.0) == 0, "Ein Knoten ohne Bewegung macht keine Schritte.")
	_game.set("player", player_before if is_instance_valid(player_before) else null)
	plain.free()
	walker.free()


## Herzschlag nur unter der Schwelle (30 % Leben), schneller bei weniger Leben, nie bei 0.
func _test_heartbeat() -> void:
	paused = false
	_game.call("start_run", 3)
	var consts: Dictionary = _sfx_script.get_script_constant_map()
	var share: float = float(consts.get("HEARTBEAT_SHARE", 0.0))
	var slow: float = float(consts.get("HEARTBEAT_SLOW", 0.0))
	var fast: float = float(consts.get("HEARTBEAT_FAST", 0.0))
	_near(share, 0.3, "Der Herzschlag beginnt unter 30 Prozent Leben.")
	_check(fast > 0.2 and fast < slow, "Kurz vor dem Tod schlägt das Herz schneller (%.2f s gegen %.2f s)." % [fast, slow])
	var total: int = _total_count()
	_check(_beats(10.0) == 0, "Mit vollem Leben schlägt kein Herz.")
	_events.emit_signal("player_health_changed", 50.0, 100.0)
	_check(_beats(10.0) == 0, "Mit halbem Leben schlägt kein Herz.")
	_events.emit_signal("player_health_changed", 30.0, 100.0)
	_check(_beats(10.0) == 0, "Genau an der Schwelle schlägt noch kein Herz.")
	_events.emit_signal("player_health_changed", 29.0, 100.0)
	var near_threshold: int = _beats(10.0)
	_check(near_threshold >= floori(10.0 / slow) - 1 and near_threshold <= floori(10.0 / slow) + 2, "Knapp unter der Schwelle schlägt das Herz etwa alle %.2f s: %d Schläge in 10 s." % [slow, near_threshold])
	_events.emit_signal("player_health_changed", 3.0, 100.0)
	var near_death: int = _beats(10.0)
	_check(near_death > near_threshold, "Mit weniger Leben schlägt das Herz schneller (%d gegen %d Schläge in 10 s)." % [near_death, near_threshold])
	_check(near_death <= floori(10.0 / fast) + 2, "Schneller als alle %.2f s schlägt es nie, waren %d Schläge in 10 s." % [fast, near_death])
	_check(_total_count() - total == near_threshold + near_death, "Der Herzschlag startet nichts anderes.")
	# Der Anteil zählt, nicht die Zahl: 40 von 200 sind 20 Prozent.
	_events.emit_signal("player_health_changed", 100.0, 200.0)
	_check(_beats(5.0) == 0, "100 von 200 Leben: kein Herzschlag.")
	_events.emit_signal("player_health_changed", 40.0, 200.0)
	_check(_beats(5.0) > 0, "40 von 200 Leben: Das Herz schlägt.")
	# Geheilt: Ruhe.
	_events.emit_signal("player_health_changed", 160.0, 200.0)
	_check(_beats(5.0) == 0, "Nach dem Heilen schlägt kein Herz mehr.")
	# Tot: Ruhe.
	_events.emit_signal("player_health_changed", 0.0, 100.0)
	_check(_beats(5.0) == 0, "Bei 0 Leben schlägt kein Herz.")
	# Über _process: nur im laufenden Spiel, nicht bei offenem Rucksack.
	_events.emit_signal("player_health_changed", 10.0, 100.0)
	var beats: int = _count("heartbeat")
	_sfx.call("_process", 0.5)
	_check(_count("heartbeat") == beats + 1, "Im laufenden Spiel zählt _process den Herzschlag.")
	_game.call("open_backpack")
	beats = _count("heartbeat")
	for _i: int in 5:
		_sfx.call("_process", 1.0)
	_check(_count("heartbeat") == beats, "Bei offenem Rucksack schlägt kein Herz.")
	_game.call("close_backpack")
	# Ein neuer Lauf beginnt mit vollem Leben.
	_game.call("start_run", 3)
	_check(_beats(5.0) == 0, "Ein neuer Lauf beginnt ohne Herzschlag.")


## Stellt den Herzschlag um seconds Sekunden vor (in Schritten von 0,05 s) und zählt die Schläge.
func _beats(seconds: float) -> int:
	var before: int = _count("heartbeat")
	for _i: int in roundi(seconds * 20.0):
		_sfx.call("_tick_heartbeat", 0.05)
	return _count("heartbeat") - before


## Publikum (Erschrecken, Raunen) und die Geräusche für Material, Reparieren, Verschrotten.
func _test_crowd_and_materials() -> void:
	paused = false
	_game.call("start_run", 3)
	await _pause(GAP_WAIT)
	var consts: Dictionary = _sfx_script.get_script_constant_map()
	var heavy: float = float(consts.get("HEAVY_HIT_SHARE", 0.0))
	_check(heavy >= 0.15 and heavy <= 0.5, "Ein schwerer Treffer nimmt etwa ein Drittel des Lebens, war %.2f." % heavy)
	# Leichte Treffer, Treffer aufs Schild und Treffer bei viel Leben lassen das Publikum kalt.
	var gasps: int = _count("crowd_gasp")
	_events.emit_signal("player_health_changed", 100.0, 100.0)
	_events.emit_signal("player_damaged", 100.0 * heavy - 5.0)
	_check(_count("crowd_gasp") == gasps, "Ein leichter Treffer erschreckt das Publikum nicht.")
	await _pause(0.15)
	_events.emit_signal("player_shield_changed", 50.0, 50.0)
	_events.emit_signal("player_damaged", 60.0)
	_events.emit_signal("player_shield_changed", 0.0, 50.0)
	_check(_count("crowd_gasp") == gasps, "Fängt das Schild den größten Teil ab, erschrickt das Publikum nicht.")
	await _pause(0.15)
	_events.emit_signal("player_health_changed", 200.0, 200.0)
	_events.emit_signal("player_damaged", 100.0 * heavy + 5.0)
	_check(_count("crowd_gasp") == gasps, "Bei 200 Leben ist ein Treffer von 35 nicht schwer.")
	await _pause(0.15)
	# Ein schwerer Treffer: Das Publikum erschrickt, einmal.
	_events.emit_signal("player_health_changed", 100.0, 100.0)
	_events.emit_signal("player_damaged", 100.0 * heavy + 5.0)
	_check(_count("crowd_gasp") == gasps + 1, "Ein schwerer Treffer erschreckt das Publikum.")
	_check(_bus_of_playing("crowd_gasp") == &"Sfx", "Das Publikum läuft über den Bus Sfx.")
	await _pause(0.15)
	_events.emit_signal("player_damaged", 100.0 * heavy + 5.0)
	_check(_count("crowd_gasp") == gasps + 1, "Direkt danach erschrickt es nicht noch einmal (Mindestabstand).")
	# Raunen: in jedem State außer MENU, mit Blende.
	var fade: float = float(consts.get("AMBIENCE_FADE_TIME", 0.0))
	var ambience: AudioStreamPlayer = _sfx.get_node("Ambience") as AudioStreamPlayer
	_check(ambience != null and ambience.stream is AudioStreamWAV and (ambience.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "Das Raunen hat einen eigenen Spieler mit einer Schleife.")
	_check(bool(_sfx.call("is_ambience_wanted")), "Im laufenden Spiel raunt das Publikum.")
	_sfx.call("_tick_ambience", fade + 0.01)
	_near(float(_sfx.call("get_ambience_gain")), 1.0, "Das Raunen ist nach der Blende voll da.")
	_check(ambience.playing, "Der Spieler des Raunens läuft.")
	_check(absf(ambience.volume_db - float(consts.get("AMBIENCE_DB", 0.0))) < 0.01, "Das Raunen hat seine Lautstärke aus AMBIENCE_DB (%.1f dB)." % ambience.volume_db)
	_check(ambience.volume_db <= -18.0, "Das Raunen ist leise.")
	_game.call("set_paused", true)
	_check(bool(_sfx.call("is_ambience_wanted")), "In der Pause raunt das Publikum weiter.")
	_game.call("set_paused", false)
	_game.set("state", 0)
	_check(not bool(_sfx.call("is_ambience_wanted")), "Im State MENU raunt kein Publikum.")
	_sfx.call("_tick_ambience", fade * 0.5)
	_check(absf(float(_sfx.call("get_ambience_gain")) - 0.5) < 0.05, "Das Raunen blendet aus (Stand %.2f)." % float(_sfx.call("get_ambience_gain")))
	_sfx.call("_tick_ambience", fade)
	_near(float(_sfx.call("get_ambience_gain")), 0.0, "Das Raunen ist nach der Blende weg.")
	_check(not ambience.playing, "Der Spieler des Raunens hält an.")
	_game.set("state", 1)
	# Material: Reparieren, Verschrotten, Klimpern. Die Signale gibt es erst mit Abschnitt 26.
	await _pause(GAP_WAIT)
	if _events.has_signal("item_repaired") and _events.has_signal("item_scrapped") and _events.has_signal("materials_changed"):
		_expect_only("item_repaired", func() -> void: _events.emit_signal("item_repaired", 7), "item_repaired")
		_expect_only("item_scrapped", func() -> void: _events.emit_signal("item_scrapped", 7, 2), "item_scrapped")
		_expect_only("material_gain", func() -> void: _events.emit_signal("materials_changed", 5, 2), "materials_changed mit Zuwachs")
		await _pause(0.2)
		_expect_silent(func() -> void: _events.emit_signal("materials_changed", 3, -2), "materials_changed beim Ausgeben")
		_expect_silent(func() -> void: _events.emit_signal("materials_changed", 3, 0), "materials_changed ohne Änderung (Laufbeginn)")
	else:
		print("Hinweis: Events hat die Material-Signale noch nicht, ihre Verbindung wird nicht geprüft.")
	# Die Reaktionen selbst, unabhängig von den Signalen.
	await _pause(0.2)
	_expect_only("item_repaired", func() -> void: _sfx.call("_on_item_repaired", 3), "Reaktion auf item_repaired")
	_expect_only("item_scrapped", func() -> void: _sfx.call("_on_item_scrapped", 3, 1), "Reaktion auf item_scrapped")
	_expect_only("material_gain", func() -> void: _sfx.call("_on_materials_changed", 4, 1), "Reaktion auf materials_changed")
	_expect_silent(func() -> void: _sfx.call("_on_materials_changed", 2, -2), "Reaktion auf ausgegebenes Material")
	await _pause(GAP_WAIT)


func _test_limits() -> void:
	await _pause(GAP_WAIT)
	var zombie: Node3D = _fake_zombie("walker", Vector3(1.0, 0.0, 1.0))
	# 100 Treffer in einem Bild: nur ein Bruchteil klingt.
	var hits: int = _count("hit")
	for _i: int in 100:
		_events.emit_signal("bullet_hit", zombie, 5.0, {"source": "bullet"})
	var hit_rise: int = _count("hit") - hits
	_check(hit_rise >= 1 and hit_rise <= 5, "100 Treffer in einem Bild starten höchstens ein paar Treffer-Geräusche, waren %d." % hit_rise)
	# 100 Kills und 100 Explosionen ebenso.
	var deaths: int = _count("zombie_death")
	var explosions: int = _count("explosion")
	for _i: int in 100:
		_events.emit_signal("zombie_killed", zombie, {"source": "explosion"})
		_events.emit_signal("zombie_damaged", zombie, 50.0, {"source": "explosion"})
	_check(_count("zombie_death") - deaths <= 5, "100 Kills in einem Bild starten höchstens ein paar Todes-Geräusche, waren %d." % (_count("zombie_death") - deaths))
	_check(_count("explosion") - explosions <= 5, "100 Explosionstreffer in einem Bild starten höchstens ein paar Explosionen, waren %d." % (_count("explosion") - explosions))
	# Schüsse klingen dagegen immer, auch wenn der Vorrat an Spielern kleiner ist.
	var shots: int = _count("shot_smg")
	for _i: int in 100:
		_events.emit_signal("weapon_fired", "smg")
	_check(_count("shot_smg") == shots + 100, "100 Schüsse starten 100 Schuss-Geräusche, waren %d." % (_count("shot_smg") - shots))
	# Auch 100 Geräusche mit Ort an verschiedenen Stellen sind harmlos.
	var dashes: int = _count("dash")
	for i: int in 100:
		_sfx.call("play_at", "dash", Vector3(float(i), 1.0, 0.0))
	_check(_count("dash") == dashes + 100, "100 Geräusche mit Ort starten ohne Fehler.")
	await process_frame
	# Nach dem Mindestabstand klingt der nächste Treffer wieder.
	await _pause(0.2)
	_expect("hit", 1, func() -> void: _events.emit_signal("bullet_hit", zombie, 5.0, {"source": "bullet"}), "Treffer nach dem Mindestabstand")
	zombie.free()


## Flammenwerfer und Strahl: 20 Schüsse je Sekunde über 2 Sekunden. Der Mindestabstand lässt nur
## einen Teil davon ein Stück starten, die Stücke überlappen sich aber lückenlos und belegen nur
## wenige Spieler des Vorrats.
func _test_stream_fire() -> void:
	await _wait_silent()
	var table: Dictionary = _sfx_script.get_script_constant_map().get("SOUNDS", {})
	var pool_size: int = int(_sfx_script.get_script_constant_map().get("POOL_SIZE", 0))
	_check(pool_size > 0, "Die Größe des Vorrats ist lesbar.")
	for weapon_id: String in STREAM_WEAPON_IDS:
		var id: String = "shot_" + weapon_id
		var entry: Dictionary = table.get(id, {})
		var gap: float = float(entry.get("gap", 0.0))
		var spread: float = float(entry.get("pitch", 0.0))
		var length: float = (load(AUDIO_DIR + id + ".wav") as AudioStream).get_length()
		# Bei 20 Schüssen je Sekunde startet spätestens einen Schuss nach dem Mindestabstand das
		# nächste Stück. Liegt das unter der halben Länge, überlappen sich die Stücke lückenlos.
		_check(gap >= 0.08, "%s: Der Mindestabstand ist mindestens 0,08 s (kein Knattern), war %.3f s." % [id, gap])
		_check(gap + STREAM_SHOT_INTERVAL <= length * 0.5 + 0.001, "%s: Mindestabstand %.2f s plus ein Schuss passt nicht in die halbe Länge (%.2f s)." % [id, gap, length * 0.5])
		_check(float(entry.get("db", 0.0)) <= -10.0, "%s: Ein Dauergeräusch ist leise eingestellt." % id)
		# So viele Stücke können höchstens zugleich laufen (das tiefste Stück läuft am längsten),
		# dazu eines, weil ein Spieler sein Ende erst ein Bild später meldet.
		var most_allowed: int = ceili(length / (1.0 - spread) / gap) + 1
		_check(most_allowed * 3 <= pool_size, "%s belegt höchstens ein Drittel des Vorrats, wären %d von %d." % [id, most_allowed, pool_size])
		var before: int = _count(id)
		var total: int = _total_count()
		var most_playing: int = 0
		var least_playing: int = pool_size
		var began: int = Time.get_ticks_msec()
		for i: int in STREAM_SHOTS:
			_events.emit_signal("weapon_fired", weapon_id)
			if i == 0:
				_check(_count(id) == before + 1, "Der erste Schuss von %s klingt sofort." % weapon_id)
			var playing: int = _playing_stream(id)
			most_playing = maxi(most_playing, playing)
			if i >= 10:
				least_playing = mini(least_playing, playing)
			# Fester Fahrplan statt einzelner Pausen: Die Schüsse kommen alle 50 ms, auch wenn ein
			# Bild einmal länger dauert.
			await _wait_until(began + roundi(float(i + 1) * STREAM_SHOT_INTERVAL * 1000.0))
		var elapsed: float = float(Time.get_ticks_msec() - began) / 1000.0
		var starts: int = _count(id) - before
		var allowed: int = floori(elapsed / gap) + 1
		_check(starts <= allowed, "%s: %d Schüsse in %.2f s starten höchstens %d Stücke (Mindestabstand %.2f s), waren %d." % [id, STREAM_SHOTS, elapsed, allowed, gap, starts])
		# Nur wenn die Schüsse wirklich im Takt kamen: Auf einem ausgelasteten Rechner dauert jede
		# Pause länger, dann liegen zwei Schüsse schon einen Mindestabstand auseinander.
		if elapsed <= float(STREAM_SHOTS) * STREAM_SHOT_INTERVAL * 1.15:
			_check(starts * 2 < STREAM_SHOTS, "%s: Weniger als jeder zweite Schuss startet ein Stück, waren %d von %d." % [id, starts, STREAM_SHOTS])
		else:
			print("Hinweis: %s lief zu langsam für die Takt-Prüfung (%.2f s für %d Schüsse)." % [id, elapsed, STREAM_SHOTS])
		# Zwei Stücke Luft für Ruckler der Testmaschine.
		_check(starts >= floori(elapsed / (length * 0.5)) - 2, "%s: Etwa alle %.2f s startet ein Stück, waren nur %d in %.2f s." % [id, length * 0.5, starts, elapsed])
		_check(_total_count() - total == starts, "%s: Im Dauerfeuer startet nichts anderes." % id)
		_check(most_playing <= most_allowed, "%s: Höchstens %d Spieler zugleich, waren %d." % [id, most_allowed, most_playing])
		_check(least_playing >= 1, "%s: Im Dauerfeuer läuft immer mindestens ein Stück." % id)
		_check(most_playing >= 2, "%s: Die Stücke überlappen sich." % id)
		print("Dauerfeuer %s: %d Schüsse in %.2f s starten %d Stücke (erlaubt %d), zugleich %d bis %d Spieler." % [weapon_id, STREAM_SHOTS, elapsed, starts, allowed, least_playing, most_playing])
		await _wait_silent()
	# Treffer von Flammenwerfer und Strahl: 20 je Sekunde, aber nur ab und zu ein Treffer-Geräusch.
	var zombie: Node3D = _fake_zombie("walker", Vector3(1.0, 0.0, 1.0))
	var hit_gap: float = float(int(_sfx_script.get_script_constant_map().get("STREAM_HIT_GAP_MSEC", 0))) / 1000.0
	_check(hit_gap >= 0.15, "Treffer im Dauerfeuer haben einen eigenen Mindestabstand, war %.2f s." % hit_gap)
	for weapon_id: String in STREAM_WEAPON_IDS:
		await _pause(GAP_WAIT)
		var hits: int = _count("hit")
		var began: int = Time.get_ticks_msec()
		for _i: int in 20:
			_events.emit_signal("bullet_hit", zombie, 9.0, {"source": "bullet", "weapon_id": weapon_id, "weapon": weapon_id})
			await _pause(STREAM_SHOT_INTERVAL)
		var elapsed: float = float(Time.get_ticks_msec() - began) / 1000.0
		var rise: int = _count("hit") - hits
		_check(rise >= 2 and rise <= floori(elapsed / maxf(hit_gap, 0.01)) + 1, "20 Treffer von %s in %.2f s starten höchstens %d Treffer-Geräusche, waren %d." % [weapon_id, elapsed, floori(elapsed / maxf(hit_gap, 0.01)) + 1, rise])
	# Eine gewöhnliche Waffe ist davon nicht betroffen: Ihr Treffer klingt sofort, auch direkt nach
	# einem Treffer des Strahls.
	await _pause(GAP_WAIT)
	_expect("hit", 1, func() -> void: _events.emit_signal("bullet_hit", zombie, 9.0, {"source": "bullet", "weapon_id": "beam"}), "Treffer des Strahls")
	await _pause(0.1)
	_expect("hit", 1, func() -> void: _events.emit_signal("bullet_hit", zombie, 25.0, {"source": "bullet", "weapon_id": "pistol"}), "Pistolentreffer kurz nach dem Strahl")
	zombie.free()


func _test_buttons() -> void:
	await _pause(GAP_WAIT)
	var button: Button = Button.new()
	button.text = "Test"
	root.add_child(button)
	_expect("ui_click", 1, func() -> void: button.pressed.emit(), "Klick auf einen neuen Knopf")
	_expect("ui_hover", 1, func() -> void: button.mouse_entered.emit(), "Maus über einem Knopf")
	await _pause(0.2)
	# Auch bei pausiertem Baum (Menüs).
	paused = true
	_expect("ui_click", 1, func() -> void: button.pressed.emit(), "Klick bei pausiertem Baum")
	paused = false
	await _pause(0.2)
	# Ein gesperrter Knopf klingt beim Überfahren nicht.
	button.disabled = true
	_expect("ui_hover", 0, func() -> void: button.mouse_entered.emit(), "Maus über einem gesperrten Knopf")
	button.free()
	# Knöpfe, die es beim Start des Moduls schon gab, sind auch verbunden.
	var early: Button = Button.new()
	root.add_child(early)
	var late_sfx: Node = _sfx_script.new() as Node
	root.add_child(late_sfx)
	var before: int = int(late_sfx.call("get_play_count", "ui_click"))
	early.pressed.emit()
	_check(int(late_sfx.call("get_play_count", "ui_click")) == before + 1, "Ein Knopf, den es schon vor dem Modul gab, klickt.")
	# Dieses Modul lief ohne Spieler (headless): Es zählt, aber nichts spielt.
	var late_playing: int = 0
	for child: Node in late_sfx.get_children():
		if (child is AudioStreamPlayer or child is AudioStreamPlayer3D) and bool(child.get("playing")):
			late_playing += 1
	_check(late_playing == 0, "Headless zählt das Modul nur und startet keinen Spieler.")
	# Auch seine Musik spielt nicht, kennt aber ihr Stück.
	var late_music: Node = late_sfx.get("music") as Node
	late_music.call("advance", 2.0)
	_check(not bool(late_music.call("is_playing")), "Headless startet die Musik keinen Abspieler.")
	_check(str(late_music.call("get_track")) != "", "Headless weiß die Musik trotzdem, welches Stück läuft (%s)." % str(late_music.call("get_track")))
	_check(is_equal_approx(float(late_music.call("get_layer_gain", str(late_music.call("get_track")))), 1.0) or str(late_music.call("get_track")) == "late", "Headless laufen die Blenden der Musik trotzdem.")
	late_sfx.free()
	early.free()
	await _pause(0.2)


func _test_volume_menu() -> void:
	_settings.call("reset_to_defaults")
	_settings.call("apply_audio")
	var menu: CanvasLayer = (load("res://scripts/ui/pause_menu.gd") as GDScript).new() as CanvasLayer
	root.add_child(menu)
	await process_frame
	var settings_menu: Control = menu.get("settings_menu") as Control
	_check(settings_menu != null, "Das Pausemenü hat die Ansicht der Einstellungen.")
	if settings_menu != null:
		var rows: Array = (settings_menu.get_script() as GDScript).get_script_constant_map().get("ROWS", [])
		_check(not rows.is_empty() and str((rows[0] as Dictionary)["id"]) == "master_volume", "Die Lautstärke ist die erste Zeile der Einstellungen.")
		var sliders: Dictionary = settings_menu.get("sliders")
		var labels: Dictionary = settings_menu.get("value_labels")
		_check(sliders.has("master_volume") and labels.has("master_volume"), "Die Einstellungen haben Regler und Anzeige für die Lautstärke.")
		if sliders.has("master_volume") and labels.has("master_volume"):
			var slider: HSlider = sliders["master_volume"] as HSlider
			var label: Label = labels["master_volume"] as Label
			_near(float(slider.min_value), 0.0, "Der Regler beginnt bei 0 Prozent.")
			_near(float(slider.max_value), 100.0, "Der Regler endet bei 100 Prozent.")
			_near(float(slider.value), 80.0, "Der Regler steht anfangs auf 80.")
			_check(label.text == "80 %", "Die Anzeige zeigt anfangs 80 Prozent, war: " + label.text)
			slider.value = 30.0
			_near(_volume(), 0.3, "Der Regler ändert die Lautstärke.")
			_check(label.text == "30 %", "Die Anzeige folgt dem Regler, war: " + label.text)
			_check(absf(_master_db() - linear_to_db(0.3)) < 0.01, "Der Regler wirkt sofort auf den Master-Bus (erwartet %.2f dB, war %.2f dB)." % [linear_to_db(0.3), _master_db()])
			slider.value = 0.0
			_check(AudioServer.is_bus_mute(0), "Regler auf 0: Der Master-Bus ist stumm.")
			_check(label.text == "0 %", "Die Anzeige zeigt 0 Prozent, war: " + label.text)
			(settings_menu.get("reset_button") as Button).pressed.emit()
			_near(_volume(), 0.8, "Standard setzt die Lautstärke zurück.")
			_near(float(slider.value), 80.0, "Standard stellt auch den Regler zurück.")
			_check(not AudioServer.is_bus_mute(0) and absf(_master_db() - linear_to_db(0.8)) < 0.01, "Standard wirkt sofort auf den Master-Bus.")
		# Musik und Geräusche: zwei Regler direkt unter der Lautstärke, jeder mit seinem Bus.
		_check(rows.size() >= 3 and str((rows[1] as Dictionary)["id"]) == "music_volume" and str((rows[2] as Dictionary)["id"]) == "sfx_volume", "Unter der Lautstärke stehen Musik und Geräusche.")
		for entry: Array in [["music_volume", "Music", 70.0, "70 %"], ["sfx_volume", "Sfx", 100.0, "100 %"]]:
			var id: String = str(entry[0])
			var bus_name: String = str(entry[1])
			_check(sliders.has(id) and labels.has(id), "Die Einstellungen haben Regler und Anzeige für %s." % id)
			if not (sliders.has(id) and labels.has(id)):
				continue
			var volume_slider: HSlider = sliders[id] as HSlider
			var volume_label: Label = labels[id] as Label
			_near(float(volume_slider.min_value), 0.0, "%s: Der Regler beginnt bei 0 Prozent." % id)
			_near(float(volume_slider.max_value), 100.0, "%s: Der Regler endet bei 100 Prozent." % id)
			_near(float(volume_slider.value), float(entry[2]), "%s: Der Regler steht anfangs auf dem Standard." % id)
			_check(volume_label.text == str(entry[3]), "%s: Die Anzeige zeigt anfangs %s, war: %s" % [id, str(entry[3]), volume_label.text])
			var master_before: float = _master_db()
			volume_slider.value = 45.0
			_near(float(_settings.get(id)), 0.45, "%s: Der Regler ändert die Einstellung." % id)
			_check(volume_label.text == "45 %", "%s: Die Anzeige folgt dem Regler, war: %s" % [id, volume_label.text])
			_check(absf(_bus_db(bus_name) - linear_to_db(0.45)) < 0.01, "%s: Der Regler wirkt sofort auf den Bus %s (erwartet %.2f dB, war %.2f dB)." % [id, bus_name, linear_to_db(0.45), _bus_db(bus_name)])
			_check(absf(_master_db() - master_before) < 0.001, "%s: Der Master-Bus bleibt, wie er war." % id)
			volume_slider.value = 0.0
			_check(_bus_mute(bus_name) and not AudioServer.is_bus_mute(0), "%s auf 0: Nur der Bus %s ist stumm." % [id, bus_name])
			_check(volume_label.text == "0 %", "%s: Die Anzeige zeigt 0 Prozent, war: %s" % [id, volume_label.text])
		_check(not _bus_mute("Reverb"), "Der Hall-Bus wird nie selbst stumm geschaltet.")
		(settings_menu.get("reset_button") as Button).pressed.emit()
		_near(float(_settings.get("music_volume")), 0.7, "Standard setzt die Musik zurück.")
		_near(float(_settings.get("sfx_volume")), 1.0, "Standard setzt die Geräusche zurück.")
		if sliders.has("music_volume") and sliders.has("sfx_volume"):
			_near(float((sliders["music_volume"] as HSlider).value), 70.0, "Standard stellt den Regler Musik zurück.")
			_near(float((sliders["sfx_volume"] as HSlider).value), 100.0, "Standard stellt den Regler Geräusche zurück.")
		_check(not _bus_mute("Music") and not _bus_mute("Sfx") and absf(_bus_db("Music") - linear_to_db(0.7)) < 0.01 and absf(_bus_db("Sfx")) < 0.01, "Standard wirkt sofort auf die Busse Music und Sfx.")
		# Die Zeilen und die Fußzeile passen auf den Bildschirm (720 Punkte hoch).
		var back_button: Button = settings_menu.get("back_button") as Button
		_check(back_button != null and back_button.offset_bottom <= minf(720.0, settings_menu.size.y if settings_menu.size.y > 0.0 else 720.0), "Die Fußzeile der Einstellungen liegt im Bild (untere Kante %.0f, Höhe der Ansicht %.0f)." % [back_button.offset_bottom if back_button != null else -1.0, settings_menu.size.y])
		# Die Musik-Lautstärke übersteht Speichern und Laden.
		_settings.call("set_music_volume", 0.3)
		_check(bool(_settings.call("save_to", TEMP_SETTINGS)), "Die Einstellungen lassen sich speichern.")
		_settings.call("reset_to_defaults")
		_settings.call("load_from", TEMP_SETTINGS)
		_near(float(_settings.get("music_volume")), 0.3, "Die Musik-Lautstärke übersteht Speichern und Laden.")
		_settings.call("reset_to_defaults")
		_settings.call("apply_audio")
	menu.queue_free()
	await process_frame


# --- Hilfen ---------------------------------------------------------------------------------------

## Ein Knoten, der für Game und das Ton-Modul wie ein Zombie aussieht (hat zombie_type).
func _fake_zombie(type: String, at: Vector3) -> Node3D:
	if _zombie_script == null:
		_zombie_script = GDScript.new()
		_zombie_script.source_code = "extends Node3D\nvar zombie_type: String = \"walker\"\n"
		_zombie_script.reload()
	var zombie: Node3D = Node3D.new()
	zombie.set_script(_zombie_script)
	zombie.set("zombie_type", type)
	zombie.position = at
	root.add_child(zombie)
	return zombie


## Zahl der Spieler aus den beiden Vorräten des Moduls, die gerade laufen (mit oder ohne Ort).
## Musik und Raunen (Schleifen mit eigenen Abspielern) zählen nicht mit.
func _playing_count(with_place: bool) -> int:
	var total: int = 0
	for child: Node in _sfx.get_children():
		if not str(child.name).begins_with("Player"):
			continue
		if (child is AudioStreamPlayer3D) == with_place and bool(child.get("playing")):
			total += 1
	return total


## Laufen gerade Musik oder Raunen?
func _loops_playing() -> bool:
	var ambience: AudioStreamPlayer = _sfx.get_node("Ambience") as AudioStreamPlayer
	return (ambience != null and ambience.playing) or bool(_music().call("is_playing"))


## Alle geladenen Dateien eines Geräuschs (eine oder mehrere Varianten).
func _streams_of(id: String) -> Array:
	var loaded: Dictionary = _sfx.get("_variants")
	return loaded.get(id, [])


## Bus eines Spielers ohne Ort, der gerade dieses Geräusch spielt (&"" wenn keiner).
func _bus_of_playing(id: String) -> StringName:
	var wanted: Array = _streams_of(id)
	for child: Node in _sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player != null and player.playing and wanted.has(player.stream):
			return player.bus
	return &""


## Größte Lautstärke (dB) unter den Spielern ohne Ort, die gerade dieses Geräusch spielen.
func _volume_of_playing(id: String) -> float:
	var wanted: Array = _streams_of(id)
	var loudest: float = -200.0
	for child: Node in _sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player != null and player.playing and wanted.has(player.stream):
			loudest = maxf(loudest, player.volume_db)
	return loudest


## Wartet, bis kein Spieler mehr läuft (höchstens fünf Sekunden), und dann noch einen Moment,
## damit der Ton-Thread alles freigegeben hat.
func _wait_silent() -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while _playing_count(false) + _playing_count(true) > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(_playing_count(false) + _playing_count(true) == 0, "Nach fünf Sekunden laufen noch Geräusche.")
	await _pause(0.3)


func _count(id: String) -> int:
	return int(_sfx.call("get_play_count", id))


## Alle Starts aller Geräusche zusammen.
func _total_count() -> int:
	var total: int = 0
	for id: String in _sfx.call("sound_ids"):
		total += _count(id)
	return total


## Zahl der Spieler, die gerade dieses Geräusch spielen.
func _playing_stream(id: String) -> int:
	var wanted: Array = _streams_of(id)
	var total: int = 0
	for child: Node in _sfx.get_children():
		if (child is AudioStreamPlayer or child is AudioStreamPlayer3D) and bool(child.get("playing")) and wanted.has(child.get("stream")):
			total += 1
	return total


## Spielt gerade ein Spieler mit Ort dieses Geräusch (eine seiner Varianten) an dieser Stelle?
func _playing_at(id: String, at: Vector3) -> bool:
	var wanted: Array = _streams_of(id)
	for child: Node in _sfx.get_children():
		var player: AudioStreamPlayer3D = child as AudioStreamPlayer3D
		if player != null and player.playing and wanted.has(player.stream) and player.global_position.is_equal_approx(at):
			return true
	return false


## Führt action aus und prüft, dass dabei genau dieses Geräusch genau einmal startet und kein anderes.
func _expect_only(id: String, action: Callable, what: String) -> void:
	var before: int = _count(id)
	var total: int = _total_count()
	action.call()
	var got: int = _count(id) - before
	var all: int = _total_count() - total
	_check(got == 1, "%s: %s sollte einmal starten, war %d mal." % [what, id, got])
	_check(all == got, "%s: Außer %s startete noch etwas anderes (%d Starts zusammen)." % [what, id, all])


## Führt action aus und prüft, dass dabei kein Geräusch startet.
func _expect_silent(action: Callable, what: String) -> void:
	var total: int = _total_count()
	action.call()
	_check(_total_count() == total, "%s: sollte stumm bleiben, waren %d Starts." % [what, _total_count() - total])


func _groan_count() -> int:
	var total: int = 0
	for id: String in GROANS:
		total += _count(id)
	return total


func _with(base: Dictionary, source: String) -> Dictionary:
	var info: Dictionary = base.duplicate()
	info["source"] = source
	return info


## Führt action aus und prüft, dass das Geräusch dabei genau rise mal gestartet wurde.
func _expect(id: String, rise: int, action: Callable, what: String) -> void:
	var before: int = _count(id)
	action.call()
	var got: int = _count(id) - before
	_check(got == rise, "%s: %s sollte %d mal starten, war %d mal." % [what, id, rise, got])


## Wartet echte Zeit (die Mindestabstände der Geräusche laufen in echter Zeit).
func _pause(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


## Wartet bis zu einem Zeitpunkt (Millisekunden wie Time.get_ticks_msec): in ganzen Bildern, das
## letzte Stück genau. So trifft ein Takt von 50 ms auch dann, wenn ein Bild 7 oder 9 ms dauert.
func _wait_until(msec: int) -> void:
	while msec - Time.get_ticks_msec() > 12:
		await process_frame
	var left: int = msec - Time.get_ticks_msec()
	if left > 0:
		OS.delay_msec(left)


func _near(value: float, expected: float, message: String) -> void:
	_check(absf(value - expected) < 0.0001, "%s (erwartet %s, war %s)" % [message, expected, value])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
