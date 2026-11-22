extends Node
## Modul: Ton (scripts/game/audio).
## Spielt alle Geräusche des Spiels. main.gd legt den Knoten als Kind "Sfx" an. Der Knoten legt
## selbst die Musik an (music.gd, Kind "Music", abfragbar über die Variable music).
##
## Die Dateien liegen in res://audio (erzeugt von tools/make_sounds.py, siehe audio/LIESMICH.txt).
## Der Knoten hört auf Events und spielt dazu passende Geräusche über zwei Vorräte von Spielern:
## AudioStreamPlayer für alles, was der Spieler selbst tut oder als Oberfläche hört (Schüsse,
## Treffer, Menü, Fanfaren), und AudioStreamPlayer3D für Geräusche mit einem Ort in der Welt
## (Stöhnen, Tod eines Zombies, Explosion, Blitz, Kiste, Kameras, Minen). Sind alle Spieler eines
## Vorrats belegt, wird der älteste neu benutzt.
##
## Busse (audio_buses.gd): Geräusche mit Ort laufen über den Bus Reverb (Studio-Hall), ebenso
## Schüsse und alle Geräusche mit "room" in der Tabelle SOUNDS (Schritte, Landen). Alles andere
## läuft trocken über den Bus Sfx. Reverb mündet in Sfx, der Regler "Geräusche" gilt für beide.
##
## Varianten: Hat ein Geräusch "variants" in der Tabelle SOUNDS, gibt es so viele Dateien dazu
## (name.wav, name_2.wav, name_3.wav ...). Bei jedem Start wird eine zufällig gewählt, nie
## dieselbe wie beim letzten Mal. Gezählt wird unter dem Namen des Geräuschs.
##
## Laute Ereignisse mit "duck" in der Tabelle drängen die Musik für ihre Dauer um so viele dB
## zurück (music.duck).
##
## Der Knoten ändert nichts am Spiel und benutzt nie Game.rng: Tonhöhe, Variante und Stöhnen
## würfelt er mit dem allgemeinen Zufall (randf, randi), ein Lauf mit festem Seed bleibt also gleich.
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
##                                durchkommt. Kommt auf einen Schlag mindestens HEAVY_HIT_SHARE des
##                                höchsten Lebens durch, dazu crowd_gasp (das Publikum erschrickt)
##   player_health_changed        merkt den Anteil des Lebens für den Herzschlag
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
##   item_repaired / item_scrapped       item_repaired (Ratsche) / item_scrapped (Blech zerknüllt)
##   materials_changed            material_gain (Klimpern), wenn Material dazukommt (delta > 0)
##                                Diese drei Signale werden nur verbunden, wenn Events sie hat
##   wave_started                 wave_start
##   wave_cleared                 wave_cleared und crowd_cheer (Applaus und Jubel)
##   intermission_tick            countdown_tick in den letzten COUNTDOWN_FROM Sekunden
##   game_over                    game_over und crowd_aww (das Publikum ist enttäuscht)
##   Knöpfe (BaseButton)          ui_hover (Maus darüber), ui_click (gedrückt); Regler: ui_hover
##   Zombies in der Nähe          zombie_groan_1 bis 3, alle GROAN_GAP_MIN bis GROAN_GAP_MAX s eines,
##                                nie zweimal dasselbe hintereinander
##   Spieler läuft am Boden       step: alle STEP_STRIDE Meter ein Schritt (über Game.player:
##                                velocity und is_on_floor), also beim Sprinten schneller und dann
##                                etwas lauter. Nicht in der Luft, nicht im Ausweichsprung, nicht
##                                unter STEP_MIN_SPEED
##   Spieler landet               land, wenn er mit mindestens LAND_MIN_FALL_SPEED aufkommt, je
##                                schneller desto lauter
##   Leben unter HEARTBEAT_SHARE  heartbeat, je weniger Leben desto schneller und lauter
##   laufende Sendung             crowd_murmur als leise Schleife (in jedem State außer MENU)

const Settings := preload("res://scripts/game/settings.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const AudioBuses := preload("res://scripts/game/audio/audio_buses.gd")
const AudioLoader := preload("res://scripts/game/audio/audio_loader.gd")
const Music := preload("res://scripts/game/audio/music.gd")

const AUDIO_DIR: String = "res://audio/"
const BUS_NAME: String = AudioBuses.SFX
const ROOM_BUS: String = AudioBuses.REVERB
const MASTER_BUS: String = AudioBuses.MASTER
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
## Schritte: Weg in Metern zwischen zwei Schritten. Passt zum Wippen der Kamera in player.gd (ein
## Auf und Ab je PI / BOB_FREQUENCY = 1,8 m): Gehen (5 m/s) ergibt 2,8 Schritte je Sekunde,
## Sprinten (7 m/s) 3,9. Unter STEP_MIN_SPEED (m/s) gibt es keine Schritte. Über STEP_SPRINT_SPEED
## sind sie um STEP_SPRINT_DB lauter. Nach dem Stehen kommt der erste Schritt nach
## STEP_FIRST_SHARE des Wegs.
const STEP_STRIDE: float = 1.8
const STEP_MIN_SPEED: float = 1.5
const STEP_SPRINT_SPEED: float = 6.0
const STEP_SPRINT_DB: float = 2.0
const STEP_FIRST_SHARE: float = 0.6
## Landen: ab dieser Fallgeschwindigkeit (m/s) ist es zu hören (ein Sprung auf ebenem Boden landet
## mit 4,5 m/s), bei LAND_FULL_FALL_SPEED mit voller Lautstärke, an der Schwelle um LAND_SOFT_DB leiser.
const LAND_MIN_FALL_SPEED: float = 2.0
const LAND_FULL_FALL_SPEED: float = 7.0
const LAND_SOFT_DB: float = -10.0
## Herzschlag: unter diesem Anteil des höchsten Lebens. Abstand zweier Schläge in Sekunden an der
## Schwelle (SLOW) und kurz vor dem Tod (FAST), an der Schwelle um HEARTBEAT_SOFT_DB leiser.
const HEARTBEAT_SHARE: float = 0.3
const HEARTBEAT_SLOW: float = 0.95
const HEARTBEAT_FAST: float = 0.55
const HEARTBEAT_SOFT_DB: float = -6.0
## Schwerer Treffer: Kommt auf einen Schlag mindestens dieser Anteil des höchsten Lebens durch,
## erschrickt das Publikum (ein Elite-Zombie trifft mit 35 von 100).
const HEAVY_HIT_SHARE: float = 0.3
## Leben des Spielers, solange noch kein player_health_changed kam.
const DEFAULT_MAX_HP: float = 100.0
## Raunen des Publikums: Datei, Lautstärke in dB und Dauer des Ein- und Ausblendens in Sekunden.
## Die Datei hat im Mittel -17,7 dBFS: Mit -20 dB liegt das Raunen bei etwa -38 dBFS, gut 10 dB
## unter der ruhigen Musik. Es soll den Raum füllen, ohne dass man hinhört.
const AMBIENCE_FILE: String = "crowd_murmur"
const AMBIENCE_DB: float = -20.0
const AMBIENCE_FADE_TIME: float = 1.5
## Größter Zeitschritt für das Blenden in Sekunden.
const MAX_STEP: float = 0.1

## Alle Geräusche: Name = Dateiname ohne Endung.
## db: Grundlautstärke in dB. pitch: Streuung der Tonhöhe (0.05 = 5 % nach oben und unten).
## gap: Mindestabstand in Sekunden zwischen zwei Starts desselben Geräuschs (0 = jeder Start zählt).
## variants (wenn vorhanden): Zahl der Dateien (name, name_2, name_3 ...), sonst 1.
## room (wenn vorhanden und true): läuft auch ohne Ort über den Hall-Bus. Schüsse (shot_...) tun
##   das immer.
## duck (wenn vorhanden): drängt die Musik für die Dauer des Geräuschs um so viele dB zurück.
const SOUNDS: Dictionary = {
	"shot_pistol": {"db": -5.0, "pitch": 0.05, "gap": 0.0, "variants": 3},
	"shot_revolver": {"db": -3.0, "pitch": 0.04, "gap": 0.0},
	"shot_smg": {"db": -7.0, "pitch": 0.06, "gap": 0.0, "variants": 3},
	"shot_sawed_off": {"db": -2.0, "pitch": 0.05, "gap": 0.0},
	"shot_shotgun": {"db": -2.0, "pitch": 0.04, "gap": 0.0},
	"shot_rifle": {"db": -5.0, "pitch": 0.05, "gap": 0.0, "variants": 3},
	"shot_sniper": {"db": -1.0, "pitch": 0.03, "gap": 0.0},
	"shot_minigun": {"db": -9.0, "pitch": 0.07, "gap": 0.0, "variants": 3},
	"shot_rocket_launcher": {"db": -6.0, "pitch": 0.04, "gap": 0.0},
	"reload_start": {"db": -8.0, "pitch": 0.04, "gap": 0.05},
	"reload_done": {"db": -7.0, "pitch": 0.04, "gap": 0.05},
	"hit": {"db": -12.0, "pitch": 0.08, "gap": 0.05, "variants": 3},
	"headshot": {"db": -7.0, "pitch": 0.04, "gap": 0.08},
	"zombie_death": {"db": -4.0, "pitch": 0.12, "gap": 0.04, "variants": 3},
	"zombie_groan_1": {"db": -6.0, "pitch": 0.12, "gap": 0.0},
	"zombie_groan_2": {"db": -6.0, "pitch": 0.12, "gap": 0.0},
	"zombie_groan_3": {"db": -6.0, "pitch": 0.12, "gap": 0.0},
	"elite_roar": {"db": -1.0, "pitch": 0.05, "gap": 0.5, "duck": -5.0},
	"player_hurt": {"db": -4.0, "pitch": 0.06, "gap": 0.1},
	"shield_hit": {"db": -6.0, "pitch": 0.05, "gap": 0.08},
	"shield_recharge": {"db": -14.0, "pitch": 0.0, "gap": 0.5},
	"dash": {"db": -6.0, "pitch": 0.06, "gap": 0.0},
	"chest_drop": {"db": -3.0, "pitch": 0.05, "gap": 0.1},
	"chest_open": {"db": -6.0, "pitch": 0.0, "gap": 0.1},
	"card_chosen": {"db": -8.0, "pitch": 0.03, "gap": 0.05},
	"upgrade": {"db": -7.0, "pitch": 0.0, "gap": 0.25},
	"synergy": {"db": -5.0, "pitch": 0.0, "gap": 0.5, "duck": -4.0},
	"backpack_open": {"db": -8.0, "pitch": 0.03, "gap": 0.1},
	"backpack_close": {"db": -8.0, "pitch": 0.03, "gap": 0.1},
	"item_sold": {"db": -8.0, "pitch": 0.03, "gap": 0.06},
	"purchase": {"db": -6.0, "pitch": 0.02, "gap": 0.06},
	"wave_start": {"db": -5.0, "pitch": 0.0, "gap": 0.5, "duck": -6.0},
	"wave_cleared": {"db": -6.0, "pitch": 0.0, "gap": 0.5, "duck": -6.0},
	"countdown_tick": {"db": -14.0, "pitch": 0.0, "gap": 0.2},
	"game_over": {"db": -4.0, "pitch": 0.0, "gap": 1.0, "duck": -8.0},
	"ui_hover": {"db": -20.0, "pitch": 0.03, "gap": 0.04},
	"ui_click": {"db": -13.0, "pitch": 0.03, "gap": 0.03},
	"explosion": {"db": -1.0, "pitch": 0.1, "gap": 0.07, "variants": 3, "duck": -5.0},
	"lightning": {"db": -7.0, "pitch": 0.12, "gap": 0.06},
	# Der Abstand hält viele Drohnen im Zaum: höchstens zwölf Schüsse je Sekunde sind zu hören.
	"drone_shot": {"db": -10.0, "pitch": 0.08, "gap": 0.08},
	# --- Ausbau 3: Schüsse der neuen Waffen ---
	"shot_burst_pistol": {"db": -6.0, "pitch": 0.05, "gap": 0.0, "variants": 3},
	"shot_nail_gun": {"db": -8.0, "pitch": 0.06, "gap": 0.0, "variants": 3},
	"shot_machine_pistol": {"db": -9.0, "pitch": 0.07, "gap": 0.0, "variants": 3},
	"shot_crossbow": {"db": -5.0, "pitch": 0.04, "gap": 0.0},
	"shot_grenade_launcher": {"db": -4.0, "pitch": 0.05, "gap": 0.0},
	# Dauerfeuer als überlappende Stücke (siehe STREAM_GAP). Drei Stücke zusammen sind etwa 4 dB
	# lauter als eines, deshalb die niedrige Grundlautstärke. Die Streuung der Tonhöhe macht beim
	# Fauchen jedes Stück etwas anders, sonst wiederholt sich dasselbe Rauschen im Takt der Starts.
	# Der Summton bleibt ohne Streuung, damit er nicht eiert.
	"shot_flamethrower": {"db": -13.0, "pitch": 0.1, "gap": STREAM_GAP},
	"shot_beam": {"db": -15.0, "pitch": 0.0, "gap": STREAM_GAP},
	"shot_tesla": {"db": -5.0, "pitch": 0.08, "gap": 0.0},
	"shot_lmg": {"db": -8.0, "pitch": 0.06, "gap": 0.0, "variants": 3},
	"shot_auto_shotgun": {"db": -4.0, "pitch": 0.05, "gap": 0.0, "variants": 3},
	# --- Ausbau 3: Kameras (leise, mit Abstand: Zehn Kameras sollen nicht nerven) ---
	"cam_tele": {"db": -8.0, "pitch": 0.05, "gap": 0.12},
	"cam_flash": {"db": -9.0, "pitch": 0.06, "gap": 0.15},
	"cam_slow": {"db": -11.0, "pitch": 0.06, "gap": 0.2},
	"cam_director": {"db": -17.0, "pitch": 0.02, "gap": 0.25},
	# --- Ausbau 3: Gegenstände und Fortschritt ---
	"mine_placed": {"db": -12.0, "pitch": 0.05, "gap": 0.1},
	"mine_triggered": {"db": -12.0, "pitch": 0.0, "gap": 0.1},
	"player_revived": {"db": -4.0, "pitch": 0.0, "gap": 1.0, "duck": -7.0},
	"pack_unlocked": {"db": -6.0, "pitch": 0.0, "gap": 0.5, "duck": -6.0},
	"bank_coins": {"db": -7.0, "pitch": 0.0, "gap": 1.0},
	"ricochet": {"db": -14.0, "pitch": 0.1, "gap": 0.08},
	"thorns": {"db": -9.0, "pitch": 0.08, "gap": 0.1},
	# --- Ausbau 4: Spieler (leise: Schritte sollen den Raum füllen, nicht stören). Ohne
	# Mindestabstand: Den Takt geben Weg (STEP_STRIDE) und Leben (HEARTBEAT_...) vor. ---
	"step": {"db": -15.0, "pitch": 0.06, "gap": 0.0, "variants": 4, "room": true},
	"land": {"db": -8.0, "pitch": 0.05, "gap": 0.0, "room": true},
	"heartbeat": {"db": -7.0, "pitch": 0.0, "gap": 0.0},
	# --- Ausbau 4: Publikum ---
	"crowd_cheer": {"db": -9.0, "pitch": 0.04, "gap": 1.0},
	"crowd_gasp": {"db": -8.0, "pitch": 0.05, "gap": 2.5},
	"crowd_aww": {"db": -7.0, "pitch": 0.03, "gap": 2.0},
	# --- Ausbau 4: Material ---
	"item_repaired": {"db": -9.0, "pitch": 0.03, "gap": 0.08},
	"item_scrapped": {"db": -8.0, "pitch": 0.06, "gap": 0.08},
	"material_gain": {"db": -15.0, "pitch": 0.06, "gap": 0.12},
}

## false: Geräusche werden nur gezählt (get_play_count), kein Spieler startet. Headless (Tests)
## ist das der Standard: Dort endet das Programm oft mitten in einem Geräusch, und Godot meldet
## dann verlorene Objekte ("ObjectDB instances leaked", "resources still in use"), womit ein Test
## als fehlgeschlagen gilt. Wer die Spieler headless prüfen will (tests/test_audio.gd), setzt true
## und wartet vor dem Ende, bis alles verklungen ist. Der Wert gilt auch für die Musik: Er wird ihr
## beim Start übergeben.
var playback_enabled: bool = DisplayServer.get_name() != "headless"
## Die Musik (Kind "Music"), angelegt in _ready.
var music: Music

## Geladene Geräusche (Name -> AudioStream, die erste Variante). Was fehlt, steht hier nicht.
var _streams: Dictionary = {}
## Alle geladenen Varianten je Geräusch (Name -> Array von AudioStream, mindestens eine).
var _variants: Dictionary = {}
## Stelle der zuletzt gespielten Variante je Geräusch (Name -> int).
var _last_variant: Dictionary = {}
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
var _last_groan: String = ""
## Letzter bekannter Punktestand, -1 = noch keiner in diesem Lauf.
var _points: int = -1
var _shield: float = 0.0
var _shield_rising: bool = false
var _last_state: int = -1
## Zeitpunkt (Millisekunden) des letzten Treffer-Geräuschs von Flammenwerfer oder Strahl.
var _stream_hit_at: int = -STREAM_HIT_GAP_MSEC
## Schritte: Weg seit dem letzten Schritt in Metern, Boden im letzten Bild, letzte Fallgeschwindigkeit.
var _step_distance: float = STEP_STRIDE * STEP_FIRST_SHARE
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
## Leben des Spielers: Anteil (0 bis 1) und Höchstwert, aus player_health_changed.
var _hp_share: float = 1.0
var _max_hp: float = DEFAULT_MAX_HP
## Sekunden bis zum nächsten Herzschlag.
var _heart_left: float = 0.0
## Raunen des Publikums: eigener Spieler und Stand der Blende (0 = aus, 1 = voll).
var _ambience_player: AudioStreamPlayer
var _ambience_gain: float = 0.0
var _last_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Die gespeicherten Lautstärken gelten ab dem Start. apply_audio legt auch die Busse an.
	Settings.ensure_loaded()
	Settings.apply_audio()
	_build_pools()
	_load_sounds()
	_build_ambience()
	music = Music.new()
	music.name = "Music"
	music.playback_enabled = playback_enabled
	add_child(music)
	_groan_left = randf_range(GROAN_GAP_MIN, GROAN_GAP_MAX)
	_last_state = int(Game.state)
	_last_msec = Time.get_ticks_msec()
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
## Musik und Raunen laufen fast immer: Auch sie gelten als laufendes Geräusch.
func _exit_tree() -> void:
	var loops_running: bool = _loops_playing()
	if (Time.get_ticks_msec() >= _busy_until and not loops_running) or (Game.state == Game.State.MENU and not _closing):
		return
	_busy_until = 0
	stop_all()
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
		_tick_movement(delta)
		_tick_heartbeat(delta)
	# Das Raunen blendet in echter Zeit, auch bei pausiertem Baum und in der Zeitlupe.
	var now: int = Time.get_ticks_msec()
	var real_delta: float = float(now - _last_msec) / 1000.0
	_last_msec = now
	_tick_ambience(minf(real_delta, MAX_STEP))


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


## Wie oft das Geräusch gestartet wurde, seit es diesen Knoten gibt (ausgelassene Starts zählen
## nicht). Alle Varianten zählen unter dem Namen des Geräuschs.
func get_play_count(sound_id: String) -> int:
	return int(_play_counts.get(sound_id, 0))


## Namen aller Geräusche, die das Spiel kennt (auch die, deren Datei fehlt), sortiert. Varianten
## haben keinen eigenen Namen.
func sound_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in SOUNDS:
		ids.append(id)
	ids.sort()
	return ids


## Zahl der geladenen Varianten eines Geräuschs (0, wenn es nicht geladen ist).
func get_variant_count(sound_id: String) -> int:
	return (_variants[sound_id] as Array).size() if _variants.has(sound_id) else 0


## Stelle der zuletzt gespielten Variante (0 = name.wav, 1 = name_2.wav ...), -1 vor dem ersten Start.
func get_last_variant(sound_id: String) -> int:
	return int(_last_variant.get(sound_id, -1))


## Soll das Raunen des Publikums gerade zu hören sein? In jedem State außer MENU.
func is_ambience_wanted() -> bool:
	return int(Game.state) != Game.State.MENU


## Stand der Blende des Raunens: 0 = aus, 1 = voll.
func get_ambience_gain() -> float:
	return _ambience_gain


## Hält alle Spieler sofort an, auch Musik und Raunen (Programmende, Tests). Solange
## playback_enabled gilt, starten Musik und Raunen im nächsten Bild wieder.
func stop_all() -> void:
	for player: AudioStreamPlayer in _players:
		player.stop()
	for player_3d: AudioStreamPlayer3D in _players_3d:
		player_3d.stop()
	if _ambience_player != null:
		_ambience_player.stop()
	if is_instance_valid(music):
		music.stop_all()


# --- Aufbau -------------------------------------------------------------------------------------

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
		player_3d.bus = ROOM_BUS
		player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player_3d.unit_size = UNIT_SIZE_3D
		player_3d.max_distance = MAX_DISTANCE_3D
		add_child(player_3d)
		_players_3d.append(player_3d)
		_order_3d.append(0)


func _load_sounds() -> void:
	for id: String in SOUNDS:
		var total: int = int((SOUNDS[id] as Dictionary).get("variants", 1))
		var loaded: Array[AudioStream] = []
		for index: int in total:
			var stream: AudioStream = _load_stream(AUDIO_DIR + variant_file(id, index) + ".wav")
			if stream != null:
				loaded.append(stream)
		if not loaded.is_empty():
			_variants[id] = loaded
			_streams[id] = loaded[0]


## Dateiname (ohne Endung) der Variante mit dieser Stelle: Die erste heißt wie das Geräusch, die
## weiteren name_2, name_3 ...
static func variant_file(sound_id: String, index: int) -> String:
	return sound_id if index <= 0 else "%s_%d" % [sound_id, index + 1]


## Der Spieler für das Raunen des Publikums (eine Schleife, kein Geräusch aus der Tabelle).
func _build_ambience() -> void:
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "Ambience"
	_ambience_player.bus = BUS_NAME
	_ambience_player.volume_db = -80.0
	add_child(_ambience_player)
	var stream: AudioStream = _load_stream(AUDIO_DIR + AMBIENCE_FILE + ".wav")
	if stream != null:
		AudioLoader.ensure_loop(stream)
		_ambience_player.stream = stream


## Lädt eine Tondatei, ohne je eine Fehlermeldung auszulösen (siehe audio_loader.gd).
func _load_stream(path: String) -> AudioStream:
	return AudioLoader.load_stream(path)


func _is_imported(path: String) -> bool:
	return AudioLoader.is_imported(path)


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
	Events.player_health_changed.connect(_on_player_health_changed)
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
	# Material (Abschnitt 26): nur verbinden, wenn Events die Signale schon hat.
	if Events.has_signal("item_repaired"):
		Events.connect("item_repaired", _on_item_repaired)
	if Events.has_signal("item_scrapped"):
		Events.connect("item_scrapped", _on_item_scrapped)
	if Events.has_signal("materials_changed"):
		Events.connect("materials_changed", _on_materials_changed)


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
	player.bus = ROOM_BUS if _uses_room(sound_id) else BUS_NAME
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
## zählt den Start, wählt die Variante, drängt bei lauten Ereignissen die Musik zurück und gibt
## die Tondatei zurück. null = nicht spielen.
func _claim(sound_id: String) -> AudioStream:
	if not _variants.has(sound_id) or not is_inside_tree() or _players.is_empty():
		return null
	var entry: Dictionary = SOUNDS[sound_id]
	var now: int = Time.get_ticks_msec()
	var gap_msec: int = roundi(float(entry["gap"]) * 1000.0)
	if gap_msec > 0 and _last_start.has(sound_id) and now - int(_last_start[sound_id]) < gap_msec:
		return null
	_last_start[sound_id] = now
	_play_counts[sound_id] = int(_play_counts.get(sound_id, 0)) + 1
	var stream: AudioStream = _pick_variant(sound_id)
	if entry.has("duck") and is_instance_valid(music):
		music.duck(float(entry["duck"]), stream.get_length())
	return stream


## Wählt eine Variante des Geräuschs: zufällig, aber nie dieselbe wie beim letzten Mal.
func _pick_variant(sound_id: String) -> AudioStream:
	var loaded: Array = _variants[sound_id]
	var total: int = loaded.size()
	var pick: int = 0
	if total > 1:
		var last: int = int(_last_variant.get(sound_id, -1))
		# Nach der letzten Variante eine bis total - 1 Stellen weiter: jede andere gleich wahrscheinlich.
		pick = randi() % total if last < 0 else (last + 1 + randi() % (total - 1)) % total
	_last_variant[sound_id] = pick
	return loaded[pick] as AudioStream


## Läuft das Geräusch auch ohne Ort über den Hall-Bus? Schüsse immer, sonst nach der Tabelle.
func _uses_room(sound_id: String) -> bool:
	return sound_id.begins_with(SHOT_PREFIX) or bool((SOUNDS[sound_id] as Dictionary).get("room", false))


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


## Laufen gerade Musik oder Raunen?
func _loops_playing() -> bool:
	if _ambience_player != null and _ambience_player.playing:
		return true
	return is_instance_valid(music) and music.is_playing()


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
	play_at(_next_groan(), near[randi() % near.size()])


## Eines der Stöhn-Geräusche, nie dasselbe wie beim letzten Mal.
func _next_groan() -> String:
	var choices: Array[String] = []
	for id: String in GROAN_IDS:
		if id != _last_groan and has_sound(id):
			choices.append(id)
	if choices.is_empty():
		return GROAN_IDS[0]
	_last_groan = choices[randi() % choices.size()]
	return _last_groan


# --- Schritte, Landen, Herzschlag, Raunen -------------------------------------------------------

## Schritte und Landen des Spielers. Liest nur Game.player (velocity, is_on_floor, is_dashing,
## is_dead), ändert dort nichts.
func _tick_movement(delta: float) -> void:
	var player: Node3D = Game.player if is_instance_valid(Game.player) else null
	if player == null or not player.is_inside_tree() or not player.has_method("is_on_floor"):
		_was_on_floor = true
		_fall_speed = 0.0
		return
	var velocity_value: Variant = player.get("velocity")
	if typeof(velocity_value) != TYPE_VECTOR3 or player.get("is_dead") == true:
		return
	var velocity: Vector3 = velocity_value
	var on_floor: bool = bool(player.call("is_on_floor"))
	if not on_floor:
		# In der Luft: Die letzte Fallgeschwindigkeit entscheidet beim Aufkommen über das Landen.
		_fall_speed = maxf(0.0, -velocity.y)
		_was_on_floor = false
		return
	if not _was_on_floor:
		_was_on_floor = true
		if _fall_speed >= LAND_MIN_FALL_SPEED:
			var force: float = clampf(inverse_lerp(LAND_MIN_FALL_SPEED, LAND_FULL_FALL_SPEED, _fall_speed), 0.0, 1.0)
			play("land", lerpf(LAND_SOFT_DB, 0.0, force))
			# Das Landen ist selbst ein Schritt: Der nächste kommt erst nach einem ganzen Weg.
			_step_distance = 0.0
		_fall_speed = 0.0
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var dashing: bool = player.has_method("is_dashing") and bool(player.call("is_dashing"))
	if dashing:
		return
	if speed < STEP_MIN_SPEED:
		# Stehen: Der erste Schritt nach dem Loslaufen kommt bald.
		_step_distance = maxf(_step_distance, STEP_STRIDE * STEP_FIRST_SHARE)
		return
	_step_distance += speed * delta
	if _step_distance >= STEP_STRIDE:
		_step_distance = fmod(_step_distance, STEP_STRIDE)
		play("step", STEP_SPRINT_DB if speed >= STEP_SPRINT_SPEED else 0.0)


## Herzschlag bei wenig Leben: je weniger, desto schneller und lauter.
func _tick_heartbeat(delta: float) -> void:
	if _hp_share <= 0.0 or _hp_share >= HEARTBEAT_SHARE:
		_heart_left = 0.0
		return
	_heart_left -= delta
	if _heart_left > 0.0:
		return
	# 0 an der Schwelle, 1 kurz vor dem Tod.
	var urgency: float = 1.0 - _hp_share / HEARTBEAT_SHARE
	_heart_left = lerpf(HEARTBEAT_SLOW, HEARTBEAT_FAST, urgency)
	play("heartbeat", lerpf(HEARTBEAT_SOFT_DB, 0.0, urgency))


## Blendet das Raunen des Publikums ein und aus.
func _tick_ambience(delta: float) -> void:
	_ambience_gain = move_toward(_ambience_gain, 1.0 if is_ambience_wanted() else 0.0, delta / AMBIENCE_FADE_TIME)
	if not playback_enabled or _ambience_player == null or _ambience_player.stream == null:
		return
	if _ambience_gain <= 0.0:
		if _ambience_player.playing:
			_ambience_player.stop()
		return
	_ambience_player.volume_db = AMBIENCE_DB + linear_to_db(_ambience_gain)
	if not _ambience_player.playing:
		_ambience_player.play()


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
	_step_distance = STEP_STRIDE * STEP_FIRST_SHARE
	_was_on_floor = true
	_fall_speed = 0.0
	_hp_share = 1.0
	_heart_left = 0.0


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
## tut weh. Ein schwerer Treffer lässt das Publikum erschrecken.
func _on_player_damaged(amount: float) -> void:
	if _shield > 0.0:
		play("shield_hit")
	if amount > _shield:
		play("player_hurt")
		if amount - _shield >= HEAVY_HIT_SHARE * _max_hp:
			play("crowd_gasp")


func _on_player_health_changed(hp: float, max_hp: float) -> void:
	if max_hp > 0.0:
		_max_hp = max_hp
		_hp_share = clampf(hp / max_hp, 0.0, 1.0)


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


func _on_item_repaired(_uid: int) -> void:
	play("item_repaired")


func _on_item_scrapped(_uid: int, _amount: int) -> void:
	play("item_scrapped")


## Nur dazugekommenes Material klimpert (Wellen-Prämie, Verschrotten). Ausgaben (Reparieren) und
## der Stand am Laufbeginn (delta 0) sind stumm.
func _on_materials_changed(_total: int, delta: int) -> void:
	if delta > 0:
		play("material_gain")


func _on_wave_started(_wave: int, _total_zombies: int) -> void:
	play("wave_start")


func _on_wave_cleared(_wave: int) -> void:
	play("wave_cleared")
	play("crowd_cheer")


func _on_intermission_tick(seconds_left: int) -> void:
	if seconds_left >= 1 and seconds_left <= COUNTDOWN_FROM:
		play("countdown_tick")


func _on_game_over(_stats: Dictionary) -> void:
	play("game_over")
	play("crowd_aww")
