extends CharacterBody3D
## Modul: Zombies (scripts/game/zombies).
## Ein Zombie: Leben, Schadensweg (Abschnitt 7), Brand, Gift (Abschnitt 19.1), Rückstoß, Angriff
## mit Ausholen, Wegfindung.
## Gruppe "zombies" (nur solange er lebt). Der Ursprung des Knotens sind die Füße.
##
## Aufbau (entsteht in _ready):
##   Zombie (CharacterBody3D, Lage 3, Maske 1 + 2 + 3)
##   ├─ Shape      CollisionShape3D, Kapsel über die ganze Körperhöhe
##   ├─ Body       Node3D mit zombie_body.gd: der sichtbare Körper aus elf Teilen (Rumpf, Kopf,
##   │   │         Augen, Ober- und Unterarme, Ober- und Unterschenkel), siehe dort. Der Kopf
##   │   │         liegt genau im Kopftreffer-Bereich (über HEADSHOT_HEIGHT_RATIO).
##   │   ├─ Rig    alle Körperteile
##   │   ├─ Flames MeshInstance3D, ein Netz. Entsteht erst beim ersten Brand, nur bei Brand sichtbar.
##   │   └─ Poison Node3D, grüne Giftblasen (zwei Netze). Entsteht erst beim ersten Gift, nur bei
##   │             Gift sichtbar.
##   ├─ NavAgent   NavigationAgent3D
##   ├─ Glow       OmniLight3D (nur Elite)
##   ├─ HealthBar  Node3D (nur Elite), dreht sich zur Kamera
##   └─ Mark       Node3D, pinke Raute über dem Kopf. Entsteht erst bei der ersten Markierung.
##
## Aussehen und Bewegung sind reine Optik: Sie ändern nie den Spielzustand und benutzen nie
## Game.rng. Beim Tod gibt der Zombie seinen Körper ab (zombie_body.gd, release_as_corpse): Der
## liegt noch ZombieBody.CORPSE_TIME Sekunden herum, ohne Kollision. Der Zombie selbst ist wie
## bisher nach Balance.ZOMBIE_DEATH_TIME entfernt.
##
## Bewegung: Ziel ist Game.player. Der Pfad wird alle Balance.ZOMBIE_REPATH_INTERVAL s neu
## berechnet. Gibt es kein Navigationsnetz oder keinen Pfad (headless-Test, Spieler abseits des
## Netzes), läuft der Zombie geradeaus auf den Spieler zu. Niedrige Kanten überspringt er.

const Balance := preload("res://scripts/core/balance.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")
const ZombieBody := preload("res://scripts/game/zombies/zombie_body.gd")
const ZombieLook := preload("res://scripts/game/zombies/zombie_look.gd")

# --- Reine Optik und Technik ---
const HOP_MARGIN: float = 0.12
## Eine Berührung gilt als Wand, wenn ihre Normale höchstens so steil nach oben oder unten zeigt
## (knapp über cos 45 Grad, der Grenze zwischen Boden und Wand in move_and_slide).
const WALL_NORMAL_MAX_Y: float = 0.72
const SEPARATION_INTERVAL: float = 0.1
## Waagerechter Abstand (m), ab dem ein Pfadpunkt als erreicht gilt.
const WAYPOINT_REACHED: float = 0.2
const TURN_SPEED: float = 10.0
const FACE_PLAYER_DISTANCE: float = 3.0
const BURN_EPSILON: float = 0.0001
const FLASH_TIME: float = 0.09
const FLASH_STRENGTH: float = 0.75
## Aufblitzen bei einem Treffer: Die Farben werden um diesen Faktor heller, dazu leuchtet der
## Körper weiß (Anteil FLASH_GLOW).
const FLASH_BRIGHTEN: float = 1.7
const FLASH_GLOW: float = 0.6
const SPAWN_GROW_TIME: float = 0.35
const STRIKE_TIME: float = 0.3
## Kopfradius des sichtbaren Kopfs als Anteil der Körperhöhe, siehe zombie_look.gd.
const HEAD_RADIUS_SHARE: float = ZombieLook.HEAD_RADIUS_SHARE
## Einfärben des Körpers: Anteil der Farbe (TINT) und des Leuchtens in dieser Farbe (GLOW).
const BURN_COLOR: Color = Color(1.0, 0.45, 0.08)
const BURN_TINT: float = 0.6
const BURN_GLOW: float = 0.3
const BURN_GLOW_FLICKER: float = 0.25
const FLAME_COLOR: Color = Color(1.0, 0.62, 0.1)
## Gift: Färbung des Körpers und Farbe der Blasen.
const POISON_COLOR: Color = Color(0.3, 1.0, 0.2)
const POISON_BUBBLE_COLOR: Color = Color(0.45, 1.0, 0.25)
const POISON_CLUSTER_COUNT: int = 2
const POISON_TINT: float = 0.6
const POISON_GLOW: float = 0.16
const POISON_GLOW_PULSE: float = 0.16
## Abstufung der Animation (nur Optik, spart Rechenzeit bei vielen Zombies): Der Körper wird
## höchstens so oft je Sekunde neu gestellt, je nach Entfernung zur Kamera. Näher als
## ANIM_NEAR_DISTANCE Meter einmal je Physikschritt (siehe POSE_WITH_PHYSICS, höchstens
## ANIM_RATE_NEAR), bis ANIM_MID_DISTANCE ANIM_RATE_MID, weiter weg
## ANIM_RATE_FAR, hinter der Kamera ANIM_RATE_BEHIND. Ausholen, Schlag, Treffer und Erscheinen
## laufen immer in jedem Bild. Die Stelle des Zombies in der Welt folgt immer der Physik.
const ANIM_NEAR_DISTANCE: float = 12.0
const ANIM_MID_DISTANCE: float = 26.0
const ANIM_RATE_NEAR: float = 100.0
const ANIM_RATE_MID: float = 45.0
const ANIM_RATE_FAR: float = 30.0
const ANIM_RATE_BEHIND: float = 20.0
## Antwort von _pose_interval für Zombies in der Nähe: stellen, sobald ein Physikschritt gelaufen
## ist. Der Zombie bewegt sich nur in Physikschritten (60 je Sekunde). Stellt man den Körper öfter,
## sieht man davon nichts, aber jedes Stellen schickt elf neue Lagen an den Renderer.
const POSE_WITH_PHYSICS: float = -1.0
## Läuft die Physik nicht (Test, der nur _process ruft), wird spätestens nach dieser Zeit gestellt.
const POSE_MAX_WAIT: float = 0.05
## Verlangsamt (Trockeneis, Zeitlupen-Kamera): Der Körper wird eisblau.
const SLOW_COLOR: Color = Color(0.45, 0.8, 1.0)
const SLOW_TINT: float = 0.75
const SLOW_GLOW: float = 0.45
## Markiert (Regie-Kamera): eine kleine pinke Raute, die sich über dem Kopf dreht.
const MARK_COLOR: Color = Color(1.0, 0.2, 0.75)
const MARK_SIZE: float = 0.2
const MARK_GAP: float = 0.28
const BAR_WIDTH: float = 0.9
const BAR_HEIGHT: float = 0.09

## Netz und Material der Giftblasen: einmal für alle Zombies (dieselbe Material-Art wie die Flammen).
static var _poison_bubble_mesh: ArrayMesh = null
## Netz und Material der Markierung teilen sich alle Zombies.
static var _mark_mesh: PrismMesh = null
## Netz der Flammen (Höhe 1, wird auf die Körperhöhe gestreckt), für alle Zombies geteilt.
static var _flame_mesh: ArrayMesh = null
## Kamera dieses Bilds (einmal je Bild ermittelt), für die Abstufung der Animation.
static var _view_frame: int = -1
static var _view_valid: bool = false
static var _view_origin: Vector3 = Vector3.ZERO
static var _view_forward: Vector3 = Vector3.FORWARD
## Materialien des Lebensbalkens der Elite (Hintergrund und Füllung), für alle geteilt.
static var _bar_materials: Dictionary = {}

## "walker", "sprinter" oder "elite".
var zombie_type: String = WavePlan.TYPE_WALKER
var max_hp: float = 1.0
var hp: float = 1.0
## Ab dem tödlichen Treffer true. Tote Zombies nehmen keinen Schaden und sterben nie zweimal.
var is_dead: bool = false
## Welle, für die der Zombie erzeugt wurde.
var wave: int = 1
var move_speed: float = 0.0
var attack_damage: float = 0.0
## Körperhöhe in Metern (Elite: 1,3-fach). Grundlage für Kopftreffer.
var body_height: float = Balance.ZOMBIE_HEIGHT
var body_radius: float = Balance.ZOMBIE_RADIUS
## Bestimmt das Aussehen des Exemplars (Variante, Größe, Eigenheiten). -1: zufällig. Nur Optik.
## Vor add_child setzen.
var look_seed: int = -1

var _shape: CollisionShape3D
var _body: ZombieBody
var _flames: MeshInstance3D
var _glow: OmniLight3D
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _agent: NavigationAgent3D
var _base_color: Color = Color.WHITE
var _base_emission: Color = Color.BLACK
var _glow_energy: float = 0.0

var _knockback: Vector3 = Vector3.ZERO
var _lift: float = 0.0
var _separation: Vector3 = Vector3.ZERO
var _separation_left: float = 0.0
var _repath_left: float = 0.0
var _path_valid: bool = false
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _hop_cooldown_left: float = 0.0
var _walk_speed_now: float = 0.0
## Tempo für die Schritte des Körpers: das gewollte Lauftempo, höchstens das wirklich erreichte.
var _anim_speed: float = 0.0
var _burn_dps: float = 0.0
var _burn_left: float = 0.0
var _burn_accum: float = 0.0
var _poison_dps: float = 0.0
var _poison_left: float = 0.0
var _poison_accum: float = 0.0
var _poison_marker: Node3D
## Verlangsamung: Bruchteil, um den der Zombie langsamer läuft (schon mit Elite-Faktor), und
## Restzeit in Sekunden.
var _slow_amount: float = 0.0
var _slow_left: float = 0.0
## Markierung: Mehr-Schaden als Bruchteil und Restzeit in Sekunden.
var _mark_bonus: float = 0.0
var _mark_left: float = 0.0
var _mark_marker: Node3D
var _windup_left: float = -1.0
var _attack_cooldown_left: float = 0.0
var _death_left: float = 0.0

var _anim_time: float = 0.0
var _flicker_phase: float = 0.0
var _flash_left: float = 0.0
var _spawn_grow: float = 0.0
var _strike_left: float = 0.0
var _corpse_pending: bool = false
## Zeit seit dem letzten Stellen des Körpers (Sekunden).
var _pose_delta: float = 0.0
## Seit dem letzten Stellen des Körpers ist ein Physikschritt gelaufen.
var _stepped: bool = true
## Der Körper trägt gerade die Färbung eines laufenden Zustands (Brand, Gift, Treffer).
var _tint_live: bool = false
var _material_dirty: bool = true


## Legt Typ und Welle fest und berechnet daraus Leben, Tempo, Schaden und Größe.
## Vor add_child aufrufen. Unbekannte Typen werden zu "walker".
func setup(type: String, wave_number: int) -> void:
	zombie_type = type if Balance.ZOMBIE_TYPES.has(type) else WavePlan.TYPE_WALKER
	wave = maxi(wave_number, 1)
	var def: Dictionary = Balance.ZOMBIE_TYPES[zombie_type]
	max_hp = WavePlan.zombie_hp(zombie_type, wave)
	hp = max_hp
	move_speed = WavePlan.zombie_speed(zombie_type, wave)
	attack_damage = WavePlan.zombie_damage(zombie_type, wave)
	body_height = Balance.ZOMBIE_HEIGHT * float(def["scale"])
	body_radius = Balance.ZOMBIE_RADIUS * float(def["scale"])


func _ready() -> void:
	if hp <= 0.0 or move_speed <= 0.0:
		setup(zombie_type, wave)
	add_to_group("zombies")
	collision_layer = Balance.LAYER_ZOMBIES
	collision_mask = Balance.MASK_ZOMBIE
	floor_snap_length = 0.25
	_build_body()
	_build_agent()
	# Zeitversatz, damit nicht alle Zombies im selben Bild rechnen und im Gleichschritt wackeln.
	_repath_left = randf() * Balance.ZOMBIE_REPATH_INTERVAL
	_separation_left = randf() * SEPARATION_INTERVAL
	_flicker_phase = randf() * TAU
	_animate(0.0)


func _process(delta: float) -> void:
	_animate(delta)


func _physics_process(delta: float) -> void:
	if is_dead:
		_death_left -= delta
		if _death_left <= 0.0 and not is_queued_for_deletion():
			queue_free()
		return
	_tick_burn(delta)
	if is_dead:
		return
	_tick_poison(delta)
	if is_dead:
		return
	_tick_slow_and_mark(delta)
	var target: Node3D = _find_target()
	var direct: Vector3 = Vector3.ZERO
	var distance: float = INF
	var height_diff: float = 0.0
	if target != null:
		var to_target: Vector3 = target.global_position - global_position
		height_diff = to_target.y
		to_target.y = 0.0
		distance = to_target.length()
		if distance > 0.001:
			direct = to_target / distance
	# Freie Bahn zum Spieler wird nur in Schlagweite gebraucht (ein Strahl kostet, 24 Zombies leben).
	var reach_clear: bool = false
	if target != null and distance <= get_attack_range() + Balance.ZOMBIE_ATTACK_HIT_RANGE_BONUS:
		reach_clear = _has_clear_reach(target)
	# Stehen bleibt er nur, wenn er den Spieler auch erreichen kann. Steht eine Wand dazwischen,
	# folgt er weiter dem Pfad um sie herum, statt dahinter zu parken.
	var stops: bool = reach_clear and distance <= get_attack_range() * Balance.ZOMBIE_ATTACK_STOP_RANGE_FACTOR
	var walk: Vector3 = Vector3.ZERO
	if target != null and not stops:
		# Eine Verlangsamung bremst nur das Laufen, nicht den Schlag.
		var speed: float = move_speed * get_speed_factor()
		if _windup_left >= 0.0:
			walk = direct * speed * Balance.ZOMBIE_ATTACK_WINDUP_SPEED_FACTOR
		else:
			walk = _steer(delta, target.global_position, direct) * speed
	_move(delta, walk)
	_stepped = true
	_face(delta, walk, direct, distance)
	_tick_attack(delta, target, distance, height_diff, reach_clear)


## Der Schadensweg: zieht Leben ab und sendet Events.zombie_damaged (amount unverändert, auch
## beim tödlichen Treffer). Fällt das Leben auf 0: is_dead, Events.zombie_killed, kurze
## Todesanimation, dann queue_free. info siehe Abschnitt 7 ("source" ist Pflicht).
## Tote Zombies und Beträge <= 0 werden ignoriert.
## Ein markierter Zombie (apply_mark) nimmt aus jeder Quelle mehr Schaden: Der Betrag wird hier
## mit get_damage_factor() multipliziert, und zombie_damaged meldet den erhöhten Betrag.
func take_damage(amount: float, info: Dictionary) -> void:
	if is_dead or amount <= 0.0:
		return
	amount *= get_damage_factor()
	hp = maxf(0.0, hp - amount)
	var source: String = String(info.get("source", ""))
	if source != "burn" and source != "poison":
		# Brand färbt ohnehin orange und Gift grün, nur echte Treffer blitzen weiß und lassen den
		# Körper zucken.
		_flash_left = FLASH_TIME
		if is_instance_valid(_body):
			_body.kick(1.0, bool(info.get("headshot", false)))
	_material_dirty = true
	Events.zombie_damaged.emit(self, amount, info)
	if hp <= 0.0 and not is_dead:
		_die(info)


## Setzt den Zombie in Brand: dps ist Schaden je Sekunde in Lebenspunkten (schon fertig
## gerechnet, auch der Elite-Faktor, siehe get_burn_dps). Ein neuer Aufruf erneuert die Dauer,
## der höhere dps gewinnt. Der Brand-Schaden tickt alle Balance.BURN_TICK_INTERVAL s über
## take_damage mit source "burn". Über die ganze Dauer fällt genau dps * duration Schaden an.
func apply_burn(dps: float, duration: float) -> void:
	if is_dead or dps <= 0.0 or duration <= 0.0:
		return
	if _burn_left > 0.0:
		_burn_dps = maxf(_burn_dps, dps)
		_burn_left = maxf(_burn_left, duration)
	else:
		_burn_dps = dps
		_burn_left = duration
		_burn_accum = 0.0
	if not is_instance_valid(_flames) and get_body() != null:
		_build_flames()
	_material_dirty = true


## Rechnet den Brand-Schaden je Sekunde für diesen Zombie aus dem Anteil am Maximal-Leben
## (Upgrade "burn", Schlüssel dps_percent). Elite brennt nur mit Balance.BURN_ELITE_FACTOR.
## Das Ergebnis ist der Wert für apply_burn.
func get_burn_dps(dps_percent: float) -> float:
	var dps: float = maxf(dps_percent, 0.0) * max_hp
	if zombie_type == WavePlan.TYPE_ELITE:
		dps *= Balance.BURN_ELITE_FACTOR
	return dps


## Vergiftet den Zombie (Kantinenessen, Abschnitt 19.1): dps ist Schaden je Sekunde in
## Lebenspunkten, schon fertig gerechnet. Ein neuer Aufruf stellt die Dauer neu, der höhere dps
## gewinnt. Das Gift tickt wie der Brand alle Balance.BURN_TICK_INTERVAL s über take_damage mit
## source "poison", über die ganze Dauer fällt genau dps * duration Schaden an. Gift und Brand
## laufen unabhängig voneinander, auch zugleich. Solange das Gift wirkt, ist der Körper grün
## gefärbt und es steigen grüne Blasen auf.
func apply_poison(dps: float, duration: float) -> void:
	if is_dead or dps <= 0.0 or duration <= 0.0:
		return
	if _poison_left > 0.0:
		_poison_dps = maxf(_poison_dps, dps)
		_poison_left = maxf(_poison_left, duration)
	else:
		_poison_dps = dps
		_poison_left = duration
		_poison_accum = 0.0
	_show_poison_marker(true)
	_material_dirty = true


## Ist der Zombie gerade vergiftet?
func is_poisoned() -> bool:
	return _poison_left > 0.0


## Verlangsamt den Zombie (Trockeneis, Zeitlupen-Kamera, Abschnitt 22): factor ist der Bruchteil,
## um den er langsamer läuft (0.3 = 30 % langsamer), duration die Dauer in Sekunden. Elite spürt
## nur Balance.SLOW_ELITE_FACTOR davon. Mehrere Verlangsamungen addieren sich nicht: Die stärkste
## gilt, und jeder neue Aufruf stellt die Zeit neu (nie kürzer als der Rest). Langsamer als um
## Balance.SLOW_MAX wird kein Zombie. Der Körper ist solange eisblau.
func apply_slow(factor: float, duration: float) -> void:
	if is_dead or factor <= 0.0 or duration <= 0.0:
		return
	var amount: float = factor
	if zombie_type == WavePlan.TYPE_ELITE:
		amount *= Balance.SLOW_ELITE_FACTOR
	amount = minf(amount, Balance.SLOW_MAX)
	if _slow_left > 0.0:
		_slow_amount = maxf(_slow_amount, amount)
		_slow_left = maxf(_slow_left, duration)
	else:
		_slow_amount = amount
		_slow_left = duration
	_material_dirty = true


## Ist der Zombie gerade verlangsamt?
func is_slowed() -> bool:
	return _slow_left > 0.0


## Faktor auf das Lauftempo: 1,0 ohne Verlangsamung, 0,7 bei 30 % (Elite 0,85).
func get_speed_factor() -> float:
	return 1.0 - _slow_amount if _slow_left > 0.0 else 1.0


## Markiert den Zombie (Regie-Kamera, Abschnitt 22): Solange nimmt er aus jeder Quelle
## (1 + bonus) mal Schaden. Mehrere Markierungen addieren sich nicht: Die stärkste gilt, und jeder
## neue Aufruf stellt die Zeit neu (nie kürzer als der Rest). Über dem Kopf dreht sich solange
## eine pinke Raute.
func apply_mark(bonus: float, duration: float) -> void:
	if is_dead or bonus <= 0.0 or duration <= 0.0:
		return
	if _mark_left > 0.0:
		_mark_bonus = maxf(_mark_bonus, bonus)
		_mark_left = maxf(_mark_left, duration)
	else:
		_mark_bonus = bonus
		_mark_left = duration
	_show_mark_marker(true)


## Ist der Zombie gerade markiert?
func is_marked() -> bool:
	return _mark_left > 0.0


## Faktor auf jeden Schaden an diesem Zombie: 1,0 ohne Markierung, sonst 1 + Mehr-Schaden.
func get_damage_factor() -> float:
	return 1.0 + _mark_bonus if _mark_left > 0.0 else 1.0


## Stößt den Zombie weg: impulse ist eine Geschwindigkeit in m/s, die schnell abklingt.
## Solange der Stoß stark ist, kann der Zombie nicht laufen.
func apply_knockback(impulse: Vector3) -> void:
	if is_dead:
		return
	var planar: Vector3 = Vector3(impulse.x, 0.0, impulse.z)
	_knockback += planar
	var lift: float = impulse.y
	if lift <= 0.0:
		lift = minf(planar.length() * Balance.ZOMBIE_KNOCKBACK_LIFT_SHARE, Balance.ZOMBIE_KNOCKBACK_LIFT_MAX)
	_lift = maxf(_lift, lift)
	if is_instance_valid(_body):
		_body.punch()


## Brennt der Zombie gerade?
func is_burning() -> bool:
	return _burn_left > 0.0


## Liegt der Trefferpunkt (Weltkoordinaten) im Kopfbereich? Höher als
## Balance.HEADSHOT_HEIGHT_RATIO der Körperhöhe über den Füßen.
func is_headshot(hit_position: Vector3) -> bool:
	return hit_position.y - global_position.y > body_height * Balance.HEADSHOT_HEIGHT_RATIO


## Weltposition der Körpermitte (Zielpunkt für Drohne, Blitz und Sichtlinien).
func get_center_position() -> Vector3:
	return global_position + Vector3(0.0, body_height * 0.5, 0.0)


## Weltposition der Kopfmitte (liegt sicher im Kopftreffer-Bereich).
func get_head_position() -> Vector3:
	return global_position + Vector3(0.0, body_height * (1.0 - HEAD_RADIUS_SHARE), 0.0)


## Der sichtbare Körper (zombie_body.gd). null, sobald der Zombie tot ist und seinen Körper
## abgegeben hat. Nur für Optik und Tests, nie für Spielregeln.
func get_body() -> Node3D:
	return _body if is_instance_valid(_body) and _body.get_parent() == self else null


## Zahl der MeshInstance3D unter diesem Zombie (jeder sichtbare ist ein Zeichenaufruf).
func get_mesh_count() -> int:
	return _count_meshes(self)


## Entfernung (Füße zu Füßen, waagerecht), ab der dieser Zombie zum Schlag ausholt.
## Größere Zombies reichen um ihren zusätzlichen Körperradius weiter.
func get_attack_range() -> float:
	return Balance.ZOMBIE_ATTACK_RANGE + (body_radius - Balance.ZOMBIE_RADIUS)


## Holt der Zombie gerade zum Schlag aus?
func is_winding_up() -> bool:
	return _windup_left >= 0.0


## Setzt den Zombie an eine neue Stelle (Weltkoordinaten der Füße) und hält ihn an.
## Für die Rettung festhängender oder aus der Welt gefallener Zombies durch den WaveManager.
func teleport_to(world_position: Vector3) -> void:
	if is_dead:
		return
	global_position = world_position
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_lift = 0.0
	_windup_left = -1.0
	_repath_left = 0.0
	_path_valid = false
	_path = PackedVector3Array()
	_path_index = 0
	_spawn_grow = 0.0


## Entfernt den Zombie sofort und ohne Belohnung: kein zombie_killed, keine Punkte, keine Kiste.
## Für das Aufräumen bei einem neuen Lauf und als letzte Rettung gegen einen festhängenden Zombie.
func despawn() -> void:
	if is_dead:
		return
	is_dead = true
	_burn_left = 0.0
	_clear_poison()
	_clear_slow_and_mark()
	remove_from_group("zombies")
	collision_layer = 0
	collision_mask = 0
	queue_free()


func _die(info: Dictionary) -> void:
	is_dead = true
	_death_left = Balance.ZOMBIE_DEATH_TIME
	_burn_left = 0.0
	_burn_accum = 0.0
	_clear_poison()
	_clear_slow_and_mark()
	_windup_left = -1.0
	_knockback = Vector3.ZERO
	remove_from_group("zombies")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if is_instance_valid(_shape):
		_shape.set_deferred("disabled", true)
	if is_instance_valid(_bar):
		_bar.visible = false
	if is_instance_valid(_flames):
		_flames.visible = false
	_start_body_death(info)
	Events.zombie_killed.emit(self, info)


## Lässt den Körper sterben (nur Optik): Die Schadensquelle bestimmt die Todesart, ein
## Kopfschuss reißt den Kopf ab, der Körper fällt vom Treffer weg.
func _start_body_death(info: Dictionary) -> void:
	if not is_instance_valid(_body):
		return
	var push: Vector3 = Vector3.ZERO
	var hit: Variant = info.get("hit_position")
	if hit is Vector3 and is_inside_tree():
		var away: Vector3 = get_center_position() - (hit as Vector3)
		away.y = 0.0
		if away.length_squared() > 0.0025:
			# In den Raum des Zombies gedreht (vorn ist -Z).
			push = away.normalized() * global_transform.basis.orthonormalized()
	_body.start_death(ZombieBody.death_mode_for(String(info.get("source", ""))), bool(info.get("headshot", false)), push)
	_corpse_pending = true


## Brand: sammelt die Zeit und zieht je vollem Tick-Abstand Schaden ab. Läuft der Brand
## zwischen zwei Ticks aus, kommt der Rest anteilig, damit die Summe stimmt.
func _tick_burn(delta: float) -> void:
	if _burn_left <= 0.0:
		return
	var step: float = minf(delta, _burn_left)
	_burn_left -= step
	_burn_accum += step
	var dps: float = _burn_dps
	var ends: bool = _burn_left <= BURN_EPSILON
	var interval: float = Balance.BURN_TICK_INTERVAL
	while _burn_accum >= interval - BURN_EPSILON and not is_dead:
		_burn_accum -= interval
		take_damage(dps * interval, {"source": "burn"})
	if is_dead:
		return
	if ends:
		_burn_left = 0.0
		_burn_dps = 0.0
		var rest: float = _burn_accum
		_burn_accum = 0.0
		_material_dirty = true
		if rest > BURN_EPSILON:
			take_damage(dps * rest, {"source": "burn"})


## Gift: tickt wie der Brand (gleicher Tick-Abstand, Rest am Ende anteilig), mit source "poison".
func _tick_poison(delta: float) -> void:
	if _poison_left <= 0.0:
		return
	var step: float = minf(delta, _poison_left)
	_poison_left -= step
	_poison_accum += step
	var dps: float = _poison_dps
	var ends: bool = _poison_left <= BURN_EPSILON
	var interval: float = Balance.BURN_TICK_INTERVAL
	while _poison_accum >= interval - BURN_EPSILON and not is_dead:
		_poison_accum -= interval
		take_damage(dps * interval, {"source": "poison"})
	if is_dead:
		return
	if ends:
		var rest: float = _poison_accum
		_clear_poison()
		if rest > BURN_EPSILON:
			take_damage(dps * rest, {"source": "poison"})


## Beendet das Gift sofort und nimmt Färbung und Blasen weg (Ablauf, Tod, despawn).
func _clear_poison() -> void:
	_poison_left = 0.0
	_poison_dps = 0.0
	_poison_accum = 0.0
	_show_poison_marker(false)
	_material_dirty = true


## Zeigt oder versteckt die Giftblasen. Sie entstehen erst, wenn ein Zombie zum ersten Mal
## vergiftet wird: Die meisten Zombies brauchen sie nie.
func _show_poison_marker(shown: bool) -> void:
	if not is_instance_valid(_poison_marker):
		if not shown or get_body() == null:
			return
		_build_poison_marker()
	_poison_marker.visible = shown


## Lässt die Zeit von Verlangsamung und Markierung ablaufen.
func _tick_slow_and_mark(delta: float) -> void:
	if _slow_left > 0.0:
		_slow_left -= delta
		if _slow_left <= 0.0:
			_slow_left = 0.0
			_slow_amount = 0.0
			_material_dirty = true
	if _mark_left > 0.0:
		_mark_left -= delta
		if _mark_left <= 0.0:
			_mark_left = 0.0
			_mark_bonus = 0.0
			_show_mark_marker(false)


## Beendet Verlangsamung und Markierung sofort (Tod, despawn).
func _clear_slow_and_mark() -> void:
	_slow_left = 0.0
	_slow_amount = 0.0
	_mark_left = 0.0
	_mark_bonus = 0.0
	_show_mark_marker(false)
	_material_dirty = true


## Zeigt oder versteckt die Raute der Markierung. Sie entsteht erst, wenn ein Zombie zum ersten
## Mal markiert wird.
func _show_mark_marker(shown: bool) -> void:
	if not is_instance_valid(_mark_marker):
		if not shown or not is_inside_tree():
			return
		_build_mark_marker()
	_mark_marker.visible = shown


## Der lebende Spieler oder null.
func _find_target() -> Node3D:
	var target: Node3D = Game.player
	if not is_instance_valid(target) or not target.is_inside_tree():
		return null
	if bool(target.get("is_dead")):
		return null
	return target


## Laufrichtung (waagerechter Einheitsvektor): entlang des Pfads, sonst geradeaus zum Spieler.
## Der NavigationAgent3D berechnet den Pfad, abgelaufen wird er hier Punkt für Punkt. Ein Punkt
## gilt erst als erreicht, wenn der Zombie wirklich dort steht (WAYPOINT_REACHED). So schneidet
## er an Türöffnungen und Kulissen keine Ecke und bleibt nicht an der Wand hängen.
func _steer(delta: float, target_position: Vector3, direct: Vector3) -> Vector3:
	_repath_left -= delta
	if _repath_left <= 0.0:
		_repath_left = Balance.ZOMBIE_REPATH_INTERVAL
		_path = PackedVector3Array()
		_path_index = 0
		if _nav_usable():
			_agent.target_position = target_position
			_agent.get_next_path_position()
			_path = _agent.get_current_navigation_path()
		_path_valid = _path.size() >= 2
	if _path_valid:
		while _path_index < _path.size():
			var waypoint: Vector3 = _path[_path_index]
			var to_waypoint: Vector3 = Vector3(waypoint.x - global_position.x, 0.0, waypoint.z - global_position.z)
			if to_waypoint.length_squared() > WAYPOINT_REACHED * WAYPOINT_REACHED:
				return to_waypoint.normalized()
			_path_index += 1
	# Pfad zu Ende (oder keiner da): das letzte Stück geradeaus.
	return direct


## Gibt es ein Navigationsnetz, das schon einmal abgeglichen wurde? Vorher wäre eine Abfrage
## ein Fehler, ohne Netz (headless-Test) bleibt der Pfad leer.
func _nav_usable() -> bool:
	if not is_instance_valid(_agent) or not _agent.is_inside_tree():
		return false
	var map: RID = _agent.get_navigation_map()
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0


func _move(delta: float, walk: Vector3) -> void:
	_update_separation(delta)
	var knock_speed: float = _knockback.length()
	var control: float = clampf(1.0 - knock_speed / Balance.ZOMBIE_STAGGER_KNOCKBACK_SPEED, 0.0, 1.0)
	var planar: Vector3 = (walk + _separation) * control
	_walk_speed_now = walk.length() * control
	velocity.x = planar.x + _knockback.x
	velocity.z = planar.z + _knockback.z
	if is_on_floor():
		velocity.y = _lift
	else:
		velocity.y -= Balance.GRAVITY * delta
	_lift = 0.0
	_knockback = _knockback.move_toward(Vector3.ZERO, Balance.ZOMBIE_KNOCKBACK_DAMPING * delta)
	move_and_slide()
	# Nur für die Optik: Wer an einer Wand oder im Gedränge hängt, tritt nicht auf der Stelle.
	_anim_speed = minf(_walk_speed_now, Vector2(velocity.x, velocity.z).length())
	_hop_cooldown_left = maxf(0.0, _hop_cooldown_left - delta)
	if _hop_cooldown_left <= 0.0 and control > 0.5 and walk.length_squared() > 0.01:
		# Schneller: Im Gedränge ist die "Wand" fast immer ein anderer Zombie. Der ist für einen
		# Sprung immer zu hoch, die bis zu neun Bewegungsproben in _try_hop wären umsonst (gemessen
		# etwa 130 µs je blockiertem Zombie und Physikschritt, bei 48 Zombies über die Hälfte des
		# ganzen Schritts). Geprobt wird nur noch an Wänden der Welt.
		if is_on_floor() and is_on_wall() and _touches_world_wall():
			_try_hop(walk.normalized())


## Berührt der Zombie nach move_and_slide eine Wand der Welt (Kante, Stufe, Kulisse)? Andere
## Zombies und der Spieler (beide CharacterBody3D) zählen nicht, Boden und Decke auch nicht.
func _touches_world_wall() -> bool:
	for index: int in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(index)
		for contact: int in collision.get_collision_count():
			if absf(collision.get_normal(contact).y) > WALL_NORMAL_MAX_Y:
				continue
			if not (collision.get_collider(contact) is CharacterBody3D):
				return true
	return false


## Abstoßung: schiebt den Zombie von nahen Artgenossen weg, damit sie sich um den Spieler
## verteilen und nicht in einem Punkt stehen. Wird nur alle SEPARATION_INTERVAL s neu berechnet.
func _update_separation(delta: float) -> void:
	_separation_left -= delta
	if _separation_left > 0.0:
		return
	_separation_left = SEPARATION_INTERVAL
	var radius: float = Balance.ZOMBIE_SEPARATION_RADIUS * (body_radius / Balance.ZOMBIE_RADIUS)
	var push: Vector3 = Vector3.ZERO
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		if node == self:
			continue
		var other: Node3D = node as Node3D
		if other == null:
			continue
		var offset: Vector3 = global_position - other.global_position
		if absf(offset.y) > body_height:
			continue
		offset.y = 0.0
		var gap: float = offset.length()
		if gap >= radius:
			continue
		if gap < 0.01:
			# Genau übereinander: Beide rechnen aus ihren IDs dieselbe Achse aus und gehen in
			# entgegengesetzte Richtungen auseinander.
			var own_id: int = get_instance_id()
			var other_id: int = other.get_instance_id()
			var angle: float = float(mini(own_id, other_id) % 360) * TAU / 360.0
			var side: float = 1.0 if own_id < other_id else -1.0
			push += Vector3(cos(angle), 0.0, sin(angle)) * side
		else:
			push += offset / gap * (1.0 - gap / radius)
	_separation = push.limit_length(1.0) * Balance.ZOMBIE_SEPARATION_STRENGTH


## Steht der Zombie vor einer niedrigen Kante (Bühne, Stufe), springt er hinauf. Geprüft wird,
## ob der Weg in einer der Probehöhen frei ist. Wände und andere Zombies sind dafür zu hoch.
func _try_hop(direction: Vector3) -> void:
	var normal: Vector3 = get_wall_normal()
	if direction.dot(Vector3(normal.x, 0.0, normal.z)) > -0.25:
		return
	var probe: Vector3 = direction * maxf(body_radius * 0.5, 0.15)
	if not test_move(global_transform, probe):
		# Nur gestreift (Wandecke, Nachbar): Der Weg ist auf Bodenhöhe frei.
		return
	for height: float in Balance.ZOMBIE_HOP_PROBE_HEIGHTS:
		var from: Transform3D = global_transform
		if test_move(from, Vector3(0.0, height, 0.0)):
			return
		from.origin.y += height
		if not test_move(from, probe):
			_lift = sqrt(2.0 * Balance.GRAVITY * (height + HOP_MARGIN))
			_hop_cooldown_left = Balance.ZOMBIE_HOP_COOLDOWN
			return


## Dreht den Zombie weich: in der Nähe und beim Ausholen zum Spieler, sonst in Laufrichtung.
func _face(delta: float, walk: Vector3, direct: Vector3, distance: float) -> void:
	var look: Vector3 = direct
	if distance > FACE_PLAYER_DISTANCE and _windup_left < 0.0 and walk.length_squared() > 0.01:
		look = walk.normalized()
	if look.length_squared() < 0.0001:
		return
	var yaw: float = atan2(-look.x, -look.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))


## Angriff: in Reichweite ausholen (sichtbar: Arme gehen hoch), nach dem Ausholen trifft der
## Schlag, wenn der Spieler noch nah genug ist, danach Pause. reach_clear sagt, ob zwischen
## Zombie und Spieler keine Wand steht (siehe _has_clear_reach): Ohne freie Bahn holt er nicht
## aus, und ein schon begonnener Schlag geht ins Leere.
func _tick_attack(delta: float, target: Node3D, distance: float, height_diff: float, reach_clear: bool) -> void:
	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	if target == null:
		_windup_left = -1.0
		return
	var in_height: bool = absf(height_diff) <= body_height
	if _windup_left >= 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0:
			_windup_left = -1.0
			_attack_cooldown_left = Balance.ZOMBIE_ATTACK_COOLDOWN
			_strike_left = STRIKE_TIME
			var reach: float = get_attack_range() + Balance.ZOMBIE_ATTACK_HIT_RANGE_BONUS
			if distance <= reach and in_height and reach_clear and target.has_method("take_damage"):
				target.call("take_damage", attack_damage)
	elif _attack_cooldown_left <= 0.0 and distance <= get_attack_range() and in_height and reach_clear:
		_windup_left = Balance.ZOMBIE_ATTACK_WINDUP


## Kann der Zombie den Spieler erreichen, ohne durch die Welt zu schlagen? Zwei Strahlen nur
## gegen die Welt (Balance.MASK_LINE_OF_SIGHT): Körpermitte zu Körpermitte und Kopf zu Augen.
## Ist einer frei, gilt die Bahn als frei. So schützt eine Wand, eine hüfthohe Deckung aber
## nicht (darüber reicht er hinweg). Andere Zombies und die Sperren der Lage 6 zählen nicht.
func _has_clear_reach(target: Node3D) -> bool:
	if not is_inside_tree() or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	var world: World3D = get_world_3d()
	if world == null:
		return false
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return false
	var feet: Vector3 = target.global_position
	var center_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		get_center_position(), feet + Vector3(0.0, Balance.PLAYER_HEIGHT * 0.5, 0.0), Balance.MASK_LINE_OF_SIGHT)
	if space.intersect_ray(center_ray).is_empty():
		return true
	var head_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		get_head_position(), feet + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 0.0), Balance.MASK_LINE_OF_SIGHT)
	return space.intersect_ray(head_ray).is_empty()


# --- Aussehen -------------------------------------------------------------------------------

func _build_body() -> void:
	var def: Dictionary = Balance.ZOMBIE_TYPES[zombie_type]
	var is_elite: bool = zombie_type == WavePlan.TYPE_ELITE
	_base_color = def["color"]
	_base_emission = ZombieLook.base_emission(zombie_type)

	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = body_radius
	capsule.height = body_height
	_shape = CollisionShape3D.new()
	_shape.name = "Shape"
	_shape.shape = capsule
	_shape.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(_shape)

	# Der sichtbare Körper. Sein Zufall kommt nie aus Game.rng: Ein Lauf mit festem Seed bleibt gleich.
	_body = ZombieBody.new()
	_body.setup(zombie_type, look_seed if look_seed >= 0 else randi())
	add_child(_body)
	if is_elite:
		_build_glow()
		_build_health_bar()


## Flammen: zwei Kränze aus Tropfen um den Körper (unten weit, oben eng) in einem einzigen Netz,
## das sich dreht und flackert. Das Netz teilen sich alle Zombies, seine Höhe ist 1: Der Knoten
## streckt es auf die Körperhöhe. Entsteht erst, wenn ein Zombie zum ersten Mal brennt.
func _build_flames() -> void:
	if _flame_mesh == null:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = FLAME_COLOR
		var part: ZombieLook.Part = ZombieLook.Part.new(1.0)
		for ring: int in 2:
			var count: int = 4 if ring == 0 else 3
			for i: int in count:
				var angle: float = TAU * float(i) / float(count) + 0.6 * float(ring)
				var radius: float = 0.17 if ring == 0 else 0.11
				var height: float = (0.3 + 0.07 * float(i)) if ring == 0 else (0.62 + 0.1 * float(i))
				var at: Vector3 = Vector3(cos(angle) * radius, height, sin(angle) * radius)
				# Tropfenform: unten rund, oben spitz.
				part.ball(at, Vector3(0.05, 0.06, 0.05), Color.WHITE)
				part.tube(at + Vector3(0.0, 0.1, 0.0), 0.046, 0.0, 0.16, Color.WHITE, Vector3.ZERO, 1.0, 8)
		_flame_mesh = part.build(material)
	_flames = MeshInstance3D.new()
	_flames.name = "Flames"
	_flames.mesh = _flame_mesh
	_flames.visible = false
	_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flames.scale = Vector3.ONE * body_height
	_body.add_child(_flames)


## Giftblasen: kleine grüne Kugeln, die am Körper aufsteigen (_animate_poison). Je drei Blasen
## sind ein Netz (eine Traube), POISON_CLUSTER_COUNT Trauben steigen versetzt. Netz und Material
## teilen sich alle Zombies, die Höhe des Netzes ist 1 (der Knoten streckt es auf die Körperhöhe).
func _build_poison_marker() -> void:
	if _poison_bubble_mesh == null:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = POISON_BUBBLE_COLOR
		var part: ZombieLook.Part = ZombieLook.Part.new(1.0)
		var sizes: Array[float] = [0.042, 0.03, 0.022]
		for i: int in sizes.size():
			var angle: float = TAU * float(i) / float(sizes.size())
			part.ball(Vector3(cos(angle) * 0.19, 0.07 * float(i - 1), sin(angle) * 0.19), Vector3.ONE * sizes[i], Color.WHITE)
		_poison_bubble_mesh = part.build(material)
	_poison_marker = Node3D.new()
	_poison_marker.name = "Poison"
	_poison_marker.visible = false
	for i: int in POISON_CLUSTER_COUNT:
		var cluster: MeshInstance3D = MeshInstance3D.new()
		cluster.name = "Bubbles%d" % i
		cluster.mesh = _poison_bubble_mesh
		cluster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_poison_marker.add_child(cluster)
	_body.add_child(_poison_marker)
	_animate_poison()


## Markierung: eine kleine, auf der Spitze stehende Pyramide über dem Kopf (über dem Lebensbalken
## der Elite). Sie hängt am Zombie selbst, damit sie beim Zucken des Körpers ruhig bleibt.
func _build_mark_marker() -> void:
	if _mark_mesh == null:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = MARK_COLOR
		_mark_mesh = PrismMesh.new()
		_mark_mesh.size = Vector3(MARK_SIZE, MARK_SIZE * 1.3, MARK_SIZE)
		_mark_mesh.material = material
	_mark_marker = Node3D.new()
	_mark_marker.name = "Mark"
	_mark_marker.visible = false
	var height: float = body_height + MARK_GAP + (0.5 if is_instance_valid(_bar) else 0.0)
	_mark_marker.position = Vector3(0.0, height, 0.0)
	var arrow: MeshInstance3D = MeshInstance3D.new()
	arrow.name = "Arrow"
	arrow.mesh = _mark_mesh
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Spitze nach unten: Sie zeigt auf den Zombie.
	arrow.rotation.x = PI
	_mark_marker.add_child(arrow)
	add_child(_mark_marker)


func _build_glow() -> void:
	_glow_energy = 1.6
	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.light_color = _base_color
	_glow.light_energy = _glow_energy
	_glow.omni_range = body_height * 2.4
	_glow.shadow_enabled = false
	_glow.position = Vector3(0.0, body_height * 0.6, 0.0)
	add_child(_glow)


## Lebensbalken über der Elite: zwei Flächen, die sich in _animate zur Kamera drehen.
func _build_health_bar() -> void:
	_bar = Node3D.new()
	_bar.name = "HealthBar"
	_bar.position = Vector3(0.0, body_height + 0.45, 0.0)
	var back: MeshInstance3D = MeshInstance3D.new()
	back.name = "Back"
	back.mesh = _make_bar_quad(Vector2(BAR_WIDTH + 0.06, BAR_HEIGHT + 0.06), Color(0.05, 0.04, 0.08))
	_bar.add_child(back)
	_bar_fill = MeshInstance3D.new()
	_bar_fill.name = "Fill"
	_bar_fill.mesh = _make_bar_quad(Vector2(BAR_WIDTH, BAR_HEIGHT), Color(1.0, 0.2, 0.25))
	_bar_fill.position = Vector3(0.0, 0.0, 0.01)
	_bar.add_child(_bar_fill)
	add_child(_bar)


func _make_bar_quad(size: Vector2, color: Color) -> QuadMesh:
	if not _bar_materials.has(color):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bar_materials[color] = material
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	quad.material = _bar_materials[color]
	return quad


func _build_agent() -> void:
	_agent = NavigationAgent3D.new()
	_agent.name = "NavAgent"
	_agent.radius = body_radius
	_agent.height = body_height
	_agent.max_speed = maxf(move_speed, 0.1)
	_agent.avoidance_enabled = false
	add_child(_agent)


# --- Animation (nur Optik, ändert nie den Spielzustand) ---------------------------------------

func _animate(delta: float) -> void:
	_anim_time += delta
	_flash_left = maxf(0.0, _flash_left - delta)
	_spawn_grow = move_toward(_spawn_grow, 1.0, delta / SPAWN_GROW_TIME)
	_strike_left = maxf(0.0, _strike_left - delta)
	if is_dead:
		_animate_death()
	elif is_instance_valid(_body):
		_update_material(_animate_alive(delta))


## Bewegt alles Sichtbare am lebenden Zombie. Gibt zurück, ob der Körper in diesem Bild neu
## gestellt wurde: Flammen, Giftblasen, das Licht der Elite und das Flackern der Färbung laufen
## im selben Takt mit (schneller: weniger neue Lagen und Materialwerte für den Renderer).
func _animate_alive(delta: float) -> bool:
	_pose_delta += delta
	var interval: float = _pose_interval()
	var posed: bool = _pose_delta >= interval
	if interval == POSE_WITH_PHYSICS:
		posed = (_stepped and _pose_delta >= 1.0 / ANIM_RATE_NEAR) or _pose_delta >= POSE_MAX_WAIT
	if posed:
		_pose_body(_pose_delta)
		_pose_delta = 0.0
		_stepped = false
	_animate_flames(posed)
	_animate_poison(posed)
	if is_instance_valid(_mark_marker) and _mark_marker.visible:
		_mark_marker.rotation.y = _anim_time * 3.0
	if posed and is_instance_valid(_glow):
		_glow.light_energy = _glow_energy * (1.0 + 0.25 * sin(_anim_time * 5.0))
	if is_instance_valid(_bar):
		_update_health_bar()
	if delta > 0.0 and _burn_left > 0.0:
		_material_dirty = true
	return posed


## Stellt den Körper für dieses Bild. delta ist die Zeit seit dem letzten Stellen.
func _pose_body(delta: float) -> void:
	# Ausholen und Schlag als Fortschritt von 0 bis 1, sonst -1.
	var windup: float = -1.0
	var strike: float = -1.0
	if _windup_left >= 0.0:
		windup = 1.0 - clampf(_windup_left / Balance.ZOMBIE_ATTACK_WINDUP, 0.0, 1.0)
	elif _strike_left > 0.0:
		strike = 1.0 - _strike_left / STRIKE_TIME
	# Rückstoß im Raum des Zombies: Der Körper taumelt in die Richtung, in die er fliegt.
	var stagger: Vector3 = Vector3.ZERO
	if _knockback.length_squared() > 0.0001:
		stagger = (_knockback * global_transform.basis) / Balance.ZOMBIE_STAGGER_KNOCKBACK_SPEED
	_body.pose_alive(delta, _anim_speed, windup, strike, stagger, _spawn_grow)


## Wie viele Sekunden mindestens zwischen zwei Stellungen des Körpers liegen (siehe
## ANIM_NEAR_DISTANCE). 0 = in jedem Bild: ohne Kamera (headless-Test) und bei allem, was man
## genau sehen soll. POSE_WITH_PHYSICS = einmal je Physikschritt (Zombies in der Nähe).
func _pose_interval() -> float:
	if _windup_left >= 0.0 or _strike_left > 0.0 or _spawn_grow < 1.0 or _flash_left > 0.0:
		return 0.0
	var frame: int = Engine.get_process_frames()
	if frame != _view_frame:
		_view_frame = frame
		var viewport: Viewport = get_viewport()
		var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
		_view_valid = camera != null
		if _view_valid:
			var view: Transform3D = camera.global_transform
			_view_origin = view.origin
			_view_forward = -view.basis.z
	if not _view_valid:
		return 0.0
	var offset: Vector3 = global_position - _view_origin
	var distance_squared: float = offset.length_squared()
	if distance_squared < ANIM_NEAR_DISTANCE * ANIM_NEAR_DISTANCE:
		return POSE_WITH_PHYSICS
	if offset.dot(_view_forward) < 0.0:
		return 1.0 / ANIM_RATE_BEHIND
	return 1.0 / (ANIM_RATE_MID if distance_squared < ANIM_MID_DISTANCE * ANIM_MID_DISTANCE else ANIM_RATE_FAR)


## Tod: Der Körper spielt ihn selbst (zombie_body.gd). Hier wird er nur abgegeben, damit er
## liegen bleiben kann, wenn der Zombie nach Balance.ZOMBIE_DEATH_TIME entfernt wird. Das
## Licht der Elite flackert in dieser Zeit aus.
func _animate_death() -> void:
	if _corpse_pending and is_inside_tree():
		_corpse_pending = false
		if is_instance_valid(_body):
			_body.release_as_corpse()
	var progress: float = 1.0 - clampf(_death_left / Balance.ZOMBIE_DEATH_TIME, 0.0, 1.0)
	if is_instance_valid(_glow):
		_glow.light_energy = _glow_energy * (1.0 - progress) * (1.0 + 2.0 * sin(progress * PI))


func _animate_flames(posed: bool = true) -> void:
	if not is_instance_valid(_flames):
		return
	var burning: bool = _burn_left > 0.0
	var appeared: bool = burning and not _flames.visible
	if _flames.visible != burning:
		_flames.visible = burning
	if not burning or not (posed or appeared):
		return
	var flicker: float = 0.9 + 0.3 * sin(_anim_time * 19.0 + _flicker_phase)
	_flames.transform = Transform3D(
			Basis(Vector3.UP, _anim_time * 2.5).scaled(Vector3(body_height, body_height * flicker, body_height)), Vector3.ZERO)


## Giftblasen: Jede Traube steigt versetzt vom Bauch bis über den Kopf, dreht sich und wird dabei
## kleiner. Der Ursprung des Behälters sind die Füße.
func _animate_poison(posed: bool = true) -> void:
	if not is_instance_valid(_poison_marker):
		return
	var poisoned: bool = _poison_left > 0.0 and not is_dead
	var appeared: bool = poisoned and not _poison_marker.visible
	if _poison_marker.visible != poisoned:
		_poison_marker.visible = poisoned
	if not poisoned or not (posed or appeared):
		return
	var index: int = 0
	for child: Node in _poison_marker.get_children():
		var cluster: Node3D = child as Node3D
		if cluster != null:
			var rise: float = fposmod(_anim_time * 0.8 + float(index) / float(POISON_CLUSTER_COUNT), 1.0)
			var size: float = body_height * (1.0 - 0.5 * rise)
			cluster.transform = Transform3D(
					Basis(Vector3.UP, float(index) * 2.4 + _anim_time * 1.7).scaled(Vector3(size, size, size)),
					Vector3(0.0, body_height * (0.3 + 0.72 * rise), 0.0))
		index += 1


func _update_health_bar() -> void:
	var ratio: float = clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	_bar_fill.scale = Vector3(maxf(ratio, 0.001), 1.0, 1.0)
	_bar_fill.position = Vector3(-(1.0 - ratio) * BAR_WIDTH * 0.5, 0.0, 0.01)
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		# Gleiche Ausrichtung wie die Kamera: Die Flächen stehen immer parallel zum Bild.
		_bar.global_transform = Transform3D(camera.global_transform.basis.orthonormalized(), _bar.global_position)


## Färbung des lebenden Körpers aus Verlangsamung (eisblau), Brand (orange, flackernd), Gift
## (grün, pulsierend) und Treffer (hell). Die Farben des Körpers stecken in seinen Netzen, deshalb
## wird hier nicht die Farbe gesetzt, sondern multipliziert (mul) und dazu geleuchtet (emission).
## Ohne Färbung benutzt der Körper das geteilte Material seines Typs. Den toten Körper färbt
## zombie_body.gd selbst dunkel.
## posed: Der Körper wurde in diesem Bild neu gestellt. Das Flackern von Brand und Gift läuft nur
## in diesen Bildern weiter (jede neue Farbe ist ein neuer Materialwert für den Renderer), das
## Aufblitzen bei einem Treffer und jeder Wechsel des Zustands wirken sofort.
func _update_material(posed: bool = true) -> void:
	var burning: bool = _burn_left > 0.0
	var poisoned: bool = _poison_left > 0.0
	var slowed: bool = _slow_left > 0.0
	var flashing: bool = _flash_left > 0.0
	var active: bool = burning or poisoned or flashing
	if not active and not _material_dirty:
		return
	if active and not flashing and not posed and _tint_live:
		return
	_material_dirty = active
	_tint_live = active
	if not active and not slowed:
		_body.clear_tint()
		return
	var mul: Color = Color.WHITE
	var emission: Color = _base_emission
	if slowed:
		# Ruhige Färbung ohne Pulsieren: Sie muss nicht in jedem Bild neu gesetzt werden.
		mul = mul.lerp(SLOW_COLOR, SLOW_TINT)
		emission = emission.lerp(SLOW_COLOR, SLOW_GLOW)
	if burning:
		var flicker: float = 0.5 + 0.5 * sin(_anim_time * 23.0 + _flicker_phase)
		mul = mul.lerp(BURN_COLOR, BURN_TINT)
		emission = emission.lerp(BURN_COLOR, BURN_GLOW + BURN_GLOW_FLICKER * flicker)
	if poisoned:
		# Brennt der Zombie zugleich, mischen sich beide Farben: Man sieht beides.
		var pulse: float = 0.5 + 0.5 * sin(_anim_time * 5.0 + _flicker_phase)
		mul = mul.lerp(POISON_COLOR, POISON_TINT)
		emission = emission.lerp(POISON_COLOR, POISON_GLOW + POISON_GLOW_PULSE * pulse)
	if flashing:
		# Nicht bis ganz weiß: Unter Dauerfeuer bliebe sonst nur ein weißer Fleck ohne Form.
		var flash: float = clampf(_flash_left / FLASH_TIME, 0.0, 1.0) * FLASH_STRENGTH
		mul = mul.lerp(Color(FLASH_BRIGHTEN, FLASH_BRIGHTEN, FLASH_BRIGHTEN), flash)
		emission = emission.lerp(Color.WHITE, flash * FLASH_GLOW)
	_body.set_tint(mul, emission)


func _count_meshes(node: Node) -> int:
	var count: int = 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		count += _count_meshes(child)
	return count
