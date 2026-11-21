extends RefCounted
## Modul: Upgrades (scripts/game/upgrades).
## Kurzlebige Bilder für die Kameras und Gegenstände aus Abschnitt 22: Strahl (Tele-Kamera,
## Zeitlupe, Markierung, Querschläger), Blitzlicht-Fächer am Boden, Aufblitzen an der Kamera,
## Stachelkranz der Kaktus-Requisite. fx.gd bleibt unverändert, hier stehen nur die neuen Bilder.
##
## Dieselben Regeln wie in fx.gd:
## - nur statische Funktionen, Einbinden mit const UpgradeFx := preload(".../upgrade_fx.gd")
## - nie abstürzen: ein ungültiger oder nicht im Baum hängender parent bedeutet "nichts tun"
## - jeder Effekt räumt sich selbst weg und läuft auch headless ohne Fehler
## - Effekte ändern nie den Spielzustand, ihr Zufall kommt nie aus Game.rng
## - kein Licht: Das Level hat schon fast so viele Lichter, wie die Grafik je Objekt verkraftet.
## Die Materialien haben Schalter, die es im Spiel schon gibt: unbeleuchtet und deckend für die
## Strahlen (wie die Linse der Drohne, die Farbe bleibt so auch vor hellem Hintergrund satt),
## unbeleuchtet, durchscheinend und addierend für Fächer und Aufleuchten (wie die Leuchtmaterialien
## aus fx.gd). Es kommt keine neue Shader-Art dazu.

# --- Reine Optik-Zahlen (keine Spielregeln) ---
## Anteil der Zeit, den ein Strahl in voller Breite steht, bevor er dünner wird.
const BEAM_HOLD_SHARE: float = 0.35
## Ein Strahl ist ein Kegelstumpf: So viel seiner Breite hat das schmale Ende.
const BEAM_TAPER: float = 0.2
const BEAM_SIDES: int = 6
const WEDGE_TIME: float = 0.3
const WEDGE_SEGMENTS: int = 14
const WEDGE_LIFT: float = 0.08
const BURST_TIME: float = 0.14
const SPIKE_COUNT: int = 12
const SPIKE_WIDTH: float = 0.13
const SPIKE_TIME: float = 0.3
const SPIKE_HEIGHT: float = 0.55
const SPIKE_TILT: float = 0.3
## Die Stacheln beginnen in diesem Anteil des Radius: nicht direkt vor den Augen des Spielers.
const SPIKE_START_SHARE: float = 0.4
const MATERIAL_CACHE_LIMIT: int = 32

static var _beam_mesh: CylinderMesh = null
static var _sphere_mesh: SphereMesh = null
static var _solid_materials: Dictionary = {}
static var _materials: Dictionary = {}
## Fächer-Netze je Öffnungswinkel (ganze Grad): Spitze im Ursprung, Mitte nach -Z, Radius 1.
static var _wedges: Dictionary = {}


## Gerader Strahl von from nach to (Weltkoordinaten), der kurz steht und dann dünner wird. Er ist
## an einem Ende schmal: ohne pointed_end am Anfang (eine Kamera, die nah am Auge des Spielers
## schwebt, zieht so keinen dicken Balken durchs Bild), mit pointed_end am Ende (Stachel). width
## ist die Breite am dicken Ende. Die Farbe deckt (ihr Alpha zählt nicht).
static func beam(parent: Node, from: Vector3, to: Vector3, color: Color, width: float, time: float, pointed_end: bool = false) -> void:
	if not _usable(parent):
		return
	var offset: Vector3 = to - from
	var length: float = offset.length()
	if length < 0.05:
		return
	# Das Netz steht entlang +Y, oben ist es schmal.
	var axes: Basis = _basis_along(offset / length if pointed_end else -offset / length)
	var node: MeshInstance3D = _mesh_node(_beam(), _solid_material(color))
	node.name = "Beam"
	parent.add_child(node)
	var middle: Vector3 = (from + to) * 0.5
	node.global_transform = Transform3D(Basis(axes.x * width, axes.y * length, axes.z * width), middle)
	var thin: Transform3D = Transform3D(Basis(axes.x * 0.002, axes.y * length, axes.z * 0.002), middle)
	var tween: Tween = node.create_tween()
	tween.tween_interval(maxf(time, 0.02) * BEAM_HOLD_SHARE)
	tween.tween_property(node, "global_transform", thin, maxf(time, 0.02) * (1.0 - BEAM_HOLD_SHARE)).set_ease(Tween.EASE_IN)
	tween.tween_callback(node.queue_free)


## Blitzlicht: heller Fächer knapp über dem Boden. origin ist die Spitze (Weltkoordinaten, schon
## auf Bodenhöhe), direction die Mitte des Fächers (nur die waagerechte Richtung zählt), reach
## seine Länge und cone_deg sein voller Öffnungswinkel. strength 0 bis 1 dämpft die Helligkeit
## (zweiter Blitz der Zweitkamera).
static func flash_wedge(parent: Node, origin: Vector3, direction: Vector3, reach: float, cone_deg: float, color: Color, strength: float = 1.0) -> void:
	if not _usable(parent) or reach <= 0.05 or cone_deg <= 0.0:
		return
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	# Eigenes Material: Die Deckkraft läuft per Tween aus.
	var material: StandardMaterial3D = _new_glow_material(Color(color, clampf(strength, 0.1, 1.0)))
	material.vertex_color_use_as_albedo = true
	var node: MeshInstance3D = _mesh_node(_wedge(cone_deg), material)
	node.name = "FlashWedge"
	parent.add_child(node)
	node.global_transform = Transform3D(
		Basis.looking_at(flat, Vector3.UP).scaled(Vector3(reach, 1.0, reach)), origin + Vector3(0.0, WEDGE_LIFT, 0.0))
	var tween: Tween = node.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, WEDGE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(node.queue_free)


## Kurzes Aufblitzen an pos (Weltkoordinaten): eine Leuchtkugel, die aufgeht und verschwindet.
static func burst(parent: Node, pos: Vector3, color: Color, size: float) -> void:
	if not _usable(parent):
		return
	var node: MeshInstance3D = _mesh_node(_sphere(), _glow_material(color))
	node.name = "Burst"
	parent.add_child(node)
	node.global_position = pos
	node.scale = Vector3.ONE * size * 0.35
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE * size, BURST_TIME * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE * 0.01, BURST_TIME * 0.6).set_ease(Tween.EASE_IN)
	tween.tween_callback(node.queue_free)


## Stachelkranz: spitze Stacheln rund um center (Weltkoordinaten, Füße), die bis zum Radius
## nach außen zeigen.
static func spikes(parent: Node, center: Vector3, radius: float, color: Color) -> void:
	if not _usable(parent) or radius <= 0.1:
		return
	var turn: float = randf() * TAU
	for i: int in SPIKE_COUNT:
		var angle: float = turn + TAU * float(i) / float(SPIKE_COUNT)
		var out: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		# Abwechselnd nach oben und unten geneigt: So liest sich der Kranz als Stacheln, nicht als Scheibe.
		var tip: Vector3 = Vector3(0.0, SPIKE_HEIGHT + (SPIKE_TILT if i % 2 == 0 else -SPIKE_TILT), 0.0)
		beam(parent, center + out * radius * SPIKE_START_SHARE + Vector3(0.0, SPIKE_HEIGHT, 0.0), center + out * radius + tip,
			color, SPIKE_WIDTH, SPIKE_TIME, true)


## Darf an diesem Knoten ein Effekt entstehen?
static func _usable(parent: Node) -> bool:
	return is_instance_valid(parent) and parent.is_inside_tree()


static func _mesh_node(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Basis, deren Y-Achse entlang direction zeigt (für das gestreckte Netz des Strahls).
static func _basis_along(direction: Vector3) -> Basis:
	var side: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var x: Vector3 = side.cross(direction).normalized()
	var z: Vector3 = x.cross(direction).normalized()
	return Basis(x, direction, z)


## Kegelstumpf entlang +Y mit Höhe 1: unten Durchmesser 1, oben BEAM_TAPER.
static func _beam() -> CylinderMesh:
	if _beam_mesh == null:
		_beam_mesh = CylinderMesh.new()
		_beam_mesh.bottom_radius = 0.5
		_beam_mesh.top_radius = 0.5 * BEAM_TAPER
		_beam_mesh.height = 1.0
		_beam_mesh.radial_segments = BEAM_SIDES
		_beam_mesh.rings = 1
	return _beam_mesh


## Grobe Kugel mit Durchmesser 1.
static func _sphere() -> SphereMesh:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radius = 0.5
		_sphere_mesh.height = 1.0
		_sphere_mesh.radial_segments = 10
		_sphere_mesh.rings = 5
	return _sphere_mesh


## Flacher Fächer in der Bodenebene: Spitze im Ursprung, Mitte nach -Z, Radius 1. Innen hell,
## zum Rand hin durchsichtig (Farbe je Ecke).
static func _wedge(cone_deg: float) -> ArrayMesh:
	var key: int = roundi(clampf(cone_deg, 1.0, 360.0))
	if _wedges.has(key):
		return _wedges[key] as ArrayMesh
	var half: float = deg_to_rad(float(key)) * 0.5
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var inner: Color = Color(1.0, 1.0, 1.0, 0.5)
	var outer: Color = Color(1.0, 1.0, 1.0, 0.05)
	for i: int in WEDGE_SEGMENTS:
		var a0: float = lerpf(-half, half, float(i) / float(WEDGE_SEGMENTS))
		var a1: float = lerpf(-half, half, float(i + 1) / float(WEDGE_SEGMENTS))
		vertices.append(Vector3.ZERO)
		colors.append(inner)
		vertices.append(Vector3(sin(a0), 0.0, -cos(a0)))
		colors.append(outer)
		vertices.append(Vector3(sin(a1), 0.0, -cos(a1)))
		colors.append(outer)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_wedges[key] = mesh
	return mesh


## Deckendes, unbeleuchtetes Material in dieser Farbe, je Farbe geteilt (nie verändern).
static func _solid_material(color: Color) -> StandardMaterial3D:
	var key: int = Color(color, 1.0).to_rgba32()
	if _solid_materials.has(key):
		return _solid_materials[key] as StandardMaterial3D
	if _solid_materials.size() >= MATERIAL_CACHE_LIMIT:
		_solid_materials.clear()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, 1.0)
	_solid_materials[key] = material
	return material


## Leuchtendes Material in dieser Farbe, je Farbe geteilt (nie verändern).
static func _glow_material(color: Color) -> StandardMaterial3D:
	var key: int = color.to_rgba32()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	if _materials.size() >= MATERIAL_CACHE_LIMIT:
		_materials.clear()
	var material: StandardMaterial3D = _new_glow_material(color)
	_materials[key] = material
	return material


## Dieselben Schalter wie die Leuchtmaterialien in fx.gd.
static func _new_glow_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	return material
