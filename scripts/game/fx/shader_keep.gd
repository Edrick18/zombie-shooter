extends RefCounted
## Modul: FX (scripts/game/fx).
## Hält Shader am Leben und merkt sich, welche Material-Arten das Spiel benutzt.
##
## Warum: Godot übersetzt den Shader einer Material-Art beim ersten Zeichnen (ein Ruckler) und
## wirft ihn wieder weg, sobald das letzte Material dieser Art verschwindet. Ohne dieses Skript
## ruckelte deshalb jede Kiste, jede Explosion und jeder Elite-Zombie aufs Neue.
##
## Wie: Jeder Knoten, der in den Baum kommt, wird angesehen (Game verbindet dafür
## SceneTree.node_added mit track_node). Von jeder neuen Material-Art bleibt eine Kopie für immer
## im Speicher, damit lebt auch ihr Shader weiter. Die Art ist ein Text aus allen Schaltern des
## Materials (Schlüssel), Farben und andere Zahlen gehören nicht dazu.
##
## Die Liste der Arten wird gespeichert (user://shader_warmup.json) und beim nächsten Start von
## warmup.gd vorab gezeichnet. Mit dem Spiel kommt eine fertige Liste mit
## (res://data/shader_warmup.json, erzeugt von tests/perf_game.gd mit "-- record").
##
## Nur statische Funktionen. Einbinden mit preload, keine Knoten, kein Spielzustand.

const SHIPPED_LIST: String = "res://data/shader_warmup.json"
const USER_LIST: String = "user://shader_warmup.json"

## Wie eine Material-Art gezeichnet wird: als normales Mesh oder als Partikel (eigene Shader-Variante).
const USE_MESH: int = 1
const USE_PARTICLES: int = 2

## Eigenschaften, die den Shader nicht verändern oder nichts mit ihm zu tun haben.
const IGNORED_PROPERTIES: Array[String] = [
	"script", "next_pass", "render_priority", "resource_local_to_scene",
]
## Eigenschaften eines Label3D, die seine Shader-Art und seine Schrift-Textur bestimmen.
const LABEL_PROPERTIES: Array[String] = [
	"billboard", "shaded", "double_sided", "no_depth_test", "fixed_size", "alpha_cut",
	"alpha_antialiasing_mode", "texture_filter", "font_size", "outline_size",
]
const SEEN_LIMIT: int = 4096

## Schlüssel -> Kopie eines Materials dieser Art (hält den Shader am Leben).
static var _held: Dictionary = {}
## Schlüssel -> Bitmaske aus USE_MESH und USE_PARTICLES.
static var _usage: Dictionary = {}
## Schlüssel -> Einstellungen eines Label3D (Dictionary).
static var _labels: Dictionary = {}
## Instanz-IDs schon angesehener Materialien (spart die Schlüssel-Berechnung).
static var _seen: Dictionary = {}
## Namen der Eigenschaften, die in den Schlüssel eingehen (einmal ermittelt).
static var _property_names: PackedStringArray = PackedStringArray()
static var _property_is_object: Dictionary = {}
static var _defaults: Dictionary = {}
static var _placeholder_texture: ImageTexture = null
## true: Jede neu gelernte Art wird sofort in USER_LIST gespeichert (schaltet warmup.gd ein).
static var autosave: bool = false
static var _dirty: bool = false


## Sieht sich einen Knoten an, der in den Baum kommt. Billig für alles, was kein 3D-Körper ist.
static func track_node(node: Node) -> void:
	if not (node is GeometryInstance3D):
		return
	if node is Label3D:
		_track_label(node as Label3D)
		return
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	var usage: int = USE_MESH
	var mesh: Mesh = null
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		mesh = instance.mesh
		if mesh != null:
			for i: int in instance.get_surface_override_material_count():
				hold(instance.get_surface_override_material(i), usage)
	elif node is CPUParticles3D:
		usage = USE_PARTICLES
		mesh = (node as CPUParticles3D).mesh
	elif node is MultiMeshInstance3D:
		usage = USE_PARTICLES
		var multimesh: MultiMesh = (node as MultiMeshInstance3D).multimesh
		if multimesh != null:
			mesh = multimesh.mesh
	hold(geometry.material_override, usage)
	hold(geometry.material_overlay, usage)
	if mesh != null:
		for i: int in mesh.get_surface_count():
			hold(mesh.surface_get_material(i), usage)


## Merkt sich die Art dieses Materials und hält ihren Shader am Leben. null und fremde
## Material-Klassen werden übergangen.
static func hold(material: Material, usage: int = USE_MESH) -> void:
	if material == null or not (material is BaseMaterial3D):
		return
	var id: int = material.get_instance_id()
	if int(_seen.get(id, 0)) & usage == usage:
		return
	if _seen.size() >= SEEN_LIMIT:
		_seen.clear()
	_seen[id] = int(_seen.get(id, 0)) | usage
	var key: String = material_key(material as BaseMaterial3D)
	var known: int = int(_usage.get(key, 0))
	if known & usage == usage:
		return
	if not _held.has(key):
		# Eine Kopie halten: Der Besitzer darf sein Material danach verändern oder freigeben.
		_held[key] = material.duplicate()
	_usage[key] = known | usage
	_mark_changed()


## Schlüssel der Material-Art: alle Schalter (bool, Aufzählungen) und die Frage, welche Texturen
## gesetzt sind. Nur Abweichungen vom Standardmaterial stehen drin.
static func material_key(material: BaseMaterial3D) -> String:
	_prepare_properties()
	var parts: PackedStringArray = PackedStringArray()
	for property: String in _property_names:
		var value: Variant = material.get(property)
		if bool(_property_is_object[property]):
			if value != null:
				parts.append("T:" + property)
		elif value != _defaults[property]:
			parts.append("%s=%d" % [property, int(value)])
	return ",".join(parts)


## Baut aus einem Schlüssel wieder ein Material dieser Art (Farben bleiben Standard).
static func material_from_key(key: String) -> StandardMaterial3D:
	_prepare_properties()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	if key.is_empty():
		return material
	for part: String in key.split(","):
		if part.begins_with("T:"):
			var texture_property: String = part.substr(2)
			if _property_is_object.has(texture_property):
				material.set(texture_property, _placeholder())
			continue
		var pieces: PackedStringArray = part.split("=")
		if pieces.size() != 2 or not _defaults.has(pieces[0]):
			continue
		if typeof(_defaults[pieces[0]]) == TYPE_BOOL:
			material.set(pieces[0], pieces[1].to_int() != 0)
		else:
			material.set(pieces[0], pieces[1].to_int())
	return material


## Alle bekannten Material-Arten: Array aus {"key", "material", "usage"}.
static func material_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: String in _held:
		entries.append({"key": key, "material": _held[key], "usage": int(_usage.get(key, USE_MESH))})
	return entries


## Alle bekannten Label3D-Arten (Dictionary je Art, Schlüssel siehe LABEL_PROPERTIES).
static func label_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: String in _labels:
		entries.append(_labels[key])
	return entries


static func known_count() -> int:
	return _held.size() + _labels.size()


## Lädt die mitgelieferte und die selbst gelernte Liste. Schon bekannte Arten bleiben.
static func load_lists() -> void:
	var was_autosave: bool = autosave
	autosave = false
	for path: String in [SHIPPED_LIST, USER_LIST]:
		_load_list(path)
	autosave = was_autosave


## Speichert die gelernte Liste, falls seit dem letzten Speichern etwas dazukam.
static func save_if_changed() -> void:
	if _dirty:
		save_list(USER_LIST)


## Schreibt alle bekannten Arten als JSON nach path. Gibt false zurück, wenn das nicht geht.
static func save_list(path: String) -> bool:
	var materials: Array = []
	for key: String in _held:
		materials.append({"key": key, "usage": int(_usage.get(key, USE_MESH))})
	var labels: Array = []
	for key: String in _labels:
		labels.append(_labels[key])
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "materials": materials, "labels": labels}, "\t"))
	file.close()
	if path == USER_LIST:
		_dirty = false
	return true


## Vergisst alles (nur für Tests).
static func reset() -> void:
	_held.clear()
	_usage.clear()
	_labels.clear()
	_seen.clear()
	_dirty = false
	autosave = false


static func _load_list(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	var materials: Variant = data.get("materials", [])
	if typeof(materials) == TYPE_ARRAY:
		for entry: Variant in materials:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var key: String = str((entry as Dictionary).get("key", ""))
			var usage: int = int((entry as Dictionary).get("usage", USE_MESH))
			if not _held.has(key):
				_held[key] = material_from_key(key)
			_usage[key] = int(_usage.get(key, 0)) | usage
	var labels: Variant = data.get("labels", [])
	if typeof(labels) == TYPE_ARRAY:
		for entry: Variant in labels:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var settings: Dictionary = {}
			for property: String in LABEL_PROPERTIES:
				settings[property] = int((entry as Dictionary).get(property, 0))
			var label_key: String = JSON.stringify(settings)
			if not _labels.has(label_key):
				_labels[label_key] = settings


static func _track_label(label: Label3D) -> void:
	var settings: Dictionary = {}
	for property: String in LABEL_PROPERTIES:
		settings[property] = int(label.get(property))
	var key: String = JSON.stringify(settings)
	if _labels.has(key):
		return
	_labels[key] = settings
	_mark_changed()


static func _mark_changed() -> void:
	_dirty = true
	if autosave:
		save_list(USER_LIST)


static func _placeholder() -> ImageTexture:
	if _placeholder_texture == null:
		var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_placeholder_texture = ImageTexture.create_from_image(image)
	return _placeholder_texture


## Ermittelt einmal alle Schalter eines StandardMaterial3D und ihre Standardwerte.
static func _prepare_properties() -> void:
	if not _property_names.is_empty():
		return
	var reference: StandardMaterial3D = StandardMaterial3D.new()
	var names: PackedStringArray = PackedStringArray()
	for info: Dictionary in ClassDB.class_get_property_list("StandardMaterial3D"):
		var property: String = str(info.get("name", ""))
		var type: int = int(info.get("type", TYPE_NIL))
		if property.is_empty() or IGNORED_PROPERTIES.has(property) or names.has(property):
			continue
		if type != TYPE_BOOL and type != TYPE_INT and type != TYPE_OBJECT:
			continue
		names.append(property)
		_property_is_object[property] = type == TYPE_OBJECT
		_defaults[property] = reference.get(property)
	names.sort()
	_property_names = names
