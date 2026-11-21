extends Node3D
## Modul: Spieler (scripts/game/player).
## Sichtbarer Dauerstrahl des Rotlichts (WeaponDefs.MODE_BEAM). Reine Optik: Die Waffensteuerung
## ruft aim(from, to), solange gefeuert wird (jedes Bild neu, der Strahl folgt Mündung und Blick),
## und stop(), sobald der Strahl aus ist. Der Knoten rechnet in Weltkoordinaten: Er hängt unter
## einem Knoten ohne eigene Lage (der Waffensteuerung).
##
## Aufbau:
##   BeamFx
##   ├─ Glow   breiter, durchscheinender Mantel
##   ├─ Core   dünner heller Kern
##   ├─ Flare  Leuchtpunkt am Einschlag
##   └─ Light  rotes Punktlicht am Einschlag
##
## Einbinden mit: const BeamFx := preload("res://scripts/game/player/beam_fx.gd")

const GLOW_COLOR: Color = Color(1.0, 0.08, 0.05, 0.5)
const CORE_COLOR: Color = Color(1.0, 0.75, 0.7, 0.95)
const FLARE_COLOR: Color = Color(1.0, 0.25, 0.15, 0.8)
const LIGHT_COLOR: Color = Color(1.0, 0.2, 0.12)
const GLOW_WIDTH: float = 0.11
const CORE_WIDTH: float = 0.035
const FLARE_SIZE: float = 0.4
const LIGHT_ENERGY: float = 2.2
const LIGHT_RANGE: float = 5.0
## Der Strahl flimmert: Seine Breite schwankt um diesen Anteil mit dieser Frequenz (1/s).
const FLICKER_AMOUNT: float = 0.22
const FLICKER_SPEED: float = 38.0
## Das Licht sitzt so weit vor dem Einschlag, damit es die getroffene Wand beleuchtet.
const LIGHT_BACKOFF: float = 0.25
## Kürzere Strahlen werden nicht gezeichnet.
const MIN_LENGTH: float = 0.05

static var _box_mesh: BoxMesh = null
static var _sphere_mesh: SphereMesh = null
static var _materials: Dictionary = {}

var _glow: MeshInstance3D
var _core: MeshInstance3D
var _flare: MeshInstance3D
var _light: OmniLight3D
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _active: bool = false
var _time: float = 0.0


func _init() -> void:
	name = "BeamFx"
	_glow = _part("Glow", _box(), GLOW_COLOR)
	_core = _part("Core", _box(), CORE_COLOR)
	_flare = _part("Flare", _sphere(), FLARE_COLOR)
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
		_glow.visible = false
		_core.visible = false
		return
	_glow.visible = true
	_core.visible = true
	var direction: Vector3 = offset / length
	var axes: Basis = _basis_along(direction)
	var flicker: float = 1.0 + sin(_time * FLICKER_SPEED) * FLICKER_AMOUNT
	var middle: Vector3 = (_from + _to) * 0.5
	_glow.transform = Transform3D(
		Basis(axes.x * GLOW_WIDTH * flicker, axes.y * GLOW_WIDTH * flicker, axes.z * length), middle)
	_core.transform = Transform3D(
		Basis(axes.x * CORE_WIDTH, axes.y * CORE_WIDTH, axes.z * length), middle)
	_flare.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * FLARE_SIZE * flicker), _to)
	_light.position = _to - direction * minf(LIGHT_BACKOFF, length * 0.5)


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
