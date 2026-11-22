extends Node3D
## Modul: Spieler (scripts/game/player).
## Sichtbarer Dauerstrahl des Rotlichts (WeaponDefs.MODE_BEAM). Reine Optik: Die Waffensteuerung
## ruft aim(from, to), solange gefeuert wird (jedes Bild neu, der Strahl folgt Mündung und Blick),
## und stop(), sobald der Strahl aus ist. Der Knoten rechnet in Weltkoordinaten: Er hängt unter
## einem Knoten ohne eigene Lage (der Waffensteuerung).
##
## Aufbau:
##   BeamFx
##   ├─ Halo    weiter, schwacher Schein um den Strahl
##   ├─ Glow    breiter, durchscheinender Mantel
##   ├─ Core    dünner, fast weißer Kern
##   ├─ Pulse0… kurze helle Stücke, die von der Mündung zum Einschlag laufen (der Strahl "fließt")
##   ├─ Flare   Leuchtpunkt am Einschlag
##   ├─ Ring    flimmernder Kranz um den Einschlag
##   └─ Light   rotes Punktlicht am Einschlag
## Am Einschlag springen dazu Funken aus dem Vorrat von fx.gd weg (höchstens einer Schub alle
## SPARK_INTERVAL Sekunden).
##
## Einbinden mit: const BeamFx := preload("res://scripts/game/player/beam_fx.gd")

const Fx := preload("res://scripts/game/fx/fx.gd")
const FxPool := preload("res://scripts/game/fx/fx_pool.gd")

const HALO_COLOR: Color = Color(1.0, 0.1, 0.05, 0.1)
const GLOW_COLOR: Color = Color(1.0, 0.08, 0.05, 0.42)
const CORE_COLOR: Color = Color(1.0, 0.8, 0.72, 0.9)
const PULSE_COLOR: Color = Color(1.0, 0.5, 0.4, 0.6)
const FLARE_COLOR: Color = Color(1.0, 0.25, 0.15, 0.8)
const RING_COLOR: Color = Color(1.0, 0.5, 0.35, 0.4)
const SPARK_COLOR: Color = Color(1.0, 0.6, 0.4, 1.0)
const LIGHT_COLOR: Color = Color(1.0, 0.2, 0.12)
const HALO_WIDTH: float = 0.2
const GLOW_WIDTH: float = 0.1
const CORE_WIDTH: float = 0.03
## Schein und Mantel beginnen erst so weit vor der Mündung (höchstens dieser Anteil der Länge),
## bis dahin steht nur der dünne Kern: Direkt vor der Kamera wäre der breite Strahl ein Balken.
const WIDE_LEAD: float = 1.1
const WIDE_LEAD_SHARE: float = 0.3
const FLARE_SIZE: float = 0.3
const RING_SIZE: float = 0.55
const LIGHT_ENERGY: float = 2.2
const LIGHT_RANGE: float = 5.0
## Der Strahl flimmert: Seine Breite schwankt um diesen Anteil mit dieser Frequenz (1/s).
const FLICKER_AMOUNT: float = 0.22
const FLICKER_SPEED: float = 38.0
## Helle Stücke, die den Strahl entlanglaufen: Zahl, Länge, Breite, Tempo (m/s). Sie beginnen
## erst PULSE_LEAD Meter vor der Mündung, damit direkt vor der Kamera nichts flackert.
const PULSE_COUNT: int = 3
const PULSE_LENGTH: float = 0.7
const PULSE_WIDTH: float = 0.07
const PULSE_SPEED: float = 30.0
const PULSE_LEAD: float = 1.2
## Funken am Einschlag: Abstand der Schübe in Sekunden und Funken je Schub.
const SPARK_INTERVAL: float = 0.07
const SPARKS_PER_BURST: int = 2
## Das Licht sitzt so weit vor dem Einschlag, damit es die getroffene Wand beleuchtet.
const LIGHT_BACKOFF: float = 0.25
## Kürzere Strahlen werden nicht gezeichnet.
const MIN_LENGTH: float = 0.05

static var _box_mesh: BoxMesh = null
static var _sphere_mesh: SphereMesh = null
static var _ring_mesh: TorusMesh = null
static var _materials: Dictionary = {}

var _halo: MeshInstance3D
var _glow: MeshInstance3D
var _core: MeshInstance3D
var _flare: MeshInstance3D
var _ring: MeshInstance3D
var _pulses: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _active: bool = false
var _time: float = 0.0
var _spark_left: float = 0.0


func _init() -> void:
	name = "BeamFx"
	_halo = _part("Halo", _box(), HALO_COLOR)
	_glow = _part("Glow", _box(), GLOW_COLOR)
	_core = _part("Core", _box(), CORE_COLOR)
	for index: int in PULSE_COUNT:
		_pulses.append(_part("Pulse%d" % index, _box(), PULSE_COLOR))
	_flare = _part("Flare", _sphere(), FLARE_COLOR)
	_ring = _part("Ring", _ring_shape(), RING_COLOR)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = LIGHT_COLOR
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.shadow_enabled = false
	add_child(_light)
	visible = false


func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	_apply()
	_spark_left -= delta
	if _spark_left <= 0.0:
		_spark_left = SPARK_INTERVAL
		_emit_sparks()


## Zeigt den Strahl von from nach to (Weltkoordinaten).
func aim(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	_active = true
	visible = true
	_apply()


## Schaltet den Strahl aus.
func stop() -> void:
	_active = false
	visible = false


## Ist der Strahl gerade an?
func is_active() -> bool:
	return _active


## Anfang und Ende des gezeigten Strahls (Weltkoordinaten).
func get_from() -> Vector3:
	return _from


func get_to() -> Vector3:
	return _to


func _apply() -> void:
	var offset: Vector3 = _to - _from
	var length: float = offset.length()
	if length < MIN_LENGTH:
		_halo.visible = false
		_glow.visible = false
		_core.visible = false
		for pulse: MeshInstance3D in _pulses:
			pulse.visible = false
		return
	_halo.visible = true
	_glow.visible = true
	_core.visible = true
	var direction: Vector3 = offset / length
	var axes: Basis = _basis_along(direction)
	var flicker: float = 1.0 + sin(_time * FLICKER_SPEED) * FLICKER_AMOUNT
	var middle: Vector3 = (_from + _to) * 0.5
	var lead: float = minf(WIDE_LEAD, length * WIDE_LEAD_SHARE)
	var wide_middle: Vector3 = _from + direction * (lead + (length - lead) * 0.5)
	_halo.transform = Transform3D(
		Basis(axes.x * HALO_WIDTH, axes.y * HALO_WIDTH, axes.z * (length - lead)), wide_middle)
	_glow.transform = Transform3D(
		Basis(axes.x * GLOW_WIDTH * flicker, axes.y * GLOW_WIDTH * flicker, axes.z * (length - lead)), wide_middle)
	_core.transform = Transform3D(
		Basis(axes.x * CORE_WIDTH, axes.y * CORE_WIDTH, axes.z * length), middle)
	# Helle Stücke laufen in gleichem Abstand von der Mündung zum Einschlag.
	var track: float = length - PULSE_LEAD
	for index: int in _pulses.size():
		var pulse: MeshInstance3D = _pulses[index]
		if track < PULSE_LENGTH:
			pulse.visible = false
			continue
		var along: float = fposmod(_time * PULSE_SPEED + track * float(index) / float(_pulses.size()), track)
		var piece: float = minf(PULSE_LENGTH, track - along)
		pulse.visible = true
		pulse.transform = Transform3D(Basis(axes.x * PULSE_WIDTH, axes.y * PULSE_WIDTH, axes.z * piece),
			_from + direction * (PULSE_LEAD + along + piece * 0.5))
	_flare.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * FLARE_SIZE * flicker), _to)
	# Der Kranz liegt quer zum Strahl und dreht sich, seine Größe flimmert gegenläufig zum Mantel.
	var ring_size: float = RING_SIZE * (1.0 - (flicker - 1.0))
	_ring.transform = Transform3D(
		Basis(axes.y, axes.z, axes.x).rotated(direction, _time * 9.0).scaled(Vector3.ONE * ring_size),
		_to - direction * 0.04)
	_light.position = _to - direction * minf(LIGHT_BACKOFF, length * 0.5)


## Funken, die am Einschlag zum Schützen hin wegspringen (aus dem Vorrat von fx.gd).
func _emit_sparks() -> void:
	var pool: FxPool = Fx.pool_of(Fx.root_of(self))
	if pool == null or pool.spark_count() > FxPool.MAX_SPARKS / 2:
		return
	var offset: Vector3 = _to - _from
	if offset.length() < MIN_LENGTH:
		return
	var back: Vector3 = -offset.normalized()
	for _i: int in SPARKS_PER_BURST:
		var heading: Vector3 = (back + Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 1.2), randf_range(-1.0, 1.0))).normalized()
		pool.add_spark(_to + back * 0.05, heading * randf_range(2.0, 4.5), SPARK_COLOR, 0.028, 0.18, randf_range(0.14, 0.24), 8.0)


func _part(part_name: String, mesh: Mesh, color: Color) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = _material(color)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part


## Rechtwinklige Achsen, deren z-Achse entlang direction (Einheitsvektor) zeigt.
static func _basis_along(direction: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis: Vector3 = up.cross(direction).normalized()
	var y_axis: Vector3 = direction.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, direction)


## Einheitswürfel (Kante 1), geteilt.
static func _box() -> BoxMesh:
	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
		_box_mesh.size = Vector3.ONE
	return _box_mesh


## Kugel mit Durchmesser 1, geteilt.
static func _sphere() -> SphereMesh:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radius = 0.5
		_sphere_mesh.height = 1.0
		_sphere_mesh.radial_segments = 12
		_sphere_mesh.rings = 6
	return _sphere_mesh


## Dünner Ring mit Durchmesser 1 in der XZ-Ebene, geteilt.
static func _ring_shape() -> TorusMesh:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.42
		_ring_mesh.outer_radius = 0.5
		_ring_mesh.rings = 10
		_ring_mesh.ring_segments = 4
	return _ring_mesh


## Leuchtendes, unbeleuchtetes Material je Farbe (dieselbe Art wie die Leuchtspur in fx.gd, also
## kein neuer Shader). Geteilt, also nie verändern.
static func _material(color: Color) -> StandardMaterial3D:
	var key: int = color.to_rgba32()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	_materials[key] = material
	return material
