extends CanvasLayer
## Modul: Oberfläche (scripts/ui).
## Game-Over-Bildschirm (Abschnitte 11 und 22.5): erreichte Welle, Kills, Punkte, die Gutschrift
## des Laufs aufs Konto mit dem neuen Kontostand, dazu der Build (Upgrades und Kameras mit ihrer
## Rarität, aktive Verbindungen).
## Knöpfe: Neustart -> Game.restart_run(), Programm -> open_program(), Beenden ->
## Game.quit_game(). Die Taste R (Aktion "reload") startet ebenfalls neu, die Taste P öffnet das
## Programm.
##
## Öffnet sich bei Events.game_over(stats). Das Spiel ist dann pausiert (GAME_OVER), deshalb
## process_mode ALWAYS. stats siehe Game.get_stats():
## { "wave": int, "kills": int, "points": int, "upgrades": Array von { "id", "name", "level" },
##   "synergies": Array[String], "cameras": Array von { "id", "name", "level" } (je Exemplar),
##   "bank_gained": int, "bank": int }.
## Kurz nach dem Öffnen sind Knöpfe und Tasten gesperrt (INPUT_LOCK_SECONDS), damit ein
## Tastendruck aus dem letzten Gefecht nicht sofort neu startet.
##
## Programm: main.gd setzt unlock_screen. open_program() meldet program_requested und öffnet
## den Bildschirm „Programm“ darüber. Solange er offen ist, nimmt das Game Over keine Eingabe an.
## Der Kontostand folgt Events.bank_changed (ein Kauf im Programm zieht ihn ab).

## Der Spieler will ins Programm (Knopf oder Taste P).
signal program_requested

const UiStyle := preload("res://scripts/ui/hud.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const UnlockScreen := preload("res://scripts/ui/unlock_screen.gd")

const LAYER: int = 30

# --- Optik- und Bedien-Zahlen ---
const INPUT_LOCK_SECONDS: float = 0.6
const MAX_LOCK_STEP: float = 0.05
const STAGE_SIZE: Vector2 = Vector2(860.0, 690.0)
const STAT_TOP: float = 156.0
const STAT_SIZE: Vector2 = Vector2(250.0, 96.0)
const STAT_GAP: float = 24.0
const STAT_FONT_SIZE: int = 46
## Streifen mit Gutschrift und Kontostand zwischen den Kennzahlen und dem Build.
const BANK_RECT: Rect2 = Rect2(20.0, 262.0, 820.0, 48.0)
const BANK_FONT_SIZE: int = 28
const BUILD_TOP: float = 320.0
const BUILD_SIZE: Vector2 = Vector2(820.0, 244.0)
## Die Liste des Builds hat drei Raster, je nach Zahl der Einträge: bis WIDE_SLOTS zwei breite
## Spalten, bis NARROW_SLOTS drei schmale, darüber vier Spalten mit engen Zeilen. Passt auch das
## nicht (mehr als COMPACT_SLOTS), nennt der letzte Platz, wie viele fehlen.
const ROW_SIZE: Vector2 = Vector2(380.0, 44.0)
const NARROW_ROW_SIZE: Vector2 = Vector2(250.0, 44.0)
const COMPACT_ROW_SIZE: Vector2 = Vector2(185.0, 36.0)
const WIDE_SLOTS: int = 8
const NARROW_SLOTS: int = 12
const COMPACT_SLOTS: int = 20
const ROW_STEP: float = 50.0
const COMPACT_ROW_STEP: float = 40.0
const BUTTON_TOP: float = 578.0
const BUTTON_SIZE: Vector2 = Vector2(262.0, 62.0)
const BUTTON_GAP: float = 17.0
const HINT_TEXT: String = "Taste R: sofort neu starten  ·  Taste P: Programm"

## Statistik des beendeten Laufs (leer, solange geschlossen).
var stats: Dictionary = {}
## Überschrift des Bildschirms.
var headline_label: Label
## Spruch unter der Überschrift (hängt von der erreichten Welle ab).
var subline_label: Label
## Erreichte Welle als Zahl.
var wave_value_label: Label
## Kills als Zahl.
var kills_value_label: Label
## Insgesamt verdiente Punkte mit Tausenderpunkt.
var points_value_label: Label
## Gutschrift des Laufs aufs Konto, z. B. "+4.972".
var bank_gain_label: Label
## Neuer Kontostand mit Tausenderpunkt.
var bank_label: Label
## Behälter der Zeilen des Builds: je Upgrade und je Kameratyp "Row_<id>" (Kinder "Name",
## "Rarity"; mehrere gleiche Kameras stehen als "2 × Kameradrohne" in einer Zeile), je Synergie
## "Synergy_<id>", bei zu vielen Einträgen zuletzt das Label "More" ("+3 weitere").
var upgrade_list: Control
## Hinweis, wenn der Lauf ohne Upgrade endete.
var empty_label: Label
## Knopf "Neustart" (Game.restart_run).
var restart_button: Button
## Knopf "Programm" (open_program).
var program_button: Button
## Knopf "Beenden" (Game.quit_game).
var quit_button: Button
## Bildschirm „Programm“, den der Knopf öffnet. Setzt main.gd, ohne ihn meldet der Knopf nur
## program_requested.
var unlock_screen: UnlockScreen = null

var _headline: PanelContainer
var _stat_boxes: Array[Control] = []
var _bank_box: Control
var _lock_left: float = 0.0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	Events.game_over.connect(show_stats)
	Events.run_started.connect(close)
	Events.bank_changed.connect(_on_bank_changed)


func _process(delta: float) -> void:
	if not is_open() or _lock_left <= 0.0:
		return
	_lock_left = maxf(_lock_left - minf(delta, MAX_LOCK_STEP), 0.0)
	if _lock_left <= 0.0:
		_set_buttons_disabled(false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or is_program_open():
		return
	if event.is_action_pressed("reload"):
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		request_restart()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code == KEY_P:
			if is_inside_tree():
				get_viewport().set_input_as_handled()
			if not is_input_locked():
				open_program()


## Zeigt den Bildschirm mit dieser Statistik und sperrt die Eingabe kurz.
func show_stats(run_stats: Dictionary) -> void:
	stats = run_stats
	var wave: int = int(run_stats.get("wave", 0))
	_set_stat(wave_value_label, str(wave))
	_set_stat(kills_value_label, UiStyle.format_int(int(run_stats.get("kills", 0))))
	_set_stat(points_value_label, UiStyle.format_int(int(run_stats.get("points", 0))))
	subline_label.text = _verdict(wave)
	bank_gain_label.text = "+%s" % UiStyle.format_int(maxi(int(run_stats.get("bank_gained", 0)), 0))
	_set_bank(int(run_stats.get("bank", Game.progress.bank)))
	var upgrades: Array = []
	var upgrades_value: Variant = run_stats.get("upgrades", [])
	if upgrades_value is Array:
		upgrades = upgrades_value
	var synergies: Array = []
	var synergies_value: Variant = run_stats.get("synergies", [])
	if synergies_value is Array:
		synergies = synergies_value
	var cameras: Array = []
	var cameras_value: Variant = run_stats.get("cameras", [])
	if cameras_value is Array:
		cameras = cameras_value
	_fill_build(upgrades, synergies, cameras)
	visible = true
	_lock_left = INPUT_LOCK_SECONDS
	_set_buttons_disabled(true)
	_animate_open()


## Ist der Game-Over-Bildschirm gerade offen?
func is_open() -> bool:
	return visible


## Sind Knöpfe und die Taste R noch gesperrt (kurz nach dem Öffnen)?
func is_input_locked() -> bool:
	return _lock_left > 0.0


## Neustart über Knopf oder Taste R. Wirkt nur bei offenem Bildschirm, nach der Sperre und
## nicht, solange das Programm darüber offen ist. Gibt true zurück, wenn neu gestartet wurde.
func request_restart() -> bool:
	if not is_open() or is_input_locked() or is_program_open():
		return false
	Game.restart_run()
	return true


## Öffnet den Bildschirm „Programm“ über dem Game Over (ohne Rücksicht auf die Eingabesperre) und
## meldet program_requested. Das Game Over bleibt darunter offen. false bei geschlossenem
## Bildschirm oder wenn das Programm schon offen ist.
func open_program() -> bool:
	if not is_open() or is_program_open():
		return false
	program_requested.emit()
	if is_instance_valid(unlock_screen):
		unlock_screen.open()
	return true


## Liegt gerade der Bildschirm „Programm“ über dem Game Over?
func is_program_open() -> bool:
	return is_instance_valid(unlock_screen) and unlock_screen.is_open()


## Blendet den Bildschirm aus (bei run_started).
func close() -> void:
	visible = false
	stats = {}
	_lock_left = 0.0


# --- Aufbau ---------------------------------------------------------------------------

func _build() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim: ColorRect = UiStyle.make_dim(Color(0.1, 0.0, 0.04, 0.86))
	dim.name = "Dim"
	root.add_child(dim)
	var sunburst: UiStyle.Sunburst = UiStyle.Sunburst.new()
	sunburst.name = "Sunburst"
	sunburst.ray_color = Color(UiStyle.COL_RED, 0.1)
	sunburst.speed = 0.08
	sunburst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sunburst)
	var stage: Control = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(stage, Vector2(0.5, 0.5), -STAGE_SIZE * 0.5, STAGE_SIZE)
	root.add_child(stage)

	_headline = UiStyle.make_headline("SENDESCHLUSS!", 60, UiStyle.COL_RED, UiStyle.COL_YELLOW, UiStyle.COL_YELLOW)
	_headline.name = "Headline"
	_headline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_headline.pivot_offset_ratio = Vector2(0.5, 0.5)
	_headline.rotation_degrees = -3.0
	UiStyle.anchor_box(_headline, Vector2(0.5, 0.0), Vector2(0.0, 12.0), Vector2.ZERO)
	stage.add_child(_headline)
	headline_label = _headline.get_node("Label") as Label
	subline_label = UiStyle.make_label("", 21, UiStyle.COL_WHITE, true)
	subline_label.name = "Subline"
	subline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(subline_label, Vector2(0.5, 0.0), Vector2(-500.0, 122.0), Vector2(1000.0, 30.0))
	stage.add_child(subline_label)

	var stats_width: float = STAT_SIZE.x * 3.0 + STAT_GAP * 2.0
	var stats_left: float = (STAGE_SIZE.x - stats_width) * 0.5
	wave_value_label = _add_stat(stage, "ERREICHTE WELLE", UiStyle.COL_PINK,
			Vector2(stats_left, STAT_TOP), "Wave")
	kills_value_label = _add_stat(stage, "KILLS", UiStyle.COL_CYAN,
			Vector2(stats_left + STAT_SIZE.x + STAT_GAP, STAT_TOP), "Kills")
	points_value_label = _add_stat(stage, "PUNKTE", UiStyle.COL_YELLOW,
			Vector2(stats_left + (STAT_SIZE.x + STAT_GAP) * 2.0, STAT_TOP), "Points")
	_build_bank(stage)

	var build_left: float = (STAGE_SIZE.x - BUILD_SIZE.x) * 0.5
	var build_plate: Panel = UiStyle.make_plate(UiStyle.COL_PANEL, UiStyle.COL_PURPLE, 4, 0.0, 12)
	build_plate.name = "BuildPlate"
	UiStyle.anchor_box(build_plate, Vector2.ZERO, Vector2(build_left, BUILD_TOP), BUILD_SIZE)
	stage.add_child(build_plate)
	var build_title: Label = UiStyle.make_label("DEIN BUILD", 20, UiStyle.COL_CYAN, true)
	build_title.name = "BuildTitle"
	UiStyle.anchor_box(build_title, Vector2.ZERO, Vector2(build_left + 22.0, BUILD_TOP + 5.0), Vector2(400.0, 30.0))
	stage.add_child(build_title)
	upgrade_list = Control.new()
	upgrade_list.name = "Upgrades"
	upgrade_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(upgrade_list, Vector2.ZERO, Vector2(build_left + 22.0, BUILD_TOP + 38.0),
			Vector2(BUILD_SIZE.x - 44.0, BUILD_SIZE.y - 44.0))
	stage.add_child(upgrade_list)
	empty_label = UiStyle.make_label("Kein einziges Upgrade.\nNächstes Mal die Kisten einsammeln!", 22, UiStyle.COL_WHITE, true)
	empty_label.name = "Empty"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(empty_label, Vector2.ZERO, Vector2(build_left, BUILD_TOP + 38.0), Vector2(BUILD_SIZE.x, BUILD_SIZE.y - 52.0))
	stage.add_child(empty_label)

	# Drei Knöpfe nebeneinander: Neustart, Programm, Beenden.
	var buttons_width: float = BUTTON_SIZE.x * 3.0 + BUTTON_GAP * 2.0
	var buttons_left: float = (STAGE_SIZE.x - buttons_width) * 0.5
	restart_button = _add_button(stage, "NEUSTART", UiStyle.COL_GREEN, "Restart", buttons_left)
	restart_button.pressed.connect(_on_restart_pressed)
	program_button = _add_button(stage, "PROGRAMM", UiStyle.COL_YELLOW, "Program", buttons_left + BUTTON_SIZE.x + BUTTON_GAP)
	program_button.pressed.connect(_on_program_pressed)
	quit_button = _add_button(stage, "BEENDEN", UiStyle.COL_ORANGE, "Quit", buttons_left + (BUTTON_SIZE.x + BUTTON_GAP) * 2.0)
	quit_button.pressed.connect(_on_quit_pressed)
	restart_button.focus_neighbor_right = restart_button.get_path_to(program_button)
	program_button.focus_neighbor_left = program_button.get_path_to(restart_button)
	program_button.focus_neighbor_right = program_button.get_path_to(quit_button)
	quit_button.focus_neighbor_left = quit_button.get_path_to(program_button)
	var hint: Label = UiStyle.make_label(HINT_TEXT, 16, UiStyle.COL_CYAN, true)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(hint, Vector2.ZERO, Vector2(0.0, 652.0), Vector2(STAGE_SIZE.x, 26.0))
	stage.add_child(hint)


func _add_button(stage: Control, text: String, accent: Color, node_name: String, left: float) -> Button:
	var button: Button = UiStyle.make_button(text, accent, 28)
	button.name = node_name
	button.custom_minimum_size = BUTTON_SIZE
	button.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(button, Vector2.ZERO, Vector2(left, BUTTON_TOP), BUTTON_SIZE)
	stage.add_child(button)
	return button


## Streifen unter den Kennzahlen: links die Gutschrift des Laufs, rechts der neue Kontostand.
func _build_bank(stage: Control) -> void:
	_bank_box = Control.new()
	_bank_box.name = "Bank"
	_bank_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bank_box.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(_bank_box, Vector2.ZERO, BANK_RECT.position, BANK_RECT.size)
	stage.add_child(_bank_box)
	var plate: Panel = UiStyle.make_plate(UiStyle.COL_PANEL_SOLID, UiStyle.COL_GREEN, 4, 0.12, 8)
	plate.name = "Plate"
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bank_box.add_child(plate)
	var half: float = BANK_RECT.size.x * 0.5
	var gain_title: Label = UiStyle.make_label("AUFS KONTO", 17, UiStyle.COL_GREEN, true)
	gain_title.name = "GainTitle"
	gain_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(gain_title, Vector2.ZERO, Vector2(34.0, 0.0), Vector2(150.0, BANK_RECT.size.y))
	_bank_box.add_child(gain_title)
	bank_gain_label = UiStyle.make_label("+0", BANK_FONT_SIZE, UiStyle.COL_WHITE, true)
	bank_gain_label.name = "Gain"
	bank_gain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bank_gain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(bank_gain_label, Vector2.ZERO, Vector2(184.0, -2.0), Vector2(half - 214.0, BANK_RECT.size.y))
	_bank_box.add_child(bank_gain_label)
	var divider: ColorRect = ColorRect.new()
	divider.name = "Divider"
	divider.color = Color(UiStyle.COL_GREEN, 0.5)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(divider, Vector2.ZERO, Vector2(half - 1.0, 10.0), Vector2(2.0, BANK_RECT.size.y - 20.0))
	_bank_box.add_child(divider)
	var bank_title: Label = UiStyle.make_label("KONTOSTAND", 17, UiStyle.COL_YELLOW, true)
	bank_title.name = "BankTitle"
	bank_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(bank_title, Vector2.ZERO, Vector2(half + 26.0, 0.0), Vector2(160.0, BANK_RECT.size.y))
	_bank_box.add_child(bank_title)
	bank_label = UiStyle.make_label("0", BANK_FONT_SIZE, UiStyle.COL_YELLOW, true)
	bank_label.name = "Value"
	bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bank_label.pivot_offset_ratio = Vector2(1.0, 0.5)
	UiStyle.anchor_box(bank_label, Vector2.ZERO, Vector2(half + 186.0, -2.0), Vector2(half - 220.0, BANK_RECT.size.y))
	_bank_box.add_child(bank_label)


## Baut eine Kennzahl-Kiste (Titel oben, große Zahl darunter) und gibt das Zahlen-Label zurück.
func _add_stat(stage: Control, title: String, accent: Color, offset: Vector2, node_name: String) -> Label:
	var box: Control = Control.new()
	box.name = "Stat%s" % node_name
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(box, Vector2.ZERO, offset, STAT_SIZE)
	stage.add_child(box)
	var plate: Panel = UiStyle.make_plate(UiStyle.COL_PANEL_SOLID, accent, 5, 0.12, 10)
	plate.name = "Plate"
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(plate)
	var title_label: Label = UiStyle.make_label(title, 17, accent, true)
	title_label.name = "Title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(title_label, Vector2.ZERO, Vector2(0.0, 6.0), Vector2(STAT_SIZE.x, 26.0))
	box.add_child(title_label)
	var value_label: Label = UiStyle.make_label("0", STAT_FONT_SIZE, UiStyle.COL_WHITE, true)
	value_label.name = "Value"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(value_label, Vector2.ZERO, Vector2(0.0, 28.0), Vector2(STAT_SIZE.x, 64.0))
	box.add_child(value_label)
	_stat_boxes.append(box)
	return value_label


## Setzt eine Kennzahl und verkleinert die Schrift, falls die Zahl sonst nicht in die Kiste passt.
func _set_stat(label: Label, text: String) -> void:
	label.text = text
	label.add_theme_font_size_override("font_size",
			UiStyle.fit_font_size(text, STAT_FONT_SIZE, STAT_SIZE.x - 44.0, true, 22))


## Zeigt den Kontostand und verkleinert die Schrift, falls die Zahl sonst nicht passt.
func _set_bank(bank: int) -> void:
	var text: String = UiStyle.format_int(bank)
	bank_label.text = text
	bank_label.add_theme_font_size_override("font_size",
			UiStyle.fit_font_size(text, BANK_FONT_SIZE, bank_label.offset_right - bank_label.offset_left - 8.0, true, 18))


## Die Kameras des Laufs für die Liste, je Kameratyp eine Zeile: { "id", "name" ("2 × Kameradrohne"
## bei mehreren), "level" (beste Rarität) }. cameras: stats["cameras"] (ein Eintrag je Exemplar).
static func camera_rows(cameras: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Dictionary in UiStyle.camera_entries(cameras):
		rows.append({"id": str(entry["id"]), "name": str(entry["text"]), "level": int(entry["level"])})
	return rows


## Füllt die Liste des Builds: erst die Upgrades, dann die Kameras, zuletzt die Synergien.
func _fill_build(upgrades: Array, synergies: Array, cameras: Array = []) -> void:
	for child: Node in upgrade_list.get_children():
		upgrade_list.remove_child(child)
		child.queue_free()
	var entries: Array[Dictionary] = []
	for entry: Variant in upgrades:
		if not entry is Dictionary:
			continue
		var data: Dictionary = entry
		var id: String = String(data.get("id", ""))
		if id.is_empty():
			continue
		entries.append({"id": id, "name": String(data.get("name", UiStyle.entry_name(id))), "level": int(data.get("level", 0))})
	entries.append_array(camera_rows(cameras))
	var total: int = entries.size() + synergies.size()
	var columns: int = 2
	var row_size: Vector2 = ROW_SIZE
	var step: float = ROW_STEP
	if total > NARROW_SLOTS:
		columns = 4
		row_size = COMPACT_ROW_SIZE
		step = COMPACT_ROW_STEP
	elif total > WIDE_SLOTS:
		columns = 3
		row_size = NARROW_ROW_SIZE
	# Mehr Einträge als Plätze: Der letzte Platz nennt, wie viele fehlen. Synergien haben Vorrang.
	var shown_entries: int = entries.size()
	if total > COMPACT_SLOTS:
		shown_entries = maxi(COMPACT_SLOTS - 1 - synergies.size(), 0)
	var index: int = 0
	for n: int in mini(shown_entries, entries.size()):
		var shown: Dictionary = entries[n]
		var row: Control = UiStyle.make_upgrade_row(str(shown["id"]), int(shown["level"]), row_size)
		var name_label: Label = row.get_node("Name") as Label
		name_label.text = str(shown["name"])
		row.position = _slot_position(index, columns, row_size.x, step)
		upgrade_list.add_child(row)
		index += 1
	for synergy: Variant in synergies:
		var synergy_row: Control = UiStyle.make_synergy_row(String(synergy), row_size)
		synergy_row.position = _slot_position(index, columns, row_size.x, step)
		upgrade_list.add_child(synergy_row)
		index += 1
	if shown_entries < entries.size():
		var more: Label = UiStyle.make_label("+%d weitere" % (entries.size() - shown_entries), 16, UiStyle.COL_CYAN, true)
		more.name = "More"
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		more.position = _slot_position(index, columns, row_size.x, step)
		more.size = row_size
		upgrade_list.add_child(more)
	empty_label.visible = index == 0


## Platz Nummer index in der Liste mit so vielen Spalten (zeilenweise gefüllt). Die Spalten
## verteilen sich über die ganze Breite der Liste.
func _slot_position(index: int, columns: int, row_width: float, step: float) -> Vector2:
	var column: int = index % columns
	@warning_ignore("integer_division")
	var line: int = index / columns
	var list_width: float = BUILD_SIZE.x - 44.0
	var gap: float = (list_width - row_width * float(columns)) / float(maxi(columns - 1, 1))
	return Vector2(float(column) * (row_width + gap), float(line) * step)


## Spruch des Moderators zur erreichten Welle.
func _verdict(wave: int) -> String:
	if wave <= 1:
		return "Game Over. Das war kurz: Die Werbung lief länger als Sie."
	if wave <= 4:
		return "Game Over. Die Zombies bedanken sich für die Mahlzeit."
	if wave <= 9:
		return "Game Over. Solide Quote, aber der Sender ruft nicht zurück."
	return "Game Over. Legendär! Das Publikum verlangt eine zweite Staffel."


func _set_buttons_disabled(disabled: bool) -> void:
	restart_button.disabled = disabled
	program_button.disabled = disabled
	quit_button.disabled = disabled


func _animate_open() -> void:
	if not is_inside_tree():
		return
	UiStyle.pop(_headline, 2.2, 0.35)
	for i: int in _stat_boxes.size():
		UiStyle.pop(_stat_boxes[i], 0.5, 0.25 + 0.1 * float(i))
	UiStyle.pop(_bank_box, 0.6, 0.55)


func _on_restart_pressed() -> void:
	request_restart()


func _on_program_pressed() -> void:
	if is_input_locked():
		return
	open_program()


func _on_quit_pressed() -> void:
	if is_input_locked() or is_program_open():
		return
	Game.quit_game()


## Das Konto hat sich geändert, während der Bildschirm offen ist (Kauf im Programm).
func _on_bank_changed(bank: int, _gained: int) -> void:
	if not is_open():
		return
	_set_bank(bank)
	UiStyle.pop(bank_label, 1.2, 0.2)
