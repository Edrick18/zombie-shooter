extends Node3D
## Modul: Spieler (scripts/game/player).
## Sichtbare Flamme der Heißen Phase (WeaponDefs.MODE_FLAME). Reine Optik: Die Waffensteuerung
## ruft aim(from, to), solange gefeuert wird (jedes Bild neu, die Flamme folgt Mündung und Blick),
## und stop(), sobald der Abzug los ist. Die Flammen sind Partikel in Weltkoordinaten: Was schon
## fliegt, brennt nach dem Loslassen noch aus. Der Knoten rechnet in Weltkoordinaten: Er hängt
## unter einem Knoten ohne eigene Lage (der Waffensteuerung).
##
## Aufbau:
##   FlameFx
##   ├─ Particles  CPUParticles3D, fliegt im Kegel von der Mündung bis zum Ende der Flamme
##   ├─ Core       CPUParticles3D, heller, schmaler Kern in der Mitte der Flamme (kürzer)
##   ├─ Smoke      CPUParticles3D, dünne Rauchfahne, die am Ende der Flamme aufsteigt
##   └─ Light      warmes Punktlicht in der Flamme
##
## Einbinden mit: const FlameFx := preload("res://scripts/game/player/flame_fx.gd")

const FxPool := preload("res://scripts/game/fx/fx_pool.gd")

const PARTICLE_AMOUNT: int = 44
## Flugzeit eines Flammenballs von der Mündung bis zum Ende der Flamme.
const PARTICLE_LIFETIME: float = 0.4
## Die langsamsten Flammenbälle fliegen mit diesem Anteil des vollen Tempos.
const SLOW_SPEED_FACTOR: float = 0.7
## Größe eines Flammenballs an der Mündung, als Anteil seiner Größe am Ende.
const START_SIZE_FACTOR: float = 0.08
## Die Flammenbälle am Ende füllen diesen Anteil des Kegel-Durchmessers.
const END_SIZE_FACTOR: float = 0.5
const SMALL_SIZE_FACTOR: float = 0.6
const MIN_END_SIZE: float = 0.25
## Flammen steigen leicht (m/s²).
const RISE: float = 1.4
const LIGHT_COLOR: Color = Color(1.0, 0.55, 0.15)
const LIGHT_ENERGY: float = 2.6
const LIGHT_RANGE: float = 7.0
## Das Licht sitzt bei diesem Anteil der Flammenlänge.
const LIGHT_AT: float = 0.45
## Farbverlauf über das Leben eines Flammenballs: hell an der Mündung, rot und durchsichtig am Ende.
## Die Deckkraft ist niedrig: Die Bälle überlagern sich (additiv), und die Zombies in der Flamme
## sollen zu sehen bleiben.
const RAMP_OFFSETS: Array[float] = [0.0, 0.18, 0.5, 1.0]
const RAMP_COLORS: Array[Color] = [
	Color(1.0, 0.9, 0.5, 0.4), Color(1.0, 0.66, 0.14, 0.22),
	Color(1.0, 0.3, 0.05, 0.11), Color(0.5, 0.06, 0.0, 0.0),
]
## Kern: wenige kleine, fast weiße Bälle in einem schmalen Kegel, die nur den vorderen Teil der
## Flamme erreichen. So hat die Flamme eine heiße Mitte, ohne dass ihr Ende heller wird.
const CORE_AMOUNT: int = 14
const CORE_LIFETIME: float = 0.26
const CORE_REACH: float = 0.6
const CORE_SPREAD_FACTOR: float = 0.4
const CORE_SIZE_FACTOR: float = 0.4
const CORE_RAMP_OFFSETS: Array[float] = [0.0, 0.4, 1.0]
const CORE_RAMP_COLORS: Array[Color] = [
	Color(1.0, 1.0, 0.85, 0.24), Color(1.0, 0.85, 0.35, 0.14), Color(1.0, 0.5, 0.1, 0.0),
]
## Rauchfahne: wenige dunkle, durchscheinende Scheiben, die am Ende der Flamme aufsteigen. Wenig
## Deckkraft und kurzes Leben: Der Rauch zeigt, wo die Flamme endet, und verdeckt nichts.
const SMOKE_AMOUNT: int = 10
const SMOKE_LIFETIME: float = 0.7
## Der Rauch entsteht bei diesem Anteil der Flammenlänge.
const SMOKE_AT: float = 0.8
const SMOKE_RISE: float = 2.2
const SMOKE_RAMP_OFFSETS: Array[float] = [0.0, 0.25, 1.0]
const SMOKE_RAMP_COLORS: Array[Color] = [
	Color(0.3, 0.26, 0.32, 0.0), Color(0.3, 0.26, 0.32, 0.3), Color(0.24, 0.2, 0.3, 0.0),
]
const MIN_LENGTH: float = 0.05

static var _ball_mesh: SphereMesh = null
static var _color_ramp: Gradient = null
static var _core_ramp: Gradient = null
static var _smoke_ramp: Gradient = null
static var _size_curve: Curve = null

## Halber Öffnungswinkel des Kegels in Grad (WeaponDefs.cone_deg).
var cone_deg: float = 14.0

var _particles: CPUParticles3D
var _core: CPUParticles3D
var _smoke: CPUParticles3D
var _light: OmniLight3D
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _active: bool = false


func _init() -> void:
	name = "FlameFx"
	_particles = _emitter("Particles", PARTICLE_AMOUNT, PARTICLE_LIFETIME, _ball(), _gradient_ramp())
	_particles.gravity = Vector3(0.0, RISE, 0.0)
	_particles.scale_amount_curve = _size_ramp()
	_core = _emitter("Core", CORE_AMOUNT, CORE_LIFETIME, _ball(), _core_gradient())
	_core.gravity = Vector3(0.0, RISE, 0.0)
	_core.scale_amount_curve = _size_ramp()
	# Der Rauch ist ein eigener Knoten am Ende der Flamme: Er steigt nach oben, nicht nach vorn.
	_smoke = _emitter("Smoke", SMOKE_AMOUNT, SMOKE_LIFETIME, FxPool.blob_mesh(), _smoke_gradient())
	_smoke.top_level = true
	_smoke.direction = Vector3.UP
	_smoke.spread = 35.0
	_smoke.initial_velocity_min = SMOKE_RISE * 0.5
	_smoke.initial_velocity_max = SMOKE_RISE
	_smoke.gravity = Vector3(0.0, 1.0, 0.0)
	_smoke.scale_amount_curve = _size_ramp()
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = LIGHT_COLOR
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)


## Richtet die Flamme von from (Mündung) nach to (Ende der Flamme, Weltkoordinaten) und lässt sie
## brennen.
func aim(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	_active = true
	var offset: Vector3 = to - from
	var length: float = offset.length()
	if length < MIN_LENGTH:
		_particles.emitting = false
		_core.emitting = false
		_smoke.emitting = false
		_light.visible = false
		return
	var direction: Vector3 = offset / length
	var axes: Basis = _basis_along(direction)
	# Die Partikel fliegen entlang -Z des Knotens.
	transform = Transform3D(Basis(-axes.x, axes.y, -axes.z), from)
	var speed: float = length / PARTICLE_LIFETIME
	_particles.spread = cone_deg
	_particles.initial_velocity_max = speed
	_particles.initial_velocity_min = speed * SLOW_SPEED_FACTOR
	var end_size: float = maxf(MIN_END_SIZE, 2.0 * length * tan(deg_to_rad(cone_deg)) * END_SIZE_FACTOR)
	_particles.scale_amount_max = end_size
	_particles.scale_amount_min = end_size * SMALL_SIZE_FACTOR
	_particles.emitting = true
	var core_speed: float = length * CORE_REACH / CORE_LIFETIME
	_core.spread = cone_deg * CORE_SPREAD_FACTOR
	_core.initial_velocity_max = core_speed
	_core.initial_velocity_min = core_speed * SLOW_SPEED_FACTOR
	_core.scale_amount_max = end_size * CORE_SIZE_FACTOR
	_core.scale_amount_min = end_size * CORE_SIZE_FACTOR * SMALL_SIZE_FACTOR
	_core.emitting = true
	_smoke.scale_amount_max = end_size * 0.8
	_smoke.scale_amount_min = end_size * 0.45
	_smoke.emitting = true
	if is_inside_tree():
		_smoke.global_position = from + offset * SMOKE_AT
		_light.global_position = from + offset * LIGHT_AT
	_light.visible = true


## Dreht die Flamme ab. Was schon fliegt, brennt aus.
func stop() -> void:
	_active = false
	_particles.emitting = false
	_core.emitting = false
	_smoke.emitting = false
	_light.visible = false


## Brennt die Flamme gerade?
func is_active() -> bool:
	return _active


## Anfang und Ende der gezeigten Flamme (Weltkoordinaten).
func get_from() -> Vector3:
	return _from


func get_to() -> Vector3:
	return _to


## Ein Partikel-Knoten der Flamme in Weltkoordinaten, noch aus.
func _emitter(node_name: String, amount: int, lifetime: float, mesh: Mesh, ramp: Gradient) -> CPUParticles3D:
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = node_name
	particles.emitting = false
	particles.local_coords = false
	particles.amount = amount
	particles.lifetime = lifetime
	particles.randomness = 0.25
	particles.mesh = mesh
	particles.direction = Vector3.FORWARD
	particles.color_ramp = ramp
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles


## Rechtwinklige Achsen, deren z-Achse entlang direction (Einheitsvektor) zeigt.
static func _basis_along(direction: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis: Vector3 = up.cross(direction).normalized()
	var y_axis: Vector3 = direction.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, direction)


## Flammenball: Kugel mit Durchmesser 1 und leuchtendem Material, dessen Farbe aus dem Verlauf
## der Partikel kommt. Geteilt.
static func _ball() -> SphereMesh:
	if _ball_mesh == null:
		_ball_mesh = SphereMesh.new()
		_ball_mesh.radius = 0.5
		_ball_mesh.height = 1.0
		_ball_mesh.radial_segments = 10
		_ball_mesh.rings = 5
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		# Nur die Außenseite: So leuchtet ein Ball nicht doppelt, und wer in der Flamme steht,
		# sieht das Spiel statt einer hellen Wand.
		material.cull_mode = BaseMaterial3D.CULL_BACK
		material.disable_receive_shadows = true
		_ball_mesh.material = material
	return _ball_mesh


static func _gradient_ramp() -> Gradient:
	if _color_ramp == null:
		_color_ramp = _gradient(RAMP_OFFSETS, RAMP_COLORS)
	return _color_ramp


static func _core_gradient() -> Gradient:
	if _core_ramp == null:
		_core_ramp = _gradient(CORE_RAMP_OFFSETS, CORE_RAMP_COLORS)
	return _core_ramp


static func _smoke_gradient() -> Gradient:
	if _smoke_ramp == null:
		_smoke_ramp = _gradient(SMOKE_RAMP_OFFSETS, SMOKE_RAMP_COLORS)
	return _smoke_ramp


static func _gradient(offsets: Array[float], colors: Array[Color]) -> Gradient:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	return gradient


## Größe über das Leben: klein an der Mündung, voll am Ende.
static func _size_ramp() -> Curve:
	if _size_curve == null:
		_size_curve = Curve.new()
		_size_curve.add_point(Vector2(0.0, START_SIZE_FACTOR))
		_size_curve.add_point(Vector2(1.0, 1.0))
	return _size_curve
