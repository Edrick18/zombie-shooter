extends Node
## Modul: Upgrades (scripts/game/upgrades).
## Setzt die Upgrades aus Game.upgrades in Wirkung um (Abschnitt 7, Schritt 3, und Abschnitt 18):
##   bullet_hit      -> Kettenblitz ("chain_lightning", Synergie "storm_front"), Brand ("burn"),
##                      Gift ("poison"), Trockeneis ("frost"), Querschläger ("ricochet"), je Waffe
##                      über info["weapon_uid"]
##   zombie_damaged  -> Lebensraub ("lifesteal", höchstens Balance.LIFESTEAL_MAX_PER_SECOND)
##   zombie_killed   -> Trostpflaster ("kill_heal"), Konfetti-Explosion ("corpse_explosion",
##                      Kettentiefe über chain_depth)
##   reload_started, hand_reload_started
##                   -> Druckwelle ("reload_shockwave", Abklingzeit Balance.SHOCKWAVE_COOLDOWN)
##   player_damaged  -> Kaktus-Requisite ("thorns"), wirkt im nächsten Schritt
##   wave_cleared    -> Pausensnack ("snack")
##   upgrade_chosen  -> Kameras und Discokugeln abgleichen, kleiner Jubel
##   build_changed, cameras_changed
##                   -> Kameras und Discokugeln abgleichen (der Rucksack kann sie auch wegnehmen)
##   weapon_fired    -> Zähler der Blitz-Auslösungen je Schuss zurücksetzen (Gewitterfront)
##   run_started     -> Abklingzeiten und Störsender zurück, wartende Explosionen und Minen weg,
##                      Kameras und Discokugeln neu aufbauen
##   tick (je Physik-Schritt)
##                   -> Discokugeln kreisen und treffen ("disco_ball"), Störsender ("jammer"),
##                      Requisitenbombe ("mine": legen, auslösen), Kaktus-Requisite
##
## Nur source "bullet" löst Kettenblitz, Brand und Gift aus. Maximal-Leben und Tempo setzt der
## Spieler selbst (player.refresh_stats), Punkte und Kistenglück liest Game bzw. ChestDropper.
## Feste Schadenswerte mal Game.effect_factor().
##
## Mehrfache Wirkung (Abschnitt 18): Jedes eingeräumte Exemplar zählt.
##   Kugel-Effekte (Kettenblitz, Brand, Gift) gelten je Waffe: Game.bullet_value(weapon_uid, id, key)
##   verbindet die allgemein gesetzten Exemplare mit den Stern-Gegenständen dieser Waffe, ob der
##   Effekt für die Waffe überhaupt wirkt, sagt Game.bullet_level(weapon_uid, id) > 0. Fehlt
##   weapon_uid im Treffer, gilt -1: Dann zählen nur die allgemeinen. Die Gewitterfront gilt nur
##   für eine Waffe, auf die alle ihre Voraussetzungen selbst wirken.
##   Alles andere (Lebensraub, Explosion, Druckwelle) liest Game.upgrades.value(id, key): Das
##   verbindet schon alle Exemplare. Game.upgrades.get_level(id) dient hier nur als Ja oder Nein.
##   Kameras (Abschnitt 22.1): Game.cameras nennt jede Kamera mit ihren fertigen Werten. Für
##   jeden Eintrag gibt es genau einen Knoten, der seine Werte aus dem Eintrag liest (set_stats):
##   die Drohnen (drones, drone.gd) und die vier anderen Typen (camera_nodes(id), Skripte aus
##   CAMERA_SCRIPTS). Alle zusammen stehen in cameras, in der Reihenfolge ihrer Plätze um den
##   Spieler: erst die Drohnen, dann Tele, Blitzlicht, Zeitlupe, Regie. Die Einträge werden neu
##   zugeteilt, sobald Game.cameras ersetzt wurde (Events.cameras_changed).
##   Discokugeln: Game.upgrades.copies("disco_ball") nennt die Rarität jedes Exemplars (disco_balls).
##
## Abschnitt 19:
##   Gift (Kantinenessen): Ein Kugeltreffer vergiftet den Zombie für Balance.POISON_DURATION
##   Sekunden mit Game.bullet_value(weapon_uid, "poison", "dps") mal Effekt-Faktor je Sekunde. Das
##   Gift tickt im Zombie (zombie.apply_poison, source "poison"), unabhängig vom Brand.
##   Trostpflaster: Jeder Kill, gleich welche Quelle, heilt Game.upgrades.value("kill_heal", "heal").
##   Discokugel: je Exemplar ein Knoten aus disco_ball.gd. Alle teilen einen Grundwinkel, der hier
##   je Schritt weiterläuft, und stehen gleichmäßig über den Kreis verteilt.
##   Störsender: Alle Balance.JAMMER_INTERVAL Sekunden ein Schlag auf alle Zombies im Umkreis
##   "radius" um den Spieler (source "jammer"). Die Uhr läuft nur im State PLAYING. Ist niemand
##   im Umkreis, wartet der fällige Schlag und löst aus, sobald ein Zombie hineinkommt.
##
## Abschnitt 22.3:
##   Trockeneis: Ein Kugeltreffer verlangsamt den Zombie für Balance.FROST_DURATION Sekunden um
##   Game.bullet_value(weapon_uid, "frost", "slow") (zombie.apply_slow, Elite halb).
##   Querschläger: Mit Game.bullet_value(weapon_uid, "ricochet", "chance") aus Game.rng springt
##   der Treffer auf den nächsten anderen Zombie im Umkreis Balance.RICOCHET_RADIUS, mit
##   RICOCHET_DAMAGE_FACTOR des Kugelschadens (source "ricochet"). Er kommt nicht als bullet_hit
##   und löst deshalb selbst nichts weiter aus.
##   Kaktus-Requisite: Nach player_damaged nehmen alle Zombies im Umkreis Balance.THORNS_RADIUS um
##   den Spieler Schaden (source "thorns"). Das wirkt im nächsten Schritt und nicht im Signal:
##   Sonst könnte ein Kill daraus (Trostpflaster, Lebensraub) den Spieler mitten in seinem
##   Treffer heilen, bevor sein Tod festgestellt ist.
##   Pausensnack: wave_cleared heilt Game.upgrades.value("snack", "heal").
##   Requisitenbombe: Alle "interval" Sekunden (kürzester Wert) legt der Spieler eine Mine an
##   seine Füße (mine.gd, Liste mines, Events.mine_placed), höchstens Balance.MINE_MAX_ACTIVE
##   zugleich und nie näher als MINE_MIN_SPACING an eine liegende. Ist kein Platz, wartet die
##   fällige Mine. Die Uhr läuft nur im State PLAYING. Kommt ein Zombie einer scharfen Mine auf
##   Balance.MINE_TRIGGER_RADIUS nahe, kommt Events.mine_triggered und sie explodiert: Schaden
##   "damage" (Summe aller Exemplare beim Legen) mal Effekt-Faktor an allen Zombies im Umkreis
##   Balance.MINE_RADIUS mit freier Sicht (source "mine"), dazu Events.explosion.
##
## Was "je Schuss" heißt (Obergrenze der Gewitterfront): Die Waffe meldet erst alle Treffer
## eines Schusses (bullet_hit) und danach weapon_fired. Der Zähler beginnt deshalb bei jedem
## weapon_fired neu und zusätzlich, sobald ein Treffer in einem späteren Bild eintrifft als
## der vorige. So gilt die Grenze je Schuss, egal ob weapon_fired vor oder nach den Treffern
## kommt, und auch für alle Kugeln einer Schrotladung zusammen.
##
## Explosionen laufen nie innerhalb von zombie_killed: Sie werden vorgemerkt und im nächsten
## Physik-Schritt (Folgeexplosionen nach Balance.EXPLOSION_CHAIN_DELAY) ausgeführt.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")
const Drone := preload("res://scripts/game/upgrades/drone.gd")
const DiscoBall := preload("res://scripts/game/upgrades/disco_ball.gd")
const Mine := preload("res://scripts/game/upgrades/mine.gd")
const UpgradeFx := preload("res://scripts/game/upgrades/upgrade_fx.gd")
const CamTele := preload("res://scripts/game/upgrades/cam_tele.gd")
const CamFlash := preload("res://scripts/game/upgrades/cam_flash.gd")
const CamSlow := preload("res://scripts/game/upgrades/cam_slow.gd")
const CamDirector := preload("res://scripts/game/upgrades/cam_director.gd")

## Kameratypen neben der Drohne, in der Reihenfolge ihrer Plätze (nach den Drohnen), und ihr Skript.
const CAMERA_IDS: Array[String] = ["cam_tele", "cam_flash", "cam_slow", "cam_director"]
const CAMERA_SCRIPTS: Dictionary = {
	"cam_tele": CamTele, "cam_flash": CamFlash, "cam_slow": CamSlow, "cam_director": CamDirector,
}
## Requisitenbombe: So weit muss eine neue Mine von jeder liegenden entfernt sein (Meter). Wer
## stehen bleibt, stapelt also keine Minen auf einem Fleck.
const MINE_MIN_SPACING: float = 1.0
## Höhe über dem Boden, von der die Explosion einer Mine ausgeht (Sichtlinie zu den Zombies).
const MINE_BLAST_HEIGHT: float = 0.4
## So tief unter den Füßen des Spielers wird der Boden für eine Mine gesucht (Meter).
const MINE_DROP_DEPTH: float = 6.0
## Requisitenbombe: Wert der Uhr, solange der Gegenstand nicht wirkt (wer ihn einräumt, wartet
## einen vollen Abstand).
const MINE_IDLE: float = -1.0

# --- Reine Optik-Zahlen ---
## Trefferzahlen für Schaden aus Upgrades (Blitz, Explosion, Druckwelle, Drohne).
const SHOW_DAMAGE_NUMBERS: bool = true
## Trefferzahlen für Kugeltreffer. UpgradeEffects ist die einzige Stelle, die Trefferzahlen
## zeigt (Waffe und Zombie zeigen keine eigenen).
const SHOW_BULLET_NUMBERS: bool = true
const BULLET_NUMBER_COLOR: Color = Color(1.0, 1.0, 1.0)
const HEADSHOT_NUMBER_COLOR: Color = Color(1.0, 0.85, 0.15)
const LIGHTNING_NUMBER_COLOR: Color = Color(0.4, 0.95, 1.0)
const EXPLOSION_NUMBER_COLOR: Color = Color(1.0, 0.55, 0.85)
const SHOCKWAVE_NUMBER_COLOR: Color = Color(0.8, 0.95, 1.0)
const JAMMER_NUMBER_COLOR: Color = Color(0.55, 0.8, 1.0)
const RICOCHET_NUMBER_COLOR: Color = Color(1.0, 0.7, 0.3)
const RICOCHET_COLOR: Color = Color(1.0, 0.92, 0.3)
const RICOCHET_WIDTH: float = 0.09
const RICOCHET_TIME: float = 0.18
const THORNS_NUMBER_COLOR: Color = Color(0.55, 1.0, 0.45)
const THORNS_COLOR: Color = Color(0.3, 0.85, 0.25)
const MINE_NUMBER_COLOR: Color = Color(1.0, 0.8, 0.3)
const MINE_COLOR: Color = Color(1.0, 0.7, 0.15)
## Höhe über den Füßen des Spielers, von der die Blitze des Störsenders ausgehen.
const JAMMER_ORIGIN_HEIGHT: float = 1.2
## Reste einer Wartezeit unter diesem Wert gelten als abgelaufen (Rundung vieler kleiner Schritte).
const TIME_EPSILON: float = 0.0001
const EXPLOSION_COLORS: Array[Color] = [
	Color(1.0, 0.25, 0.6), Color(1.0, 0.75, 0.1), Color(0.3, 0.85, 1.0), Color(0.6, 0.4, 1.0),
]

## Die erste Drohne, null solange keine Kameradrohne wirkt.
var drone: Node3D = null
## Alle Drohnen, eine je wirkendem Exemplar der Kameradrohne, in der Reihenfolge ihrer Plätze
## (drones[i] hat den Platz i). Nur lesen: _sync_cameras hält die Liste aktuell.
var drones: Array[Node3D] = []
## Alle Kamera-Knoten (Drohnen und die vier anderen Typen), einer je Eintrag aus Game.cameras, in
## der Reihenfolge ihrer Plätze um den Spieler (cameras[i] hat den Platz i): erst die Drohnen,
## dann Tele, Blitzlicht, Zeitlupe, Regie. Nur lesen: _sync_cameras hält die Liste aktuell.
var cameras: Array[Node3D] = []
## Alle Discokugeln, eine je wirkendem Exemplar, in der Reihenfolge ihrer Plätze auf dem Kreis.
## Nur lesen: _sync_disco_balls hält die Liste aktuell.
var disco_balls: Array[Node3D] = []
## Alle liegenden Minen der Requisitenbombe, die älteste zuerst. Nur lesen.
var mines: Array[Node3D] = []

var _shot_procs: int = 0
var _shot_frame: int = -1
var _lifesteal_window_left: float = 0.0
var _lifesteal_healed: float = 0.0
var _shockwave_cooldown_left: float = 0.0
## Ist seit dem letzten tick schon eine Druckwelle losgegangen? Ein Nachladen meldet sich für die
## linke Hand über zwei Signale, und beide Hände laden oft im selben Augenblick nach: Das soll
## nur eine Welle geben, auch wenn sie niemanden trifft und deshalb keine Abklingzeit beginnt.
var _shockwave_this_step: bool = false
var _shockwave_count: int = 0
## Vorgemerkte Explosionen: { "position": Vector3, "radius": float, "damage": float,
## "depth": int, "delay": float }.
var _pending_explosions: Array[Dictionary] = []
var _explosion_count: int = 0
## Das Array Game.cameras, aus dem die Kameras zuletzt ihre Werte bekommen haben.
var _camera_source: Variant = null
## Knoten der Kameratypen aus CAMERA_IDS: camera_id -> Array[Node3D].
var _camera_nodes: Dictionary = {}
## Gewünschte Raritäten je Kameratyp (camera_id -> Array[int]) und das Array Game.cameras, aus
## dem sie gelesen wurden: Game ersetzt es nur bei einer Änderung.
var _wanted_cache: Dictionary = {}
var _wanted_source: Variant = null
## Kaktus-Requisite: Der Spieler wurde getroffen, die Stacheln wirken im nächsten Schritt.
var _thorns_pending: bool = false
## Requisitenbombe: Sekunden bis zur nächsten Mine. 0 = fällig, wartet auf Platz. MINE_IDLE = der
## Gegenstand wirkt nicht.
var _mine_left: float = MINE_IDLE
## Grundwinkel aller Discokugeln auf dem Kreis um den Spieler (Radiant).
var _disco_angle: float = 0.0
## Sekunden bis zum nächsten Schlag des Störsenders. 0 = fällig, wartet auf einen Zombie im Umkreis.
var _jammer_left: float = Balance.JAMMER_INTERVAL


func _ready() -> void:
	for camera_id: String in CAMERA_IDS:
		var empty: Array[Node3D] = []
		_camera_nodes[camera_id] = empty
	Events.bullet_hit.connect(_on_bullet_hit)
	Events.zombie_damaged.connect(_on_zombie_damaged)
	Events.zombie_killed.connect(_on_zombie_killed)
	Events.reload_started.connect(_on_reload_started)
	Events.hand_reload_started.connect(_on_hand_reload_started)
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.upgrade_chosen.connect(_on_upgrade_chosen)
	# Der Rucksack kann Kameras und Discokugeln auch wieder wegnehmen oder schwächen.
	Events.build_changed.connect(_on_build_changed)
	Events.cameras_changed.connect(_sync_cameras)
	Events.player_damaged.connect(_on_player_damaged)
	Events.wave_cleared.connect(_on_wave_cleared)
	Events.synergy_unlocked.connect(_on_synergy_unlocked)
	Events.run_started.connect(_on_run_started)


func _exit_tree() -> void:
	_remove_cameras()
	_remove_disco_balls()
	_remove_mines()


func _physics_process(delta: float) -> void:
	tick(delta)


## Lässt die Zeit der Effekte vergehen: Abklingzeit der Druckwelle, Zeitfenster des Lebensraubs,
## fällige Explosionen, Abgleich der Kameras und Discokugeln mit den Exemplaren, Umlauf und
## Treffer der Discokugeln, Uhr des Störsenders, Stacheln der Kaktus-Requisite, Minen der
## Requisitenbombe. Läuft je Physik-Schritt, Tests rufen es mit einem eigenen Zeitschritt auf.
func tick(delta: float) -> void:
	_shockwave_cooldown_left = maxf(0.0, _shockwave_cooldown_left - delta)
	_shockwave_this_step = false
	_lifesteal_window_left = maxf(0.0, _lifesteal_window_left - delta)
	_sync_cameras()
	_sync_disco_balls()
	_tick_explosions(delta)
	_tick_disco_balls(delta)
	_tick_jammer(delta)
	_tick_thorns()
	_tick_mines(delta)


## Zündet die vorgemerkten Explosionen, deren Wartezeit um ist.
func _tick_explosions(delta: float) -> void:
	if _pending_explosions.is_empty():
		return
	# Erst sortieren, dann zünden: Eine Explosion kann neue vormerken.
	var due: Array[Dictionary] = []
	var waiting: Array[Dictionary] = []
	for entry: Dictionary in _pending_explosions:
		entry["delay"] = float(entry["delay"]) - delta
		if float(entry["delay"]) <= 0.0:
			due.append(entry)
		else:
			waiting.append(entry)
	_pending_explosions = waiting
	for entry: Dictionary in due:
		_explode(entry)


## Restliche Abklingzeit der Druckwelle in Sekunden (0 = bereit).
func get_shockwave_cooldown_left() -> float:
	return _shockwave_cooldown_left


## Zahl der Druckwellen in diesem Lauf, auch der Wellen, die niemanden getroffen haben.
func get_shockwave_count() -> int:
	return _shockwave_count


## Zahl der vorgemerkten, noch nicht gezündeten Explosionen.
func get_pending_explosion_count() -> int:
	return _pending_explosions.size()


## Wie viel Leben der Lebensraub im laufenden Zeitfenster noch heilen darf.
func get_lifesteal_budget_left() -> float:
	if _lifesteal_window_left <= 0.0:
		return Balance.LIFESTEAL_MAX_PER_SECOND
	return maxf(0.0, Balance.LIFESTEAL_MAX_PER_SECOND - _lifesteal_healed)


## Blitz-Auslösungen im laufenden Schuss (für die Obergrenze der Gewitterfront).
func get_lightning_procs_this_shot() -> int:
	return _shot_procs


## Sekunden bis zum nächsten Schlag des Störsenders. 0 = der Schlag ist fällig und wartet auf
## einen Zombie im Umkreis. Ohne Störsender steht hier der volle Abstand.
func get_jammer_time_left() -> float:
	return _jammer_left


## Die Knoten eines Kameratyps (CameraDefs.ORDER), in der Reihenfolge ihrer Plätze. Nur lesen.
func camera_nodes(camera_id: String) -> Array[Node3D]:
	if camera_id == Drone.CAMERA_ID:
		return drones
	if _camera_nodes.has(camera_id):
		return _camera_nodes[camera_id]
	return []


## Zahl der liegenden Minen der Requisitenbombe (höchstens Balance.MINE_MAX_ACTIVE).
func get_mine_count() -> int:
	return mines.size()


## Sekunden bis zur nächsten Mine. 0 = die Mine ist fällig und wartet auf Platz (zu viele liegen
## schon, oder eine liegt direkt unter dem Spieler). Ohne Requisitenbombe 0.
func get_mine_time_left() -> float:
	return maxf(0.0, _mine_left)


# --- Kugeltreffer: Brand, Gift, Trockeneis, Kettenblitz und Querschläger ---

func _on_bullet_hit(zombie: Node3D, damage: float, info: Dictionary) -> void:
	# Nur echte Kugeltreffer lösen Kugel-Effekte aus, nie Blitz, Brand, Gift, Explosion, Drohne,
	# Discokugel oder Störsender.
	if String(info.get("source", "")) != "bullet" or damage <= 0.0:
		return
	_show_bullet_number(zombie, damage, info)
	# Welche Waffe getroffen hat. Ohne Angabe (-1) zählen nur die allgemein gesetzten Upgrades.
	var weapon_uid: int = int(info.get("weapon_uid", -1))
	_apply_burn(zombie, weapon_uid)
	_apply_poison(zombie, weapon_uid)
	_apply_frost(zombie, weapon_uid)
	_try_chain_lightning(zombie, damage, info, weapon_uid)
	_try_ricochet(zombie, damage, info, weapon_uid)


func _on_weapon_fired(_weapon_id: String) -> void:
	_shot_procs = 0
	_shot_frame = Engine.get_process_frames()


## Trefferzahl am Einschlag der Kugel: weiß, Kopftreffer gelb.
func _show_bullet_number(zombie: Node3D, damage: float, info: Dictionary) -> void:
	if not SHOW_BULLET_NUMBERS:
		return
	var at: Vector3
	if info.has("hit_position"):
		at = info["hit_position"]
	elif is_instance_valid(zombie) and zombie.is_inside_tree():
		at = _center_of(zombie)
	else:
		return
	var color: Color = HEADSHOT_NUMBER_COLOR if bool(info.get("headshot", false)) else BULLET_NUMBER_COLOR
	Fx.damage_number(Fx.root_of(self), at + Vector3(0.0, 0.3, 0.0), damage, color)


## Feuershow: setzt den getroffenen Zombie in Brand. Zählt alle Exemplare, die für diese Waffe
## wirken (mehrere addieren ihren Anteil).
func _apply_burn(zombie: Node3D, weapon_uid: int) -> void:
	if Game.bullet_level(weapon_uid, "burn") <= 0:
		return
	var dps_percent: float = Game.bullet_value(weapon_uid, "burn", "dps_percent")
	if dps_percent <= 0.0 or not _is_alive(zombie) or not zombie.has_method("apply_burn"):
		return
	var dps: float = dps_percent * float(zombie.get("max_hp"))
	if String(zombie.get("zombie_type")) == "elite":
		dps *= Balance.BURN_ELITE_FACTOR
	if dps > 0.0:
		zombie.call("apply_burn", dps, Balance.BURN_DURATION)


## Kantinenessen: vergiftet den getroffenen Zombie für Balance.POISON_DURATION Sekunden. Zählt
## alle Exemplare, die für diese Waffe wirken (ihr Schaden je Sekunde addiert sich), mal
## Effekt-Faktor der Welle. Ein weiterer Treffer stellt die Zeit neu, der höhere Wert bleibt
## (zombie.apply_poison). Das Gift tickt im Zombie mit source "poison" und löst deshalb selbst
## keine Kugel-Effekte aus.
func _apply_poison(zombie: Node3D, weapon_uid: int) -> void:
	if Game.bullet_level(weapon_uid, "poison") <= 0:
		return
	var dps: float = Game.bullet_value(weapon_uid, "poison", "dps") * Game.effect_factor()
	if dps <= 0.0 or not _is_alive(zombie) or not zombie.has_method("apply_poison"):
		return
	zombie.call("apply_poison", dps, Balance.POISON_DURATION)


## Trockeneis: verlangsamt den getroffenen Zombie für Balance.FROST_DURATION Sekunden. Mehrere
## Exemplare auf der Waffe: Der stärkste Wert zählt (Game.bullet_value). Den halben Wert für
## Elite und die Regel "die stärkste Verlangsamung gilt" rechnet der Zombie selbst.
func _apply_frost(zombie: Node3D, weapon_uid: int) -> void:
	if Game.bullet_level(weapon_uid, "frost") <= 0:
		return
	var slow: float = Game.bullet_value(weapon_uid, "frost", "slow")
	if slow <= 0.0 or not _is_alive(zombie) or not zombie.has_method("apply_slow"):
		return
	zombie.call("apply_slow", slow, Balance.FROST_DURATION)


## Querschläger: würfelt mit der Chance der Waffe, die getroffen hat. Dann springt der Treffer
## auf den nächsten anderen lebenden Zombie im Umkreis Balance.RICOCHET_RADIUS um den Getroffenen
## und macht dort RICOCHET_DAMAGE_FACTOR des Kugelschadens (source "ricochet"). Der Querschläger
## ist kein Kugeltreffer: kein bullet_hit, also kein Blitz, Brand, Gift und kein weiterer Sprung.
## Gewürfelt wird nur, wenn der Gegenstand auf die Waffe wirkt (sonst bleibt Game.rng unberührt).
func _try_ricochet(zombie: Node3D, damage: float, info: Dictionary, weapon_uid: int) -> void:
	if Game.bullet_level(weapon_uid, "ricochet") <= 0:
		return
	var chance: float = Game.bullet_value(weapon_uid, "ricochet", "chance")
	if chance <= 0.0 or Game.rng.randf() >= chance:
		return
	var origin: Vector3
	if is_instance_valid(zombie) and zombie.is_inside_tree():
		origin = _center_of(zombie)
	elif info.has("hit_position"):
		origin = info["hit_position"]
	else:
		return
	var best: Node3D = null
	var best_distance: float = Balance.RICOCHET_RADIUS
	for entry: Variant in _living_zombies():
		var candidate: Node3D = entry
		if candidate == zombie:
			continue
		var distance: float = origin.distance_to(_center_of(candidate))
		if distance <= best_distance:
			best = candidate
			best_distance = distance
	if best == null:
		return
	var amount: float = damage * Balance.RICOCHET_DAMAGE_FACTOR
	var target: Vector3 = _center_of(best)
	var fx_root: Node = Fx.root_of(self)
	UpgradeFx.beam(fx_root, origin, target, RICOCHET_COLOR, RICOCHET_WIDTH, RICOCHET_TIME)
	if SHOW_DAMAGE_NUMBERS:
		Fx.damage_number(fx_root, target + Vector3(0.0, 0.6, 0.0), amount, RICOCHET_NUMBER_COLOR)
	best.call("take_damage", amount, {"source": "ricochet", "hit_position": target})


## Starkstrom-Sponsor: würfelt den Blitz aus, mit den Werten der Waffe, die getroffen hat. Mit
## der Gewitterfront kommt er sicher, aber höchstens Balance.STORM_FRONT_MAX_PROCS_PER_SHOT Mal
## je Schuss.
func _try_chain_lightning(zombie: Node3D, damage: float, info: Dictionary, weapon_uid: int) -> void:
	if Game.bullet_level(weapon_uid, "chain_lightning") <= 0:
		return
	# Ein Treffer in einem späteren Bild gehört zu einem neuen Schuss.
	var frame: int = Engine.get_process_frames()
	if frame != _shot_frame:
		_shot_frame = frame
		_shot_procs = 0
	if _has_storm_front(weapon_uid):
		if _shot_procs >= Balance.STORM_FRONT_MAX_PROCS_PER_SHOT:
			return
	else:
		var chance: float = Game.bullet_value(weapon_uid, "chain_lightning", "chance")
		# Die Waffen-ID heißt im Treffer "weapon_id", seit Abschnitt 18 auch "weapon".
		var weapon_def: Dictionary = WeaponDefs.get_def(String(info.get("weapon_id", info.get("weapon", ""))))
		if int(weapon_def.get("pellets", 1)) > 1:
			chance *= Balance.CHAIN_PELLET_CHANCE_FACTOR
		if Game.rng.randf() >= chance:
			return
	var origin: Vector3
	if is_instance_valid(zombie) and zombie.is_inside_tree():
		origin = _center_of(zombie)
	elif info.has("hit_position"):
		origin = info["hit_position"]
	else:
		return
	# Nur ein Blitz, der wirklich überspringt, zählt als Auslösung.
	if _cast_lightning(zombie, origin, damage, weapon_uid):
		_shot_procs += 1


## Gilt die Gewitterfront für diese Waffe? Die Verbindung muss aktiv sein, und jede ihrer
## Voraussetzungen muss in der verlangten Stufe auf genau diese Waffe wirken (allgemein gesetzte
## Upgrades zählen für jede Waffe). Eine zweite Waffe ohne diese Gegenstände würfelt normal.
func _has_storm_front(weapon_uid: int) -> bool:
	if not Game.upgrades.has_synergy("storm_front"):
		return false
	var requires: Dictionary = UpgradeDefs.synergy_requirements("storm_front")
	for upgrade_id: String in requires:
		if Game.bullet_level(weapon_uid, upgrade_id) < int(requires[upgrade_id]):
			return false
	return Game.bullet_level(weapon_uid, "chain_lightning") > 0


## Lässt einen Blitz von origin aus von Zombie zu Zombie springen: jeweils zum nächsten noch
## nicht getroffenen im Umkreis Balance.CHAIN_RADIUS. Der Zombie am Ursprung bekommt nichts ab.
## Sprünge und Schadensanteil sind die der Waffe weapon_uid.
## Gibt true zurück, wenn mindestens ein Zombie getroffen wurde.
func _cast_lightning(origin_zombie: Node3D, origin: Vector3, bullet_damage: float, weapon_uid: int) -> bool:
	var jumps: int = int(Game.bullet_value(weapon_uid, "chain_lightning", "jumps"))
	var damage: float = bullet_damage * Game.bullet_value(weapon_uid, "chain_lightning", "damage_factor")
	if jumps <= 0 or damage <= 0.0:
		return false
	var candidates: Array = _living_zombies()
	candidates.erase(origin_zombie)
	# Erst die ganze Kette festlegen, dann Schaden verteilen: So ändert ein Tod mitten in der
	# Kette nichts an ihrem Weg. Die Listen sind ohne Typ: Ein Ziel kann verschwinden, während
	# ein früheres Schaden nimmt, und ein freigegebenes Objekt darf nie in eine typisierte
	# Variable oder einen typisierten Parameter wandern.
	var chain: Array = []
	var points: PackedVector3Array = PackedVector3Array([origin])
	var current: Vector3 = origin
	for _jump: int in jumps:
		var best: Node3D = null
		var best_distance: float = Balance.CHAIN_RADIUS
		for entry: Variant in candidates:
			if not _is_alive(entry):
				continue
			var candidate: Node3D = entry
			var distance: float = current.distance_to(_center_of(candidate))
			if distance <= best_distance:
				best = candidate
				best_distance = distance
		if best == null:
			break
		candidates.erase(best)
		chain.append(best)
		current = _center_of(best)
		points.append(current)
	if chain.is_empty():
		return false
	var fx_root: Node = Fx.root_of(self)
	Fx.lightning(fx_root, points)
	for i: int in chain.size():
		if not _is_alive(chain[i]):
			continue
		var target: Node3D = chain[i]
		if SHOW_DAMAGE_NUMBERS:
			Fx.damage_number(fx_root, points[i + 1] + Vector3(0.0, 0.6, 0.0), damage, LIGHTNING_NUMBER_COLOR)
		target.call("take_damage", damage, {"source": "lightning", "hit_position": points[i + 1]})
	return true


# --- Lebensraub ---

func _on_zombie_damaged(_zombie: Node3D, amount: float, _info: Dictionary) -> void:
	var ratio: float = Game.upgrades.value("lifesteal", "ratio")
	if ratio <= 0.0 or amount <= 0.0:
		return
	var player: Node3D = _player()
	if player == null or bool(player.get("is_dead")) or not player.has_method("heal"):
		return
	var heal: float = minf(amount * ratio, get_lifesteal_budget_left())
	# Bei vollem Leben verfällt nichts vom Kontingent, und es beginnt auch kein Zeitfenster.
	if player.get("hp") != null and player.get("max_hp") != null:
		heal = minf(heal, float(player.get("max_hp")) - float(player.get("hp")))
	if heal <= 0.0:
		return
	if _lifesteal_window_left <= 0.0:
		# Ein neues Zeitfenster beginnt erst mit der ersten Heilung, die wirklich ankommt. Begänne
		# es schon mit einem Treffer bei vollem Leben, gäbe es kurz vor und kurz nach seinem Ende
		# je ein volles Kontingent.
		_lifesteal_window_left = Balance.LIFESTEAL_WINDOW
		_lifesteal_healed = 0.0
	_lifesteal_healed += heal
	player.call("heal", heal)


# --- Trostpflaster und Konfetti-Explosion ---

func _on_zombie_killed(zombie: Node3D, info: Dictionary) -> void:
	_heal_on_kill()
	if not is_instance_valid(zombie) or not zombie.is_inside_tree():
		return
	if Game.upgrades.get_level("corpse_explosion") <= 0:
		return
	# Tiefe der Explosion, die diesen Zombie getötet hat (0 = kein Explosions-Kill).
	var depth: int = 0
	if String(info.get("source", "")) == "explosion":
		depth = maxi(1, int(info.get("chain_depth", 1)))
	if depth >= Balance.EXPLOSION_MAX_CHAIN:
		return
	if Game.rng.randf() >= Game.upgrades.value("corpse_explosion", "chance"):
		return
	var max_hp: float = float(zombie.get("max_hp")) if zombie.get("max_hp") != null else 0.0
	var damage: float = max_hp * Game.upgrades.value("corpse_explosion", "damage_percent")
	if damage <= 0.0:
		return
	# Nie hier zünden: Die Explosion würde mitten in zombie_killed weitere Tode auslösen.
	_pending_explosions.append({
		"position": _center_of(zombie),
		"radius": Game.upgrades.value("corpse_explosion", "radius"),
		"damage": damage,
		"depth": depth + 1,
		"delay": Balance.EXPLOSION_CHAIN_DELAY if depth > 0 else 0.0,
	})


## Trostpflaster: Jeder Kill heilt den Spieler, gleich welche Quelle den Zombie getötet hat.
## Mehrere Exemplare addieren ihre Heilung. Über das Maximal-Leben hinaus heilt player.heal nie.
func _heal_on_kill() -> void:
	var amount: float = Game.upgrades.value("kill_heal", "heal")
	if amount <= 0.0:
		return
	var player: Node3D = _player()
	if player == null or bool(player.get("is_dead")) or not player.has_method("heal"):
		return
	player.call("heal", amount)


## Zündet eine vorgemerkte Explosion: Schaden an allen lebenden Zombies im Radius mit freier
## Sichtlinie. Der Spieler nimmt keinen Schaden.
func _explode(entry: Dictionary) -> void:
	if not is_inside_tree():
		return
	var center: Vector3 = entry["position"]
	var radius: float = float(entry["radius"])
	var damage: float = float(entry["damage"])
	var depth: int = int(entry["depth"])
	var fx_root: Node = Fx.root_of(self)
	Fx.explosion(fx_root, center, radius, EXPLOSION_COLORS[_explosion_count % EXPLOSION_COLORS.size()])
	Fx.confetti(fx_root, center)
	Events.explosion.emit(center, radius)
	_explosion_count += 1
	for candidate: Variant in _living_zombies():
		# Ein früheres Opfer dieser Schleife kann inzwischen tot oder weg sein.
		if not _is_alive(candidate):
			continue
		var zombie: Node3D = candidate
		var target: Vector3 = _center_of(zombie)
		if center.distance_to(target) > radius or not _has_line_of_sight(center, target):
			continue
		if SHOW_DAMAGE_NUMBERS:
			Fx.damage_number(fx_root, target + Vector3(0.0, 0.6, 0.0), damage, EXPLOSION_NUMBER_COLOR)
		zombie.call("take_damage", damage, {
			"source": "explosion", "chain_depth": depth, "hit_position": target,
		})


# --- Druckwelle beim Nachladen ---

## Nachladen der linken Hand (und jeder Waffe in älteren Abläufen).
func _on_reload_started(_weapon_id: String, _duration: float) -> void:
	_try_shockwave()


## Nachladen einer Hand (0 = links, 1 = rechts). Die linke Hand meldet sich zusätzlich über
## reload_started: _try_shockwave lässt je Schritt nur eine Welle zu.
func _on_hand_reload_started(_hand: int, _duration: float) -> void:
	_try_shockwave()


## Werbepause: Druckwelle um den Spieler, wenn das Upgrade wirkt und die Abklingzeit um ist.
## Mit zwei Waffen darf das Nachladen jeder Hand sie auslösen. Mehrere Exemplare: der größte
## Radius, die Schadenswerte addieren sich (Game.upgrades.value).
func _try_shockwave() -> void:
	if Game.upgrades.get_level("reload_shockwave") <= 0 or _shockwave_cooldown_left > 0.0:
		return
	if _shockwave_this_step:
		return
	var player: Node3D = _player()
	if player == null or bool(player.get("is_dead")):
		return
	var radius: float = Game.upgrades.value("reload_shockwave", "radius")
	var damage: float = Game.upgrades.value("reload_shockwave", "damage") * Game.effect_factor()
	if radius <= 0.0:
		return
	_shockwave_this_step = true
	_shockwave_count += 1
	var center: Vector3 = player.global_position
	var fx_root: Node = Fx.root_of(self)
	Fx.shockwave(fx_root, center, radius)
	var hit_any: bool = false
	for entry: Variant in _living_zombies():
		if not _is_alive(entry):
			continue
		var zombie: Node3D = entry
		var offset: Vector3 = zombie.global_position - center
		if offset.length() > radius:
			continue
		hit_any = true
		var push: Vector3 = Vector3(offset.x, 0.0, offset.z)
		if push.length_squared() < 0.0001:
			push = -player.global_basis.z
			push.y = 0.0
		if push.length_squared() < 0.0001:
			push = Vector3.FORWARD
		var center_position: Vector3 = _center_of(zombie)
		if SHOW_DAMAGE_NUMBERS:
			Fx.damage_number(fx_root, center_position + Vector3(0.0, 0.6, 0.0), damage, SHOCKWAVE_NUMBER_COLOR)
		zombie.call("take_damage", damage, {"source": "shockwave", "hit_position": center_position})
		# Wer die Welle überlebt, fliegt vom Spieler weg.
		if _is_alive(zombie) and zombie.has_method("apply_knockback"):
			zombie.call("apply_knockback", push.normalized() * Balance.SHOCKWAVE_KNOCKBACK)
	# Die Abklingzeit beginnt nur, wenn die Welle jemanden erwischt hat: Ein Nachladen ohne
	# Zombie in der Nähe verbraucht die Druckwelle nicht.
	if hit_any:
		_shockwave_cooldown_left = Balance.SHOCKWAVE_COOLDOWN


# --- Discokugeln: Umlauf ---

## Lässt die Discokugeln einen Schritt weiterkreisen und treffen. Nur im State PLAYING: Sonst
## bleiben sie stehen.
func _tick_disco_balls(delta: float) -> void:
	if disco_balls.is_empty():
		return
	var playing: bool = Game.state == Game.State.PLAYING
	if playing:
		_disco_angle = fposmod(_disco_angle + Balance.DISCO_ORBIT_SPEED * delta, TAU)
	# Über den Index: Ein freigegebenes Objekt darf nie in eine typisierte Variable.
	for i: int in disco_balls.size():
		if not is_instance_valid(disco_balls[i]) or disco_balls[i].is_queued_for_deletion():
			continue
		if playing:
			disco_balls[i].call("tick", delta, _disco_angle)
		else:
			disco_balls[i].call("hold")


# --- Störsender ---

## Uhr des Störsenders: zählt im State PLAYING herunter und schlägt zu, sobald sie um ist und ein
## Zombie im Umkreis steht. Ohne Zombie bleibt der Schlag fällig. Ohne Störsender läuft keine
## Uhr: Wer ihn einräumt, wartet einen vollen Abstand.
func _tick_jammer(delta: float) -> void:
	if Game.upgrades.get_level("jammer") <= 0:
		_jammer_left = Balance.JAMMER_INTERVAL
		return
	if Game.state != Game.State.PLAYING:
		return
	_jammer_left = maxf(0.0, _jammer_left - delta)
	if _jammer_left > TIME_EPSILON:
		return
	_jammer_left = 0.0
	if _fire_jammer():
		_jammer_left = Balance.JAMMER_INTERVAL


## Elektroschlag des Störsenders: Schaden an allen lebenden Zombies im Umkreis um den Spieler
## (Füße zu Füßen, wie die Druckwelle). Mehrere Exemplare: der größte Radius, die Schadenswerte
## addieren sich (Game.upgrades.value). Gibt true zurück, wenn mindestens ein Zombie im Umkreis
## stand. Sonst passiert nichts, auch kein Effekt.
func _fire_jammer() -> bool:
	var player: Node3D = _player()
	if player == null or bool(player.get("is_dead")):
		return false
	var radius: float = Game.upgrades.value("jammer", "radius")
	var damage: float = Game.upgrades.value("jammer", "damage") * Game.effect_factor()
	if radius <= 0.0 or damage <= 0.0:
		return false
	var center: Vector3 = player.global_position
	# Erst alle Ziele festlegen, dann Schaden verteilen: Ein Tod ändert nichts an der Auswahl.
	var targets: Array = []
	var points: PackedVector3Array = PackedVector3Array()
	for entry: Variant in _living_zombies():
		var candidate: Node3D = entry
		if candidate.global_position.distance_to(center) <= radius:
			targets.append(candidate)
			points.append(_center_of(candidate))
	if targets.is_empty():
		return false
	var fx_root: Node = Fx.root_of(self)
	Fx.lightning_star(fx_root, center + Vector3(0.0, JAMMER_ORIGIN_HEIGHT, 0.0), points)
	Fx.shockwave(fx_root, center, radius)
	for i: int in targets.size():
		# Ein früheres Opfer dieser Schleife kann ein späteres mitgerissen haben.
		if not _is_alive(targets[i]):
			continue
		var target: Node3D = targets[i]
		if SHOW_DAMAGE_NUMBERS:
			Fx.damage_number(fx_root, points[i] + Vector3(0.0, 0.6, 0.0), damage, JAMMER_NUMBER_COLOR)
		target.call("take_damage", damage, {"source": "jammer", "hit_position": points[i]})
	return true


# --- Kaktus-Requisite und Pausensnack ---

## Ein Zombie hat den Spieler getroffen: Die Stacheln wirken im nächsten Schritt (siehe Kopf).
func _on_player_damaged(_amount: float) -> void:
	if Game.upgrades.get_level("thorns") > 0:
		_thorns_pending = true


func _tick_thorns() -> void:
	if not _thorns_pending:
		return
	_thorns_pending = false
	_fire_thorns()


## Kaktus-Requisite: Schaden an allen lebenden Zombies im Umkreis Balance.THORNS_RADIUS um den
## Spieler (Füße zu Füßen, wie der Störsender). Mehrere Exemplare addieren ihren Schaden, mal
## Effekt-Faktor der Welle. Ein toter Spieler sticht nicht mehr.
func _fire_thorns() -> void:
	var player: Node3D = _player()
	if player == null or bool(player.get("is_dead")):
		return
	var damage: float = Game.upgrades.value("thorns", "damage") * Game.effect_factor()
	if damage <= 0.0:
		return
	var center: Vector3 = player.global_position
	var fx_root: Node = Fx.root_of(self)
	UpgradeFx.spikes(fx_root, center, Balance.THORNS_RADIUS, THORNS_COLOR)
	# Erst alle Ziele festlegen, dann Schaden verteilen: Ein Tod ändert nichts an der Auswahl.
	var targets: Array = []
	var points: PackedVector3Array = PackedVector3Array()
	for entry: Variant in _living_zombies():
		var candidate: Node3D = entry
		if candidate.global_position.distance_to(center) <= Balance.THORNS_RADIUS:
			targets.append(candidate)
			points.append(_center_of(candidate))
	for i: int in targets.size():
		if not _is_alive(targets[i]):
			continue
		var target: Node3D = targets[i]
		if SHOW_DAMAGE_NUMBERS:
			Fx.damage_number(fx_root, points[i] + Vector3(0.0, 0.6, 0.0), damage, THORNS_NUMBER_COLOR)
		target.call("take_damage", damage, {"source": "thorns", "hit_position": points[i]})


## Pausensnack: Am Ende jeder Welle heilt der Spieler zusätzlich (mehrere Exemplare addieren sich).
func _on_wave_cleared(_wave: int) -> void:
	var amount: float = Game.upgrades.value("snack", "heal")
	if amount <= 0.0:
		return
	var player: Node3D = _player()
	if player == null or bool(player.get("is_dead")) or not player.has_method("heal"):
		return
	player.call("heal", amount)


# --- Requisitenbombe ---

## Minen: Die liegenden werden scharf und lösen aus, sobald ein Zombie nah genug ist. Danach
## läuft die Uhr für die nächste Mine (nur im State PLAYING).
func _tick_mines(delta: float) -> void:
	if not mines.is_empty():
		_prune_mines()
		if Game.state == Game.State.PLAYING:
			_trigger_mines(delta)
	if Game.upgrades.get_level("mine") <= 0:
		_mine_left = MINE_IDLE
		return
	var interval: float = Game.upgrades.value("mine", "interval")
	if interval <= 0.0:
		return
	# Neu eingeräumt: einen vollen Abstand warten. Ein kürzerer Abstand gilt sofort.
	if _mine_left < 0.0:
		_mine_left = interval
	_mine_left = minf(_mine_left, interval)
	if Game.state != Game.State.PLAYING:
		return
	_mine_left = maxf(0.0, _mine_left - delta)
	if _mine_left > TIME_EPSILON:
		return
	_mine_left = 0.0
	if _place_mine():
		_mine_left = interval


## Minen, die von außen verschwunden sind (Effekt-Behälter geleert), fallen aus der Liste.
func _prune_mines() -> void:
	var gone: bool = false
	for i: int in mines.size():
		if not is_instance_valid(mines[i]) or mines[i].is_queued_for_deletion():
			gone = true
			break
	if not gone:
		return
	var alive: Array[Node3D] = []
	for i: int in mines.size():
		if is_instance_valid(mines[i]) and not mines[i].is_queued_for_deletion():
			alive.append(mines[i])
	mines = alive


## Lässt die Minen scharf werden und zündet jede scharfe, der ein lebender Zombie auf
## Balance.MINE_TRIGGER_RADIUS nahe gekommen ist (Füße des Zombies zur Mine).
func _trigger_mines(delta: float) -> void:
	var due: Array[Node3D] = []
	var zombies: Array = _living_zombies()
	for mine: Node3D in mines:
		mine.call("tick", delta)
		if not bool(mine.call("is_armed")):
			continue
		var at: Vector3 = mine.global_position
		for entry: Variant in zombies:
			var zombie: Node3D = entry
			if zombie.global_position.distance_to(at) <= Balance.MINE_TRIGGER_RADIUS:
				due.append(mine)
				break
	for mine: Node3D in due:
		_explode_mine(mine)


## Legt eine Mine an die Füße des Spielers (auf den Boden darunter). Gibt false zurück, wenn es
## gerade nicht geht: kein lebender Spieler, schon Balance.MINE_MAX_ACTIVE Minen, oder eine Mine
## liegt näher als MINE_MIN_SPACING. Die älteste Mine weicht nie.
func _place_mine() -> bool:
	var player: Node3D = _player()
	var fx_root: Node = Fx.root_of(self)
	if player == null or fx_root == null or bool(player.get("is_dead")):
		return false
	if mines.size() >= Balance.MINE_MAX_ACTIVE:
		return false
	var damage: float = Game.upgrades.value("mine", "damage")
	if damage <= 0.0:
		return false
	var at: Vector3 = _floor_below(player.global_position)
	for mine: Node3D in mines:
		if mine.global_position.distance_to(at) < MINE_MIN_SPACING:
			return false
	var new_mine: Node3D = Mine.new()
	new_mine.name = "Mine"
	new_mine.set("damage", damage)
	fx_root.add_child(new_mine, true)
	new_mine.global_position = at
	mines.append(new_mine)
	Events.mine_placed.emit(at)
	return true


## Der Boden unter diesem Punkt (Welt, Lage 1), höchstens MINE_DROP_DEPTH tiefer. Ohne Boden
## oder ohne Physik-Welt der Punkt selbst.
func _floor_below(point: Vector3) -> Vector3:
	var world: World3D = get_viewport().find_world_3d()
	if world == null or world.direct_space_state == null:
		return point
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		point + Vector3(0.0, 0.5, 0.0), point - Vector3(0.0, MINE_DROP_DEPTH, 0.0), Balance.MASK_LINE_OF_SIGHT)
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return point
	return hit["position"] as Vector3


## Zündet eine Mine: Events.mine_triggered, dann die Explosion (Events.explosion) mit Schaden an
## allen lebenden Zombies im Umkreis Balance.MINE_RADIUS (Füße zur Mine) mit freier Sicht. Der
## Spieler nimmt keinen Schaden.
func _explode_mine(mine: Node3D) -> void:
	if not is_instance_valid(mine) or not mines.has(mine):
		return
	mines.erase(mine)
	var at: Vector3 = mine.global_position
	var damage: float = float(mine.get("damage")) * Game.effect_factor()
	mine.queue_free()
	Events.mine_triggered.emit(at)
	var center: Vector3 = at + Vector3(0.0, MINE_BLAST_HEIGHT, 0.0)
	var fx_root: Node = Fx.root_of(self)
	Fx.explosion(fx_root, center, Balance.MINE_RADIUS, MINE_COLOR)
	Events.explosion.emit(center, Balance.MINE_RADIUS)
	if damage <= 0.0:
		return
	for candidate: Variant in _living_zombies():
		# Ein früheres Opfer dieser Schleife kann inzwischen tot oder weg sein.
		if not _is_alive(candidate):
			continue
		var zombie: Node3D = candidate
		var target: Vector3 = _center_of(zombie)
		if zombie.global_position.distance_to(at) > Balance.MINE_RADIUS or not _has_line_of_sight(center, target):
			continue
		if SHOW_DAMAGE_NUMBERS:
			Fx.damage_number(fx_root, target + Vector3(0.0, 0.6, 0.0), damage, MINE_NUMBER_COLOR)
		zombie.call("take_damage", damage, {"source": "mine", "hit_position": target})


## Entfernt alle Minen, ohne dass sie explodieren (neuer Lauf).
func _remove_mines() -> void:
	for i: int in mines.size():
		if is_instance_valid(mines[i]):
			mines[i].queue_free()
	mines = []


# --- Kameras, Discokugeln, Upgrade-Wahl, neuer Lauf ---

func _on_upgrade_chosen(_upgrade_id: String, _new_level: int) -> void:
	_sync_cameras()
	_sync_disco_balls()
	# Kleiner Jubel vor der Nase des Spielers.
	var player: Node3D = _player()
	if player == null:
		return
	var spot: Vector3 = player.global_position + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 0.0)
	if player.has_method("get_eye_position") and player.has_method("get_aim_direction"):
		var eye: Vector3 = player.call("get_eye_position")
		var aim: Vector3 = player.call("get_aim_direction")
		spot = eye + aim * 2.2
	Fx.confetti(Fx.root_of(self), spot)


func _on_build_changed() -> void:
	_sync_cameras()
	_sync_disco_balls()


func _on_synergy_unlocked(synergy_id: String) -> void:
	if synergy_id != "storm_front":
		return
	# Gewitterfront: Blitze schlagen rund um den Spieler ein.
	var player: Node3D = _player()
	if player == null:
		return
	var fx_root: Node = Fx.root_of(self)
	var feet: Vector3 = player.global_position
	for i: int in 6:
		var angle: float = TAU * float(i) / 6.0
		var ground: Vector3 = feet + Vector3(cos(angle), 0.0, sin(angle)) * 2.5
		Fx.lightning(fx_root, PackedVector3Array([ground + Vector3(0.0, 4.5, 0.0), ground]))
	Fx.shockwave(fx_root, feet, 3.0)


func _on_run_started() -> void:
	_shot_procs = 0
	_shot_frame = -1
	_lifesteal_window_left = 0.0
	_lifesteal_healed = 0.0
	_shockwave_cooldown_left = 0.0
	_shockwave_this_step = false
	_shockwave_count = 0
	_pending_explosions.clear()
	_explosion_count = 0
	_jammer_left = Balance.JAMMER_INTERVAL
	_disco_angle = 0.0
	_thorns_pending = false
	_mine_left = MINE_IDLE
	_remove_mines()
	# Ein neuer Lauf beginnt mit frischen Kameras und Discokugeln (Start-Gegenstände des Kandidaten).
	_remove_cameras()
	_sync_cameras()
	_remove_disco_balls()
	_sync_disco_balls()


## Stufen der Begleiter, die es geben soll: einer je wirkendem Exemplar dieses Gegenstands
## (Game.upgrades.copies(id)), jede Stufe im gültigen Bereich.
func _wanted_levels(upgrade_id: String) -> Array[int]:
	var levels: Array[int] = []
	for entry: Variant in Game.upgrades.copies(upgrade_id):
		if int(entry) > 0:
			levels.append(clampi(int(entry), 1, Balance.UPGRADE_MAX_LEVEL))
	return levels


## Raritäten der Kameras, die es geben soll: camera_id -> Array[int], eine je Eintrag dieses Typs
## in Game.cameras. Wird nur neu gelesen, wenn Game das Array ersetzt hat.
func _wanted_camera_levels() -> Dictionary:
	if is_same(Game.cameras, _wanted_source) and not _wanted_cache.is_empty():
		return _wanted_cache
	var wanted: Dictionary = {}
	var none: Array[int] = []
	wanted[Drone.CAMERA_ID] = none
	for camera_id: String in CAMERA_IDS:
		var empty: Array[int] = []
		wanted[camera_id] = empty
	for entry: Dictionary in Game.cameras:
		var entry_id: String = str(entry["id"])
		if wanted.has(entry_id):
			(wanted[entry_id] as Array).append(clampi(int(entry["level"]), 1, Balance.UPGRADE_MAX_LEVEL))
	_wanted_cache = wanted
	_wanted_source = Game.cameras
	return wanted


## Gleicht eine Liste von Begleitern (Kameras, Discokugeln: Knoten mit level und set_level) mit
## den gewünschten Stufen ab: fehlende erzeugen, Stufen setzen, überzählige entfernen. Vorhandene
## Knoten bleiben, soweit es geht: Erst behält jeder, dessen Stufe noch gebraucht wird, seinen
## Knoten, dann bekommen übrige eine der noch offenen Stufen, erst danach wird entfernt oder neu
## erzeugt. create(stufe, platz) liefert einen neuen, fertig eingestellten Knoten, der noch nicht
## im Baum hängt: Er kommt hier in den Effekt-Behälter.
## Gibt die neue Liste zurück (die Plätze vergibt der Aufrufer). Hat sich nichts geändert, kommt
## current selbst zurück (prüfen mit is_same).
func _sync_companions(current: Array[Node3D], wanted: Array[int], create: Callable) -> Array[Node3D]:
	# Knoten, die von außen verschwunden sind (Effekt-Behälter geleert), fallen aus der Liste.
	# Über den Index, weil ein freigegebenes Objekt nie in eine typisierte Variable darf.
	var alive: Array[Node3D] = []
	for i: int in current.size():
		if is_instance_valid(current[i]) and not current[i].is_queued_for_deletion():
			alive.append(current[i])
	# Schneller Ausweg für den Normalfall (läuft je Physik-Schritt): nichts hat sich geändert.
	if alive.size() == current.size() and alive.size() == wanted.size():
		var same: bool = true
		for i: int in alive.size():
			if int(alive[i].get("level")) != wanted[i]:
				same = false
				break
		if same:
			return current
	# 1. Knoten, deren Stufe noch gebraucht wird, behalten sie.
	var open: Array[int] = wanted.duplicate()
	var matched: Dictionary = {}
	for i: int in alive.size():
		var at: int = open.find(int(alive[i].get("level")))
		if at >= 0:
			open.remove_at(at)
			matched[i] = true
	# 2. Die übrigen bekommen eine offene Stufe oder gehen.
	var kept: Array[Node3D] = []
	for i: int in alive.size():
		if matched.has(i):
			kept.append(alive[i])
		elif not open.is_empty():
			alive[i].call("set_level", open.pop_front())
			kept.append(alive[i])
		else:
			alive[i].queue_free()
	# 3. Für jede Stufe, die noch offen ist, ein neuer Knoten.
	var fx_root: Node = Fx.root_of(self)
	if fx_root != null:
		for level: int in open:
			var created: Node3D = create.call(level, kept.size())
			fx_root.add_child(created, true)
			kept.append(created)
	return kept


## Gleicht die Kamera-Knoten mit Game.cameras ab: je Typ ein Abgleich wie bei allen Begleitern
## (siehe _sync_companions), dann rücken die Plätze auf und jeder Knoten bekommt seinen Eintrag.
## Läuft je Schritt und bei jeder Änderung des Rucksacks. Ohne Änderung passiert fast nichts.
func _sync_cameras() -> void:
	if _camera_nodes.is_empty():
		return
	var wanted: Dictionary = _wanted_camera_levels()
	var changed: bool = false
	var drone_levels: Array[int] = wanted[Drone.CAMERA_ID]
	var kept: Array[Node3D] = _sync_companions(drones, drone_levels, _new_drone)
	if not is_same(kept, drones):
		drones = kept
		drone = drones[0] if not drones.is_empty() else null
		changed = true
	for camera_id: String in CAMERA_IDS:
		var current: Array[Node3D] = _camera_nodes[camera_id]
		var levels: Array[int] = wanted[camera_id]
		kept = _sync_companions(current, levels, _new_camera.bind(camera_id))
		if not is_same(kept, current):
			_camera_nodes[camera_id] = kept
			changed = true
	if not changed and is_same(Game.cameras, _camera_source):
		return
	# Plätze aufrücken: Jede Kamera schwebt an ihrem Platz in der Liste, die Drohnen zuerst.
	var all: Array[Node3D] = []
	all.append_array(drones)
	for camera_id: String in CAMERA_IDS:
		var nodes: Array[Node3D] = _camera_nodes[camera_id]
		all.append_array(nodes)
	for i: int in all.size():
		if int(all[i].get("slot")) != i:
			all[i].call("set_slot", i)
	cameras = all
	_assign_camera_stats()


## Gibt jeder Kamera ihren Eintrag aus Game.cameras (fertige Werte): je Knoten den ersten noch
## freien Eintrag seines Typs und seiner Rarität. Game ersetzt das Array nur, wenn sich etwas
## geändert hat, deshalb reicht der Vergleich mit _camera_source, um das nicht in jedem Schritt
## zu tun.
func _assign_camera_stats() -> void:
	_camera_source = Game.cameras
	var open: Array[Dictionary] = Game.cameras.duplicate()
	for node: Node3D in cameras:
		var camera_id: String = Drone.CAMERA_ID
		if node.get("camera_id") != null:
			camera_id = String(node.get("camera_id"))
		for i: int in open.size():
			if str(open[i]["id"]) == camera_id and int(open[i]["level"]) == int(node.get("level")):
				node.call("set_stats", open[i])
				open.remove_at(i)
				break


## Eine neue Drohne dieser Stufe für diesen Platz, noch nicht im Baum.
func _new_drone(level: int, slot: int) -> Node3D:
	var new_drone: Node3D = Drone.new()
	new_drone.name = "Drone"
	new_drone.call("set_level", level)
	new_drone.call("set_slot", slot)
	new_drone.set("show_damage_numbers", SHOW_DAMAGE_NUMBERS)
	return new_drone


## Eine neue Kamera dieses Typs und dieser Stufe, noch nicht im Baum. index ist ihre Stelle unter
## den Kameras ihres Typs: Ihr Platz liegt hinter allen Drohnen und den Typen davor.
func _new_camera(level: int, index: int, camera_id: String) -> Node3D:
	var camera: Node3D = (CAMERA_SCRIPTS[camera_id] as GDScript).new()
	camera.name = camera_id.to_pascal_case()
	camera.call("set_level", level)
	var slot: int = drones.size() + index
	for other_id: String in CAMERA_IDS:
		if other_id == camera_id:
			break
		slot += (_camera_nodes[other_id] as Array).size()
	camera.call("set_slot", slot)
	camera.set("show_damage_numbers", SHOW_DAMAGE_NUMBERS)
	return camera


## Entfernt alle Kameras (Drohnen und die anderen Typen).
func _remove_cameras() -> void:
	for i: int in drones.size():
		if is_instance_valid(drones[i]):
			drones[i].queue_free()
	for camera_id: String in _camera_nodes:
		var nodes: Array[Node3D] = _camera_nodes[camera_id]
		for i: int in nodes.size():
			if is_instance_valid(nodes[i]):
				nodes[i].queue_free()
		var empty: Array[Node3D] = []
		_camera_nodes[camera_id] = empty
	cameras = []
	drones = []
	drone = null


## Gleicht die Discokugeln mit den Exemplaren der Discokugel ab (siehe _sync_companions). Zum
## Schluss bekommt jede ihren Platz: Alle stehen gleichmäßig über den Kreis verteilt.
func _sync_disco_balls() -> void:
	var kept: Array[Node3D] = _sync_companions(disco_balls, _wanted_levels("disco_ball"), _new_disco_ball)
	if is_same(kept, disco_balls):
		return
	disco_balls = kept
	for i: int in kept.size():
		kept[i].call("set_slot", i, kept.size())
		kept[i].call("place", _disco_angle)


## Eine neue Discokugel dieser Stufe, noch nicht im Baum. Ihren Platz bekommt sie in
## _sync_disco_balls, wenn die Zahl aller Kugeln feststeht.
func _new_disco_ball(level: int, _slot: int) -> Node3D:
	var ball: Node3D = DiscoBall.new()
	ball.name = "DiscoBall"
	ball.call("set_level", level)
	ball.set("show_damage_numbers", SHOW_DAMAGE_NUMBERS)
	return ball


## Entfernt alle Discokugeln.
func _remove_disco_balls() -> void:
	for i: int in disco_balls.size():
		if is_instance_valid(disco_balls[i]):
			disco_balls[i].queue_free()
	disco_balls = []


# --- Hilfen ---

## Der Spieler, wenn er gültig ist und im Baum hängt, sonst null.
func _player() -> Node3D:
	var player: Node3D = Game.player
	if is_instance_valid(player) and player.is_inside_tree():
		return player
	return null


## Momentaufnahme aller lebenden Zombies (Node3D). Die Liste ist bewusst ohne Typ: Ein Zombie
## kann mitten in der Schleife sterben oder verschwinden. Wer darüber läuft, prüft jeden
## Eintrag mit _is_alive, bevor er ihn in eine typisierte Variable legt.
func _living_zombies() -> Array:
	var list: Array = []
	if not is_inside_tree():
		return list
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		if _is_alive(node):
			list.append(node)
	return list


## Lebt dieser Zombie noch und hängt im Baum? Nimmt bewusst jeden Wert an, auch ein schon
## freigegebenes Objekt (das dürfte nie an einen typisierten Parameter gehen).
func _is_alive(candidate: Variant) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node3D:
		return false
	var zombie: Node3D = candidate
	return zombie.is_inside_tree() and not zombie.is_queued_for_deletion() \
		and not bool(zombie.get("is_dead")) and zombie.has_method("take_damage")


## Körpermitte eines Zombies (Zielpunkt für Blitz und Explosion).
func _center_of(zombie: Node3D) -> Vector3:
	if zombie.has_method("get_center_position"):
		return zombie.call("get_center_position")
	return zombie.global_position + Vector3(0.0, Balance.ZOMBIE_HEIGHT * 0.5, 0.0)


## Freie Sicht zwischen zwei Punkten? Nur die Welt (Lage 1) verdeckt. Ohne Physik-Welt: ja.
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var world: World3D = get_viewport().find_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, Balance.MASK_LINE_OF_SIGHT)
	return world.direct_space_state.intersect_ray(query).is_empty()
