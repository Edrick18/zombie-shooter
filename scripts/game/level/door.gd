extends StaticBody3D
## Modul: Level (scripts/game/level).
## Kaufbare Tür zu einem Raum (Backstage, Kantine, Garderobe, Regieraum). Sperrt als Körper den
## Durchgang (Lage 1) und ist zugleich Interaktionsobjekt (Lage 5, Gruppe "interactables").
## Gehört nicht zur Gruppe "nav_source": Das Navigationsnetz führt durch die Türöffnung (das Level
## schaltet das Netz eines Raums erst frei, wenn er gekauft ist).
##
## Ursprung = Mitte der Unterkante. Lokal X ist die Breite, lokal Z die Dicke (beide Seiten
## sind beschriftet). Eine Lampe im Türblatt zeigt, ob die Punkte reichen (grün) oder nicht (rot).
##
## Eine Tür verkauft den Raum "zone". Wird er gekauft (an dieser oder an einer anderen Tür), gehen
## alle Türen dieses Raums auf: Kollision weg, Türblatt fährt hoch und verschwindet, Spawnpunkte
## des Raums werden aktiv (Meta "active" = true), kein Hinweis mehr.
##
## Verbindungstür (back_zone > 0): Sie liegt zwischen zwei kaufbaren Räumen und geht erst auf,
## wenn beide gekauft sind. Ist einer offen, verkauft sie den anderen: zone, zone_name und cost
## nennen immer den Raum, den es an dieser Tür gerade zu kaufen gibt.
##
## Bei Events.run_started (neuer Lauf in derselben Szene) schließt sich jede Tür wieder.

const Balance := preload("res://scripts/core/balance.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

## Alle Türen des Levels. Darüber erfährt jede Tür, dass ein Raum gekauft wurde.
const GROUP_DOORS: String = "doors"

## Wird genau einmal gesendet, wenn die Tür aufgeht.
signal opened
## Wird gesendet, wenn sich eine offene Tür wieder schließt (neuer Lauf).
signal closed

var is_open: bool = false
## Preis in Punkten.
var cost: int = Balance.DOOR_COST
## Raum hinter der Tür: Dessen Spawnpunkte werden beim Öffnen aktiv.
var zone: int = 2
## Name des Raums für Hinweis und Banner.
var zone_name: String = "Backstage"
## Nur Verbindungstür: der kaufbare Raum auf der anderen Seite, sein Name und Preis.
## 0 = keine Verbindungstür (die andere Seite ist die Bühne und immer offen).
var back_zone: int = 0
var back_zone_name: String = ""
var back_cost: int = 0
## Maße des Türblatts (Breite, Höhe, Dicke). Vor add_child setzen.
var size: Vector3 = Vector3(2.4, 3.0, 0.3)

# Optik.
const COLOR_LEAF: Color = Color(0.86, 0.14, 0.5)
const COLOR_PANEL: Color = Color(0.22, 0.05, 0.3)
const COLOR_GOLD: Color = Color(1.0, 0.8, 0.12)
const COLOR_BLACK: Color = Color(0.06, 0.06, 0.07)
const COLOR_LAMP_YES: Color = Color(0.3, 1.0, 0.35)
const COLOR_LAMP_NO: Color = Color(1.0, 0.15, 0.1)
const OPEN_TIME: float = 0.75
const STRIPE_COUNT: int = 8
## Schriftgröße des Raumnamens in Metern und die Zeichenzahl, ab der sie kleiner wird.
const NAME_HEIGHT: float = 0.3
const NAME_FULL_LENGTH: int = 9

var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _lamp_material: StandardMaterial3D
var _lamp_state: int = -1
var _slide_tween: Tween
var _shake_tween: Tween
var _name_labels: Array[Label3D] = []
var _cost_labels: Array[Label3D] = []
## true: Der Raum auf der anderen Seite ist offen (ohne Verbindung immer).
var _back_open: bool = true
## Die Belegung beim Bau: [zone, zone_name, cost, back_zone, back_zone_name, back_cost].
var _home: Array = []


func _ready() -> void:
	add_to_group("interactables")
	add_to_group(GROUP_DOORS)
	_home = [zone, zone_name, cost, back_zone, back_zone_name, back_cost]
	_back_open = back_zone <= 0
	collision_layer = Balance.LAYER_WORLD | Balance.LAYER_INTERACTABLES
	collision_mask = 0
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	_shape = CollisionShape3D.new()
	_shape.name = "Shape"
	_shape.shape = box
	_shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(_shape)
	_build_leaf()
	Events.run_started.connect(close)
	if is_open:
		# open() lief schon vor _ready (Tür außerhalb des Baums geöffnet).
		remove_from_group("interactables")
		collision_layer = 0
		_shape.disabled = true
		_mesh.visible = false
		set_process(false)


## Hinweistext für den Blick des Spielers, "" wenn die Tür offen ist.
## Reichen die Punkte nicht, nennt der Hinweis den Preis und wie viel fehlt, ohne "E –"
## ("Backstage (750) – dir fehlen 320 Punkte").
func get_prompt() -> String:
	if is_open:
		return ""
	if Game.can_afford(cost):
		return "E – %s öffnen (%d)" % [zone_name, cost]
	return "%s (%d) – dir fehlen %d Punkte" % [zone_name, cost, cost - Game.points]


## Der Spieler drückt E: Reichen die Punkte, wird bezahlt und der Raum geht auf.
## Sonst gibt es ein Banner und das Türblatt rüttelt.
func interact(_player: Node3D) -> void:
	if is_open:
		return
	if Game.spend_points(cost):
		open()
	else:
		Events.banner.emit("Nicht genug Punkte! Dir fehlen %d." % maxi(cost - Game.points, 0))
		_shake()


## Öffnet den Raum dieser Tür ohne Bezahlung (interact ruft das nach dem Bezahlen, Tests direkt).
## Wirkt nur einmal: Spawnpunkte des Raums aktiv, alle Türen des Raums gehen auf (jede sendet
## opened), ein Banner. Eine Verbindungstür, deren andere Seite noch zu ist, bleibt dabei
## geschlossen und verkauft ab dann den anderen Raum.
func open() -> void:
	if is_open:
		return
	var sold_zone: int = zone
	var sold_name: String = zone_name
	if is_inside_tree():
		_set_spawns_active(sold_zone, true)
		for node: Node in get_tree().get_nodes_in_group(GROUP_DOORS):
			if node.has_method("zone_opened"):
				node.call("zone_opened", sold_zone)
	else:
		zone_opened(sold_zone)
	Events.banner.emit("%s ist offen!" % sold_name)


## Meldung an jede Tür: Der Raum opened_zone wurde gekauft. Die Tür geht auf, wenn damit beide
## Seiten offen sind. Wer einen Raum öffnen will, ruft open() an einer seiner Türen.
func zone_opened(opened_zone: int) -> void:
	if is_open:
		return
	if opened_zone == zone:
		if _back_open:
			_open_leaf()
		else:
			# Verbindungstür: Diese Seite ist jetzt offen, zu kaufen gibt es hier den Raum dahinter.
			var sold: Array = [zone, zone_name, cost]
			zone = back_zone
			zone_name = back_zone_name
			cost = back_cost
			back_zone = int(sold[0])
			back_zone_name = String(sold[1])
			back_cost = int(sold[2])
			_back_open = true
			_refresh_text()
	elif opened_zone == back_zone:
		_back_open = true


## Schließt die Tür wieder (neuer Lauf in derselben Szene, Events.run_started): Kollision an,
## Türblatt unten, Spawnpunkte ihrer Räume aus, wieder Interaktionsobjekt, Belegung wie beim Bau.
func close() -> void:
	if not _home.is_empty():
		zone = int(_home[0])
		zone_name = String(_home[1])
		cost = int(_home[2])
		back_zone = int(_home[3])
		back_zone_name = String(_home[4])
		back_cost = int(_home[5])
	_back_open = back_zone <= 0
	_lamp_state = -1
	_refresh_text()
	if not is_open:
		return
	is_open = false
	add_to_group("interactables")
	collision_layer = Balance.LAYER_WORLD | Balance.LAYER_INTERACTABLES
	set_process(true)
	if is_instance_valid(_slide_tween):
		_slide_tween.kill()
	if is_instance_valid(_shape):
		_shape.set_deferred("disabled", false)
	if is_instance_valid(_mesh):
		_mesh.position = Vector3(0.0, size.y * 0.5, 0.0)
		_mesh.visible = true
	if is_inside_tree():
		_set_spawns_active(zone, false)
		if back_zone > 0:
			_set_spawns_active(back_zone, false)
	closed.emit()


func _process(_delta: float) -> void:
	var state: int = 1 if Game.can_afford(cost) else 0
	if state == _lamp_state or _lamp_material == null:
		return
	_lamp_state = state
	_lamp_material.albedo_color = COLOR_LAMP_YES if state == 1 else COLOR_LAMP_NO


func _set_spawns_active(spawn_zone: int, active: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group("zombie_spawns"):
		if int(node.get_meta("zone", 1)) == spawn_zone:
			node.set_meta("active", active)


## Die Tür selbst geht auf: Kollision weg, Türblatt fährt hoch, kein Interaktionsobjekt mehr.
func _open_leaf() -> void:
	is_open = true
	remove_from_group("interactables")
	collision_layer = 0
	set_process(false)
	if is_instance_valid(_shape):
		_shape.set_deferred("disabled", true)
	if is_inside_tree():
		Fx.confetti(Fx.root_of(self), global_position + Vector3(0.0, size.y * 0.6, 0.0))
	_slide_open()
	opened.emit()


## Türblatt (Knoten "Leaf") mit Warnstreifen, Preisschild auf beiden Seiten und Lampe.
func _build_leaf() -> void:
	var slab: BoxMesh = BoxMesh.new()
	slab.size = size
	slab.material = _flat(COLOR_LEAF)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Leaf"
	_mesh.mesh = slab
	_mesh.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(_mesh)

	# Warnstreifen oben und unten: abwechselnd gold und schwarz, auf beiden Seiten sichtbar.
	var stripe_width: float = size.x / float(STRIPE_COUNT)
	for row: float in [-1.0, 1.0]:
		for i: int in range(STRIPE_COUNT):
			var color: Color = COLOR_GOLD if (i + (0 if row < 0.0 else 1)) % 2 == 0 else COLOR_BLACK
			var center: Vector3 = Vector3(-size.x * 0.5 + stripe_width * (float(i) + 0.5), row * (size.y * 0.5 - 0.17), 0.0)
			_add_box(Vector3(stripe_width, 0.34, size.z + 0.04), center, _flat(color))

	# Dunkles Feld mit goldenem Rahmen für die Schrift.
	var panel_size: Vector2 = Vector2(size.x * 0.82, minf(1.5, size.y * 0.5))
	_add_box(Vector3(panel_size.x + 0.12, panel_size.y + 0.12, size.z + 0.02), Vector3.ZERO, _flat(COLOR_GOLD))
	_add_box(Vector3(panel_size.x, panel_size.y, size.z + 0.04), Vector3.ZERO, _flat(COLOR_PANEL))
	var face: float = size.z * 0.5 + 0.025
	for side: float in [-1.0, 1.0]:
		var yaw: float = 0.0 if side > 0.0 else 180.0
		_name_labels.append(_add_label("", Vector3(0.0, panel_size.y * 0.5 - 0.28, side * face), yaw, NAME_HEIGHT, Color(1.0, 0.55, 0.8)))
		_cost_labels.append(_add_label("", Vector3(0.0, -0.05, side * face), yaw, 0.62, COLOR_GOLD))
		_add_label("PUNKTE", Vector3(0.0, -panel_size.y * 0.5 + 0.2, side * face), yaw, 0.2, Color(0.95, 0.95, 0.9))
	_refresh_text()

	# Lampe über dem Feld: grün, sobald die Punkte reichen.
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_material.albedo_color = COLOR_LAMP_NO
	_add_box(Vector3(0.6, 0.2, size.z + 0.06), Vector3(0.0, panel_size.y * 0.5 + 0.32, 0.0), _lamp_material)


## Schreibt Raum und Preis auf beide Seiten des Türblatts. Lange Namen werden kleiner gesetzt,
## damit sie in das Feld passen.
func _refresh_text() -> void:
	var title: String = zone_name.to_upper()
	var height: float = NAME_HEIGHT * minf(1.0, float(NAME_FULL_LENGTH) / float(maxi(title.length(), 1)))
	for label: Label3D in _name_labels:
		if is_instance_valid(label):
			label.text = title
			label.pixel_size = height / float(label.font_size)
	for label: Label3D in _cost_labels:
		if is_instance_valid(label):
			label.text = str(cost)


func _add_box(box_size: Vector3, center: Vector3, material: Material) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = box_size
	box.material = material
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = "Part"
	part.mesh = box
	part.position = center
	_mesh.add_child(part, true)


func _add_label(text: String, pos: Vector3, yaw_deg: float, height: float, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = text
	label.font_size = 128
	label.pixel_size = height / 128.0
	label.outline_size = 24
	label.modulate = color
	label.outline_modulate = COLOR_BLACK
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	label.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	_mesh.add_child(label, true)
	return label


func _flat(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.metallic_specular = 0.2
	return material


## Türblatt holt kurz Schwung und fährt dann nach oben in die Wand, danach ist es unsichtbar.
func _slide_open() -> void:
	if not is_instance_valid(_mesh):
		return
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	if not is_inside_tree():
		_mesh.visible = false
		return
	_mesh.position.x = 0.0
	if _lamp_material != null:
		_lamp_material.albedo_color = COLOR_LAMP_YES
	_slide_tween = create_tween()
	_slide_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_slide_tween.tween_property(_mesh, "position:y", size.y * 1.5 - 0.02, OPEN_TIME)
	_slide_tween.tween_callback(_mesh.hide)


## Kurzes Rütteln: Die Tür bleibt zu.
func _shake() -> void:
	if not is_instance_valid(_mesh) or not is_inside_tree():
		return
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	_mesh.position.x = 0.0
	_shake_tween = create_tween()
	for offset: float in [0.07, -0.06, 0.04, -0.03, 0.0]:
		_shake_tween.tween_property(_mesh, "position:x", offset, 0.045)
