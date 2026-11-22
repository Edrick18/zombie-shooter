extends Node3D
## Modul: Zombies (scripts/game/zombies).
## Der sichtbare Körper eines Zombies: Knoten, Bewegung, Einfärben, Tod. Reine Optik, ändert nie
## den Spielzustand und benutzt nie Game.rng (nur einen eigenen Zufall aus look_seed und randf).
## Formen, Farben und Maße stehen in zombie_look.gd.
##
## Aufbau (entsteht in setup, der Ursprung sind die Füße):
##   Body (dieses Skript)
##   └─ Rig        Node3D: Größe des Exemplars, Stauchen bei Treffern, Umfallen beim Tod
##       └─ Hips   Node3D auf Hüfthöhe
##           ├─ Torso  Rumpf, dreht sich um die Hüfte (Vorbeugen, Schwanken, Verdrehen)
##           │   ├─ Head ─ Eyes     Der Ursprung von Head ist die Kopfmitte.
##           │   ├─ ArmL ─ Fore     Oberarm (Schultergelenk) und Unterarm mit Hand (Ellbogen)
##           │   └─ ArmR ─ Fore
##           ├─ LegL ─ Shin         Oberschenkel (Hüftgelenk) und Unterschenkel mit Schuh (Knie)
##           └─ LegR ─ Shin
## Das sind elf MeshInstance3D, also elf Zeichenaufrufe je Zombie.
##
## Bewegung (pose_alive, jedes Bild vom Zombie aufgerufen):
## - Die Kopfmitte steht fest über den Füßen auf Look.HEAD_CENTER_SHARE der Körperhöhe, also
##   mitten im Kopftreffer-Bereich. Aus ihr und der Neigung des Rumpfs ergibt sich die Hüfte,
##   die Beine werden von der Hüfte zu ihren Fußpunkten gestellt (Knie beugt sich passend).
## - Der Schritt läuft mit der echten Strecke: Tempo geteilt durch Schrittlänge. Steht der Zombie,
##   stehen die Beine. Arme pendeln gegengleich.
## - Ausholen, Schlag, Zucken bei Treffern und Taumeln beim Rückstoß drehen nur den Rumpf um die
##   Hüfte und die Arme. Dabei verlässt der Kopf kurz seinen Platz, wie schon beim alten Körper.
##
## Tod (start_death): Der Körper spielt seinen Tod selbst zu Ende. Der Zombie gibt ihn dafür mit
## release_as_corpse ab: Er hängt dann im Behälter "ZombieCorpses" neben dem Behälter der
## Zombies, hat keine Kollision, blockiert nichts und verschwindet nach CORPSE_TIME von selbst.

const Balance := preload("res://scripts/core/balance.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")
const Look := preload("res://scripts/game/zombies/zombie_look.gd")

## Todesarten: nach hinten umfallen, nach vorn zusammensacken, in Teile zerfallen.
const DEATH_FALL: int = 0
const DEATH_COLLAPSE: int = 1
const DEATH_BURST: int = 2

## So lange bleibt ein toter Körper insgesamt zu sehen (Sekunden ab dem tödlichen Treffer):
## umfallen, liegen bleiben, im Boden versinken. Der Zombie selbst (Kollision, Gruppe, Knoten)
## ist wie bisher nach Balance.ZOMBIE_DEATH_TIME weg, das hier betrifft nur die Optik.
const CORPSE_TIME: float = 1.6
## Liegen schon MAX_CORPSES Körper herum, verschwindet jeder weitere schneller.
const CORPSE_TIME_CROWDED: float = 0.7
const MAX_CORPSES: int = 8
## Die letzten Sekunden von CORPSE_TIME: Der Körper versinkt im Boden.
const CORPSE_SINK_TIME: float = 0.35
const CORPSE_HOLDER_NAME: String = "ZombieCorpses"
const CORPSE_GROUP: String = "zombie_corpses"

## Zufall je Exemplar: Breite und Höhe (unterhalb des Kopfs) weichen um diese Anteile ab. Der
## Kopf behält seine Höhe und höchstens seine Größe, damit die Trefferzone stimmt.
const WIDTH_VARIATION: float = 0.07
const HEIGHT_VARIATION: float = 0.035
const HEAD_SHRINK_MAX: float = 0.07

## Längster Zeitschritt für die Federn (bei langen Bildern bleibt die Rechnung stabil).
const MAX_STEP: float = 1.0 / 30.0
## Ab diesem Tempo (m/s bei Größe 1) läuft der Schritt mit voller Weite.
const FULL_STRIDE_SPEED: float = 0.5
const MOVE_BLEND_RATE: float = 5.0
## Zucken: Feder, die Rumpfneigung (x = seitlich, y = nach hinten) zurück in die Ruhe zieht.
const WOBBLE_STIFFNESS: float = 150.0
const WOBBLE_DAMPING: float = 9.0
const WOBBLE_MAX: float = 0.5
const HIT_KICK_BACK: float = 3.4
const HIT_KICK_SIDE: float = 2.2
const HEAD_KICK_TIME: float = 0.22
const HEAD_KICK_ANGLE: float = 0.55
const PUNCH_TIME: float = 0.14
const PUNCH_WIDEN: float = 0.07
const PUNCH_SQUASH: float = 0.05
## Taumeln: Neigung des Rumpfs bei vollem Rückstoß, Glättung des Rückstoßes.
const STAGGER_LEAN: float = 0.45
const STAGGER_ROLL: float = 0.4
const STAGGER_SMOOTH: float = 14.0
## Angriff: Armwinkel (0 = hängt, PI/2 = waagerecht nach vorn, mehr = über den Kopf).
const ARM_RAISED: float = 2.75
const ARM_SLAM: float = 0.8
const WINDUP_LEAN: float = 0.2
const STRIKE_LEAN: float = -0.5
const STRIKE_LUNGE: float = 0.06
const WINDUP_CROUCH: float = 0.025
## Wie stark der Kopf die Neigung des Rumpfs ausgleicht (1 = Blick bleibt waagerecht).
const HEAD_LEVEL: float = 0.85
## Tod.
const FALL_TIME: float = 0.42
const FALL_ANGLE: float = 1.5
const FALL_BOUNCE: float = 0.07
const FALL_BOUNCE_TIME: float = 0.22
const DEATH_FLASH_TIME: float = 0.09
const DEATH_DARKEN_TIME: float = 0.5
const DEATH_TINT: Color = Color(0.5, 0.46, 0.46)
const CHUNK_GRAVITY: float = 18.0
const CHUNK_REST_SPEED: float = 1.6
const CHUNK_BOUNCE: float = 0.3
const CHUNK_FRICTION: float = 0.55
const CHUNK_SETTLE_TIME: float = 0.16
## Schadensquellen, die den Körper zerreißen bzw. zusammensacken lassen (info.source).
const BURST_SOURCES: Array[String] = ["explosion", "shockwave", "mine"]
const COLLAPSE_SOURCES: Array[String] = ["burn", "poison"]

## Zahl der toten Körper, die gerade noch zu sehen sind.
static var _live_corpses: int = 0


## Ein loses Körperteil nach dem Tod: fliegt, prallt einmal ab, bleibt liegen.
class Chunk:
	extends RefCounted
	var node: Node3D
	var velocity: Vector3 = Vector3.ZERO
	var axis: Vector3 = Vector3.RIGHT
	var spin: float = 0.0
	var radius: float = 0.1
	## true: legt sich am Boden flach hin (Rumpf, Arme, Beine). Der Kopf bleibt, wie er landet.
	var flat: bool = true
	var landed: bool = false
	var settle: float = 0.0
	var from_turn: Quaternion = Quaternion.IDENTITY
	var to_turn: Quaternion = Quaternion.IDENTITY
	var size: Vector3 = Vector3.ONE


var zombie_type: String = WavePlan.TYPE_WALKER
## Farb- und Detail-Variante (0 bis Look.VARIANT_COUNT - 1).
var variant: int = 0
## Körperhöhe in Metern.
var body_height: float = Balance.ZOMBIE_HEIGHT

var _rig: Node3D
var _hips: Node3D
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _eyes: MeshInstance3D
var _arm_l: MeshInstance3D
var _arm_r: MeshInstance3D
var _fore_l: MeshInstance3D
var _fore_r: MeshInstance3D
var _leg_l: MeshInstance3D
var _leg_r: MeshInstance3D
var _shin_l: MeshInstance3D
var _shin_r: MeshInstance3D
## Alle Teile, die mit dem Körper eingefärbt werden (alles außer den Augen).
var _tinted: Array[MeshInstance3D] = []
var _tint: StandardMaterial3D = null
var _tint_on: bool = false

# Maße in Metern bzw. Radiant (aus Look.get_metrics).
var _size: Vector3 = Vector3.ONE
var _rig_scale: Vector3 = Vector3.ONE
var _scale_factor: float = 1.0
var _neck: Vector3 = Vector3.ZERO
var _head_y: float = 0.0
var _head_z: float = 0.0
var _hip_rest: float = 0.0
var _hip_rest_z: float = 0.0
var _hip_max: float = 0.0
var _thigh: float = 0.0
var _shin: float = 0.0
var _ankle: float = 0.0
var _leg_min: float = 0.0
var _leg_max: float = 0.0
var _foot_center: float = 0.0
var _lean_rest: float = 0.0
var _run_lean: float = 0.0
var _stride_base: float = 1.0
var _stride_gain: float = 0.0
var _stance: float = 0.6
var _max_step: float = 0.3
var _lift: float = 0.0
var _bob: float = 0.0
var _bob_shift: float = 0.0
var _sway: float = 0.0
var _roll_amp: float = 0.0
var _twist_amp: float = 0.0
var _arm_rest: float = 0.0
var _arm_swing: float = 0.0
var _elbow_rest: float = 0.0
var _elbow_swing: float = 0.0
var _arm_out: float = 0.0
var _chest_depth: float = 0.1

# Eigenheiten des Exemplars.
var _reach_l: float = 0.0
var _reach_r: float = 0.0
var _limp: float = 0.0
var _tilt: float = 0.0
var _phase: float = 0.0
var _twitchy: float = 0.0

# Laufende Animation.
var _time: float = 0.0
var _gait: float = 0.0
var _move: float = 0.0
var _punch: float = 0.0
var _head_kick: float = 0.0
var _wobble: Vector2 = Vector2.ZERO
var _wobble_vel: Vector2 = Vector2.ZERO
var _stagger: Vector3 = Vector3.ZERO

# Tod.
var _dead: bool = false
var _death_mode: int = DEATH_FALL
var _death_time: float = 0.0
var _death_side: float = 1.0
var _life: float = CORPSE_TIME
var _counted: bool = false
var _released: bool = false
var _corpse_origin: Vector3 = Vector3.ZERO
var _chunks: Array[Chunk] = []
var _from_rotations: Array[Vector3] = []
var _from_hips: Vector3 = Vector3.ZERO
var _joints: Array[Node3D] = []


func _init() -> void:
	name = "Body"
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _counted:
			_counted = false
			_live_corpses = maxi(0, _live_corpses - 1)
		if _tint != null:
			Look.release_tint_material(_tint)
			_tint = null


## Baut den Körper für diesen Typ. look_seed bestimmt Variante, Größe und Eigenheiten des
## Exemplars (gleiche Zahl = gleiches Aussehen). Vor add_child aufrufen.
func setup(type: String, look_seed: int) -> void:
	zombie_type = type if Look.METRICS.has(type) else WavePlan.TYPE_WALKER
	body_height = Look.type_height(zombie_type)
	_scale_factor = body_height / Balance.ZOMBIE_HEIGHT
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(look_seed)
	variant = rng.randi_range(0, Look.VARIANT_COUNT - 1)
	var width: float = 1.0 + rng.randf_range(-WIDTH_VARIATION, WIDTH_VARIATION)
	var height: float = 1.0 + rng.randf_range(-HEIGHT_VARIATION, HEIGHT_VARIATION)
	var head_size: float = 1.0 - rng.randf_range(0.0, HEAD_SHRINK_MAX)
	_size = Vector3(width, height, width)
	_rig_scale = _size
	_phase = rng.randf() * TAU
	_gait = rng.randf()
	_death_side = -1.0 if rng.randf() < 0.5 else 1.0
	_tilt = rng.randf_range(-1.0, 1.0)
	if zombie_type == WavePlan.TYPE_WALKER:
		# Schlurfer: Manche strecken einen Arm oder beide vor, die meisten ziehen ein Bein nach.
		var pose: float = rng.randf()
		_reach_l = 1.0 if pose < 0.25 or pose > 0.9 else 0.0
		_reach_r = 1.0 if pose > 0.65 else 0.0
		_limp = 0.0 if rng.randf() < 0.3 else (-1.0 if rng.randf() < 0.5 else 1.0)
		_tilt *= 0.3
	elif zombie_type == WavePlan.TYPE_SPRINTER:
		_twitchy = 1.0
		_tilt *= 0.12
	else:
		_tilt *= 0.06
	_read_metrics(Look.get_metrics(zombie_type), rng.randf_range(-0.05, 0.03))
	_build(Look.get_look(zombie_type, variant), head_size)
	pose_alive(0.0, 0.0, -1.0, -1.0, Vector3.ZERO, 1.0)


## Zahl der MeshInstance3D dieses Körpers (jeder ist ein Zeichenaufruf).
func get_mesh_count() -> int:
	return _count_meshes(self)


## Der Knoten des Kopfs. Sein Ursprung ist die Kopfmitte.
func get_head() -> MeshInstance3D:
	return _head


## Ein Körperteil nach Namen: "torso", "head", "eyes", "arm_l", "arm_r", "fore_l", "fore_r",
## "leg_l", "leg_r", "shin_l", "shin_r". null bei unbekanntem Namen.
func get_part(part_name: String) -> MeshInstance3D:
	match part_name:
		"torso": return _torso
		"head": return _head
		"eyes": return _eyes
		"arm_l": return _arm_l
		"arm_r": return _arm_r
		"fore_l": return _fore_l
		"fore_r": return _fore_r
		"leg_l": return _leg_l
		"leg_r": return _leg_r
		"shin_l": return _shin_l
		"shin_r": return _shin_r
	return null


## Größe des Exemplars als Faktoren auf Breite, Höhe und Tiefe (um 1).
func get_size_factors() -> Vector3:
	return _size


## Ist der Körper tot (spielt seinen Tod oder liegt)?
func is_corpse() -> bool:
	return _dead


## Treffer: Der Rumpf zuckt nach hinten und zur Seite, bei headshot schnellt der Kopf zurück.
func kick(strength: float, headshot: bool) -> void:
	if _dead:
		return
	_punch = 1.0
	_wobble_vel += Vector2(randf_range(-1.0, 1.0) * HIT_KICK_SIDE, HIT_KICK_BACK) * strength
	if headshot:
		_head_kick = 1.0


## Stoß ohne Treffer (Rückstoß): Der Körper staucht sich kurz.
func punch() -> void:
	_punch = 1.0


## Färbt den ganzen Körper: mul multipliziert die Farben, emission leuchtet dazu. Die Augen
## behalten ihre Farbe. Der Körper bekommt dafür ein eigenes Material derselben Art.
func set_tint(mul: Color, emission: Color) -> void:
	if _tint == null:
		_tint = Look.take_tint_material(zombie_type)
	if not _tint_on:
		_tint_on = true
		for part: MeshInstance3D in _tinted:
			part.material_override = _tint
	_tint.albedo_color = mul
	_tint.emission = emission


## Nimmt die Färbung weg: Der Körper benutzt wieder das geteilte Material seines Typs.
func clear_tint() -> void:
	if not _tint_on:
		return
	_tint_on = false
	for part: MeshInstance3D in _tinted:
		part.material_override = null


func is_tinted() -> bool:
	return _tint_on


## Stellt den lebenden Körper für dieses Bild.
##   speed    Lauftempo in m/s (bestimmt Schrittfolge und Schrittweite)
##   windup   Fortschritt des Ausholens von 0 bis 1, sonst -1
##   strike   Fortschritt des Schlags von 0 bis 1, sonst -1
##   stagger  Rückstoß im Raum des Zombies (x = nach rechts, z = nach hinten), Länge 1 = voll
##   grow     Aufrichten nach dem Erscheinen von 0 bis 1
func pose_alive(delta: float, speed: float, windup: float, strike: float, stagger: Vector3, grow: float) -> void:
	if _dead:
		return
	_time += delta
	var step: float = minf(delta, MAX_STEP)
	_punch = move_toward(_punch, 0.0, delta / PUNCH_TIME)
	_head_kick = move_toward(_head_kick, 0.0, delta / HEAD_KICK_TIME)
	var flail: float = 0.0
	if stagger != Vector3.ZERO or _stagger != Vector3.ZERO:
		_stagger = _stagger.lerp(stagger.limit_length(1.0), 1.0 - exp(-STAGGER_SMOOTH * delta))
		flail = _stagger.length()
		if flail < 0.003 and stagger == Vector3.ZERO:
			_stagger = Vector3.ZERO
			flail = 0.0

	# --- Schritt: läuft mit der gelaufenen Strecke ---
	var pace: float = speed / _scale_factor
	var stride: float = (_stride_base + _stride_gain * pace) * _scale_factor
	_gait = fposmod(_gait + speed * delta / stride + flail * 2.5 * delta, 1.0)
	_move = move_toward(_move, clampf(pace / FULL_STRIDE_SPEED, 0.0, 1.0), delta * MOVE_BLEND_RATE)
	var left: Vector2 = _foot_cycle(_gait)
	var right: Vector2 = _foot_cycle(fposmod(_gait + 0.5, 1.0))
	var amp: float = maxf(minf(stride * _stance * 0.5, _max_step) * _move, flail * _max_step * 0.4)
	var lift: float = _lift * maxf(_move, flail)
	# +1: linkes Bein vorn, -1: rechtes Bein vorn.
	var swing: float = (right.x - left.x) * 0.5
	var weight: float = cos((_gait - _stance * 0.5) * TAU)
	var idle: float = sin(_time * 1.3 + _phase)
	var idle_slow: float = sin(_time * 0.83 + _phase * 2.0)

	# --- Zucken und Taumeln: Feder um die Ruhelage ---
	if flail > 0.0 or _wobble != Vector2.ZERO or _wobble_vel != Vector2.ZERO:
		var wobble_target: Vector2 = Vector2(-_stagger.x * STAGGER_ROLL, _stagger.z * STAGGER_LEAN)
		_wobble_vel += ((wobble_target - _wobble) * WOBBLE_STIFFNESS - _wobble_vel * WOBBLE_DAMPING) * step
		_wobble = (_wobble + _wobble_vel * step).limit_length(WOBBLE_MAX)
		if flail <= 0.0 and _wobble.length_squared() < 0.000001 and _wobble_vel.length_squared() < 0.0001:
			_wobble = Vector2.ZERO
			_wobble_vel = Vector2.ZERO

	# --- Rumpf ---
	var base_lean: float = _lean_rest + _run_lean * _move + 0.02 * idle
	var react_lean: float = _wobble.y
	var roll: float = _roll_amp * weight * _move + 0.025 * idle_slow + _wobble.x
	var twist: float = _twist_amp * swing * _move
	var crouch: float = 0.0
	var lunge: float = 0.0

	# --- Arme: pendeln gegengleich zu den Beinen ---
	var arm_l: float = _arm_rest - _arm_swing * swing * _move + 0.05 * idle_slow
	var arm_r: float = _arm_rest + _arm_swing * swing * _move - 0.05 * idle_slow
	var elbow_l: float = _elbow_rest + _elbow_swing * maxf(-swing, -0.4) * _move
	var elbow_r: float = _elbow_rest + _elbow_swing * maxf(swing, -0.4) * _move
	var out_l: float = _arm_out
	var out_r: float = _arm_out
	if _reach_l > 0.0:
		arm_l = lerpf(arm_l, 1.3 + 0.12 * idle, _reach_l)
		elbow_l = lerpf(elbow_l, 0.3 + 0.15 * idle_slow, _reach_l)
	if _reach_r > 0.0:
		arm_r = lerpf(arm_r, 1.2 - 0.12 * idle, _reach_r)
		elbow_r = lerpf(elbow_r, 0.35 - 0.15 * idle_slow, _reach_r)
	if flail > 0.01:
		# Taumeln: Die Arme rudern.
		arm_l = lerpf(arm_l, 1.5 + 0.7 * sin(_time * 17.0), flail)
		arm_r = lerpf(arm_r, 1.3 + 0.7 * sin(_time * 15.0 + 2.0), flail)
		out_l += 0.6 * flail
		out_r += 0.6 * flail

	# --- Angriff ---
	if windup >= 0.0:
		# Ausholen: Arme hoch über den Kopf, Rumpf lehnt sich zurück. Das ist die Warnung.
		var raise: float = 1.0 - (1.0 - windup) * (1.0 - windup)
		arm_l = lerpf(arm_l, ARM_RAISED, raise)
		arm_r = lerpf(arm_r, ARM_RAISED - 0.15, raise)
		elbow_l = lerpf(elbow_l, 0.5, raise)
		elbow_r = lerpf(elbow_r, 0.5, raise)
		out_l = lerpf(out_l, 0.3, raise)
		out_r = lerpf(out_r, 0.3, raise)
		react_lean += WINDUP_LEAN * raise
		crouch = WINDUP_CROUCH * body_height * raise
	elif strike >= 0.0:
		# Schlag: Arme sausen herunter, der Rumpf wirft sich vor und richtet sich wieder auf.
		if strike < 0.3:
			var slam: float = strike / 0.3
			slam *= slam
			arm_l = lerpf(ARM_RAISED, ARM_SLAM, slam)
			arm_r = lerpf(ARM_RAISED - 0.15, ARM_SLAM - 0.1, slam)
			elbow_l = lerpf(0.5, 0.2, slam)
			elbow_r = elbow_l
			out_l = lerpf(0.3, 0.05, slam)
			out_r = out_l
			react_lean += lerpf(WINDUP_LEAN, STRIKE_LEAN, slam)
			lunge = -STRIKE_LUNGE * body_height * slam
			crouch = WINDUP_CROUCH * body_height
		else:
			var recover: float = (strike - 0.3) / 0.7
			recover = recover * recover * (3.0 - 2.0 * recover)
			arm_l = lerpf(ARM_SLAM, arm_l, recover)
			arm_r = lerpf(ARM_SLAM - 0.1, arm_r, recover)
			elbow_l = lerpf(0.2, elbow_l, recover)
			elbow_r = lerpf(0.2, elbow_r, recover)
			out_l = lerpf(0.05, out_l, recover)
			out_r = lerpf(0.05, out_r, recover)
			react_lean += STRIKE_LEAN * (1.0 - recover)
			lunge = -STRIKE_LUNGE * body_height * (1.0 - recover)
			crouch = WINDUP_CROUCH * body_height * (1.0 - recover)

	# --- Kopf fest, Hüfte ergibt sich aus der Neigung ---
	var limp_dip: float = 0.0
	if _limp != 0.0:
		# Das nachgezogene Bein: Der Körper sackt ab, wenn es das Gewicht trägt.
		limp_dip = maxf(0.0, -_limp * weight) * _bob * 1.6 * _move
	var bounce: float = 0.5 + 0.5 * cos((_gait - _bob_shift) * TAU * 2.0)
	var head_y: float = _head_y - _bob * bounce * _move - limp_dip - crouch
	var head_z: float = _head_z + lunge
	var sin_lean: float = sin(base_lean)
	var cos_lean: float = cos(base_lean)
	var hip_y: float = minf(head_y - (_neck.y * cos_lean - _neck.z * sin_lean), _hip_max)
	var hip_z: float = head_z - (_neck.y * sin_lean + _neck.z * cos_lean)
	var hip_x: float = -_sway * weight * _move
	_hips.position = Vector3(hip_x, hip_y, hip_z)
	var lean: float = base_lean + react_lean
	_torso.rotation = Vector3(lean, twist, roll)
	var look: float = 0.0
	if _twitchy > 0.0:
		# Sprinter: Der Kopf ruckt unruhig hin und her.
		look = 0.22 * sin(_time * 7.0 + _phase) * sin(_time * 2.3 + _phase)
	_head.rotation = Vector3(
			-lean * HEAD_LEVEL + HEAD_KICK_ANGLE * _head_kick + 0.04 * idle,
			-twist * 0.7 + look,
			-roll * 0.6 + _tilt + 0.06 * idle_slow)
	_arm_l.rotation = Vector3(arm_l - lean, 0.0, -out_l)
	_arm_r.rotation = Vector3(arm_r - lean, 0.0, out_r)
	_fore_l.rotation = Vector3(elbow_l, 0.0, 0.0)
	_fore_r.rotation = Vector3(elbow_r, 0.0, 0.0)

	# --- Beine: von der Hüfte zum Fußpunkt ---
	var amp_l: float = amp
	var amp_r: float = amp
	var lift_l: float = lift
	var lift_r: float = lift
	if _limp < 0.0:
		amp_l *= 0.55
		lift_l *= 0.15
	elif _limp > 0.0:
		amp_r *= 0.55
		lift_r *= 0.15
	_pose_leg(_leg_l, _shin_l, hip_y, hip_z, _ankle + left.y * lift_l, _foot_center + left.x * amp_l, -0.04)
	_pose_leg(_leg_r, _shin_r, hip_y, hip_z, _ankle + right.y * lift_r, _foot_center + right.x * amp_r, 0.04)

	# --- Größe: Exemplar, Stauchen bei Treffern, Aufrichten nach dem Erscheinen ---
	var wide: float = 1.0 + PUNCH_WIDEN * _punch
	var tall: float = 1.0 - PUNCH_SQUASH * _punch
	if grow < 1.0:
		var eased: float = _ease_out_back(grow)
		wide *= lerpf(0.7, 1.0, eased)
		tall *= maxf(eased, 0.05)
	var wanted: Vector3 = Vector3(_size.x * wide, _size.y * tall, _size.z * wide)
	if not wanted.is_equal_approx(_rig_scale):
		_rig_scale = wanted
		_rig.scale = wanted


## Beginnt den Tod. mode ist DEATH_FALL, DEATH_COLLAPSE oder DEATH_BURST (siehe death_mode_for),
## headshot lässt den Kopf wegfliegen, push ist die Richtung des tödlichen Stoßes im Raum des
## Zombies (Länge egal, null = keine). Ab jetzt spielt der Körper selbst weiter (_process).
func start_death(mode: int, headshot: bool, push: Vector3) -> void:
	if _dead:
		return
	_dead = true
	_death_mode = mode
	_death_time = 0.0
	_counted = true
	_live_corpses += 1
	_life = CORPSE_TIME if _live_corpses <= MAX_CORPSES else CORPSE_TIME_CROWDED
	_joints = [_torso, _head, _arm_l, _fore_l, _arm_r, _fore_r, _leg_l, _shin_l, _leg_r, _shin_r]
	_from_rotations.clear()
	for joint: Node3D in _joints:
		_from_rotations.append(joint.rotation)
	_from_hips = _hips.position
	_rig.scale = _size
	_rig_scale = _size
	_eyes.material_override = Look.dead_eye_material()
	# Ein liegender Körper braucht keinen Schatten.
	for part: MeshInstance3D in _tinted:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var away: Vector3 = Vector3(push.x, 0.0, push.z)
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3(0.0, 0.0, 1.0)
	if _death_mode == DEATH_FALL and away.z < -0.5:
		# Von hinten getroffen: Der Körper fällt nach vorn, also weiter vom Treffer weg.
		_death_mode = DEATH_COLLAPSE
	if is_inside_tree():
		if _death_mode == DEATH_BURST:
			var center: Vector3 = Vector3(0.0, body_height * 0.5, 0.0)
			for limb: MeshInstance3D in [_head, _arm_l, _arm_r, _leg_l, _leg_r, _torso]:
				var chunk: Chunk = _make_chunk(limb, limb != _head)
				var outward: Vector3 = (chunk.node.position - center)
				outward.y = 0.0
				outward = outward.normalized() if outward.length_squared() > 0.0001 else Vector3.ZERO
				chunk.velocity = outward * randf_range(1.5, 3.0) + away * randf_range(1.5, 3.0) \
						+ Vector3(0.0, randf_range(2.5, 4.5), 0.0)
		elif headshot:
			var head_chunk: Chunk = _make_chunk(_head, false)
			head_chunk.velocity = away * randf_range(1.6, 2.8) + Vector3(_death_side * randf_range(0.4, 1.4), randf_range(3.2, 4.2), 0.0)
	_apply_death_tint()
	set_process(true)


## Todesart für eine Schadensquelle (info.source): Explosionen zerreißen, Brand und Gift lassen
## zusammensacken, alles andere wirft nach hinten um.
static func death_mode_for(source: String) -> int:
	if BURST_SOURCES.has(source):
		return DEATH_BURST
	if COLLAPSE_SOURCES.has(source):
		return DEATH_COLLAPSE
	return DEATH_FALL


## Hängt den toten Körper vom Zombie ab und in den Behälter "ZombieCorpses" (neben dem Behälter
## der Zombies). Dort spielt er seinen Tod zu Ende und räumt sich selbst weg. false, wenn das
## gerade nicht geht (nicht tot, nicht im Baum).
func release_as_corpse() -> bool:
	if not _dead or _released or not is_inside_tree():
		return false
	var owner_node: Node = get_parent()
	var holder: Node3D = _find_corpse_holder(owner_node)
	if holder == null:
		return false
	var world: Transform3D = global_transform
	owner_node.remove_child(self)
	holder.add_child(self)
	global_transform = world
	_corpse_origin = position
	_released = true
	add_to_group(CORPSE_GROUP)
	# Ein neuer Lauf räumt liegen gebliebene Körper sofort weg.
	if not Events.run_started.is_connected(queue_free):
		Events.run_started.connect(queue_free)
	return true


func _process(delta: float) -> void:
	if not _dead:
		return
	_death_time += delta
	if _death_time >= _life:
		set_process(false)
		queue_free()
		return
	if _death_mode != DEATH_BURST:
		_animate_fall()
	_animate_chunks(delta)
	_apply_death_tint()
	# Am Ende versinkt alles im Boden.
	var sink: float = clampf((_death_time - (_life - CORPSE_SINK_TIME)) / CORPSE_SINK_TIME, 0.0, 1.0)
	if sink > 0.0:
		position = _corpse_origin + Vector3(0.0, -sink * sink * body_height * 0.3, 0.0)
		scale = Vector3.ONE * (1.0 - 0.4 * sink)


# --- Aufbau ---------------------------------------------------------------------------------------

func _read_metrics(m: Dictionary, lean_offset: float) -> void:
	var h: float = body_height
	_lean_rest = float(m["lean"]) + lean_offset * (1.0 if zombie_type == WavePlan.TYPE_WALKER else 0.4)
	_run_lean = m["run_lean"]
	_thigh = float(m["thigh"]) * h
	_shin = float(m["shin"]) * h
	_ankle = float(m["ankle"]) * h
	_leg_max = (_thigh + _shin) * 0.995
	_leg_min = absf(_thigh - _shin) + (_thigh + _shin) * 0.35
	_hip_max = _ankle + _leg_max
	_hip_rest = float(m["hip_rest"]) * h
	# Ziel der Kopfmitte im Raum des Rigs. Das Rig ist um _size gestreckt, deshalb geteilt:
	# In der Welt steht die Kopfmitte so bei jedem Exemplar auf derselben Höhe.
	_head_y = Look.HEAD_CENTER_SHARE * h / _size.y
	_head_z = float(m["head_z"]) * h
	# Halslänge des Exemplars: so, dass die Kopfmitte im Stand genau auf ihrem Ziel sitzt.
	var neck_z: float = float(m["neck_z"]) * h
	_neck = Vector3(0.0, (_head_y - _hip_rest + neck_z * sin(_lean_rest)) / cos(_lean_rest), neck_z)
	_hip_rest_z = _head_z - (_neck.y * sin(_lean_rest) + _neck.z * cos(_lean_rest))
	_foot_center = _hip_rest_z * 0.5
	_stride_base = m["stride_base"]
	_stride_gain = m["stride_gain"]
	_stance = m["stance"]
	_max_step = float(m["max_step"]) * h
	_lift = float(m["lift"]) * h
	_bob = float(m["bob"]) * h
	_bob_shift = _stance * 0.5 if _stance < 0.5 else 0.0
	_sway = float(m["sway"]) * h
	_roll_amp = m["roll"]
	_twist_amp = m["twist"]
	_arm_rest = m["arm_rest"]
	_arm_swing = m["arm_swing"]
	_elbow_rest = m["elbow_rest"]
	_elbow_swing = m["elbow_swing"]
	_arm_out = m["arm_out"]
	_chest_depth = float(m["chest_d"]) * h


func _build(look: Dictionary, head_size: float) -> void:
	var m: Dictionary = Look.get_metrics(zombie_type)
	var h: float = body_height
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.scale = _size
	add_child(_rig)
	_hips = Node3D.new()
	_hips.name = "Hips"
	_rig.add_child(_hips)
	_torso = _add_part(_hips, "Torso", look["torso"], Vector3.ZERO)
	_head = _add_part(_torso, "Head", look["head"], _neck)
	# Der Kopf macht die Streckung des Rigs rückgängig: Er ist bei jedem Exemplar höchstens so
	# groß wie der Kopftreffer-Bereich.
	_head.scale = Vector3(head_size / _size.x, head_size / _size.y, head_size / _size.z)
	_eyes = _add_part(_head, "Eyes", look["eyes"], Vector3.ZERO)
	var shoulder: Vector3 = Vector3(float(m["shoulder_half"]) * h, float(m["shoulder_up"]) * h, 0.0)
	var elbow: Vector3 = Vector3(0.0, -float(m["upper_arm"]) * h, 0.0)
	_arm_l = _add_part(_torso, "ArmL", look["arm_l"], Vector3(-shoulder.x, shoulder.y, 0.0))
	_arm_r = _add_part(_torso, "ArmR", look["arm_r"], shoulder)
	_fore_l = _add_part(_arm_l, "Fore", look["fore_l"], elbow)
	_fore_r = _add_part(_arm_r, "Fore", look["fore_r"], elbow)
	var hip_half: float = float(m["hip_half"]) * h
	var knee: Vector3 = Vector3(0.0, -_thigh, 0.0)
	_leg_l = _add_part(_hips, "LegL", look["thigh_l"], Vector3(-hip_half, 0.0, 0.0))
	_leg_r = _add_part(_hips, "LegR", look["thigh_r"], Vector3(hip_half, 0.0, 0.0))
	_shin_l = _add_part(_leg_l, "Shin", look["shin_l"], knee)
	_shin_r = _add_part(_leg_r, "Shin", look["shin_r"], knee)
	_tinted = [_torso, _head, _arm_l, _fore_l, _arm_r, _fore_r, _leg_l, _shin_l, _leg_r, _shin_r]
	# Schatten kosten je Netz einen weiteren Zeichenaufruf: Nur Rumpf, Kopf und Beine werfen einen.
	for part: MeshInstance3D in [_eyes, _arm_l, _fore_l, _arm_r, _fore_r]:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_part(parent: Node3D, part_name: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = at
	parent.add_child(part)
	return part


func _count_meshes(node: Node) -> int:
	var count: int = 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		count += _count_meshes(child)
	return count


# --- Bewegung -------------------------------------------------------------------------------------

## Ein Fuß im Lauf eines Doppelschritts (u von 0 bis 1). x: -1 = ganz vorn, +1 = ganz hinten,
## y: Anheben von 0 bis 1. Erst steht der Fuß und wandert unter dem Körper nach hinten, dann
## schwingt er angehoben wieder nach vorn.
func _foot_cycle(u: float) -> Vector2:
	if u < _stance:
		return Vector2(u / _stance * 2.0 - 1.0, 0.0)
	var w: float = (u - _stance) / (1.0 - _stance)
	return Vector2(1.0 - 2.0 * w * w * (3.0 - 2.0 * w), sin(w * PI))


## Stellt ein Bein so, dass der Knöchel den Fußpunkt erreicht: Oberschenkel und Knie ergeben
## sich aus dem Abstand von Hüfte und Fuß (Dreieck aus Ober- und Unterschenkel). Das Knie beugt
## sich nach vorn. splay spreizt das Bein leicht nach außen.
func _pose_leg(thigh: Node3D, shin: Node3D, hip_y: float, hip_z: float, foot_y: float, foot_z: float, splay: float) -> void:
	var down: float = hip_y - foot_y
	var back: float = foot_z - hip_z
	var reach: float = clampf(sqrt(down * down + back * back), _leg_min, _leg_max)
	var gamma: float = atan2(back, down)
	var alpha: float = acos(clampf((_thigh * _thigh + reach * reach - _shin * _shin) / (2.0 * _thigh * reach), -1.0, 1.0))
	var beta: float = acos(clampf((_shin * _shin + reach * reach - _thigh * _thigh) / (2.0 * _shin * reach), -1.0, 1.0))
	thigh.rotation = Vector3(alpha - gamma, 0.0, splay)
	# Knie: Außenwinkel des Dreiecks = Summe der beiden anderen Winkel.
	shin.rotation = Vector3(-(alpha + beta), 0.0, 0.0)


## Weiches Überschwingen (0 -> 1), für das Aufrichten beim Erscheinen.
func _ease_out_back(value: float) -> float:
	var shifted: float = clampf(value, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * shifted * shifted * shifted + 1.70158 * shifted * shifted


# --- Tod ------------------------------------------------------------------------------------------

## Umfallen: Das Rig kippt um die Füße (nach hinten oder nach vorn), die Glieder erschlaffen.
func _animate_fall() -> void:
	var fall: float = clampf(_death_time / FALL_TIME, 0.0, 1.0)
	var eased: float = fall * fall
	var bounce: float = 0.0
	if _death_time > FALL_TIME:
		var after: float = (_death_time - FALL_TIME) / FALL_BOUNCE_TIME
		if after < 1.0:
			bounce = sin(after * PI) * FALL_BOUNCE
	var forward: bool = _death_mode == DEATH_COLLAPSE
	var direction: float = -1.0 if forward else 1.0
	var angle: float = direction * (FALL_ANGLE * eased - bounce)
	var turned: Basis = Basis.from_euler(Vector3(angle, 0.0, _death_side * 0.2 * eased))
	# Liegt der Körper, trägt ihn der Rücken (oder die Brust): so weit über dem Boden.
	var rest_height: float = (_chest_depth * 1.1 + absf(_hip_rest_z) * (0.2 if forward else 1.0)) * sin(absf(angle))
	_rig.transform = Transform3D(turned * Basis.from_scale(_size), Vector3(0.0, rest_height, 0.0))
	var limp: float = fall * fall * (3.0 - 2.0 * fall)
	var fling: float = sin(fall * PI)
	var side: float = _death_side
	var targets: Array[Vector3] = []
	if forward:
		# Auf dem Bauch: Arme nach vorn geworfen, Gesicht zur Seite, ein Bein angewinkelt.
		targets = [
			Vector3(-0.08, 0.0, side * 0.08), Vector3(0.1, side * 1.1, 0.0),
			Vector3(2.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.0), Vector3(2.2, 0.0, 0.7), Vector3(0.9, 0.0, 0.0),
			Vector3(-0.12, 0.0, -0.2), Vector3(-0.2, 0.0, 0.0), Vector3(0.2, 0.0, 0.35), Vector3(-1.2, 0.0, 0.0),
		]
	else:
		# Auf dem Rücken: Arme zur Seite gebreitet, ein Knie angezogen.
		targets = [
			Vector3(0.05, 0.0, side * 0.1), Vector3(0.25, side * 0.5, 0.0),
			Vector3(0.35 + 1.3 * fling, 0.0, -1.2), Vector3(0.5, 0.0, 0.0),
			Vector3(0.15 + 1.5 * fling, 0.0, 1.0), Vector3(0.25, 0.0, 0.0),
			Vector3(0.55, 0.0, -0.12), Vector3(-1.0, 0.0, 0.0), Vector3(0.08, 0.0, 0.22), Vector3(-0.2, 0.0, 0.0),
		]
	for i: int in _joints.size():
		var joint: Node3D = _joints[i]
		# Abgetrennte Teile (Kopf nach einem Kopfschuss) fliegen selbst.
		if joint.get_parent() == self:
			continue
		joint.rotation = _from_rotations[i].lerp(targets[i], limp)
	_hips.position = _from_hips.lerp(Vector3(0.0, _hip_rest, _hip_rest_z * 0.3), limp)


## Löst ein Körperteil aus dem Rig und hängt es direkt an den Körper (gleiche Stelle in der Welt).
func _make_chunk(part: Node3D, flat: bool) -> Chunk:
	var local: Transform3D = global_transform.affine_inverse() * part.global_transform
	part.get_parent().remove_child(part)
	add_child(part)
	part.transform = local
	var chunk: Chunk = Chunk.new()
	chunk.node = part
	chunk.flat = flat
	chunk.radius = body_height * (Look.HEAD_RADIUS_SHARE * 0.9 if not flat else 0.05)
	if part == _torso:
		chunk.radius = _chest_depth
	chunk.axis = Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)).normalized()
	chunk.spin = randf_range(5.0, 11.0) * (1.0 if randf() < 0.5 else -1.0)
	chunk.size = local.basis.get_scale()
	_chunks.append(chunk)
	return chunk


func _animate_chunks(delta: float) -> void:
	for chunk: Chunk in _chunks:
		var node: Node3D = chunk.node
		if not chunk.landed:
			chunk.velocity.y -= CHUNK_GRAVITY * delta
			var at: Vector3 = node.position + chunk.velocity * delta
			var turned: Basis = Basis(chunk.axis, chunk.spin * delta) * node.transform.basis
			if at.y <= chunk.radius:
				at.y = chunk.radius
				if chunk.velocity.y < -CHUNK_REST_SPEED:
					chunk.velocity = Vector3(chunk.velocity.x * CHUNK_FRICTION, -chunk.velocity.y * CHUNK_BOUNCE,
							chunk.velocity.z * CHUNK_FRICTION)
					chunk.spin *= 0.5
				else:
					chunk.landed = true
					chunk.from_turn = turned.get_rotation_quaternion()
					chunk.to_turn = _flat_turn(turned) if chunk.flat else chunk.from_turn
			node.transform = Transform3D(turned, at)
		elif chunk.settle < 1.0:
			chunk.settle = minf(1.0, chunk.settle + delta / CHUNK_SETTLE_TIME)
			var turn: Quaternion = chunk.from_turn.slerp(chunk.to_turn, chunk.settle)
			node.transform = Transform3D(Basis(turn) * Basis.from_scale(chunk.size), node.position)


## Drehung, bei der die Längsachse (Y) des Teils flach auf dem Boden liegt, möglichst nah an
## der jetzigen Lage.
func _flat_turn(current: Basis) -> Quaternion:
	var along: Vector3 = Vector3(current.y.x, 0.0, current.y.z)
	along = along.normalized() if along.length_squared() > 0.0001 else Vector3(1.0, 0.0, 0.0)
	var up: Vector3 = Vector3.UP if current.z.y >= 0.0 else Vector3.DOWN
	var across: Vector3 = along.cross(up)
	return Basis(across, along, up).get_rotation_quaternion()


## Farbe des toten Körpers: erst kurz hell, dann dunkel und ohne Leuchten.
func _apply_death_tint() -> void:
	var dark: float = clampf(_death_time / DEATH_DARKEN_TIME, 0.0, 1.0)
	var mul: Color = Color.WHITE.lerp(DEATH_TINT, dark)
	var emission: Color = Look.base_emission(zombie_type).lerp(Color.BLACK, dark)
	if _death_time < DEATH_FLASH_TIME:
		var flash: float = 1.0 - _death_time / DEATH_FLASH_TIME
		emission = emission.lerp(Color.WHITE, flash * 0.45)
	set_tint(mul, emission)


## Behälter für tote Körper: neben dem Behälter der Zombies. Entsteht beim ersten Toten.
func _find_corpse_holder(zombie: Node) -> Node3D:
	if zombie == null:
		return null
	var zombies_root: Node = zombie.get_parent()
	if zombies_root == null:
		return null
	var base: Node = zombies_root.get_parent()
	if base == null:
		base = zombies_root
	var holder: Node3D = base.get_node_or_null(CORPSE_HOLDER_NAME) as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = CORPSE_HOLDER_NAME
		base.add_child(holder)
	return holder
