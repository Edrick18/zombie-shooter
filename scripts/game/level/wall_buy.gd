extends StaticBody3D
## Modul: Level (scripts/game/level).
## Wandkauf: eine Waffe an der Wand (Lage 5, Gruppe "interactables"). Für "price" Punkte (aus
## WeaponDefs) gibt es die Waffe als gewöhnlichen Gegenstand: Game.grant_item legt sie in die
## Ablage und öffnet den Rucksack. Jeder Kauf gibt ein weiteres Exemplar (zwei gleiche lassen sich
## kombinieren). Munition wird nicht gekauft, sie ist unendlich.
##
## Ursprung = Mitte der Tafel auf der Wandfläche, lokal +Z zeigt in den Raum. Zu sehen sind eine
## dunkle Tafel mit leuchtendem Rahmen, der Umriss der Waffe aus Quadern, darüber der Name und
## darunter der Preis.

const Balance := preload("res://scripts/core/balance.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

## Waffe dieser Wand ("shotgun" oder "smg").
var weapon_id: String = "shotgun"

# Optik.
const BOARD_SIZE: Vector2 = Vector2(2.0, 1.25)
const COLOR_BOARD: Color = Color(0.09, 0.07, 0.16)
const COLOR_OUTLINE: Color = Color(0.02, 0.02, 0.03)
const COLOR_TEXT: Color = Color(0.97, 0.97, 0.92)
const COLOR_PRICE: Color = Color(1.0, 0.85, 0.2)
const ACCENT_COLORS: Dictionary = {
	"shotgun": Color(1.0, 0.5, 0.08),
	"smg": Color(0.1, 0.85, 1.0),
}
const ACCENT_DEFAULT: Color = Color(1.0, 0.8, 0.12)
## Umriss je Waffe: Liste von [Mitte x, Mitte y, Breite, Höhe] in Metern auf der Tafel.
const SILHOUETTES: Dictionary = {
	"shotgun": [
		[0.22, 0.13, 1.05, 0.09], [0.3, 0.03, 0.8, 0.07], [0.2, 0.01, 0.34, 0.14],
		[-0.36, 0.08, 0.42, 0.2], [-0.44, -0.1, 0.1, 0.18], [-0.68, 0.02, 0.26, 0.2], [-0.82, -0.04, 0.14, 0.26],
	],
	"smg": [
		[0.0, 0.1, 0.8, 0.2], [0.5, 0.12, 0.28, 0.08], [0.08, -0.2, 0.13, 0.44], [-0.24, -0.13, 0.12, 0.3],
		[-0.6, 0.14, 0.42, 0.07], [-0.8, 0.06, 0.08, 0.26], [0.12, 0.24, 0.2, 0.06],
	],
}
const SILHOUETTE_FALLBACK: Array = [[0.0, 0.06, 0.7, 0.16], [-0.25, -0.12, 0.14, 0.24]]
const SILHOUETTE_SCALE: float = 1.15

var _silhouette: Node3D
var _price_label: Label3D
var _frame_material: StandardMaterial3D
var _accent: Color = ACCENT_DEFAULT
var _time: float = 0.0
var _feedback_tween: Tween


## Legt die Waffe fest. Vor add_child aufrufen.
func setup(new_weapon_id: String) -> void:
	weapon_id = new_weapon_id


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = Balance.LAYER_INTERACTABLES
	collision_mask = 0
	_accent = ACCENT_COLORS.get(weapon_id, ACCENT_DEFAULT)
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(BOARD_SIZE.x + 0.1, BOARD_SIZE.y + 0.9, 0.3)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = box
	shape.position = Vector3(0.0, 0.0, 0.15)
	add_child(shape)
	_build_board()
	_build_silhouette()
	_build_labels()
	_refresh_price_label()


## Hinweistext: "E: Publikumsjoker kaufen (500 Punkte)" oder, wenn die Punkte nicht reichen,
## Preis und Fehlbetrag ohne "E:" ("Publikumsjoker (500 Punkte): dir fehlen 120 Punkte").
func get_prompt() -> String:
	var def: Dictionary = WeaponDefs.get_def(weapon_id)
	if def.is_empty():
		return ""
	var weapon_name: String = String(def["name"])
	var price: int = int(def["price"])
	if Game.can_afford(price):
		return "E: %s kaufen (%d Punkte)" % [weapon_name, price]
	return "%s (%d Punkte): dir fehlen %d Punkte" % [weapon_name, price, price - Game.points]


## Der Spieler drückt E: kauft die Waffe, wenn die Punkte reichen. Sie kommt als gewöhnlicher
## Gegenstand in die Ablage und der Rucksack öffnet sich (Game.grant_item). Kann Game den
## Gegenstand gerade nicht vergeben (kein laufendes Spiel, unbekannte Waffe), kostet es nichts.
func interact(player: Node3D) -> void:
	var def: Dictionary = WeaponDefs.get_def(weapon_id)
	if def.is_empty() or not is_instance_valid(player):
		return
	# Dieselben Bedingungen wie Game.grant_item: erst prüfen, dann zahlen.
	if Game.state != Game.State.PLAYING or not ItemDefs.is_weapon(weapon_id):
		return
	var price: int = int(def["price"])
	if not Game.can_afford(price):
		Events.banner.emit("Nicht genug Punkte! Dir fehlen %d." % maxi(price - Game.points, 0))
		_play_denied()
		return
	if not Game.spend_points(price):
		return
	Events.banner.emit("%s gekauft!" % String(def["name"]))
	_play_bought()
	Game.grant_item(weapon_id, 1)


func _process(delta: float) -> void:
	_time += delta
	if _frame_material != null:
		var pulse: float = 0.72 + 0.28 * sin(_time * 4.0)
		_frame_material.albedo_color = Color(_accent.r * pulse, _accent.g * pulse, _accent.b * pulse)


func _refresh_price_label() -> void:
	if not is_instance_valid(_price_label):
		return
	var def: Dictionary = WeaponDefs.get_def(weapon_id)
	if def.is_empty():
		return
	_price_label.text = "%d Punkte" % int(def["price"])


func _build_board() -> void:
	var board: MeshInstance3D = _box(Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.08), Vector3(0.0, 0.0, 0.04), _flat(COLOR_BOARD))
	board.name = "Sign"
	add_child(board)
	_frame_material = _unshaded(_accent)
	var half: Vector2 = BOARD_SIZE * 0.5
	for dy: float in [-1.0, 1.0]:
		add_child(_box(Vector3(BOARD_SIZE.x + 0.16, 0.08, 0.14), Vector3(0.0, dy * (half.y + 0.04), 0.07), _frame_material), true)
	for dx: float in [-1.0, 1.0]:
		add_child(_box(Vector3(0.08, BOARD_SIZE.y, 0.14), Vector3(dx * (half.x + 0.04), 0.0, 0.07), _frame_material), true)


## Umriss der Waffe: helle Quader vor etwas größeren dunklen Quadern (Kontur).
func _build_silhouette() -> void:
	_silhouette = Node3D.new()
	_silhouette.name = "Silhouette"
	_silhouette.position = Vector3(0.0, 0.0, 0.1)
	_silhouette.scale = Vector3.ONE * SILHOUETTE_SCALE
	add_child(_silhouette)
	var parts: Array = SILHOUETTES.get(weapon_id, SILHOUETTE_FALLBACK)
	var bright: StandardMaterial3D = _unshaded(COLOR_TEXT.lerp(_accent, 0.25))
	var dark: StandardMaterial3D = _unshaded(COLOR_OUTLINE)
	for part: Array in parts:
		var center: Vector3 = Vector3(float(part[0]), float(part[1]), 0.0)
		var extent: Vector2 = Vector2(float(part[2]), float(part[3]))
		_silhouette.add_child(_box(Vector3(extent.x + 0.07, extent.y + 0.07, 0.04), center + Vector3(0.0, 0.0, -0.015), dark), true)
		_silhouette.add_child(_box(Vector3(extent.x, extent.y, 0.08), center + Vector3(0.0, 0.0, 0.02), bright), true)


func _build_labels() -> void:
	var half_y: float = BOARD_SIZE.y * 0.5
	for dy: float in [-1.0, 1.0]:
		add_child(_box(Vector3(BOARD_SIZE.x, 0.4, 0.05), Vector3(0.0, dy * (half_y + 0.3), 0.025), _flat(COLOR_BOARD)), true)
	var name_label: Label3D = _label(WeaponDefs.display_name(weapon_id), Vector3(0.0, half_y + 0.3, 0.06), 0.28, COLOR_TEXT)
	name_label.name = "NameLabel"
	add_child(name_label)
	_price_label = _label("", Vector3(0.0, -half_y - 0.3, 0.06), 0.24, COLOR_PRICE)
	_price_label.name = "PriceLabel"
	add_child(_price_label)


func _box(box_size: Vector3, center: Vector3, material: Material) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = box_size
	box.material = material
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Part"
	mesh.mesh = box
	mesh.position = center
	return mesh


func _label(text: String, pos: Vector3, height: float, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = 128
	label.pixel_size = height / 128.0
	label.outline_size = 24
	label.modulate = color
	label.outline_modulate = COLOR_OUTLINE
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	return label


func _flat(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.metallic_specular = 0.2
	return material


func _unshaded(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


## Kauf geglückt: Der Umriss springt kurz auf, Konfetti.
func _play_bought() -> void:
	if not is_inside_tree() or not is_instance_valid(_silhouette):
		return
	Fx.confetti(Fx.root_of(self), global_position + global_transform.basis.z * 0.4)
	if is_instance_valid(_feedback_tween):
		_feedback_tween.kill()
	_silhouette.position.x = 0.0
	_silhouette.scale = Vector3.ONE * SILHOUETTE_SCALE * 1.35
	_feedback_tween = create_tween()
	_feedback_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(_silhouette, "scale", Vector3.ONE * SILHOUETTE_SCALE, 0.35)


## Kauf abgelehnt: Der Umriss rüttelt.
func _play_denied() -> void:
	if not is_inside_tree() or not is_instance_valid(_silhouette):
		return
	if is_instance_valid(_feedback_tween):
		_feedback_tween.kill()
	_silhouette.scale = Vector3.ONE * SILHOUETTE_SCALE
	_silhouette.position.x = 0.0
	_feedback_tween = create_tween()
	for offset: float in [0.07, -0.06, 0.04, -0.03, 0.0]:
		_feedback_tween.tween_property(_silhouette, "position:x", offset, 0.045)
