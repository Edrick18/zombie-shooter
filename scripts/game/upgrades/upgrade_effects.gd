extends Node
## Modul: Upgrades (scripts/game/upgrades).
## Setzt die Upgrades aus Game.upgrades in Wirkung um (Abschnitt 7, Schritt 3, und Abschnitt 18):
##   bullet_hit      -> Kettenblitz ("chain_lightning", Synergie "storm_front"), Brand ("burn"),
##                      je Waffe über info["weapon_uid"]
##   zombie_damaged  -> Lebensraub ("lifesteal", höchstens Balance.LIFESTEAL_MAX_PER_SECOND)
##   zombie_killed   -> Konfetti-Explosion ("corpse_explosion", Kettentiefe über chain_depth)
##   reload_started, hand_reload_started
##                   -> Druckwelle ("reload_shockwave", Abklingzeit Balance.SHOCKWAVE_COOLDOWN)
##   upgrade_chosen  -> Drohnen abgleichen ("drone"), kleiner Jubel
##   build_changed   -> Drohnen abgleichen (der Rucksack kann sie auch wegnehmen)
##   weapon_fired    -> Zähler der Blitz-Auslösungen je Schuss zurücksetzen (Gewitterfront)
##   run_started     -> Abklingzeiten zurück, wartende Explosionen weg, Drohnen neu aufbauen
##
## Nur source "bullet" löst Kettenblitz und Brand aus. Maximal-Leben und Tempo setzt der Spieler
## selbst (player.refresh_stats), Punkte und Kistenglück liest Game bzw. ChestDropper.
## Feste Schadenswerte mal Game.effect_factor().
##
## Mehrfache Wirkung (Abschnitt 18): Jedes eingeräumte Exemplar zählt.
##   Kugel-Effekte (Kettenblitz, Brand) gelten je Waffe: Game.bullet_value(weapon_uid, id, key)
##   verbindet die allgemein gesetzten Exemplare mit den Stern-Gegenständen dieser Waffe, ob der
##   Effekt für die Waffe überhaupt wirkt, sagt Game.bullet_level(weapon_uid, id) > 0. Fehlt
##   weapon_uid im Treffer, gilt -1: Dann zählen nur die allgemeinen. Die Gewitterfront gilt nur
##   für eine Waffe, auf die alle ihre Voraussetzungen selbst wirken.
##   Alles andere (Lebensraub, Explosion, Druckwelle) liest Game.upgrades.value(id, key): Das
##   verbindet schon alle Exemplare. Game.upgrades.get_level(id) dient hier nur als Ja oder Nein.
##   Drohnen: Game.upgrades.copies("drone") nennt die Rarität jedes Exemplars, jedes ist eine
##   eigene Drohne (drones).
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
const EXPLOSION_COLORS: Array[Color] = [
	Color(1.0, 0.25, 0.6), Color(1.0, 0.75, 0.1), Color(0.3, 0.85, 1.0), Color(0.6, 0.4, 1.0),
]

## Die erste Drohne, null solange keine Kameradrohne wirkt.
var drone: Node3D = null
## Alle Drohnen, eine je wirkendem Exemplar der Kameradrohne, in der Reihenfolge ihrer Plätze
## (drones[i] hat den Platz i). Nur lesen: _sync_drones hält die Liste aktuell.
var drones: Array[Node3D] = []

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


func _ready() -> void:
	Events.bullet_hit.connect(_on_bullet_hit)
	Events.zombie_damaged.connect(_on_zombie_damaged)
	Events.zombie_killed.connect(_on_zombie_killed)
	Events.reload_started.connect(_on_reload_started)
	Events.hand_reload_started.connect(_on_hand_reload_started)
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.upgrade_chosen.connect(_on_upgrade_chosen)
	# Der Rucksack kann Drohnen auch wieder wegnehmen oder schwächen.
	Events.build_changed.connect(_sync_drones)
	Events.synergy_unlocked.connect(_on_synergy_unlocked)
	Events.run_started.connect(_on_run_started)


func _exit_tree() -> void:
	_remove_drones()


func _physics_process(delta: float) -> void:
	tick(delta)


## Lässt die Zeit der Effekte vergehen: Abklingzeit der Druckwelle, Zeitfenster des Lebensraubs,
## fällige Explosionen, Abgleich der Drohnen mit den Exemplaren. Läuft je Physik-Schritt, Tests
## rufen es mit einem eigenen Zeitschritt auf.
func tick(delta: float) -> void:
	_shockwave_cooldown_left = maxf(0.0, _shockwave_cooldown_left - delta)
	_shockwave_this_step = false
	_lifesteal_window_left = maxf(0.0, _lifesteal_window_left - delta)
	_sync_drones()
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


# --- Kugeltreffer: Brand und Kettenblitz ---

func _on_bullet_hit(zombie: Node3D, damage: float, info: Dictionary) -> void:
	# Nur echte Kugeltreffer lösen Kugel-Effekte aus, nie Blitz, Brand, Explosion oder Drohne.
	if String(info.get("source", "")) != "bullet" or damage <= 0.0:
		return
	_show_bullet_number(zombie, damage, info)
	# Welche Waffe getroffen hat. Ohne Angabe (-1) zählen nur die allgemein gesetzten Upgrades.
	var weapon_uid: int = int(info.get("weapon_uid", -1))
	_apply_burn(zombie, weapon_uid)
	_try_chain_lightning(zombie, damage, info, weapon_uid)


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


# --- Konfetti-Explosion ---

func _on_zombie_killed(zombie: Node3D, info: Dictionary) -> void:
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


# --- Drohnen, Upgrade-Wahl, neuer Lauf ---

func _on_upgrade_chosen(_upgrade_id: String, _new_level: int) -> void:
	_sync_drones()
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
	# Ein neuer Lauf beginnt mit frischen Drohnen (Start-Gegenstände des Kandidaten).
	_remove_drones()
	_sync_drones()


## Stufen der Drohnen, die es geben soll: eine je wirkendem Exemplar der Kameradrohne
## (Game.upgrades.copies("drone")), jede Stufe im gültigen Bereich.
func _wanted_drone_levels() -> Array[int]:
	var levels: Array[int] = []
	for entry: Variant in Game.upgrades.copies("drone"):
		if int(entry) > 0:
			levels.append(clampi(int(entry), 1, Balance.UPGRADE_MAX_LEVEL))
	return levels


## Gleicht die Drohnen mit den Exemplaren der Kameradrohne ab: fehlende erzeugen, Stufen setzen,
## überzählige entfernen. Vorhandene Drohnen bleiben, soweit es geht: Erst behält jede Drohne,
## deren Stufe noch gebraucht wird, ihren Knoten, dann bekommen übrige Drohnen eine der noch
## offenen Stufen, erst danach wird entfernt oder neu erzeugt. Zum Schluss rücken die Plätze auf.
func _sync_drones() -> void:
	var wanted: Array[int] = _wanted_drone_levels()
	# Drohnen, die von außen verschwunden sind (Effekt-Behälter geleert), fallen aus der Liste.
	# Über den Index, weil ein freigegebenes Objekt nie in eine typisierte Variable darf.
	var alive: Array[Node3D] = []
	for i: int in drones.size():
		if is_instance_valid(drones[i]) and not drones[i].is_queued_for_deletion():
			alive.append(drones[i])
	# Schneller Ausweg für den Normalfall (läuft je Physik-Schritt): nichts hat sich geändert.
	if alive.size() == drones.size() and alive.size() == wanted.size():
		var same: bool = true
		for i: int in alive.size():
			if int(alive[i].get("level")) != wanted[i]:
				same = false
				break
		if same:
			return
	# 1. Drohnen, deren Stufe noch gebraucht wird, behalten sie.
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
	# 3. Für jede Stufe, die noch offen ist, eine neue Drohne.
	var fx_root: Node = Fx.root_of(self)
	if fx_root != null:
		for level: int in open:
			var new_drone: Node3D = Drone.new()
			new_drone.name = "Drone"
			new_drone.call("set_level", level)
			new_drone.call("set_slot", kept.size())
			new_drone.set("show_damage_numbers", SHOW_DAMAGE_NUMBERS)
			fx_root.add_child(new_drone, true)
			kept.append(new_drone)
	# 4. Plätze aufrücken: Jede Drohne schwebt an ihrem Platz in der Liste.
	for i: int in kept.size():
		if int(kept[i].get("slot")) != i:
			kept[i].call("set_slot", i)
	drones = kept
	drone = drones[0] if not drones.is_empty() else null


## Entfernt alle Drohnen.
func _remove_drones() -> void:
	for i: int in drones.size():
		if is_instance_valid(drones[i]):
			drones[i].queue_free()
	drones = []
	drone = null


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
