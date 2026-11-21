extends CanvasLayer
## Modul: Oberfläche (scripts/ui).
## Bildschirm „Programm“ (Abschnitt 22.5): Mit dem Konto kauft man zwischen den Läufen Pakete.
## Was in einem gekauften Paket steckt, kann danach in Kisten liegen.
##
## Aufbau bei 1280x720: oben Überschrift und Kontostand. Links ein Raster mit den elf Paketen
## als Karten (Name, Inhalt, Preis, Zustand), im zwölften Fach der Fortschritt (x von 11 Paketen,
## beste Welle, Läufe) und der Knopf „Zurück“. Rechts die Tafel zum markierten Paket: je Teil
## Bild, Name, Art (Waffe, Kamera, Gegenstand ...) und der Wirkungstext aus ItemDefs, darunter
## der große Kaufknopf.
##
## Der Bildschirm führt keinen eigenen Spielzustand ein: Er liegt deckend über der Kandidatenwahl
## (Game.State.MENU) oder über dem Game Over. Wer ihn öffnet, bleibt darunter offen und ist nach
## close() wieder zu sehen (Signal closed). Solange er offen ist, verbraucht er alle Tasten, damit
## der Bildschirm darunter nichts auslöst. process_mode ALWAYS, weil der Baum im Game Over
## pausiert ist.
##
## Bedienung: Maus über einer Karte markiert sie, der Knopf „Kaufen“ auf der Karte oder in der
## Tafel kauft. Pfeiltasten wechseln die Karte, Enter oder Leertaste kauft die markierte, Esc
## geht zurück. Kurz nach dem Öffnen ist das Kaufen gesperrt (INPUT_LOCK_SECONDS): Der Klick,
## der den Bildschirm geöffnet hat, soll nichts kaufen.
##
## Zwei Wege zum Kauf:
## - buy(pack_id): sofort und ohne Sperre (für Tests und andere Module), ruft Game.buy_pack.
## - request_buy(pack_id): der Weg der Eingabe (Knopf, Taste), beachtet die Sperre.
## Die Anzeige folgt Events.bank_changed und Events.pack_unlocked.

signal closed

const UiStyle := preload("res://scripts/ui/hud.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UnlockDefs := preload("res://scripts/core/unlock_defs.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")

## Über allen anderen Bildschirmen (Game Over 30, Kandidatenwahl 40).
const LAYER: int = 45

## Zustand eines Pakets (pack_state).
const STATE_OWNED: String = "owned"
const STATE_BUYABLE: String = "buyable"
const STATE_LOCKED: String = "locked"

# --- Optik- und Bedien-Zahlen (keine Spielregeln) ---
## So lange nach dem Öffnen kauft keine Eingabe etwas (echte Zeit über _process).
const INPUT_LOCK_SECONDS: float = 0.3
const MAX_LOCK_STEP: float = 0.05
const STAGE_SIZE: Vector2 = Vector2(1232.0, 696.0)
const GRID_ORIGIN: Vector2 = Vector2(0.0, 104.0)
const GRID_COLUMNS: int = 4
const CARD_SIZE: Vector2 = Vector2(194.0, 190.0)
const CARD_GAP: Vector2 = Vector2(12.0, 11.0)
const CARD_ITEM_TOP: float = 42.0
const CARD_ITEM_STEP: float = 20.0
const DETAIL_RECT: Rect2 = Rect2(828.0, 104.0, 404.0, 592.0)
const DETAIL_PADDING: float = 16.0
const DETAIL_ICON: float = 48.0
const DETAIL_ITEMS_TOP: float = 80.0
const DETAIL_ITEMS_BOTTOM: float = 498.0
const DETAIL_NAME_LINE: float = 24.0
const DETAIL_GAP: float = 10.0
const DETAIL_TEXT_SIZES: Array[int] = [14, 13, 12, 11]
const DETAIL_LINE_SPACING: int = 1
const BANK_RECT: Rect2 = Rect2(892.0, 6.0, 340.0, 86.0)
const BANK_FONT_SIZE: int = 46
const SELECTED_SCALE: float = 1.04
const HEADLINE_TEXT: String = "DAS PROGRAMM"
const SUBLINE_TEXT: String = "Mit dem Konto kaufst du Pakete.\nWas drin ist, liegt danach in den Kisten."
const HINT_TEXT: String = "Esc: zurück · Pfeile: wählen\nEnter: kaufen"
const FOOTNOTE_TEXT: String = "Die Zahlen gelten für die Rarität Gewöhnlich."
const COL_LOCKED: Color = Color(0.5, 0.42, 0.7)

## Karten in der Reihenfolge von UnlockDefs.PACK_ORDER. Meta "id" = Paket. Kinder je Karte:
## "Back", "Name", "Items" (je Teil "Dot_<n>" und "Item_<n>"), "Price", "State" (Label:
## "GEKAUFT" oder "Es fehlen 1.500"), "Buy" (Knopf, nur sichtbar, wenn das Konto reicht).
var cards: Array[Control] = []
## Überschrift des Bildschirms.
var headline_label: Label
## Kontostand groß, mit Tausenderpunkt.
var bank_label: Label
## "3 VON 11 PAKETEN".
var progress_label: Label
## Balken zum Fortschritt (Anteil gekaufter Pakete).
var progress_bar: UiStyle.SlantBar
## "Beste Welle: 7".
var best_wave_label: Label
## "Läufe: 12".
var runs_label: Label
## Knopf "ZURÜCK" (close).
var back_button: Button
## Tafel rechts: Name des markierten Pakets.
var detail_name_label: Label
## Tafel rechts: Preis und Zustand des markierten Pakets.
var detail_state_label: Label
## Tafel rechts: Behälter der Teile. Je Teil ein Kind "Item_<id>" mit "Icon", "Name", "Kind", "Text".
var detail_items: Control
## Tafel rechts: großer Kaufknopf. Ausgegraut, wenn das Konto nicht reicht, unsichtbar, wenn
## das Paket schon gekauft ist.
var buy_button: Button
## Tafel rechts: "GEKAUFT" anstelle des Kaufknopfs.
var owned_label: Label

var _built: bool = false
var _selected: String = ""
var _lock_left: float = 0.0
var _headline: PanelContainer
var _bank_box: Control
var _detail_pack: String = ""


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_ensure_built()
	Events.bank_changed.connect(_on_bank_changed)
	Events.pack_unlocked.connect(_on_pack_unlocked)
	Events.run_started.connect(_on_run_started)


func _process(delta: float) -> void:
	if not is_open() or _lock_left <= 0.0:
		return
	_lock_left = maxf(_lock_left - minf(delta, MAX_LOCK_STEP), 0.0)


## Solange der Bildschirm offen ist, gehört ihm jede Taste: Die Kandidatenwahl oder das Game Over
## darunter bekommen nichts ab. Die Tasten werden schon in _input verbraucht, also vor den Knöpfen
## der Bildschirme darunter: Sonst könnten Pfeiltasten dort einen Knopf markieren, der dann Enter
## abfängt.
func _input(event: InputEvent) -> void:
	_handle_key(event)


func _unhandled_input(event: InputEvent) -> void:
	_handle_key(event)


func _handle_key(event: InputEvent) -> void:
	if not is_open():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null:
		if event is InputEventAction or event is InputEventJoypadButton:
			_swallow()
		return
	_swallow()
	if not key.pressed or key.echo:
		return
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	match code:
		KEY_ESCAPE, KEY_BACKSPACE:
			close()
		KEY_LEFT:
			_step_selection(-1, 0)
		KEY_RIGHT:
			_step_selection(1, 0)
		KEY_UP:
			_step_selection(0, -1)
		KEY_DOWN:
			_step_selection(0, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			request_buy(_selected)


# --- Öffentliche Schnittstelle ---------------------------------------------------------

## Zeigt den Bildschirm. Markiert ist das erste Paket, für das das Konto reicht, sonst das erste
## noch nicht gekaufte, sonst das erste.
func open() -> void:
	_ensure_built()
	_selected = _default_selection()
	_lock_left = INPUT_LOCK_SECONDS
	visible = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Kein Knopf des Bildschirms darunter soll Enter oder Leertaste abfangen.
	if is_inside_tree():
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()
	refresh()
	if is_inside_tree():
		UiStyle.pop(_headline, 0.4, 0.26)
		UiStyle.pop(_bank_box, 0.7, 0.3)


## Schließt den Bildschirm und meldet closed. Geschlossen passiert nichts.
func close() -> void:
	if not visible:
		return
	visible = false
	_lock_left = 0.0
	closed.emit()


## Ist der Bildschirm gerade offen?
func is_open() -> bool:
	return visible


## Ist das Kaufen per Eingabe noch gesperrt (kurz nach dem Öffnen)?
func is_input_locked() -> bool:
	return _lock_left > 0.0


## Gerade markiertes Paket.
func selected_id() -> String:
	return _selected


## Markiert ein Paket: Die Tafel rechts zeigt seinen Inhalt. Eine unbekannte ID ändert nichts.
func select(pack_id: String) -> void:
	if not UnlockDefs.has_pack(pack_id) or pack_id == _selected:
		return
	_selected = pack_id
	refresh()


## Karte eines Pakets, null bei unbekannter ID.
func card_of(pack_id: String) -> Control:
	var index: int = UnlockDefs.PACK_ORDER.find(pack_id)
	if index < 0 or index >= cards.size():
		return null
	return cards[index]


## Zustand eines Pakets: STATE_OWNED (gekauft), STATE_BUYABLE (das Konto reicht) oder
## STATE_LOCKED (zu teuer). "" bei unbekannter ID.
static func pack_state(pack_id: String) -> String:
	if not UnlockDefs.has_pack(pack_id):
		return ""
	if Game.progress.has_pack(pack_id):
		return STATE_OWNED
	return STATE_BUYABLE if Game.progress.can_buy(pack_id) else STATE_LOCKED


## Punkte, die dem Konto für dieses Paket noch fehlen (0, wenn es reicht oder schon gekauft ist).
static func missing_points(pack_id: String) -> int:
	if not UnlockDefs.has_pack(pack_id) or Game.progress.has_pack(pack_id):
		return 0
	return maxi(UnlockDefs.pack_price(pack_id) - Game.progress.bank, 0)


## Art eines Teils in einfachen Worten: "Waffe · 1 Hand", "Kamera", "Kamera-Zubehör",
## "Verstärker", "Rucksack" oder "Gegenstand".
static func kind_text(item_id: String) -> String:
	if ItemDefs.is_weapon(item_id):
		return "Waffe · %s" % ("1 Hand" if ItemDefs.hands(item_id) == 1 else "2 Hände")
	if ItemDefs.is_camera(item_id):
		return "Kamera"
	if CameraDefs.is_mod(item_id):
		return "Kamera-Zubehör"
	if ItemDefs.is_booster(item_id):
		return "Verstärker"
	if ItemDefs.is_bag(item_id):
		return "Rucksack"
	return "Gegenstand"


## Kauft das Paket über Game.buy_pack (ohne Rücksicht auf die Eingabesperre). true, wenn es
## geklappt hat: Konto, Karten und Tafel zeigen dann schon den neuen Stand. false (und nichts
## ändert sich) bei geschlossenem Bildschirm, unbekanntem oder schon gekauftem Paket oder wenn
## das Konto nicht reicht.
func buy(pack_id: String) -> bool:
	if not is_open() or not Game.buy_pack(pack_id):
		return false
	_selected = pack_id
	refresh()
	var card: Control = card_of(pack_id)
	if card != null and card.is_inside_tree():
		UiStyle.pop(card, 1.18, 0.3)
	if is_inside_tree():
		UiStyle.pop(_bank_box, 1.15, 0.25)
	return true


## Kauf über Knopf oder Taste: wie buy, aber nicht während der Sperre nach dem Öffnen.
func request_buy(pack_id: String) -> bool:
	if is_input_locked():
		return false
	return buy(pack_id)


## Bringt Konto, Karten, Fortschritt und Tafel auf den Stand von Game.progress.
func refresh() -> void:
	if not _built:
		return
	if not UnlockDefs.has_pack(_selected):
		_selected = _default_selection()
	var bank_text: String = UiStyle.format_int(Game.progress.bank)
	bank_label.text = bank_text
	bank_label.add_theme_font_size_override("font_size",
			UiStyle.fit_font_size(bank_text, BANK_FONT_SIZE, BANK_RECT.size.x - 60.0, true, 24))
	var owned: int = 0
	for i: int in cards.size():
		var pack_id: String = UnlockDefs.PACK_ORDER[i]
		if Game.progress.has_pack(pack_id):
			owned += 1
		_update_card(cards[i], pack_id)
	var total: int = UnlockDefs.PACK_ORDER.size()
	progress_label.text = "%d VON %d PAKETEN" % [owned, total]
	progress_bar.ratio = float(owned) / float(maxi(total, 1))
	best_wave_label.text = "Beste Welle: %d" % Game.progress.best_wave
	runs_label.text = "Läufe: %d" % Game.progress.runs
	_update_detail()


# --- Aufbau ---------------------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_build()
	_built = true
	_selected = _default_selection()
	refresh()


func _build() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# Deckend: Vom Bildschirm darunter ist nichts zu sehen, und kein Klick kommt dort an.
	var background: ColorRect = UiStyle.make_dim(Color(UiStyle.COL_INK, 1.0))
	background.name = "Background"
	root.add_child(background)
	var sunburst: UiStyle.Sunburst = UiStyle.Sunburst.new()
	sunburst.name = "Sunburst"
	sunburst.ray_color = Color(UiStyle.COL_YELLOW, 0.06)
	sunburst.speed = 0.05
	sunburst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sunburst)
	# Bühne fester Größe in der Bildmitte: passt bei 1280x720 und bleibt bei größeren Fenstern mittig.
	var stage: Control = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(stage, Vector2(0.5, 0.5), -STAGE_SIZE * 0.5, STAGE_SIZE)
	root.add_child(stage)

	_headline = UiStyle.make_headline(HEADLINE_TEXT, 46, UiStyle.COL_PINK, UiStyle.COL_YELLOW, UiStyle.COL_YELLOW)
	_headline.name = "Headline"
	_headline.pivot_offset_ratio = Vector2(0.5, 0.5)
	_headline.rotation_degrees = -2.0
	UiStyle.anchor_box(_headline, Vector2.ZERO, Vector2(14.0, 10.0), Vector2.ZERO)
	stage.add_child(_headline)
	headline_label = _headline.get_node("Label") as Label
	var subline: Label = UiStyle.make_label(SUBLINE_TEXT, 17, UiStyle.COL_WHITE, true)
	subline.name = "Subline"
	subline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(subline, Vector2.ZERO, Vector2(486.0, 14.0), Vector2(396.0, 64.0))
	stage.add_child(subline)

	_build_bank(stage)
	var cards_root: Control = Control.new()
	cards_root.name = "Cards"
	cards_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(cards_root, Vector2.ZERO, GRID_ORIGIN, Vector2(DETAIL_RECT.position.x - 16.0, STAGE_SIZE.y - GRID_ORIGIN.y))
	stage.add_child(cards_root)
	for i: int in UnlockDefs.PACK_ORDER.size():
		var card: Control = _make_card(UnlockDefs.PACK_ORDER[i])
		card.position = _slot_position(i)
		cards_root.add_child(card)
		cards.append(card)
	var stats_box: Control = _make_stats_box()
	stats_box.position = _slot_position(UnlockDefs.PACK_ORDER.size())
	cards_root.add_child(stats_box)
	_build_detail(stage)


## Linke obere Ecke des Fachs index im Raster (zeilenweise gefüllt).
func _slot_position(index: int) -> Vector2:
	var column: int = index % GRID_COLUMNS
	@warning_ignore("integer_division")
	var line: int = index / GRID_COLUMNS
	return Vector2(float(column) * (CARD_SIZE.x + CARD_GAP.x), float(line) * (CARD_SIZE.y + CARD_GAP.y))


func _build_bank(stage: Control) -> void:
	_bank_box = Control.new()
	_bank_box.name = "Bank"
	_bank_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bank_box.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(_bank_box, Vector2.ZERO, BANK_RECT.position, BANK_RECT.size)
	stage.add_child(_bank_box)
	var plate: Panel = UiStyle.make_plate(UiStyle.COL_PANEL_SOLID, UiStyle.COL_YELLOW, 5, 0.12, 10)
	plate.name = "Plate"
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bank_box.add_child(plate)
	var tag: Label = UiStyle.make_label("KONTO", 17, UiStyle.COL_CYAN, true)
	tag.name = "Tag"
	UiStyle.anchor_box(tag, Vector2.ZERO, Vector2(26.0, 6.0), Vector2(120.0, 24.0))
	_bank_box.add_child(tag)
	var unit: Label = UiStyle.make_label("PUNKTE", 13, UiStyle.COL_WHITE, true)
	unit.name = "Unit"
	_thin_outline(unit)
	UiStyle.anchor_box(unit, Vector2.ZERO, Vector2(26.0, 56.0), Vector2(120.0, 20.0))
	_bank_box.add_child(unit)
	bank_label = UiStyle.make_label("0", BANK_FONT_SIZE, UiStyle.COL_YELLOW, true)
	bank_label.name = "Value"
	bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(bank_label, Vector2.ZERO, Vector2(20.0, 8.0), Vector2(BANK_RECT.size.x - 44.0, BANK_RECT.size.y - 14.0))
	_bank_box.add_child(bank_label)


func _make_card(pack_id: String) -> Control:
	var card: Control = Control.new()
	card.name = "Card_%s" % pack_id
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.pivot_offset_ratio = Vector2(0.5, 0.5)
	card.set_meta("id", pack_id)
	card.gui_input.connect(_on_card_gui_input.bind(pack_id))
	card.mouse_entered.connect(_on_card_hover.bind(pack_id))

	var back_box: StyleBoxFlat = UiStyle.make_box(UiStyle.COL_PANEL_SOLID, COL_LOCKED, 4, 0.0, 12)
	back_box.shadow_offset = Vector2(5.0, 6.0)
	var back: Panel = Panel.new()
	back.name = "Back"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", back_box)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(back)
	card.set_meta("box", back_box)

	var inner_width: float = CARD_SIZE.x - 20.0
	var pack_name: String = UnlockDefs.pack_name(pack_id)
	var name_label: Label = UiStyle.make_label(pack_name, UiStyle.fit_font_size(pack_name, 20, inner_width - 6.0, true, 13),
			UiStyle.COL_YELLOW, true)
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(name_label, Vector2.ZERO, Vector2(10.0, 6.0), Vector2(inner_width, 28.0))
	card.add_child(name_label)
	var rule: ColorRect = ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(UiStyle.COL_WHITE, 0.25)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(rule, Vector2.ZERO, Vector2(14.0, 36.0), Vector2(CARD_SIZE.x - 28.0, 2.0))
	card.add_child(rule)

	# Inhalt: je Teil ein Farbfeld (Art) und der Name.
	var items: Control = Control.new()
	items.name = "Items"
	items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(items, Vector2.ZERO, Vector2(0.0, CARD_ITEM_TOP), Vector2(CARD_SIZE.x, CARD_ITEM_STEP * 4.0))
	card.add_child(items)
	var item_ids: Array[String] = UnlockDefs.pack_items(pack_id)
	for n: int in item_ids.size():
		var item_id: String = item_ids[n]
		var dot: ColorRect = ColorRect.new()
		dot.name = "Dot_%d" % n
		dot.color = ItemDefs.color(item_id)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiStyle.anchor_box(dot, Vector2.ZERO, Vector2(14.0, float(n) * CARD_ITEM_STEP + 5.0), Vector2(10.0, 10.0))
		items.add_child(dot)
		var item_name: String = ItemDefs.display_name(item_id)
		var item_width: float = CARD_SIZE.x - 42.0
		var item_label: Label = UiStyle.make_label(item_name, UiStyle.fit_font_size(item_name, 14, item_width - 4.0, false, 10), UiStyle.COL_WHITE)
		item_label.name = "Item_%d" % n
		item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item_label.clip_text = true
		_thin_outline(item_label)
		UiStyle.anchor_box(item_label, Vector2.ZERO, Vector2(31.0, float(n) * CARD_ITEM_STEP), Vector2(item_width, CARD_ITEM_STEP))
		items.add_child(item_label)

	var price_label: Label = UiStyle.make_label("%s Punkte" % UiStyle.format_int(UnlockDefs.pack_price(pack_id)), 16, UiStyle.COL_WHITE, true)
	price_label.name = "Price"
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(price_label, Vector2.ZERO, Vector2(10.0, 124.0), Vector2(inner_width, 24.0))
	card.add_child(price_label)

	var state_label: Label = UiStyle.make_label("", 15, UiStyle.COL_GREEN, true)
	state_label.name = "State"
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(state_label, Vector2.ZERO, Vector2(10.0, 150.0), Vector2(inner_width, 32.0))
	card.add_child(state_label)

	var button: Button = _make_small_button("KAUFEN", UiStyle.COL_GREEN, 17, Vector2(150.0, 32.0))
	button.name = "Buy"
	UiStyle.anchor_box(button, Vector2.ZERO, Vector2((CARD_SIZE.x - 150.0) * 0.5, 150.0), Vector2(150.0, 32.0))
	button.pressed.connect(_on_card_buy_pressed.bind(pack_id))
	button.mouse_entered.connect(_on_card_hover.bind(pack_id))
	card.add_child(button)
	return card


## Zwölftes Fach des Rasters: Fortschritt, beste Welle, Läufe und der Knopf "Zurück".
func _make_stats_box() -> Control:
	var box: Control = Control.new()
	box.name = "Stats"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = CARD_SIZE
	box.size = CARD_SIZE
	var plate: Panel = UiStyle.make_plate(Color(0.0, 0.0, 0.0, 0.35), Color(UiStyle.COL_CYAN, 0.6), 3, 0.0, 12)
	plate.name = "Plate"
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(plate)
	var inner_width: float = CARD_SIZE.x - 20.0
	progress_label = UiStyle.make_label("", 16, UiStyle.COL_CYAN, true)
	progress_label.name = "Progress"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(progress_label, Vector2.ZERO, Vector2(10.0, 8.0), Vector2(inner_width, 24.0))
	box.add_child(progress_label)
	progress_bar = UiStyle.SlantBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.slant = 5.0
	progress_bar.border = 3.0
	progress_bar.fill_color = UiStyle.COL_GREEN
	UiStyle.anchor_box(progress_bar, Vector2.ZERO, Vector2(16.0, 34.0), Vector2(CARD_SIZE.x - 32.0, 14.0))
	box.add_child(progress_bar)
	best_wave_label = UiStyle.make_label("", 15, UiStyle.COL_WHITE)
	best_wave_label.name = "BestWave"
	best_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thin_outline(best_wave_label)
	UiStyle.anchor_box(best_wave_label, Vector2.ZERO, Vector2(10.0, 54.0), Vector2(inner_width, 22.0))
	box.add_child(best_wave_label)
	runs_label = UiStyle.make_label("", 15, UiStyle.COL_WHITE)
	runs_label.name = "Runs"
	runs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thin_outline(runs_label)
	UiStyle.anchor_box(runs_label, Vector2.ZERO, Vector2(10.0, 76.0), Vector2(inner_width, 22.0))
	box.add_child(runs_label)
	back_button = _make_small_button("ZURÜCK", UiStyle.COL_ORANGE, 22, Vector2(160.0, 42.0))
	back_button.name = "Back"
	UiStyle.anchor_box(back_button, Vector2.ZERO, Vector2((CARD_SIZE.x - 160.0) * 0.5, 104.0), Vector2(160.0, 42.0))
	back_button.pressed.connect(close)
	box.add_child(back_button)
	var hint: Label = UiStyle.make_label(HINT_TEXT, 11, UiStyle.COL_CYAN)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_thin_outline(hint)
	UiStyle.anchor_box(hint, Vector2.ZERO, Vector2(6.0, 150.0), Vector2(CARD_SIZE.x - 12.0, 34.0))
	box.add_child(hint)
	return box


func _build_detail(stage: Control) -> void:
	var detail: Control = Control.new()
	detail.name = "Detail"
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(detail, Vector2.ZERO, DETAIL_RECT.position, DETAIL_RECT.size)
	stage.add_child(detail)
	var plate: Panel = UiStyle.make_plate(UiStyle.COL_PANEL, UiStyle.COL_CYAN, 4, 0.0, 12)
	plate.name = "Plate"
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail.add_child(plate)
	var inner_width: float = DETAIL_RECT.size.x - DETAIL_PADDING * 2.0
	detail_name_label = UiStyle.make_label("", 28, UiStyle.COL_YELLOW, true)
	detail_name_label.name = "Name"
	detail_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(detail_name_label, Vector2.ZERO, Vector2(DETAIL_PADDING, 8.0), Vector2(inner_width, 38.0))
	detail.add_child(detail_name_label)
	detail_state_label = UiStyle.make_label("", 16, UiStyle.COL_WHITE)
	detail_state_label.name = "State"
	detail_state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_thin_outline(detail_state_label)
	UiStyle.anchor_box(detail_state_label, Vector2.ZERO, Vector2(DETAIL_PADDING, 46.0), Vector2(inner_width, 24.0))
	detail.add_child(detail_state_label)
	var rule: ColorRect = ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(UiStyle.COL_CYAN, 0.45)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(rule, Vector2.ZERO, Vector2(DETAIL_PADDING, 72.0), Vector2(inner_width, 2.0))
	detail.add_child(rule)
	detail_items = Control.new()
	detail_items.name = "Items"
	detail_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(detail_items, Vector2.ZERO, Vector2(DETAIL_PADDING, DETAIL_ITEMS_TOP),
			Vector2(inner_width, DETAIL_ITEMS_BOTTOM - DETAIL_ITEMS_TOP))
	detail.add_child(detail_items)
	var footnote: Label = UiStyle.make_label(FOOTNOTE_TEXT, 12, Color(UiStyle.COL_CYAN, 0.9))
	footnote.name = "Footnote"
	footnote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thin_outline(footnote)
	UiStyle.anchor_box(footnote, Vector2.ZERO, Vector2(DETAIL_PADDING, DETAIL_ITEMS_BOTTOM + 2.0), Vector2(inner_width, 18.0))
	detail.add_child(footnote)
	var button_size: Vector2 = Vector2(inner_width - 16.0, 56.0)
	buy_button = UiStyle.make_button("KAUFEN", UiStyle.COL_GREEN, 26)
	buy_button.name = "Buy"
	buy_button.focus_mode = Control.FOCUS_NONE
	buy_button.custom_minimum_size = button_size
	buy_button.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(buy_button, Vector2.ZERO, Vector2(DETAIL_PADDING + 8.0, DETAIL_RECT.size.y - 72.0), button_size)
	buy_button.pressed.connect(_on_detail_buy_pressed)
	detail.add_child(buy_button)
	owned_label = UiStyle.make_label("GEKAUFT", 30, UiStyle.COL_GREEN, true)
	owned_label.name = "Owned"
	owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	owned_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(owned_label, Vector2.ZERO, Vector2(DETAIL_PADDING, DETAIL_RECT.size.y - 72.0), Vector2(inner_width, 56.0))
	owned_label.visible = false
	detail.add_child(owned_label)


## Kleiner Knopf im Show-Stil (dünnerer Rand als die großen Knöpfe). Ohne Tastatur-Fokus: Die
## Tasten gehen an _unhandled_input.
func _make_small_button(text: String, accent: Color, font_size: int, button_size: Vector2) -> Button:
	var button: Button = UiStyle.make_button(text, accent, font_size)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = button_size
	button.pivot_offset_ratio = Vector2(0.5, 0.5)
	button.add_theme_stylebox_override("normal", UiStyle.make_box(accent, UiStyle.COL_INK, 3, UiStyle.PLATE_SKEW, 6))
	button.add_theme_stylebox_override("hover", UiStyle.make_box(accent.lightened(0.45), UiStyle.COL_WHITE, 3, UiStyle.PLATE_SKEW, 6))
	button.add_theme_stylebox_override("pressed", UiStyle.make_box(UiStyle.COL_PINK, UiStyle.COL_WHITE, 3, UiStyle.PLATE_SKEW, 6))
	return button


## Kleine Schrift bekommt einen dünneren Rand, sonst läuft sie zu.
func _thin_outline(label: Label) -> void:
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_constant_override("shadow_outline_size", 3)


# --- Anzeige --------------------------------------------------------------------------

## Erstes Paket, für das das Konto reicht, sonst das erste noch nicht gekaufte, sonst das erste.
func _default_selection() -> String:
	var first_open: String = ""
	for pack_id: String in UnlockDefs.PACK_ORDER:
		if Game.progress.has_pack(pack_id):
			continue
		if Game.progress.can_buy(pack_id):
			return pack_id
		if first_open.is_empty():
			first_open = pack_id
	if not first_open.is_empty():
		return first_open
	return UnlockDefs.PACK_ORDER[0] if not UnlockDefs.PACK_ORDER.is_empty() else ""


## Farbe zum Zustand eines Pakets: gekauft grün, kaufbar gelb, zu teuer blass.
func _state_color(state: String) -> Color:
	match state:
		STATE_OWNED:
			return UiStyle.COL_GREEN
		STATE_BUYABLE:
			return UiStyle.COL_YELLOW
	return COL_LOCKED


func _update_card(card: Control, pack_id: String) -> void:
	var state: String = pack_state(pack_id)
	var is_selected: bool = pack_id == _selected
	var color: Color = _state_color(state)
	var box: StyleBoxFlat = card.get_meta("box") as StyleBoxFlat
	box.border_color = UiStyle.COL_WHITE if is_selected else color
	box.set_border_width_all(5 if is_selected else 4)
	box.bg_color = UiStyle.COL_PANEL_SOLID.lerp(color, 0.3 if is_selected else 0.14)
	card.z_index = 1 if is_selected else 0
	card.scale = Vector2.ONE * (SELECTED_SCALE if is_selected else 1.0)
	var price_label: Label = card.get_node("Price") as Label
	var state_label: Label = card.get_node("State") as Label
	var button: Button = card.get_node("Buy") as Button
	button.visible = state == STATE_BUYABLE
	state_label.visible = state != STATE_BUYABLE
	price_label.add_theme_color_override("font_color", UiStyle.COL_YELLOW if state == STATE_BUYABLE else UiStyle.COL_WHITE)
	price_label.modulate.a = 0.6 if state == STATE_OWNED else 1.0
	if state == STATE_OWNED:
		state_label.text = "GEKAUFT"
		state_label.add_theme_color_override("font_color", UiStyle.COL_GREEN)
		state_label.add_theme_font_size_override("font_size", 20)
	else:
		state_label.text = "Es fehlen %s" % UiStyle.format_int(missing_points(pack_id))
		state_label.add_theme_color_override("font_color", UiStyle.COL_ORANGE)
		state_label.add_theme_font_size_override("font_size", 15)


func _update_detail() -> void:
	if not UnlockDefs.has_pack(_selected):
		return
	if _detail_pack != _selected:
		_detail_pack = _selected
		_fill_detail_items(_selected)
	var pack_name: String = UnlockDefs.pack_name(_selected)
	var inner_width: float = DETAIL_RECT.size.x - DETAIL_PADDING * 2.0
	detail_name_label.text = pack_name
	detail_name_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(pack_name, 28, inner_width - 8.0, true, 18))
	var state: String = pack_state(_selected)
	var price_text: String = UiStyle.format_int(UnlockDefs.pack_price(_selected))
	buy_button.visible = state != STATE_OWNED
	owned_label.visible = state == STATE_OWNED
	match state:
		STATE_OWNED:
			detail_state_label.text = "Gekauft: Der Inhalt liegt in den Kisten."
			detail_state_label.add_theme_color_override("font_color", UiStyle.COL_GREEN)
		STATE_BUYABLE:
			detail_state_label.text = "Preis: %s Punkte" % price_text
			detail_state_label.add_theme_color_override("font_color", UiStyle.COL_YELLOW)
			buy_button.text = "KAUFEN: %s" % price_text
			buy_button.disabled = false
		_:
			var missing: String = UiStyle.format_int(missing_points(_selected))
			detail_state_label.text = "Preis: %s Punkte · es fehlen %s" % [price_text, missing]
			detail_state_label.add_theme_color_override("font_color", UiStyle.COL_ORANGE)
			buy_button.text = "ES FEHLEN %s" % missing
			buy_button.disabled = true


## Baut die Teile des Pakets in der Tafel: je Teil Bild, Name, Art und Wirkungstext. Die Schrift
## der Texte wird so groß gewählt, wie alle vier Teile untereinander Platz haben.
func _fill_detail_items(pack_id: String) -> void:
	for child: Node in detail_items.get_children():
		detail_items.remove_child(child)
		child.queue_free()
	var item_ids: Array[String] = UnlockDefs.pack_items(pack_id)
	var width: float = DETAIL_RECT.size.x - DETAIL_PADDING * 2.0
	var text_left: float = DETAIL_ICON + 10.0
	var text_width: float = width - text_left
	var available: float = DETAIL_ITEMS_BOTTOM - DETAIL_ITEMS_TOP
	var font: Font = UiStyle.show_font(false)
	var texts: Array[String] = []
	for item_id: String in item_ids:
		texts.append(UiStyle.keep_units_together(ItemDefs.description(item_id, 1)))
	var font_size: int = DETAIL_TEXT_SIZES[DETAIL_TEXT_SIZES.size() - 1]
	var heights: Array[float] = []
	for candidate: int in DETAIL_TEXT_SIZES:
		heights.clear()
		var total: float = 0.0
		for text: String in texts:
			var block: float = maxf(DETAIL_NAME_LINE + _text_height(font, text, text_width, candidate), DETAIL_ICON + 4.0)
			heights.append(block)
			total += block
		total += DETAIL_GAP * float(maxi(texts.size() - 1, 0))
		font_size = candidate
		if total <= available:
			break
	var y: float = 0.0
	for n: int in item_ids.size():
		var item_id: String = item_ids[n]
		var block: Control = Control.new()
		block.name = "Item_%s" % item_id
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiStyle.anchor_box(block, Vector2.ZERO, Vector2(0.0, y), Vector2(width, heights[n]))
		detail_items.add_child(block)
		block.add_child(_make_item_icon(item_id))
		var kind: String = kind_text(item_id)
		var kind_label: Label = UiStyle.make_label(kind, 13, ItemDefs.color(item_id), true)
		kind_label.name = "Kind"
		kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kind_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_thin_outline(kind_label)
		var kind_width: float = font.get_string_size(kind, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x + 22.0
		UiStyle.anchor_box(kind_label, Vector2.ZERO, Vector2(width - kind_width, 0.0), Vector2(kind_width, DETAIL_NAME_LINE))
		block.add_child(kind_label)
		var item_name: String = ItemDefs.display_name(item_id)
		var name_width: float = text_width - kind_width - 4.0
		var name_label: Label = UiStyle.make_label(item_name, UiStyle.fit_font_size(item_name, 18, name_width - 4.0, false, 12), UiStyle.COL_WHITE)
		name_label.name = "Name"
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		UiStyle.anchor_box(name_label, Vector2.ZERO, Vector2(text_left, 0.0), Vector2(name_width, DETAIL_NAME_LINE))
		block.add_child(name_label)
		var text_label: Label = UiStyle.make_label(texts[n], font_size, Color(0.9, 0.9, 1.0))
		text_label.name = "Text"
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.add_theme_constant_override("line_spacing", DETAIL_LINE_SPACING)
		_thin_outline(text_label)
		UiStyle.anchor_box(text_label, Vector2.ZERO, Vector2(text_left, DETAIL_NAME_LINE - 2.0), Vector2(text_width, heights[n] - DETAIL_NAME_LINE + 2.0))
		block.add_child(text_label)
		y += heights[n] + DETAIL_GAP


## Höhe eines umbrochenen Texts in einem Label dieser Breite (mit dem Zeilenabstand der Tafel).
func _text_height(font: Font, text: String, width: float, font_size: int) -> float:
	var line_height: float = maxf(font.get_height(font_size), 1.0)
	var measured: float = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
	var lines: float = maxf(roundf(measured / line_height), 1.0)
	return ceilf(lines * line_height + (lines - 1.0) * float(DETAIL_LINE_SPACING))


## Bild eines Teils: das gezeichnete Symbol, wenn es eines gibt, sonst seine Form im Rucksack.
func _make_item_icon(item_id: String) -> Control:
	var icon_size: Vector2 = Vector2(DETAIL_ICON, DETAIL_ICON)
	if UiStyle.has_icon(item_id):
		var icon: UiStyle.UpgradeIcon = UiStyle.UpgradeIcon.new()
		icon.name = "Icon"
		icon.icon_id = item_id
		UiStyle.anchor_box(icon, Vector2.ZERO, Vector2(0.0, 3.0), icon_size)
		return icon
	var shape: UiStyle.ItemShape = UiStyle.ItemShape.new()
	shape.name = "Icon"
	shape.item_id = item_id
	shape.max_cell = 20.0
	UiStyle.anchor_box(shape, Vector2.ZERO, Vector2(0.0, 3.0), icon_size)
	return shape


## Markierung um dx Spalten und dy Zeilen weiter. Zur Seite geht es am Ende der Liste vorn
## weiter, nach oben und unten bleibt die Markierung am Rand stehen.
func _step_selection(dx: int, dy: int) -> void:
	var count: int = UnlockDefs.PACK_ORDER.size()
	if count <= 0:
		return
	var index: int = maxi(UnlockDefs.PACK_ORDER.find(_selected), 0)
	if dx != 0:
		index = posmod(index + dx, count)
	if dy != 0:
		var target: int = index + dy * GRID_COLUMNS
		if target >= 0 and target < count:
			index = target
	select(UnlockDefs.PACK_ORDER[index])


func _swallow() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# --- Signale und Eingabe --------------------------------------------------------------

func _on_bank_changed(_bank: int, _gained: int) -> void:
	if visible:
		refresh()


func _on_pack_unlocked(_pack_id: String) -> void:
	if visible:
		refresh()


## Ein neuer Lauf beginnt: Der Bildschirm hat dort nichts verloren.
func _on_run_started() -> void:
	close()


func _on_card_hover(pack_id: String) -> void:
	if is_open():
		select(pack_id)


func _on_card_gui_input(event: InputEvent, pack_id: String) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or not is_open():
		return
	var card: Control = card_of(pack_id)
	if card != null and card.is_inside_tree():
		card.accept_event()
	select(pack_id)


func _on_card_buy_pressed(pack_id: String) -> void:
	request_buy(pack_id)


func _on_detail_buy_pressed() -> void:
	request_buy(_selected)
