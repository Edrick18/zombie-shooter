extends Node3D
## Modul: FX (scripts/game/fx).
## Vorrat für die vielen kleinen Teile der Effekte: Leuchtspuren, Funken, Spritzer, Rauch und
## Einschussmale. Statt für jedes Teil einen Knoten anzulegen und wieder zu löschen, liegen alle
## Teile einer Sorte in einem MultiMesh mit fester Größe. Das kostet je Sorte einen Zeichenaufruf,
## egal wie viele Teile fliegen, und nie mehr als die Obergrenzen unten.
##
## fx.gd legt den Vorrat bei Bedarf als Kind des Effekt-Behälters an (Name "FxPool") und füllt
## ihn über add_tracer, add_spark, add_blob und add_decal. Ist eine Sorte voll, fällt das neue
## Teil weg (add_* gibt false zurück), nur das älteste Einschussmal macht dem neuen Platz. Der
## Vorrat räumt sich selbst weg, sobald IDLE_FREE_TIME lang nichts mehr fliegt und kein Mal mehr
## zu sehen ist: Auch er ist ein Effekt, der nicht liegen bleibt.
##
## Reine Optik: keine Kollision, kein Spielzustand, Zufall kommt vom Aufrufer (nie aus Game.rng).
## Die Bewegung läuft in _process, steht also in der Pause wie die Tweens der übrigen Effekte.
##
## Die drei Material-Arten gibt es im Spiel schon (kein neuer Shader):
## - Leuchtspuren und Funken: wie die Flammenbälle in flame_fx.gd (unbeleuchtet, addierend, Farbe
##   je Teil), gezeichnet als Partikel.
## - Spritzer und Rauch: wie das Konfetti in fx.gd (unbeleuchtet, durchscheinend, Farbe je Teil,
##   zur Kamera gedreht), gezeichnet als Partikel.
## - Einschussmale: unbeleuchtet und deckend wie die Lampe der Mine, gezeichnet als Mesh.
##
## Einbinden mit: const FxPool := preload("res://scripts/game/fx/fx_pool.gd")

const NODE_NAME: String = "FxPool"

## Obergrenzen der gleichzeitig sichtbaren Teile je Sorte.
const MAX_TRACERS: int = 32
const MAX_SPARKS: int = 72
const MAX_BLOBS: int = 88
const MAX_DECALS: int = 28
## So lange nach dem letzten Teil bleibt der Vorrat noch liegen, dann löscht er sich.
const IDLE_FREE_TIME: float = 0.4

## Eine Leuchtspur zieht sich zum Ziel hin zusammen: Am Ende bleibt dieser Anteil ihrer Länge
## und ihrer Breite.
const TRACER_END_LENGTH: float = 0.12
const TRACER_END_WIDTH: float = 0.3
## Eine Leuchtspur ist am Anfang schmaler als am Ziel (Anteil ihrer Breite): Der Anfang liegt
## meist direkt vor der Kamera und wäre sonst ein dicker Balken, so ist sie im Bild überall dünn.
const TRACER_TAPER: float = 0.15
## Ein Spritzer oder Rauchball verblasst im letzten Teil seines Lebens (Anteil).
const BLOB_FADE_SHARE: float = 0.45
const BLOB_SIDES: int = 8
## Einschussmale: Lebensdauer, Schrumpfen am Ende, Abstand zur Wand (gegen Flimmern).
const DECAL_LIFE: float = 4.5
const DECAL_FADE_TIME: float = 0.35
const DECAL_LIFT: float = 0.02
const DECAL_POINTS: int = 9
const DECAL_SCORCH: int = 0
const DECAL_SLIME: int = 1
const DECAL_COLORS: Array[Color] = [Color(0.05, 0.04, 0.08), Color(0.3, 0.72, 0.12)]
## Die Teile fliegen überall im Studio: Der Renderer soll sie nie wegen ihrer Lage auslassen.
const CULL_SIZE: float = 4000.0

static var _box_mesh: BoxMesh = null
static var _tracer_mesh: ArrayMesh = null
static var _blob_mesh: ArrayMesh = null
static var _decal_mesh: ArrayMesh = null
static var _decal_materials: Array[StandardMaterial3D] = []

var _tracer_mm: MultiMesh
var _spark_mm: MultiMesh
var _blob_mm: MultiMesh

# Leuchtspuren (Index 0 bis _tracer_count - 1 sind belegt).
var _tracer_count: int = 0
var _t_to: PackedVector3Array = PackedVector3Array()
var _t_dir: PackedVector3Array = PackedVector3Array()
var _t_ax: PackedVector3Array = PackedVector3Array()
var _t_ay: PackedVector3Array = PackedVector3Array()
var _t_len: PackedFloat32Array = PackedFloat32Array()
var _t_width: PackedFloat32Array = PackedFloat32Array()
var _t_age: PackedFloat32Array = PackedFloat32Array()
var _t_life: PackedFloat32Array = PackedFloat32Array()
var _t_color: PackedColorArray = PackedColorArray()

# Funken: gestreckte Splitter, die fliegen, fallen und dabei schrumpfen.
var _spark_count: int = 0
var _s_pos: PackedVector3Array = PackedVector3Array()
var _s_vel: PackedVector3Array = PackedVector3Array()
var _s_dir: PackedVector3Array = PackedVector3Array()
var _s_ax: PackedVector3Array = PackedVector3Array()
var _s_ay: PackedVector3Array = PackedVector3Array()
var _s_len: PackedFloat32Array = PackedFloat32Array()
var _s_width: PackedFloat32Array = PackedFloat32Array()
var _s_age: PackedFloat32Array = PackedFloat32Array()
var _s_life: PackedFloat32Array = PackedFloat32Array()
var _s_gravity: PackedFloat32Array = PackedFloat32Array()
var _s_color: PackedColorArray = PackedColorArray()

# Spritzer und Rauch: runde Flächen zur Kamera, die fliegen, wachsen oder schrumpfen und verblassen.
var _blob_count: int = 0
var _b_pos: PackedVector3Array = PackedVector3Array()
var _b_vel: PackedVector3Array = PackedVector3Array()
var _b_size_from: PackedFloat32Array = PackedFloat32Array()
var _b_size_to: PackedFloat32Array = PackedFloat32Array()
var _b_age: PackedFloat32Array = PackedFloat32Array()
var _b_life: PackedFloat32Array = PackedFloat32Array()
var _b_gravity: PackedFloat32Array = PackedFloat32Array()
var _b_drag: PackedFloat32Array = PackedFloat32Array()
var _b_turn: PackedFloat32Array = PackedFloat32Array()
var _b_color: PackedColorArray = PackedColorArray()

# Einschussmale: fester Ring aus Knoten, das älteste Mal wird zuerst wiederverwendet.
var _decal_nodes: Array[MeshInstance3D] = []
var _decal_head: int = 0
var _decal_count: int = 0
var _d_expire: PackedFloat32Array = PackedFloat32Array()
var _d_size: PackedFloat32Array = PackedFloat32Array()

var _clock: float = 0.0
var _idle: float = 0.0


func _init() -> void:
	name = NODE_NAME
	# Die Teile rechnen in Weltkoordinaten, egal wo der Behälter steht.
	top_level = true
	_tracer_mm = _new_multimesh("Tracers", _tracer_shape(), MAX_TRACERS)
	_spark_mm = _new_multimesh("Sparks", _box(), MAX_SPARKS)
	_blob_mm = _new_multimesh("Blobs", _blob(), MAX_BLOBS)
	_t_to.resize(MAX_TRACERS)
	_t_dir.resize(MAX_TRACERS)
	_t_ax.resize(MAX_TRACERS)
	_t_ay.resize(MAX_TRACERS)
	_t_len.resize(MAX_TRACERS)
	_t_width.resize(MAX_TRACERS)
	_t_age.resize(MAX_TRACERS)
	_t_life.resize(MAX_TRACERS)
	_t_color.resize(MAX_TRACERS)
	_s_pos.resize(MAX_SPARKS)
	_s_vel.resize(MAX_SPARKS)
	_s_dir.resize(MAX_SPARKS)
	_s_ax.resize(MAX_SPARKS)
	_s_ay.resize(MAX_SPARKS)
	_s_len.resize(MAX_SPARKS)
	_s_width.resize(MAX_SPARKS)
	_s_age.resize(MAX_SPARKS)
	_s_life.resize(MAX_SPARKS)
	_s_gravity.resize(MAX_SPARKS)
	_s_color.resize(MAX_SPARKS)
	_b_pos.resize(MAX_BLOBS)
	_b_vel.resize(MAX_BLOBS)
	_b_size_from.resize(MAX_BLOBS)
	_b_size_to.resize(MAX_BLOBS)
	_b_age.resize(MAX_BLOBS)
	_b_life.resize(MAX_BLOBS)
	_b_gravity.resize(MAX_BLOBS)
	_b_drag.resize(MAX_BLOBS)
	_b_turn.resize(MAX_BLOBS)
	_b_color.resize(MAX_BLOBS)
	_d_expire.resize(MAX_DECALS)
	_d_size.resize(MAX_DECALS)


func _ready() -> void:
	global_transform = Transform3D.IDENTITY
	# Über den Baum statt über den Namen Events: So bleibt fx.gd ohne Autoload ladbar wie bisher.
	var events: Node = get_tree().root.get_node_or_null(^"Events")
	if events != null and events.has_signal(&"run_started"):
		events.connect(&"run_started", clear)


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	_clock += dt
	if _tracer_count > 0:
		_update_tracers(dt)
	if _spark_count > 0:
		_update_sparks(dt)
	if _blob_count > 0:
		_update_blobs(dt)
	if _decal_count > 0:
		_update_decals()
	if is_empty():
		_idle += dt
		if _idle >= IDLE_FREE_TIME:
			queue_free()
	else:
		_idle = 0.0


# --- Öffentliche Schnittstelle ---------------------------------------------------------------


## Leuchtspur von from nach to (Weltkoordinaten), die sich in time Sekunden zum Ziel hin
## zusammenzieht und verblasst.
func add_tracer(from: Vector3, to: Vector3, color: Color, width: float, time: float) -> bool:
	if _tracer_count >= MAX_TRACERS:
		return false
	var offset: Vector3 = to - from
	var length: float = offset.length()
	if length < 0.01:
		return false
	var direction: Vector3 = offset / length
	var side: Vector3 = _side_of(direction)
	var i: int = _tracer_count
	_t_to[i] = to
	_t_dir[i] = direction
	_t_ax[i] = side
	_t_ay[i] = direction.cross(side)
	_t_len[i] = length
	_t_width[i] = width
	_t_age[i] = 0.0
	_t_life[i] = maxf(time, 0.01)
	_t_color[i] = color
	_tracer_mm.set_instance_transform(i, Transform3D(side * width, _t_ay[i] * width, offset, (from + to) * 0.5))
	_tracer_mm.set_instance_color(i, color)
	_tracer_count += 1
	_tracer_mm.visible_instance_count = _tracer_count
	_idle = 0.0
	return true


## Funke: ein in Flugrichtung gestreckter Splitter an pos (Weltkoordinaten) mit Tempo velocity,
## der unter gravity (m/s², nach unten) fällt und in life Sekunden auf nichts schrumpft.
func add_spark(pos: Vector3, velocity: Vector3, color: Color, width: float, length: float, life: float,
		gravity: float) -> bool:
	if _spark_count >= MAX_SPARKS:
		return false
	var speed: float = velocity.length()
	var direction: Vector3 = velocity / speed if speed > 0.001 else Vector3.UP
	var side: Vector3 = _side_of(direction)
	var i: int = _spark_count
	_s_pos[i] = pos
	_s_vel[i] = velocity
	_s_dir[i] = direction
	_s_ax[i] = side
	_s_ay[i] = direction.cross(side)
	_s_len[i] = length
	_s_width[i] = width
	_s_age[i] = 0.0
	_s_life[i] = maxf(life, 0.01)
	_s_gravity[i] = gravity
	_s_color[i] = color
	_spark_mm.set_instance_transform(i, Transform3D(side * width, _s_ay[i] * width, direction * length, pos))
	_spark_mm.set_instance_color(i, color)
	_spark_count += 1
	_spark_mm.visible_instance_count = _spark_count
	_idle = 0.0
	return true


## Spritzer oder Rauchball: runde, zur Kamera gedrehte Fläche an pos (Weltkoordinaten), die mit
## velocity fliegt, unter gravity fällt (negativ: steigt), mit drag (1/s) abbremst, von size_from
## auf size_to (Durchmesser) wächst oder schrumpft und am Ende verblasst.
func add_blob(pos: Vector3, velocity: Vector3, color: Color, size_from: float, size_to: float, life: float,
		gravity: float, drag: float) -> bool:
	if _blob_count >= MAX_BLOBS:
		return false
	var i: int = _blob_count
	_b_pos[i] = pos
	_b_vel[i] = velocity
	_b_size_from[i] = size_from
	_b_size_to[i] = size_to
	_b_age[i] = 0.0
	_b_life[i] = maxf(life, 0.01)
	_b_gravity[i] = gravity
	_b_drag[i] = drag
	_b_turn[i] = randf() * TAU
	_b_color[i] = color
	_blob_mm.set_instance_transform(i, Transform3D(
		Vector3(size_from, 0.0, 0.0), Vector3(0.0, size_from, 0.0), Vector3(0.0, 0.0, size_from), pos))
	_blob_mm.set_instance_color(i, color)
	_blob_mm.set_instance_custom_data(i, Color(_b_turn[i], 0.0, 0.0, 0.0))
	_blob_count += 1
	_blob_mm.visible_instance_count = _blob_count
	_idle = 0.0
	return true


## Einschussmal: flacher, gezackter Fleck an pos auf einer Fläche mit der Normalen normal. Bleibt
## DECAL_LIFE Sekunden und schrumpft dann weg. Ist der Ring voll, weicht das älteste Mal.
## kind: DECAL_SCORCH (dunkel) oder DECAL_SLIME (grün).
func add_decal(pos: Vector3, normal: Vector3, size: float, kind: int = DECAL_SCORCH) -> void:
	var facing: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var index: int = (_decal_head + _decal_count) % MAX_DECALS
	if _decal_count >= MAX_DECALS:
		index = _decal_head
		_decal_head = (_decal_head + 1) % MAX_DECALS
	else:
		_decal_count += 1
	while _decal_nodes.size() <= index:
		_decal_nodes.append(_new_decal_node())
	var node: MeshInstance3D = _decal_nodes[index]
	node.material_override = _decal_material(kind)
	var side: Vector3 = _side_of(facing).rotated(facing, randf() * TAU)
	node.transform = Transform3D(Basis(side, facing.cross(side), facing).scaled(Vector3.ONE * size),
		pos + facing * DECAL_LIFT)
	node.visible = true
	_d_expire[index] = _clock + DECAL_LIFE
	_d_size[index] = size
	_idle = 0.0


## Zahl der gerade sichtbaren Teile je Sorte (für Tests und zum Drosseln).
func tracer_count() -> int:
	return _tracer_count


func spark_count() -> int:
	return _spark_count


func blob_count() -> int:
	return _blob_count


func decal_count() -> int:
	return _decal_count


## Das Netz der Spritzer und Rauchscheiben (Achteck, dreht sich zur Kamera, Farbe je Teil): auch
## für Partikel anderer Effekte, die dieselbe Material-Art nutzen sollen.
static func blob_mesh() -> ArrayMesh:
	return _blob()


## Fliegt nichts mehr und ist kein Mal mehr zu sehen?
func is_empty() -> bool:
	return _tracer_count + _spark_count + _blob_count + _decal_count == 0


## Räumt alles sofort weg (neuer Lauf).
func clear() -> void:
	_tracer_count = 0
	_spark_count = 0
	_blob_count = 0
	_tracer_mm.visible_instance_count = 0
	_spark_mm.visible_instance_count = 0
	_blob_mm.visible_instance_count = 0
	for node: MeshInstance3D in _decal_nodes:
		node.visible = false
	_decal_count = 0
	_decal_head = 0


# --- Bewegung --------------------------------------------------------------------------------


func _update_tracers(dt: float) -> void:
	var i: int = 0
	while i < _tracer_count:
		var age: float = _t_age[i] + dt
		var life: float = _t_life[i]
		if age >= life:
			# Das letzte Teil rückt auf den frei gewordenen Platz.
			_tracer_count -= 1
			if i < _tracer_count:
				var last: int = _tracer_count
				_t_to[i] = _t_to[last]
				_t_dir[i] = _t_dir[last]
				_t_ax[i] = _t_ax[last]
				_t_ay[i] = _t_ay[last]
				_t_len[i] = _t_len[last]
				_t_width[i] = _t_width[last]
				_t_age[i] = _t_age[last]
				_t_life[i] = _t_life[last]
				_t_color[i] = _t_color[last]
			continue
		_t_age[i] = age
		var k: float = age / life
		var remaining: float = _t_len[i] * (1.0 - (1.0 - TRACER_END_LENGTH) * k * k)
		var width: float = _t_width[i] * (1.0 - (1.0 - TRACER_END_WIDTH) * k)
		var direction: Vector3 = _t_dir[i]
		_tracer_mm.set_instance_transform(i, Transform3D(
			_t_ax[i] * width, _t_ay[i] * width, direction * remaining, _t_to[i] - direction * (remaining * 0.5)))
		var color: Color = _t_color[i]
		color.a *= 1.0 - k
		_tracer_mm.set_instance_color(i, color)
		i += 1
	_tracer_mm.visible_instance_count = _tracer_count


func _update_sparks(dt: float) -> void:
	var i: int = 0
	while i < _spark_count:
		var age: float = _s_age[i] + dt
		var life: float = _s_life[i]
		if age >= life:
			_spark_count -= 1
			if i < _spark_count:
				var last: int = _spark_count
				_s_pos[i] = _s_pos[last]
				_s_vel[i] = _s_vel[last]
				_s_dir[i] = _s_dir[last]
				_s_ax[i] = _s_ax[last]
				_s_ay[i] = _s_ay[last]
				_s_len[i] = _s_len[last]
				_s_width[i] = _s_width[last]
				_s_age[i] = _s_age[last]
				_s_life[i] = _s_life[last]
				_s_gravity[i] = _s_gravity[last]
				_s_color[i] = _s_color[last]
				_spark_mm.set_instance_color(i, _s_color[i])
			continue
		_s_age[i] = age
		var velocity: Vector3 = _s_vel[i]
		velocity.y -= _s_gravity[i] * dt
		_s_vel[i] = velocity
		var pos: Vector3 = _s_pos[i] + velocity * dt
		_s_pos[i] = pos
		var k: float = 1.0 - age / life
		var width: float = _s_width[i] * k
		_spark_mm.set_instance_transform(i, Transform3D(
			_s_ax[i] * width, _s_ay[i] * width, _s_dir[i] * (_s_len[i] * k), pos))
		i += 1
	_spark_mm.visible_instance_count = _spark_count


func _update_blobs(dt: float) -> void:
	var i: int = 0
	while i < _blob_count:
		var age: float = _b_age[i] + dt
		var life: float = _b_life[i]
		if age >= life:
			_blob_count -= 1
			if i < _blob_count:
				var last: int = _blob_count
				_b_pos[i] = _b_pos[last]
				_b_vel[i] = _b_vel[last]
				_b_size_from[i] = _b_size_from[last]
				_b_size_to[i] = _b_size_to[last]
				_b_age[i] = _b_age[last]
				_b_life[i] = _b_life[last]
				_b_gravity[i] = _b_gravity[last]
				_b_drag[i] = _b_drag[last]
				_b_turn[i] = _b_turn[last]
				_b_color[i] = _b_color[last]
				_blob_mm.set_instance_custom_data(i, Color(_b_turn[i], 0.0, 0.0, 0.0))
			continue
		_b_age[i] = age
		var velocity: Vector3 = _b_vel[i]
		velocity.y -= _b_gravity[i] * dt
		velocity *= maxf(0.0, 1.0 - _b_drag[i] * dt)
		_b_vel[i] = velocity
		var pos: Vector3 = _b_pos[i] + velocity * dt
		_b_pos[i] = pos
		var k: float = age / life
		var size: float = lerpf(_b_size_from[i], _b_size_to[i], k)
		_blob_mm.set_instance_transform(i, Transform3D(
			Vector3(size, 0.0, 0.0), Vector3(0.0, size, 0.0), Vector3(0.0, 0.0, size), pos))
		var color: Color = _b_color[i]
		color.a *= minf(1.0, (1.0 - k) / BLOB_FADE_SHARE)
		_blob_mm.set_instance_color(i, color)
		i += 1
	_blob_mm.visible_instance_count = _blob_count


## Die Male liegen im Ring in der Reihenfolge ihres Alters: Nur die ältesten laufen ab oder
## schrumpfen gerade, alle anderen brauchen keine Rechnung.
func _update_decals() -> void:
	while _decal_count > 0 and _d_expire[_decal_head] <= _clock:
		_decal_nodes[_decal_head].visible = false
		_decal_head = (_decal_head + 1) % MAX_DECALS
		_decal_count -= 1
	var index: int = _decal_head
	for _n: int in _decal_count:
		var left: float = _d_expire[index] - _clock
		if left >= DECAL_FADE_TIME:
			break
		var node: MeshInstance3D = _decal_nodes[index]
		node.basis = node.basis.orthonormalized().scaled(Vector3.ONE * maxf(0.001, _d_size[index] * left / DECAL_FADE_TIME))
		index = (index + 1) % MAX_DECALS


# --- Aufbau ----------------------------------------------------------------------------------


func _new_multimesh(node_name: String, mesh: Mesh, capacity: int) -> MultiMesh:
	var multimesh: MultiMesh = MultiMesh.new()
	# Dieselbe Aufteilung wie bei CPUParticles3D (Lage, Farbe, Zusatzdaten): derselbe Shader.
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	var bounds: AABB = AABB(Vector3.ONE * -CULL_SIZE * 0.5, Vector3.ONE * CULL_SIZE)
	multimesh.custom_aabb = bounds
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = bounds
	add_child(node)
	return multimesh


func _new_decal_node() -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "Decal"
	node.mesh = _decal()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	return node


## Ein Einheitsvektor quer zu direction (Einheitsvektor).
static func _side_of(direction: Vector3) -> Vector3:
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	return up.cross(direction).normalized()


## Einheitswürfel mit dem Leuchtmaterial der Flammenbälle (Farbe und Deckkraft je Teil).
static func _box() -> BoxMesh:
	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
		_box_mesh.size = Vector3.ONE
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.disable_receive_shadows = true
		_box_mesh.material = material
	return _box_mesh


## Quader der Länge 1 entlang Z, am Ende +Z mit Kantenlänge 1, am Ende -Z auf TRACER_TAPER
## verjüngt. Dasselbe Material wie der Würfel der Funken.
static func _tracer_shape() -> ArrayMesh:
	if _tracer_mesh == null:
		var near: float = 0.5 * TRACER_TAPER
		var corners: Array[Vector3] = [
			Vector3(-near, -near, -0.5), Vector3(near, -near, -0.5), Vector3(near, near, -0.5), Vector3(-near, near, -0.5),
			Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5),
		]
		var faces: Array[PackedInt32Array] = [
			PackedInt32Array([0, 1, 2, 3]), PackedInt32Array([4, 5, 6, 7]), PackedInt32Array([0, 1, 5, 4]),
			PackedInt32Array([1, 2, 6, 5]), PackedInt32Array([2, 3, 7, 6]), PackedInt32Array([3, 0, 4, 7]),
		]
		var vertices: PackedVector3Array = PackedVector3Array()
		for face: PackedInt32Array in faces:
			for triangle: Array in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = corners[face[int(triangle[0])]]
				var b: Vector3 = corners[face[int(triangle[1])]]
				var c: Vector3 = corners[face[int(triangle[2])]]
				# Vorderseiten laufen im Uhrzeigersinn: Das Kreuzprodukt zeigt dann nach innen.
				if (b - a).cross(c - a).dot(a + b + c) > 0.0:
					var swap: Vector3 = b
					b = c
					c = swap
				vertices.append(a)
				vertices.append(b)
				vertices.append(c)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		_tracer_mesh = ArrayMesh.new()
		_tracer_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_tracer_mesh.surface_set_material(0, _box().material)
	return _tracer_mesh


## Achteck mit Durchmesser 1 in der XY-Ebene, mit dem Material des Konfettis: dreht sich zur
## Kamera, Farbe und Deckkraft je Teil.
static func _blob() -> ArrayMesh:
	if _blob_mesh == null:
		var vertices: PackedVector3Array = PackedVector3Array()
		for i: int in BLOB_SIDES:
			var a0: float = TAU * float(i) / float(BLOB_SIDES)
			var a1: float = TAU * float(i + 1) / float(BLOB_SIDES)
			vertices.append(Vector3.ZERO)
			vertices.append(Vector3(cos(a1), sin(a1), 0.0) * 0.5)
			vertices.append(Vector3(cos(a0), sin(a0), 0.0) * 0.5)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		_blob_mesh = ArrayMesh.new()
		_blob_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.billboard_keep_scale = true
		_blob_mesh.surface_set_material(0, material)
	return _blob_mesh


## Gezackter Fleck mit Radius etwa 1 in der XY-Ebene, Vorderseite nach +Z.
static func _decal() -> ArrayMesh:
	if _decal_mesh == null:
		var vertices: PackedVector3Array = PackedVector3Array()
		var rim: PackedVector3Array = PackedVector3Array()
		for i: int in DECAL_POINTS * 2:
			var angle: float = TAU * float(i) / float(DECAL_POINTS * 2)
			# Abwechselnd Zacke und Kerbe, jede Zacke etwas anders lang.
			var radius: float = 0.55 if i % 2 == 1 else 0.8 + 0.2 * sin(float(i) * 2.3)
			rim.append(Vector3(cos(angle), sin(angle), 0.0) * radius)
		for i: int in rim.size():
			vertices.append(Vector3.ZERO)
			vertices.append(rim[(i + 1) % rim.size()])
			vertices.append(rim[i])
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		_decal_mesh = ArrayMesh.new()
		_decal_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _decal_mesh


static func _decal_material(kind: int) -> StandardMaterial3D:
	if _decal_materials.is_empty():
		for color: Color in DECAL_COLORS:
			var material: StandardMaterial3D = StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = color
			_decal_materials.append(material)
	return _decal_materials[clampi(kind, 0, _decal_materials.size() - 1)]
