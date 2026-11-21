extends CanvasLayer
## Modul: Oberfläche (scripts/ui).
## Kistenwahl (Abschnitt 11): Überschrift im Showton und 3 Karten nebeneinander in
## Seltenheits-Farbe mit Name, Stufenzeile und Wirkungstext der neuen Stufe.
## Wahl per Taste 1/2/3 (Aktionen weapon_1 bis weapon_3) oder Mausklick auf eine Karte.
##
## Öffnet sich bei Events.chest_opened(rarity, offers). Das Spiel ist dann pausiert
## (Game.state == CHOOSING), deshalb process_mode ALWAYS.
##
## Zwei Wege zur Wahl:
## - choose(index): sofort und ohne Sperre (für Tests und andere Module), schließt und ruft
##   Game.choose_offer(index).
## - request_choice(index): der Weg der Eingabe (Taste, Klick). Kurz nach dem Öffnen ist die
##   Eingabe gesperrt (INPUT_LOCK_SECONDS), damit gehaltenes Feuern oder ein Tastendruck aus dem
##   Gefecht nichts versehentlich wählt. Die Wahl greift nach einer kurzen Bestätigung
##   (CONFIRM_DELAY) und erst, wenn die Taste oder Maustaste wieder losgelassen ist (höchstens
##   CONFIRM_MAX_WAIT später): Die Karte blitzt auf, und der auslösende Tastendruck oder Klick
##   löst im weiterlaufenden Spiel weder Waffenwechsel noch Schuss aus.
##
## Schutz vor dem versehentlichen Klick: Im Gefecht ist die Maus gefangen, der Zeiger steht dann
## in der Bildmitte, also genau auf der mittleren Karte. Wer mit der halbautomatischen Pistole
## schnell klickt, würde sie blind wählen. Deshalb setzt die Wahl den Zeiger beim Öffnen unter
## die Karten auf die Hinweiszeile (get_pointer_rest_position), und Klicks zählen erst nach
## CLICK_LOCK_SECONDS (länger als die Sperre der Tasten).

const UiStyle := preload("res://scripts/ui/hud.gd")
const Balance := preload("res://scripts/core/balance.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")

const LAYER: int = 10

# --- Optik- und Bedien-Zahlen (keine Spielregeln) ---
## So lange nach dem Öffnen nimmt die Wahl keine Eingabe an.
const INPUT_LOCK_SECONDS: float = 0.4
## So lange nach dem Öffnen zählt kein Mausklick auf eine Karte. Länger als die Sperre der
## Tasten: Wer im Gefecht schnell klickt, hört erst nach einer Schrecksekunde damit auf.
const CLICK_LOCK_SECONDS: float = 0.8
## Zeit zwischen Eingabe und Wirkung der Wahl (Karte blitzt auf).
const CONFIRM_DELAY: float = 0.12
## So lange wartet die Wahl nach der Bestätigung höchstens auf das Loslassen der Taste.
const CONFIRM_MAX_WAIT: float = 0.5
## Höchster Zeitschritt für die Sperre: Ein Ruckler beim Öffnen frisst sie nicht auf.
const MAX_LOCK_STEP: float = 0.05
const STAGE_SIZE: Vector2 = Vector2(1160.0, 680.0)
const CARD_SIZE: Vector2 = Vector2(340.0, 420.0)
const CARD_GAP: float = 28.0
const CARD_TOP: float = 156.0
const MAX_CARDS: int = 3
## Breite rechts oben in der Karte, die der Aufkleber NEU braucht.
const NEW_STICKER_SPACE: float = 128.0
## Zeilenabstand eines Labels (Standard des Themas): zählt beim Ausmessen des Wirkungstexts mit.
const LABEL_LINE_SPACING: float = 3.0
## Schrift der Zeile mit Art und Rarität: Größe und kleinste Größe, wenn die Zeile lang ist.
const LEVEL_FONT_SIZE: int = 24
const LEVEL_MIN_FONT_SIZE: int = 15
const SUBLINES: Array[String] = [
	"Kandidat, Sie haben die Wahl: Ein Preis darf mit!",
	"Hinter welcher Karte steckt Ihr Glück?",
	"Das Publikum tobt. Greifen Sie zu!",
	"Nur ein Preis darf mit ins Studio!",
]

## Angebote der offenen Kiste (leer, wenn geschlossen), siehe ChestRoller.build_offers.
var offers: Array = []
## Seltenheit der offenen Kiste.
var rarity: int = 0
## Karten der offenen Wahl in der Reihenfolge der Angebote. Kinder je Karte: "Key" (Taste),
## "Tag", "Icon", "Name", "Level", "Pips" (nur Upgrades), "Text".
var cards: Array[Control] = []
## Überschrift, z. B. "GOLD-KISTE! JACKPOT!".
var headline_label: Label
## Zeile unter der Überschrift.
var subline_label: Label
## Bedienhinweis unter den Karten.
var hint_label: Label

var _root: Control
var _sunburst: UiStyle.Sunburst
var _headline: PanelContainer
var _card_row: Control
var _lock_left: float = 0.0
var _click_lock_left: float = 0.0
var _pending_index: int = -1
var _pending_left: float = 0.0
var _pending_action: String = ""


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	Events.chest_opened.connect(_on_chest_opened)
	Events.run_started.connect(close)
	Events.game_over.connect(_on_game_over)


func _process(delta: float) -> void:
	if not is_open():
		return
	if _lock_left > 0.0:
		_lock_left = maxf(_lock_left - minf(delta, MAX_LOCK_STEP), 0.0)
		if _lock_left <= 0.0:
			_on_unlocked()
	if _click_lock_left > 0.0:
		_click_lock_left = maxf(_click_lock_left - minf(delta, MAX_LOCK_STEP), 0.0)
	if _pending_index >= 0:
		_pending_left -= delta
		var still_held: bool = InputMap.has_action(_pending_action) and Input.is_action_pressed(_pending_action)
		if _pending_left <= 0.0 and (not still_held or _pending_left <= -CONFIRM_MAX_WAIT):
			var index: int = _pending_index
			_pending_index = -1
			choose(index)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	for i: int in MAX_CARDS:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			request_choice(i, "weapon_%d" % (i + 1))
			return


## Zeigt die Wahl für diese Angebote und sperrt die Eingabe kurz. Ohne Angebote bleibt die
## Wahl geschlossen.
func show_offers(chest_rarity: int, chest_offers: Array) -> void:
	_clear_cards()
	rarity = clampi(chest_rarity, Balance.RARITY_BRONZE, Balance.RARITY_GOLD)
	offers = chest_offers
	_pending_index = -1
	if offers.is_empty():
		visible = false
		return
	var color: Color = ChestRoller.rarity_color(rarity)
	var headline: String = "%s-KISTE!" % ChestRoller.rarity_name(rarity).to_upper()
	if rarity >= Balance.RARITY_GOLD:
		headline += " JACKPOT!"
	headline_label.text = headline
	headline_label.add_theme_color_override("font_color", color.lightened(0.3))
	subline_label.text = SUBLINES[(Game.kills + rarity) % SUBLINES.size()]
	_sunburst.ray_color = Color(color, 0.13)
	var count: int = mini(offers.size(), MAX_CARDS)
	var total_width: float = float(count) * CARD_SIZE.x + float(count - 1) * CARD_GAP
	var left: float = (STAGE_SIZE.x - total_width) * 0.5
	for i: int in count:
		var offer: Dictionary = offers[i] if offers[i] is Dictionary else {}
		var card: Control = _make_card(i, offer, color)
		var rest: Vector2 = Vector2(left + float(i) * (CARD_SIZE.x + CARD_GAP), 0.0)
		card.position = rest
		card.set_meta("rest_position", rest)
		_card_row.add_child(card)
		cards.append(card)
	visible = true
	_lock_left = INPUT_LOCK_SECONDS
	_click_lock_left = CLICK_LOCK_SECONDS
	_park_pointer()
	hint_label.modulate.a = 0.25
	_animate_entrance()


## Ist die Kistenwahl gerade offen?
func is_open() -> bool:
	return visible


## Nimmt die Wahl gerade keine Eingabe an (Sperre nach dem Öffnen oder Bestätigung läuft)?
func is_input_locked() -> bool:
	return _lock_left > 0.0 or _pending_index >= 0


## Zählt ein Mausklick auf eine Karte gerade nicht (längere Sperre nach dem Öffnen oder
## Bestätigung läuft)?
func is_click_locked() -> bool:
	return _click_lock_left > 0.0 or is_input_locked()


## Stelle (Koordinaten des Fensterinhalts), auf die der Mauszeiger beim Öffnen gesetzt wird:
## die Mitte der Hinweiszeile unter den Karten. Dort liegt keine Karte, auch keine vergrößerte.
func get_pointer_rest_position() -> Vector2:
	return hint_label.get_global_rect().get_center()


## Eingabe-Weg der Wahl (Taste oder Klick): beachtet die Sperre und wählt nach der kurzen
## Bestätigung. held_action: Aktion der auslösenden Taste; solange sie gedrückt ist, wartet die
## Wahl noch kurz. Gibt true zurück, wenn die Wahl angenommen wurde.
func request_choice(index: int, held_action: String = "") -> bool:
	if not is_open() or is_input_locked():
		return false
	if index < 0 or index >= offers.size():
		return false
	_pending_index = index
	_pending_action = held_action
	_pending_left = CONFIRM_DELAY
	_animate_confirm(index)
	return true


## Wählt die Karte mit diesem Index (0 bis 2): schließt die Wahl und ruft Game.choose_offer.
## Ein ungültiger Index oder eine geschlossene Wahl ändert nichts.
func choose(index: int) -> void:
	if not is_open() or index < 0 or index >= offers.size():
		return
	close()
	Game.choose_offer(index)


## Schließt die Wahl ohne Auswahl (nur Anzeige, der Spielzustand bleibt unberührt).
func close() -> void:
	visible = false
	offers = []
	_pending_index = -1
	_lock_left = 0.0
	_click_lock_left = 0.0
	_clear_cards()


# --- Aufbau ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim: ColorRect = UiStyle.make_dim(Color(UiStyle.COL_INK, 0.85))
	dim.name = "Dim"
	_root.add_child(dim)
	_sunburst = UiStyle.Sunburst.new()
	_sunburst.name = "Sunburst"
	_sunburst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_sunburst)
	# Bühne fester Größe in der Bildmitte: passt bei 1280x720 und bleibt bei größeren Fenstern mittig.
	var stage: Control = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(stage, Vector2(0.5, 0.5), -STAGE_SIZE * 0.5, STAGE_SIZE)
	_root.add_child(stage)
	_headline = UiStyle.make_headline("", 50)
	_headline.name = "Headline"
	_headline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_headline.pivot_offset_ratio = Vector2(0.5, 0.5)
	_headline.rotation_degrees = -2.0
	UiStyle.anchor_box(_headline, Vector2(0.5, 0.0), Vector2(0.0, 14.0), Vector2.ZERO)
	stage.add_child(_headline)
	headline_label = _headline.get_node("Label") as Label
	subline_label = UiStyle.make_label("", 22, UiStyle.COL_WHITE, true)
	subline_label.name = "Subline"
	subline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(subline_label, Vector2.ZERO, Vector2(0.0, 110.0), Vector2(STAGE_SIZE.x, 32.0))
	stage.add_child(subline_label)
	_card_row = Control.new()
	_card_row.name = "Cards"
	_card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(_card_row, Vector2.ZERO, Vector2(0.0, CARD_TOP), Vector2(STAGE_SIZE.x, CARD_SIZE.y))
	stage.add_child(_card_row)
	hint_label = UiStyle.make_label("Taste 1, 2 oder 3 drücken – oder eine Karte anklicken", 20, UiStyle.COL_CYAN, true)
	hint_label.name = "Hint"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(hint_label, Vector2.ZERO, Vector2(0.0, CARD_TOP + CARD_SIZE.y + 20.0), Vector2(STAGE_SIZE.x, 30.0))
	stage.add_child(hint_label)


func _clear_cards() -> void:
	for card: Control in cards:
		if is_instance_valid(card):
			if card.get_parent() != null:
				card.get_parent().remove_child(card)
			card.queue_free()
	cards.clear()


func _make_card(index: int, offer: Dictionary, color: Color) -> Control:
	var kind: String = String(offer.get("kind", ""))
	# Gegenstand für den Rucksack: Upgrade-Gegenstände sehen aus wie die alten Upgrade-Karten
	# (von 0 auf die Stufe des Gegenstands), Verstärker und Rucksack-Teile zeigen ihre Form.
	var is_item: bool = kind == ChestRoller.KIND_ITEM
	var item_id: String = String(offer.get("id", "")) if is_item else ""
	var is_plain_item: bool = is_item and not ItemDefs.is_upgrade(item_id)
	var is_upgrade: bool = kind == ChestRoller.KIND_UPGRADE or (is_item and not is_plain_item)
	var from_level: int = int(offer.get("from_level", 0))
	var to_level: int = int(offer.get("to_level", 0))
	var owned_level: int = int(offer.get("owned_level", 0))
	if is_item:
		from_level = 0
		to_level = int(offer.get("level", 1))
	var card: Control = Control.new()
	card.name = "Card%d" % index
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.pivot_offset_ratio = Vector2(0.5, 0.5)
	card.gui_input.connect(_on_card_gui_input.bind(index))
	card.mouse_entered.connect(_on_card_hover.bind(index, true))
	card.mouse_exited.connect(_on_card_hover.bind(index, false))

	var back_box: StyleBoxFlat = UiStyle.make_box(UiStyle.COL_PANEL_SOLID.lerp(color, 0.16), color, 6, 0.0, 16)
	back_box.shadow_offset = Vector2(8.0, 10.0)
	var back: Panel = Panel.new()
	back.name = "Back"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", back_box)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(back)
	card.set_meta("box", back_box)
	card.set_meta("color", color)

	var band_box: StyleBoxFlat = UiStyle.make_box(color, color, 0, 0.0, 0)
	band_box.corner_radius_top_left = 12
	band_box.corner_radius_top_right = 12
	band_box.shadow_size = 0
	var band: Panel = Panel.new()
	band.name = "Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_theme_stylebox_override("panel", band_box)
	UiStyle.anchor_box(band, Vector2.ZERO, Vector2(5.0, 5.0), Vector2(CARD_SIZE.x - 10.0, 52.0))
	card.add_child(band)

	var key_plate: Panel = UiStyle.make_plate(UiStyle.COL_INK, UiStyle.COL_WHITE, 3, 0.0, 7)
	key_plate.name = "KeyPlate"
	UiStyle.anchor_box(key_plate, Vector2.ZERO, Vector2(13.0, 10.0), Vector2(42.0, 42.0))
	card.add_child(key_plate)
	var key_label: Label = UiStyle.make_label(str(index + 1), 26, UiStyle.COL_WHITE)
	key_label.name = "Key"
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(key_label, Vector2.ZERO, Vector2(13.0, 9.0), Vector2(42.0, 42.0))
	card.add_child(key_label)

	var tag_text: String = "TROSTPREIS"
	if is_plain_item:
		tag_text = "RUCKSACK" if ItemDefs.is_bag(item_id) else ItemDefs.rarity_name(to_level).to_upper()
	elif is_item:
		tag_text = ItemDefs.rarity_name(to_level).to_upper()
	elif is_upgrade:
		var gain: int = maxi(to_level - from_level, 0)
		tag_text = "+1 STUFE" if gain == 1 else "+%d STUFEN" % gain
	var tag: Label = UiStyle.make_label(tag_text, 22, UiStyle.COL_WHITE, true)
	tag.name = "Tag"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(tag, Vector2.ZERO, Vector2(64.0, 5.0), Vector2(CARD_SIZE.x - 84.0, 52.0))
	card.add_child(tag)

	if is_item and not UiStyle.has_icon(item_id):
		# Waffen, Verstärker, Rucksack-Teile und neuere Gegenstände: Die Form ist das Bild der Karte.
		# Kameras haben ein gezeichnetes Bild wie die ersten Upgrades.
		var big_shape: UiStyle.ItemShape = UiStyle.ItemShape.new()
		big_shape.name = "Icon"
		big_shape.item_id = item_id
		big_shape.max_cell = 34.0
		var shape_rect: Rect2 = Rect2((CARD_SIZE.x - 110.0) * 0.5, 66.0, 110.0, 80.0)
		if ItemDefs.has_rarity(item_id) and owned_level <= 0 and ItemDefs.size(item_id).x >= 3:
			# Lange Formen (vor allem Waffen) rücken nach links: Rechts sitzt der Aufkleber NEU.
			shape_rect = Rect2(22.0, 66.0, CARD_SIZE.x - 22.0 - NEW_STICKER_SPACE, 80.0)
			big_shape.max_cell = 30.0
		UiStyle.anchor_box(big_shape, Vector2.ZERO, shape_rect.position, shape_rect.size)
		card.add_child(big_shape)
	else:
		var icon: UiStyle.UpgradeIcon = UiStyle.UpgradeIcon.new()
		icon.name = "Icon"
		icon.icon_id = String(offer.get("id", "")) if (is_upgrade or is_item) else kind
		UiStyle.anchor_box(icon, Vector2.ZERO, Vector2((CARD_SIZE.x - 76.0) * 0.5, 68.0), Vector2(76.0, 76.0))
		card.add_child(icon)
		if is_item:
			# Wie viel Platz der Gegenstand im Rucksack braucht (links, rechts sitzt der Aufkleber NEU).
			var small_shape: UiStyle.ItemShape = UiStyle.ItemShape.new()
			small_shape.name = "Shape"
			small_shape.item_id = item_id
			small_shape.max_cell = 16.0
			UiStyle.anchor_box(small_shape, Vector2.ZERO, Vector2(22.0, 78.0), Vector2(56.0, 56.0))
			card.add_child(small_shape)

	var title: String = ChestRoller.offer_title(offer)
	if not is_upgrade and title.contains(": "):
		# "Trostpreis: Punkte" -> "Punkte" (der Trostpreis steht schon im Kopf der Karte).
		title = title.get_slice(": ", 1)
	var name_width: float = CARD_SIZE.x - 32.0
	var name_label: Label = UiStyle.make_label(title, _name_font_size(title, name_width), UiStyle.COL_YELLOW, true)
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStyle.anchor_box(name_label, Vector2.ZERO, Vector2(16.0, 148.0), Vector2(name_width, 68.0))
	card.add_child(name_label)

	var level_text: String = ""
	var level_color: Color = UiStyle.COL_CYAN
	var has_rarity: bool = is_item and ItemDefs.has_rarity(item_id)
	if is_item:
		level_text = ChestRoller.offer_level_text(offer)
		level_color = UiStyle.COL_YELLOW
		if has_rarity:
			# Die Zeile steht in der Farbe der Rarität. Verstärker nennen dazu ihre Art.
			level_color = ItemDefs.rarity_color(to_level)
			if owned_level <= 0:
				level_text = "NEU · %s" % ItemDefs.rarity_name(to_level)
			var kind_text: String = ""
			if is_plain_item:
				kind_text = "Verstärker · "
				if ItemDefs.is_weapon(item_id):
					kind_text = "Waffe · "
				elif ItemDefs.is_camera(item_id):
					kind_text = "Kamera · "
			level_text = kind_text + level_text
			if owned_level > 0 and not _fits_level_line(level_text, name_width - 8.0):
				# "Kamera · Ungewöhnlich · du hast Ungewöhnlich" passt in keiner lesbaren Größe in
				# die Karte: Die neue Rarität steht schon oben im Kopf und in den Kästchen.
				level_text = "%sdu hast %s" % [kind_text, ItemDefs.rarity_name(owned_level)]
	elif is_upgrade:
		if from_level <= 0:
			level_text = "NEU · Stufe %d" % to_level
			level_color = UiStyle.COL_GREEN
		else:
			level_text = ChestRoller.offer_level_text(offer)
	elif kind == ChestRoller.KIND_POINTS:
		level_text = "+%s PUNKTE" % UiStyle.format_int(int(offer.get("amount", 0)))
		level_color = UiStyle.COL_YELLOW
	elif kind == ChestRoller.KIND_HEAL:
		level_text = "+%d LEBEN" % int(offer.get("amount", 0))
		level_color = UiStyle.COL_GREEN
	# "Kamera · NEU · Ungewöhnlich" ist in voller Größe breiter als die Karte: Die Schrift passt sich an.
	var level_label: Label = UiStyle.make_label(level_text, UiStyle.fit_font_size(level_text, LEVEL_FONT_SIZE, name_width - 8.0, true, LEVEL_MIN_FONT_SIZE), level_color, true)
	level_label.name = "Level"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(level_label, Vector2.ZERO, Vector2(16.0, 216.0), Vector2(name_width, 34.0))
	card.add_child(level_label)

	var text_top: float = 262.0
	if is_upgrade or has_rarity:
		var pips: UiStyle.Pips = UiStyle.Pips.new()
		pips.name = "Pips"
		pips.level = to_level
		pips.gained_from = from_level
		pips.fill_color = UiStyle.COL_CYAN
		pips.new_color = UiStyle.COL_YELLOW
		if has_rarity:
			# Gegenstand: so viele Kästchen wie die Rarität, in ihrer Farbe.
			pips.gained_from = -1
			pips.fill_color = ItemDefs.rarity_color(to_level)
		UiStyle.anchor_box(pips, Vector2.ZERO, Vector2((CARD_SIZE.x - 180.0) * 0.5, 254.0), Vector2(180.0, 14.0))
		card.add_child(pips)
		text_top = 280.0
		if (owned_level <= 0) if is_item else (from_level <= 0):
			card.add_child(_make_new_sticker())

	var description: String = _keep_units_together(ChestRoller.offer_description(offer))
	var text_size: Vector2 = Vector2(CARD_SIZE.x - 40.0, CARD_SIZE.y - text_top - 14.0)
	var text_label: Label = UiStyle.make_label(description, _text_font_size(description, text_size), UiStyle.COL_WHITE)
	text_label.name = "Text"
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP if (is_upgrade or is_item) else VERTICAL_ALIGNMENT_CENTER
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_constant_override("outline_size", 3)
	text_label.add_theme_constant_override("shadow_outline_size", 3)
	UiStyle.anchor_box(text_label, Vector2.ZERO, Vector2(20.0, text_top), text_size)
	card.add_child(text_label)
	return card


## Ersetzt das Leerzeichen zwischen Zahl und Einheit ("15 m", "3 s", "15 %") durch ein
## geschütztes, damit der Zeilenumbruch die beiden nie trennt.
func _keep_units_together(text: String) -> String:
	return UiStyle.keep_units_together(text)


## Passt die Zeile mit Art und Rarität in ihrer kleinsten Schrift in diese Breite?
func _fits_level_line(text: String, width: float) -> bool:
	return UiStyle.show_font(true).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LEVEL_MIN_FONT_SIZE).x <= width


## Schräger Aufkleber "NEU!" neben dem Symbol einer Karte mit einem neuen Upgrade.
func _make_new_sticker() -> Control:
	var sticker: PanelContainer = UiStyle.make_headline("NEU!", 20, UiStyle.COL_PINK, UiStyle.COL_WHITE, UiStyle.COL_WHITE)
	sticker.name = "NewSticker"
	sticker.pivot_offset_ratio = Vector2(0.5, 0.5)
	sticker.rotation_degrees = 12.0
	UiStyle.anchor_box(sticker, Vector2.ZERO, Vector2(CARD_SIZE.x - 122.0, 76.0), Vector2.ZERO)
	return sticker


## Schriftgröße des Namens: Das längste Wort muss in die Kartenbreite passen.
func _name_font_size(title: String, width: float) -> int:
	var longest: String = ""
	for word: String in title.split(" ", false):
		if word.length() > longest.length():
			longest = word
	return UiStyle.fit_font_size(longest, 26, width - 8.0, true, 16)


## Schriftgröße des Wirkungstextes: Der umbrochene Text muss in das Feld passen.
func _text_font_size(text: String, box: Vector2) -> int:
	var font: Font = UiStyle.show_font(false)
	var font_size: int = 17
	while font_size > 11:
		var needed: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, box.x, font_size)
		# Das Label setzt zwischen die Zeilen noch seinen Zeilenabstand.
		var lines: float = maxf(roundf(needed.y / maxf(font.get_height(font_size), 1.0)), 1.0)
		if needed.y + (lines - 1.0) * LABEL_LINE_SPACING <= box.y - 4.0:
			break
		font_size -= 1
	return font_size


# --- Animation ------------------------------------------------------------------------

func _animate_entrance() -> void:
	if not is_inside_tree():
		return
	UiStyle.pop(_headline, 0.3, 0.3)
	for i: int in cards.size():
		var card: Control = cards[i]
		var rest: Vector2 = card.get_meta("rest_position") as Vector2
		card.position = rest + Vector2(0.0, 520.0)
		card.rotation_degrees = -14.0 if i % 2 == 0 else 14.0
		card.modulate.a = 0.0
		var delay: float = 0.07 * float(i)
		var tween: Tween = card.create_tween()
		tween.set_parallel(true)
		tween.tween_property(card, "position", rest, 0.3).set_delay(delay) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "rotation_degrees", 0.0, 0.3).set_delay(delay) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "modulate:a", 1.0, 0.12).set_delay(delay)


func _animate_confirm(index: int) -> void:
	for i: int in cards.size():
		var card: Control = cards[i]
		if not is_instance_valid(card):
			continue
		if i == index:
			card.modulate = Color(1.6, 1.6, 1.6)
			card.z_index = 2
			_set_card_border(card, UiStyle.COL_WHITE)
			UiStyle.pop(card, 1.16, CONFIRM_DELAY)
		else:
			card.modulate = Color(0.45, 0.45, 0.5, 0.7)


## Setzt den Mauszeiger von der Bildmitte (dort steht er nach dem gefangenen Modus, also auf der
## mittleren Karte) auf die Hinweiszeile. Nur mit sichtbarem Zeiger und echtem Bildschirm.
func _park_pointer() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	get_viewport().warp_mouse(get_pointer_rest_position())


func _on_unlocked() -> void:
	hint_label.modulate.a = 1.0
	UiStyle.pop(hint_label, 1.25, 0.2)


func _set_card_border(card: Control, color: Color) -> void:
	var box: StyleBoxFlat = card.get_meta("box") as StyleBoxFlat
	if box != null:
		box.border_color = color


# --- Eingabe --------------------------------------------------------------------------

func _on_card_gui_input(event: InputEvent, index: int) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if index < cards.size() and is_instance_valid(cards[index]):
		cards[index].accept_event()
	if is_click_locked():
		return
	request_choice(index, "fire")


func _on_card_hover(index: int, hovered: bool) -> void:
	if index < 0 or index >= cards.size() or _pending_index >= 0:
		return
	var card: Control = cards[index]
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	card.z_index = 1 if hovered else 0
	_set_card_border(card, UiStyle.COL_WHITE if hovered else card.get_meta("color") as Color)
	UiStyle.kill_tween(card, "pop_tween")
	var tween: Tween = card.create_tween()
	tween.tween_property(card, "scale", Vector2.ONE * (1.06 if hovered else 1.0), 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	card.set_meta("pop_tween", tween)


func _on_chest_opened(chest_rarity: int, chest_offers: Array) -> void:
	show_offers(chest_rarity, chest_offers)


func _on_game_over(_stats: Dictionary) -> void:
	close()
