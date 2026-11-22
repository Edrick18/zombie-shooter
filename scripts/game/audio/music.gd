extends Node
## Modul: Ton (scripts/game/audio).
## Die Musik des Spiels. sfx.gd legt den Knoten als Kind "Music" an.
##
## Die Dateien liegen in res://audio (erzeugt von tools/make_music.py, siehe audio/LIESMICH.txt):
##   music_menu       Kandidatenwahl, Programm und der Bildschirm nach dem Abgesang
##   music_calm       Pause zwischen den Wellen (auch vor der ersten Welle)
##   music_wave       in der Welle
##   music_late       ab Welle LATE_WAVE: eine Zusatzspur, die über music_wave läuft
##   music_game_over  Abgesang bei Game Over (keine Schleife), danach wieder music_menu
##
## Welches Stück läuft (get_track), hängt nur von Game.state und den Signalen ab:
##   State MENU                             "menu"
##   State GAME_OVER                        "game_over", nach seinem Ende "menu"
##   sonst, nach wave_started               "wave", ab Welle LATE_WAVE "late" (= wave + Zusatzspur)
##   sonst, nach wave_cleared/run_started   "calm"
## In Pause, Kistenwahl und Rucksack (States PAUSED, CHOOSING, PACKING) läuft das Stück weiter,
## aber leiser und dumpfer (MUFFLE_DB, Tiefpass auf dem Bus Music bei MUFFLE_CUTOFF).
##
## Ein Wechsel blendet in FADE_TIME Sekunden über (gleiche Leistung). music_calm, music_wave und
## music_late haben dasselbe Tempo und dieselbe Tonart und laufen gemeinsam in einem Abspieler
## (AudioStreamSynchronized): Sie bleiben auf den Abtastwert genau im Takt, gewechselt wird nur
## über ihre Lautstärken. Laute Ereignisse drängen die Musik kurz zurück (duck): sfx.gd ruft das
## für alle Geräusche mit dem Eintrag "duck" in seiner Tabelle SOUNDS auf.
##
## Der Knoten ändert nichts am Spiel und benutzt nie Game.rng. process_mode ALWAYS, damit die
## Musik auch bei pausiertem Baum weiterläuft. Die Zeit für das Blenden ist echte Zeit (nicht die
## verlangsamte Spielzeit der Zeitlupe).
## Headless (Tests) startet kein Abspieler (playback_enabled false), die ganze Logik läuft aber:
## get_track, get_layer_gain, is_fading, is_muffled, get_muffle und get_duck_db sind abfragbar,
## advance(delta) stellt die Zeit von Hand vor.
## Fehlt eine Datei, bleibt nur diese Spur stumm.

const AudioBuses := preload("res://scripts/game/audio/audio_buses.gd")
const AudioLoader := preload("res://scripts/game/audio/audio_loader.gd")

const AUDIO_DIR: String = "res://audio/"
const BUS_NAME: String = AudioBuses.MUSIC

const TRACK_NONE: String = ""
const TRACK_MENU: String = "menu"
const TRACK_CALM: String = "calm"
const TRACK_WAVE: String = "wave"
const TRACK_LATE: String = "late"
const TRACK_GAME_OVER: String = "game_over"

## Die Spuren (je eine Datei). db: Lautstärke der Spur in dB, zum Nachstellen der Mischung.
## Die Dateien haben alle die Spitze -3 dBFS. Ihr mittlerer Pegel (aus tools/make_music.py):
## menu -18,3, calm -16,0, wave -16,6, late -20,9, game_over -17,6 dBFS. Mit den Werten hier liegt
## die Musik im Mittel bei etwa -22 dBFS (Menü, Welle, Abgesang) und -25 dBFS (Pause), die
## Zusatzspur gut 5 dB unter der Welle. Dazu kommt der Regler "Musik" (Standard 70 % = -3,1 dB).
## tools/check_mix.py rechnet nach, wie die Musik damit zu den Geräuschen steht: im Gefecht etwa
## 9 bis 11 dB unter ihnen, bei einzelnen Pistolenschüssen etwa 4 dB.
const LAYERS: Dictionary = {
	"menu": {"file": "music_menu", "db": -4.0, "loop": true},
	"calm": {"file": "music_calm", "db": -9.0, "loop": true},
	"wave": {"file": "music_wave", "db": -4.5, "loop": true},
	"late": {"file": "music_late", "db": -6.0, "loop": true},
	"game_over": {"file": "music_game_over", "db": -4.0, "loop": false},
}
## Welche Spuren bei welchem Stück zu hören sind.
const TRACK_LAYERS: Dictionary = {
	"menu": ["menu"],
	"calm": ["calm"],
	"wave": ["wave"],
	"late": ["wave", "late"],
	"game_over": ["game_over"],
}
## Diese Spuren laufen gemeinsam und im Takt in einem Abspieler.
const STEM_LAYERS: Array[String] = ["calm", "wave", "late"]
## Ab dieser Welle läuft die Zusatzspur mit.
const LATE_WAVE: int = 10
## Dauer eines Wechsels zwischen zwei Stücken in Sekunden.
const FADE_TIME: float = 1.0
## Pause, Kistenwahl, Rucksack: so viele dB leiser, Tiefpass bei so vielen Hz, Übergang in so
## vielen Sekunden.
const MUFFLE_DB: float = -6.0
const MUFFLE_CUTOFF: float = 900.0
const MUFFLE_TIME: float = 0.4
## Zurückdrängen bei lauten Ereignissen: höchstens so viele dB, so schnell hinunter und so
## langsam wieder herauf (dB je Sekunde).
const DUCK_FLOOR_DB: float = -12.0
const DUCK_ATTACK_RATE: float = 120.0
const DUCK_RELEASE_RATE: float = 14.0
## Länge des Abgesangs in Sekunden, falls seine Datei fehlt.
const GAME_OVER_LENGTH: float = 8.6
## Unter diesem Pegel gilt eine Spur als stumm.
const SILENT_DB: float = -80.0
## Größter Zeitschritt in Sekunden: Nach einem Ruckler springt keine Blende.
const MAX_STEP: float = 0.1

## false: kein Abspieler startet, die Logik läuft trotzdem (headless der Standard, siehe sfx.gd).
## sfx.gd setzt den Wert vor dem Einhängen.
var playback_enabled: bool = DisplayServer.get_name() != "headless"

## Geladene Spuren (Name der Spur -> AudioStream). Was fehlt, steht hier nicht.
var _streams: Dictionary = {}
## Stand der Blende je Spur: 0 = aus, 1 = voll.
var _gains: Dictionary = {}
## Das Stück, das gerade läuft oder eingeblendet wird.
var _track: String = TRACK_NONE
var _in_wave: bool = false
var _wave: int = 0
## Restzeit des Abgesangs in Sekunden und ob er schon zu Ende ist.
var _over_left: float = 0.0
var _over_done: bool = false
## Der Abgesang soll beim nächsten Schritt von vorn starten.
var _over_restart: bool = false
## Stand der Dämpfung: 0 = offen, 1 = ganz gedämpft.
var _muffle: float = 0.0
## Zurückdrängen: aktueller Wert, Ziel und Restzeit, in der das Ziel gilt.
var _duck_db: float = 0.0
var _duck_goal_db: float = 0.0
var _duck_hold: float = 0.0
var _last_msec: int = 0
var _stem_player: AudioStreamPlayer
var _menu_player: AudioStreamPlayer
var _over_player: AudioStreamPlayer
## Die Spielmusik als ein Stück aus mehreren Spuren und die Stelle jeder Spur darin.
var _stem_stream: AudioStreamSynchronized
var _stem_index: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure()
	_load_layers()
	_build_players()
	for layer: String in LAYERS:
		_gains[layer] = 0.0
	Events.run_started.connect(_on_run_started)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_cleared.connect(_on_wave_cleared)
	Events.game_over.connect(_on_game_over)
	_last_msec = Time.get_ticks_msec()
	# Ein neuer Knoten (Neustart der Szene) beginnt offen und ungedrängt.
	AudioBuses.set_music_cutoff(AudioBuses.MUSIC_OPEN_CUTOFF)
	_refresh_track()
	_apply()


func _exit_tree() -> void:
	AudioBuses.set_music_cutoff(AudioBuses.MUSIC_OPEN_CUTOFF)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var real_delta: float = float(now - _last_msec) / 1000.0
	_last_msec = now
	advance(minf(real_delta, MAX_STEP))


# --- Öffentliche Schnittstelle ----------------------------------------------------------------

## Das Stück, das gerade läuft oder eingeblendet wird: "menu", "calm", "wave", "late",
## "game_over" oder "" (nichts).
func get_track() -> String:
	return _track


## Stand der Blende einer Spur ("menu", "calm", "wave", "late", "game_over"): 0 = aus, 1 = voll.
func get_layer_gain(layer: String) -> float:
	return float(_gains.get(layer, 0.0))


## Läuft gerade eine Blende zwischen zwei Stücken?
func is_fading() -> bool:
	var wanted: Array = TRACK_LAYERS.get(_track, [])
	for layer: String in LAYERS:
		var target: float = 1.0 if wanted.has(layer) else 0.0
		if not is_equal_approx(float(_gains[layer]), target):
			return true
	return false


## Soll die Musik gerade gedämpft sein (Pause, Kistenwahl, Rucksack)?
func is_muffled() -> bool:
	var state: int = int(Game.state)
	return state == Game.State.PAUSED or state == Game.State.CHOOSING or state == Game.State.PACKING


## Stand der Dämpfung: 0 = offen, 1 = ganz gedämpft (MUFFLE_DB leiser, Tiefpass bei MUFFLE_CUTOFF).
func get_muffle() -> float:
	return _muffle


## Um so viele dB ist die Musik gerade zurückgedrängt (0 = gar nicht, negativ = leiser).
func get_duck_db() -> float:
	return _duck_db


## Drängt die Musik für seconds Sekunden um db zurück (negativ, höchstens DUCK_FLOOR_DB), danach
## kommt sie von selbst wieder. Mehrere Aufrufe addieren sich nicht: Es gilt der tiefste Wert.
func duck(db: float, seconds: float) -> void:
	if db >= 0.0 or seconds <= 0.0:
		return
	var goal: float = maxf(db, DUCK_FLOOR_DB)
	_duck_goal_db = minf(goal, _duck_goal_db) if _duck_hold > 0.0 else goal
	_duck_hold = maxf(_duck_hold, seconds)


## Ist die Datei dieser Spur geladen?
func has_layer(layer: String) -> bool:
	return _streams.has(layer)


## Die geladene Datei einer Spur, null wenn sie fehlt.
func get_layer_stream(layer: String) -> AudioStream:
	return _streams.get(layer) as AudioStream


## Läuft gerade ein Abspieler der Musik?
func is_playing() -> bool:
	return _stem_player.playing or _menu_player.playing or _over_player.playing


## Hält alle Abspieler sofort an (Programmende, Tests). Der nächste Schritt startet sie wieder,
## solange playback_enabled gilt.
func stop_all() -> void:
	_stem_player.stop()
	_menu_player.stop()
	_over_player.stop()


## Stellt die Musik um delta Sekunden vor: wählt das Stück, bewegt die Blenden, die Dämpfung und
## das Zurückdrängen und überträgt alles auf Abspieler und Bus. _process ruft das mit echter Zeit
## auf, Tests rufen es direkt.
func advance(delta: float) -> void:
	delta = maxf(delta, 0.0)
	_refresh_track()
	if _track == TRACK_GAME_OVER:
		_over_left -= delta
		if _over_left <= 0.0:
			_over_done = true
			_refresh_track()
	var wanted: Array = TRACK_LAYERS.get(_track, [])
	for layer: String in LAYERS:
		var target: float = 1.0 if wanted.has(layer) else 0.0
		if target > 0.0 and not bool((LAYERS[layer] as Dictionary)["loop"]):
			# Ein Stück ohne Schleife beginnt mit seinem eigenen Einschwingen: sofort voll.
			_gains[layer] = 1.0
		else:
			_gains[layer] = move_toward(float(_gains[layer]), target, delta / FADE_TIME)
	_muffle = move_toward(_muffle, 1.0 if is_muffled() else 0.0, delta / MUFFLE_TIME)
	var goal: float = 0.0
	if _duck_hold > 0.0:
		_duck_hold -= delta
		goal = _duck_goal_db
	_duck_db = move_toward(_duck_db, goal, delta * (DUCK_ATTACK_RATE if goal < _duck_db else DUCK_RELEASE_RATE))
	_apply()


# --- Aufbau -------------------------------------------------------------------------------------

func _load_layers() -> void:
	for layer: String in LAYERS:
		var entry: Dictionary = LAYERS[layer]
		var stream: AudioStream = AudioLoader.load_stream(AUDIO_DIR + str(entry["file"]) + ".wav")
		if stream == null:
			continue
		if bool(entry["loop"]):
			AudioLoader.ensure_loop(stream)
		_streams[layer] = stream


func _build_players() -> void:
	_stem_player = _new_player("Stems")
	_menu_player = _new_player("Menu")
	_over_player = _new_player("GameOver")
	if _streams.has(TRACK_MENU):
		_menu_player.stream = _streams[TRACK_MENU] as AudioStream
	if _streams.has(TRACK_GAME_OVER):
		_over_player.stream = _streams[TRACK_GAME_OVER] as AudioStream
	var count: int = 0
	for layer: String in STEM_LAYERS:
		if _streams.has(layer):
			_stem_index[layer] = count
			count += 1
	if count == 0:
		return
	_stem_stream = AudioStreamSynchronized.new()
	_stem_stream.stream_count = count
	for layer: String in _stem_index:
		_stem_stream.set_sync_stream(int(_stem_index[layer]), _streams[layer] as AudioStream)
		_stem_stream.set_sync_stream_volume(int(_stem_index[layer]), SILENT_DB)
	_stem_player.stream = _stem_stream


func _new_player(player_name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = player_name
	player.bus = BUS_NAME
	player.volume_db = SILENT_DB
	add_child(player)
	return player


# --- Wahl des Stücks ----------------------------------------------------------------------------

func _wanted_track() -> String:
	var state: int = int(Game.state)
	if state == Game.State.MENU:
		return TRACK_MENU
	if state == Game.State.GAME_OVER:
		return TRACK_MENU if _over_done else TRACK_GAME_OVER
	if _in_wave:
		return TRACK_LATE if _wave >= LATE_WAVE else TRACK_WAVE
	return TRACK_CALM


func _refresh_track() -> void:
	if int(Game.state) != Game.State.GAME_OVER:
		_over_done = false
	var wanted: String = _wanted_track()
	if wanted == _track:
		return
	_track = wanted
	if wanted == TRACK_GAME_OVER:
		var stream: AudioStream = _streams.get(TRACK_GAME_OVER) as AudioStream
		_over_left = stream.get_length() if stream != null else GAME_OVER_LENGTH
		_over_restart = true


func _on_run_started() -> void:
	_in_wave = false
	_wave = 0
	_over_done = false
	_refresh_track()


func _on_wave_started(wave: int, _total_zombies: int) -> void:
	_in_wave = true
	_wave = wave
	_refresh_track()


func _on_wave_cleared(_cleared_wave: int) -> void:
	_in_wave = false
	_refresh_track()


func _on_game_over(_stats: Dictionary) -> void:
	_in_wave = false
	_refresh_track()


# --- Übertragen auf Abspieler und Bus -----------------------------------------------------------

## Lautstärke einer Spur in dB aus ihrem Tabellenwert und dem Stand ihrer Blende (gleiche Leistung:
## In der Mitte einer Überblendung sind beide Stücke 3 dB leiser, zusammen also gleich laut).
func _layer_db(layer: String) -> float:
	var gain: float = float(_gains[layer])
	if gain <= 0.001:
		return SILENT_DB
	return float((LAYERS[layer] as Dictionary)["db"]) + linear_to_db(sin(gain * PI * 0.5))


func _apply() -> void:
	# Der Tiefpass gehört zum Bus und wird auch ohne Abspieler gestellt: Grenzfrequenz zwischen
	# offen und gedämpft, in Oktaven gleichmäßig.
	var cutoff: float = AudioBuses.MUSIC_OPEN_CUTOFF * pow(MUFFLE_CUTOFF / AudioBuses.MUSIC_OPEN_CUTOFF, _muffle)
	AudioBuses.set_music_cutoff(AudioBuses.MUSIC_OPEN_CUTOFF if _muffle <= 0.0 else cutoff)
	if not playback_enabled:
		return
	var common_db: float = _duck_db + _muffle * MUFFLE_DB
	# Spielmusik: läuft, solange eine ihrer Spuren zu hören ist oder gebraucht wird.
	if _stem_stream != null:
		var stems_needed: bool = false
		var wanted: Array = TRACK_LAYERS.get(_track, [])
		for layer: String in _stem_index:
			_stem_stream.set_sync_stream_volume(int(_stem_index[layer]), _layer_db(layer))
			if float(_gains[layer]) > 0.0 or wanted.has(layer):
				stems_needed = true
		_stem_player.volume_db = common_db
		if stems_needed and not _stem_player.playing:
			_stem_player.play()
		elif not stems_needed and _stem_player.playing:
			_stem_player.stop()
	_drive(_menu_player, TRACK_MENU, common_db, false)
	var restart_over: bool = _over_restart and float(_gains[TRACK_GAME_OVER]) > 0.0
	_drive(_over_player, TRACK_GAME_OVER, common_db, restart_over)
	if restart_over:
		_over_restart = false


## Stellt einen Abspieler mit einer einzelnen Spur: startet ihn, sobald die Spur eingeblendet wird,
## und hält ihn an, wenn sie ausgeblendet ist. restart: von vorn beginnen, auch wenn er läuft.
func _drive(player: AudioStreamPlayer, layer: String, common_db: float, restart: bool) -> void:
	if player.stream == null:
		return
	var gain: float = float(_gains[layer])
	var loops: bool = bool((LAYERS[layer] as Dictionary)["loop"])
	player.volume_db = _layer_db(layer) + common_db
	if gain <= 0.0:
		if player.playing:
			player.stop()
		return
	if restart or (loops and not player.playing):
		player.play()
