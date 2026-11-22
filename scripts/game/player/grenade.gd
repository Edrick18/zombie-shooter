extends Node3D
## Modul: Spieler (scripts/game/player).
## Granate des Knalleffekts (WeaponDefs.MODE_GRENADE): fliegt im Bogen und meldet jeden Einschlag
## an die Waffensteuerung. Sie kennt keine Spielregeln: Schaden, Explosion und die Frage, ob ein
## getroffener Körper zählt, entscheidet der Aufrufer über on_hit.
##
## Flugbahn: genau die Wurfparabel (Start, Tempo, Schwerkraft), abgetastet in jedem Physik-Schritt.
## Zwischen zwei Punkten prüft ein Strahl auf Welt und Zombies (Balance.MASK_SHOT). Die Granate
## prallt nicht ab: Der erste Einschlag, den on_hit annimmt, beendet sie.
##
## on_hit(hit: Dictionary, position: Vector3, direction: Vector3) -> bool
##   hit        Ergebnis von intersect_ray, leer wenn die Flugzeit abgelaufen ist
##   position   Einschlagpunkt (oder der Ort der Granate bei Ablauf der Flugzeit)
##   direction  Flugrichtung im Augenblick des Einschlags (Einheitsvektor)
##   Rückgabe   true = die Granate ist verbraucht, false = hindurchfliegen (Leiche im Weg)
##
## Einbinden mit: const Grenade := preload("res://scripts/game/player/grenade.gd")

const Balance := preload("res://scripts/core/balance.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

## Nach so vielen Sekunden ohne Einschlag explodiert die Granate in der Luft.
const MAX_FLIGHT_TIME: float = 6.0
## Obergrenze der Körper, durch die eine Granate in einem Schritt hindurchfliegt (Leichen).
const MAX_PASSES_PER_STEP: int = 8

# --- Reine Optik ---
const BODY_RADIUS: float = 0.1
const BODY_LENGTH: float = 0.28
## So lange wandert die sichtbare Granate von der Mündung auf die echte Flugbahn (die beginnt am
## Auge, damit der Einschlag zum Fadenkreuz passt).
const MUZZLE_BLEND_TIME: float = 0.18
## In dieser Zeit wächst die sichtbare Granate auch von diesem Anteil auf ihre volle Größe: Voll
## groß und leuchtend direkt vor der Kamera verdeckte sie beim Abschuss die Bildmitte.
const BODY_START_SCALE: float = 0.2
const TRAIL_COLOR_WHITEN: float = 0.35
const SPIN_SPEED: float = 14.0
const GLOW_ENERGY: float = 2.2
const ROUGHNESS: float = 0.45
## Schein um die fliegende Granate (Durchmesser in Metern, Deckkraft): So sieht man sie im Bogen.
## Er geht erst nach HALO_DELAY Sekunden Flug auf und ist nach HALO_GROW weiteren voll da: An der
## Mündung, direkt vor der Kamera, füllte er sonst das halbe Bild.
const HALO_SIZE: float = 0.36
const HALO_ALPHA: float = 0.3
const HALO_DELAY: float = 0.1
const HALO_GROW: float = 0.25

static var _body_mesh: CapsuleMesh = null
static var _halo_mesh: SphereMesh = null
static var _materials: Dictionary = {}

var _start: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _gravity: float = 0.0
var _exclude: Array[RID] = []
var _on_hit: Callable = Callable()
var _color: Color = Color.WHITE
## Versatz der sichtbaren Granate am Start (Mündung minus Auge).
var _muzzle_offset: Vector3 = Vector3.ZERO
## Alter der Flugbahn in Physik-Schritten gerechnet und das Alter, das gerade gezeigt wird.
var _age: float = 0.0
var _shown_age: float = 0.0
var _done: bool = false
var _body: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _trail_from: Vector3 = Vector3.ZERO


## Startet die Granate. Vorher in den Baum hängen (sie setzt ihre Weltposition).
## from: Start der Flugbahn (Auge), muzzle: Mündung der sichtbaren Waffe, velocity: Tempo und
## Richtung in m/s, gravity: Schwerkraft in m/s², exclude: Körper, die sie nie trifft (der Spieler).
func launch(from: Vector3, muzzle: Vector3, velocity: Vector3, gravity: float, exclude: Array[RID],
		on_hit: Callable, color: Color) -> void:
	_start = from
	_velocity = velocity
	_gravity = gravity
	_exclude = exclude.duplicate()
	_on_hit = on_hit
	_color = color
	_muzzle_offset = muzzle - from
	_age = 0.0
	_shown_age = 0.0
	_done = false
	_trail_from = muzzle
	if is_inside_tree():
		global_position = from
	_build_body()
	_show_at(0.0)


## Ort auf der Flugbahn nach time Sekunden.
func point_at(time: float) -> Vector3:
	return _start + _velocity * time + Vector3(0.0, -0.5 * _gravity * time * time, 0.0)


## Ist die Granate schon eingeschlagen (oder abgelaufen)?
func is_done() -> bool:
	return _done


func _ready() -> void:
	Events.run_started.connect(_on_run_started)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var from: Vector3 = point_at(_age)
	_age += delta
	var to: Vector3 = point_at(_age)
	var offset: Vector3 = to - from
	if offset.length_squared() > 0.000001 and _trace(from, to, offset.normalized()):
		return
	global_position = to
	if _age >= MAX_FLIGHT_TIME:
		_finish(_report({}, to, offset.normalized() if offset.length_squared() > 0.000001 else Vector3.DOWN))


func _process(delta: float) -> void:
	if _done:
		return
	# Die Anzeige läuft mit den Bildern mit, höchstens bis zum Stand der Physik.
	_shown_age = minf(_shown_age + delta, _age)
	_show_at(_shown_age)
	if is_instance_valid(_body):
		_body.rotate_object_local(Vector3.RIGHT, SPIN_SPEED * delta)


## Prüft das Stück Flugbahn von from nach to. Gibt true zurück, wenn die Granate verbraucht ist.
func _trace(from: Vector3, to: Vector3, direction: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start: Vector3 = from
	for _pass: int in MAX_PASSES_PER_STEP:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			start, to, Balance.MASK_SHOT, _exclude)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return false
		var at: Vector3 = hit["position"]
		if _report(hit, at, direction):
			global_position = at
			_finish(true)
			return true
		# Der Aufrufer will hindurch (Leiche): diesen Körper ab jetzt übergehen.
		_exclude.append(hit["rid"])
	return false


## Fragt den Aufrufer. Ohne gültigen Aufrufer (die Waffensteuerung ist weg) gilt die Granate als
## verbraucht: Sie verschwindet ohne Wirkung.
func _report(hit: Dictionary, at: Vector3, direction: Vector3) -> bool:
	if not _on_hit.is_valid():
		return true
	return bool(_on_hit.call(hit, at, direction))


func _finish(consumed: bool) -> void:
	if not consumed:
		return
	_done = true
	queue_free()


func _on_run_started() -> void:
	# Ein neuer Lauf: Was noch fliegt, verschwindet ohne Wirkung.
	_done = true
	queue_free()


## Zeigt die Granate an ihrem Ort zur Zeit time und zieht eine kurze Rauchspur nach.
func _show_at(time: float) -> void:
	if not is_instance_valid(_body) or not is_inside_tree():
		return
	var blend: float = clampf(1.0 - time / MUZZLE_BLEND_TIME, 0.0, 1.0)
	var at: Vector3 = point_at(time) + _muzzle_offset * blend
	_body.global_position = at
	# An der Mündung, direkt vor der Kamera, ist die Granate klein und wächst im Flug auf ihre Größe.
	_body.scale = Vector3.ONE * lerpf(BODY_START_SCALE, 1.0, 1.0 - blend)
	if is_instance_valid(_halo):
		var open: float = clampf((time - HALO_DELAY) / HALO_GROW, 0.0, 1.0)
		_halo.visible = open > 0.0
		_halo.scale = Vector3.ONE * maxf(open, 0.01)
	if at.distance_squared_to(_trail_from) > BODY_LENGTH * BODY_LENGTH:
		Fx.tracer(get_parent(), _trail_from, at, _color.lerp(Color.WHITE, TRAIL_COLOR_WHITEN))
		_trail_from = at


func _build_body() -> void:
	if is_instance_valid(_body):
		return
	if _body_mesh == null:
		_body_mesh = CapsuleMesh.new()
		_body_mesh.radius = BODY_RADIUS
		_body_mesh.height = BODY_LENGTH
		_body_mesh.radial_segments = 8
		_body_mesh.rings = 2
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = _body_mesh
	_body.material_override = _material(_color)
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Die sichtbare Granate bewegt sich unabhängig vom Knoten (der sitzt auf der echten Flugbahn).
	_body.top_level = true
	add_child(_body)
	if _halo_mesh == null:
		_halo_mesh = SphereMesh.new()
		_halo_mesh.radius = HALO_SIZE * 0.5
		_halo_mesh.height = HALO_SIZE
		_halo_mesh.radial_segments = 10
		_halo_mesh.rings = 5
	var halo: MeshInstance3D = MeshInstance3D.new()
	halo.name = "Halo"
	halo.mesh = _halo_mesh
	halo.material_override = Fx.glow_material(Color(_color.r, _color.g, _color.b, HALO_ALPHA))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.visible = false
	_body.add_child(halo)
	_halo = halo


## Leuchtendes Material je Farbe (geteilt, also nie verändern).
static func _material(color: Color) -> StandardMaterial3D:
	var key: int = color.to_rgba32()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = GLOW_ENERGY
	material.roughness = ROUGHNESS
	_materials[key] = material
	return material
