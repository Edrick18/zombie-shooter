extends CanvasLayer
## Modul: Oberfläche (scripts/ui).
## Kandidatenwahl (Abschnitt 16): Vor dem Lauf tritt einer der Kandidaten aus CharacterDefs an.
## Deckender Hintergrund (die 3D-Szene ist nicht zu sehen), Überschrift im Showton und je
## Kandidat eine Karte nebeneinander: Taste, Name, Spruch, Leben, Tempo, Waffen, Startpunkte,
## Start-Gegenstände und die Form des Start-Rucksacks.
##
## Bedienung: Klick auf eine Karte oder Taste 1/2/3 wählt sofort. Pfeiltasten links/rechts
## wechseln die markierte Karte (im Kreis), Enter oder Leertaste bestätigt sie. Die Maus
## markiert die Karte, über die sie bewegt wird. Kurz nach dem Öffnen ist die Eingabe gesperrt
## (INPUT_LOCK_SECONDS), damit ein Klick oder Tastendruck von vorher nichts versehentlich wählt.
##
## Die Wahl setzt Game.character_id, schließt den Bildschirm und meldet character_chosen(id).
## Den Lauf startet der Bildschirm nicht selbst: main.gd hört auf das Signal.
## process_mode ALWAYS: Der Bildschirm lässt sich auch bei pausiertem Baum bedienen.
##
## Oben rechts stehen der Kontostand (Game.progress.bank, folgt Events.bank_changed) und der
## Knopf „Programm“ (auch Taste P): open_program() meldet program_requested und öffnet den
## Bildschirm „Programm“ (unlock_screen, von main.gd gesetzt) über der Wahl. Solange er offen
## ist, nimmt die Kandidatenwahl keine Eingabe an. Danach ist sie wieder da, wie sie war.

signal character_chosen(id: String)
## Der Spieler will ins Programm (Knopf oder Taste P).
signal program_requested

const UiStyle := preload("res://scripts/ui/hud.gd")
const UnlockScreen := preload("res://scripts/ui/unlock_screen.gd")
const Balance := preload("res://scripts/core/balance.gd")
const CharacterDefs := preload("res://scripts/core/character_defs.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")

## Über allen anderen Bildschirmen (HUD 1, Kistenwahl 10, Rucksack 15, Pause 20, Game Over 30).
const LAYER: int = 40

# --- Optik- und Bedien-Zahlen (keine Spielregeln) ---
## So lange nach dem Öffnen nimmt die Wahl keine Eingabe an (echte Zeit über _process).
const INPUT_LOCK_SECONDS: float = 0.3
const STAGE_SIZE: Vector2 = Vector2(1180.0, 690.0)
const CARD_SIZE: Vector2 = Vector2(360.0, 468.0)
const CARD_GAP: float = 30.0
const CARD_TOP: float = 148.0
## Vergrößerung der markierten Karte.
const SELECTED_SCALE: float = 1.05
## Abdunklung der nicht markierten Karten.
const DIM_COLOR: Color = Color(0.72, 0.72, 0.8)
const FACTS_TOP: float = 158.0
const FACTS_HEIGHT: float = 154.0
const FACT_LINE: float = 25.0
const FACT_CAPTION_X: float = 24.0
const FACT_VALUE_X: float = 148.0
## Kantenlänge eines Felds in der Zeichnung des Start-Rucksacks.
const BAG_CELL: float = 19.0
const HEADLINE_TEXT: String = "WER TRITT HEUTE AN?"
const SUBLINE_TEXT: String = "Drei Kandidaten, ein Studio voller Zombies. Sie haben die Wahl!"
const HINT_TEXT: String = "Taste 1, 2 oder 3 oder ein Klick wählt sofort  ·  Pfeiltasten wechseln  ·  Enter bestätigt  ·  P: Programm"
const PICK_TEXT: String = "ENTER: ANTRETEN!"
## Kontostand und Knopf "Programm" oben rechts auf der Bühne.
const BANK_RECT: Rect2 = Rect2(950.0, 0.0, 230.0, 40.0)
const PROGRAM_BUTTON_RECT: Rect2 = Rect2(964.0, 44.0, 212.0, 50.0)

## Karten in der Reihenfolge von CharacterDefs.ORDER. Meta "id" = Kandidat. Kinder je Karte:
## "Key" (Taste), "Tag", "Name", "Tagline", "Facts" (Zeilen mit Leben, Tempo, Waffen ...),
## "BagCaption", "Bag" (Zeichnung des Start-Rucksacks), "Pick" (Aufkleber der markierten Karte).
var cards: Array[Control] = []
## Überschrift des Bildschirms.
var headline_label: Label
## Bedienhinweis unter den Karten.
var hint_label: Label
## Kontostand oben rechts: "KONTO  12.340".
var bank_label: Label
## Knopf "PROGRAMM" (open_program).
var program_button: Button
## Bildschirm „Programm“, den der Knopf öffnet. Setzt main.gd, ohne ihn meldet der Knopf nur
## program_requested.
var unlock_screen: UnlockScreen = null

var _built: bool = false
var _selected: String = CharacterDefs.DEFAULT
var _lock_left: float = 0.0
var _headline: PanelContainer
var _sunburst: UiStyle.Sunburst
var _card_row: Control


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_ensure_built()
	Events.bank_changed.connect(_on_bank_changed)


func _process(delta: float) -> void:
	if not is_open() or _lock_left <= 0.0:
		return
	_lock_left = maxf(_lock_left - delta, 0.0)
	if _lock_left <= 0.0:
		_on_unlocked()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or is_program_open():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# Tasten nach ihrer Lage auf der Tastatur (unabhängig von der Belegung).
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	var number: int = _number_index(code)
	var step: int = 0
	if code == KEY_LEFT:
		step = -1
	elif code == KEY_RIGHT:
		step = 1
	var confirm: bool = code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE
	var program: bool = code == KEY_P
	if number < 0 and step == 0 and not confirm and not program:
		return
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	if is_input_locked():
		return
	if program:
		open_program()
	elif number >= 0:
		choose(CharacterDefs.ORDER[number])
	elif step != 0:
		_step_selection(step)
	else:
		choose(_selected)


## Zeigt die Kandidatenwahl und sperrt die Eingabe kurz. Markiert ist der Kandidat aus
## Game.character_id, wenn es ihn gibt, sonst CharacterDefs.DEFAULT.
func open() -> void:
	_ensure_built()
	_selected = _valid_id(Game.character_id)
	_lock_left = INPUT_LOCK_SECONDS
	visible = true
	hint_label.modulate.a = 0.3
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Kein versteckter Knopf eines anderen Bildschirms soll Enter oder Leertaste abfangen.
	if is_inside_tree():
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()
	_apply_selection(false)
	_update_bank()
	_animate_entrance()


## Öffnet den Bildschirm „Programm“ über der Kandidatenwahl (ohne Rücksicht auf die
## Eingabesperre) und meldet program_requested. Die Wahl bleibt darunter offen. false bei
## geschlossener Wahl oder wenn das Programm schon offen ist.
func open_program() -> bool:
	if not is_open() or is_program_open():
		return false
	program_requested.emit()
	if is_instance_valid(unlock_screen):
		unlock_screen.open()
	return true


## Liegt gerade der Bildschirm „Programm“ über der Kandidatenwahl?
func is_program_open() -> bool:
	return is_instance_valid(unlock_screen) and unlock_screen.is_open()


## Schließt die Kandidatenwahl ohne Wahl (nur Anzeige, Game.character_id bleibt unberührt).
func close() -> void:
	visible = false
	_lock_left = 0.0


## Ist die Kandidatenwahl gerade offen?
func is_open() -> bool:
	return visible


## Nimmt die Wahl gerade keine Eingabe an (Sperre nach dem Öffnen)?
func is_input_locked() -> bool:
	return _lock_left > 0.0


## Gerade markierter Kandidat.
func selected_id() -> String:
	return _selected


## Markiert einen Kandidaten, ohne ihn zu wählen. Eine unbekannte ID ändert nichts.
func select(id: String) -> void:
	if not CharacterDefs.ORDER.has(id) or id == _selected:
		return
	_selected = id
	_apply_selection(true)


## Wählt den Kandidaten (ohne Rücksicht auf die Eingabesperre): setzt Game.character_id, schließt
## den Bildschirm und meldet character_chosen. Gibt false zurück und ändert nichts bei einer
## unbekannten ID oder geschlossenem Bildschirm.
func choose(id: String) -> bool:
	if not is_open() or is_program_open() or not CharacterDefs.ORDER.has(id):
		return false
	_selected = id
	Game.character_id = id
	close()
	character_chosen.emit(id)
	return true


# --- Aufbau ---------------------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_build()
	_apply_selection(false)


func _build() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# Deckend: Hinter der Wahl ist vom Studio nichts zu sehen.
	var background: ColorRect = UiStyle.make_dim(Color(UiStyle.COL_INK, 1.0))
	background.name = "Background"
	root.add_child(background)
	_sunburst = UiStyle.Sunburst.new()
	_sunburst.name = "Sunburst"
	_sunburst.speed = 0.08
	_sunburst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_sunburst)
	# Bühne fester Größe in der Bildmitte: passt bei 1280x720 und bleibt bei größeren Fenstern mittig.
	var stage: Control = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(stage, Vector2(0.5, 0.5), -STAGE_SIZE * 0.5, STAGE_SIZE)
	root.add_child(stage)
	_headline = UiStyle.make_headline(HEADLINE_TEXT, 50)
	_headline.name = "Headline"
	_headline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_headline.pivot_offset_ratio = Vector2(0.5, 0.5)
	_headline.rotation_degrees = -2.0
	UiStyle.anchor_box(_headline, Vector2(0.5, 0.0), Vector2(0.0, 10.0), Vector2.ZERO)
	stage.add_child(_headline)
	headline_label = _headline.get_node("Label") as Label
	var subline: Label = UiStyle.make_label(SUBLINE_TEXT, 22, UiStyle.COL_WHITE, true)
	subline.name = "Subline"
	subline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(subline, Vector2.ZERO, Vector2(0.0, 104.0), Vector2(STAGE_SIZE.x, 32.0))
	stage.add_child(subline)
	_card_row = Control.new()
	_card_row.name = "Cards"
	_card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(_card_row, Vector2.ZERO, Vector2(0.0, CARD_TOP), Vector2(STAGE_SIZE.x, CARD_SIZE.y))
	stage.add_child(_card_row)
	var count: int = CharacterDefs.ORDER.size()
	var total_width: float = float(count) * CARD_SIZE.x + float(count - 1) * CARD_GAP
	var left: float = (STAGE_SIZE.x - total_width) * 0.5
	for i: int in count:
		var card: Control = _make_card(i, CharacterDefs.ORDER[i])
		var rest: Vector2 = Vector2(left + float(i) * (CARD_SIZE.x + CARD_GAP), 0.0)
		card.position = rest
		card.set_meta("rest_position", rest)
		_card_row.add_child(card)
		cards.append(card)
	hint_label = UiStyle.make_label(HINT_TEXT, 18, UiStyle.COL_CYAN, true)
	hint_label.name = "Hint"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(hint_label, Vector2.ZERO, Vector2(0.0, CARD_TOP + CARD_SIZE.y + 34.0), Vector2(STAGE_SIZE.x, 30.0))
	hint_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(HINT_TEXT, 18, STAGE_SIZE.x - 20.0, true, 13))
	stage.add_child(hint_label)
	# Konto und Programm oben rechts neben der Überschrift.
	bank_label = UiStyle.make_label("", 20, UiStyle.COL_YELLOW, true)
	bank_label.name = "Bank"
	bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bank_label.pivot_offset_ratio = Vector2(1.0, 0.5)
	UiStyle.anchor_box(bank_label, Vector2.ZERO, BANK_RECT.position, BANK_RECT.size)
	stage.add_child(bank_label)
	program_button = UiStyle.make_button("PROGRAMM", UiStyle.COL_YELLOW, 24)
	program_button.name = "Program"
	# Kein Tastatur-Fokus: Enter und Leertaste gehören der markierten Karte.
	program_button.focus_mode = Control.FOCUS_NONE
	program_button.custom_minimum_size = PROGRAM_BUTTON_RECT.size
	program_button.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(program_button, Vector2.ZERO, PROGRAM_BUTTON_RECT.position, PROGRAM_BUTTON_RECT.size)
	program_button.pressed.connect(_on_program_pressed)
	stage.add_child(program_button)
	_update_bank()


func _make_card(index: int, id: String) -> Control:
	var color: Color = CharacterDefs.color(id)
	var card: Control = Control.new()
	card.name = "Card_%s" % id
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.pivot_offset_ratio = Vector2(0.5, 0.5)
	card.set_meta("id", id)
	card.set_meta("color", color)
	card.gui_input.connect(_on_card_gui_input.bind(index))

	var back_box: StyleBoxFlat = UiStyle.make_box(UiStyle.COL_PANEL_SOLID.lerp(color, 0.14), color, 6, 0.0, 16)
	back_box.shadow_offset = Vector2(8.0, 10.0)
	var back: Panel = Panel.new()
	back.name = "Back"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", back_box)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(back)
	card.set_meta("box", back_box)

	# Kopf in der Farbe des Kandidaten mit Taste und Schriftzug.
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
	var tag: Label = UiStyle.make_label("KANDIDAT", 22, UiStyle.COL_WHITE, true)
	tag.name = "Tag"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(tag, Vector2.ZERO, Vector2(64.0, 5.0), Vector2(CARD_SIZE.x - 84.0, 52.0))
	card.add_child(tag)

	var inner_width: float = CARD_SIZE.x - 32.0
	var display_name: String = CharacterDefs.display_name(id)
	var name_label: Label = UiStyle.make_label(display_name, UiStyle.fit_font_size(display_name, 30, inner_width - 8.0, true, 18),
			UiStyle.COL_YELLOW, true)
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(name_label, Vector2.ZERO, Vector2(16.0, 62.0), Vector2(inner_width, 44.0))
	card.add_child(name_label)

	var tagline: Label = UiStyle.make_label("„%s“" % CharacterDefs.tagline(id), 16, color.lightened(0.55), true)
	tagline.name = "Tagline"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_thin_outline(tagline)
	UiStyle.anchor_box(tagline, Vector2.ZERO, Vector2(16.0, 103.0), Vector2(inner_width, 44.0))
	card.add_child(tagline)

	card.add_child(_make_rule(color, FACTS_TOP - 8.0))
	card.add_child(_make_facts(id))

	# Start-Rucksack: Beschriftung und Zeichnung unten in der Karte.
	var bag_cells: Array[Vector2i] = CharacterDefs.bag_cells(id)
	var bag_size: Vector2 = Vector2(float(Balance.BACKPACK_COLS), float(Balance.BACKPACK_ROWS)) * BAG_CELL
	var bag_top: float = CARD_SIZE.y - bag_size.y - 20.0
	card.add_child(_make_rule(color, bag_top - 32.0))
	var bag_caption: Label = UiStyle.make_label("START-RUCKSACK  ·  %d FELDER" % bag_cells.size(), 13, UiStyle.COL_CYAN)
	bag_caption.name = "BagCaption"
	bag_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_thin_outline(bag_caption)
	UiStyle.anchor_box(bag_caption, Vector2.ZERO, Vector2(16.0, bag_top - 26.0), Vector2(inner_width, 22.0))
	card.add_child(bag_caption)
	var bag: BagShape = BagShape.new()
	bag.name = "Bag"
	bag.cols = Balance.BACKPACK_COLS
	bag.rows = Balance.BACKPACK_ROWS
	bag.cells = bag_cells
	bag.fill = color
	UiStyle.anchor_box(bag, Vector2.ZERO, Vector2((CARD_SIZE.x - bag_size.x) * 0.5, bag_top), bag_size)
	card.add_child(bag)

	# Aufkleber der markierten Karte, ragt über den unteren Rand.
	var pick: PanelContainer = UiStyle.make_headline(PICK_TEXT, 18, UiStyle.COL_PINK, UiStyle.COL_WHITE, UiStyle.COL_WHITE)
	pick.name = "Pick"
	pick.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pick.pivot_offset_ratio = Vector2(0.5, 0.5)
	pick.rotation_degrees = -3.0
	pick.visible = false
	UiStyle.anchor_box(pick, Vector2(0.5, 1.0), Vector2(0.0, -17.0), Vector2.ZERO)
	card.add_child(pick)
	return card


## Zeilen mit den Eigenheiten des Kandidaten: links die Bezeichnung, rechts je Wert eine Zeile.
func _make_facts(id: String) -> Control:
	var facts: Control = Control.new()
	facts.name = "Facts"
	facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(facts, Vector2.ZERO, Vector2(0.0, FACTS_TOP), Vector2(CARD_SIZE.x, FACTS_HEIGHT))
	var rows: Array[Dictionary] = _fact_rows(id)
	var line_count: int = 0
	for row: Dictionary in rows:
		line_count += (row["values"] as Array).size()
	# Mehr Zeilen als Platz: Die Zeilen rücken zusammen.
	var line_height: float = minf(FACT_LINE, FACTS_HEIGHT / float(maxi(line_count, 1)))
	var value_width: float = CARD_SIZE.x - FACT_VALUE_X - 18.0
	var y: float = 0.0
	for row: Dictionary in rows:
		var caption: Label = UiStyle.make_label(str(row["caption"]), 13, UiStyle.COL_CYAN)
		caption.name = "Caption_%s" % str(row["key"])
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_thin_outline(caption)
		UiStyle.anchor_box(caption, Vector2.ZERO, Vector2(FACT_CAPTION_X, y + 1.0), Vector2(FACT_VALUE_X - FACT_CAPTION_X - 6.0, line_height))
		facts.add_child(caption)
		var values: Array = row["values"]
		for i: int in values.size():
			var text: String = str(values[i])
			var value: Label = UiStyle.make_label(text, UiStyle.fit_font_size(text, 17, value_width - 4.0, false, 11), row["color"] as Color)
			value.name = "Value_%s_%d" % [str(row["key"]), i]
			value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			value.clip_text = true
			_thin_outline(value)
			UiStyle.anchor_box(value, Vector2.ZERO, Vector2(FACT_VALUE_X, y), Vector2(value_width, line_height))
			facts.add_child(value)
			y += line_height
	return facts


## Eigenheiten als Zeilen: { key, caption, values (Array aus Text), color }.
func _fact_rows(id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var hp: float = CharacterDefs.base_max_hp(id)
	rows.append({"key": "hp", "caption": "LEBEN", "values": [str(roundi(hp))],
			"color": _rating_color(hp - Balance.PLAYER_MAX_HP)})
	var speed: float = float(CharacterDefs.extra(id).get("speed", 0.0))
	rows.append({"key": "speed", "caption": "TEMPO", "values": [speed_text(speed)], "color": _rating_color(speed)})
	# Die Waffen liegen im Start-Rucksack. Ohne eigene Waffe bliebe die Dienstpistole.
	var weapon_names: Array = []
	for weapon_id: String in CharacterDefs.weapons(id):
		weapon_names.append(WeaponDefs.display_name(weapon_id))
	if weapon_names.is_empty():
		weapon_names.append(WeaponDefs.display_name(WeaponDefs.START_WEAPON))
	rows.append({"key": "weapons", "caption": "WAFFEN", "values": weapon_names, "color": UiStyle.COL_WHITE})
	var start_points: int = CharacterDefs.start_points(id)
	if start_points > 0:
		rows.append({"key": "points", "caption": "STARTPUNKTE", "values": [UiStyle.format_int(start_points)],
				"color": UiStyle.COL_YELLOW})
	var item_names: Array = []
	for entry: Dictionary in CharacterDefs.start_items(id):
		# Waffen stehen schon in der Zeile darüber.
		if ItemDefs.is_weapon(str(entry["id"])):
			continue
		var item_name: String = ItemDefs.display_name(str(entry["id"]))
		if int(entry["level"]) > 1:
			item_name += " (%s)" % ItemDefs.rarity_name(int(entry["level"]))
		item_names.append(item_name)
	if not item_names.is_empty():
		rows.append({"key": "items", "caption": "GEGENSTÄNDE", "values": item_names, "color": UiStyle.COL_WHITE})
	return rows


## Tempo als Text: "+10 %", "−5 %" oder "normal". fraction ist der Bruchteil (0.1 = 10 Prozent).
static func speed_text(fraction: float) -> String:
	var percent: int = roundi(fraction * 100.0)
	if percent == 0:
		return "normal"
	return "%s%d %%" % ["+" if percent > 0 else "−", absi(percent)]


## Farbe eines Werts: grün über dem Grundwert, orange darunter, sonst weiß.
func _rating_color(difference: float) -> Color:
	if difference > 0.0001:
		return UiStyle.COL_GREEN
	if difference < -0.0001:
		return UiStyle.COL_ORANGE
	return UiStyle.COL_WHITE


## Dünne Trennlinie in der Farbe des Kandidaten.
func _make_rule(color: Color, y: float) -> ColorRect:
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(color, 0.45)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(rule, Vector2.ZERO, Vector2(22.0, y), Vector2(CARD_SIZE.x - 44.0, 2.0))
	return rule


## Kleine Schrift bekommt einen dünneren Rand, sonst läuft sie zu.
func _thin_outline(label: Label) -> void:
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_constant_override("shadow_outline_size", 3)


# --- Markierung und Animation ---------------------------------------------------------

func _valid_id(id: String) -> String:
	return id if CharacterDefs.ORDER.has(id) else CharacterDefs.DEFAULT


func _number_index(code: Key) -> int:
	var index: int = -1
	if code >= KEY_1 and code <= KEY_9:
		index = int(code) - int(KEY_1)
	elif code >= KEY_KP_1 and code <= KEY_KP_9:
		index = int(code) - int(KEY_KP_1)
	return index if index < CharacterDefs.ORDER.size() else -1


## Markierung um step Karten weiter, am Rand geht es auf der anderen Seite weiter.
func _step_selection(step: int) -> void:
	var count: int = CharacterDefs.ORDER.size()
	var index: int = maxi(CharacterDefs.ORDER.find(_selected), 0)
	select(CharacterDefs.ORDER[posmod(index + step, count)])


## Zeigt die Markierung: heller Rand, größer und mit Aufkleber, die anderen Karten dunkler.
func _apply_selection(animated: bool) -> void:
	for card: Control in cards:
		var is_selected: bool = str(card.get_meta("id")) == _selected
		var color: Color = card.get_meta("color") as Color
		var box: StyleBoxFlat = card.get_meta("box") as StyleBoxFlat
		box.border_color = UiStyle.COL_WHITE if is_selected else color
		box.bg_color = UiStyle.COL_PANEL_SOLID.lerp(color, 0.26 if is_selected else 0.14)
		card.modulate = UiStyle.COL_WHITE if is_selected else DIM_COLOR
		card.z_index = 1 if is_selected else 0
		(card.get_node("Pick") as Control).visible = is_selected
		var target: Vector2 = Vector2.ONE * (SELECTED_SCALE if is_selected else 1.0)
		UiStyle.kill_tween(card, "pop_tween")
		if animated and visible and card.is_inside_tree():
			var tween: Tween = card.create_tween()
			tween.tween_property(card, "scale", target, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			card.set_meta("pop_tween", tween)
		else:
			card.scale = target
	if _sunburst != null:
		_sunburst.ray_color = Color(CharacterDefs.color(_selected), 0.1)


func _animate_entrance() -> void:
	for i: int in cards.size():
		var card: Control = cards[i]
		var rest: Vector2 = card.get_meta("rest_position") as Vector2
		UiStyle.kill_tween(card, "enter_tween")
		card.position = rest
		card.rotation_degrees = 0.0
		if not card.is_inside_tree():
			continue
		card.position = rest + Vector2(0.0, 480.0)
		card.rotation_degrees = -10.0 if i % 2 == 0 else 10.0
		var delay: float = 0.05 * float(i)
		var tween: Tween = card.create_tween()
		tween.set_parallel(true)
		tween.tween_property(card, "position", rest, 0.26).set_delay(delay) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "rotation_degrees", 0.0, 0.26).set_delay(delay) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		card.set_meta("enter_tween", tween)
	UiStyle.pop(_headline, 0.3, 0.28)


func _on_unlocked() -> void:
	hint_label.modulate.a = 1.0
	UiStyle.pop(hint_label, 1.15, 0.2)


## Zeigt den Kontostand aus Game.progress.
func _update_bank() -> void:
	if bank_label == null:
		return
	var text: String = "KONTO  %s" % UiStyle.format_int(Game.progress.bank)
	bank_label.text = text
	bank_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(text, 20, BANK_RECT.size.x - 8.0, true, 13))


func _on_bank_changed(_bank: int, _gained: int) -> void:
	_update_bank()
	if is_open():
		UiStyle.pop(bank_label, 1.2, 0.2)


## Der Knopf beachtet die Sperre nach dem Öffnen wie jede andere Eingabe.
func _on_program_pressed() -> void:
	if is_input_locked():
		return
	open_program()


# --- Eingabe --------------------------------------------------------------------------

## Maus auf einer Karte: Bewegung markiert sie, ein Linksklick wählt sie. Während der Sperre
## nach dem Öffnen wirkt beides nicht (ein ruhender Zeiger verdrängt die Vorauswahl nicht).
func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if not is_open() or is_program_open() or index < 0 or index >= cards.size():
		return
	var id: String = CharacterDefs.ORDER[index]
	if event is InputEventMouseMotion:
		if not is_input_locked():
			select(id)
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if cards[index].is_inside_tree():
		cards[index].accept_event()
	if is_input_locked():
		return
	choose(id)


# --- Gezeichnete Bausteine ------------------------------------------------------------

## Form eines Rucksacks im Raster: alle Felder des Rasters blass, die Felder des Rucksacks
## kräftig in der Farbe fill. Das Raster wird in die Größe des Controls eingepasst.
class BagShape:
	extends Control

	## Größe des Rasters in Feldern.
	var cols: int = 7:
		set(value):
			cols = value
			queue_redraw()
	var rows: int = 5:
		set(value):
			rows = value
			queue_redraw()
	## Felder des Rucksacks (x nach rechts, y nach unten).
	var cells: Array[Vector2i] = []:
		set(value):
			cells = value
			queue_redraw()
	var fill: Color = Color(1.0, 1.0, 1.0):
		set(value):
			fill = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if cols <= 0 or rows <= 0 or size.x < 4.0 or size.y < 4.0:
			return
		var cell: float = minf(size.x / float(cols), size.y / float(rows))
		var origin: Vector2 = (size - Vector2(float(cols), float(rows)) * cell) * 0.5
		for y: int in rows:
			for x: int in cols:
				var rect: Rect2 = Rect2(origin + Vector2(float(x), float(y)) * cell, Vector2(cell, cell)).grow(-1.5)
				if cells.has(Vector2i(x, y)):
					draw_rect(rect, Color(0.05, 0.04, 0.12))
					draw_rect(rect.grow(-2.0), fill)
					draw_rect(Rect2(rect.position + Vector2(3.0, 3.0), Vector2(rect.size.x - 6.0, rect.size.y * 0.28)), fill.lightened(0.45))
				else:
					draw_rect(rect, Color(1.0, 1.0, 1.0, 0.07))
					draw_rect(rect, Color(1.0, 1.0, 1.0, 0.16), false, 1.0)
