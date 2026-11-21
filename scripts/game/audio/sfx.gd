extends Node
## Modul: Ton (scripts/game/audio).
## Spielt alle Geräusche des Spiels. main.gd legt den Knoten als Kind "Sfx" an.
##
## Die Dateien liegen in res://audio (erzeugt von tools/make_sounds.py, siehe audio/LIESMICH.txt).
## Der Knoten hört auf Events und spielt dazu passende Geräusche über zwei Vorräte von Spielern:
## AudioStreamPlayer für alles, was der Spieler selbst tut oder als Oberfläche hört (Schüsse,
## Treffer, Menü, Fanfaren), und AudioStreamPlayer3D für Geräusche mit einem Ort in der Welt
## (Stöhnen, Tod eines Zombies, Explosion, Blitz, Kiste, Kameras, Minen). Sind alle Spieler eines
## Vorrats belegt, wird der älteste neu benutzt.
##
## Der Knoten ändert nichts am Spiel und benutzt nie Game.rng: Tonhöhe und Stöhnen würfelt er
## mit dem allgemeinen Zufall (randf), ein Lauf mit festem Seed bleibt also gleich.
## process_mode ALWAYS, damit Menü-Geräusche auch bei pausiertem Baum erklingen.
## Fehlt eine Datei (oder hat Godot sie noch nicht eingelesen), bleibt nur dieses Geräusch stumm.
##
## Was wann erklingt:
##   weapon_fired                 shot_<waffe> für alle 19 Waffen (unbekannte Waffe: shot_pistol).
##                                Flammenwerfer und Strahl feuern bis zu 20 Mal je Sekunde: Ihre
##                                Geräusche sind 0,4 s lange Stücke Fauchen bzw. Summen, die weich
##                                an- und abschwellen. Der Mindestabstand STREAM_GAP lässt nur jeden
##                                zweiten oder dritten Schuss ein Stück starten, die Stücke
##                                überlappen sich zu einem durchgehenden Klang (drei bis vier
##                                Spieler des Vorrats). Ein einzelner Schuss ist ein kurzes Fauchen.
##   hand_reload_started/finished reload_start / reload_done
##   bullet_hit                   hit. Bei Flammenwerfer und Strahl höchstens alle
##                                STREAM_HIT_GAP_MSEC und leiser, damit es nicht knattert
##   zombie_killed                zombie_death am Ort, bei Kopfschuss dazu headshot
##   zombie_spawned (Elite)       elite_roar am Ort
##   zombie_damaged               je nach info.source: "explosion"/"shockwave" explosion,
##                                "lightning"/"jammer" lightning, "ricochet" ricochet,
##                                "thorns" thorns, "bullet" einer Waffe mit Explosion (Rakete,
##                                Granate) explosion. Alle anderen Quellen sind hier stumm: Kameras
##                                ("drone", "cam_tele", "cam_flash", "cam_slow") klingen über
##                                camera_fired, die Mine ("mine") über explosion
##   camera_fired                 am Ort der Kamera: "drone" drone_shot, "cam_tele" cam_tele,
##                                "cam_flash" cam_flash, "cam_slow" cam_slow,
##                                "cam_director" cam_director (unbekannter Typ: nichts)
##   explosion                    explosion am Ort (auch ohne Treffer)
##   mine_placed / mine_triggered mine_placed / mine_triggered am Ort
##   player_damaged               shield_hit, wenn ein Schild da ist, und player_hurt, wenn Schaden
##                                durchkommt
##   player_shield_changed        shield_recharge, sobald das Schild wieder steigt
##   player_dashed                dash
##   player_revived               player_revived (Fanfare der Zweiten Staffel)
##   pack_unlocked                pack_unlocked (Kassenklingeln mit Tusch)
##   bank_changed                 bank_coins bei einer Gutschrift über 0 (Laufende). Der Kauf eines
##                                Pakets (negativer Betrag) und eine Gutschrift von 0 sind stumm
##   chest_dropped / chest_opened chest_drop am Ort / chest_open
##   Game.state verlässt CHOOSING card_chosen
##   upgrade_chosen / synergy_unlocked   upgrade / synergy
##   backpack_opened / backpack_closed   backpack_open / backpack_close
##   points_changed               mehr Punkte bei offenem Rucksack: item_sold,
##                                weniger Punkte im laufenden Spiel (Tür): purchase
##   wave_started / wave_cleared  wave_start / wave_cleared
##   intermission_tick            countdown_tick in den letzten COUNTDOWN_FROM Sekunden
##   game_over                    game_over
##   Knöpfe (BaseButton)          ui_hover (Maus darüber), ui_click (gedrückt); Regler: ui_hover
##   Zombies in der Nähe          zombie_groan_1 bis 3, alle GROAN_GAP_MIN bis GROAN_GAP_MAX s eines

const Settings := preload("res://scripts/game/settings.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")

const AUDIO_DIR: String = "res://audio/"
const BUS_NAME: String = "Sfx"
const MASTER_BUS: String = "Master"
## Zahl der Spieler ohne Ort und mit Ort.
const POOL_SIZE: int = 16
const POOL_SIZE_3D: int = 12
## In dieser Entfernung (m) ist ein Geräusch mit Ort so laut wie eingestellt, weiter weg leiser.
const UNIT_SIZE_3D: float = 8.0
const MAX_DISTANCE_3D: float = 70.0
## Stöhnen: Abstand zwischen zwei Lauten in Sekunden, Umkreis um den Spieler in Metern.
const GROAN_GAP_MIN: float = 1.5
const GROAN_GAP_MAX: float = 4.0
const GROAN_RETRY: float = 0.5
const GROAN_RADIUS: float = 18.0
const GROAN_IDS: Array[String] = ["zombie_groan_1", "zombie_groan_2", "zombie_groan_3"]
## Mund eines Zombies über seinen Füßen.
const VOICE_OFFSET: Vector3 = Vector3(0.0, 1.4, 0.0)
## Die letzten so vielen Sekunden vor einer Welle ticken.
const COUNTDOWN_FROM: int = 3
const SHOT_PREFIX: String = "shot_"
const FALLBACK_SHOT: String = "shot_pistol"
## Elite-Zombies sterben tiefer und lauter.
const ELITE_DEATH_PITCH: float = 0.72
const ELITE_DEATH_DB: float = 3.0
## Die Druckwelle beim Nachladen ist eine leisere Explosion.
const SHOCKWAVE_DB: float = -6.0
## So lange (ms) wartet der Knoten am Programmende, wenn noch ein Geräusch läuft (siehe _exit_tree).
const EXIT_GRACE_MSEC: int = 200
## Geräusch je Schadensquelle (info.source von zombie_damaged). Quellen, die hier fehlen, sind
## stumm: Die Kameras klingen über camera_fired, die Mine über explosion.
const DAMAGE_SOUNDS: Dictionary = {
	"explosion": "explosion",
	"shockwave": "explosion",
	"lightning": "lightning",
	"jammer": "lightning",
	"ricochet": "ricochet",
	"thorns": "thorns",
}
## Geräusch je Kameratyp (camera_id von camera_fired).
const CAMERA_SOUNDS: Dictionary = {
	"drone": "drone_shot",
	"cam_tele": "cam_tele",
	"cam_flash": "cam_flash",
	"cam_slow": "cam_slow",
	"cam_director": "cam_director",
}
## Mindestabstand (s) zwischen zwei Stücken der Dauerfeuer-Geräusche (Flammenwerfer, Strahl).
## Die Stücke sind 0,4 s lang und schwellen als halbe Sinuswelle an und ab: Starten sie alle 0,12
## bis 0,2 s, bleibt die Summe gleich laut. 0,12 liegt mit Absicht nicht auf einem Vielfachen der
## Schussabstände (Flamme 67 ms, Strahl 50 ms): So startet verlässlich jeder zweite Stoß der
## Flamme (alle 133 ms) und jeder dritte Treffer des Strahls (alle 150 ms), auch wenn die Uhr
## um eine Millisekunde schwankt.
const STREAM_GAP: float = 0.12
## Treffer von Flammenwerfer und Strahl: höchstens alle so viele Millisekunden ein Treffer-Geräusch,
## und um so viele dB leiser.
const STREAM_HIT_GAP_MSEC: int = 250
const STREAM_HIT_DB: float = -5.0

## Alle Geräusche: Name = Dateiname ohne Endung.
## db: Grundlautstärke in dB. pitch: Streuung der Tonhöhe (0.05 = 5 % nach oben und unten).
## gap: Mindestabstand in Sekunden zwischen zwei Starts desselben Geräuschs (0 = jeder Start zählt).
const SOUNDS: Dictionary = {
	"shot_pistol": {"db": -5.0, "pitch": 0.05, "gap": 0.0},
	"shot_revolver": {"db": -3.0, "pitch": 0.04, "gap": 0.0},
	"shot_smg": {"db": -7.0, "pitch": 0.06, "gap": 0.0},
	"shot_sawed_off": {"db": -2.0, "pitch": 0.05, "gap": 0.0},
	"shot_shotgun": {"db": -2.0, "pitch": 0.04, "gap": 0.0},
	"shot_rifle": {"db": -5.0, "pitch": 0.05, "gap": 0.0},
	"shot_sniper": {"db": -1.0, "pitch": 0.03, "gap": 0.0},
	"shot_minigun": {"db": -9.0, "pitch": 0.07, "gap": 0.0},
	"shot_rocket_launcher": {"db": -6.0, "pitch": 0.04, "gap": 0.0},
	"reload_start": {"db": -8.0, "pitch": 0.04, "gap": 0.05},
	"reload_done": {"db": -7.0, "pitch": 0.04, "gap": 0.05},
	"hit": {"db": -12.0, "pitch": 0.08, "gap": 0.05},
	"headshot": {"db": -7.0, "pitch": 0.04, "gap": 0.08},
	"zombie_death": {"db": -4.0, "pitch": 0.12, "gap": 0.04},
	"zombie_groan_1": {"db": -6.0, "pitch": 0.12, "gap": 0.0},
	"zombie_groan_2": {"db": -6.0, "pitch": 0.12, "gap": 0.0},
	"zombie_groan_3": {"db": -6.0, "pitch": 0.12, "gap": 0.0},
	"elite_roar": {"db": -1.0, "pitch": 0.05, "gap": 0.5},
	"player_hurt": {"db": -4.0, "pitch": 0.06, "gap": 0.1},
	"shield_hit": {"db": -6.0, "pitch": 0.05, "gap": 0.08},
	"shield_recharge": {"db": -14.0, "pitch": 0.0, "gap": 0.5},
	"dash": {"db": -6.0, "pitch": 0.06, "gap": 0.0},
	"chest_drop": {"db": -3.0, "pitch": 0.05, "gap": 0.1},
	"chest_open": {"db": -6.0, "pitch": 0.0, "gap": 0.1},
	"card_chosen": {"db": -8.0, "pitch": 0.03, "gap": 0.05},
	"upgrade": {"db": -7.0, "pitch": 0.0, "gap": 0.25},
	"synergy": {"db": -5.0, "pitch": 0.0, "gap": 0.5},
	"backpack_open": {"db": -8.0, "pitch": 0.03, "gap": 0.1},
	"backpack_close": {"db": -8.0, "pitch": 0.03, "gap": 0.1},
	"item_sold": {"db": -8.0, "pitch": 0.03, "gap": 0.06},
	"purchase": {"db": -6.0, "pitch": 0.02, "gap": 0.06},
	"wave_start": {"db": -5.0, "pitch": 0.0, "gap": 0.5},
	"wave_cleared": {"db": -6.0, "pitch": 0.0, "gap": 0.5},
	"countdown_tick": {"db": -14.0, "pitch": 0.0, "gap": 0.2},
	"game_over": {"db": -4.0, "pitch": 0.0, "gap": 1.0},
	"ui_hover": {"db": -20.0, "pitch": 0.03, "gap": 0.04},
	"ui_click": {"db": -13.0, "pitch": 0.03, "gap": 0.03},
	"explosion": {"db": -1.0, "pitch": 0.1, "gap": 0.07},
	"lightning": {"db": -7.0, "pitch": 0.12, "gap": 0.06},
	# Der Abstand hält viele Drohnen im Zaum: höchstens zwölf Schüsse je Sekunde sind zu hören.
	"drone_shot": {"db": -10.0, "pitch": 0.08, "gap": 0.08},
	# --- Ausbau 3: Schüsse der neuen Waffen ---
	"shot_burst_pistol": {"db": -6.0, "pitch": 0.05, "gap": 0.0},
	"shot_nail_gun": {"db": -8.0, "pitch": 0.06, "gap": 0.0},
	"shot_machine_pistol": {"db": -9.0, "pitch": 0.07, "gap": 0.0},
	"shot_crossbow": {"db": -5.0, "pitch": 0.04, "gap": 0.0},
	"shot_grenade_launcher": {"db": -4.0, "pitch": 0.05, "gap": 0.0},
	# Dauerfeuer als überlappende Stücke (siehe STREAM_GAP). Drei Stücke zusammen sind etwa 4 dB
	# lauter als eines, deshalb die niedrige Grundlautstärke. Die Streuung der Tonhöhe macht beim
	# Fauchen jedes Stück etwas anders, sonst wiederholt sich dasselbe Rauschen im Takt der Starts.
	# Der Summton bleibt ohne Streuung, damit er nicht eiert.
	"shot_flamethrower": {"db": -13.0, "pitch": 0.1, "gap": STREAM_GAP},
	"shot_beam": {"db": -15.0, "pitch": 0.0, "gap": STREAM_GAP},
	"shot_tesla": {"db": -5.0, "pitch": 0.08, "gap": 0.0},
	"shot_lmg": {"db": -8.0, "pitch": 0.06, "gap": 0.0},
	"shot_auto_shotgun": {"db": -4.0, "pitch": 0.05, "gap": 0.0},
	# --- Ausbau 3: Kameras (leise, mit Abstand: Zehn Kameras sollen nicht nerven) ---
	"cam_tele": {"db": -8.0, "pitch": 0.05, "gap": 0.12},
	"cam_flash": {"db": -9.0, "pitch": 0.06, "gap": 0.15},
	"cam_slow": {"db": -11.0, "pitch": 0.06, "gap": 0.2},
	"cam_director": {"db": -17.0, "pitch": 0.02, "gap": 0.25},
	# --- Ausbau 3: Gegenstände und Fortschritt ---
	"mine_placed": {"db": -12.0, "pitch": 0.05, "gap": 0.1},
	"mine_triggered": {"db": -12.0, "pitch": 0.0, "gap": 0.1},
	"player_revived": {"db": -4.0, "pitch": 0.0, "gap": 1.0},
	"pack_unlocked": {"db": -6.0, "pitch": 0.0, "gap": 0.5},
	"bank_coins": {"db": -7.0, "pitch": 0.0, "gap": 1.0},
	"ricochet": {"db": -14.0, "pitch": 0.1, "gap": 0.08},
	"thorns": {"db": -9.0, "pitch": 0.08, "gap": 0.1},
}

## false: Geräusche werden nur gezählt (get_play_count), kein Spieler startet. Headless (Tests)
## ist das der Standard: Dort endet das Programm oft mitten in einem Geräusch, und Godot meldet
## dann verlorene Objekte ("ObjectDB instances leaked", "resources still in use"), womit ein Test
## als fehlgeschlagen gilt. Wer die Spieler headless prüfen will (tests/test_audio.gd), setzt true
## und wartet vor dem Ende, bis alles verklungen ist.
var playback_enabled: bool = DisplayServer.get_name() != "headless"

## Geladene Geräusche (Name -> AudioStream). Was fehlt, steht hier nicht.
var _streams: Dictionary = {}
## Wie oft ein Geräusch gestartet wurde (Name -> int).
var _play_counts: Dictionary = {}
## Zeitpunkt des letzten Starts in Millisekunden (Name -> int).
var _last_start: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
## Laufende Nummer des letzten Starts je Spieler: Der kleinste Wert ist der älteste.
var _order: PackedInt64Array = PackedInt64Array()
var _order_3d: PackedInt64Array = PackedInt64Array()
var _serial: int = 0
## Knöpfe und Regler, die schon verbunden sind (Instanz-Nummer -> true).
var _wired: Dictionary = {}
## Bis zu diesem Zeitpunkt (Millisekunden) läuft voraussichtlich noch ein Geräusch.
var _busy_until: int = 0
## Das Fenster wird gerade geschlossen.
var _closing: bool = false
var _groan_left: float = GROAN_GAP_MIN
## Letzter bekannter Punktestand, -1 = noch keiner in diesem Lauf.
var _points: int = -1
var _shield: float = 0.0
var _shield_rising: bool = false
var _last_state: int = -1
## Zeitpunkt (Millisekunden) des letzten Treffer-Geräuschs von Flammenwerfer oder Strahl.
var _stream_hit_at: int = -STREAM_HIT_GAP_MSEC


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Die gespeicherte Lautstärke gilt ab dem Start.
	Settings.ensure_loaded()
	Settings.apply_audio()
	_ensure_bus()
	_build_pools()
	_load_sounds()
	_groan_left = randf_range(GROAN_GAP_MIN, GROAN_GAP_MAX)
	_last_state = int(Game.state)
	_connect_events()
	get_tree().node_added.connect(_wire_ui)
	_wire_existing(get_tree().root)


## Endet das Programm, während noch ein Geräusch läuft, stoppen die Spieler zwar sofort, der
## Ton-Thread gibt das Geräusch aber erst einige Schritte später frei. Ist Godot bis dahin
## schon beendet, meldet es verlorene Objekte ("ObjectDB instances leaked", "resources still in
## use"). Deshalb bekommt der Ton-Thread hier kurz Zeit (gemessen: 60 ms reichen nicht immer,
## 100 ms schon). Ohne laufendes Geräusch wird nicht gewartet, und auch nicht beim Neustart des
## Laufs: Game.restart_run setzt den State auf MENU, bevor es die Szene neu lädt, und das
## Programm läuft danach weiter, Godot räumt also selbst auf. Wird das Fenster geschlossen,
## gilt das auch im State MENU (Kandidatenwahl) als Programmende.
func _exit_tree() -> void:
	if Time.get_ticks_msec() >= _busy_until or (Game.state == Game.State.MENU and not _closing):
		return
	_busy_until = 0
	for player: AudioStreamPlayer in _players:
		player.stop()
	for player_3d: AudioStreamPlayer3D in _players_3d:
		player_3d.stop()
	OS.delay_msec(EXIT_GRACE_MSEC)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_closing = true


func _process(delta: float) -> void:
	var state: int = int(Game.state)
	if state != _last_state:
		# Die Kistenwahl ist vorbei: Eine Karte wurde genommen.
		if _last_state == Game.State.CHOOSING and (state == Game.State.PLAYING or state == Game.State.PACKING):
			play("card_chosen")
		_last_state = state
	if state == Game.State.PLAYING and not get_tree().paused:
		_tick_groans(delta)


# --- Öffentliche Schnittstelle ----------------------------------------------------------------

## Spielt ein Geräusch ohne Ort. volume_db kommt zur Grundlautstärke des Geräuschs dazu.
## Ein unbekannter oder nicht geladener Name tut nichts. Kommt dasselbe Geräusch schneller
## hintereinander als sein Mindestabstand (SOUNDS, "gap"), wird der Start ausgelassen.
func play(sound_id: String, volume_db: float = 0.0) -> void:
	_start(sound_id, volume_db, 1.0)


## Spielt ein Geräusch an einer Stelle der Welt (Weltkoordinaten): Der Spieler hört, woher es
## kommt, und weiter weg ist es leiser. Sonst wie play.
func play_at(sound_id: String, position: Vector3, volume_db: float = 0.0) -> void:
	_start_at(sound_id, position, volume_db, 1.0)


## Ist das Geräusch geladen?
func has_sound(sound_id: String) -> bool:
	return _streams.has(sound_id)


## Wie oft das Geräusch gestartet wurde, seit es diesen Knoten gibt (ausgelassene Starts zählen nicht).
func get_play_count(sound_id: String) -> int:
	return int(_play_counts.get(sound_id, 0))


## Namen aller Geräusche, die das Spiel kennt (auch die, deren Datei fehlt), sortiert.
func sound_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in SOUNDS:
		ids.append(id)
	ids.sort()
	return ids


# --- Aufbau -------------------------------------------------------------------------------------

## Legt den Bus "Sfx" an, wenn es ihn noch nicht gibt. Er geht in den Master-Bus.
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, MASTER_BUS)


func _build_pools() -> void:
	for i: int in POOL_SIZE:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Player%d" % i
		player.bus = BUS_NAME
		add_child(player)
		_players.append(player)
		_order.append(0)
	for i: int in POOL_SIZE_3D:
		var player_3d: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player_3d.name = "Player3D%d" % i
		player_3d.bus = BUS_NAME
		player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player_3d.unit_size = UNIT_SIZE_3D
		player_3d.max_distance = MAX_DISTANCE_3D
		add_child(player_3d)
		_players_3d.append(player_3d)
		_order_3d.append(0)


func _load_sounds() -> void:
	for id: String in SOUNDS:
		var stream: AudioStream = _load_stream(AUDIO_DIR + id + ".wav")
		if stream != null:
			_streams[id] = stream


## Lädt eine Tondatei, ohne je eine Fehlermeldung auszulösen.
## 1. Hat Godot die Datei eingelesen (im fertigen Spiel gibt es nur das), wird sie normal geladen.
## 2. Sonst wird die rohe WAV-Datei direkt gelesen (frisch kopiertes Projekt ohne Import).
## 3. Fehlt beides, kommt null zurück.
func _load_stream(path: String) -> AudioStream:
	if _is_imported(path) and ResourceLoader.exists(path):
		var imported: AudioStream = load(path) as AudioStream
		if imported != null:
			return imported
	if FileAccess.file_exists(path):
		return AudioStreamWAV.load_from_file(path)
	# Letzter Versuch: ein Paket, in dem die Import-Notiz nicht lesbar ist, die Datei aber bekannt.
	if not FileAccess.file_exists(path + ".import") and ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


## Gibt es die Import-Notiz der Datei und die Datei, auf die sie zeigt? Nur dann lädt load()
## ohne Fehlermeldung.
func _is_imported(path: String) -> bool:
	var note_path: String = path + ".import"
	if not FileAccess.file_exists(note_path):
		return false
	var note: ConfigFile = ConfigFile.new()
	if note.load(note_path) != OK:
		return false
	var target: String = str(note.get_value("remap", "path", ""))
	return target != "" and FileAccess.file_exists(target)


func _connect_events() -> void:
	Events.run_started.connect(_on_run_started)
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.hand_reload_started.connect(_on_hand_reload_started)
	Events.hand_reload_finished.connect(_on_hand_reload_finished)
	Events.bullet_hit.connect(_on_bullet_hit)
	Events.zombie_damaged.connect(_on_zombie_damaged)
	Events.explosion.connect(_on_explosion)
	Events.zombie_killed.connect(_on_zombie_killed)
	Events.zombie_spawned.connect(_on_zombie_spawned)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_shield_changed.connect(_on_player_shield_changed)
	Events.player_dashed.connect(_on_player_dashed)
	Events.camera_fired.connect(_on_camera_fired)
	Events.mine_placed.connect(_on_mine_placed)
	Events.mine_triggered.connect(_on_mine_triggered)
	Events.player_revived.connect(_on_player_revived)
	Events.pack_unlocked.connect(_on_pack_unlocked)
	Events.bank_changed.connect(_on_bank_changed)
	Events.chest_dropped.connect(_on_chest_dropped)
	Events.chest_opened.connect(_on_chest_opened)
	Events.upgrade_chosen.connect(_on_upgrade_chosen)
	Events.synergy_unlocked.connect(_on_synergy_unlocked)
	Events.backpack_opened.connect(_on_backpack_opened)
	Events.backpack_closed.connect(_on_backpack_closed)
	Events.points_changed.connect(_on_points_changed)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_cleared.connect(_on_wave_cleared)
	Events.intermission_tick.connect(_on_intermission_tick)
	Events.game_over.connect(_on_game_over)


# --- Abspielen ----------------------------------------------------------------------------------

func _start(sound_id: String, volume_db: float, pitch_factor: float) -> void:
	var stream: AudioStream = _claim(sound_id)
	if stream == null:
		return
	if not playback_enabled:
		return
	var index: int = _free_player()
	var player: AudioStreamPlayer = _players[index]
	_serial += 1
	_order[index] = _serial
	player.stream = stream
	player.volume_db = _base_db(sound_id) + volume_db
	player.pitch_scale = _pitch(sound_id) * pitch_factor
	player.play()
	_note_busy(stream, player.pitch_scale)


func _start_at(sound_id: String, position: Vector3, volume_db: float, pitch_factor: float) -> void:
	var stream: AudioStream = _claim(sound_id)
	if stream == null:
		return
	if not playback_enabled:
		return
	var index: int = _free_player_3d()
	var player: AudioStreamPlayer3D = _players_3d[index]
	_serial += 1
	_order_3d[index] = _serial
	player.stream = stream
	player.volume_db = _base_db(sound_id) + volume_db
	player.pitch_scale = _pitch(sound_id) * pitch_factor
	player.global_position = position
	player.play()
	_note_busy(stream, player.pitch_scale)


## Prüft, ob das Geräusch jetzt starten darf (geladen, Knoten im Baum, Mindestabstand vorbei),
## zählt den Start und gibt die Tondatei zurück. null = nicht spielen.
func _claim(sound_id: String) -> AudioStream:
	if not _streams.has(sound_id) or not is_inside_tree() or _players.is_empty():
		return null
	var now: int = Time.get_ticks_msec()
	var gap_msec: int = roundi(float((SOUNDS[sound_id] as Dictionary)["gap"]) * 1000.0)
	if gap_msec > 0 and _last_start.has(sound_id) and now - int(_last_start[sound_id]) < gap_msec:
		return null
	_last_start[sound_id] = now
	_play_counts[sound_id] = int(_play_counts.get(sound_id, 0)) + 1
	return _streams[sound_id] as AudioStream


## Merkt, bis wann das gerade gestartete Geräusch läuft (mit etwas Luft).
func _note_busy(stream: AudioStream, pitch: float) -> void:
	var length_msec: int = ceili(stream.get_length() / maxf(pitch, 0.1) * 1000.0) + 100
	_busy_until = maxi(_busy_until, Time.get_ticks_msec() + length_msec)


func _base_db(sound_id: String) -> float:
	return float((SOUNDS[sound_id] as Dictionary)["db"])


## Tonhöhe mit etwas Zufall (allgemeiner Zufall, nie Game.rng).
func _pitch(sound_id: String) -> float:
	var spread: float = float((SOUNDS[sound_id] as Dictionary)["pitch"])
	if spread <= 0.0:
		return 1.0
	return 1.0 + randf_range(-spread, spread)


## Stelle eines freien Spielers, sonst die des ältesten.
func _free_player() -> int:
	var oldest: int = 0
	for i: int in _players.size():
		if not _players[i].playing:
			return i
		if _order[i] < _order[oldest]:
			oldest = i
	return oldest


func _free_player_3d() -> int:
	var oldest: int = 0
	for i: int in _players_3d.size():
		if not _players_3d[i].playing:
			return i
		if _order_3d[i] < _order_3d[oldest]:
			oldest = i
	return oldest


## Spielt ein Geräusch am Ort eines Zombies (oder des Treffers aus info), ohne Ort, wenn keiner
## bekannt ist.
func _play_near(sound_id: String, zombie: Node3D, info: Dictionary, volume_db: float = 0.0, pitch_factor: float = 1.0) -> void:
	var hit_position: Variant = info.get("hit_position")
	if typeof(hit_position) == TYPE_VECTOR3:
		_start_at(sound_id, hit_position as Vector3, volume_db, pitch_factor)
	elif is_instance_valid(zombie) and zombie.is_inside_tree():
		_start_at(sound_id, zombie.global_position + VOICE_OFFSET, volume_db, pitch_factor)
	else:
		_start(sound_id, volume_db, pitch_factor)


# --- Stöhnen ------------------------------------------------------------------------------------

## Lässt in zufälligen Abständen einen Zombie in der Nähe des Spielers stöhnen.
func _tick_groans(delta: float) -> void:
	_groan_left -= delta
	if _groan_left > 0.0:
		return
	_groan_left = GROAN_RETRY
	if not is_instance_valid(Game.player):
		return
	var listener: Node3D = Game.player
	if not listener.is_inside_tree():
		return
	var near: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		var zombie: Node3D = node as Node3D
		if zombie == null or not zombie.is_inside_tree():
			continue
		if zombie.global_position.distance_to(listener.global_position) <= GROAN_RADIUS:
			near.append(zombie.global_position + VOICE_OFFSET)
	if near.is_empty():
		return
	_groan_left = randf_range(GROAN_GAP_MIN, GROAN_GAP_MAX)
	play_at(GROAN_IDS[randi() % GROAN_IDS.size()], near[randi() % near.size()])


# --- Oberfläche ---------------------------------------------------------------------------------

func _wire_existing(node: Node) -> void:
	_wire_ui(node)
	for child: Node in node.get_children():
		_wire_existing(child)


## Verbindet einen Knopf (Maus darüber, gedrückt) oder Regler (Wert geändert) mit seinem Geräusch.
func _wire_ui(node: Node) -> void:
	if not (node is BaseButton or node is Slider):
		return
	var id: int = node.get_instance_id()
	if _wired.has(id):
		return
	_wired[id] = true
	if node is BaseButton:
		var button: BaseButton = node as BaseButton
		button.mouse_entered.connect(_on_button_hover.bind(button))
		button.pressed.connect(_on_button_pressed)
	else:
		(node as Slider).value_changed.connect(_on_slider_changed)


func _on_button_hover(button: BaseButton) -> void:
	if button.disabled or not button.is_visible_in_tree():
		return
	play("ui_hover")


func _on_button_pressed() -> void:
	play("ui_click")


func _on_slider_changed(_value: float) -> void:
	play("ui_hover")


# --- Reaktionen auf das Spiel -------------------------------------------------------------------

func _on_run_started() -> void:
	# Der erste Punktestand eines Laufs ist kein Kauf und kein Verkauf.
	_points = -1
	_shield = 0.0
	_shield_rising = false
	_groan_left = randf_range(GROAN_GAP_MIN, GROAN_GAP_MAX)


func _on_weapon_fired(weapon_id: String) -> void:
	var sound_id: String = SHOT_PREFIX + weapon_id
	play(sound_id if has_sound(sound_id) else FALLBACK_SHOT)


func _on_hand_reload_started(_hand: int, _duration: float) -> void:
	play("reload_start")


func _on_hand_reload_finished(_hand: int) -> void:
	play("reload_done")


func _on_bullet_hit(_zombie: Node3D, _damage: float, info: Dictionary) -> void:
	if _is_stream_weapon(str(info.get("weapon_id", info.get("weapon", "")))):
		# Flamme und Strahl treffen ständig und oft mehrere Zombies zugleich: nur ab und zu ein
		# leiser Treffer, das Fauchen bzw. Summen trägt den Rest.
		var now: int = Time.get_ticks_msec()
		if now - _stream_hit_at < STREAM_HIT_GAP_MSEC:
			return
		_stream_hit_at = now
		play("hit", STREAM_HIT_DB)
		return
	play("hit")


## Feuert diese Waffe als Dauerstrom (Flammenwerfer, Strahl)?
func _is_stream_weapon(weapon_id: String) -> bool:
	var mode: String = WeaponDefs.mode(weapon_id)
	return mode == WeaponDefs.MODE_FLAME or mode == WeaponDefs.MODE_BEAM


## Die Schüsse der Kameras ("drone", "cam_tele", "cam_flash", "cam_slow") haben hier kein Geräusch:
## Es kommt über camera_fired. Auch "mine" bleibt stumm, ihre Explosion kommt über explosion.
func _on_zombie_damaged(zombie: Node3D, _amount: float, info: Dictionary) -> void:
	var source: String = str(info.get("source", ""))
	if source == "bullet":
		# Rakete und Granate explodieren am Treffer.
		if WeaponDefs.is_explosive(str(info.get("weapon_id", ""))):
			_play_near("explosion", zombie, info)
	elif DAMAGE_SOUNDS.has(source):
		_play_near(str(DAMAGE_SOUNDS[source]), zombie, info, SHOCKWAVE_DB if source == "shockwave" else 0.0)


## Jede Explosion ist zu hören, auch wenn sie niemanden trifft (Rakete in die Wand). Die Treffer
## derselben Explosion bleiben danach durch die Sperrzeit des Geräuschs stumm.
func _on_explosion(position: Vector3, _radius: float) -> void:
	play_at("explosion", position)


## Schuss, Blitz oder Markierung einer Kamera, am Ort der Kamera. Ein unbekannter Typ bleibt stumm.
func _on_camera_fired(camera_id: String, position: Vector3) -> void:
	if CAMERA_SOUNDS.has(camera_id):
		play_at(str(CAMERA_SOUNDS[camera_id]), position)


func _on_mine_placed(position: Vector3) -> void:
	play_at("mine_placed", position)


## Der Warnton kurz vor der Explosion. Die Explosion selbst kommt über explosion.
func _on_mine_triggered(position: Vector3) -> void:
	play_at("mine_triggered", position)


func _on_zombie_killed(zombie: Node3D, info: Dictionary) -> void:
	var is_elite: bool = is_instance_valid(zombie) and str(zombie.get("zombie_type")) == "elite"
	# Der Tod erklingt am Zombie, nicht am Treffer.
	_play_near("zombie_death", zombie, {}, ELITE_DEATH_DB if is_elite else 0.0, ELITE_DEATH_PITCH if is_elite else 1.0)
	if bool(info.get("headshot", false)):
		play("headshot")


func _on_zombie_spawned(zombie: Node3D) -> void:
	if is_instance_valid(zombie) and str(zombie.get("zombie_type")) == "elite":
		_play_near("elite_roar", zombie, {})


## Der Spieler fängt Schaden zuerst mit dem Schild ab (player.gd): Nur was darüber hinausgeht,
## tut weh.
func _on_player_damaged(amount: float) -> void:
	if _shield > 0.0:
		play("shield_hit")
	if amount > _shield:
		play("player_hurt")


func _on_player_shield_changed(shield: float, _max_shield: float) -> void:
	if shield > _shield:
		if not _shield_rising:
			play("shield_recharge")
		_shield_rising = true
	elif shield < _shield:
		_shield_rising = false
	_shield = shield


func _on_player_dashed() -> void:
	play("dash")


func _on_player_revived() -> void:
	play("player_revived")


func _on_pack_unlocked(_pack_id: String) -> void:
	play("pack_unlocked")


## Nur eine Gutschrift klimpert (Laufende). Der Kauf eines Pakets kommt mit negativem Betrag und
## hat sein eigenes Geräusch (pack_unlocked), eine Gutschrift von 0 ist nichts zum Feiern.
func _on_bank_changed(_bank: int, gained: int) -> void:
	if gained > 0:
		play("bank_coins")


func _on_chest_dropped(chest: Node3D) -> void:
	_play_near("chest_drop", chest, {})


func _on_chest_opened(_rarity: int, _offers: Array) -> void:
	play("chest_open")


func _on_upgrade_chosen(_upgrade_id: String, _new_level: int) -> void:
	play("upgrade")


func _on_synergy_unlocked(_synergy_id: String) -> void:
	play("synergy")


func _on_backpack_opened(_new_uid: int) -> void:
	play("backpack_open")


func _on_backpack_closed() -> void:
	play("backpack_close")


func _on_points_changed(total: int) -> void:
	var before: int = _points
	_points = total
	if before < 0:
		return
	if total > before and Game.state == Game.State.PACKING:
		play("item_sold")
	elif total < before and Game.state == Game.State.PLAYING:
		play("purchase")


func _on_wave_started(_wave: int, _total_zombies: int) -> void:
	play("wave_start")


func _on_wave_cleared(_wave: int) -> void:
	play("wave_cleared")


func _on_intermission_tick(seconds_left: int) -> void:
	if seconds_left >= 1 and seconds_left <= COUNTDOWN_FROM:
		play("countdown_tick")


func _on_game_over(_stats: Dictionary) -> void:
	play("game_over")
