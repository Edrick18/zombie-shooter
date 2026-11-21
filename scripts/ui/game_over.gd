extends CanvasLayer
## Modul: Oberfläche (scripts/ui).
## Game-Over-Bildschirm (Abschnitt 11): erreichte Welle, Kills, Punkte, Upgrades mit Stufen.
## Knöpfe: Neustart -> Game.restart_run(), Beenden -> Game.quit_game(). Die Taste R (Aktion
## "reload") startet ebenfalls neu.
##
## Öffnet sich bei Events.game_over(stats). Das Spiel ist dann pausiert (GAME_OVER), deshalb
## process_mode ALWAYS. stats siehe Game.get_stats():
## { "wave": int, "kills": int, "points": int, "upgrades": Array von { "id", "name", "level" },
##   "synergies": Array[String] }.
## Kurz nach dem Öffnen sind Knöpfe und R gesperrt (INPUT_LOCK_SECONDS), damit ein Tastendruck
## aus dem letzten Gefecht nicht sofort neu startet.

const UiStyle := preload("res://scripts/ui/hud.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")

const LAYER: int = 30

# --- Optik- und Bedien-Zahlen ---
const INPUT_LOCK_SECONDS: float = 0.6
const MAX_LOCK_STEP: float = 0.05
const STAGE_SIZE: Vector2 = Vector2(860.0, 690.0)
const STAT_SIZE: Vector2 = Vector2(250.0, 106.0)
const STAT_GAP: float = 24.0
const STAT_FONT_SIZE: int = 50
const BUILD_SIZE: Vector2 = Vector2(820.0, 264.0)
const ROW_SIZE: Vector2 = Vector2(380.0, 48.0)
## Ab mehr als WIDE_SLOTS Einträgen: drei Spalten mit schmalen Zeilen.
const NARROW_ROW_SIZE: Vector2 = Vector2(250.0, 48.0)
const WIDE_SLOTS: int = 8
const ROW_STEP: float = 54.0
const BUTTON_SIZE: Vector2 = Vector2(320.0, 64.0)

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
## Behälter der Upgrade-Zeilen: je Upgrade "Row_<id>" (Kinder "Name", "Level"), je Synergie
## "Synergy_<id>".
var upgrade_list: Control
## Hinweis, wenn der Lauf ohne Upgrade endete.
var empty_label: Label
## Knopf "Neustart" (Game.restart_run).
var restart_button: Button
## Knopf "Beenden" (Game.quit_game).
var quit_button: Button

var _headline: PanelContainer
var _stat_boxes: Array[Control] = []
var _lock_left: float = 0.0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	Events.game_over.connect(show_stats)
	Events.run_started.connect(close)


func _process(delta: float) -> void:
	if not is_open() or _lock_left <= 0.0:
		return
	_lock_left = maxf(_lock_left - minf(delta, MAX_LOCK_STEP), 0.0)
	if _lock_left <= 0.0:
		_set_buttons_disabled(false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("reload"):
		get_viewport().set_input_as_handled()
		request_restart()


## Zeigt den Bildschirm mit dieser Statistik und sperrt die Eingabe kurz.
func show_stats(run_stats: Dictionary) -> void:
	stats = run_stats
	var wave: int = int(run_stats.get("wave", 0))
	_set_stat(wave_value_label, str(wave))
	_set_stat(kills_value_label, UiStyle.format_int(int(run_stats.get("kills", 0))))
	_set_stat(points_value_label, UiStyle.format_int(int(run_stats.get("points", 0))))
	subline_label.text = _verdict(wave)
	var upgrades: Array = []
	var upgrades_value: Variant = run_stats.get("upgrades", [])
	if upgrades_value is Array:
		upgrades = upgrades_value
	var synergies: Array = []
	var synergies_value: Variant = run_stats.get("synergies", [])
	if synergies_value is Array:
		synergies = synergies_value
	_fill_build(upgrades, synergies)
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


## Neustart über Knopf oder Taste R. Wirkt nur bei offenem Bildschirm und nach der Sperre.
## Gibt true zurück, wenn neu gestartet wurde.
func request_restart() -> bool:
	if not is_open() or is_input_locked():
		return false
	Game.restart_run()
	return true


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
			Vector2(stats_left, 166.0), "Wave")
	kills_value_label = _add_stat(stage, "KILLS", UiStyle.COL_CYAN,
			Vector2(stats_left + STAT_SIZE.x + STAT_GAP, 166.0), "Kills")
	points_value_label = _add_stat(stage, "PUNKTE", UiStyle.COL_YELLOW,
			Vector2(stats_left + (STAT_SIZE.x + STAT_GAP) * 2.0, 166.0), "Points")

	var build_left: float = (STAGE_SIZE.x - BUILD_SIZE.x) * 0.5
	var build_plate: Panel = UiStyle.make_plate(UiStyle.COL_PANEL, UiStyle.COL_PURPLE, 4, 0.0, 12)
	build_plate.name = "BuildPlate"
	UiStyle.anchor_box(build_plate, Vector2.ZERO, Vector2(build_left, 292.0), BUILD_SIZE)
	stage.add_child(build_plate)
	var build_title: Label = UiStyle.make_label("DEIN BUILD", 20, UiStyle.COL_CYAN, true)
	build_title.name = "BuildTitle"
	UiStyle.anchor_box(build_title, Vector2.ZERO, Vector2(build_left + 22.0, 300.0), Vector2(400.0, 30.0))
	stage.add_child(build_title)
	upgrade_list = Control.new()
	upgrade_list.name = "Upgrades"
	upgrade_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(upgrade_list, Vector2.ZERO, Vector2(build_left + 22.0, 336.0),
			Vector2(BUILD_SIZE.x - 44.0, BUILD_SIZE.y - 52.0))
	stage.add_child(upgrade_list)
	empty_label = UiStyle.make_label("Kein einziges Upgrade.\nNächstes Mal die Kisten einsammeln!", 22, UiStyle.COL_WHITE, true)
	empty_label.name = "Empty"
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(empty_label, Vector2.ZERO, Vector2(build_left, 336.0), Vector2(BUILD_SIZE.x, BUILD_SIZE.y - 60.0))
	stage.add_child(empty_label)

	var buttons_left: float = STAGE_SIZE.x * 0.5 - BUTTON_SIZE.x - 14.0
	restart_button = UiStyle.make_button("NEUSTART", UiStyle.COL_GREEN, 30)
	restart_button.name = "Restart"
	restart_button.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(restart_button, Vector2.ZERO, Vector2(buttons_left, 576.0), BUTTON_SIZE)
	restart_button.pressed.connect(_on_restart_pressed)
	stage.add_child(restart_button)
	quit_button = UiStyle.make_button("BEENDEN", UiStyle.COL_ORANGE, 30)
	quit_button.name = "Quit"
	quit_button.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(quit_button, Vector2.ZERO, Vector2(STAGE_SIZE.x * 0.5 + 14.0, 576.0), BUTTON_SIZE)
	quit_button.pressed.connect(_on_quit_pressed)
	stage.add_child(quit_button)
	restart_button.focus_neighbor_right = restart_button.get_path_to(quit_button)
	quit_button.focus_neighbor_left = quit_button.get_path_to(restart_button)
	var hint: Label = UiStyle.make_label("Taste R: sofort neu starten", 16, UiStyle.COL_CYAN, true)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(hint, Vector2.ZERO, Vector2(0.0, 652.0), Vector2(STAGE_SIZE.x, 26.0))
	stage.add_child(hint)


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
	UiStyle.anchor_box(title_label, Vector2.ZERO, Vector2(0.0, 8.0), Vector2(STAT_SIZE.x, 26.0))
	box.add_child(title_label)
	var value_label: Label = UiStyle.make_label("0", STAT_FONT_SIZE, UiStyle.COL_WHITE, true)
	value_label.name = "Value"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(value_label, Vector2.ZERO, Vector2(0.0, 30.0), Vector2(STAT_SIZE.x, 70.0))
	box.add_child(value_label)
	_stat_boxes.append(box)
	return value_label


## Setzt eine Kennzahl und verkleinert die Schrift, falls die Zahl sonst nicht in die Kiste passt.
func _set_stat(label: Label, text: String) -> void:
	label.text = text
	label.add_theme_font_size_override("font_size",
			UiStyle.fit_font_size(text, STAT_FONT_SIZE, STAT_SIZE.x - 44.0, true, 22))


## Füllt die Liste der Upgrades (zwei Spalten) und darunter die Synergien.
func _fill_build(upgrades: Array, synergies: Array) -> void:
	for child: Node in upgrade_list.get_children():
		upgrade_list.remove_child(child)
		child.queue_free()
	# Bis 8 Einträge zwei breite Spalten. Mit dem Rucksack sind bis zu 10 Upgrades und eine
	# Verbindung möglich: Dann werden es drei schmale Spalten.
	var columns: int = 2 if upgrades.size() + synergies.size() <= WIDE_SLOTS else 3
	var row_size: Vector2 = ROW_SIZE if columns == 2 else NARROW_ROW_SIZE
	var index: int = 0
	for entry: Variant in upgrades:
		if not entry is Dictionary:
			continue
		var data: Dictionary = entry
		var id: String = String(data.get("id", ""))
		if id.is_empty():
			continue
		var row: Control = UiStyle.make_upgrade_row(id, int(data.get("level", 0)), row_size)
		var name_label: Label = row.get_node("Name") as Label
		name_label.text = String(data.get("name", UpgradeDefs.display_name(id)))
		row.position = _slot_position(index, columns)
		upgrade_list.add_child(row)
		index += 1
	for synergy: Variant in synergies:
		var synergy_row: Control = UiStyle.make_synergy_row(String(synergy), row_size)
		synergy_row.position = _slot_position(index, columns)
		upgrade_list.add_child(synergy_row)
		index += 1
	empty_label.visible = index == 0


## Platz Nummer index in der Liste mit so vielen Spalten (zeilenweise gefüllt).
func _slot_position(index: int, columns: int = 2) -> Vector2:
	var column: int = index % columns
	@warning_ignore("integer_division")
	var line: int = index / columns
	var width: float = ROW_SIZE.x if columns == 2 else NARROW_ROW_SIZE.x
	var gap: float = 16.0 if columns == 2 else 13.0
	return Vector2(float(column) * (width + gap), float(line) * ROW_STEP)


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
	quit_button.disabled = disabled


func _animate_open() -> void:
	if not is_inside_tree():
		return
	UiStyle.pop(_headline, 2.2, 0.35)
	for i: int in _stat_boxes.size():
		UiStyle.pop(_stat_boxes[i], 0.5, 0.25 + 0.1 * float(i))


func _on_restart_pressed() -> void:
	request_restart()


func _on_quit_pressed() -> void:
	if is_input_locked():
		return
	Game.quit_game()
