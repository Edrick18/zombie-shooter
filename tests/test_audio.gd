extends SceneTree
## Tests für den Ton: die Dateien in res://audio, das Modul scripts/game/audio/sfx.gd und die
## Lautstärke-Einstellung (scripts/game/settings.gd, Regler in scripts/ui/settings_menu.gd).
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
]
const MIN_LENGTH: float = 0.03
const MAX_LENGTH: float = 2.0
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
	_test_volume_setting()
	await _test_start()
	_test_loading()
	_test_shots()
	await _test_fight_signals()
	await _test_player_signals()
	await _test_show_signals()
	await _test_cameras()
	await _test_items_and_progress()
	await _test_points_and_cards()
	await _test_groans()
	await _test_limits()
	await _test_stream_fire()
	await _test_buttons()
	await _test_volume_menu()
	await _wait_silent()
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


# --- Lautstärke-Einstellung -----------------------------------------------------------------------

func _volume() -> float:
	return float(_settings.get("master_volume"))


func _master_db() -> float:
	return AudioServer.get_bus_volume_db(0)


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
	_check(AudioServer.bus_count <= buses_before + 1, "Es kommt höchstens ein Bus dazu.")
	_check(_sfx.process_mode == Node.PROCESS_MODE_ALWAYS, "Das Modul läuft auch bei pausiertem Baum.")
	# Ein zweiter Knoten (nach einem Neustart der Szene) legt keinen zweiten Bus an.
	var bus_count: int = AudioServer.bus_count
	var second: Node = _sfx_script.new() as Node
	root.add_child(second)
	_check(AudioServer.bus_count == bus_count, "Ein zweites Modul legt keinen zweiten Bus an.")
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
			await _pause(STREAM_SHOT_INTERVAL)
		var elapsed: float = float(Time.get_ticks_msec() - began) / 1000.0
		var starts: int = _count(id) - before
		var allowed: int = floori(elapsed / gap) + 1
		_check(starts <= allowed, "%s: %d Schüsse in %.2f s starten höchstens %d Stücke (Mindestabstand %.2f s), waren %d." % [id, STREAM_SHOTS, elapsed, allowed, gap, starts])
		_check(starts * 2 < STREAM_SHOTS, "%s: Weniger als jeder zweite Schuss startet ein Stück, waren %d von %d." % [id, starts, STREAM_SHOTS])
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
		if bool(child.get("playing")):
			late_playing += 1
	_check(late_playing == 0, "Headless zählt das Modul nur und startet keinen Spieler.")
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


## Zahl der Spieler des Moduls, die gerade laufen (mit oder ohne Ort).
func _playing_count(with_place: bool) -> int:
	var total: int = 0
	for child: Node in _sfx.get_children():
		if (child is AudioStreamPlayer3D) == with_place and bool(child.get("playing")):
			total += 1
	return total


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
	var streams: Dictionary = _sfx.get("_streams")
	var wanted: AudioStream = streams.get(id) as AudioStream
	var total: int = 0
	for child: Node in _sfx.get_children():
		if wanted != null and bool(child.get("playing")) and child.get("stream") == wanted:
			total += 1
	return total


## Spielt gerade ein Spieler mit Ort dieses Geräusch an dieser Stelle?
func _playing_at(id: String, at: Vector3) -> bool:
	var streams: Dictionary = _sfx.get("_streams")
	var wanted: AudioStream = streams.get(id) as AudioStream
	for child: Node in _sfx.get_children():
		var player: AudioStreamPlayer3D = child as AudioStreamPlayer3D
		if player != null and wanted != null and player.playing and player.stream == wanted and player.global_position.is_equal_approx(at):
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


func _near(value: float, expected: float, message: String) -> void:
	_check(absf(value - expected) < 0.0001, "%s (erwartet %s, war %s)" % [message, expected, value])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
