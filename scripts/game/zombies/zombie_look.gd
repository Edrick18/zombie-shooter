extends RefCounted
## Modul: Zombies (scripts/game/zombies).
## Aussehen der Zombies: Maße, Farben, Netze und Materialien der drei Typen. Nur statische
## Funktionen und Zwischenspeicher, kein Spielzustand. Benutzt wird das von zombie_body.gd.
##
## Die drei Figuren (eigene Entwürfe, passend zur Gameshow):
##   walker    "Kandidat": grüne Haut, zerrissenes Jackett, Namensschild oder Startnummer,
##             Buckel, hängender Kiefer. Schlurft gebeugt.
##   sprinter  "Kabelträger": rote Haut, schmal, ärmelloses Crew-Hemd, lange Arme mit Krallen,
##             Sprechgarnitur mit Mikrofon-Bügel, helle Turnschuhe. Rennt vorgebeugt.
##   elite     "Showmaster": groß und breit, goldenes Glitzer-Jackett mit Schulterpolstern und
##             Frackschößen, Fliege, Krone, Mikrofon in der Faust. Leuchtet.
##
## Leistung: Jedes bewegliche Körperteil ist genau ein Netz mit einer Fläche. Die Farben stecken
## in den Ecken (Vertexfarben), deshalb braucht ein Zombie trotz vieler Farbtöne nur ein Material
## und elf Zeichenaufrufe. Je Typ gibt es VARIANT_COUNT Farb- und Detail-Varianten. Netze und
## Materialien entstehen beim ersten Gebrauch und werden von allen Zombies derselben Variante
## geteilt (nie verändern).
##
## Material-Arten (siehe ARCHITEKTUR Abschnitt 15):
##   Körper   StandardMaterial3D mit vertex_color_use_as_albedo und emission_enabled
##            (Schlüssel "emission_enabled=1,vertex_color_use_as_albedo=1")
##   Augen    unbeleuchtet ("shading_mode=0"), wie bisher
##
## Maße: Alle Zahlen in den Tabellen sind Anteile der Körperhöhe (Balance.ZOMBIE_HEIGHT mal
## "scale" des Typs). Vorn ist -Z, rechts +X, der Ursprung des Körpers sind die Füße.

const Balance := preload("res://scripts/core/balance.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")

## Varianten je Typ (Farben, Frisur, Details).
const VARIANT_COUNT: int = 4
## Kopfmitte und Kopfradius als Anteil der Körperhöhe. Der Kopf füllt damit genau den Bereich
## über Balance.HEADSHOT_HEIGHT_RATIO (0,78) bis zum Scheitel: Dort zählt ein Treffer als Kopfschuss.
const HEAD_RADIUS_SHARE: float = 0.112
const HEAD_CENTER_SHARE: float = 1.0 - HEAD_RADIUS_SHARE
## Die Schuhspitze zeigt im Netz um diesen Winkel nach oben. Beim Gehen ist das Knie gebeugt und
## der Unterschenkel geneigt: So steht der Fuß flach statt mit den Zehen im Boden.
const FOOT_TOE_UP: float = 0.24
## Anteil des Leuchtens an der Grundfarbe bei Typen mit "glow" (Elite).
const GLOW_SHARE: float = 0.22
const BODY_ROUGHNESS: float = 0.85

const COLOR_MOUTH: Color = Color(0.1, 0.03, 0.04)
const COLOR_TEETH: Color = Color(0.93, 0.9, 0.74)
const COLOR_GORE: Color = Color(0.42, 0.04, 0.06)
const COLOR_TAG: Color = Color(0.95, 0.95, 0.92)
const COLOR_TAG_STRIPE: Color = Color(0.9, 0.12, 0.2)
const COLOR_INK: Color = Color(0.08, 0.08, 0.1)
const COLOR_METAL: Color = Color(0.72, 0.74, 0.8)
const COLOR_DEAD_EYES: Color = Color(0.08, 0.07, 0.07)

## Augenfarbe je Typ (unbeleuchtet, leuchtet also auch im Dunkeln).
const EYE_COLORS: Dictionary = {
	"walker": Color(1.0, 0.86, 0.25),
	"sprinter": Color(1.0, 1.0, 0.85),
	"elite": Color(1.0, 0.12, 0.08),
}

## Maße und Gang je Typ, alles Anteile der Körperhöhe bzw. Radiant.
##   hip_rest       Höhe der Hüfte im Stand (Beine leicht gebeugt)
##   hip_half       halber Abstand der Hüftgelenke
##   thigh, shin    Länge von Ober- und Unterschenkel, ankle = Höhe des Knöchels über der Sohle
##   leg_r, arm_r   Radius von Oberschenkel und Oberarm
##   lean           Vorbeugen des Rumpfs im Stand (negativ = nach vorn), run_lean kommt beim Laufen dazu
##   neck_drop      Schultergelenk liegt so weit unter der Kopfmitte
##   neck_z         Kopfmitte vor (negativ) der Rumpfachse: vorgeschobener Kopf
##   head_z         Kopfmitte vor den Füßen
##   shoulder_half  halbe Schulterbreite, chest_w / chest_d / waist_w = halbe Breite und Tiefe des Rumpfs
##   upper_arm, forearm, hand   Längen des Arms
##   stride_base, stride_gain   Länge eines Doppelschritts in Metern bei Größe 1 = base + gain * Tempo (m/s)
##   max_step       größte Auslenkung eines Fußes nach vorn und hinten
##   stance         Anteil des Schritts, in dem der Fuß am Boden steht (unter 0,5 = Flugphase)
##   lift           Höhe, um die der Fuß beim Vorschwingen angehoben wird
##   bob, sway      Auf und Ab bzw. seitliches Pendeln des Kopfs beim Gehen
##   roll, twist    Seitneigung und Verdrehung des Rumpfs im Takt
##   arm_rest, arm_swing, elbow_rest, elbow_swing, arm_out   Armhaltung und Pendeln
const METRICS: Dictionary = {
	"walker": {
		"hip_rest": 0.425, "hip_half": 0.062, "thigh": 0.2, "shin": 0.2, "ankle": 0.04,
		"leg_r": 0.05, "arm_r": 0.036, "lean": -0.2, "run_lean": -0.04, "neck_drop": 0.17,
		"neck_z": -0.035, "head_z": -0.05, "shoulder_half": 0.128, "chest_w": 0.112, "chest_d": 0.078,
		"waist_w": 0.094, "upper_arm": 0.155, "forearm": 0.145, "hand": 0.05,
		"stride_base": 0.55, "stride_gain": 0.38, "max_step": 0.16, "stance": 0.62, "lift": 0.022, "bob": 0.012,
		"sway": 0.022, "roll": 0.07, "twist": 0.1, "arm_rest": 0.3, "arm_swing": 0.22,
		"elbow_rest": 0.3, "elbow_swing": 0.12, "arm_out": 0.1,
	},
	"sprinter": {
		"hip_rest": 0.41, "hip_half": 0.05, "thigh": 0.2, "shin": 0.2, "ankle": 0.04,
		"leg_r": 0.04, "arm_r": 0.027, "lean": -0.34, "run_lean": -0.12, "neck_drop": 0.185,
		"neck_z": -0.03, "head_z": -0.09, "shoulder_half": 0.098, "chest_w": 0.086, "chest_d": 0.064,
		"waist_w": 0.066, "upper_arm": 0.2, "forearm": 0.2, "hand": 0.06,
		"stride_base": 0.8, "stride_gain": 0.3, "max_step": 0.2, "stance": 0.36, "lift": 0.11, "bob": 0.016,
		"sway": 0.008, "roll": 0.04, "twist": 0.24, "arm_rest": 0.15, "arm_swing": 0.95,
		"elbow_rest": 0.75, "elbow_swing": 0.5, "arm_out": 0.16,
	},
	"elite": {
		"hip_rest": 0.428, "hip_half": 0.076, "thigh": 0.2, "shin": 0.2, "ankle": 0.04,
		"leg_r": 0.066, "arm_r": 0.054, "lean": -0.07, "run_lean": -0.03, "neck_drop": 0.15,
		"neck_z": -0.012, "head_z": -0.01, "shoulder_half": 0.168, "chest_w": 0.152, "chest_d": 0.1,
		"waist_w": 0.118, "upper_arm": 0.165, "forearm": 0.155, "hand": 0.066,
		"stride_base": 0.75, "stride_gain": 0.34, "max_step": 0.18, "stance": 0.6, "lift": 0.06, "bob": 0.014,
		"sway": 0.03, "roll": 0.085, "twist": 0.16, "arm_rest": 0.12, "arm_swing": 0.3,
		"elbow_rest": 0.55, "elbow_swing": 0.1, "arm_out": 0.4,
	},
}

## "Typ:Variante" -> Dictionary mit den Netzen (siehe get_look).
static var _looks: Dictionary = {}
## Typ -> fertige Maße (METRICS plus berechnete Werte).
static var _metrics: Dictionary = {}
## Typ -> Material des Körpers bzw. der Augen.
static var _body_materials: Dictionary = {}
static var _eye_materials: Dictionary = {}
static var _dead_eye_material: StandardMaterial3D = null
## Zurückgegebene Färbe-Materialien, die der nächste Zombie wieder benutzt.
static var _tint_pool: Array[StandardMaterial3D] = []
## Zahl der bisher gebauten Varianten (für Tests: Sie darf mit mehr Zombies nicht wachsen).
static var _build_count: int = 0


## Sammelt einfache Formen zu einem einzigen Netz mit Vertexfarben. Alle Maße sind Anteile von
## unit (der Körperhöhe in Metern).
class Part:
	extends RefCounted

	static var _box_arrays: Array = []
	static var _ball_arrays: Array = []

	var unit: float = 1.0
	var _vertices: PackedVector3Array = PackedVector3Array()
	var _normals: PackedVector3Array = PackedVector3Array()
	var _colors: PackedColorArray = PackedColorArray()
	var _indices: PackedInt32Array = PackedInt32Array()

	func _init(unit_length: float) -> void:
		unit = unit_length

	## Quader mit Mittelpunkt center und Kantenlängen size.
	func box(center: Vector3, size: Vector3, color: Color, euler: Vector3 = Vector3.ZERO) -> void:
		if _box_arrays.is_empty():
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3.ONE
			_box_arrays = mesh.get_mesh_arrays()
		_append(_box_arrays, center, size, color, euler)

	## Kugel oder Ei mit den Halbachsen radii.
	func ball(center: Vector3, radii: Vector3, color: Color, euler: Vector3 = Vector3.ZERO) -> void:
		if _ball_arrays.is_empty():
			var mesh: SphereMesh = SphereMesh.new()
			mesh.radius = 1.0
			mesh.height = 2.0
			mesh.radial_segments = 12
			mesh.rings = 6
			_ball_arrays = mesh.get_mesh_arrays()
		_append(_ball_arrays, center, radii, color, euler)

	## Rohr entlang Y mit Mittelpunkt center: unten r_bottom, oben r_top (0 = Spitze), Höhe height.
	## z_ratio staucht den Querschnitt in der Tiefe (ovaler Rumpf).
	func tube(center: Vector3, r_bottom: float, r_top: float, height: float, color: Color,
			euler: Vector3 = Vector3.ZERO, z_ratio: float = 1.0, sides: int = 10) -> void:
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.bottom_radius = r_bottom
		mesh.top_radius = r_top
		mesh.height = height
		mesh.radial_segments = sides
		mesh.rings = 1
		_append(mesh.get_mesh_arrays(), center, Vector3(1.0, 1.0, z_ratio), color, euler)

	## Ring (Torus) um die Y-Achse: Radius der Mittellinie und Dicke des Rings.
	func ring(center: Vector3, radius: float, thickness: float, color: Color,
			euler: Vector3 = Vector3.ZERO, stretch: Vector3 = Vector3.ONE) -> void:
		var mesh: TorusMesh = TorusMesh.new()
		mesh.inner_radius = radius - thickness
		mesh.outer_radius = radius + thickness
		mesh.rings = 14
		mesh.ring_segments = 6
		_append(mesh.get_mesh_arrays(), center, stretch, color, euler)

	func is_empty() -> bool:
		return _vertices.is_empty()

	## Baut das Netz (eine Fläche) und hängt das Material an.
	func build(material: Material) -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		return mesh

	func _append(arrays: Array, center: Vector3, stretch: Vector3, color: Color, euler: Vector3) -> void:
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var turned: Basis = Basis.from_euler(euler)
		var shape: Basis = turned * Basis.from_scale(stretch * unit)
		var base: int = _vertices.size()
		_vertices.append_array(Transform3D(shape, center * unit) * vertices)
		# Normalen: gedreht und gegen die Streckung entzerrt. Der Shader normiert sie selbst.
		var inverse_stretch: Vector3 = Vector3(1.0 / stretch.x, 1.0 / stretch.y, 1.0 / stretch.z)
		_normals.append_array(Transform3D(turned * Basis.from_scale(inverse_stretch), Vector3.ZERO) * normals)
		# Vertexfarben erwartet der Shader linear, die Tabellen hier sind wie albedo_color in sRGB.
		var colors: PackedColorArray = PackedColorArray()
		colors.resize(vertices.size())
		colors.fill(color.srgb_to_linear())
		_colors.append_array(colors)
		for index: int in indices:
			_indices.append(index + base)


# --- Öffentlich ---------------------------------------------------------------------------------

## Körperhöhe eines Typs in Metern.
static func type_height(type: String) -> float:
	return Balance.ZOMBIE_HEIGHT * float(Balance.ZOMBIE_TYPES[_known(type)]["scale"])


## Maße eines Typs (Anteile der Körperhöhe, siehe METRICS). Dazu berechnet:
##   neck_y       Kopfmitte über der Hüfte, gemessen entlang des Rumpfs. So gewählt, dass die
##                Kopfmitte im Stand genau auf HEAD_CENTER_SHARE der Körperhöhe liegt.
##   shoulder_up  Schultergelenk über der Hüfte
static func get_metrics(type: String) -> Dictionary:
	var key: String = _known(type)
	if _metrics.has(key):
		return _metrics[key]
	var m: Dictionary = (METRICS[key] as Dictionary).duplicate()
	var lean: float = float(m["lean"])
	var neck_z: float = float(m["neck_z"])
	var neck_y: float = (HEAD_CENTER_SHARE - float(m["hip_rest"]) + neck_z * sin(lean)) / cos(lean)
	m["neck_y"] = neck_y
	m["shoulder_up"] = neck_y - float(m["neck_drop"])
	_metrics[key] = m
	return m


## Netze einer Variante: Dictionary mit "torso", "head", "eyes", "arm_l", "arm_r", "fore_l",
## "fore_r", "thigh_l", "thigh_r", "shin_l", "shin_r" (alle ArrayMesh mit einer Fläche). Wird
## beim ersten Aufruf gebaut und danach geteilt.
static func get_look(type: String, variant: int) -> Dictionary:
	var known: String = _known(type)
	var index: int = posmod(variant, VARIANT_COUNT)
	var key: String = "%s:%d" % [known, index]
	if not _looks.has(key):
		_looks[key] = _build_look(known, index)
		_build_count += 1
	return _looks[key]


## Material des Körpers für diesen Typ (geteilt, nie verändern).
static func body_material(type: String) -> StandardMaterial3D:
	var key: String = _known(type)
	if not _body_materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = BODY_ROUGHNESS
		# Leuchten ist immer an (schwarz = aus): Aufblitzen, Brand und Gift brauchen so keine neue
		# Material-Art.
		material.emission_enabled = true
		material.emission = base_emission(key)
		_body_materials[key] = material
	return _body_materials[key]


## Grund-Leuchten eines Typs: schwarz, bei der Elite ein Anteil ihrer Farbe.
static func base_emission(type: String) -> Color:
	var def: Dictionary = Balance.ZOMBIE_TYPES[_known(type)]
	if bool(def["glow"]):
		var color: Color = def["color"]
		return Color(color.r * GLOW_SHARE, color.g * GLOW_SHARE, color.b * GLOW_SHARE)
	return Color.BLACK


## Material der Augen für diesen Typ (geteilt, nie verändern).
static func eye_material(type: String) -> StandardMaterial3D:
	var key: String = _known(type)
	if not _eye_materials.has(key):
		_eye_materials[key] = _flat_material(EYE_COLORS[key])
	return _eye_materials[key]


## Material erloschener Augen (tote Zombies), für alle geteilt.
static func dead_eye_material() -> StandardMaterial3D:
	if _dead_eye_material == null:
		_dead_eye_material = _flat_material(COLOR_DEAD_EYES)
	return _dead_eye_material


## Eigenes Material zum Einfärben eines einzelnen Zombies (Treffer, Brand, Gift, Kälte, Tod).
## Dieselbe Material-Art wie body_material. Nach Gebrauch mit release_tint_material zurückgeben.
static func take_tint_material(type: String) -> StandardMaterial3D:
	if not _tint_pool.is_empty():
		return _tint_pool.pop_back()
	return body_material(type).duplicate() as StandardMaterial3D


static func release_tint_material(material: StandardMaterial3D) -> void:
	if material != null:
		_tint_pool.append(material)


## Zahl der bisher gebauten Varianten (Test: Netze werden geteilt, nicht je Zombie gebaut).
static func built_look_count() -> int:
	return _build_count


static func _known(type: String) -> String:
	return type if METRICS.has(type) and Balance.ZOMBIE_TYPES.has(type) else WavePlan.TYPE_WALKER


static func _flat_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


# --- Farben -------------------------------------------------------------------------------------

## Farbtöne einer Variante. Die Hautfarbe bleibt nah an der Typfarbe aus Balance.ZOMBIE_TYPES,
## damit man den Typ auf einen Blick erkennt.
static func _palette(type: String, variant: int) -> Dictionary:
	var base: Color = Balance.ZOMBIE_TYPES[type]["color"]
	var pal: Dictionary = {}
	match type:
		"sprinter":
			var skins: Array[Color] = [base, Color(0.96, 0.3, 0.12), Color(0.82, 0.1, 0.2), Color(0.96, 0.22, 0.3)]
			var tops: Array[Color] = [Color(0.2, 0.2, 0.25), Color(0.16, 0.22, 0.38), Color(0.14, 0.14, 0.16), Color(0.3, 0.24, 0.32)]
			var shoes: Array[Color] = [Color(0.94, 0.94, 0.9), Color(0.86, 0.96, 0.2), Color(0.94, 0.94, 0.9), Color(0.2, 0.9, 0.95)]
			var accents: Array[Color] = [Color(1.0, 0.82, 0.1), Color(0.95, 0.95, 0.9), Color(0.2, 0.9, 0.95), Color(1.0, 0.82, 0.1)]
			pal["skin"] = skins[variant]
			pal["cloth"] = tops[variant]
			pal["pants"] = Color(0.24, 0.24, 0.3)
			pal["shoes"] = shoes[variant]
			pal["accent"] = accents[variant]
			pal["shirt"] = COLOR_TAG
			pal["hair"] = Color(0.07, 0.07, 0.08)
		"elite":
			var accents: Array[Color] = [Color(0.92, 0.12, 0.55), Color(0.1, 0.78, 0.92), Color(0.56, 0.26, 0.96), Color(0.96, 0.96, 0.96)]
			var jackets: Array[Color] = [Color(0.98, 0.66, 0.08), Color(1.0, 0.74, 0.1), Color(0.95, 0.6, 0.05), Color(1.0, 0.7, 0.12)]
			pal["skin"] = Color(1.0, 0.84, 0.36)
			pal["cloth"] = jackets[variant]
			pal["pants"] = Color(0.44, 0.16, 0.66)
			pal["shoes"] = Color(0.95, 0.95, 0.92)
			pal["accent"] = accents[variant]
			pal["shirt"] = Color(0.97, 0.97, 0.94)
			pal["hair"] = Color(0.2, 0.1, 0.05)
			pal["crown"] = Color(1.0, 0.92, 0.42)
		_:
			var skins: Array[Color] = [_shade(base, 1.3), Color(0.68, 0.76, 0.42), Color(0.46, 0.72, 0.58), Color(0.7, 0.8, 0.6)]
			var jackets: Array[Color] = [Color(0.38, 0.52, 0.72), Color(0.68, 0.48, 0.28), Color(0.64, 0.42, 0.7), Color(0.8, 0.78, 0.66)]
			var pants: Array[Color] = [Color(0.26, 0.28, 0.4), Color(0.36, 0.3, 0.24), Color(0.24, 0.22, 0.34), Color(0.36, 0.3, 0.46)]
			var hairs: Array[Color] = [Color(0.12, 0.1, 0.09), Color(0.56, 0.56, 0.5), Color(0.3, 0.13, 0.08), Color(0.1, 0.1, 0.13)]
			var accents: Array[Color] = [Color(0.96, 0.76, 0.15), Color(0.1, 0.72, 0.72), Color(1.0, 0.55, 0.76), Color(0.2, 0.46, 0.85)]
			pal["skin"] = skins[variant]
			pal["cloth"] = jackets[variant]
			pal["pants"] = pants[variant]
			pal["shoes"] = Color(0.16, 0.14, 0.14)
			pal["accent"] = accents[variant]
			pal["shirt"] = Color(0.78, 0.76, 0.66)
			pal["hair"] = hairs[variant]
	pal["skin_dark"] = _shade(pal["skin"], 0.8)
	pal["cloth_dark"] = _shade(pal["cloth"], 0.7)
	pal["cloth_light"] = _shade(pal["cloth"], 1.2)
	return pal


## Dunkler (factor < 1) oder heller (factor > 1), ohne den Farbton zu ändern.
static func _shade(color: Color, factor: float) -> Color:
	return Color(minf(color.r * factor, 1.0), minf(color.g * factor, 1.0), minf(color.b * factor, 1.0))


# --- Netze --------------------------------------------------------------------------------------

static func _build_look(type: String, variant: int) -> Dictionary:
	var m: Dictionary = get_metrics(type)
	var unit: float = type_height(type)
	var pal: Dictionary = _palette(type, variant)
	var material: StandardMaterial3D = body_material(type)
	var look: Dictionary = {}
	look["torso"] = _build_torso(type, variant, unit, m, pal).build(material)
	look["head"] = _build_head(type, variant, unit, pal).build(material)
	look["eyes"] = _build_eyes(type, variant, unit).build(eye_material(type))
	for side: float in [-1.0, 1.0]:
		var tag: String = "l" if side < 0.0 else "r"
		look["arm_" + tag] = _build_upper_arm(type, variant, unit, m, pal, side).build(material)
		look["fore_" + tag] = _build_forearm(type, variant, unit, m, pal, side).build(material)
		look["thigh_" + tag] = _build_thigh(type, unit, m, pal).build(material)
		look["shin_" + tag] = _build_shin(type, variant, unit, m, pal, side).build(material)
	return look


## Tiefe der Rumpf-Vorderseite (positiv) in der Höhe y über der Hüfte.
static func _front(m: Dictionary, y: float) -> float:
	var top: float = float(m["shoulder_up"]) - 0.03
	var t: float = clampf((y - 0.02) / maxf(top - 0.02, 0.01), 0.0, 1.0)
	var depth_ratio: float = float(m["chest_d"]) / float(m["chest_w"])
	return lerpf(float(m["waist_w"]), float(m["chest_w"]), t) * depth_ratio


## Rumpf. Ursprung ist die Mitte der Hüfte, die Kopfmitte liegt bei (0, neck_y, neck_z).
static func _build_torso(type: String, variant: int, unit: float, m: Dictionary, pal: Dictionary) -> Part:
	var p: Part = Part.new(unit)
	var su: float = m["shoulder_up"]
	var sh: float = m["shoulder_half"]
	var cw: float = m["chest_w"]
	var cd: float = m["chest_d"]
	var ww: float = m["waist_w"]
	var neck_y: float = m["neck_y"]
	var neck_z: float = m["neck_z"]
	var depth_ratio: float = cd / cw
	var cloth: Color = pal["cloth"]
	var skin: Color = pal["skin"]
	var bare_shoulders: bool = type == "sprinter"
	# Becken, Rumpf (unten schmal, oben breit) und Schulterpartie.
	p.ball(Vector3(0.0, -0.008, 0.004), Vector3(ww + 0.012, 0.078, ww * depth_ratio + 0.012), pal["pants"])
	p.tube(Vector3(0.0, 0.02 + (su - 0.05) * 0.5, 0.0), ww, cw, su - 0.05, cloth, Vector3.ZERO, depth_ratio)
	p.ball(Vector3(0.0, su - 0.034, 0.0), Vector3(sh + 0.008, 0.064, cd + 0.006), skin if bare_shoulders else cloth)
	# Hals. Oben sitzt eine dunkelrote Scheibe: Man sieht sie nur, wenn der Kopf fehlt.
	var neck_top: float = neck_y - 0.07
	p.tube(Vector3(0.0, (su + neck_top) * 0.5, neck_z * 0.6), 0.042, 0.036, neck_top - su + 0.07, pal["skin"],
			Vector3(atan2(neck_z, neck_top - su), 0.0, 0.0))
	p.tube(Vector3(0.0, neck_top + 0.036, neck_z), 0.03, 0.026, 0.008, COLOR_GORE)
	match type:
		"sprinter":
			_detail_sprinter_torso(p, variant, m, pal)
		"elite":
			_detail_elite_torso(p, variant, m, pal)
		_:
			_detail_walker_torso(p, variant, m, pal)
	return p


static func _detail_walker_torso(p: Part, variant: int, m: Dictionary, pal: Dictionary) -> void:
	var su: float = m["shoulder_up"]
	var cw: float = m["chest_w"]
	var cd: float = m["chest_d"]
	var cloth_dark: Color = pal["cloth_dark"]
	var chest_y: float = su * 0.66
	var chest_z: float = -_front(m, chest_y)
	# Buckel: Der Kandidat hängt krumm in seinem Jackett.
	p.ball(Vector3(0.0, su - 0.075, cd * 0.62), Vector3(cw * 0.82, 0.085, 0.062), pal["cloth"])
	if variant != 3:
		# Offenes Jackett: Hemd in der Mitte, Revers links und rechts.
		p.box(Vector3(0.0, su * 0.56, -_front(m, su * 0.56) + 0.006), Vector3(0.07, su * 0.62, 0.02), pal["shirt"])
		for side: float in [-1.0, 1.0]:
			p.box(Vector3(side * 0.045, su * 0.7, chest_z - 0.002), Vector3(0.03, su * 0.42, 0.014), cloth_dark,
					Vector3(0.0, 0.0, side * 0.22))
		# Zerrissener Saum: Fetzen hängen unter dem Jackett heraus.
		for i: int in 4:
			var angle: float = 0.9 + float(i) * 1.5 + float(variant)
			p.box(Vector3(cos(angle) * m["waist_w"] * 0.95, -0.012 - 0.012 * float(i % 2), sin(angle) * m["waist_w"] * 0.62),
					Vector3(0.04, 0.07, 0.012), cloth_dark, Vector3(0.0, -angle + PI * 0.5, 0.18 * float(i - 1)))
	match variant:
		0:
			# Krawatte, schief gezogen, und das Namensschild der Show.
			p.box(Vector3(0.008, su * 0.58, chest_z - 0.008), Vector3(0.024, su * 0.5, 0.01), pal["accent"], Vector3(0.0, 0.0, 0.14))
			_name_tag(p, Vector3(-0.062, chest_y + 0.012, chest_z - 0.006))
		1:
			# Startnummer: weißes Feld mit einer dunklen 7.
			p.box(Vector3(0.0, su * 0.56, -_front(m, su * 0.56) - 0.006), Vector3(0.105, 0.1, 0.012), COLOR_TAG)
			p.box(Vector3(0.0, su * 0.56 + 0.03, -_front(m, su * 0.56) - 0.014), Vector3(0.05, 0.014, 0.006), COLOR_INK)
			p.box(Vector3(0.006, su * 0.56 - 0.006, -_front(m, su * 0.56) - 0.014), Vector3(0.014, 0.066, 0.006), COLOR_INK,
					Vector3(0.0, 0.0, -0.32))
		2:
			_name_tag(p, Vector3(0.06, chest_y + 0.012, chest_z - 0.006))
			# Ein Riss quer über den Bauch zeigt die grüne Haut.
			p.box(Vector3(-0.03, su * 0.3, -_front(m, su * 0.3) - 0.002), Vector3(0.075, 0.024, 0.012), pal["skin_dark"],
					Vector3(0.0, 0.0, 0.35))
		_:
			# Ohne Jackett: Hosenträger, Krawatte und die Startnummer auf dem Rücken.
			for side: float in [-1.0, 1.0]:
				p.box(Vector3(side * 0.055, su * 0.55, -_front(m, su * 0.55) - 0.003), Vector3(0.02, su * 0.86, 0.012), pal["accent"])
				p.box(Vector3(side * 0.055, su * 0.55, _front(m, su * 0.55) + 0.003), Vector3(0.02, su * 0.86, 0.012), pal["accent"])
			p.box(Vector3(-0.006, su * 0.6, chest_z - 0.008), Vector3(0.026, su * 0.46, 0.01), COLOR_TAG_STRIPE, Vector3(0.0, 0.0, -0.1))
			p.box(Vector3(0.0, su * 0.5, _front(m, su * 0.5) + 0.008), Vector3(0.1, 0.085, 0.01), COLOR_TAG)
			p.box(Vector3(0.0, su * 0.5, _front(m, su * 0.5) + 0.015), Vector3(0.016, 0.06, 0.006), COLOR_INK)


## Namensschild der Show: weißes Kärtchen mit rotem Streifen.
static func _name_tag(p: Part, at: Vector3) -> void:
	p.box(at, Vector3(0.054, 0.036, 0.008), COLOR_TAG, Vector3(0.0, 0.0, 0.08))
	p.box(at + Vector3(0.0, 0.012, -0.002), Vector3(0.054, 0.012, 0.008), COLOR_TAG_STRIPE, Vector3(0.0, 0.0, 0.08))


static func _detail_sprinter_torso(p: Part, variant: int, m: Dictionary, pal: Dictionary) -> void:
	var su: float = m["shoulder_up"]
	var cw: float = m["chest_w"]
	var cd: float = m["chest_d"]
	# Träger des Crew-Hemds über den nackten Schultern.
	for side: float in [-1.0, 1.0]:
		p.box(Vector3(side * cw * 0.55, su - 0.012, 0.0), Vector3(0.026, 0.07, cd * 2.0 + 0.016), pal["cloth"])
	# Weißes Crew-Schild auf dem Rücken.
	p.box(Vector3(0.0, su * 0.66, _front(m, su * 0.66) + 0.004), Vector3(0.1, 0.034, 0.01), pal["shirt"])
	# Knochiger Rücken: Wirbel stehen durch das Hemd.
	for i: int in 4:
		var y: float = su * (0.2 + 0.15 * float(i))
		p.ball(Vector3(0.0, y, _front(m, y) + 0.002), Vector3(0.016, 0.02, 0.014), pal["cloth_light"])
	if variant == 1 or variant == 3:
		# Aufgerolltes Kabel quer über der Brust.
		var slant: float = 0.62 if variant == 1 else -0.62
		p.ring(Vector3(0.0, su * 0.52, 0.0), cw * 1.08, 0.011, pal["accent"], Vector3(0.0, 0.0, slant),
				Vector3(1.0, 1.0, (cd + 0.014) / (cw * 1.08)))
	else:
		# Gürtel mit Funkgerät.
		p.tube(Vector3(0.0, 0.03, 0.0), m["waist_w"] + 0.012, m["waist_w"] + 0.012, 0.022, pal["accent"],
				Vector3.ZERO, cd / cw)
		p.box(Vector3(m["waist_w"] * 0.8, 0.03, m["waist_w"] * 0.55), Vector3(0.03, 0.055, 0.022), COLOR_INK)


static func _detail_elite_torso(p: Part, variant: int, m: Dictionary, pal: Dictionary) -> void:
	var su: float = m["shoulder_up"]
	var sh: float = m["shoulder_half"]
	var cd: float = m["chest_d"]
	var ww: float = m["waist_w"]
	var accent: Color = pal["accent"]
	var chest_y: float = su * 0.62
	# Hemdbrust, breite Revers in der Showfarbe, große Fliege.
	p.box(Vector3(0.0, chest_y, -_front(m, chest_y) + 0.004), Vector3(0.085, su * 0.66, 0.02), pal["shirt"])
	for side: float in [-1.0, 1.0]:
		p.box(Vector3(side * 0.062, su * 0.72, -_front(m, su * 0.72) - 0.002), Vector3(0.045, su * 0.5, 0.014), accent,
				Vector3(0.0, 0.0, side * 0.26))
		p.tube(Vector3(side * 0.034, su - 0.012, -cd - 0.012), 0.03, 0.006, 0.062, accent, Vector3(0.0, 0.0, side * PI * 0.5), 0.5, 4)
		# Schulterpolster.
		p.ball(Vector3(side * (sh + 0.012), su + 0.002, 0.0), Vector3(0.078, 0.05, 0.08), pal["cloth_light"])
		p.ball(Vector3(side * (sh + 0.03), su + 0.004, 0.0), Vector3(0.05, 0.02, 0.085), accent)
		# Frackschöße hinter den Beinen.
		p.box(Vector3(side * ww * 0.5, -0.085, ww * 0.55), Vector3(ww * 0.8, 0.2, 0.022), pal["cloth_dark"],
				Vector3(0.12, 0.0, side * 0.06))
	p.ball(Vector3(0.0, su - 0.012, -cd - 0.014), Vector3(0.014, 0.016, 0.012), pal["cloth_dark"])
	# Goldknöpfe.
	for i: int in 3:
		var y: float = su * (0.24 + 0.14 * float(i))
		p.ball(Vector3(0.0, y, -_front(m, y) - 0.006), Vector3(0.012, 0.012, 0.008), pal["crown"])
	if variant % 2 == 1:
		# Schärpe quer über der Brust.
		p.box(Vector3(0.0, su * 0.5, -_front(m, su * 0.5) - 0.01), Vector3(0.032, su * 0.95, 0.008), accent, Vector3(0.0, 0.0, 0.7))


## Kopf. Ursprung ist die Kopfmitte, alles bleibt innerhalb von HEAD_RADIUS_SHARE (außer Krone).
static func _build_head(type: String, variant: int, unit: float, pal: Dictionary) -> Part:
	var p: Part = Part.new(unit)
	var skin: Color = pal["skin"]
	var skin_dark: Color = pal["skin_dark"]
	match type:
		"sprinter":
			# Schmaler, langer Schädel mit aufgerissenem Maul.
			p.ball(Vector3(0.0, 0.01, 0.006), Vector3(0.08, 0.1, 0.098), skin)
			p.ball(Vector3(0.0, -0.062, -0.026), Vector3(0.056, 0.048, 0.06), skin_dark)
			p.box(Vector3(0.0, -0.052, -0.074), Vector3(0.066, 0.058, 0.03), COLOR_MOUTH)
			for i: int in 4:
				var x: float = -0.024 + 0.016 * float(i)
				p.tube(Vector3(x, -0.034, -0.088), 0.0, 0.007, 0.022, COLOR_TEETH, Vector3.ZERO, 1.0, 4)
				p.tube(Vector3(x + 0.008, -0.072, -0.086), 0.006, 0.0, 0.018, COLOR_TEETH, Vector3.ZERO, 1.0, 4)
			for side: float in [-1.0, 1.0]:
				p.ball(Vector3(side * 0.034, 0.026, -0.074), Vector3(0.026, 0.02, 0.02), COLOR_MOUTH)
				p.box(Vector3(side * 0.034, 0.05, -0.08), Vector3(0.05, 0.014, 0.03), skin_dark, Vector3(0.0, 0.0, side * 0.42))
			_detail_sprinter_head(p, variant, pal)
		"elite":
			# Breiter Schädel, kantiges Kinn, Showmaster-Grinsen.
			p.ball(Vector3(0.0, 0.006, 0.004), Vector3(0.094, 0.1, 0.098), skin)
			p.box(Vector3(0.0, -0.066, -0.02), Vector3(0.14, 0.07, 0.13), skin, Vector3(0.1, 0.0, 0.0))
			p.box(Vector3(0.0, -0.058, -0.086), Vector3(0.108, 0.04, 0.012), COLOR_MOUTH)
			p.box(Vector3(0.0, -0.05, -0.091), Vector3(0.098, 0.017, 0.01), COLOR_TEETH)
			p.box(Vector3(0.0, -0.068, -0.091), Vector3(0.086, 0.01, 0.01), COLOR_TEETH)
			p.ball(Vector3(0.0, -0.012, -0.098), Vector3(0.018, 0.024, 0.016), skin_dark)
			for side: float in [-1.0, 1.0]:
				p.ball(Vector3(side * 0.038, 0.024, -0.078), Vector3(0.03, 0.022, 0.02), COLOR_MOUTH)
				p.box(Vector3(side * 0.04, 0.05, -0.084), Vector3(0.056, 0.018, 0.03), pal["hair"], Vector3(0.0, 0.0, side * 0.36))
				p.ball(Vector3(side * 0.094, 0.0, 0.004), Vector3(0.014, 0.028, 0.02), skin_dark)
				# Koteletten.
				p.box(Vector3(side * 0.086, -0.02, -0.03), Vector3(0.014, 0.07, 0.034), pal["hair"])
			_detail_elite_head(p, variant, pal)
		_:
			# Runder Schädel, schief hängender Kiefer.
			p.ball(Vector3(0.0, 0.006, 0.004), Vector3(0.09, 0.102, 0.098), skin)
			p.ball(Vector3(0.008, -0.064, -0.028), Vector3(0.062, 0.044, 0.062), skin_dark, Vector3(0.0, 0.0, 0.14))
			p.box(Vector3(0.004, -0.05, -0.08), Vector3(0.066, 0.036, 0.03), COLOR_MOUTH, Vector3(0.0, 0.0, 0.1))
			p.box(Vector3(-0.016, -0.038, -0.094), Vector3(0.014, 0.014, 0.008), COLOR_TEETH)
			p.box(Vector3(0.006, -0.038, -0.094), Vector3(0.014, 0.016, 0.008), COLOR_TEETH)
			p.box(Vector3(0.022, -0.062, -0.092), Vector3(0.014, 0.014, 0.008), COLOR_TEETH)
			p.ball(Vector3(0.0, -0.006, -0.098), Vector3(0.014, 0.02, 0.014), skin_dark)
			for side: float in [-1.0, 1.0]:
				p.ball(Vector3(side * 0.036, 0.024, -0.076), Vector3(0.03, 0.029, 0.02), COLOR_MOUTH)
				p.box(Vector3(side * 0.036, 0.058, -0.082), Vector3(0.05, 0.014, 0.03), skin_dark, Vector3(0.0, 0.0, -side * 0.24))
				p.ball(Vector3(side * 0.09, 0.0, 0.004), Vector3(0.014, 0.026, 0.02), skin_dark)
			_detail_walker_head(p, variant, pal)
	return p


static func _detail_walker_head(p: Part, variant: int, pal: Dictionary) -> void:
	var hair: Color = pal["hair"]
	match variant:
		0:
			# Seitenscheitel.
			p.ball(Vector3(0.0, 0.05, 0.022), Vector3(0.094, 0.066, 0.094), hair)
			p.box(Vector3(-0.03, 0.082, -0.06), Vector3(0.08, 0.024, 0.05), hair, Vector3(0.3, 0.0, 0.2))
		1:
			# Glatze mit drei grauen Büscheln.
			for i: int in 3:
				var x: float = -0.05 + 0.05 * float(i)
				p.tube(Vector3(x, 0.104, 0.01), 0.014, 0.0, 0.04, hair, Vector3(0.0, 0.0, -x * 6.0), 1.0, 5)
			for side: float in [-1.0, 1.0]:
				p.ball(Vector3(side * 0.082, 0.02, 0.03), Vector3(0.02, 0.036, 0.05), hair)
		2:
			# Lange Strähnen hängen über Ohren und Nacken.
			p.ball(Vector3(0.0, 0.052, 0.018), Vector3(0.096, 0.064, 0.098), hair)
			for side: float in [-1.0, 1.0]:
				p.box(Vector3(side * 0.09, -0.03, 0.02), Vector3(0.02, 0.13, 0.07), hair, Vector3(0.0, 0.0, side * 0.08))
			p.box(Vector3(0.0, -0.02, 0.094), Vector3(0.13, 0.12, 0.02), hair)
		_:
			# Dünne Strähne quer über die Glatze, dazu ein Verband.
			p.box(Vector3(0.01, 0.1, 0.0), Vector3(0.12, 0.012, 0.05), hair, Vector3(0.0, 0.4, 0.1))
			p.tube(Vector3(0.0, 0.058, 0.004), 0.093, 0.084, 0.03, pal["shirt"], Vector3(0.0, 0.0, 0.2))


## Sprechgarnitur: Bügel über den Kopf, Ohrmuschel und Mikrofon-Bügel bis vor den Mund.
static func _detail_sprinter_head(p: Part, variant: int, pal: Dictionary) -> void:
	var dark: Color = pal["hair"]
	var side: float = -1.0 if variant % 2 == 0 else 1.0
	for i: int in 5:
		var angle: float = deg_to_rad(-72.0 + 36.0 * float(i))
		p.box(Vector3(sin(angle) * 0.088, 0.008 + cos(angle) * 0.102, 0.004), Vector3(0.058, 0.012, 0.024), dark,
				Vector3(0.0, 0.0, -angle))
	p.tube(Vector3(side * 0.086, 0.004, 0.004), 0.032, 0.032, 0.026, dark, Vector3(0.0, 0.0, PI * 0.5))
	p.tube(Vector3(-side * 0.084, 0.004, 0.004), 0.02, 0.02, 0.016, dark, Vector3(0.0, 0.0, PI * 0.5))
	p.box(Vector3(side * 0.078, -0.03, -0.052), Vector3(0.008, 0.008, 0.12), dark, Vector3(-0.5, side * 0.3, 0.0))
	p.ball(Vector3(side * 0.05, -0.056, -0.104), Vector3(0.016, 0.016, 0.02), pal["accent"])
	match variant:
		1:
			# Schirmmütze, verkehrt herum.
			p.ball(Vector3(0.0, 0.06, 0.006), Vector3(0.086, 0.052, 0.1), pal["cloth"])
			p.box(Vector3(0.0, 0.05, 0.11), Vector3(0.1, 0.01, 0.06), pal["cloth"], Vector3(-0.2, 0.0, 0.0))
		2:
			# Stirnband.
			p.tube(Vector3(0.0, 0.054, 0.004), 0.086, 0.078, 0.026, pal["accent"])
		_:
			pass


## Krone des Stargasts, dazu je nach Variante ein Schnurrbart.
static func _detail_elite_head(p: Part, variant: int, pal: Dictionary) -> void:
	var crown: Color = pal["crown"]
	p.tube(Vector3(0.0, 0.1, 0.004), 0.068, 0.082, 0.04, crown, Vector3.ZERO, 1.0, 10)
	for i: int in 5:
		var angle: float = TAU * float(i) / 5.0 + PI * 0.5
		var rim: Vector3 = Vector3(cos(angle) * 0.076, 0.138, 0.004 - sin(angle) * 0.076)
		p.tube(rim, 0.016, 0.0, 0.042, crown, Vector3.ZERO, 1.0, 4)
		p.ball(Vector3(cos(angle) * 0.078, 0.102, 0.004 - sin(angle) * 0.078), Vector3(0.012, 0.012, 0.012), pal["accent"])
	if variant >= 2:
		for side: float in [-1.0, 1.0]:
			p.box(Vector3(side * 0.03, -0.034, -0.094), Vector3(0.058, 0.014, 0.014), pal["hair"], Vector3(0.0, 0.0, -side * 0.28))


## Augen. Eigenes Netz mit unbeleuchtetem Material: Sie leuchten und zeigen die Blickrichtung.
static func _build_eyes(type: String, variant: int, unit: float) -> Part:
	var p: Part = Part.new(unit)
	match type:
		"sprinter":
			for side: float in [-1.0, 1.0]:
				p.ball(Vector3(side * 0.034, 0.026, -0.088), Vector3(0.017, 0.011, 0.01), Color.WHITE, Vector3(0.0, 0.0, side * 0.35))
		"elite":
			for side: float in [-1.0, 1.0]:
				p.ball(Vector3(side * 0.038, 0.024, -0.092), Vector3(0.022, 0.014, 0.01), Color.WHITE, Vector3(0.0, 0.0, side * 0.3))
		_:
			# Ein großes und ein kleines Auge: Der Kandidat hat schon bessere Tage gesehen.
			var big: float = -1.0 if variant % 2 == 0 else 1.0
			p.ball(Vector3(big * 0.036, 0.026, -0.088), Vector3(0.025, 0.025, 0.012), Color.WHITE)
			p.ball(Vector3(-big * 0.036, 0.022, -0.09), Vector3(0.016, 0.016, 0.01), Color.WHITE)
	return p


## Oberarm. Ursprung ist das Schultergelenk, der Arm zeigt nach unten (-Y) bis zum Ellbogen.
static func _build_upper_arm(type: String, variant: int, unit: float, m: Dictionary, pal: Dictionary, side: float) -> Part:
	var p: Part = Part.new(unit)
	var length: float = m["upper_arm"]
	var radius: float = m["arm_r"]
	var sleeve: Color = pal["cloth"]
	var cap: Color = pal["cloth"]
	match type:
		"sprinter":
			sleeve = pal["skin"]
			cap = pal["skin"]
		"elite":
			cap = pal["cloth_light"]
		_:
			# Variante 2: Der linke Ärmel ist abgerissen.
			if variant == 2 and side < 0.0:
				sleeve = pal["skin"]
	p.ball(Vector3.ZERO, Vector3.ONE * radius * 1.22, cap)
	p.tube(Vector3(0.0, -length * 0.5, 0.0), radius * 0.86, radius, length, sleeve)
	p.ball(Vector3(0.0, -length, 0.0), Vector3.ONE * radius * 0.9, sleeve)
	if type == "sprinter" and variant % 2 == 0:
		# Crew-Armbinde.
		p.tube(Vector3(0.0, -length * 0.45, 0.0), radius * 1.12, radius * 1.16, 0.03, pal["accent"])
	elif type == "walker" and variant == 2 and side < 0.0:
		# Rest des Ärmels als ausgefranster Ring.
		p.tube(Vector3(0.0, -0.02, 0.0), radius * 1.3, radius * 1.18, 0.04, pal["cloth_dark"])
	return p


## Unterarm mit Hand. Ursprung ist der Ellbogen, der Arm zeigt nach unten (-Y).
static func _build_forearm(type: String, variant: int, unit: float, m: Dictionary, pal: Dictionary, side: float) -> Part:
	var p: Part = Part.new(unit)
	var length: float = m["forearm"]
	var hand: float = m["hand"]
	var radius: float = float(m["arm_r"]) * 0.86
	var skin: Color = pal["skin"]
	var wrist: Vector3 = Vector3(0.0, -length, 0.0)
	match type:
		"sprinter":
			p.tube(Vector3(0.0, -length * 0.5, 0.0), radius * 0.74, radius, length, skin)
			p.ball(wrist + Vector3(0.0, -hand * 0.3, 0.0), Vector3(radius * 1.0, hand * 0.45, radius * 1.3), pal["skin_dark"])
			# Lange Krallen.
			for i: int in 3:
				var spread: float = float(i - 1)
				p.tube(wrist + Vector3(spread * 0.012, -hand * 0.95, -0.006), 0.0, 0.007, hand * 0.9, COLOR_INK,
						Vector3(0.12, 0.0, spread * 0.2), 1.0, 4)
		"elite":
			p.tube(Vector3(0.0, -length * 0.5, 0.0), radius * 0.88, radius, length, pal["cloth"])
			p.tube(wrist + Vector3(0.0, 0.018, 0.0), radius * 1.04, radius * 1.04, 0.04, pal["accent"])
			p.ball(wrist + Vector3(0.0, -hand * 0.45, 0.0), Vector3(radius * 1.18, hand * 0.62, radius * 1.3), skin)
			if side > 0.0:
				# Mikrofon in der rechten Faust.
				var grip: Vector3 = wrist + Vector3(0.0, -hand * 0.5, -0.03)
				p.tube(grip, 0.012, 0.012, 0.12, COLOR_INK, Vector3(PI * 0.5, 0.0, 0.0))
				p.ball(grip + Vector3(0.0, 0.0, -0.075), Vector3.ONE * 0.03, COLOR_METAL)
		_:
			var torn: bool = variant == 2 and side < 0.0
			var sleeve: Color = skin if torn else pal["cloth"]
			if variant == 3:
				sleeve = pal["shirt"]
			p.tube(Vector3(0.0, -length * 0.5, 0.0), radius * 0.8, radius, length, sleeve)
			if not torn:
				p.tube(wrist + Vector3(0.0, 0.016, 0.0), radius * 0.92, radius * 0.96, 0.03, pal["shirt"])
			p.ball(wrist + Vector3(0.0, -hand * 0.36, 0.0), Vector3(radius * 0.95, hand * 0.5, radius * 1.2), skin)
			for i: int in 3:
				p.box(wrist + Vector3(float(i - 1) * 0.014, -hand * 0.92, -0.004), Vector3(0.011, hand * 0.5, 0.012), pal["skin_dark"],
						Vector3(0.2, 0.0, float(i - 1) * 0.12))
	return p


## Oberschenkel. Ursprung ist das Hüftgelenk, das Bein zeigt nach unten bis zum Knie.
static func _build_thigh(type: String, unit: float, m: Dictionary, pal: Dictionary) -> Part:
	var p: Part = Part.new(unit)
	var length: float = m["thigh"]
	var radius: float = m["leg_r"]
	p.ball(Vector3.ZERO, Vector3.ONE * radius * 1.04, pal["pants"])
	if type == "sprinter":
		# Kurze Hose: unten schaut das Bein heraus.
		p.tube(Vector3(0.0, -length * 0.3, 0.0), radius * 1.02, radius * 1.06, length * 0.6, pal["pants"])
		p.tube(Vector3(0.0, -length * 0.78, 0.0), radius * 0.8, radius * 0.88, length * 0.46, pal["skin"])
		p.ball(Vector3(0.0, -length, 0.0), Vector3.ONE * radius * 0.84, pal["skin"])
	else:
		p.tube(Vector3(0.0, -length * 0.5, 0.0), radius * 0.82, radius, length, pal["pants"])
		p.ball(Vector3(0.0, -length, 0.0), Vector3.ONE * radius * 0.84, pal["pants"])
	return p


## Unterschenkel mit Schuh. Ursprung ist das Knie, die Sohle liegt bei -(shin + ankle).
static func _build_shin(type: String, variant: int, unit: float, m: Dictionary, pal: Dictionary, side: float) -> Part:
	var p: Part = Part.new(unit)
	var length: float = m["shin"]
	var ankle: float = m["ankle"]
	var radius: float = float(m["leg_r"]) * 0.8
	var leg: Color = pal["pants"]
	if type == "sprinter":
		leg = pal["skin"]
	elif type == "walker" and (variant == 1 or variant == 2) and side > 0.0:
		# Rechtes Hosenbein abgerissen.
		leg = pal["skin"]
		p.tube(Vector3(0.0, -0.016, 0.0), radius * 1.12, radius * 1.04, 0.04, pal["pants"])
	p.tube(Vector3(0.0, -length * 0.5, 0.0), radius * 0.74, radius, length, leg)
	# Schuh: Ferse am Knöchel, Spitze nach vorn und leicht nach oben (FOOT_TOE_UP).
	var foot_turn: Basis = Basis.from_euler(Vector3(FOOT_TOE_UP, 0.0, 0.0))
	var ankle_at: Vector3 = Vector3(0.0, -length, 0.0)
	var foot_w: float = radius * 1.06
	var foot_len: float = 0.085 if type != "elite" else 0.092
	p.ball(ankle_at + foot_turn * Vector3(0.0, -ankle * 0.45, -foot_len * 0.42), Vector3(foot_w, ankle * 0.6, foot_len),
			pal["shoes"], Vector3(FOOT_TOE_UP, 0.0, 0.0))
	match type:
		"sprinter":
			# Farbiger Streifen am Turnschuh, Socke.
			p.tube(ankle_at + Vector3(0.0, 0.02, 0.0), radius * 0.86, radius * 0.9, 0.04, pal["shoes"])
			p.box(ankle_at + foot_turn * Vector3(0.0, -ankle * 0.5, -foot_len * 0.5), Vector3(foot_w * 2.06, 0.012, foot_len * 1.1),
					pal["accent"], Vector3(FOOT_TOE_UP, 0.0, 0.0))
		"elite":
			# Gamaschen über den weißen Schuhen.
			p.tube(ankle_at + Vector3(0.0, 0.024, 0.0), radius * 0.92, radius * 0.98, 0.05, pal["accent"])
		_:
			pass
	return p
