extends SceneTree
## Tests für den Rucksack-Bildschirm (scripts/ui/backpack_screen.gd): Öffnen und Schließen,
## Greifen, Drehen, Einräumen, Zusammenlegen (im Raster und im Regal), Rucksack-Teile, Ablage
## ohne Grenze (das Regal rollt), Material, kaputte Gegenstände, Reparieren, Verschrotten und
## Verkaufen über die drei Felder und über Tasten, Bilder auf den Gegenständen, Namen ein und aus,
## Tasten und Maus, dazu Sterne (star_marks), Hände und Waffen im Raster. Außerdem die Anordnung:
## Regal links, Rucksack in der Mitte, nur vorhandene Felder, Karte am Gegenstand mit
## Wertebalken, Hilfe-Tafel.
## Der Bildschirm wird über seine öffentlichen Funktionen bedient.
##
## Der Rucksack ohne Kandidat hat die Felder x 1 bis 4, y 1 bis 3. Die Tests zu Sternen nutzen:
## Dienstpistole auf (2, 2) belegt (2, 2) und (3, 2). Spezialmunition auf (2, 3) hat ihre Sterne
## auf (2, 2) und (3, 2), Starkstrom-Sponsor auf (1, 2) hat Sterne auf (0, 2) und (2, 2),
## Scheinwerfer auf (2, 1) hat Sterne auf (2, 2) und (3, 2).

const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")

const SCREEN_SCRIPT: String = "res://scripts/ui/backpack_screen.gd"
const STATE_PLAYING: int = 1
const STATE_CHOOSING: int = 2
const STATE_PACKING: int = 5
const NO_CELL: Vector2i = Vector2i(-1, -1)

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
var _screen: CanvasLayer
var _build_changes: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum.
	await process_frame
	_game = root.get_node("Game")
	_events = root.get_node("Events")
	_events.connect("build_changed", func() -> void: _build_changes += 1)
	_game.set("character_id", "")
	_game.set("auto_pack", false)
	var script: GDScript = load(SCREEN_SCRIPT) as GDScript
	_check(script != null, "backpack_screen.gd lädt.")
	if script != null:
		_screen = script.new() as CanvasLayer
		root.add_child(_screen)
		await process_frame
		_test_basics(script)
		_test_cells()
		_test_open_and_pick_up()
		_test_failed_drops()
		_test_move_and_merge()
		_test_bag()
		_test_store_and_sell()
		_test_close()
		_test_keys()
		_test_chest()
		_test_mouse()
		_test_info_texts()
		_test_layout()
		_test_shelf()
		_test_shelf_scroll()
		_test_shelf_merge()
		_test_materials()
		_test_broken()
		_test_broken_loot()
		_test_repair()
		_test_scrap()
		await _test_icons()
		await _test_redraw_only_on_change()
		await _test_name_toggle()
		_test_card()
		_test_bars()
		_test_help()
		await _test_stars()
		_test_held_weapon_stars()
		_test_hands()
		_test_weapon_merge_and_sell()
		await _test_cameras()
		_test_names(script)
		_test_hide_signals()
		await process_frame
		_screen.queue_free()
		await process_frame
	paused = false
	_game.set("character_id", "")
	_game.set("auto_pack", false)
	_game.set("broken_loot", false)
	# Gemerkte Schriften freigeben, damit beim Beenden nichts als Leck gemeldet wird.
	(load("res://scripts/ui/hud.gd") as GDScript).call("clear_font_cache")
	await process_frame
	await process_frame
	if _failures == 0:
		print("Alle %d Prüfungen für den Rucksack-Bildschirm bestanden." % _checks)
	else:
		printerr("%d von %d Prüfungen für den Rucksack-Bildschirm fehlgeschlagen." % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


# --- Helfer ---------------------------------------------------------------------------

func _pack() -> BackpackState:
	return _game.get("backpack") as BackpackState


func _state() -> int:
	return int(_game.get("state"))


func _level(upgrade_id: String) -> int:
	var levels: Dictionary = (_game.get("upgrades") as RefCounted).call("levels")
	# Kameras sind seit Abschnitt 22 keine Upgrades mehr: Ihre Rarität steht in Game.camera_levels().
	var cameras: Dictionary = _game.call("camera_levels")
	return maxi(int(levels.get(upgrade_id, 0)), int(cameras.get(upgrade_id, 0)))


func _is_open() -> bool:
	return bool(_screen.call("is_open"))


func _held() -> int:
	return int(_screen.call("held_uid"))


## Neuer Lauf mit leerem Standard-Rucksack, Rucksack-Bildschirm offen.
func _fresh_open(seed_value: int) -> void:
	_game.call("start_run", seed_value)
	_game.call("open_backpack")


## Greift einen Gegenstand und legt ihn mit der Drehung rot auf pos.
func _put(uid: int, pos: Vector2i, rot: int = 0) -> bool:
	if not bool(_screen.call("pick_up", uid)):
		return false
	var turns: int = posmod(rot - int(_screen.call("held_rotation")), 4)
	for _i: int in turns:
		_screen.call("rotate_held")
	return bool(_screen.call("drop_on_cell", pos))


func _action(action_name: String) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action_name
	event.pressed = true
	return event


func _mouse_button(index: MouseButton, pressed: bool, at: Vector2, double_click: bool = false) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = at
	event.double_click = double_click
	return event


func _mouse_motion(at: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	return event


func _cell_center(cell: Vector2i) -> Vector2:
	return (_screen.call("cell_rect", cell) as Rect2).get_center()


func _marks() -> Array[Dictionary]:
	var marks: Array[Dictionary] = _screen.call("star_marks")
	return marks


## Sterne eines Gegenstands (owner) aus star_marks, auf Wunsch nur die der Vorschau.
func _marks_of(owner_uid: int, preview_only: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mark: Dictionary in _marks():
		if int(mark["owner"]) == owner_uid and (bool(mark.get("preview", false)) or not preview_only):
			result.append(mark)
	return result


## Der Stern von owner auf cell, leer wenn es ihn nicht gibt.
func _mark(owner_uid: int, cell: Vector2i) -> Dictionary:
	for mark: Dictionary in _marks_of(owner_uid):
		if (mark["cell"] as Vector2i) == cell:
			return mark
	return {}


func _is_lit(owner_uid: int, cell: Vector2i) -> bool:
	return bool(_mark(owner_uid, cell).get("lit", false))


func _mark_cells(marks: Array[Dictionary]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for mark: Dictionary in marks:
		cells.append(mark["cell"] as Vector2i)
	return cells


func _warning() -> Label:
	return _screen.get("warning_label") as Label


## Die ganze Zeichenfläche des Bildschirms in ihren eigenen Koordinaten.
func _board_rect() -> Rect2:
	return Rect2(Vector2.ZERO, (_screen.get("board") as Control).size)


## Fläche eines Elements in den Koordinaten der Bühne, ohne die Vergrößerung beim Aufploppen.
func _box(control: Control) -> Rect2:
	return Rect2(control.offset_left, control.offset_top, control.offset_right - control.offset_left, control.offset_bottom - control.offset_top)


## Setzt den Zeiger weit neben alles.
func _pointer_away() -> void:
	_screen.call("set_pointer", Vector2(-40.0, -40.0))


## Macht den Rucksack zum vollen Raster (7 mal 5 Felder) und leert ihn.
func _full_raster() -> void:
	var cells: Array[Vector2i] = []
	for y: int in BackpackState.ROWS:
		for x: int in BackpackState.COLS:
			cells.append(Vector2i(x, y))
	_pack().setup(cells)
	_game.call("sync_build")


## Taste gedrückt (nach Beschriftung).
func _key(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


## Drückt eine Taste am Bildschirm.
func _press(keycode: Key) -> void:
	_screen.call("_unhandled_input", _key(keycode))


func _materials() -> int:
	return int(_game.get("materials"))


func _constant(constant_name: String) -> Variant:
	return (_screen.get_script() as GDScript).get_script_constant_map().get(constant_name)


func _layout() -> Array[Dictionary]:
	var layout: Array[Dictionary] = _screen.call("shelf_layout")
	return layout


## Mitte der Zeile eines Gegenstands im Regal (nach dem Rollen dorthin).
func _row_center(uid: int) -> Vector2:
	_screen.call("scroll_to_item", uid)
	return (_screen.call("item_rect", uid) as Rect2).get_center()


## Steht alles aus describe(uid) auf der Karte (Name, Zeile darunter, "Kaputt", Wirkung, jede
## Zusatzzeile, Verkaufswert, Ertrag beim Verschrotten) und dazu die Schlagworte?
func _card_has_all(uid: int) -> bool:
	if int(_screen.call("card_uid")) != uid:
		return false
	var text: String = _screen.call("card_text")
	var info: Dictionary = _screen.call("describe", uid)
	for key: String in ["name", "subtitle", "broken", "text", "sell", "scrap"]:
		if not str(info[key]).is_empty() and not text.contains(str(info[key])):
			return false
	for line: String in str(info["extra"]).split("\n", false):
		if not text.contains(line):
			return false
	var tags: String = ItemDefs.tags_text(str(_pack().item(uid)["id"]))
	return tags.is_empty() or text.contains("Schlagworte: " + tags)


## Liegen alle sichtbaren Zeilen der Karte in der Karte und untereinander (keine überdeckt eine andere)?
func _card_parts_fit() -> bool:
	var card: Control = _screen.get("card") as Control
	var inside: Rect2 = Rect2(Vector2.ZERO, card.size)
	var bottom: float = 0.0
	for child: Node in card.get_children():
		var part: Control = child as Control
		if part == null or not part.visible or part.name == "Plate":
			continue
		if not inside.encloses(Rect2(part.position, part.size)) or part.position.y < bottom - 0.5:
			return false
		var label: Label = part as Label
		if label != null and label.get_minimum_size().y > part.size.y + 0.5:
			return false
		bottom = part.position.y + part.size.y
	return true


func _hands_title() -> String:
	return (_screen.get("hands_label") as Label).text


func _hand_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = _screen.call("hand_slots")
	return slots


func _loadout() -> Array[Dictionary]:
	var weapons: Array[Dictionary] = _game.get("loadout")
	return weapons


# --- Tests ----------------------------------------------------------------------------

func _test_basics(script: GDScript) -> void:
	_check(not _is_open(), "Der Bildschirm ist anfangs zu.")
	_check(_screen.layer == 15, "Der Bildschirm liegt auf Ebene 15, war %d." % _screen.layer)
	_check(int(script.get_script_constant_map().get("LAYER", -1)) == 15, "Die Konstante LAYER ist 15.")
	_check(_screen.process_mode == Node.PROCESS_MODE_ALWAYS, "Der Bildschirm läuft auch bei pausiertem Baum.")
	_check(_held() == -1, "Anfangs wird nichts gehalten.")
	_check(not bool(_screen.call("request_close")), "Schließen ohne offenen Rucksack meldet false.")
	_check(_screen.get("done_button") is Button and _screen.get("warning_label") is Label, "Knopf FERTIG und Warnung gibt es.")
	_check(str((_screen.get("hint_label") as Label).text).contains("Drehen: R oder Rechtsklick"), "Die Hinweiszeile nennt das Drehen.")
	_check(str((_screen.get("hint_label") as Label).text).contains("Sterne"), "Die Hinweiszeile nennt die Sterne.")
	_check(str((_screen.get("hint_label") as Label).text).contains("Ablage") and str((_screen.get("hint_label") as Label).text).contains("kombinieren"),
		"Die Hinweiszeile sagt, dass man auch in der Ablage kombinieren kann.")
	_check(str((_screen.get("hint_label") as Label).text).contains("F1"), "Die Hinweiszeile nennt die Taste für die Hilfe.")
	var hint: Label = _screen.get("hint_label") as Label
	_check(hint.text.contains("Fundstücke sind kaputt") and hint.text.contains("Reparieren kostet Material"), "Die Hinweiszeile sagt, dass Fundstücke kaputt sind und Reparieren Material kostet.")
	_check(hint.text.contains("Verschrotten gibt Material") and hint.text.contains("Verkaufen gibt Punkte"), "Die Hinweiszeile sagt, was Verschrotten und Verkaufen geben.")
	_check(hint.text.contains("geschaffte Welle"), "Die Hinweiszeile sagt, dass es Material auch für Wellen gibt.")
	_check(hint.text.contains("Taste F") and hint.text.contains("zweimal X") and hint.text.contains("N: Namen"), "Die Hinweiszeile nennt die Tasten F, X und N.")
	var hint_height: float = (_constant("HINT_RECT") as Rect2).size.y
	_check(hint.get_minimum_size().y <= hint_height + 0.5 and _box(hint).size.y <= hint_height + 0.5 and hint.get_theme_font_size("font_size") >= 12,
		"Die ganze Hinweiszeile passt lesbar in die untere Leiste (%d von %d)." % [roundi(hint.get_minimum_size().y), roundi(hint_height)])
	_check(_screen.get("material_label") is Label, "Die Anzeige für Material gibt es.")
	_check(_screen.get("repair_title_label") is Label and _screen.get("repair_value_label") is Label and _screen.get("scrap_title_label") is Label
		and _screen.get("scrap_value_label") is Label and _screen.get("sell_title_label") is Label and _screen.get("sell_value_label") is Label,
		"Die drei Felder haben je Titel und Zeile.")
	_check((_screen.get("repair_title_label") as Label).text == "REPARIEREN" and (_screen.get("scrap_title_label") as Label).text == "VERSCHROTTEN"
		and (_screen.get("sell_title_label") as Label).text == "VERKAUFEN", "Die drei Felder heißen REPARIEREN, VERSCHROTTEN und VERKAUFEN.")
	_check(not _screen.has_method("overflow_text"), "Die Warnung zur vollen Ablage gibt es nicht mehr.")
	_check(not bool(_screen.call("names_shown")), "Anfangs sind die Namen im Raster ausgeblendet.")
	_check(_screen.get("hands_label") is Label, "Die Anzeige der Hände gibt es.")
	_check(_screen.get("card") is Control and _screen.get("help_panel") is Control and _screen.get("help_button") is Button,
		"Karte, Hilfe-Tafel und Knopf für die Hilfe gibt es.")
	_check(not bool(_screen.call("is_card_open")) and not bool(_screen.call("is_help_open")), "Anfangs sind Karte und Hilfe nicht zu sehen.")


func _test_cells() -> void:
	var all_ok: bool = true
	for y: int in BackpackState.ROWS:
		for x: int in BackpackState.COLS:
			var cell: Vector2i = Vector2i(x, y)
			var rect: Rect2 = _screen.call("cell_rect", cell)
			if (_screen.call("cell_at", rect.get_center()) as Vector2i) != cell:
				all_ok = false
			if (_screen.call("cell_at", rect.position + Vector2(1.0, 1.0)) as Vector2i) != cell:
				all_ok = false
	_check(all_ok, "cell_at findet für jedes Feld des Rasters die Mitte und die Ecke von cell_rect.")
	var first: Rect2 = _screen.call("cell_rect", Vector2i(0, 0))
	var last: Rect2 = _screen.call("cell_rect", Vector2i(BackpackState.COLS - 1, BackpackState.ROWS - 1))
	_check((_screen.call("cell_at", first.position - Vector2(3.0, 3.0)) as Vector2i) == NO_CELL, "Links oben neben dem Raster liegt kein Feld.")
	_check((_screen.call("cell_at", last.end + Vector2(3.0, 3.0)) as Vector2i) == NO_CELL, "Rechts unten neben dem Raster liegt kein Feld.")
	_check(first.size.x >= 56.0 and is_equal_approx(first.size.x, first.size.y), "Die Felder sind quadratisch und groß genug.")


func _test_open_and_pick_up() -> void:
	_game.call("start_run", 11)
	_check(not _is_open(), "Nach start_run ist der Bildschirm zu.")
	_game.call("open_backpack")
	_check(_is_open(), "Game.open_backpack öffnet den Bildschirm.")
	_check(bool(_screen.call("is_help_open")), "Beim ersten Öffnen in einem Programmlauf steht die Hilfe von selbst da.")
	_check(not bool(_screen.call("is_card_open")), "Ohne Gegenstand unter dem Zeiger gibt es keine Karte.")
	_check(_state() == STATE_PACKING and paused, "Bei offenem Rucksack ist der State PACKING und der Baum pausiert.")
	var pack: BackpackState = _pack()
	var cells: Array[Vector2i] = pack.cells()
	_check(cells.size() == 12, "Ohne Kandidat hat der Rucksack 12 Felder, waren %d." % cells.size())
	_check(not bool(_screen.call("pick_up", 999)), "Einen unbekannten Gegenstand kann man nicht greifen.")
	var uid: int = pack.add_item("drone", 1)
	_check(bool(_screen.call("pick_up", uid)), "Ein Gegenstand aus der Ablage lässt sich greifen.")
	_check(_held() == uid and int(_screen.call("held_rotation")) == 0, "Gehalten wird der gegriffene Gegenstand ohne Drehung.")
	_check(not pack.is_placed(uid) and pack.storage_items().size() == 1, "Beim Halten bleibt der Rucksack unverändert.")
	_screen.call("rotate_held")
	_check(int(_screen.call("held_rotation")) == 1, "rotate_held dreht um eine Vierteldrehung.")
	for _i: int in 4:
		_screen.call("rotate_held")
	_check(int(_screen.call("held_rotation")) == 1, "Vier Drehungen ergeben wieder dieselbe Drehung.")
	var before: int = _build_changes
	_check(_level("drone") == 0, "Vor dem Einräumen wirkt die Kameradrohne nicht.")
	_check(bool(_screen.call("drop_on_cell", cells[0])), "Der gedrehte Gegenstand passt auf das erste Feld.")
	_check(_held() == -1, "Nach dem Ablegen wird nichts mehr gehalten.")
	_check(pack.is_placed(uid) and int(pack.item(uid)["rot"]) == 1 and (pack.item(uid)["pos"] as Vector2i) == cells[0],
		"Der Gegenstand liegt mit der gewählten Drehung auf dem Feld.")
	_check(pack.cells_of(uid).has(cells[0] + Vector2i(0, 1)), "Gedreht belegt die Kameradrohne zwei Felder untereinander.")
	_check(_level("drone") == 1, "Nach dem Ablegen steht die Stufe in Game.upgrades.")
	_check(_build_changes == before + 1, "Das Ablegen gleicht den Build genau einmal ab.")
	_check(not bool(_screen.call("drop_on_cell", cells[1])), "Ohne gehaltenen Gegenstand meldet drop_on_cell false.")
	# cancel_hold lässt alles, wie es war.
	_screen.call("pick_up", uid)
	_screen.call("rotate_held")
	_screen.call("cancel_hold")
	_check(_held() == -1 and int(pack.item(uid)["rot"]) == 1 and (pack.item(uid)["pos"] as Vector2i) == cells[0],
		"cancel_hold legt den Gegenstand unverändert zurück.")


func _test_failed_drops() -> void:
	_fresh_open(12)
	var pack: BackpackState = _pack()
	var cells: Array[Vector2i] = pack.cells()
	var outside: Vector2i = Vector2i(0, 0)
	_check(not pack.has_cell(outside), "Das Feld (0, 0) gehört nicht zum Start-Rucksack.")
	# Aus der Ablage auf ein Feld, das es nicht gibt.
	var burn: int = pack.add_item("burn", 1)
	_screen.call("pick_up", burn)
	_screen.call("rotate_held")
	var before: int = _build_changes
	_check(not bool(_screen.call("drop_on_cell", outside)), "Außerhalb des Rucksacks passt nichts.")
	_check(_held() == -1 and pack.has_item(burn) and not pack.is_placed(burn), "Der Gegenstand liegt wieder in der Ablage.")
	_check(_build_changes == before, "Ein misslungenes Ablegen gleicht den Build nicht ab.")
	# Von einem Platz im Raster: alter Platz und alte Drehung bleiben.
	var drone: int = pack.add_item("drone", 2)
	_check(_put(drone, cells[0], 1), "Die Kameradrohne liegt gedreht im Raster.")
	_screen.call("pick_up", drone)
	_screen.call("rotate_held")
	_check(int(_screen.call("held_rotation")) == 2, "Ein eingeräumter Gegenstand startet mit seiner Drehung.")
	_check(not bool(_screen.call("drop_on_cell", outside)), "Auch aus dem Raster passt er nicht nach außen.")
	var entry: Dictionary = pack.item(drone)
	_check(bool(entry["placed"]) and (entry["pos"] as Vector2i) == cells[0] and int(entry["rot"]) == 1,
		"Nach dem misslungenen Ablegen liegt er am alten Platz mit der alten Drehung.")
	_check(_level("drone") == 2, "Die Stufe wirkt weiter.")
	_check(not _warning().visible, "Ein misslungenes Ablegen ohne Waffe zeigt keine Warnung.")
	# Auf ein belegtes Feld (anderer Gegenstand): passt nicht.
	_screen.call("pick_up", burn)
	_check(not bool(_screen.call("drop_on_cell", cells[0])), "Auf einem belegten Feld passt nichts.")
	_check(not pack.is_placed(burn) and pack.occupant(cells[0]) == drone, "Der belegte Platz bleibt, wie er war.")


func _test_move_and_merge() -> void:
	_fresh_open(13)
	var pack: BackpackState = _pack()
	var cells: Array[Vector2i] = pack.cells()
	var first: int = pack.add_item("drone", 1)
	_check(_put(first, cells[0], 0), "Die erste Kameradrohne liegt im Raster.")
	# Verschieben im Raster.
	var target: Vector2i = cells[0] + Vector2i(0, 1)
	_check(_put(first, target, 0), "Ein eingeräumter Gegenstand lässt sich verschieben.")
	_check((pack.item(first)["pos"] as Vector2i) == target and pack.occupant(cells[0]) == -1, "Er liegt am neuen Platz, der alte ist frei.")
	# Um ein Feld verschieben: Die eigenen Felder zählen als frei.
	_check(_put(first, target + Vector2i(1, 0), 0), "Verschieben um ein Feld über die eigenen Felder klappt.")
	# Kombinieren aus der Ablage: gleicher Gegenstand, gleiche Rarität.
	var second: int = pack.add_item("drone", 1)
	_screen.call("pick_up", second)
	_check(bool(_screen.call("drop_on_cell", target + Vector2i(2, 0))), "Gleiches auf Gleiches in gleicher Rarität lässt sich ablegen.")
	_check(not pack.has_item(second) and int(pack.item(first)["level"]) == 2, "Zwei Gewöhnliche werden ein Ungewöhnlicher, ein Gegenstand bleibt.")
	_check(pack.placed_items().size() == 1 and pack.storage_items().is_empty(), "Im Rucksack liegt genau ein Gegenstand.")
	_check(_level("drone") == 2, "Game.upgrades zeigt die neue Rarität.")
	# Andere Rarität: kein Kombinieren, der Platz ist belegt, der Gegenstand geht zurück.
	var common: int = pack.add_item("drone", 1)
	_screen.call("pick_up", common)
	_check(not bool(_screen.call("drop_on_cell", target + Vector2i(1, 0))), "Gewöhnlich auf Ungewöhnlich lässt sich nicht kombinieren.")
	_check(pack.has_item(common) and not pack.is_placed(common) and int(pack.item(first)["level"]) == 2, "Der Gegenstand bleibt in der Ablage, nichts ändert sich.")
	_check(int(_game.call("sell_item", common)) == ItemDefs.sell_value("drone", 1), "Der überzählige Gegenstand lässt sich verkaufen.")
	# Die Form bedeckt das Ziel nur mit ihrem zweiten Feld: Auch das kombiniert.
	var third: int = pack.add_item("drone", 2)
	_screen.call("pick_up", third)
	_check(bool(_screen.call("drop_on_cell", target)), "Kombinieren klappt, wenn irgendein bedecktes Feld das Ziel trifft.")
	_check(not pack.has_item(third) and int(pack.item(first)["level"]) == 3, "Zwei Ungewöhnliche werden ein Seltener.")
	# Zwei eingeräumte Gegenstände kombinieren. Getrennt wirken beide, die Übersicht nennt die
	# beste Rarität.
	var fourth: int = pack.add_item("drone", 3)
	_check(_put(fourth, cells[0], 0), "Eine zweite Kameradrohne liegt getrennt im Raster.")
	_check(_level("drone") == 3, "Getrennt liegende gleiche Gegenstände heben die Rarität nicht.")
	_screen.call("pick_up", fourth)
	_check(bool(_screen.call("drop_on_cell", target + Vector2i(1, 0))), "Auch ein eingeräumter Gegenstand lässt sich auf einen gleichen legen.")
	_check(not pack.has_item(fourth) and int(pack.item(first)["level"]) == 4, "Danach ist der eine Gegenstand Episch.")
	_check(_level("drone") == 4, "Game.upgrades zeigt Episch.")
	# Legendär lässt sich nicht weiter kombinieren.
	var fifth: int = pack.add_item("drone", 4)
	_screen.call("pick_up", fifth)
	_check(bool(_screen.call("drop_on_cell", target + Vector2i(1, 0))) and int(pack.item(first)["level"]) == 5, "Zwei Epische werden Legendär.")
	var sixth: int = pack.add_item("drone", 5)
	_screen.call("pick_up", sixth)
	_check(not bool(_screen.call("drop_on_cell", target + Vector2i(1, 0))), "Zwei Legendäre lassen sich nicht kombinieren.")
	_check(pack.has_item(sixth) and not pack.is_placed(sixth), "Der Gegenstand bleibt in der Ablage.")


func _test_bag() -> void:
	_fresh_open(14)
	var pack: BackpackState = _pack()
	var cell_count: int = pack.cell_count()
	var bag: int = pack.add_item("bag_small", 1)
	var spot: Dictionary = pack.find_spot(bag)
	_check(not spot.is_empty(), "Für den Jutebeutel gibt es eine Stelle am Rand.")
	if spot.is_empty():
		return
	# Mitten im Rucksack passt ein Rucksack-Teil nicht.
	_screen.call("pick_up", bag)
	_check(not bool(_screen.call("drop_on_cell", pack.cells()[0])), "Auf vorhandenen Feldern passt ein Rucksack-Teil nicht.")
	_check(pack.has_item(bag) and pack.cell_count() == cell_count, "Der Rucksack ist unverändert.")
	var pos: Vector2i = spot["pos"]
	var covered: Array[Vector2i] = BackpackState.shape_at("bag_small", pos, int(spot["rot"]))
	_check(_put(bag, pos, int(spot["rot"])), "Am Rand lässt sich der Jutebeutel einräumen.")
	_check(pack.cell_count() == cell_count + 2, "Der Rucksack hat zwei Felder mehr, waren %d." % pack.cell_count())
	_check(not pack.has_item(bag), "Das Rucksack-Teil ist verbraucht.")
	_check(pack.has_cell(covered[0]) and pack.has_cell(covered[1]), "Die neuen Felder liegen dort, wo das Teil lag.")
	# Auf den neuen Feldern liegt jetzt ein Gegenstand.
	var luck: int = pack.add_item("luck", 1)
	_check(_put(luck, covered[0], 0), "Auf einem neuen Feld lässt sich etwas einräumen.")


func _test_store_and_sell() -> void:
	_fresh_open(15)
	var pack: BackpackState = _pack()
	var cells: Array[Vector2i] = pack.cells()
	var drone: int = pack.add_item("drone", 3)
	_check(_put(drone, cells[0], 0) and _level("drone") == 3, "Die Kameradrohne wirkt mit Stufe 3.")
	_check(not bool(_screen.call("drop_on_storage")), "Ohne gehaltenen Gegenstand meldet drop_on_storage false.")
	_screen.call("pick_up", drone)
	var before: int = _build_changes
	_check(bool(_screen.call("drop_on_storage")), "Ein eingeräumter Gegenstand lässt sich in die Ablage legen.")
	_check(pack.has_item(drone) and not pack.is_placed(drone), "Er liegt in der Ablage.")
	_check(_level("drone") == 0 and _build_changes == before + 1, "In der Ablage wirkt er nicht mehr.")
	_check(_held() == -1, "Nach dem Ablegen in die Ablage wird nichts gehalten.")
	# Aus der Ablage in die Ablage: bleibt dort.
	_screen.call("pick_up", drone)
	_check(bool(_screen.call("drop_on_storage")) and not pack.is_placed(drone), "Aus der Ablage in die Ablage ändert nichts.")
	# Verkaufen aus der Ablage.
	var points: int = int(_game.get("points"))
	_check(not bool(_screen.call("drop_on_sell")), "Ohne gehaltenen Gegenstand meldet drop_on_sell false.")
	_screen.call("pick_up", drone)
	_check(str((_screen.get("sell_value_label") as Label).text).contains(str(ItemDefs.sell_value("drone", 3))),
		"Das Verkaufsfeld zeigt den Wert des gehaltenen Gegenstands.")
	_check(bool(_screen.call("drop_on_sell")), "Der Gegenstand lässt sich verkaufen.")
	_check(not pack.has_item(drone) and _held() == -1, "Der verkaufte Gegenstand ist weg.")
	_check(int(_game.get("points")) == points + ItemDefs.sell_value("drone", 3), "Es gibt genau den Verkaufswert in Punkten.")
	# Verkaufen aus dem Raster: Die Wirkung endet.
	var piggy: int = pack.add_item("piggy_bank", 1)
	_check(_put(piggy, cells[1], 0), "Das Sparschwein liegt im Raster.")
	points = int(_game.get("points"))
	_screen.call("pick_up", piggy)
	_check(bool(_screen.call("drop_on_sell")), "Auch aus dem Raster lässt sich verkaufen.")
	_check(int(_game.get("points")) == points + ItemDefs.sell_value("piggy_bank", 1) and pack.placed_items().is_empty(),
		"Der Verstärker bringt seinen festen Betrag und das Raster ist leer.")
	# quick_place räumt aus der Ablage an die erste passende Stelle.
	var hp: int = pack.add_item("max_hp", 1)
	_check(bool(_screen.call("quick_place", hp)) and pack.is_placed(hp) and _level("max_hp") == 1, "quick_place räumt einen Gegenstand ein.")
	_check(not bool(_screen.call("quick_place", hp)), "quick_place wirkt nur auf Gegenstände in der Ablage.")


## Die Ablage hat keine Grenze: Auch mit viel darin gibt es keine Warnung, FERTIG ist nie gesperrt
## und der Rucksack schließt.
func _test_close() -> void:
	_fresh_open(16)
	var pack: BackpackState = _pack()
	var warning: Label = _screen.get("warning_label") as Label
	var done: Button = _screen.get("done_button") as Button
	var uids: Array[int] = []
	for id: String in ["luck", "drone", "lifesteal", "speed_loader", "piggy_bank", "spotlight", "snack", "burn"]:
		uids.append(pack.add_item(id, 1))
	_game.call("sync_build")
	_check((_screen.get("storage_label") as Label).text == "ABLAGE 8", "Die Überschrift zählt die Ablage ohne Grenze, war: " + (_screen.get("storage_label") as Label).text)
	_check(not warning.visible, "Acht Gegenstände in der Ablage geben keine Warnung.")
	_check(is_equal_approx(done.modulate.a, 1.0) and not done.disabled, "FERTIG ist auch mit acht Gegenständen in der Ablage frei.")
	_screen.call("pick_up", uids[0])
	_check(bool(_screen.call("request_close")), "Mit acht Gegenständen in der Ablage lässt sich der Rucksack schließen.")
	_check(_state() == STATE_PLAYING and not paused, "Nach dem Schließen läuft das Spiel weiter.")
	_check(not _is_open(), "Der Bildschirm ist zu.")
	_check(_held() == -1, "Das Schließen legt den gehaltenen Gegenstand zurück.")
	_check(pack.storage_items().size() == 8, "Die Ablage bleibt beim Schließen, wie sie war.")
	_check(not bool(_screen.call("pick_up", uids[0])), "Bei geschlossenem Bildschirm lässt sich nichts greifen.")
	# Der Knopf FERTIG schließt ebenfalls.
	_game.call("open_backpack")
	_check(_is_open() and not warning.visible and is_equal_approx(done.modulate.a, 1.0), "Beim nächsten Öffnen ist FERTIG wieder frei und nichts warnt.")
	done.pressed.emit()
	_check(not _is_open() and _state() == STATE_PLAYING, "Der Knopf FERTIG schließt den Rucksack.")


func _test_keys() -> void:
	_game.call("start_run", 17)
	var pack: BackpackState = _pack()
	_screen.call("_unhandled_input", _action("backpack"))
	_check(_is_open() and _state() == STATE_PACKING and paused, "Die Taste Rucksack öffnet im Spiel den Rucksack.")
	var uid: int = pack.add_item("burn", 1)
	_screen.call("pick_up", uid)
	_screen.call("_unhandled_input", _action("reload"))
	_check(int(_screen.call("held_rotation")) == 1, "Die Taste Nachladen dreht den gehaltenen Gegenstand.")
	_screen.call("_unhandled_input", _mouse_button(MOUSE_BUTTON_RIGHT, true, Vector2.ZERO))
	_check(int(_screen.call("held_rotation")) == 2, "Ein Rechtsklick dreht den gehaltenen Gegenstand.")
	_screen.call("cancel_hold")
	_screen.call("_unhandled_input", _action("reload"))
	_check(_held() == -1, "Ohne gehaltenen Gegenstand macht die Taste Nachladen nichts.")
	_screen.call("_unhandled_input", _action("backpack"))
	_check(not _is_open() and _state() == STATE_PLAYING and not paused, "Die Taste Rucksack schließt ihn wieder.")
	_game.call("open_backpack")
	_screen.call("_unhandled_input", _action("pause"))
	_check(not _is_open() and _state() == STATE_PLAYING and not paused, "Esc schließt den offenen Rucksack.")
	_screen.call("_unhandled_input", _action("pause"))
	_check(not _is_open() and _state() == STATE_PLAYING, "Esc im laufenden Spiel öffnet den Rucksack nicht.")
	# In der Kistenwahl wirkt die Taste nicht.
	_game.call("open_chest", 1)
	_screen.call("_unhandled_input", _action("backpack"))
	_check(not _is_open() and _state() == STATE_CHOOSING, "In der Kistenwahl öffnet die Taste den Rucksack nicht.")


func _test_chest() -> void:
	_game.call("start_run", 18)
	_game.call("open_chest", 1)
	var offers: Array = _game.get("current_offers")
	var index: int = -1
	for i: int in offers.size():
		if str((offers[i] as Dictionary).get("kind", "")) == "item" and index == -1:
			index = i
	_check(index != -1, "Die Kiste bietet mindestens einen Gegenstand an.")
	if index == -1:
		_game.call("start_run", 18)
		return
	var offer_id: String = str((offers[index] as Dictionary)["id"])
	_check(not _is_open(), "In der Kistenwahl ist der Rucksack noch zu.")
	_game.call("choose_offer", index)
	_check(_state() == STATE_PACKING and paused and _is_open(), "Nach der Wahl eines Gegenstands ist der Rucksack offen.")
	var storage: Array[Dictionary] = _pack().storage_items()
	_check(storage.size() == 1 and str(storage[0]["id"]) == offer_id, "Der neue Gegenstand liegt in der Ablage.")
	if storage.size() == 1:
		var uid: int = int(storage[0]["uid"])
		_check(not bool(_screen.call("is_card_open")), "Ohne Zeiger auf dem neuen Gegenstand gibt es keine Karte.")
		_check(int(_screen.call("item_at", (_screen.call("storage_rect", 0) as Rect2).get_center())) == uid, "Er liegt in der ersten Zeile des Regals.")
		_screen.call("set_pointer", (_screen.call("storage_rect", 0) as Rect2).get_center())
		var title: String = (_screen.get("card_name_label") as Label).text
		_check(bool(_screen.call("is_card_open")) and title.begins_with("NEU: ") and title.contains(ItemDefs.display_name(offer_id)),
			"Die Karte stellt den neuen Gegenstand vor, war: " + title)
		_screen.call("set_pointer", Vector2(-40.0, -40.0))
		if _pack().find_spot(uid).is_empty():
			# Eine lange Waffe passt nicht in den Start-Rucksack: Dann bleibt nur das Verkaufen.
			_check(not bool(_screen.call("quick_place", uid)), "Was nirgends passt, räumt quick_place nicht ein.")
			_screen.call("pick_up", uid)
			_check(bool(_screen.call("drop_on_sell")), "Der neue Gegenstand lässt sich verkaufen.")
		else:
			_check(bool(_screen.call("quick_place", uid)), "Der neue Gegenstand lässt sich in den leeren Rucksack räumen.")
		if _pack().has_item(uid):
			_screen.call("set_pointer", (_screen.call("item_rect", uid) as Rect2).get_center())
			_check(int(_screen.call("card_uid")) == uid and not (_screen.get("card_name_label") as Label).text.begins_with("NEU: "), "Danach gilt er nicht mehr als neu.")
			_screen.call("set_pointer", Vector2(-40.0, -40.0))
	_check(bool(_screen.call("request_close")) and _state() == STATE_PLAYING and not paused, "Der Lauf geht nach dem Schließen weiter.")


func _test_mouse() -> void:
	_fresh_open(19)
	var pack: BackpackState = _pack()
	var cells: Array[Vector2i] = pack.cells()
	var uid: int = pack.add_item("corpse_explosion", 1)
	var slot: Vector2 = (_screen.call("storage_rect", 0) as Rect2).get_center()
	_check(int(_screen.call("item_at", slot)) == uid, "item_at findet den Gegenstand in der Ablage.")
	# Ziehen aus der Ablage ins Raster.
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, slot))
	_check(_held() == uid, "Ein Druck der linken Maustaste greift den Gegenstand.")
	_screen.call("_on_board_input", _mouse_motion(_cell_center(cells[0])))
	var preview: Dictionary = _screen.call("drop_preview")
	_check(not preview.is_empty() and int(preview["kind"]) == 0 and (preview["pos"] as Vector2i) == cells[0], "Die Vorschau meldet: passt.")
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, false, _cell_center(cells[0])))
	_check(_held() == -1 and pack.is_placed(uid) and (pack.item(uid)["pos"] as Vector2i) == cells[0], "Loslassen über dem Raster räumt ein.")
	_check(int(_screen.call("item_at", _cell_center(cells[0] + Vector2i(2, 0)))) == uid, "item_at findet den Gegenstand im Raster.")
	# Am dritten Feld anfassen: Dieses Feld bleibt unter dem Zeiger.
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, _cell_center(cells[0] + Vector2i(2, 0))))
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, false, _cell_center(cells[0] + Vector2i(2, 1))))
	_check((pack.item(uid)["pos"] as Vector2i) == cells[0] + Vector2i(0, 1), "Das angefasste Feld der Form bleibt unter dem Zeiger.")
	# Rechtsklick dreht, die Vorschau zeigt: passt nicht (ragt unten heraus).
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, _cell_center(cells[0] + Vector2i(0, 1))))
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_RIGHT, true, _cell_center(cells[0] + Vector2i(0, 1))))
	_check(int(_screen.call("held_rotation")) == 1, "Ein Rechtsklick über dem Raster dreht.")
	_screen.call("_on_board_input", _mouse_motion(_cell_center(cells[0] + Vector2i(0, 2))))
	preview = _screen.call("drop_preview")
	_check(not preview.is_empty() and int(preview["kind"]) == 2, "Die Vorschau meldet: passt nicht.")
	# Loslassen neben allem: zurück an den alten Platz.
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(-40.0, -40.0)))
	_check(_held() == -1 and (pack.item(uid)["pos"] as Vector2i) == cells[0] + Vector2i(0, 1) and int(pack.item(uid)["rot"]) == 0,
		"Loslassen neben allen Flächen legt den Gegenstand zurück.")
	# Vorschau beim Zusammenlegen.
	var twin: int = pack.add_item("corpse_explosion", 1)
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, slot))
	_check(_held() == twin, "Der zweite Gegenstand liegt im ersten Fach und wird gegriffen.")
	_screen.call("_on_board_input", _mouse_motion(_cell_center(cells[0] + Vector2i(1, 1))))
	preview = _screen.call("drop_preview")
	_check(not preview.is_empty() and int(preview["kind"]) == 1 and int(preview["merge"]) == uid, "Die Vorschau meldet: wird zusammengelegt.")
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, false, _cell_center(cells[0] + Vector2i(1, 1))))
	_check(not pack.has_item(twin) and int(pack.item(uid)["level"]) == 2, "Loslassen auf dem gleichen Gegenstand legt zusammen.")
	# Ziehen in die Ablage und auf das Verkaufsfeld.
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, _cell_center(cells[0] + Vector2i(0, 1))))
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, false, (_screen.call("storage_area") as Rect2).get_center()))
	_check(pack.has_item(uid) and not pack.is_placed(uid), "Loslassen über der Ablage legt den Gegenstand ab.")
	var points: int = int(_game.get("points"))
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, slot))
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, false, (_screen.call("sell_rect") as Rect2).get_center()))
	_check(not pack.has_item(uid) and int(_game.get("points")) == points + ItemDefs.sell_value("corpse_explosion", 2),
		"Loslassen über dem Verkaufsfeld verkauft.")
	# Doppelklick in der Ablage räumt ein.
	var luck: int = pack.add_item("luck", 1)
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, slot))
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, false, slot))
	_check(not pack.is_placed(luck) and _held() == -1, "Ein einfacher Klick lässt den Gegenstand in der Ablage.")
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, slot, true))
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, false, slot))
	_check(pack.is_placed(luck) and _level("luck") == 1, "Ein Doppelklick räumt den Gegenstand ein.")
	# Klick ins Leere greift nichts.
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(-40.0, -40.0)))
	_check(_held() == -1, "Ein Klick neben alle Gegenstände greift nichts.")


func _test_info_texts() -> void:
	_fresh_open(20)
	var pack: BackpackState = _pack()
	var bolt: int = pack.add_item("chain_lightning", 1)
	var info: Dictionary = _screen.call("describe", bolt)
	_check(str(info["name"]) == ItemDefs.display_name("chain_lightning"), "describe nennt den Namen.")
	_check(str(info["extra"]).contains("Ablage"), "In der Ablage steht dabei, dass der Gegenstand nicht wirkt.")
	_check(str(info["sell"]).contains(str(ItemDefs.sell_value("chain_lightning", 1))), "describe nennt den Verkaufswert.")
	_check(not str(info["text"]).is_empty() and str(info["text"]) == ItemDefs.description("chain_lightning", 1), "describe nennt die Wirkung in der eigenen Rarität.")
	_check(str(info["subtitle"]) == ItemDefs.subtitle("chain_lightning", 1), "Die Zeile unter dem Namen zeigt die eigene Rarität.")
	var stats: Label = _screen.get("stats_label") as Label
	var pistol_name: String = ItemDefs.display_name("pistol")
	# Stern-Gegenstand ohne Waffe: Er sagt, dass er auf nichts wirkt.
	_check(_put(bolt, Vector2i(1, 2), 0), "Der Starkstrom-Sponsor liegt im Raster.")
	info = _screen.call("describe", bolt)
	_check(str(info["extra"]).contains("Wirkt gerade auf keine Waffe"), "Ohne Waffe auf dem Stern steht das dabei, war: " + str(info["extra"]))
	_check(not str(info["extra"]).contains("Verstärker"), "Von Verstärkern, die die Rarität heben, ist keine Rede mehr.")
	_check(_level("chain_lightning") == 0, "Ohne Waffe auf dem Stern wirkt der Starkstrom-Sponsor nicht.")
	# Waffe in der Ablage und im Raster.
	var pistol: int = pack.add_item("pistol", 1)
	info = _screen.call("describe", pistol)
	_check(str(info["name"]) == pistol_name and str(info["extra"]).contains("Ablage"), "Eine Waffe in der Ablage sagt, dass man sie nicht hält.")
	_check(_put(pistol, Vector2i(2, 2), 0), "Die Dienstpistole liegt im Raster.")
	info = _screen.call("describe", pistol)
	_check(str(info["subtitle"]) == ItemDefs.subtitle("pistol", 1) and str(info["subtitle"]).contains("Waffe"), "Die Zeile unter dem Namen nennt die Waffe, war: " + str(info["subtitle"]))
	_check(str(info["text"]) == ItemDefs.description("pistol", 1) and str(info["text"]).contains("Schaden"), "Die Tafel zeigt die Daten der Waffe.")
	_check(str(info["extra"]).contains("Darauf wirken: " + ItemDefs.display_name("chain_lightning")), "Die Waffe nennt den Gegenstand, der auf sie wirkt, war: " + str(info["extra"]))
	_check(str(info["extra"]).contains("linken Hand"), "Die Waffe nennt ihre Hand, war: " + str(info["extra"]))
	_check(str(info["sell"]).contains(str(ItemDefs.sell_value("pistol", 1))), "Auch die Waffe nennt ihren Verkaufswert.")
	info = _screen.call("describe", bolt)
	_check(str(info["extra"]).contains("Wirkt auf: " + pistol_name), "Der Stern-Gegenstand nennt die Waffe, war: " + str(info["extra"]))
	_check(_level("chain_lightning") == 1, "Mit Waffe auf dem Stern wirkt der Starkstrom-Sponsor.")
	# Mehrere Gegenstände auf derselben Waffe.
	var ammo: int = pack.add_item("pierce", 1)
	var light: int = pack.add_item("spotlight", 1)
	_check(_put(ammo, Vector2i(2, 3), 0) and _put(light, Vector2i(2, 1), 0), "Spezialmunition und Scheinwerfer liegen an der Pistole.")
	info = _screen.call("describe", pistol)
	var wanted: String = "Darauf wirken: %s, %s, %s" % [ItemDefs.display_name("chain_lightning"), ItemDefs.display_name("pierce"), ItemDefs.display_name("spotlight")]
	_check(str(info["extra"]).contains(wanted), "Die Waffe zählt alle Gegenstände auf, die auf sie wirken, war: " + str(info["extra"]))
	info = _screen.call("describe", light)
	_check(str(info["extra"]).contains("Wirkt auf: " + pistol_name) and str(info["extra"]).contains("+10 % Waffenschaden"),
		"Der Scheinwerfer nennt die Waffe und seinen Beitrag, war: " + str(info["extra"]))
	_check(stats.text.contains("%s: Schaden +10 %%" % pistol_name), "Die Übersicht nennt den Bonus der Waffe, war: " + stats.text)
	_check(stats.text.contains("Hände: 1 von 2") and stats.text.contains("Freie Felder: 4 von 12"), "Die Übersicht nennt Hände und freie Felder, war: " + stats.text)
	# Zwei gleiche Gegenstände auf derselben Waffe werden zusammengefasst.
	var second_light: int = pack.add_item("spotlight", 1)
	_check(_put(second_light, Vector2i(4, 2), 1), "Ein zweiter Scheinwerfer liegt hochkant rechts neben der Pistole.")
	info = _screen.call("describe", pistol)
	_check(str(info["extra"]).contains("2 × " + ItemDefs.display_name("spotlight")), "Gleiche Gegenstände werden gezählt, war: " + str(info["extra"]))
	_check(stats.text.contains("Schaden +20 %"), "Beide Scheinwerfer wirken, war: " + stats.text)
	_screen.call("pick_up", second_light)
	_screen.call("drop_on_sell")
	# Sparschwein: wirkt ohne Sterne.
	var piggy: int = pack.add_item("piggy_bank", 1)
	_check(_put(piggy, Vector2i(1, 1), 0), "Das Sparschwein liegt im Raster.")
	info = _screen.call("describe", piggy)
	_check(str(info["extra"]).contains("+6 % Punkte") and not str(info["extra"]).contains("Wirkt"), "Das Sparschwein nennt seinen Beitrag, war: " + str(info["extra"]))
	_check(stats.text.contains("Punkte +6 %"), "Die Übersicht nennt den Punkte-Bonus, war: " + stats.text)
	# Ohne Waffe wirken die Stern-Gegenstände nicht und nennen keinen Beitrag.
	_screen.call("pick_up", pistol)
	_check(bool(_screen.call("drop_on_storage")), "Die Pistole geht in die Ablage.")
	info = _screen.call("describe", light)
	_check(str(info["extra"]).contains("Wirkt gerade auf keine Waffe") and not str(info["extra"]).contains("Bringt gerade"),
		"Ein Verstärker ohne Waffe nennt keinen Beitrag, war: " + str(info["extra"]))
	_check(not stats.text.contains("Schaden +") and stats.text.contains("Hände: 0 von 2"), "Die Übersicht zeigt keinen Waffen-Bonus mehr, war: " + stats.text)
	_check((_screen.call("describe", 999) as Dictionary).is_empty(), "Für einen unbekannten Gegenstand ist describe leer.")
	info = _screen.call("describe", pack.add_item("bag_small", 1))
	_check(str(info["extra"]).contains("verbraucht"), "Ein Rucksack-Teil sagt, dass es verbraucht wird.")
	_check(not stats.text.contains("\n"), "Die Übersicht ist eine einzige Zeile, war: " + stats.text)
	# Die Karte folgt dem gehaltenen Gegenstand und dem Zeiger.
	_screen.call("pick_up", light)
	_check(int(_screen.call("card_uid")) == light and (_screen.get("card_name_label") as Label).text == ItemDefs.display_name("spotlight"), "Die Karte zeigt den gehaltenen Gegenstand.")
	_screen.call("cancel_hold")
	_screen.call("set_pointer", _cell_center(Vector2i(1, 2)))
	_check(int(_screen.call("card_uid")) == bolt and (_screen.get("card_name_label") as Label).text == ItemDefs.display_name("chain_lightning"), "Die Karte zeigt den Gegenstand unter dem Zeiger.")
	_screen.call("set_pointer", Vector2(-40.0, -40.0))
	_check(not bool(_screen.call("is_card_open")) and int(_screen.call("card_uid")) == -1, "Ohne Gegenstand unter dem Zeiger ist keine Karte da.")
	var help_text: String = (_screen.get("help_text_label") as Label).text
	_check(help_text.contains("Sterne") and help_text.contains("zwei Hände"), "Die Hilfe erklärt Bedienung, Hände und Sterne.")
	_check(help_text.contains("Ablage") and help_text.contains("nächsten Rarität"), "Die Hilfe sagt, dass man im Rucksack und in der Ablage kombinieren kann.")
	_check(help_text.contains("kaputt") and help_text.contains("Reparieren kostet Material"), "Die Hilfe sagt, dass Fundstücke kaputt sind und Reparieren Material kostet.")
	_check(help_text.contains("Verschrotten gibt Material") and help_text.contains("Verkaufen gibt Punkte") and help_text.contains("geschaffte Welle"),
		"Die Hilfe sagt, was Verschrotten und Verkaufen geben und dass es Material für Wellen gibt.")
	_check(help_text.contains("F repariert") and help_text.contains("zweimal X") and help_text.contains("N zeigt die Namen"), "Die Hilfe nennt die Tasten F, X und N.")
	_check((_screen.get("storage_label") as Label).text == "ABLAGE 2", "Die Ablage zeigt, wie viel darin liegt, war: " + (_screen.get("storage_label") as Label).text)


## Sterne eingeräumter Gegenstände und des gehaltenen Gegenstands. Wartet zwischendurch Bilder ab,
## damit das Zeichnen der Sterne wirklich läuft.
func _test_stars() -> void:
	_fresh_open(30)
	var pack: BackpackState = _pack()
	_check(_marks().is_empty(), "Ohne Stern-Gegenstand gibt es keine Sterne.")
	# Stern-Gegenstand ohne Waffe: zwei leere Sterne.
	var ammo: int = pack.add_item("pierce", 1)
	_check(_marks().is_empty(), "In der Ablage hat ein Gegenstand keine Sterne.")
	_check(_put(ammo, Vector2i(2, 3), 0), "Die Spezialmunition liegt unten im Raster.")
	var marks: Array[Dictionary] = _marks()
	_check(marks.size() == 2, "Die Spezialmunition zeigt zwei Sterne, waren %d." % marks.size())
	_check(not _mark(ammo, Vector2i(2, 2)).is_empty() and not _mark(ammo, Vector2i(3, 2)).is_empty(), "Die Sterne liegen über der Spezialmunition.")
	_check(not _is_lit(ammo, Vector2i(2, 2)) and not _is_lit(ammo, Vector2i(3, 2)), "Ohne Waffe sind die Sterne leer.")
	_check(not bool(_mark(ammo, Vector2i(2, 2)).get("preview", true)), "Sterne eingeräumter Gegenstände sind keine Vorschau.")
	_check(_level("pierce") == 0, "Ohne Waffe auf einem Stern wirkt die Spezialmunition nicht.")
	# Mit Waffe auf den Sternen: gefüllt.
	var pistol: int = pack.add_item("pistol", 1)
	_check(_put(pistol, Vector2i(2, 2), 0), "Die Dienstpistole liegt auf den Sternen.")
	_check(_is_lit(ammo, Vector2i(2, 2)) and _is_lit(ammo, Vector2i(3, 2)), "Mit Waffe darauf sind beide Sterne gefüllt.")
	_check(_level("pierce") == 1, "Jetzt wirkt die Spezialmunition.")
	# Zweiter Gegenstand mit einem Stern auf demselben Feld und einem außerhalb des Rucksacks.
	var bolt: int = pack.add_item("chain_lightning", 1)
	_check(_put(bolt, Vector2i(1, 2), 0), "Der Starkstrom-Sponsor liegt links neben der Pistole.")
	_check(_is_lit(bolt, Vector2i(2, 2)), "Sein rechter Stern liegt auf der Pistole und ist gefüllt.")
	_check(not pack.has_cell(Vector2i(0, 2)) and not _mark(bolt, Vector2i(0, 2)).is_empty() and not _is_lit(bolt, Vector2i(0, 2)),
		"Sein linker Stern liegt auf einem Feld ohne Rucksack: leer, aber zu sehen.")
	var shared: int = 0
	for mark: Dictionary in _marks():
		if (mark["cell"] as Vector2i) == Vector2i(2, 2):
			shared += 1
	_check(shared == 2, "Auf dem Feld (2, 2) liegen zwei Sterne verschiedener Gegenstände, waren %d." % shared)
	await process_frame
	await process_frame
	# Zeiger auf einem Gegenstand hebt seine Sterne hervor, Zeiger auf der Waffe die Sterne auf ihr.
	_screen.call("set_pointer", _cell_center(Vector2i(1, 2)))
	_check(bool(_mark(bolt, Vector2i(2, 2)).get("focus", false)) and not bool(_mark(ammo, Vector2i(2, 2)).get("focus", true)),
		"Unter dem Zeiger sind nur die Sterne dieses Gegenstands hervorgehoben.")
	_screen.call("set_pointer", _cell_center(Vector2i(3, 2)))
	_check(bool(_mark(bolt, Vector2i(2, 2)).get("focus", false)) and bool(_mark(ammo, Vector2i(3, 2)).get("focus", false))
		and not bool(_mark(bolt, Vector2i(0, 2)).get("focus", true)), "Zeiger auf der Waffe: Die Sterne auf ihr sind hervorgehoben.")
	await process_frame
	_screen.call("set_pointer", Vector2(-40.0, -40.0))
	# Gehaltener Stern-Gegenstand über einer Waffe: Vorschau mit gefüllten Sternen.
	var light: int = pack.add_item("spotlight", 1)
	_screen.call("pick_up", light)
	_check(_marks_of(light).is_empty(), "Neben dem Raster hat der gehaltene Gegenstand keine Sterne.")
	_screen.call("set_pointer", _cell_center(Vector2i(2, 1)))
	var preview: Dictionary = _screen.call("drop_preview")
	_check(not preview.is_empty() and int(preview["kind"]) == 0 and (preview["pos"] as Vector2i) == Vector2i(2, 1), "Der Scheinwerfer passt über die Pistole.")
	var held_marks: Array[Dictionary] = _marks_of(light, true)
	_check(held_marks.size() == 2 and _marks_of(light).size() == 2, "Der gehaltene Scheinwerfer zeigt zwei Sterne als Vorschau, waren %d." % held_marks.size())
	_check(_mark_cells(held_marks).has(Vector2i(2, 2)) and _mark_cells(held_marks).has(Vector2i(3, 2)), "Die Sterne der Vorschau liegen auf der Pistole.")
	_check(_is_lit(light, Vector2i(2, 2)) and _is_lit(light, Vector2i(3, 2)), "Über der Waffe sind die Sterne der Vorschau gefüllt.")
	_check(not pack.is_placed(light) and _level("pierce") == 1, "Die Vorschau ändert den Rucksack nicht.")
	await process_frame
	await process_frame
	# Drehen: Die Sterne wandern mit.
	_screen.call("rotate_held")
	preview = _screen.call("drop_preview")
	held_marks = _marks_of(light, true)
	var turned: Array[Vector2i] = BackpackState.stars_at("spotlight", preview["pos"] as Vector2i, int(_screen.call("held_rotation")))
	var same: bool = held_marks.size() == turned.size()
	for cell: Vector2i in _mark_cells(held_marks):
		if not turned.has(cell):
			same = false
	_check(int(_screen.call("held_rotation")) == 1 and same, "Nach dem Drehen liegen die Sterne dort, wo stars_at sie nennt.")
	_check(not _mark_cells(held_marks).has(Vector2i(3, 2)), "Nach dem Drehen liegt kein Stern mehr auf (3, 2).")
	var any_lit: bool = false
	for mark: Dictionary in held_marks:
		if bool(mark["lit"]):
			any_lit = true
	_check(not any_lit, "Gedreht zeigen die Sterne nach links und treffen keine Waffe.")
	await process_frame
	_screen.call("set_pointer", Vector2(-40.0, -40.0))
	_check(_marks_of(light).is_empty(), "Verlässt der Zeiger das Raster, verschwinden die Sterne der Vorschau.")
	await process_frame
	_screen.call("cancel_hold")
	# Ein eingeräumter Stern-Gegenstand in der Hand zeigt seine Sterne nicht mehr am alten Platz.
	_screen.call("pick_up", ammo)
	_check(_marks_of(ammo).is_empty(), "Der alte Platz des gehaltenen Gegenstands hat keine Sterne.")
	_screen.call("cancel_hold")
	_check(_marks_of(ammo).size() == 2, "Nach dem Zurücklegen sind die Sterne wieder da.")
	# Sterne außerhalb des Rasters: Die Ladehilfe am rechten Rand hat vier Sternfelder, eines
	# liegt außerhalb.
	var bag: int = pack.add_item("bag_small", 1)
	_check(_put(bag, Vector2i(5, 2), 0) and pack.has_cell(Vector2i(6, 2)), "Der Jutebeutel verlängert den Rucksack bis zum rechten Rand.")
	var loader: int = pack.add_item("speed_loader", 1)
	_check(_put(loader, Vector2i(6, 2), 0), "Die Ladehilfe liegt am rechten Rand.")
	_check(pack.star_cells_of(loader).size() == 4 and pack.star_cells_of(loader).has(Vector2i(7, 2)), "Ein Sternfeld der Ladehilfe liegt außerhalb des Rasters.")
	var loader_marks: Array[Dictionary] = _marks_of(loader)
	_check(loader_marks.size() == 3 and not _mark_cells(loader_marks).has(Vector2i(7, 2)), "Sterne außerhalb des Rasters fehlen in star_marks, waren %d." % loader_marks.size())
	var all_inside: bool = true
	for mark: Dictionary in _marks():
		if not BackpackState.in_bounds(mark["cell"] as Vector2i):
			all_inside = false
	_check(all_inside, "Alle Sterne liegen im Raster.")
	await process_frame
	await process_frame


## Eine gehaltene Waffe lässt die Sterne aufleuchten, die sie an der Stelle der Vorschau bedeckt.
func _test_held_weapon_stars() -> void:
	_fresh_open(31)
	var pack: BackpackState = _pack()
	var ammo: int = pack.add_item("pierce", 1)
	var bolt: int = pack.add_item("chain_lightning", 1)
	_check(_put(ammo, Vector2i(2, 3), 0) and _put(bolt, Vector2i(1, 2), 0), "Zwei Stern-Gegenstände liegen im Raster.")
	var pistol: int = pack.add_item("pistol", 1)
	_screen.call("pick_up", pistol)
	_check(not _is_lit(ammo, Vector2i(2, 2)), "Neben dem Raster leuchtet durch die gehaltene Waffe nichts.")
	_screen.call("set_pointer", _cell_center(Vector2i(2, 2)))
	var preview: Dictionary = _screen.call("drop_preview")
	_check(not preview.is_empty() and int(preview["kind"]) == 0, "Die Pistole passt auf die Sternfelder.")
	_check(_is_lit(ammo, Vector2i(2, 2)) and _is_lit(ammo, Vector2i(3, 2)) and _is_lit(bolt, Vector2i(2, 2)),
		"Die Sterne unter der gehaltenen Waffe leuchten auf.")
	_check(not _is_lit(bolt, Vector2i(0, 2)), "Sterne neben der Waffe bleiben leer.")
	_check(not pack.is_placed(pistol) and _level("pierce") == 0, "Die Vorschau ändert den Rucksack nicht.")
	_check(bool(_screen.call("drop_at", _cell_center(Vector2i(2, 2)))) and pack.is_placed(pistol), "Loslassen räumt die Pistole ein.")
	_check(_level("pierce") == 1 and _level("chain_lightning") == 1, "Danach wirken beide Stern-Gegenstände.")
	# Eine eingeräumte Waffe verschieben: An der Stelle der Vorschau zählt sie, am alten Platz nicht.
	_screen.call("pick_up", pistol)
	_check(_is_lit(ammo, Vector2i(2, 2)), "Solange die Waffe nur gegriffen ist, bleiben die Sterne gefüllt.")
	_screen.call("set_pointer", _cell_center(Vector2i(2, 1)))
	preview = _screen.call("drop_preview")
	_check(not preview.is_empty() and int(preview["kind"]) == 0, "Die Pistole passt eine Zeile höher.")
	_check(not _is_lit(ammo, Vector2i(2, 2)) and not _is_lit(ammo, Vector2i(3, 2)) and not _is_lit(bolt, Vector2i(2, 2)),
		"Am alten Platz der gehaltenen Waffe sind die Sterne leer.")
	_screen.call("cancel_hold")
	_check(_is_lit(ammo, Vector2i(2, 2)) and (pack.item(pistol)["pos"] as Vector2i) == Vector2i(2, 2), "Nach dem Zurücklegen leuchten sie wieder.")
	_screen.call("set_pointer", Vector2(-40.0, -40.0))


## Hände: Anzeige, Ablehnung der dritten Waffe mit Warnung, Zweihand-Waffen.
func _test_hands() -> void:
	_fresh_open(32)
	var pack: BackpackState = _pack()
	var pistol_name: String = ItemDefs.display_name("pistol")
	var stats: Label = _screen.get("stats_label") as Label
	# Ohne Waffe: Dienstpistole als Notlösung.
	_check(_hands_title() == "HÄNDE 0 / 2", "Ohne Waffe sind null von zwei Händen belegt, war: " + _hands_title())
	var slots: Array[Dictionary] = _hand_slots()
	_check(slots.size() == 1 and bool(slots[0]["stopgap"]) and int(slots[0]["span"]) == 2, "Ohne Waffe zeigt die Anzeige einen Kasten für die Notlösung.")
	var text: String = _screen.call("hands_text")
	_check(text.contains(pistol_name) and text.contains("Notlösung"), "Ohne Waffe nennt die Anzeige die Dienstpistole als Notlösung, war: " + text)
	_check(not _warning().visible, "Ohne Anlass ist keine Warnung zu sehen.")
	# Eine Pistole: eine von zwei Händen.
	var first: int = pack.add_item("pistol", 1)
	_check(_put(first, Vector2i(1, 1), 0), "Die erste Pistole liegt im Raster.")
	_check(_hands_title() == "HÄNDE 1 / 2", "Eine Pistole belegt eine von zwei Händen, war: " + _hands_title())
	slots = _hand_slots()
	_check(slots.size() == 2 and int(slots[0]["uid"]) == first and str(slots[0]["name"]) == pistol_name and int(slots[1]["uid"]) == -1,
		"Links liegt die Pistole, rechts ist die Hand frei.")
	text = _screen.call("hands_text")
	_check(text.contains("Linke Hand: " + pistol_name) and text.contains("Rechte Hand: frei") and not text.contains("Notlösung"), "Die Anzeige nennt beide Hände, war: " + text)
	_check(stats.text.contains("Hände: 1 von 2"), "Die Übersicht nennt die Hände, war: " + stats.text)
	_check(_loadout().size() == 1 and int(_loadout()[0]["uid"]) == first, "Game.loadout enthält die Pistole.")
	# Zwei Pistolen: beide Hände.
	var second: int = pack.add_item("pistol", 2)
	_check(_put(second, Vector2i(3, 1), 0), "Die zweite Pistole liegt rechts daneben.")
	_check(_hands_title() == "HÄNDE 2 / 2", "Zwei Pistolen belegen beide Hände, war: " + _hands_title())
	slots = _hand_slots()
	_check(slots.size() == 2 and int(slots[0]["uid"]) == first and int(slots[1]["uid"]) == second, "Die linke Pistole liegt in der linken Hand, die rechte in der rechten.")
	_check(str((_screen.call("describe", second) as Dictionary)["extra"]).contains("rechten Hand"), "Die zweite Pistole nennt die rechte Hand.")
	# Eine dritte Waffe wird nur gegriffen: Die Warnung erklärt, warum sie nicht passt.
	var third: int = pack.add_item("smg", 1)
	_check(not pack.has_free_hands(third), "Für die dritte Waffe ist keine Hand frei.")
	_screen.call("pick_up", third)
	_check(_warning().visible and _warning().text == "Keine Hand frei: erst eine Waffe in die Ablage legen", "Beim Greifen der dritten Waffe steht die Warnung da, war: " + _warning().text)
	_screen.call("cancel_hold")
	_check(not _warning().visible, "Nach dem Zurücklegen verschwindet die Warnung.")
	# Eine gleiche Pistole braucht zum Zusammenlegen keine freie Hand.
	var twin: int = pack.add_item("pistol", 1)
	_screen.call("pick_up", twin)
	_check(_warning().visible, "Auch die dritte Pistole bekommt die Warnung.")
	_screen.call("set_pointer", _cell_center(Vector2i(1, 1)))
	var preview: Dictionary = _screen.call("drop_preview")
	_check(int(preview.get("kind", -1)) == 1 and not _warning().visible, "Über der gleichen Pistole gibt es keine Warnung: Zusammenlegen geht.")
	_screen.call("cancel_hold")
	_check(int(_game.call("sell_item", twin)) == ItemDefs.sell_value("pistol", 1), "Die überzählige Pistole wird verkauft.")
	# Ablegen der dritten Waffe: rote Vorschau, abgelehnt, Warnung bleibt stehen.
	_screen.call("pick_up", third)
	_screen.call("set_pointer", _cell_center(Vector2i(1, 2)))
	preview = _screen.call("drop_preview")
	_check(not preview.is_empty() and int(preview["kind"]) == 2, "Die Vorschau der dritten Waffe ist rot, obwohl die Felder frei sind.")
	var before: int = _build_changes
	_check(not bool(_screen.call("drop_on_cell", Vector2i(1, 2))), "Die dritte Waffe wird abgelehnt.")
	_check(pack.has_item(third) and not pack.is_placed(third) and _held() == -1 and _build_changes == before, "Sie liegt wieder in der Ablage, nichts hat sich geändert.")
	_check(_warning().visible and _warning().text.contains("Keine Hand frei"), "Nach dem abgelehnten Ablegen steht die Warnung noch da.")
	_check(not bool(_screen.call("quick_place", third)) and _warning().visible, "Auch der Doppelklick räumt sie nicht ein.")
	_check(str((_screen.call("describe", third) as Dictionary)["extra"]).contains("Keine Hand frei"), "Die Karte der Waffe in der Ablage nennt den Grund.")
	# Zweihand-Waffe: abgelehnt, solange eine Pistole im Raster liegt.
	_screen.call("pick_up", second)
	_check(bool(_screen.call("drop_on_storage")) and _hands_title() == "HÄNDE 1 / 2", "Die zweite Pistole geht in die Ablage.")
	_check(not _warning().visible, "Nach einer gelungenen Änderung ist die Warnung weg.")
	var big: int = pack.add_item("shotgun", 1)
	_check(ItemDefs.hands("shotgun") == 2 and not pack.has_free_hands(big), "Die Zweihand-Waffe braucht beide Hände.")
	_screen.call("pick_up", big)
	_check(_warning().visible and _warning().text.contains("zwei Hände"), "Die Warnung nennt die zwei Hände, war: " + _warning().text)
	_check(not bool(_screen.call("drop_on_cell", Vector2i(1, 3))), "Neben einer Pistole wird die Zweihand-Waffe abgelehnt.")
	_check(not pack.is_placed(big) and _warning().visible, "Sie bleibt in der Ablage, die Warnung steht da.")
	# Nach dem Weglegen der Pistole passt sie.
	_screen.call("pick_up", first)
	_check(bool(_screen.call("drop_on_storage")) and _hands_title() == "HÄNDE 0 / 2", "Die erste Pistole geht in die Ablage.")
	_check(_put(big, Vector2i(1, 3), 0), "Ohne Pistole im Raster passt die Zweihand-Waffe.")
	_check(_hands_title() == "HÄNDE 2 / 2" and not _warning().visible, "Sie belegt beide Hände, war: " + _hands_title())
	slots = _hand_slots()
	_check(slots.size() == 1 and int(slots[0]["uid"]) == big and int(slots[0]["span"]) == 2 and not bool(slots[0]["stopgap"]), "Die Anzeige zeigt einen Kasten über beide Hände.")
	_check(str((_screen.call("describe", big) as Dictionary)["extra"]).contains("beiden Händen"), "Die Zweihand-Waffe nennt beide Hände.")
	_check(_loadout().size() == 1 and str(_loadout()[0]["id"]) == "shotgun", "Game.loadout enthält nur die Zweihand-Waffe.")
	_check(not bool(_screen.call("quick_place", first)) and _warning().text.contains("Keine Hand frei"), "Neben der Zweihand-Waffe passt keine Pistole mehr.")
	# Verschieben der Waffe im Raster braucht keine weitere Hand.
	_check(_put(big, Vector2i(1, 1), 0) and (pack.item(big)["pos"] as Vector2i) == Vector2i(1, 1), "Die eingeräumte Waffe lässt sich verschieben.")
	# Viel in der Ablage hält den Rucksack nicht mehr offen.
	for id: String in ["luck", "luck", "luck"]:
		pack.add_item(id, 1)
	_check(pack.storage_items().size() >= 6 and bool(_screen.call("request_close")) and not _is_open(), "Auch mit viel in der Ablage schließt der Rucksack.")


## Zwei gleiche Waffen zusammenlegen, eine Waffe verkaufen.
func _test_weapon_merge_and_sell() -> void:
	_fresh_open(33)
	var pack: BackpackState = _pack()
	var first: int = pack.add_item("pistol", 1)
	var second: int = pack.add_item("pistol", 1)
	_check(_put(first, Vector2i(1, 1), 0), "Die erste Pistole liegt im Raster.")
	_screen.call("pick_up", second)
	_screen.call("set_pointer", _cell_center(Vector2i(2, 1)))
	var preview: Dictionary = _screen.call("drop_preview")
	_check(int(preview.get("kind", -1)) == 1 and int(preview.get("merge", -1)) == first, "Die Vorschau meldet: Die Pistolen werden zusammengelegt.")
	var before: int = _build_changes
	_check(bool(_screen.call("drop_on_cell", Vector2i(1, 1))), "Eine gleiche Pistole lässt sich auf die erste legen.")
	_check(not pack.has_item(second) and int(pack.item(first)["level"]) == 2, "Zwei gewöhnliche Pistolen werden eine ungewöhnliche.")
	_check(_build_changes == before + 1 and _hands_title() == "HÄNDE 1 / 2", "Der Build ist abgeglichen, eine Hand ist belegt.")
	_check(_loadout().size() == 1 and int(_loadout()[0]["level"]) == 2, "Game.loadout zeigt die neue Rarität.")
	_check(str((_screen.call("describe", first) as Dictionary)["subtitle"]) == ItemDefs.subtitle("pistol", 2), "Die Karte zeigt die neue Rarität.")
	# Andere Rarität: kein Zusammenlegen.
	var common: int = pack.add_item("pistol", 1)
	_screen.call("pick_up", common)
	_check(not bool(_screen.call("drop_on_cell", Vector2i(1, 1))) and int(pack.item(first)["level"]) == 2, "Gewöhnlich auf Ungewöhnlich lässt sich nicht zusammenlegen.")
	# Zwei eingeräumte gleiche Waffen zusammenlegen.
	var other: int = pack.add_item("pistol", 2)
	_check(_put(other, Vector2i(1, 2), 0) and _hands_title() == "HÄNDE 2 / 2", "Eine zweite ungewöhnliche Pistole liegt im Raster.")
	_screen.call("pick_up", other)
	_check(bool(_screen.call("drop_on_cell", Vector2i(1, 1))), "Auch eine eingeräumte Waffe lässt sich auf eine gleiche legen.")
	_check(not pack.has_item(other) and int(pack.item(first)["level"]) == 3 and _hands_title() == "HÄNDE 1 / 2", "Danach ist die eine Pistole selten und eine Hand wieder frei.")
	# Verkaufen aus der Ablage und aus dem Raster.
	var points: int = int(_game.get("points"))
	_screen.call("pick_up", common)
	_check(str((_screen.get("sell_value_label") as Label).text).contains(str(ItemDefs.sell_value("pistol", 1))), "Das Verkaufsfeld zeigt den Wert der Waffe.")
	_check(bool(_screen.call("drop_on_sell")) and int(_game.get("points")) == points + ItemDefs.sell_value("pistol", 1), "Eine Waffe aus der Ablage bringt ihren Verkaufswert.")
	points = int(_game.get("points"))
	_screen.call("pick_up", first)
	_check(bool(_screen.call("drop_on_sell")), "Auch die Waffe aus dem Raster lässt sich verkaufen.")
	_check(int(_game.get("points")) == points + ItemDefs.sell_value("pistol", 3) and not pack.has_item(first), "Sie bringt den Verkaufswert ihrer Rarität.")
	# Ohne Waffe im Rucksack: Dienstpistole als Notlösung.
	_check(_hands_title() == "HÄNDE 0 / 2", "Ohne Waffe ist keine Hand belegt, war: " + _hands_title())
	var text: String = _screen.call("hands_text")
	_check(text.contains(ItemDefs.display_name("pistol")) and text.contains("Notlösung"), "Die Anzeige nennt wieder die Dienstpistole als Notlösung, war: " + text)
	_check(_loadout().size() == 1 and int(_loadout()[0]["uid"]) == 0, "Game.loadout enthält die Dienstpistole mit der uid 0.")


## Kameras im Rucksack (Abschnitt 22.1): fertige Werte in der Info-Tafel, Kamera-Zubehör und
## Wiederholung auf Kameras, Sterne leuchten nur auf dem, worauf sie wirken.
## Der Rucksack ohne Kandidat hat die Felder x 1 bis 4, y 1 bis 3. Die Kameradrohne liegt auf
## (1, 1) und (2, 1).
func _test_cameras() -> void:
	_fresh_open(40)
	var pack: BackpackState = _pack()
	var drone_name: String = ItemDefs.display_name("drone")
	var lens_name: String = ItemDefs.display_name("cam_lens")
	var battery_name: String = ItemDefs.display_name("cam_battery")
	var drone: int = pack.add_item("drone", 1)
	var info: Dictionary = _screen.call("describe", drone)
	_check(str(info["subtitle"]) == ItemDefs.subtitle("drone", 1) and str(info["subtitle"]).contains("Kamera"), "Die Zeile unter dem Namen nennt die Kamera, war: " + str(info["subtitle"]))
	_check(str(info["text"]) == ItemDefs.description("drone", 1), "Die Tafel zeigt den Text der Kamera.")
	_check(str(info["extra"]).contains("Ablage") and not str(info["extra"]).contains("Jetzt"), "Eine Kamera in der Ablage filmt nicht und nennt keine Werte, war: " + str(info["extra"]))
	_check(_put(drone, Vector2i(1, 1)), "Die Kameradrohne liegt im Raster.")
	_check((_game.get("cameras") as Array).size() == 1, "Game.cameras hat eine Kamera.")
	info = _screen.call("describe", drone)
	_check(str(info["extra"]).contains("Jetzt: Schaden 15 · alle 1,2 s · Reichweite 15 m"), "Die Kamera nennt ihre fertigen Werte, war: " + str(info["extra"]))
	_check(str(info["extra"]).contains("Kein Gegenstand wirkt darauf."), "Ohne Zubehör steht das dabei, war: " + str(info["extra"]))
	# Großes Objektiv: Sterne links und rechts, der linke liegt auf der Drohne.
	var lens: int = pack.add_item("cam_lens", 1)
	_check(_put(lens, Vector2i(3, 1)), "Das Objektiv liegt rechts neben der Drohne.")
	_check(_is_lit(lens, Vector2i(2, 1)), "Der Stern des Objektivs leuchtet auf der Kamera.")
	_check(not _mark(lens, Vector2i(4, 1)).is_empty() and not _is_lit(lens, Vector2i(4, 1)), "Der Stern auf dem leeren Feld ist leer.")
	info = _screen.call("describe", lens)
	_check(str(info["extra"]).contains("Wirkt auf: " + drone_name), "Das Objektiv nennt die Kamera, war: " + str(info["extra"]))
	_check(str(info["text"]).contains("Kameras auf den Sternen"), "Der Text des Objektivs nennt die Kameras auf den Sternen, war: " + str(info["text"]))
	info = _screen.call("describe", drone)
	_check(str(info["extra"]).contains("Darauf wirken: " + lens_name), "Die Kamera nennt ihr Zubehör, war: " + str(info["extra"]))
	_check(str(info["extra"]).contains("Jetzt: Schaden 18 ·"), "Mit Objektiv macht die Drohne 18 Schaden, war: " + str(info["extra"]))
	# Sterne von Kamera-Zubehör leuchten nur auf Kameras: nicht auf einem Gegenstand, nicht auf einer Waffe.
	var luck: int = pack.add_item("luck", 1)
	_check(_put(luck, Vector2i(4, 1)), "Der Publikumsliebling liegt auf dem zweiten Stern des Objektivs.")
	_check(not _is_lit(lens, Vector2i(4, 1)), "Auf einem Gegenstand leuchtet der Stern des Objektivs nicht.")
	_screen.call("pick_up", luck)
	_screen.call("drop_on_sell")
	var pistol: int = pack.add_item("pistol", 1)
	_check(_put(pistol, Vector2i(4, 1), 1), "Die Pistole liegt hochkant auf dem zweiten Stern des Objektivs.")
	_check(not _is_lit(lens, Vector2i(4, 1)), "Auf einer Waffe leuchtet der Stern des Objektivs nicht.")
	_check(not str((_screen.call("describe", pistol) as Dictionary)["extra"]).contains(lens_name), "Das Objektiv wirkt nicht auf die Waffe.")
	# Umgekehrt leuchtet ein Waffen-Stern nicht auf einer Kamera.
	var ammo: int = pack.add_item("pierce", 1)
	_check(_put(ammo, Vector2i(1, 2)), "Die Spezialmunition liegt unter der Drohne.")
	_check(not _is_lit(ammo, Vector2i(1, 1)) and not _is_lit(ammo, Vector2i(2, 1)), "Die Sterne der Spezialmunition leuchten auf der Kamera nicht.")
	_check(str((_screen.call("describe", ammo) as Dictionary)["extra"]).contains("Wirkt gerade auf keine Waffe"), "Die Spezialmunition wirkt auf keine Waffe.")
	_screen.call("pick_up", ammo)
	_screen.call("drop_on_sell")
	# Akkupack ohne Kamera auf den Sternen: Der Hinweis nennt die Kamera.
	var battery: int = pack.add_item("cam_battery", 1)
	_check(_put(battery, Vector2i(1, 3)), "Der Akkupack liegt abseits der Kamera.")
	info = _screen.call("describe", battery)
	_check(str(info["extra"]).contains("Wirkt gerade auf keine Kamera: Stern auf eine Kamera legen."), "Der Akkupack sagt, wohin sein Stern muss, war: " + str(info["extra"]))
	# Gehalten: Die Vorschau zeigt, ob sein Stern die Kamera trifft (um 90 Grad gedreht liegt ein Stern oben).
	_screen.call("pick_up", battery)
	_screen.call("rotate_held")
	_screen.call("set_pointer", _cell_center(Vector2i(2, 2)))
	var preview_lit: bool = false
	var preview_other: bool = false
	for mark: Dictionary in _marks_of(battery, true):
		if (mark["cell"] as Vector2i) == Vector2i(2, 1):
			preview_lit = bool(mark["lit"])
		elif bool(mark["lit"]):
			preview_other = true
	_check(preview_lit, "In der Vorschau leuchtet der Stern des Akkupacks auf der Kamera.")
	_check(not preview_other, "Die anderen Sterne der Vorschau bleiben leer.")
	_check(bool(_screen.call("drop_on_cell", Vector2i(2, 2))), "Der Akkupack liegt unter der Drohne.")
	info = _screen.call("describe", battery)
	_check(str(info["extra"]).contains("Wirkt auf: " + drone_name), "Jetzt wirkt der Akkupack auf die Kamera, war: " + str(info["extra"]))
	info = _screen.call("describe", drone)
	_check(str(info["extra"]).contains("alle 1,04 s"), "Mit Akkupack schießt die Drohne alle 1,04 s, war: " + str(info["extra"]))
	_check(str(info["extra"]).contains("Darauf wirken: %s, %s" % [lens_name, battery_name]), "Die Kamera zählt ihr Zubehör auf, war: " + str(info["extra"]))
	# Wiederholung auf der Kamera (um 270 Grad gedreht liegt ihr Stern oben): eine zweite Drohne.
	var replay: int = pack.add_item("replay", 1)
	_check(_put(replay, Vector2i(1, 2), 3), "Die Wiederholung liegt unter der Drohne.")
	_check(_is_lit(replay, Vector2i(1, 1)), "Der Stern der Wiederholung leuchtet auf der Kamera.")
	_check(str((_screen.call("describe", replay) as Dictionary)["extra"]).contains("Wirkt auf: " + drone_name), "Die Wiederholung nennt die Kamera.")
	_check((_game.get("cameras") as Array).size() == 2, "Mit der Wiederholung filmen zwei Drohnen.")
	info = _screen.call("describe", drone)
	_check(str(info["extra"]).contains("Zählt 2-fach durch die Wiederholung: 2 Kameras filmen."), "Die Kamera nennt die Wiederholung, war: " + str(info["extra"]))
	_check(str(info["extra"]).contains("Darauf wirken: %s, %s, %s" % [lens_name, battery_name, ItemDefs.display_name("replay")]), "Die Wiederholung steht bei dem, was auf die Kamera wirkt, war: " + str(info["extra"]))
	# Wiederholung ohne Ziel: Der Hinweis nennt Gegenstand und Kamera.
	_check(_put(replay, Vector2i(3, 3), 0), "Die Wiederholung liegt jetzt abseits.")
	info = _screen.call("describe", replay)
	_check(str(info["extra"]).contains("Stern auf einen Upgrade-Gegenstand oder eine Kamera legen."), "Die Wiederholung sagt, wohin ihr Stern darf, war: " + str(info["extra"]))
	_check((_game.get("cameras") as Array).size() == 1, "Ohne Wiederholung filmt wieder eine Drohne.")
	# Sendeleitung: ohne Sterne, wirkt auf jede Kamera.
	var uplink: int = pack.add_item("cam_uplink", 1)
	_check(pack.auto_place(uplink), "Die Sendeleitung passt in den Rucksack.")
	_game.call("sync_build")
	info = _screen.call("describe", uplink)
	_check(str(info["extra"]).contains("Wirkt auf eine Kamera."), "Die Sendeleitung nennt die Zahl der Kameras, war: " + str(info["extra"]))
	info = _screen.call("describe", drone)
	_check(str(info["extra"]).contains("Darauf wirken: %s, %s, %s" % [lens_name, battery_name, ItemDefs.display_name("cam_uplink")]), "Die Kamera nennt auch die Sendeleitung, war: " + str(info["extra"]))
	_check(str(info["extra"]).contains("Jetzt: Schaden 19,2 ·"), "Objektiv und Sendeleitung addieren sich (15 mal 1,28), war: " + str(info["extra"]))
	# Die Tafel folgt dem Zeiger auch auf einer Kamera und hebt ihr Zubehör hervor.
	_screen.call("set_pointer", _cell_center(Vector2i(1, 1)))
	_check((_screen.get("card_name_label") as Label).text == drone_name, "Die Karte zeigt die Kamera unter dem Zeiger.")
	_check(bool(_mark(lens, Vector2i(2, 1)).get("focus", false)), "Der Stern auf der Kamera unter dem Zeiger ist hervorgehoben.")
	_screen.call("set_pointer", Vector2(-40.0, -40.0))
	_check((_screen.get("help_text_label") as Label).text.contains("Kamera"), "Die Hilfe erwähnt die Kameras.")
	# Ohne Kamera im Raster wirkt das Zubehör nicht.
	_screen.call("pick_up", drone)
	_check(bool(_screen.call("drop_on_storage")), "Die Drohne geht in die Ablage.")
	_check((_game.get("cameras") as Array).is_empty(), "Ohne Kamera im Raster ist Game.cameras leer.")
	_check(str((_screen.call("describe", uplink) as Dictionary)["extra"]).contains("Wirkt gerade auf keine Kamera: Es liegt keine im Rucksack."), "Die Sendeleitung sagt, dass keine Kamera da ist.")
	_check(str((_screen.call("describe", lens) as Dictionary)["extra"]).contains("Wirkt gerade auf keine Kamera"), "Das Objektiv wirkt auf keine Kamera mehr.")
	_check(not _is_lit(lens, Vector2i(2, 1)), "Der Stern des Objektivs ist wieder leer.")
	# Die Werte-Zeile je Kameratyp.
	var tele: String = str(_screen.call("camera_stats_text", {"damage": 135.0, "interval": 2.6, "range": 30.0, "pierce": 2}))
	_check(tele == "Schaden 135 · alle 2,6 s · Reichweite 30 m · Durchschlag 2", "Die Tele-Kamera nennt den Durchschlag, war: " + tele)
	var slow: String = str(_screen.call("camera_stats_text", {"damage": 4.0, "interval": 1.5, "range": 12.0, "slow": 0.3, "second": 0.4}))
	_check(slow == "Schaden 4 · alle 1,5 s · Reichweite 12 m · Verlangsamung 30 % · zweites Ziel 40 %", "Die Zeitlupen-Kamera nennt Verlangsamung und zweites Ziel, war: " + slow)
	var director: String = str(_screen.call("camera_stats_text", {"damage": 0.0, "interval": 3.0, "range": 18.0, "mark": 0.2}))
	_check(director == "alle 3 s · Reichweite 18 m · Markierte nehmen 20 % mehr Schaden", "Die Regie-Kamera nennt den Mehr-Schaden und keinen eigenen Schaden, war: " + director)
	# Lange Texte (Regie-Kamera mit Wiederholung und Sendeleitung) passen auf die Karte.
	_fresh_open(41)
	pack = _pack()
	var cells: Array[Vector2i] = []
	for y: int in BackpackState.ROWS:
		for x: int in BackpackState.COLS:
			cells.append(Vector2i(x, y))
	pack.setup(cells)
	var regie: int = pack.add_item("cam_director", 4)
	var again: int = pack.add_item("replay", 3)
	var line: int = pack.add_item("cam_uplink", 1)
	_check(pack.place(regie, Vector2i(3, 3), 0) and pack.place(again, Vector2i(2, 3), 0) and pack.auto_place(line), "Aufbau: Regie-Kamera, Wiederholung und Sendeleitung liegen im Raster.")
	_game.call("sync_build")
	_screen.call("set_pointer", _cell_center(Vector2i(3, 3)))
	await process_frame
	await process_frame
	_check((_screen.get("card_name_label") as Label).text == ItemDefs.display_name("cam_director"), "Die Karte zeigt die Regie-Kamera.")
	info = _screen.call("describe", regie)
	_check(str(info["extra"]).contains("Markierte nehmen 40 % mehr Schaden") and str(info["extra"]).contains("Zählt 2-fach"), "Die Regie-Kamera nennt Markierung und Wiederholung, war: " + str(info["extra"]))
	_check(not str(info["extra"]).contains("Schaden 0"), "Die Regie-Kamera nennt keinen eigenen Schaden.")
	var max_height: float = float((_screen.get_script() as GDScript).get_script_constant_map().get("CARD_MAX_HEIGHT", 0.0))
	var card_rect: Rect2 = _screen.call("card_rect")
	_check(max_height > 0.0 and card_rect.size.y <= max_height + 0.5, "Die Karte mit dem langen Text bleibt unter ihrer größten Höhe (%d von %d)." % [roundi(card_rect.size.y), roundi(max_height)])
	_check(_board_rect().encloses(card_rect), "Die Karte mit dem langen Text liegt ganz im Bild.")
	_check(_card_parts_fit(), "Alle Zeilen der Karte liegen untereinander in der Karte.")
	_check((_screen.get("card_text_label") as Label).get_theme_font_size("font_size") >= 12, "Die Schrift der Karte bleibt lesbar groß.")
	_check(_card_has_all(regie), "Auch die lange Karte enthält alles aus describe.")
	_screen.call("set_pointer", Vector2(-40.0, -40.0))
	await process_frame
	await process_frame


## Namenszeile am unteren Rand eines Gegenstands im Raster (Taste N): Fläche und Umbruch für
## jeden Gegenstand in beiden Lagen.
func _test_names(script: GDScript) -> void:
	var hyphens: Dictionary = script.get_script_constant_map().get("NAME_HYPHENS", {})
	var font: Font = (load("res://scripts/ui/hud.gd") as GDScript).call("show_font") as Font
	var cell: float = float(script.get_script_constant_map().get("CELL", 64.0))
	var band: float = float(script.get_script_constant_map().get("NAME_BAND_MAX", 0.0))
	_check(cell >= 80.0, "Die Felder des Rucksacks sind groß (CELL = %d)." % roundi(cell))
	_check(band > 0.0 and band <= cell * 0.3, "Die Namenszeile ist ein schmaler Streifen (höchstens %d Pixel)." % roundi(band))
	for id: String in ItemDefs.ORDER:
		var weapon: bool = ItemDefs.is_weapon(id)
		# Gemessen wird die Fläche, in die der Bildschirm den Namen wirklich setzt (name_area), in
		# beiden Lagen: quer und hochkant.
		for rot: int in 2:
			var area: Rect2 = _screen.call("name_area", id, rot, Vector2.ZERO, cell)
			var shape_box: Rect2 = Rect2(Vector2.ZERO, Vector2(ItemDefs.size(id, rot)) * cell)
			_check(area.size.x >= cell - 20.0 and area.size.y <= band + 0.5, "Die Namenszeile von %s ist breit genug und schmal (%d x %d)." % [id, roundi(area.size.x), roundi(area.size.y)])
			_check(shape_box.encloses(area) and area.end.y > shape_box.end.y - cell * 0.15, "Die Namenszeile von %s liegt am unteren Rand seiner Form." % id)
			var covered: bool = true
			for corner: Vector2 in [area.position + Vector2(1.0, 1.0), area.end - Vector2(1.0, 1.0)]:
				if not ItemDefs.cells(id, rot).has(Vector2i(int(corner.x / cell), int(corner.y / cell))):
					covered = false
			_check(covered, "Die Namenszeile von %s liegt auf Feldern der Form (Drehung %d)." % [id, rot])
			var layout: Dictionary = _screen.call("name_layout", id, area.size.x, area.size.y)
			var lines: PackedStringArray = layout["lines"]
			_check(not lines.is_empty() and not str(lines[0]).is_empty(), "Der Name von %s wird gesetzt." % id)
			var fits: bool = true
			for line: String in lines:
				if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(layout["size"])).x > area.size.x + 0.5:
					fits = false
			_check(fits, "Jede Zeile des Namens von %s passt in die Breite, war: %s" % [id, " / ".join(lines)])
			_check(lines.size() <= 2 and float(lines.size()) * float(layout["line_height"]) <= area.size.y + 0.5, "Der Name von %s braucht höchstens zwei kleine Zeilen, waren %d." % [id, lines.size()])
			_check(int(layout["size"]) >= 9, "Die Schrift der Namenszeile von %s bleibt lesbar (%d)." % [id, int(layout["size"])])
			if not weapon:
				_check(not "".join(lines).contains("…"), "Der Name von %s passt ungekürzt in seine Zeile (Drehung %d), war: %s" % [id, rot, " / ".join(lines)])
		if weapon:
			# Die Namen der Waffen gehören dem Waffen-Modul und können sich ändern: Ein Eintrag mit
			# Trennstellen ist freiwillig, ohne ihn wird an Bindestrich und Leerzeichen getrennt.
			continue
		_check(hyphens.has(id), "Für %s gibt es Trennstellen." % id)
		_check(str(hyphens.get(id, "")).replace("|", "").replace("'", "") == ItemDefs.display_name(id), "Die Trennstellen von %s passen zum Namen." % id)
	# Ein Name ohne passende Trennstellen wird nur an Bindestrich und Leerzeichen getrennt und
	# notfalls gekürzt statt übergelaufen.
	var narrow: Dictionary = _screen.call("name_layout", "corpse_explosion", 30.0, 12.0)
	_check((narrow["lines"] as PackedStringArray).size() == 1 and str((narrow["lines"] as PackedStringArray)[0]).ends_with("…"),
		"Was nicht passt, wird mit Auslassungszeichen gekürzt.")
	var unknown: Dictionary = _screen.call("name_layout", "kein_gegenstand", cell * 2.0, cell)
	_check("".join(unknown["lines"] as PackedStringArray) == "kein_gegenstand", "Ein Name ohne Trennstellen bleibt ganz, wenn er passt.")


## Anordnung: Regal links, Rucksack waagerecht in der Bildmitte (klein und voll), nur vorhandene
## Felder gezeichnet, mögliche Felder erst mit einem Rucksack-Teil in der Hand.
func _test_layout() -> void:
	_fresh_open(50)
	var pack: BackpackState = _pack()
	var board: Control = _screen.get("board") as Control
	var stage: Rect2 = _board_rect()
	var view: Vector2 = root.get_visible_rect().size
	_check(stage.size.x <= view.x and stage.size.y <= view.y, "Die Bühne passt ins Bild (%d x %d in %d x %d)." % [roundi(stage.size.x), roundi(stage.size.y), roundi(view.x), roundi(view.y)])
	_check((board.get_global_rect().get_center() - view * 0.5).length() <= 1.0, "Die Bühne liegt mittig im Bild.")
	var shelf: Rect2 = _screen.call("storage_area")
	var small: Rect2 = _screen.call("pack_rect")
	var sell: Rect2 = _screen.call("sell_rect")
	_check(pack.cell_count() == 12 and is_equal_approx(small.size.x, 4.0 * (_screen.call("cell_rect", Vector2i.ZERO) as Rect2).size.x),
		"Der Start-Rucksack ist vier Felder breit.")
	_check(shelf.end.x < small.position.x, "Das Regal liegt links vom Rucksack.")
	_check(shelf.position.x <= 1.0 and shelf.size.y > shelf.size.x * 2.0, "Das Regal steht hoch und schmal am linken Rand.")
	_check(stage.encloses(shelf), "Das Regal liegt ganz im Bild.")
	_check(absf(small.get_center().x - stage.size.x * 0.5) <= 1.0, "Der kleine Rucksack liegt waagerecht in der Mitte der Bühne, Mitte bei %d." % roundi(small.get_center().x))
	_check(absf(board.get_global_rect().position.x + small.get_center().x - view.x * 0.5) <= 1.0, "Der kleine Rucksack liegt waagerecht in der Bildmitte.")
	# Nur die vorhandenen Felder werden gezeichnet.
	var drawn: Array[Vector2i] = _screen.call("drawn_cells")
	var all_real: bool = drawn.size() == pack.cell_count()
	for cell: Vector2i in drawn:
		if not pack.has_cell(cell):
			all_real = false
	_check(all_real and drawn.size() < BackpackState.COLS * BackpackState.ROWS, "Gezeichnet werden genau die zwölf vorhandenen Felder, waren %d." % drawn.size())
	_check((_screen.call("ghost_cells") as Array).is_empty(), "Ohne Rucksack-Teil in der Hand gibt es keine blassen Felder.")
	# Mit einem gewöhnlichen Gegenstand in der Hand auch nicht.
	var luck: int = pack.add_item("luck", 1)
	_screen.call("pick_up", luck)
	_check((_screen.call("ghost_cells") as Array).is_empty(), "Ein gewöhnlicher Gegenstand in der Hand zeigt keine neuen Felder.")
	_screen.call("cancel_hold")
	# Mit einem Rucksack-Teil in der Hand: die Felder, die es neu anlegen könnte.
	var bag: int = pack.add_item("bag_small", 1)
	_screen.call("pick_up", bag)
	var ghosts: Array[Vector2i] = _screen.call("ghost_cells")
	var ghosts_ok: bool = not ghosts.is_empty()
	for cell: Vector2i in ghosts:
		if pack.has_cell(cell) or not BackpackState.in_bounds(cell) or not stage.encloses(_screen.call("cell_rect", cell) as Rect2):
			ghosts_ok = false
	_check(ghosts_ok, "Mit einem Rucksack-Teil in der Hand zeigen sich mögliche neue Felder im Bild, waren %d." % ghosts.size())
	_check(ghosts.has(Vector2i(0, 1)) and ghosts.has(Vector2i(5, 1)) and ghosts.has(Vector2i(1, 0)), "Die möglichen Felder liegen rund um den Rucksack.")
	_check((_screen.call("drawn_cells") as Array).size() == 12, "Die möglichen Felder zählen nicht zu den gezeichneten Feldern des Rucksacks.")
	_screen.call("cancel_hold")
	_check((_screen.call("ghost_cells") as Array).is_empty(), "Nach dem Zurücklegen sind die blassen Felder weg.")
	# Das große Rucksack-Teil passt nur dorthin, wo zwei Zeilen oder Spalten frei sind.
	var big_bag: int = pack.add_item("bag_medium", 1)
	_screen.call("pick_up", big_bag)
	ghosts = _screen.call("ghost_cells")
	_check(not ghosts.is_empty() and not ghosts.has(Vector2i(0, 1)) and ghosts.has(Vector2i(5, 1)) and ghosts.has(Vector2i(6, 1)),
		"Blass sind nur Felder, auf die das gehaltene Teil wirklich passt.")
	_screen.call("cancel_hold")
	# Der Rucksack wächst nach rechts: Er rückt wieder in die Mitte.
	_check(_put(bag, Vector2i(5, 1), 0) and pack.has_cell(Vector2i(6, 1)), "Der Jutebeutel verlängert den Rucksack nach rechts.")
	var grown: Rect2 = _screen.call("pack_rect")
	_check(grown.size.x > small.size.x and absf(grown.get_center().x - stage.size.x * 0.5) <= 1.0, "Der gewachsene Rucksack liegt wieder in der Mitte, Mitte bei %d." % roundi(grown.get_center().x))
	_check((_screen.call("drawn_cells") as Array).size() == 14, "Die neuen Felder werden jetzt gezeichnet.")
	# Volles Raster: ganz im Bild, in der Mitte, neben Regal und Verkaufsfeld.
	_full_raster()
	var full: Rect2 = _screen.call("pack_rect")
	var grid: Rect2 = _screen.call("grid_rect")
	_check(full.is_equal_approx(grid) and (_screen.call("drawn_cells") as Array).size() == BackpackState.COLS * BackpackState.ROWS, "Der volle Rucksack füllt das ganze Raster.")
	_check(absf(full.get_center().x - stage.size.x * 0.5) <= 1.0, "Der volle Rucksack liegt waagerecht in der Mitte, Mitte bei %d." % roundi(full.get_center().x))
	_check(absf(board.get_global_rect().position.x + full.get_center().x - view.x * 0.5) <= 1.0, "Der volle Rucksack liegt waagerecht in der Bildmitte.")
	_check(stage.encloses(full.grow(10.0)), "Der volle Rucksack liegt mit seinem Rahmen ganz im Bild.")
	_check(is_equal_approx(full.size.x / float(BackpackState.COLS), small.size.x / 4.0), "Die Felder sind im kleinen und im vollen Rucksack gleich groß.")
	_check(shelf.end.x < full.position.x - 10.0, "Auch der volle Rucksack lässt das Regal frei.")
	_check(not full.grow(10.0).intersects(sell), "Der volle Rucksack lässt das Verkaufsfeld frei.")
	# Verkaufsfeld: kleiner als früher (260 x 120) und rechts unten.
	_check(sell.get_area() < 260.0 * 120.0 * 0.75, "Das Verkaufsfeld ist deutlich kleiner als früher.")
	_check(sell.get_center().x > full.end.x and sell.get_center().y > stage.size.y * 0.6 and stage.encloses(sell), "Das Verkaufsfeld sitzt rechts unten im Bild.")
	# Die drei Felder: gleich groß, übereinander rechts unten, gut lesbar, neben dem vollen Rucksack.
	var repair: Rect2 = _screen.call("repair_rect")
	var scrap: Rect2 = _screen.call("scrap_rect")
	_check(repair.size.is_equal_approx(scrap.size) and scrap.size.is_equal_approx(sell.size) and sell.size.x >= 200.0 and sell.size.y >= 44.0,
		"Die drei Felder sind gleich groß und groß genug zum Lesen (%d x %d)." % [roundi(sell.size.x), roundi(sell.size.y)])
	_check(is_equal_approx(repair.position.x, scrap.position.x) and is_equal_approx(scrap.position.x, sell.position.x)
		and repair.end.y <= scrap.position.y and scrap.end.y <= sell.position.y, "Reparieren, Verschrotten und Verkaufen stehen übereinander.")
	_check(stage.encloses(repair) and stage.encloses(scrap) and repair.position.x > full.end.x + 10.0 and repair.position.y > stage.size.y * 0.5,
		"Die drei Felder sitzen rechts unten neben dem vollen Rucksack.")
	_check(int(_screen.call("action_at", repair.get_center())) == 1 and int(_screen.call("action_at", scrap.get_center())) == 2
		and int(_screen.call("action_at", sell.get_center())) == 3 and int(_screen.call("action_at", full.get_center())) == 0, "action_at kennt die drei Felder.")
	for pair: Array in [["repair_title_label", "repair_value_label", repair], ["scrap_title_label", "scrap_value_label", scrap], ["sell_title_label", "sell_value_label", sell]]:
		var title_box: Rect2 = _box(_screen.get(str(pair[0])) as Control)
		var value_box: Rect2 = _box(_screen.get(str(pair[1])) as Control)
		var title: Label = _screen.get(str(pair[0])) as Label
		_check((pair[2] as Rect2).encloses(title_box) and (pair[2] as Rect2).encloses(value_box) and title_box.end.y <= value_box.position.y + 4.0,
			"Titel und Zeile von %s liegen im Feld untereinander." % title.text)
		_check(title.get_theme_font_size("font_size") >= 13 and title.get_minimum_size().x <= title_box.size.x + 0.5, "Der Titel %s passt lesbar in sein Feld." % title.text)
	# Leisten: oben Titel links, Hände über dem Rucksack, Punkte rechts. Unten Hinweise, Warnung, FERTIG.
	var headline: Control = (_screen.get("headline_label") as Label).get_parent() as Control
	var hands: Rect2 = _box(_screen.get("hands_label") as Control)
	var points: Rect2 = _box(_screen.get("points_label") as Control)
	var help: Rect2 = _box(_screen.get("help_button") as Control)
	var done: Rect2 = _box(_screen.get("done_button") as Control)
	var hint: Rect2 = _box(_screen.get("hint_label") as Control)
	var warning: Rect2 = _box(_warning())
	var stats: Rect2 = _box(_screen.get("stats_label") as Control)
	var material: Rect2 = _box(_screen.get("material_label") as Control)
	_check(material.end.y <= full.position.y and material.position.x > hands.end.x and material.end.x <= points.position.x,
		"Das Material steht in der oberen Leiste zwischen Händen und Punkten.")
	_check(headline.position.x < shelf.end.x and headline.position.y < full.position.y, "Der Titel steht oben links.")
	_check((_screen.get("headline_label") as Label).get_theme_font_size("font_size") < 44, "Der Titel ist kleiner als früher.")
	_check(hands.end.y <= full.position.y and hands.position.x > shelf.end.x and hands.end.x < points.position.x, "Die Hände stehen oben über dem Rucksack, zwischen Titel und Punkten.")
	_check(points.end.y <= full.position.y and points.get_center().x > full.get_center().x and help.position.x >= points.end.x, "Punkte und Hilfe-Knopf stehen oben rechts.")
	_check(done.position.y >= full.end.y and hint.position.y >= full.end.y and warning.position.y >= full.end.y, "Hinweise, Warnung und FERTIG stehen in der unteren Leiste.")
	_check(hint.end.x <= done.position.x and warning.end.x <= done.position.x and warning.intersects(hint), "In der unteren Leiste stehen links die Hinweise (an ihrer Stelle die Warnung), rechts FERTIG.")
	var hint_node: Label = _screen.get("hint_label") as Label
	_check(hint_node.visible and not _warning().visible, "Ohne Warnung sind die Hinweise zu sehen.")
	_screen.call("_show_notice", "Probe")
	_check(not hint_node.visible and _warning().visible and _warning().text == "Probe", "Solange eine Warnung steht, sind die Hinweise ausgeblendet.")
	_screen.call("_process", float(_constant("NOTICE_TIME")) + 0.1)
	_check(hint_node.visible and not _warning().visible, "Danach stehen die Hinweise wieder da.")
	_check(stats.position.y >= full.end.y and stats.end.y <= hint.position.y + 2.0, "Die Zeile mit freien Feldern und Händen steht unter dem Rucksack.")
	var hand_boxes_end: float = float((_constant("HAND_BOX_ORIGIN") as Vector2).x) + 2.0 * float((_constant("HAND_BOX_SIZE") as Vector2).x) + float(_constant("HAND_BOX_GAP"))
	_check(hand_boxes_end <= float((_constant("MATERIAL_RECT") as Rect2).position.x), "Die Kästen der Hände enden vor dem Material.")
	var boxes: Array[Rect2] = [shelf, full.grow(10.0), repair, scrap, sell, hands, material, points, help, done, hint, stats]
	_check(stage.encloses(warning) and not warning.intersects(done) and not warning.intersects(stats), "Die Warnung liegt im Bild neben FERTIG und unter der Zeile mit den freien Feldern.")
	var overlap: bool = false
	for i: int in boxes.size():
		if not stage.encloses(boxes[i]):
			overlap = true
		for k: int in range(i + 1, boxes.size()):
			if boxes[i].intersects(boxes[k]):
				overlap = true
	_check(not overlap, "Regal, Rucksack, die drei Felder und die Texte der Leisten liegen im Bild und überlappen sich nicht.")


## Regal: Die Gegenstände der Ablage liegen untereinander in ihrer echten Form, die neuesten
## oben, immer mit gleich großen Feldern und mit ihrem Namen.
func _test_shelf() -> void:
	_fresh_open(51)
	var pack: BackpackState = _pack()
	var area: Rect2 = _screen.call("storage_area")
	var view: Rect2 = _screen.call("shelf_view")
	var label: Label = _screen.get("storage_label") as Label
	var done: Button = _screen.get("done_button") as Button
	var shelf_cell: float = float(_constant("SHELF_CELL"))
	_check(_layout().is_empty() and label.text == "ABLAGE 0", "Das leere Regal hat keine Zeilen, war: " + label.text)
	_check(area.encloses(view) and view.size.y > 300.0 and view.size.x >= 5.0 * shelf_cell, "Der sichtbare Teil des Regals liegt im Regal und fasst fünf Felder nebeneinander.")
	_check((_screen.call("shelf_bar") as Dictionary).is_empty() and is_zero_approx(float(_screen.call("shelf_scroll_max"))), "Das leere Regal hat keinen Rollbalken.")
	var revolver: int = pack.add_item("revolver", 1)
	var luck: int = pack.add_item("luck", 2)
	var sniper: int = pack.add_item("sniper", 1)
	var shield: int = pack.add_item("shield", 3)
	_game.call("sync_build")
	_check(label.text == "ABLAGE 4", "Die Überschrift zählt die Ablage, war: " + label.text)
	var layout: Array[Dictionary] = _layout()
	_check(layout.size() == 4 and int(layout[0]["uid"]) == shield and int(layout[1]["uid"]) == sniper and int(layout[2]["uid"]) == luck and int(layout[3]["uid"]) == revolver,
		"Das Regal hat eine Zeile je Gegenstand, die neuesten oben.")
	_check(_shelf_ok(layout, view), "Die Zeilen liegen untereinander im Regal und überdecken sich nicht.")
	# Echte Form: Jede Zeile nennt Gegenstand, Drehung und Rarität, die Form passt mit ihren Feldern hinein.
	var shapes_ok: bool = true
	for row: Dictionary in layout:
		var entry: Dictionary = pack.item(int(row["uid"]))
		if str(row["id"]) != str(entry["id"]) or int(row["rot"]) != int(entry["rot"]) or int(row["level"]) != int(entry["level"]) or bool(row["broken"]):
			shapes_ok = false
		var cell: float = float(row["cell"])
		var extent: Vector2i = ItemDefs.size(str(row["id"]), int(row["rot"]))
		var shape_box: Rect2 = Rect2(row["origin"] as Vector2, Vector2(extent) * cell)
		if not is_equal_approx(cell, shelf_cell) or not (row["rect"] as Rect2).grow(0.5).encloses(shape_box) or not bool(row["visible"]):
			shapes_ok = false
		if (row["name_rect"] as Rect2).size.x <= 0.0 or (row["name_rect"] as Rect2).intersects(shape_box.grow(-0.5)):
			shapes_ok = false
	_check(shapes_ok, "Jeder Gegenstand liegt im Regal in seiner echten Form mit Rarität, der Name steht daneben oder darunter.")
	_check(ItemDefs.cells("revolver", 0).size() == 3 and ItemDefs.size("revolver", 0) == Vector2i(2, 2)
		and (layout[3]["rect"] as Rect2).size.y >= 2.0 * shelf_cell - 0.5, "Der Revolver (L-Form) ist im Regal zwei Felder hoch.")
	_check((layout[1]["rect"] as Rect2).size.y < (layout[3]["rect"] as Rect2).size.y, "Das Scharfschützengewehr (eine Zeile hoch) braucht weniger Höhe als der Revolver.")
	_check(float(layout[1]["cell"]) * 5.0 <= view.size.x, "Auch die fünf Felder breite Waffe passt in die Breite des Regals.")
	_check(int(_screen.call("item_at", (layout[1]["rect"] as Rect2).get_center())) == sniper and (_screen.call("item_rect", sniper) as Rect2).is_equal_approx(layout[1]["rect"] as Rect2),
		"item_at und item_rect kennen die Zeile im Regal.")
	_check((_screen.call("storage_rect", 3) as Rect2).is_equal_approx(layout[3]["rect"] as Rect2), "storage_rect liefert die Zeile aus shelf_layout.")
	var free_row: Rect2 = _screen.call("storage_rect", 4)
	_check(free_row.position.y >= (layout[3]["rect"] as Rect2).end.y and int(_screen.call("item_at", free_row.get_center())) == -1, "Hinter der letzten Zeile nennt storage_rect die nächste freie Zeile.")
	# Ein neuer Gegenstand steht oben, die anderen rücken nach unten.
	var fresh: int = pack.add_item("snack", 1)
	_game.call("sync_build")
	layout = _layout()
	_check(int(layout[0]["uid"]) == fresh and is_equal_approx((layout[0]["rect"] as Rect2).position.y, view.position.y) and int(layout[1]["uid"]) == shield,
		"Ein neuer Gegenstand steht ganz oben im Regal.")
	_screen.call("pick_up", fresh)
	_check(bool(_screen.call("drop_on_sell")), "Der neue Gegenstand lässt sich verkaufen.")
	# Gedreht abgelegt: Die Form liegt auch im Regal gedreht.
	_screen.call("pick_up", sniper)
	_screen.call("rotate_held")
	_check(bool(_screen.call("drop_on_storage")), "Das gedrehte Gewehr geht zurück in die Ablage.")
	layout = _layout()
	var turned: Dictionary = {}
	for row: Dictionary in layout:
		if int(row["uid"]) == sniper:
			turned = row
	_check(int(turned.get("rot", -1)) == 1 and (turned["rect"] as Rect2).size.y >= 5.0 * float(turned["cell"]) - 0.5, "Hochkant abgelegt ist es im Regal fünf Felder hoch.")
	_check(is_equal_approx(float(turned["cell"]), shelf_cell), "Auch die hohe Form hat Felder in der festen Größe.")
	_check(not _warning().visible and is_equal_approx(done.modulate.a, 1.0), "Es gibt keine Warnung und FERTIG ist frei.")
	# Jede Form passt in die Breite des Regals, jeder Name ungekürzt neben oder unter seine Form.
	var cut: PackedStringArray = PackedStringArray()
	var wide: PackedStringArray = PackedStringArray()
	for id: String in ItemDefs.ORDER:
		pack.setup(pack.cells())
		pack.add_item(id, 1)
		var row: Dictionary = _layout()[0]
		var name_rect: Rect2 = row["name_rect"]
		var name_lines: PackedStringArray = (_screen.call("name_layout", id, name_rect.size.x, name_rect.size.y,
				int(_constant("SHELF_NAME_FONT_SIZE")), int(_constant("SHELF_NAME_MIN_FONT_SIZE"))) as Dictionary)["lines"]
		if "".join(name_lines).contains("…") or not view.encloses(name_rect):
			cut.append(id)
		for rot: int in 2:
			if float(ItemDefs.size(id, rot).x) * shelf_cell > view.size.x + 0.5:
				wide.append(id)
	_check(cut.is_empty(), "Im Regal passt jeder Name ungekürzt neben oder unter seine Form, gekürzt: " + ", ".join(cut))
	_check(wide.is_empty(), "Jede Form passt in beiden Lagen in die Breite des Regals, zu breit: " + ", ".join(wide))
	_game.call("sync_build")


## Liegen alle Zeilen eines Regal-Aufbaus im Regal, von oben nach unten und ohne sich zu überdecken?
func _shelf_ok(layout: Array[Dictionary], area: Rect2) -> bool:
	var bottom: float = area.position.y
	for row: Dictionary in layout:
		var rect: Rect2 = row["rect"]
		if not area.encloses(rect) or rect.position.y < bottom - 0.01 or rect.size.y <= 0.0:
			return false
		bottom = rect.end.y
	return true


## Rollen des Regals: 30 Gegenstände ohne Schrumpfen, Mausrad, Rollbalken, von selbst beim
## Ziehen an den Rand, alles bleibt erreichbar, FERTIG nie gesperrt.
func _test_shelf_scroll() -> void:
	_fresh_open(52)
	var pack: BackpackState = _pack()
	var view: Rect2 = _screen.call("shelf_view")
	var area: Rect2 = _screen.call("storage_area")
	var done: Button = _screen.get("done_button") as Button
	var shelf_cell: float = float(_constant("SHELF_CELL"))
	var wheel_step: float = float(_constant("SHELF_WHEEL_STEP"))
	var ids: Array[String] = ["luck", "snack", "frost", "mine", "burn", "scope", "rifle", "minigun", "bag_large", "revive",
			"pistol", "crit", "dash", "poison", "thorns", "sniper", "drone", "cam_tele", "shield", "lifesteal",
			"max_hp", "cam_director", "revolver", "spotlight", "piggy_bank", "replay", "shotgun", "smg", "jammer", "disco_ball"]
	var uids: Array[int] = []
	for i: int in ids.size():
		# Gemischt: Jeder dritte ist kaputt.
		uids.append(pack.add_item(ids[i], 1 + i % 5, i % 3 == 0))
	_game.call("sync_build")
	var layout: Array[Dictionary] = _layout()
	_check(pack.storage_items().size() == 30 and layout.size() == 30 and (_screen.get("storage_label") as Label).text == "ABLAGE 30",
		"Dreißig Gegenstände liegen in der Ablage, die Überschrift zählt sie.")
	# Nichts schrumpft: gleiche Feldgröße, jeder hat seinen Namen, die Reihenfolge ist neu vor alt.
	var steady: bool = true
	var ordered: bool = true
	var bottom: float = -100000.0
	for i: int in layout.size():
		var row: Dictionary = layout[i]
		var name_rect: Rect2 = row["name_rect"]
		var shape_box: Rect2 = Rect2(row["origin"] as Vector2, Vector2(ItemDefs.size(str(row["id"]), int(row["rot"]))) * float(row["cell"]))
		if not is_equal_approx(float(row["cell"]), shelf_cell) or name_rect.size.x < 40.0 or name_rect.size.y < 12.0 or name_rect.intersects(shape_box.grow(-0.5)):
			steady = false
		if int(row["uid"]) != uids[uids.size() - 1 - i] or (row["rect"] as Rect2).position.y < bottom - 0.01:
			ordered = false
		if bool(row["broken"]) != pack.is_broken(int(row["uid"])):
			steady = false
		bottom = (row["rect"] as Rect2).end.y
	_check(steady, "Alle dreißig haben dieselbe Feldgröße (%d), ihren Namen und das Zeichen kaputt oder heil." % roundi(shelf_cell))
	_check(ordered, "Die Zeilen stehen untereinander, die neuesten oben, und überdecken sich nicht.")
	# Der Inhalt ist höher als das Regal: Es rollt.
	var content: float = float(_screen.call("shelf_content_height"))
	var limit: float = float(_screen.call("shelf_scroll_max"))
	_check(content > view.size.y * 2.0 and is_equal_approx(limit, content - view.size.y), "Dreißig Gegenstände sind höher als das Regal (%d von %d Pixeln)." % [roundi(content), roundi(view.size.y)])
	_check(is_zero_approx(float(_screen.call("shelf_scroll"))), "Anfangs steht das Regal ganz oben.")
	_check(bool(layout[0]["visible"]) and is_equal_approx((layout[0]["rect"] as Rect2).position.y, view.position.y), "Die neueste Zeile ist oben zu sehen.")
	_check(not bool(layout[29]["visible"]) and (layout[29]["rect"] as Rect2).position.y > view.end.y, "Die älteste Zeile liegt unter dem sichtbaren Teil.")
	_check(int(_screen.call("item_at", Vector2(view.get_center().x, (layout[29]["rect"] as Rect2).get_center().y))) == -1, "Was hinausgerollt ist, lässt sich nicht anfassen.")
	# Rollbalken: sichtbar, Griff oben in der Bahn.
	var bar: Dictionary = _screen.call("shelf_bar")
	_check(not bar.is_empty(), "Mit dreißig Gegenständen hat das Regal einen Rollbalken.")
	if not bar.is_empty():
		var track: Rect2 = bar["track"]
		var thumb: Rect2 = bar["thumb"]
		_check(area.encloses(track) and track.position.x >= view.end.x and track.size.x >= 6.0 and is_equal_approx(track.size.y, view.size.y), "Die Bahn des Rollbalkens steht rechts neben den Zeilen.")
		_check(track.encloses(thumb) and is_equal_approx(thumb.position.y, track.position.y) and thumb.size.y < track.size.y * 0.5 and thumb.size.y >= 20.0, "Der Griff steht oben und ist gut zu greifen.")
	# Mausrad über dem Regal.
	var over_shelf: Vector2 = view.get_center()
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, over_shelf))
	_check(is_equal_approx(float(_screen.call("shelf_scroll")), wheel_step), "Das Mausrad rollt das Regal um einen Schritt nach unten, war %d." % roundi(float(_screen.call("shelf_scroll"))))
	_check(is_equal_approx((_layout()[0]["rect"] as Rect2).position.y, view.position.y - wheel_step), "Die Zeilen wandern mit.")
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, over_shelf))
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_WHEEL_UP, true, over_shelf))
	_check(is_equal_approx(float(_screen.call("shelf_scroll")), wheel_step), "Das Mausrad rollt auch wieder nach oben.")
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, _cell_center(Vector2i(2, 2))))
	_check(is_equal_approx(float(_screen.call("shelf_scroll")), wheel_step), "Das Mausrad neben dem Regal rollt es nicht.")
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_WHEEL_UP, true, over_shelf))
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_WHEEL_UP, true, over_shelf))
	_check(is_zero_approx(float(_screen.call("shelf_scroll"))), "Über den Anfang hinaus rollt nichts.")
	# Ganz nach unten: Die älteste Zeile ist zu sehen, das Ende schließt mit dem Regal ab.
	_screen.call("scroll_shelf", 100000.0)
	layout = _layout()
	_check(is_equal_approx(float(_screen.call("shelf_scroll")), limit), "Über das Ende hinaus rollt nichts.")
	_check(bool(layout[29]["visible"]) and absf((layout[29]["rect"] as Rect2).end.y - view.end.y) <= 0.5 and not bool(layout[0]["visible"]), "Ganz unten ist die älteste Zeile zu sehen, die neueste nicht.")
	bar = _screen.call("shelf_bar")
	_check(absf((bar["thumb"] as Rect2).end.y - (bar["track"] as Rect2).end.y) <= 0.5, "Der Griff steht dann unten.")
	# Jeder der dreißig ist erreichbar: hinrollen, anfassen.
	var reachable: bool = true
	for uid: int in uids:
		var center: Vector2 = _row_center(uid)
		var rect: Rect2 = _screen.call("item_rect", uid)
		if not view.grow(0.5).encloses(rect) or int(_screen.call("item_at", center)) != uid:
			reachable = false
	_check(reachable, "Jeder der dreißig Gegenstände lässt sich ins Bild rollen und anfassen.")
	_check(not bool(_screen.call("scroll_to_item", 99999)), "Zu einem unbekannten Gegenstand rollt nichts.")
	# Rollbalken mit der Maus: Klick unten in die Bahn rollt ans Ende, Ziehen nach oben an den Anfang.
	_screen.call("set_shelf_scroll", 0.0)
	bar = _screen.call("shelf_bar")
	var bar_track: Rect2 = bar["track"]
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(bar_track.get_center().x, bar_track.end.y - 2.0)))
	_check(is_equal_approx(float(_screen.call("shelf_scroll")), limit) and _held() == -1, "Ein Klick unten in die Bahn rollt ans Ende und greift nichts.")
	_screen.call("_on_board_input", _mouse_motion(Vector2(bar_track.get_center().x, bar_track.get_center().y)))
	var half: float = float(_screen.call("shelf_scroll"))
	_check(half > limit * 0.3 and half < limit * 0.7, "Ziehen am Griff rollt mit (Mitte der Bahn: %d von %d)." % [roundi(half), roundi(limit)])
	_screen.call("_on_board_input", _mouse_motion(Vector2(bar_track.get_center().x, bar_track.position.y - 30.0)))
	_check(is_zero_approx(float(_screen.call("shelf_scroll"))), "Ziehen über den Anfang der Bahn rollt ganz nach oben.")
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(bar_track.get_center().x, bar_track.position.y)))
	_screen.call("_on_board_input", _mouse_motion(Vector2(bar_track.get_center().x, bar_track.end.y)))
	_check(is_zero_approx(float(_screen.call("shelf_scroll"))), "Nach dem Loslassen folgt der Griff der Maus nicht mehr.")
	# Von selbst rollen: Ein gehaltener Gegenstand am unteren Rand des Regals rollt es nach unten.
	_pointer_away()
	_screen.call("_process", 0.2)
	_check(is_zero_approx(float(_screen.call("shelf_scroll"))), "Ohne gehaltenen Gegenstand rollt nichts von selbst.")
	_screen.call("set_pointer", Vector2(view.get_center().x, view.end.y - 4.0))
	_screen.call("_process", 0.2)
	_check(is_zero_approx(float(_screen.call("shelf_scroll"))), "Der Zeiger allein am Rand rollt nichts.")
	_check(bool(_screen.call("pick_up", uids[29])), "Der oberste Gegenstand lässt sich greifen.")
	_screen.call("set_pointer", view.get_center())
	_screen.call("_process", 0.2)
	_check(is_zero_approx(float(_screen.call("shelf_scroll"))), "Mitten im Regal rollt beim Halten nichts.")
	_screen.call("set_pointer", Vector2(view.get_center().x, view.end.y - 4.0))
	_screen.call("_process", 0.2)
	var pulled: float = float(_screen.call("shelf_scroll"))
	_check(pulled > 20.0, "Am unteren Rand rollt das Regal beim Halten von selbst nach unten (%d Pixel)." % roundi(pulled))
	_screen.call("_process", 0.2)
	_check(float(_screen.call("shelf_scroll")) > pulled, "Solange der Gegenstand dort bleibt, rollt es weiter.")
	pulled = float(_screen.call("shelf_scroll"))
	_screen.call("set_pointer", Vector2(view.get_center().x, view.position.y + 4.0))
	_screen.call("_process", 0.1)
	_check(float(_screen.call("shelf_scroll")) < pulled, "Am oberen Rand rollt es wieder nach oben.")
	_screen.call("set_pointer", Vector2(_cell_center(Vector2i(2, 2)).x, view.end.y - 4.0))
	pulled = float(_screen.call("shelf_scroll"))
	_screen.call("_process", 0.2)
	_check(is_equal_approx(float(_screen.call("shelf_scroll")), pulled), "Neben dem Regal rollt nichts von selbst.")
	_screen.call("cancel_hold")
	# Ein Gegenstand aus dem Raster in die Ablage: Das Regal rollt zu ihm.
	var old_item: int = uids[4]
	_check(not pack.is_broken(old_item) and _put(old_item, pack.cells()[0], 0), "Ein alter Gegenstand von weit unten liegt im Raster.")
	_screen.call("set_shelf_scroll", 0.0)
	_screen.call("pick_up", old_item)
	_check(bool(_screen.call("drop_on_storage")), "Er geht zurück in die Ablage.")
	_check(view.grow(0.5).encloses(_screen.call("item_rect", old_item) as Rect2) and float(_screen.call("shelf_scroll")) > 0.0, "Das Regal rollt so, dass er zu sehen ist.")
	# Verkaufen und Einräumen: Der Bereich zum Rollen wird kleiner, das Regal bleibt darin.
	_screen.call("scroll_shelf", 100000.0)
	for i: int in 12:
		_game.call("sell_item", uids[i])
	_check(float(_screen.call("shelf_scroll")) <= float(_screen.call("shelf_scroll_max")) + 0.01 and _layout().size() == 18, "Nach dem Verkauf von zwölf bleibt das Regal im möglichen Bereich.")
	# FERTIG ist nie gesperrt, auch nicht mit einer vollen Ablage.
	_check(not _warning().visible and is_equal_approx(done.modulate.a, 1.0) and not done.disabled, "Auch mit voller Ablage warnt nichts und FERTIG ist frei.")
	_check(bool(_screen.call("request_close")) and not _is_open(), "Der Rucksack schließt mit voller Ablage.")
	# Beim nächsten Öffnen steht das Regal wieder oben.
	_game.call("open_backpack")
	_check(is_zero_approx(float(_screen.call("shelf_scroll"))) and bool(_layout()[0]["visible"]), "Beim Öffnen steht das Regal oben: Dort liegt das Neueste.")
	# Wenig Inhalt: kein Rollbalken, das Mausrad tut nichts.
	_fresh_open(521)
	pack = _pack()
	for id: String in ["luck", "snack", "drone", "pistol"]:
		pack.add_item(id, 1)
	_game.call("sync_build")
	_check((_screen.call("shelf_bar") as Dictionary).is_empty() and is_zero_approx(float(_screen.call("shelf_scroll_max"))), "Vier Gegenstände passen ins Regal: kein Rollbalken.")
	_screen.call("_on_board_input", _mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, view.get_center()))
	_check(is_zero_approx(float(_screen.call("shelf_scroll"))) and _shelf_ok(_layout(), view), "Dann rollt auch das Mausrad nichts.")


## Zusammenlegen im Regal: Regal auf Regal, Raster auf Regal, Regal auf Raster, falsche Rarität,
## Legendär, Zähler und Warnung danach, Vorschau.
func _test_shelf_merge() -> void:
	_fresh_open(53)
	var pack: BackpackState = _pack()
	var label: Label = _screen.get("storage_label") as Label
	var done: Button = _screen.get("done_button") as Button
	_check(not bool(_screen.call("drop_on_storage_item", 1)), "Ohne gehaltenen Gegenstand meldet drop_on_storage_item false.")
	_check(int(_screen.call("storage_merge_target")) == -1, "Ohne gehaltenen Gegenstand gibt es kein Ziel im Regal.")
	# Regal auf Regal.
	var first: int = pack.add_item("luck", 1)
	var second: int = pack.add_item("luck", 1)
	_game.call("sync_build")
	_check(label.text == "ABLAGE 2", "Zwei Gegenstände liegen in der Ablage, war: " + label.text)
	_screen.call("pick_up", second)
	_check(int(_screen.call("storage_merge_target")) == -1, "Neben dem Regal gibt es kein Ziel.")
	_screen.call("set_pointer", (_screen.call("item_rect", first) as Rect2).get_center())
	_check(int(_screen.call("storage_merge_target")) == first, "Vorschau: Über dem gleichen Gegenstand im Regal wird zusammengelegt.")
	_check((_screen.call("drop_preview") as Dictionary).is_empty(), "Über dem Regal gibt es keine Vorschau fürs Raster.")
	_check(pack.has_item(second) and int(pack.item(first)["level"]) == 1, "Die Vorschau ändert die Ablage nicht.")
	var before: int = _build_changes
	_check(bool(_screen.call("drop_at", (_screen.call("item_rect", first) as Rect2).get_center())), "Loslassen auf dem gleichen Gegenstand im Regal gelingt.")
	_check(not pack.has_item(second) and int(pack.item(first)["level"]) == 2 and not pack.is_placed(first), "Regal auf Regal: Das Ziel steigt um eine Rarität und bleibt im Regal.")
	_check(_held() == -1 and _build_changes == before + 1, "Danach wird nichts gehalten und der Build ist einmal abgeglichen.")
	_check(pack.storage_items().size() == 1 and label.text == "ABLAGE 1", "Der Zähler zeigt den frei gewordenen Platz, war: " + label.text)
	_check(int(_screen.call("storage_merge_target")) == -1, "Nach dem Zusammenlegen gibt es kein Ziel mehr.")
	# Raster auf Regal.
	var placed: int = pack.add_item("luck", 2)
	_check(_put(placed, pack.cells()[0], 0) and _level("luck") == 2, "Ein gleicher Gegenstand liegt im Raster und wirkt.")
	_screen.call("pick_up", placed)
	_screen.call("set_pointer", (_screen.call("item_rect", first) as Rect2).get_center())
	_check(int(_screen.call("storage_merge_target")) == first, "Vorschau: Auch ein Gegenstand aus dem Raster findet sein Ziel im Regal.")
	before = _build_changes
	_check(bool(_screen.call("drop_at", (_screen.call("item_rect", first) as Rect2).get_center())), "Loslassen aus dem Raster auf dem Regal gelingt.")
	_check(not pack.has_item(placed) and int(pack.item(first)["level"]) == 3 and not pack.is_placed(first), "Raster auf Regal: Das Ergebnis liegt im Regal.")
	_check(pack.placed_items().is_empty() and _level("luck") == 0 and _build_changes == before + 1, "Der Gegenstand wirkt nicht mehr, der Build ist abgeglichen.")
	# Regal auf Raster (wie bisher).
	var third: int = pack.add_item("luck", 3)
	_check(_put(third, pack.cells()[0], 0), "Ein seltener Gegenstand liegt im Raster.")
	_screen.call("pick_up", first)
	_check(bool(_screen.call("drop_on_cell", pack.cells()[0])) and not pack.has_item(first) and int(pack.item(third)["level"]) == 4 and pack.is_placed(third),
		"Regal auf Raster: Das Ergebnis liegt im Raster.")
	_check(pack.storage_items().is_empty() and label.text == "ABLAGE 0", "Die Ablage ist leer, war: " + label.text)
	# Andere Rarität: kein Zusammenlegen, der gehaltene landet einfach in der Ablage.
	var low: int = pack.add_item("luck", 1)
	var high: int = pack.add_item("luck", 2)
	_game.call("sync_build")
	_screen.call("pick_up", low)
	_screen.call("set_pointer", (_screen.call("item_rect", high) as Rect2).get_center())
	_check(int(_screen.call("storage_merge_target")) == -1, "Vorschau: Verschiedene Raritäten werden nicht zusammengelegt.")
	_check(bool(_screen.call("drop_at", (_screen.call("item_rect", high) as Rect2).get_center())), "Loslassen auf einem nicht passenden Gegenstand legt einfach ab.")
	_check(pack.has_item(low) and pack.has_item(high) and int(pack.item(low)["level"]) == 1 and int(pack.item(high)["level"]) == 2 and _held() == -1,
		"Beide Gegenstände liegen unverändert in der Ablage.")
	# Aus dem Raster auf einen nicht passenden im Regal: Er landet in der Ablage.
	_screen.call("pick_up", third)
	_check(bool(_screen.call("drop_on_storage_item", high)) and pack.has_item(third) and not pack.is_placed(third) and int(pack.item(third)["level"]) == 4,
		"Ein nicht passender Gegenstand aus dem Raster landet in der Ablage.")
	_check(pack.storage_items().size() == 3 and label.text == "ABLAGE 3", "Jetzt liegen drei in der Ablage, war: " + label.text)
	# Anderer Gegenstand in gleicher Rarität: kein Zusammenlegen.
	var other: int = pack.add_item("snack", 1)
	_game.call("sync_build")
	_screen.call("pick_up", other)
	_screen.call("set_pointer", (_screen.call("item_rect", low) as Rect2).get_center())
	_check(int(_screen.call("storage_merge_target")) == -1, "Verschiedene Gegenstände werden nicht zusammengelegt.")
	_screen.call("cancel_hold")
	# Legendär lässt sich nicht weiter zusammenlegen.
	_fresh_open(54)
	pack = _pack()
	var top_a: int = pack.add_item("drone", 5)
	var top_b: int = pack.add_item("drone", 5)
	_game.call("sync_build")
	_screen.call("pick_up", top_b)
	_screen.call("set_pointer", (_screen.call("item_rect", top_a) as Rect2).get_center())
	_check(int(_screen.call("storage_merge_target")) == -1, "Vorschau: Zwei Legendäre werden nicht zusammengelegt.")
	_check(bool(_screen.call("drop_on_storage_item", top_a)) and pack.has_item(top_a) and pack.has_item(top_b) and int(pack.item(top_a)["level"]) == 5,
		"Zwei Legendäre bleiben beide in der Ablage.")
	# Zusammenlegen in einer vollen Ablage: Das Ergebnis bleibt an der Stelle des Ziels, der Zähler stimmt sofort.
	_fresh_open(55)
	pack = _pack()
	var uids: Array[int] = []
	for id: String in ["luck", "drone", "lifesteal", "speed_loader", "piggy_bank", "luck"]:
		uids.append(pack.add_item(id, 1))
	_game.call("sync_build")
	_check(label.text == "ABLAGE 6" and not _warning().visible and is_equal_approx(done.modulate.a, 1.0), "Sechs Gegenstände in der Ablage: keine Warnung, FERTIG frei.")
	_screen.call("pick_up", uids[5])
	_check(bool(_screen.call("drop_on_storage_item", uids[0])), "Die beiden gleichen werden im Regal zusammengelegt.")
	_check(not pack.has_item(uids[5]) and int(pack.item(uids[0])["level"]) == 2, "Danach liegen fünf Gegenstände in der Ablage.")
	_check(label.text == "ABLAGE 5" and not _warning().visible, "Der Zähler ist sofort auf dem neuen Stand, war: " + label.text)
	var merged_rows: Array[Dictionary] = _layout()
	_check(merged_rows.size() == 5 and int(merged_rows[4]["uid"]) == uids[0] and int(merged_rows[4]["level"]) == 2,
		"Das Ergebnis liegt an der Stelle des Ziels (das älteste ganz unten) und zeigt die neue Rarität.")
	_check(bool(_screen.call("request_close")) and _state() == STATE_PLAYING, "Der Rucksack lässt sich schließen.")
	# Eine dritte Waffe über einer gleichen im Regal: Zum Zusammenlegen braucht sie keine freie Hand.
	_fresh_open(56)
	pack = _pack()
	var left: int = pack.add_item("pistol", 1)
	var right: int = pack.add_item("pistol", 2)
	_check(_put(left, Vector2i(1, 1), 0) and _put(right, Vector2i(3, 1), 0), "Zwei Pistolen belegen beide Hände.")
	var spare: int = pack.add_item("pistol", 1)
	var twin: int = pack.add_item("pistol", 1)
	_game.call("sync_build")
	_screen.call("pick_up", twin)
	_check(_warning().visible and _warning().text.contains("Keine Hand frei"), "Die gehaltene dritte Pistole bekommt die Warnung.")
	_screen.call("set_pointer", (_screen.call("item_rect", spare) as Rect2).get_center())
	_check(int(_screen.call("storage_merge_target")) == spare and not _warning().visible, "Über der gleichen Pistole im Regal gibt es keine Warnung: Zusammenlegen geht.")
	_check(bool(_screen.call("drop_at", (_screen.call("item_rect", spare) as Rect2).get_center())) and not pack.has_item(twin) and int(pack.item(spare)["level"]) == 2,
		"Zwei gleiche Waffen werden im Regal zusammengelegt.")
	_check(_hands_title() == "HÄNDE 2 / 2" and not pack.is_placed(spare), "Die Hände bleiben, wie sie waren.")
	_pointer_away()


## Material in der oberen Leiste: Stand beim Öffnen, Änderung über Events.materials_changed,
## neuer Lauf.
func _test_materials() -> void:
	_fresh_open(70)
	var label: Label = _screen.get("material_label") as Label
	_check(_materials() == Balance.MATERIAL_START and label.text == "MATERIAL %d" % Balance.MATERIAL_START, "Beim Öffnen zeigt die Leiste das Material des Laufs, war: " + label.text)
	_game.call("add_materials", 4)
	_check(label.text == "MATERIAL %d" % (Balance.MATERIAL_START + 4), "Neues Material steht sofort da, war: " + label.text)
	_check(_board_rect().encloses(_box(label)) and not _box(label).intersects(_box(_screen.get("points_label") as Control)), "Das Material steht im Bild neben den Punkten.")
	_game.call("add_materials", 995)
	_check(label.text == "MATERIAL 1.002" and label.get_minimum_size().x <= _box(label).size.x + 0.5, "Auch viel Material passt in sein Feld, war: " + label.text)
	# Bei geschlossenem Rucksack läuft die Zahl mit: Beim nächsten Öffnen stimmt sie.
	_check(bool(_screen.call("request_close")), "Der Rucksack schließt.")
	_events.emit_signal("wave_cleared", 1)
	_check(_materials() == Balance.MATERIAL_START + 999 + Balance.MATERIAL_PER_WAVE, "Eine geschaffte Welle gibt Material.")
	_game.call("open_backpack")
	_check(label.text == "MATERIAL %s" % "1.004", "Nach dem Öffnen steht der neue Stand da, war: " + label.text)
	# Neuer Lauf: zurück auf den Start.
	_fresh_open(701)
	_check(label.text == "MATERIAL %d" % Balance.MATERIAL_START, "Ein neuer Lauf beginnt wieder mit dem Start-Material, war: " + label.text)


## Kaputte Gegenstände: im Regal als kaputt gezeichnet, Karte nennt die Kosten, einräumen und
## kombinieren geht nicht und zeigt "Erst reparieren".
func _test_broken() -> void:
	_fresh_open(71)
	var pack: BackpackState = _pack()
	var cells: Array[Vector2i] = pack.cells()
	var broken: int = pack.add_item("luck", 1, true)
	var twin: int = pack.add_item("luck", 1)
	var rare: int = pack.add_item("drone", 3, true)
	_game.call("sync_build")
	_check(pack.is_broken(broken) and not pack.is_broken(twin) and pack.is_broken(rare), "Aufbau: zwei kaputte und ein heiler Gegenstand liegen in der Ablage.")
	var flags_ok: bool = true
	for row: Dictionary in _layout():
		if bool(row["broken"]) != pack.is_broken(int(row["uid"])):
			flags_ok = false
	_check(flags_ok and _layout().size() == 3, "Jede Zeile des Regals sagt, ob ihr Gegenstand kaputt ist.")
	# Karte: Kosten der Reparatur, Ertrag beim Verschrotten, Verkaufswert.
	var info: Dictionary = _screen.call("describe", broken)
	var cost_common: int = Balance.REPAIR_COST[0]
	_check(str(info["broken"]) == "Kaputt: Reparieren kostet %d Material. Bis dahin lässt er sich nicht einräumen oder kombinieren." % cost_common,
		"describe nennt für einen kaputten Gegenstand die Kosten, war: " + str(info["broken"]))
	_check(str(info["scrap"]) == "Verschrotten: +%d Material" % Balance.SCRAP_YIELD[0], "describe nennt den Ertrag beim Verschrotten, war: " + str(info["scrap"]))
	_check(str(info["sell"]).contains(str(ItemDefs.sell_value("luck", 1))), "Ein kaputter Gegenstand hat den vollen Verkaufswert.")
	_check(str((_screen.call("describe", twin) as Dictionary)["broken"]).is_empty(), "Für einen heilen Gegenstand ist der Hinweis leer.")
	_check(str((_screen.call("describe", rare) as Dictionary)["broken"]).contains("kostet %d Material" % Balance.REPAIR_COST[2]) and Balance.REPAIR_COST[2] > cost_common,
		"Ein seltener kaputter Gegenstand kostet mehr.")
	_check(str((_screen.call("describe", rare) as Dictionary)["scrap"]).contains("+%d Material" % Balance.SCRAP_YIELD[2]), "Er gibt beim Verschrotten auch mehr.")
	_screen.call("set_pointer", _row_center(broken))
	var broken_label: Label = _screen.get("card_broken_label") as Label
	_check(int(_screen.call("card_uid")) == broken and broken_label.visible and broken_label.text == str(info["broken"]), "Die Karte am kaputten Gegenstand zeigt den Hinweis.")
	_check(str(_screen.call("card_text")).contains("Kaputt: Reparieren kostet %d Material" % cost_common) and str(_screen.call("card_text")).contains("Verschrotten: +")
		and str(_screen.call("card_text")).contains("Verkaufswert: "), "Die Karte nennt Kosten, Ertrag und Verkaufswert.")
	_check(_card_has_all(broken) and _card_parts_fit(), "Die Karte des kaputten Gegenstands enthält alles aus describe, die Zeilen liegen untereinander.")
	_check(_board_rect().encloses(_screen.call("card_rect") as Rect2), "Die Karte liegt ganz im Bild.")
	_screen.call("set_pointer", _row_center(twin))
	_check(int(_screen.call("card_uid")) == twin and not broken_label.visible and broken_label.text.is_empty() and not str(_screen.call("card_text")).contains("Kaputt"),
		"Die Karte am heilen Gegenstand hat keinen Hinweis.")
	_check(_card_has_all(twin) and str(_screen.call("card_text")).contains("Verschrotten: +%d Material" % Balance.SCRAP_YIELD[0]), "Auch sie nennt den Ertrag beim Verschrotten.")
	_pointer_away()
	_check(not bool(_screen.call("needs_repair_hint")) and not _warning().visible, "Ohne gehaltenen Gegenstand gibt es keinen Hinweis.")
	# Einräumen geht nicht: Vorschau "geht nicht", Hinweis "Erst reparieren", Loslassen legt zurück.
	_screen.call("pick_up", broken)
	_check(not bool(_screen.call("needs_repair_hint")) and not _warning().visible, "Neben allem gibt es beim Halten noch keinen Hinweis.")
	_screen.call("set_pointer", _cell_center(cells[0]))
	var preview: Dictionary = _screen.call("drop_preview")
	_check(not preview.is_empty() and int(preview["kind"]) == 2 and bool(preview["broken"]), "Ein kaputter Gegenstand über einem freien Feld: Die Vorschau meldet, dass es nicht geht.")
	_check(bool(_screen.call("needs_repair_hint")) and _warning().visible and _warning().text.contains("Erst reparieren"), "Die Warnung sagt: Erst reparieren, war: " + _warning().text)
	var before: int = _build_changes
	_check(not bool(_screen.call("drop_at", _cell_center(cells[0]))), "Loslassen über dem Raster wird abgelehnt.")
	_check(pack.has_item(broken) and not pack.is_placed(broken) and pack.is_broken(broken) and _held() == -1 and _build_changes == before,
		"Der kaputte Gegenstand liegt wieder in der Ablage, nichts hat sich geändert.")
	_check(_warning().visible and _warning().text.contains("Erst reparieren"), "Der Hinweis bleibt nach dem Loslassen stehen.")
	_check(not bool(_screen.call("quick_place", broken)) and not pack.is_placed(broken) and _warning().text.contains("Erst reparieren"), "Auch der Doppelklick räumt ihn nicht ein.")
	# Kombinieren im Regal geht nicht: kaputt auf heil.
	_screen.call("pick_up", broken)
	_screen.call("set_pointer", _row_center(twin))
	_check(int(_screen.call("storage_merge_target")) == -1 and bool(_screen.call("needs_repair_hint")), "Kaputt über einem gleichen heilen im Regal: kein Ziel, aber der Hinweis.")
	_check(_warning().visible and _warning().text.contains("Erst reparieren"), "Die Warnung sagt auch hier: Erst reparieren.")
	_check(bool(_screen.call("drop_at", _row_center(twin))), "Loslassen dort legt ihn einfach zurück ins Regal.")
	_check(pack.has_item(broken) and pack.has_item(twin) and int(pack.item(twin)["level"]) == 1 and pack.is_broken(broken) and not pack.is_placed(broken) and _held() == -1,
		"Beide liegen unverändert in der Ablage.")
	_check(_warning().visible and _warning().text.contains("Erst reparieren"), "Der Hinweis steht danach noch da.")
	# Heil auf kaputt.
	_screen.call("pick_up", twin)
	_screen.call("set_pointer", _row_center(broken))
	_check(int(_screen.call("storage_merge_target")) == -1 and bool(_screen.call("needs_repair_hint")), "Heil über einem gleichen kaputten: ebenfalls der Hinweis.")
	_screen.call("cancel_hold")
	# Kaputt auf einen gleichen heilen im Raster.
	_check(_put(twin, cells[0], 0), "Der heile Gegenstand liegt im Raster.")
	_screen.call("pick_up", broken)
	_screen.call("set_pointer", _cell_center(cells[0]))
	preview = _screen.call("drop_preview")
	_check(int(preview.get("kind", -1)) == 2 and int(preview.get("merge", 0)) == -1 and bool(_screen.call("needs_repair_hint")), "Kaputt über einem gleichen im Raster: kein Zusammenlegen, Hinweis.")
	_check(not bool(_screen.call("drop_at", _cell_center(cells[0]))) and int(pack.item(twin)["level"]) == 1 and pack.has_item(broken), "Loslassen dort ändert nichts.")
	# Über einem anderen Gegenstand im Regal: kein Hinweis, er wird einfach abgelegt.
	_pointer_away()
	_screen.call("_process", float(_constant("NOTICE_TIME")) + 0.1)
	_check(not _warning().visible, "Nach einer Weile verschwindet der Hinweis.")
	_screen.call("pick_up", broken)
	_screen.call("set_pointer", _row_center(rare))
	_check(not bool(_screen.call("needs_repair_hint")) and not _warning().visible, "Über einem anderen Gegenstand gibt es keinen Hinweis.")
	_check(bool(_screen.call("drop_at", _row_center(rare))) and not _warning().visible, "Loslassen dort legt ab, ohne zu warnen.")
	# Über den drei Feldern gibt es den Hinweis nicht.
	_screen.call("pick_up", broken)
	_screen.call("set_pointer", (_screen.call("sell_rect") as Rect2).get_center())
	_check(not bool(_screen.call("needs_repair_hint")) and (_screen.call("drop_preview") as Dictionary).is_empty(), "Über dem Verkaufsfeld gibt es weder Vorschau noch Hinweis.")
	# Verkaufen geht auch kaputt, zum vollen Wert.
	var points: int = int(_game.get("points"))
	_check(bool(_screen.call("drop_at", (_screen.call("sell_rect") as Rect2).get_center())) and not pack.has_item(broken)
		and int(_game.get("points")) == points + ItemDefs.sell_value("luck", 1), "Ein kaputter Gegenstand lässt sich zum vollen Wert verkaufen.")
	# Ein Rucksack-Teil ist nie kaputt.
	var bag: int = pack.add_item("bag_small", 1, true)
	_game.call("sync_build")
	_check(not pack.is_broken(bag) and str((_screen.call("describe", bag) as Dictionary)["broken"]).is_empty() and not bool(_layout()[0]["broken"]), "Ein Rucksack-Teil ist nie kaputt.")
	_pointer_away()


## Mit Game.broken_loot kommt das Fundstück aus der Kiste kaputt oben ins Regal.
func _test_broken_loot() -> void:
	_game.set("broken_loot", true)
	_game.call("start_run", 75)
	var pack: BackpackState = _pack()
	# Etwas liegt schon in der Ablage: Das neue Fundstück steht trotzdem oben.
	for id: String in ["luck", "snack", "burn"]:
		pack.add_item(id, 1)
	_game.call("open_chest", 1)
	var offers: Array = _game.get("current_offers")
	var index: int = -1
	for i: int in offers.size():
		var offer: Dictionary = offers[i]
		if str(offer.get("kind", "")) == "item" and not ItemDefs.is_bag(str(offer.get("id", ""))) and index == -1:
			index = i
	_check(index != -1, "Die Kiste bietet mindestens einen Gegenstand an, der kein Rucksack-Teil ist.")
	if index != -1:
		var offer_id: String = str((offers[index] as Dictionary)["id"])
		var offer_level: int = int((offers[index] as Dictionary).get("level", 1))
		_game.call("choose_offer", index)
		_check(_is_open() and _state() == STATE_PACKING, "Nach der Wahl ist der Rucksack offen.")
		var layout: Array[Dictionary] = _layout()
		_check(layout.size() == 4 and str(layout[0]["id"]) == offer_id and bool(layout[0]["broken"]) and bool(layout[0]["visible"]),
			"Das Fundstück liegt kaputt ganz oben im Regal.")
		var uid: int = int(layout[0]["uid"])
		_check(pack.is_broken(uid) and not pack.is_placed(uid), "Es ist kaputt und liegt in der Ablage.")
		_screen.call("set_pointer", (layout[0]["rect"] as Rect2).get_center())
		var title: String = (_screen.get("card_name_label") as Label).text
		_check(title.begins_with("NEU: ") and str(_screen.call("card_text")).contains("Kaputt: Reparieren kostet %d Material" % Balance.REPAIR_COST[offer_level - 1]),
			"Die Karte stellt das Fundstück als neu und kaputt vor, war: " + title)
		_check(not bool(_screen.call("quick_place", uid)), "Das kaputte Fundstück lässt sich nicht einräumen.")
		# Reparieren: Es bleibt neu und liegt weiter oben.
		_game.call("add_materials", 10)
		_check(bool(_screen.call("repair", uid)) and not pack.is_broken(uid) and int(_layout()[0]["uid"]) == uid, "Nach dem Reparieren liegt es heil an derselben Stelle.")
		_check((_screen.get("card_name_label") as Label).text.begins_with("NEU: "), "Es gilt weiter als neu.")
		_pointer_away()
	_game.set("broken_loot", false)
	_game.call("start_run", 75)


## Reparieren über das Feld und über Taste F: zu wenig Material, genug Material, heiler Gegenstand.
func _test_repair() -> void:
	_fresh_open(72)
	var pack: BackpackState = _pack()
	var repair_rect: Rect2 = _screen.call("repair_rect")
	var value: Label = _screen.get("repair_value_label") as Label
	var material: Label = _screen.get("material_label") as Label
	var cost_cheap: int = Balance.REPAIR_COST[0]
	var cost_dear: int = Balance.REPAIR_COST[4]
	_check(_materials() == 3 and cost_cheap <= 3 and cost_dear > 3, "Aufbau: Mit dem Start-Material reicht es für einen gewöhnlichen, nicht für einen legendären.")
	var cheap: int = pack.add_item("luck", 1, true)
	var dear: int = pack.add_item("drone", 5, true)
	var intact: int = pack.add_item("snack", 1)
	_game.call("sync_build")
	_check(not value.text.contains("−") and not bool(_screen.call("repair_refused")), "Ohne gehaltenen Gegenstand nennt das Feld keinen Preis, war: " + value.text)
	_check(not bool(_screen.call("drop_on_repair")), "Ohne gehaltenen Gegenstand meldet drop_on_repair false.")
	# Feld, zu wenig Material: rot und ablehnend.
	_screen.call("pick_up", dear)
	_check(value.text.contains("−%d Material" % cost_dear) and value.text.contains("zu wenig"), "Das Feld zeigt beim Halten die Kosten und dass es nicht reicht, war: " + value.text)
	_check(bool(_screen.call("repair_refused")) and value.get_theme_color("font_color").is_equal_approx(Color(1.0, 0.18, 0.16)), "Reicht das Material nicht, ist die Zeile rot.")
	var free_rect: Rect2 = _screen.call("item_rect", dear)
	_screen.call("set_pointer", repair_rect.get_center())
	_check((_screen.call("drop_preview") as Dictionary).is_empty() and not bool(_screen.call("needs_repair_hint")), "Über dem Feld gibt es keine Vorschau fürs Raster.")
	# Über den drei Feldern steht der gehaltene Gegenstand klein links daneben: Ihr Text bleibt frei.
	for field: String in ["repair_rect", "scrap_rect", "sell_rect"]:
		_screen.call("set_pointer", (_screen.call(field) as Rect2).get_center())
		var docked: Rect2 = _screen.call("item_rect", dear)
		_check(docked.size.x < free_rect.size.x and docked.end.x <= repair_rect.position.x and _board_rect().encloses(docked),
			"Über %s steht der gehaltene Gegenstand klein links neben den Feldern." % field)
		_check(not docked.intersects(_screen.call("repair_rect") as Rect2) and not docked.intersects(_screen.call("scrap_rect") as Rect2) and not docked.intersects(_screen.call("sell_rect") as Rect2),
			"Über %s verdeckt er keines der drei Felder." % field)
		_check(docked.grow(0.5).encloses(_screen.call("icon_rect", dear) as Rect2), "Sein Bild sitzt dabei in seiner kleinen Form.")
		_check(str(_screen.call("card_text")).contains("Kaputt: Reparieren kostet") and not (_screen.call("card_rect") as Rect2).intersects(docked)
			and not (_screen.call("card_rect") as Rect2).intersects(_screen.call(field) as Rect2), "Die kurze Karte nennt weiter die Kosten und verdeckt weder ihn noch das Feld.")
	_screen.call("set_pointer", repair_rect.get_center())
	_check(not bool(_screen.call("drop_at", repair_rect.get_center())), "Loslassen auf REPARIEREN wird abgelehnt, wenn das Material nicht reicht.")
	_check(pack.is_broken(dear) and _materials() == 3 and _held() == -1 and not pack.is_placed(dear), "Der Gegenstand bleibt kaputt im Regal, das Material bleibt.")
	_check(_warning().visible and _warning().text == "Zu wenig Material: Reparieren kostet %d, du hast 3" % cost_dear, "Die Warnung sagt, was fehlt, war: " + _warning().text)
	# Feld, genug Material.
	_screen.call("pick_up", cheap)
	_check(value.text == "−%d Material" % cost_cheap and not bool(_screen.call("repair_refused")), "Reicht das Material, zeigt das Feld nur die Kosten, war: " + value.text)
	_check(value.get_theme_color("font_color").is_equal_approx(Color(0.35, 1.0, 0.3)), "Dann ist die Zeile grün.")
	var before: int = _build_changes
	_check(bool(_screen.call("drop_at", repair_rect.get_center())), "Loslassen auf REPARIEREN repariert.")
	_check(not pack.is_broken(cheap) and pack.has_item(cheap) and not pack.is_placed(cheap) and _held() == -1, "Der Gegenstand ist heil und bleibt im Regal.")
	_check(_materials() == 3 - cost_cheap and material.text == "MATERIAL %d" % (3 - cost_cheap), "Das Material ist abgezogen, die Leiste zeigt es, war: " + material.text)
	_check(int(_screen.get("_flash_uid")) == cheap and float(_screen.get("_flash_left")) > 0.0, "Der reparierte Gegenstand blitzt kurz auf.")
	_check(not _warning().visible and _build_changes == before, "Die Warnung ist weg, am Build hat sich nichts geändert.")
	for row: Dictionary in _layout():
		if int(row["uid"]) == cheap:
			_check(not bool(row["broken"]), "Im Regal gilt er nicht mehr als kaputt.")
	_screen.call("set_pointer", _row_center(cheap))
	_check(not str(_screen.call("card_text")).contains("Kaputt"), "Seine Karte nennt ihn nicht mehr kaputt.")
	_pointer_away()
	_check(bool(_screen.call("quick_place", cheap)) and pack.is_placed(cheap) and _level("luck") == 1, "Repariert lässt er sich einräumen und wirkt.")
	# Feld, heiler Gegenstand: abgelehnt, kostet nichts.
	_screen.call("pick_up", intact)
	_check(value.text == "Ist nicht kaputt" and bool(_screen.call("repair_refused")), "Für einen heilen Gegenstand sagt das Feld: Ist nicht kaputt, war: " + value.text)
	var materials_before: int = _materials()
	_check(not bool(_screen.call("drop_at", repair_rect.get_center())) and _materials() == materials_before and pack.has_item(intact) and _held() == -1,
		"Ein heiler Gegenstand auf REPARIEREN kostet nichts und bleibt.")
	_check(_warning().visible and _warning().text.contains("heil"), "Die Warnung sagt, dass er heil ist, war: " + _warning().text)
	# Ein eingeräumter (heiler) Gegenstand auf REPARIEREN geht an seinen Platz zurück.
	var placed_pos: Vector2i = pack.item(cheap)["pos"]
	_screen.call("pick_up", cheap)
	_check(not bool(_screen.call("drop_at", repair_rect.get_center())) and pack.is_placed(cheap) and (pack.item(cheap)["pos"] as Vector2i) == placed_pos,
		"Ein eingeräumter Gegenstand bleibt nach REPARIEREN an seinem Platz.")
	_pointer_away()
	_check(not value.text.contains("−"), "Nach dem Loslassen nennt das Feld keinen Preis mehr, war: " + value.text)
	# Taste F: ohne Gegenstand unter dem Zeiger passiert nichts.
	_check(not bool(_screen.call("press_repair")), "Taste F ohne Gegenstand unter dem Zeiger tut nichts.")
	# Taste F, zu wenig Material.
	materials_before = _materials()
	_screen.call("set_pointer", _row_center(dear))
	_press(KEY_F)
	_check(pack.is_broken(dear) and _materials() == materials_before, "Taste F repariert nicht, wenn das Material nicht reicht.")
	_check(_warning().visible and _warning().text.contains("Zu wenig Material: Reparieren kostet %d, du hast %d" % [cost_dear, materials_before]), "Die Warnung sagt, was fehlt, war: " + _warning().text)
	# Taste F, genug Material.
	_game.call("add_materials", 10)
	materials_before = _materials()
	_press(KEY_F)
	_check(not pack.is_broken(dear) and _materials() == materials_before - cost_dear and not pack.is_placed(dear), "Taste F repariert den Gegenstand unter dem Zeiger, er bleibt im Regal.")
	_check(int(_screen.get("_flash_uid")) == dear and float(_screen.get("_flash_left")) > 0.0 and not _warning().visible, "Er blitzt auf, die Warnung ist weg.")
	_check(int(_screen.call("card_uid")) == dear and not str(_screen.call("card_text")).contains("Kaputt"), "Die Karte unter dem Zeiger ist sofort auf dem neuen Stand.")
	# Taste F auf einem heilen Gegenstand (Regal und Raster).
	materials_before = _materials()
	_press(KEY_F)
	_check(_materials() == materials_before and _warning().visible and _warning().text.contains("heil"), "Taste F auf einem heilen Gegenstand kostet nichts und sagt es.")
	_screen.call("set_pointer", (_screen.call("item_rect", cheap) as Rect2).get_center())
	_press(KEY_F)
	_check(_materials() == materials_before and pack.is_placed(cheap), "Taste F auf einem eingeräumten Gegenstand ändert nichts.")
	# Taste F beim Halten: nichts.
	var held_broken: int = pack.add_item("burn", 1, true)
	_game.call("sync_build")
	_screen.call("pick_up", held_broken)
	_press(KEY_F)
	_check(pack.is_broken(held_broken) and _held() == held_broken and _materials() == materials_before, "Taste F beim Halten tut nichts.")
	_screen.call("cancel_hold")
	# Reparatur von außen (Game.repair_item): Der Bildschirm zieht nach.
	_check(bool(_game.call("repair_item", held_broken)) and int(_screen.get("_flash_uid")) == held_broken, "Eine Reparatur über Game lässt den Gegenstand ebenfalls aufblitzen.")
	for row: Dictionary in _layout():
		if int(row["uid"]) == held_broken:
			_check(not bool(row["broken"]), "Das Regal zeigt ihn danach heil.")
	_pointer_away()


## Verschrotten über das Feld und über Taste X (Raster und Regal): Ertrag, Schutz gegen Versehen.
func _test_scrap() -> void:
	_fresh_open(73)
	var pack: BackpackState = _pack()
	var cells: Array[Vector2i] = pack.cells()
	var scrap_rect: Rect2 = _screen.call("scrap_rect")
	var value: Label = _screen.get("scrap_value_label") as Label
	var confirm_time: float = float(_constant("SCRAP_CONFIRM_TIME"))
	_check(not bool(_screen.call("drop_on_scrap")), "Ohne gehaltenen Gegenstand meldet drop_on_scrap false.")
	_check(int(_screen.call("press_scrap")) == 0 and int(_screen.call("scrap_armed_uid")) == -1, "Taste X ohne Gegenstand unter dem Zeiger tut nichts.")
	# Feld, aus dem Regal (kaputt): Ertrag nach Rarität, keine Punkte.
	var broken: int = pack.add_item("luck", 2, true)
	_game.call("sync_build")
	var materials: int = _materials()
	var points: int = int(_game.get("points"))
	_screen.call("pick_up", broken)
	_check(value.text == "+%d Material" % Balance.SCRAP_YIELD[1], "Das Feld zeigt beim Halten den Ertrag, war: " + value.text)
	_check(str((_screen.get("sell_value_label") as Label).text) == "+%d Punkte" % ItemDefs.sell_value("luck", 2), "Das Verkaufsfeld zeigt daneben die Punkte, war: " + (_screen.get("sell_value_label") as Label).text)
	_screen.call("set_pointer", scrap_rect.get_center())
	_check(bool(_screen.call("drop_at", scrap_rect.get_center())), "Loslassen auf VERSCHROTTEN verschrottet.")
	_check(not pack.has_item(broken) and _held() == -1, "Der Gegenstand ist weg.")
	_check(_materials() == materials + Balance.SCRAP_YIELD[1] and int(_game.get("points")) == points, "Es gibt Material nach der Rarität und keine Punkte.")
	_check((_screen.get("material_label") as Label).text == "MATERIAL %d" % _materials(), "Die Leiste zeigt das neue Material.")
	_check(not value.text.contains("+"), "Danach nennt das Feld keinen Ertrag mehr, war: " + value.text)
	# Feld, aus dem Raster: Die Wirkung endet.
	var drone: int = pack.add_item("drone", 1)
	_check(_put(drone, cells[0], 0) and _level("drone") == 1, "Die Kameradrohne liegt im Raster und wirkt.")
	materials = _materials()
	var before: int = _build_changes
	_screen.call("pick_up", drone)
	_check(bool(_screen.call("drop_at", scrap_rect.get_center())) and not pack.has_item(drone), "Auch aus dem Raster lässt sich verschrotten.")
	_check(_materials() == materials + Balance.SCRAP_YIELD[0] and _level("drone") == 0 and _build_changes == before + 1, "Es gibt Material, die Wirkung endet, der Build ist abgeglichen.")
	# Taste X im Regal: Das erste X merkt nur vor.
	var first: int = pack.add_item("snack", 1)
	var second: int = pack.add_item("burn", 3)
	_game.call("sync_build")
	materials = _materials()
	_screen.call("set_pointer", _row_center(first))
	_press(KEY_X)
	_check(pack.has_item(first) and _materials() == materials, "Ein einzelnes X verschrottet nichts.")
	_check(int(_screen.call("scrap_armed_uid")) == first, "Der Gegenstand ist nach dem ersten X vorgemerkt.")
	_check(_warning().visible and _warning().text == "Noch einmal X: %s verschrotten (+%d Material)" % [ItemDefs.display_name("snack"), Balance.SCRAP_YIELD[0]],
		"Die Warnung sagt, was das zweite X tut, war: " + _warning().text)
	# Zeit abgelaufen: wieder nur vormerken.
	_screen.call("_process", confirm_time + 0.1)
	_check(int(_screen.call("scrap_armed_uid")) == -1 and not _warning().visible, "Nach kurzer Zeit verfällt die Vormerkung.")
	_press(KEY_X)
	_check(pack.has_item(first) and int(_screen.call("scrap_armed_uid")) == first, "Ein spätes zweites X merkt nur neu vor.")
	# Zeiger weg: Vormerkung weg.
	_pointer_away()
	_check(int(_screen.call("scrap_armed_uid")) == -1 and not _warning().visible, "Verlässt der Zeiger den Gegenstand, verfällt die Vormerkung.")
	_screen.call("set_pointer", _row_center(first))
	_press(KEY_X)
	_check(pack.has_item(first) and int(_screen.call("scrap_armed_uid")) == first, "Zurück auf dem Gegenstand merkt X wieder nur vor.")
	# Anderer Gegenstand: Das X dort merkt den anderen vor, keiner ist weg.
	_screen.call("set_pointer", _row_center(second))
	_check(int(_screen.call("scrap_armed_uid")) == -1, "Auf einem anderen Gegenstand gilt die Vormerkung nicht.")
	_press(KEY_X)
	_check(pack.has_item(first) and pack.has_item(second) and int(_screen.call("scrap_armed_uid")) == second, "X auf dem anderen merkt den anderen vor.")
	# Zweites X kurz danach: verschrottet.
	_screen.call("_process", 0.2)
	_press(KEY_X)
	_check(not pack.has_item(second) and pack.has_item(first), "Das zweite X kurz danach verschrottet genau diesen Gegenstand.")
	_check(_materials() == materials + Balance.SCRAP_YIELD[2], "Es gibt den Ertrag seiner Rarität.")
	_check(int(_screen.call("scrap_armed_uid")) == -1 and not _warning().visible, "Danach ist nichts mehr vorgemerkt.")
	# Der nächste Gegenstand rückt unter den Zeiger: Er ist nicht vorgemerkt, ein X reicht nicht.
	_check(int(_screen.call("card_uid")) == first, "Der nächste Gegenstand rückt unter den Zeiger und bekommt die Karte.")
	_press(KEY_X)
	_check(pack.has_item(first) and int(_screen.call("scrap_armed_uid")) == first, "Für ihn braucht es wieder zwei X.")
	_press(KEY_X)
	_check(not pack.has_item(first) and pack.storage_items().is_empty(), "Mit dem zweiten X ist auch er weg.")
	# Taste X im Raster.
	var placed: int = pack.add_item("piggy_bank", 4)
	_check(_put(placed, cells[1], 0), "Das Sparschwein liegt im Raster.")
	materials = _materials()
	_screen.call("set_pointer", _cell_center(cells[1]))
	_press(KEY_X)
	_check(pack.has_item(placed) and pack.is_placed(placed) and int(_screen.call("scrap_armed_uid")) == placed, "Im Raster merkt das erste X ebenfalls nur vor.")
	_press(KEY_X)
	_check(not pack.has_item(placed) and _materials() == materials + Balance.SCRAP_YIELD[3] and pack.placed_items().is_empty(), "Das zweite X verschrottet aus dem Raster.")
	# Greifen nimmt die Vormerkung zurück, X beim Halten tut nichts.
	var keep: int = pack.add_item("luck", 1)
	_game.call("sync_build")
	_screen.call("set_pointer", _row_center(keep))
	_press(KEY_X)
	_check(int(_screen.call("scrap_armed_uid")) == keep, "Vorgemerkt.")
	_screen.call("pick_up", keep)
	_check(int(_screen.call("scrap_armed_uid")) == -1, "Greifen nimmt die Vormerkung zurück.")
	_press(KEY_X)
	_press(KEY_X)
	_check(pack.has_item(keep) and _held() == keep, "X beim Halten verschrottet nichts.")
	_screen.call("cancel_hold")
	# Schließen nimmt die Vormerkung zurück.
	_screen.call("set_pointer", _row_center(keep))
	_press(KEY_X)
	_check(bool(_screen.call("request_close")), "Der Rucksack schließt.")
	_game.call("open_backpack")
	_check(int(_screen.call("scrap_armed_uid")) == -1 and pack.has_item(keep), "Nach dem Schließen ist nichts mehr vorgemerkt.")
	# Ein Rucksack-Teil gibt seinen eigenen Ertrag.
	var bag: int = pack.add_item("bag_small", 1)
	_game.call("sync_build")
	materials = _materials()
	_screen.call("pick_up", bag)
	_check(value.text == "+%d Material" % Balance.SCRAP_YIELD_BAG and bool(_screen.call("drop_on_scrap")) and _materials() == materials + Balance.SCRAP_YIELD_BAG,
		"Ein Rucksack-Teil lässt sich verschrotten.")
	_pointer_away()


## Bilder: Jeder Gegenstand im Raster, im Regal und in der Hand wird mit ItemIcons.draw
## gezeichnet. Das Bild sitzt als Quadrat mitten auf dem größten Quadrat seiner Form.
func _test_icons() -> void:
	# Die Fläche des Bildes für jede Form in jeder Lage.
	var blocks_ok: PackedStringArray = PackedStringArray()
	for id: String in ItemDefs.ORDER:
		for rot: int in 4:
			var block: Rect2 = _screen.call("icon_block", id, rot)
			var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
			var extent: Vector2i = ItemDefs.size(id, rot)
			var inside: bool = is_equal_approx(block.size.x, block.size.y) and block.size.x >= 1.0
			for y: int in range(int(floor(block.position.y + 0.001)), int(ceil(block.end.y - 0.001))):
				for x: int in range(int(floor(block.position.x + 0.001)), int(ceil(block.end.x - 0.001))):
					if not shape.has(Vector2i(x, y)):
						inside = false
			# Größer geht es nicht: Kein Quadrat aus ganzen Feldern mit einer Kante mehr passt in die Form.
			var bigger: int = int(roundf(block.size.x)) + 1
			for y: int in extent.y - bigger + 1:
				for x: int in extent.x - bigger + 1:
					var all_in: bool = true
					for dy: int in bigger:
						for dx: int in bigger:
							if not shape.has(Vector2i(x + dx, y + dy)):
								all_in = false
					if all_in:
						inside = false
			if not inside:
				blocks_ok.append("%s/%d" % [id, rot])
	_check(blocks_ok.is_empty(), "Für jede Form liegt das Bild auf dem größten Quadrat aus ihren Feldern, falsch bei: " + ", ".join(blocks_ok))
	var long_block: Rect2 = _screen.call("icon_block", "sniper", 0)
	_check(ItemDefs.size("sniper", 0) == Vector2i(5, 1) and is_equal_approx(long_block.position.x, 2.0) and is_equal_approx(long_block.size.x, 1.0), "Eine lange Form trägt ihr Bild in der Mitte.")
	var pair_block: Rect2 = _screen.call("icon_block", "drone", 0)
	_check(ItemDefs.size("drone", 0) == Vector2i(2, 1) and is_equal_approx(pair_block.position.x, 0.5), "Eine Form aus zwei Feldern trägt ihr Bild mittig über der Fuge.")
	var corner_block: Rect2 = _screen.call("icon_block", "revolver", 0)
	_check(ItemDefs.cells("revolver", 0).has(Vector2i(int(corner_block.position.x), int(corner_block.position.y))) and is_equal_approx(corner_block.position.x, roundf(corner_block.position.x)),
		"Bei einer L-Form sitzt das Bild ganz auf einem Feld der Form.")
	# Die Fläche trägt die Farbe der Rarität, kaputt ist sie grau.
	for level: int in range(1, 6):
		_check((_screen.call("_surface_color", "luck", level, false) as Color).is_equal_approx(ItemDefs.rarity_color(level)), "Die Fläche eines Gegenstands der Rarität %d hat deren Farbe." % level)
	var grey: Color = _screen.call("_surface_color", "luck", 5, true)
	_check(grey.s < ItemDefs.rarity_color(5).s * 0.5 and grey.v < 0.6, "Die Fläche eines kaputten Gegenstands ist grau.")
	_check((_screen.call("_surface_color", "bag_small", 1, false) as Color).is_equal_approx(ItemDefs.color("bag_small")), "Ein Rucksack-Teil (ohne Rarität) behält seine eigene Farbe.")
	# Gezeichnet: Raster und Regal.
	_fresh_open(74)
	_full_raster()
	var pack: BackpackState = _pack()
	var plan: Array[Array] = [["corpse_explosion", 2, 0, 0, 0], ["sniper", 1, 0, 1, 0], ["jammer", 3, 3, 2, 0], ["luck", 4, 6, 0, 0], ["drone", 5, 0, 3, 1], ["shield", 1, 5, 3, 0]]
	var placed: Array[int] = []
	for entry: Array in plan:
		var uid: int = pack.add_item(str(entry[0]), int(entry[1]))
		placed.append(uid)
		_check(pack.place(uid, Vector2i(int(entry[2]), int(entry[3])), int(entry[4])), "Aufbau: %s liegt im Raster." % str(entry[0]))
	var stored_broken: int = pack.add_item("burn", 2, true)
	var stored_intact: int = pack.add_item("minigun", 1)
	var stored_bag: int = pack.add_item("bag_small", 1)
	_game.call("sync_build")
	_pointer_away()
	await process_frame
	await process_frame
	var drawn: Array[Dictionary] = _screen.call("drawn_icons")
	var by_uid: Dictionary = {}
	for record: Dictionary in drawn:
		by_uid[int(record["uid"])] = int(by_uid.get(int(record["uid"]), 0)) + 1
	_check(drawn.size() == 9, "Für neun Gegenstände wird je ein Bild gezeichnet, waren %d." % drawn.size())
	var wrong: PackedStringArray = PackedStringArray()
	for record: Dictionary in drawn:
		var uid: int = int(record["uid"])
		var rect: Rect2 = record["rect"]
		var item: Dictionary = pack.item(uid)
		var where: String = "board" if pack.is_placed(uid) else "shelf"
		var tint: Color = record["tint"]
		var ok: bool = int(by_uid[uid]) == 1 and not item.is_empty() and str(record["id"]) == str(item.get("id", "")) and str(record["where"]) == where
		ok = ok and is_equal_approx(rect.size.x, rect.size.y) and rect.size.x >= 20.0
		ok = ok and (_screen.call("item_rect", uid) as Rect2).grow(0.5).encloses(rect) and rect.is_equal_approx(_screen.call("icon_rect", uid) as Rect2)
		ok = ok and (tint.is_equal_approx(Color.WHITE) != pack.is_broken(uid))
		if not ok:
			wrong.append(str(record["id"]))
	_check(wrong.is_empty(), "Jedes Bild gehört zu seinem Gegenstand, ist quadratisch, liegt in seiner Form und ist nur bei kaputten grau, falsch bei: " + ", ".join(wrong))
	for uid: int in placed + [stored_broken, stored_intact, stored_bag]:
		_check(int(by_uid.get(uid, 0)) == 1, "Der Gegenstand %s bekommt genau ein Bild." % str(pack.item(uid)["id"]))
	var cell: float = (_screen.call("cell_rect", Vector2i.ZERO) as Rect2).size.x
	var sniper_icon: Rect2 = _screen.call("icon_rect", placed[1])
	var sniper_rect: Rect2 = _screen.call("item_rect", placed[1])
	_check(absf(sniper_icon.get_center().x - sniper_rect.get_center().x) <= 0.5 and sniper_icon.size.x <= cell and sniper_icon.size.x >= cell * 0.6,
		"Das Bild der langen Waffe sitzt mittig und ist so groß wie ein Feld (%d Pixel)." % roundi(sniper_icon.size.x))
	var luck_icon: Rect2 = _screen.call("icon_rect", placed[3])
	var luck_rect: Rect2 = _screen.call("item_rect", placed[3])
	_check(absf(luck_icon.get_center().x - luck_rect.get_center().x) <= 0.5 and luck_icon.get_center().y <= luck_rect.get_center().y,
		"Das Bild sitzt waagerecht mittig und nicht unter der Mitte (unten stehen die Kästchen der Rarität).")
	var shelf_icon: Rect2 = _screen.call("icon_rect", stored_intact)
	_check(shelf_icon.size.x < luck_icon.size.x and shelf_icon.size.x >= 24.0 and (_screen.call("shelf_view") as Rect2).encloses(shelf_icon), "Im Regal sind die Bilder kleiner, aber gut zu erkennen (%d Pixel)." % roundi(shelf_icon.size.x))
	_check((_screen.call("icon_rect", 99999) as Rect2).size == Vector2.ZERO, "Für einen unbekannten Gegenstand gibt es keine Bildfläche.")
	# In der Hand: Das Bild wandert auf die Ebene des gehaltenen Gegenstands.
	_screen.call("pick_up", placed[3])
	_screen.call("set_pointer", Vector2(500.0, 600.0))
	await process_frame
	await process_frame
	drawn = _screen.call("drawn_icons")
	var held_records: Array[Dictionary] = []
	for record: Dictionary in drawn:
		if int(record["uid"]) == placed[3]:
			held_records.append(record)
	_check(drawn.size() == 9 and held_records.size() == 1 and str(held_records[0]["where"]) == "overlay", "Der gehaltene Gegenstand wird einmal gezeichnet, auf der Ebene über allem.")
	_check((held_records[0]["rect"] as Rect2).is_equal_approx(_screen.call("icon_rect", placed[3]) as Rect2) and (_screen.call("item_rect", placed[3]) as Rect2).encloses(held_records[0]["rect"] as Rect2),
		"Sein Bild sitzt in der Form am Zeiger.")
	_screen.call("cancel_hold")
	# Kaputt in der Hand über dem Raster: Auch das läuft durchs Zeichnen.
	_screen.call("pick_up", stored_broken)
	_screen.call("set_pointer", _cell_center(Vector2i(3, 0)))
	await process_frame
	await process_frame
	drawn = _screen.call("drawn_icons")
	var grey_ok: bool = false
	for record: Dictionary in drawn:
		if int(record["uid"]) == stored_broken and str(record["where"]) == "overlay" and not (record["tint"] as Color).is_equal_approx(Color.WHITE):
			grey_ok = true
	_check(grey_ok and bool(_screen.call("needs_repair_hint")), "Der kaputte Gegenstand in der Hand wird grau gezeichnet und zeigt den Hinweis.")
	_screen.call("cancel_hold")
	_pointer_away()
	# Viel im Regal: Gezeichnet wird nur, was zu sehen ist.
	for i: int in 30:
		pack.add_item("luck", 1 + i % 5, i % 2 == 0)
	_game.call("sync_build")
	await process_frame
	await process_frame
	var visible_rows: int = 0
	for row: Dictionary in _layout():
		if bool(row["visible"]):
			visible_rows += 1
	var shelf_draws: int = 0
	for record: Dictionary in _screen.call("drawn_icons") as Array[Dictionary]:
		if str(record["where"]) == "shelf":
			shelf_draws += 1
	_check(visible_rows > 5 and visible_rows < 33 and shelf_draws == visible_rows, "Im Regal werden genau die sichtbaren Zeilen gezeichnet (%d von 33), waren %d." % [visible_rows, shelf_draws])
	_screen.call("scroll_shelf", 100000.0)
	await process_frame
	await process_frame
	var last_drawn: bool = false
	for record: Dictionary in _screen.call("drawn_icons") as Array[Dictionary]:
		if int(record["uid"]) == stored_broken:
			last_drawn = true
	_check(last_drawn, "Nach dem Rollen ans Ende wird der älteste Gegenstand gezeichnet.")
	_screen.call("set_shelf_scroll", 0.0)


## Die Flächen zeichnen sich nur neu, wenn sich ihr Stand ändert oder solange auf ihnen etwas
## pulsiert (backpack_screen.gd, _process): Die Bilder der Gegenstände (board_faces im Raster,
## shelf_canvas im Regal) sind das Teure und sollen in Ruhe gar nicht laufen.
func _test_redraw_only_on_change() -> void:
	_fresh_open(91)
	_full_raster()
	var pack: BackpackState = _pack()
	var gun: int = pack.add_item("pistol", 1)
	var luck: int = pack.add_item("luck", 2)
	_check(pack.place(gun, Vector2i(0, 0), 0) and pack.place(luck, Vector2i(3, 2), 0), "Aufbau: zwei Gegenstände liegen im Raster.")
	pack.add_item("speed", 1)
	_game.call("sync_build")
	_pointer_away()
	var counts: Dictionary = {"board": 0, "faces": 0, "top": 0, "shelf": 0, "shelf_top": 0}
	var canvases: Dictionary = {"board": "board", "faces": "board_faces", "top": "board_top", "shelf": "shelf_canvas", "shelf_top": "shelf_top"}
	var hooks: Dictionary = {}
	for key: String in canvases:
		var hook: Callable = func() -> void: counts[key] = int(counts[key]) + 1
		hooks[key] = hook
		(_screen.get(str(canvases[key])) as Control).draw.connect(hook)
	for i: int in 4:
		await process_frame
	_check(int(counts["faces"]) >= 1 and int(counts["shelf"]) >= 1, "Nach dem Aufbau wurden Raster und Regal gezeichnet.")
	for key: String in counts:
		counts[key] = 0
	for i: int in 8:
		await process_frame
	_check(int(counts["board"]) + int(counts["faces"]) + int(counts["top"]) + int(counts["shelf"]) + int(counts["shelf_top"]) == 0,
		"In Ruhe zeichnet sich acht Bilder lang keine Fläche neu (waren %s)." % str(counts))
	# Zeiger auf einen Gegenstand: Der Rahmen liegt auf der Fläche darüber, die Bilder bleiben stehen.
	_screen.call("set_pointer", _cell_center(Vector2i(3, 2)))
	for i: int in 3:
		await process_frame
	_check(int(counts["top"]) >= 1 and int(counts["faces"]) == 0, "Der Zeiger auf einem Gegenstand zeichnet nur die Fläche über den Bildern neu.")
	# Aufnehmen: Der Gegenstand fehlt im Raster, seine Bilder werden genau einmal neu gezeichnet.
	for key: String in counts:
		counts[key] = 0
	_screen.call("pick_up", luck)
	for i: int in 4:
		await process_frame
	_check(int(counts["faces"]) == 1, "Aufnehmen zeichnet die Bilder im Raster genau einmal neu (waren %d)." % int(counts["faces"]))
	_screen.call("cancel_hold")
	_pointer_away()
	for i: int in 4:
		await process_frame
	# Neuer Gegenstand in der Ablage: Das Regal zeichnet sich einmal neu, das Raster nicht.
	for key: String in counts:
		counts[key] = 0
	pack.add_item("burn", 1)
	_game.call("sync_build")
	for i: int in 4:
		await process_frame
	_check(int(counts["shelf"]) == 1 and int(counts["faces"]) == 0, "Ein neuer Gegenstand in der Ablage zeichnet nur das Regal neu, einmal (Regal %d, Raster %d)." % [int(counts["shelf"]), int(counts["faces"])])
	# Ein Fundstück aus der Kiste pulsiert im Regal: Die Fläche darüber läuft in jedem Bild, die
	# Zeilen mit den Bildern nicht.
	_check(bool(_screen.call("request_close")), "Der Rucksack schließt.")
	var fresh: int = int(_game.call("grant_item", "speed", 1))
	_check(fresh > 0 and bool(_screen.call("is_open")), "Ein neues Fundstück öffnet den Rucksack.")
	for i: int in 4:
		await process_frame
	for key: String in counts:
		counts[key] = 0
	for i: int in 6:
		await process_frame
	_check(int(counts["shelf_top"]) >= 5 and int(counts["shelf"]) == 0 and int(counts["faces"]) == 0,
		"Solange das Fundstück pulsiert, läuft nur die Fläche über den Zeilen (darüber %d, Zeilen %d, Raster %d)." % [int(counts["shelf_top"]), int(counts["shelf"]), int(counts["faces"])])
	for key: String in canvases:
		(_screen.get(str(canvases[key])) as Control).draw.disconnect(hooks[key] as Callable)
	_check(bool(_screen.call("request_close")), "Der Rucksack schließt wieder.")


## Namen im Raster: Taste N blendet sie ein und aus, die Wahl bleibt bis zum Programmende.
func _test_name_toggle() -> void:
	_fresh_open(76)
	var pack: BackpackState = _pack()
	var uid: int = pack.add_item("luck", 1)
	var gun: int = pack.add_item("pistol", 2)
	_check(_put(uid, pack.cells()[0], 0) and _put(gun, pack.cells()[1], 0), "Aufbau: zwei Gegenstände liegen im Raster.")
	_check(not bool(_screen.call("names_shown")), "Die Namen sind anfangs ausgeblendet.")
	var plain: Rect2 = _screen.call("icon_rect", uid)
	await process_frame
	_press(KEY_N)
	_check(bool(_screen.call("names_shown")), "Taste N blendet die Namen ein.")
	var named: Rect2 = _screen.call("icon_rect", uid)
	var band: Rect2 = _screen.call("name_area", "luck", 0, (_screen.call("item_rect", uid) as Rect2).position, plain.size.x / (1.0 - 2.0 * float(_constant("ICON_INSET"))))
	_check(named.size.x < plain.size.x and named.end.y < plain.end.y and named.size.x >= 48.0, "Mit Namen ist das Bild kleiner und sitzt höher, bleibt aber groß genug (%d Pixel)." % roundi(named.size.x))
	_check((_screen.call("item_rect", uid) as Rect2).encloses(band) and band.position.y >= named.get_center().y, "Die Namenszeile steht am unteren Rand unter der Bildmitte.")
	await process_frame
	await process_frame
	var drawn: Array[Dictionary] = _screen.call("drawn_icons")
	_check(drawn.size() == 2 and (drawn[0]["rect"] as Rect2).is_equal_approx(_screen.call("icon_rect", int(drawn[0]["uid"])) as Rect2), "Mit Namen werden die Bilder an der neuen Stelle gezeichnet.")
	# Die Wahl bleibt über Schließen, Öffnen und einen neuen Lauf.
	_check(bool(_screen.call("request_close")), "Der Rucksack schließt.")
	_game.call("open_backpack")
	_check(bool(_screen.call("names_shown")), "Nach dem erneuten Öffnen sind die Namen noch eingeblendet.")
	_fresh_open(77)
	_check(bool(_screen.call("names_shown")), "Auch im nächsten Lauf sind sie noch eingeblendet.")
	var released: InputEventKey = _key(KEY_N)
	released.pressed = false
	_screen.call("_unhandled_input", released)
	_check(bool(_screen.call("names_shown")), "Das Loslassen der Taste schaltet nicht um.")
	var by_place: InputEventKey = InputEventKey.new()
	by_place.physical_keycode = KEY_N
	by_place.pressed = true
	_screen.call("_unhandled_input", by_place)
	_check(not bool(_screen.call("names_shown")), "Taste N blendet sie wieder aus.")
	_screen.call("set_names_shown", true)
	_check(bool(_screen.call("names_shown")), "set_names_shown blendet sie ein.")
	_screen.call("toggle_names")
	_check(not bool(_screen.call("names_shown")), "toggle_names schaltet um.")
	# Bei geschlossenem Rucksack tut die Taste nichts.
	_check(bool(_screen.call("request_close")), "Der Rucksack schließt.")
	_press(KEY_N)
	_check(not bool(_screen.call("names_shown")), "Bei geschlossenem Rucksack schaltet N nichts um.")
	await process_frame


## Karte am Gegenstand: erscheint neben ihm, liegt ganz im Bild, überdeckt ihn nicht (alle vier
## Ecken des Rasters und das Regal) und enthält alles aus describe.
func _test_card() -> void:
	_fresh_open(57)
	_full_raster()
	var pack: BackpackState = _pack()
	var stage: Rect2 = _board_rect()
	var constants: Dictionary = (_screen.get_script() as GDScript).get_script_constant_map()
	var gap: float = float(constants["CARD_GAP"])
	_check(not bool(_screen.call("is_card_open")) and (_screen.call("card_rect") as Rect2).size == Vector2.ZERO and str(_screen.call("card_text")).is_empty(),
		"Ohne Gegenstand unter dem Zeiger gibt es keine Karte.")
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(BackpackState.COLS - 1, 0), Vector2i(0, BackpackState.ROWS - 1), Vector2i(BackpackState.COLS - 1, BackpackState.ROWS - 1)]
	var corner_ids: Array[String] = ["luck", "lifesteal", "snack", "kill_heal"]
	for i: int in corners.size():
		var uid: int = pack.add_item(corner_ids[i], i + 1)
		_check(pack.place(uid, corners[i], 0), "Aufbau: %s liegt in der Ecke %s." % [corner_ids[i], str(corners[i])])
		_game.call("sync_build")
		_screen.call("set_pointer", _cell_center(corners[i]))
		var item: Rect2 = _screen.call("item_rect", uid)
		var card: Rect2 = _screen.call("card_rect")
		var where: String = "Ecke %s" % str(corners[i])
		_check(bool(_screen.call("is_card_open")) and int(_screen.call("card_uid")) == uid, "%s: Die Karte erscheint für den Gegenstand unter dem Zeiger." % where)
		_check(item.is_equal_approx(_screen.call("cell_rect", corners[i]) as Rect2), "%s: item_rect ist das Feld des Gegenstands." % where)
		_check(card.size.x > 100.0 and card.size.y > 60.0 and stage.encloses(card), "%s: Die Karte liegt ganz im Bild (%s)." % [where, str(card)])
		_check(not card.intersects(item), "%s: Die Karte überdeckt den Gegenstand nicht." % where)
		var right_of: bool = is_equal_approx(card.position.x, item.end.x + gap)
		var left_of: bool = is_equal_approx(card.end.x, item.position.x - gap)
		_check(right_of or left_of, "%s: Die Karte steht direkt neben dem Gegenstand." % where)
		_check(card.position.y <= item.end.y and card.end.y >= item.position.y, "%s: Die Karte steht auf der Höhe des Gegenstands." % where)
		if corners[i].x == 0:
			_check(right_of, "%s: Links im Raster steht die Karte rechts daneben." % where)
		else:
			_check(left_of, "%s: Ganz rechts ist kein Platz, die Karte steht links daneben." % where)
		_check(_card_has_all(uid), "%s: Die Karte enthält alles aus describe." % where)
		_check(_card_parts_fit(), "%s: Die Zeilen der Karte liegen untereinander in der Karte." % where)
		_check((_screen.get("card_subtitle_label") as Label).get_theme_color("font_color").is_equal_approx(ItemDefs.rarity_color(i + 1)),
			"%s: Die Zeile unter dem Namen hat die Farbe der Rarität." % where)
	_pointer_away()
	_check(not bool(_screen.call("is_card_open")), "Verlässt der Zeiger den Gegenstand, verschwindet die Karte.")
	# Mitten im Raster: rechts daneben.
	var middle: int = pack.add_item("piggy_bank", 1)
	_check(pack.place(middle, Vector2i(3, 2), 0), "Aufbau: Das Sparschwein liegt mitten im Raster.")
	_game.call("sync_build")
	_screen.call("set_pointer", _cell_center(Vector2i(3, 2)))
	var middle_card: Rect2 = _screen.call("card_rect")
	_check(is_equal_approx(middle_card.position.x, (_screen.call("item_rect", middle) as Rect2).end.x + gap) and stage.encloses(middle_card), "Mitten im Raster steht die Karte rechts neben dem Gegenstand.")
	_check((_screen.get("card_tags_label") as Label).text.is_empty() and not str(_screen.call("card_text")).contains("Schlagworte"), "Ein Verstärker hat keine Schlagworte.")
	# Im Regal: Die Karte steht rechts neben dem Regal.
	var stored: int = pack.add_item("burn", 2)
	var stored_bag: int = pack.add_item("bag_large", 1)
	_game.call("sync_build")
	var shelf: Rect2 = _screen.call("storage_area")
	for uid: int in [stored, stored_bag]:
		var row: Rect2 = _screen.call("item_rect", uid)
		_screen.call("set_pointer", row.get_center())
		var card: Rect2 = _screen.call("card_rect")
		_check(int(_screen.call("card_uid")) == uid and shelf.encloses(row), "Regal: Die Karte erscheint für den Gegenstand in seiner Zeile.")
		_check(stage.encloses(card) and not card.intersects(row) and not card.intersects(shelf), "Regal: Die Karte liegt im Bild und überdeckt weder den Gegenstand noch das Regal.")
		_check(is_equal_approx(card.position.x, shelf.end.x + gap) and card.position.y <= row.end.y and card.end.y >= row.position.y, "Regal: Die Karte steht rechts neben dem Regal auf der Höhe des Gegenstands.")
		_check(_card_has_all(uid) and _card_parts_fit(), "Regal: Die Karte enthält alles aus describe.")
	_check(str(_screen.call("card_text")).contains("verbraucht") and (_screen.call("card_bars") as Array).is_empty(), "Die Karte eines Rucksack-Teils sagt, dass es verbraucht wird, und hat keine Balken.")
	_screen.call("set_pointer", (_screen.call("item_rect", stored) as Rect2).get_center())
	_check(str(_screen.call("card_text")).contains("Schlagworte: " + ItemDefs.tags_text("burn")) and not ItemDefs.tags_text("burn").is_empty(), "Die Karte nennt die Schlagworte, war: " + (_screen.get("card_tags_label") as Label).text)
	_pointer_away()
	# Jede Art von Gegenstand: Die Karte enthält alles aus describe.
	_fresh_open(58)
	_full_raster()
	pack = _pack()
	var plan: Array[Array] = [["pistol", 2, 0, 0, 0], ["pierce", 1, 0, 1, 0], ["chain_lightning", 3, 2, 0, 0], ["drone", 2, 3, 0, 0],
			["cam_lens", 1, 5, 0, 0], ["replay", 3, 4, 1, 3], ["spotlight", 1, 0, 3, 0], ["piggy_bank", 4, 6, 4, 0], ["shield", 5, 4, 3, 0]]
	var placed: Dictionary = {}
	for entry: Array in plan:
		var uid: int = pack.add_item(str(entry[0]), int(entry[1]))
		placed[str(entry[0])] = uid
		_check(pack.place(uid, Vector2i(int(entry[2]), int(entry[3])), int(entry[4])), "Aufbau: %s liegt im Raster." % str(entry[0]))
	placed["s_revolver"] = pack.add_item("revolver", 1)
	placed["s_cam_tele"] = pack.add_item("cam_tele", 4)
	_game.call("sync_build")
	var complete: PackedStringArray = PackedStringArray()
	for key: String in placed:
		var uid: int = int(placed[key])
		var item: Rect2 = _screen.call("item_rect", uid)
		_screen.call("set_pointer", (_screen.call("cell_rect", pack.cells_of(uid)[0]) as Rect2).get_center() if pack.is_placed(uid) else item.get_center())
		var card: Rect2 = _screen.call("card_rect")
		if not _card_has_all(uid) or not _card_parts_fit() or not stage.encloses(card) or card.intersects(item):
			complete.append(key)
	_check(complete.is_empty(), "Für Waffe, Stern-Gegenstand, Kamera, Zubehör, Verstärker und Regal: Karte vollständig, im Bild, nicht auf dem Gegenstand. Fehler bei: " + ", ".join(complete))
	_screen.call("set_pointer", _cell_center(Vector2i(0, 0)))
	_check(str(_screen.call("card_text")).contains("Darauf wirken: ") and str(_screen.call("card_text")).contains("linken Hand"), "Die Karte der Waffe nennt Hand und wirkende Gegenstände.")
	_screen.call("set_pointer", _cell_center(Vector2i(3, 0)))
	_check(str(_screen.call("card_text")).contains("Jetzt: Schaden") and str(_screen.call("card_text")).contains("Zählt 2-fach"), "Die Karte der Kamera nennt ihre fertigen Werte und die Wiederholung.")
	# Gehalten: Die Karte gehört zum gehaltenen Gegenstand, liegt nicht auf ihm und nicht auf den Feldern, auf die man zielt.
	_pointer_away()
	var ammo: int = pack.add_item("pierce", 2)
	_game.call("sync_build")
	_screen.call("pick_up", ammo)
	_check(int(_screen.call("card_uid")) == ammo, "Beim Halten zeigt die Karte den gehaltenen Gegenstand.")
	var held_text: String = _screen.call("card_text")
	_check(held_text.contains(ItemDefs.display_name("pierce")) and held_text.contains(ItemDefs.subtitle("pierce", 2)) and not held_text.contains("Verkaufswert")
		and not held_text.contains(ItemDefs.description("pierce", 2)), "In der Hand ist die Karte kurz: Name und Rarität, war: " + held_text)
	_check((_screen.call("card_rect") as Rect2).size.y < 120.0 and _card_parts_fit(), "Die kurze Karte ist niedrig (%d Pixel)." % roundi((_screen.call("card_rect") as Rect2).size.y))
	var aims_ok: bool = true
	for cell: Vector2i in [Vector2i(2, 2), Vector2i(5, 2), Vector2i(0, 2), Vector2i(3, 4), Vector2i(5, 1)]:
		_screen.call("set_pointer", _cell_center(cell))
		var preview: Dictionary = _screen.call("drop_preview")
		var card: Rect2 = _screen.call("card_rect")
		if preview.is_empty() or not stage.encloses(card) or card.intersects(_screen.call("item_rect", ammo) as Rect2):
			aims_ok = false
		for aimed: Vector2i in preview.get("cells", []) as Array[Vector2i]:
			if card.intersects(_screen.call("cell_rect", aimed) as Rect2):
				aims_ok = false
		for star: Vector2i in BackpackState.stars_at("pierce", preview["pos"] as Vector2i, int(_screen.call("held_rotation"))):
			if BackpackState.in_bounds(star) and card.intersects(_screen.call("cell_rect", star) as Rect2):
				aims_ok = false
	_check(aims_ok, "Beim Zielen liegt die Karte im Bild und weder auf dem gehaltenen Gegenstand noch auf seinen Feldern und Sternen.")
	# Über dem Verkaufsfeld und über dem Regal: Die Karte verdeckt das Ziel nicht.
	_screen.call("set_pointer", (_screen.call("sell_rect") as Rect2).get_center())
	var sell_card: Rect2 = _screen.call("card_rect")
	_check(stage.encloses(sell_card) and not sell_card.intersects(_screen.call("sell_rect") as Rect2) and not sell_card.intersects(_screen.call("item_rect", ammo) as Rect2),
		"Über dem Verkaufsfeld liegt die Karte weder auf dem Feld noch auf dem Gegenstand.")
	var twin: int = pack.add_item("pierce", 2)
	_screen.call("set_pointer", (_screen.call("item_rect", twin) as Rect2).get_center())
	var merge_card: Rect2 = _screen.call("card_rect")
	_check(int(_screen.call("storage_merge_target")) == twin and stage.encloses(merge_card) and not merge_card.intersects(_screen.call("item_rect", twin) as Rect2)
		and not merge_card.intersects(_screen.call("item_rect", ammo) as Rect2), "Über dem Ziel im Regal liegt die Karte weder auf dem Ziel noch auf dem gehaltenen Gegenstand.")
	_screen.call("cancel_hold")
	_pointer_away()
	_check(not bool(_screen.call("is_card_open")), "Nach dem Zurücklegen neben allem ist keine Karte da.")
	# Ein Rucksack-Teil am Rand des kleinen Rucksacks: Die Karte verdeckt den Rucksack nicht.
	_fresh_open(59)
	pack = _pack()
	var bag: int = pack.add_item("bag_medium", 1)
	_screen.call("pick_up", bag)
	_screen.call("set_pointer", _cell_center(Vector2i(5, 0)))
	var bag_card: Rect2 = _screen.call("card_rect")
	_check(int((_screen.call("drop_preview") as Dictionary).get("kind", -1)) == 0 and stage.encloses(bag_card) and not bag_card.intersects(_screen.call("item_rect", bag) as Rect2)
		and not bag_card.intersects(_screen.call("pack_rect") as Rect2), "Beim Anlegen eines Rucksack-Teils verdeckt die Karte weder das Teil noch den Rucksack.")
	_screen.call("cancel_hold")
	_pointer_away()


## Wertebalken: vier für eine Waffe, drei für eine Kamera, keine für alles andere.
func _test_bars() -> void:
	_fresh_open(60)
	_full_raster()
	var pack: BackpackState = _pack()
	var best_damage: float = 0.0
	var best_rate: float = 0.0
	var best_magazine: float = 0.0
	var best_reload: float = 999.0
	for id: String in WeaponDefs.all_ids():
		var def: Dictionary = WeaponDefs.get_def(id)
		best_damage = maxf(best_damage, float(def["damage"]) * float(int(def["pellets"])))
		best_rate = maxf(best_rate, float(def["fire_rate"]) * float(WeaponDefs.burst(id)))
		best_magazine = maxf(best_magazine, float(int(def["magazine"])))
		best_reload = minf(best_reload, float(def["reload_time"]))
	var pistol_def: Dictionary = WeaponDefs.get_def("pistol")
	var pistol: int = pack.add_item("pistol", 1)
	var bars: Array[Dictionary] = _screen.call("stat_bars", pistol)
	_check(bars.size() == 4 and str(bars[0]["key"]) == "damage" and str(bars[1]["key"]) == "rate" and str(bars[2]["key"]) == "magazine" and str(bars[3]["key"]) == "reload",
		"Eine Waffe hat vier Balken: Schaden, Schüsse je Sekunde, Magazin, Nachladezeit.")
	if bars.size() == 4:
		_check(str(bars[0]["label"]) == "Schaden" and str(bars[0]["text"]) == "25" and is_equal_approx(float(bars[0]["ratio"]), float(pistol_def["damage"]) / best_damage),
			"Schaden der Pistole: 25, Balken im Verhältnis zum besten Schaden aller Waffen (%s)." % str(bars[0]))
		_check(str(bars[1]["text"]) == "5" and is_equal_approx(float(bars[1]["ratio"]), float(pistol_def["fire_rate"]) / best_rate), "Schüsse je Sekunde der Pistole: 5 (%s)." % str(bars[1]))
		_check(str(bars[2]["text"]) == "10" and is_equal_approx(float(bars[2]["ratio"]), float(int(pistol_def["magazine"])) / best_magazine), "Magazin der Pistole: 10 (%s)." % str(bars[2]))
		_check(str(bars[3]["text"]) == "1,2 s" and is_equal_approx(float(bars[3]["ratio"]), best_reload / float(pistol_def["reload_time"])), "Nachladezeit der Pistole: 1,2 s, kürzer ist besser (%s)." % str(bars[3]))
	# Rarität: Die Zahl steigt mit dem Faktor der Rarität.
	var rare: int = pack.add_item("pistol", 3)
	bars = _screen.call("stat_bars", rare)
	_check(bars.size() == 4 and str(bars[0]["text"]) == "37,5", "Eine seltene Pistole nennt 37,5 Schaden, war: " + str(bars[0].get("text", "")))
	# Schrot: Kugeln mal Schaden, der Balken zählt alle Kugeln.
	var shotgun: int = pack.add_item("shotgun", 1)
	bars = _screen.call("stat_bars", shotgun)
	_check(bars.size() == 4 and str(bars[0]["text"]) == "8 × 14" and is_equal_approx(float(bars[0]["ratio"]), 8.0 * 14.0 / best_damage), "Die Schrotflinte nennt 8 × 14 (%s)." % str(bars[0]))
	# Salven: Schüsse je Sekunde zählen jeden Schuss der Salve.
	bars = _screen.call("stat_bars", pack.add_item("burst_pistol", 1))
	_check(bars.size() == 4 and str(bars[1]["text"]) == "6,6", "Der Dreierpack gibt 6,6 Schüsse je Sekunde ab, war: " + str(bars[1].get("text", "")))
	# Die besten Waffen haben volle Balken, alle Balken liegen zwischen 0 und 1.
	var full_keys: Dictionary = {}
	var in_range: bool = true
	for id: String in WeaponDefs.all_ids():
		for bar: Dictionary in _screen.call("stat_bars", pack.add_item(id, 5)) as Array[Dictionary]:
			if float(bar["ratio"]) < 0.0 or float(bar["ratio"]) > 1.0 or str(bar["text"]).is_empty() or str(bar["label"]).is_empty():
				in_range = false
			if is_equal_approx(float(bar["ratio"]), 1.0):
				full_keys[str(bar["key"])] = true
	_check(in_range and full_keys.size() == 4, "Jeder Balken liegt zwischen 0 und 1, in jedem Wert hat die beste Waffe den vollen Balken.")
	# Die Karte zeichnet dieselben Balken.
	_check(pack.place(pistol, Vector2i(0, 0), 0), "Aufbau: Die Pistole liegt im Raster.")
	_game.call("sync_build")
	_screen.call("set_pointer", _cell_center(Vector2i(0, 0)))
	var shown: Array[Dictionary] = _screen.call("card_bars")
	_check(shown.size() == 4 and str(shown[0]["text"]) == "25" and (_screen.get("card_bars_box") as Control).visible and (_screen.get("card_bars_box") as Control).size.y > 40.0,
		"Die Karte der Waffe zeigt die vier Balken.")
	_check(str(_screen.call("card_text")).contains("Schaden: 25") and str(_screen.call("card_text")).contains("Nachladen: 1,2 s"), "Die Zahlen der Balken stehen auf der Karte.")
	_pointer_away()
	_check((_screen.call("card_bars") as Array).is_empty(), "Ohne Karte gibt es keine Balken.")
	# Kamera: Schaden, Schussfolge, Reichweite aus den fertigen Werten.
	_fresh_open(61)
	_full_raster()
	pack = _pack()
	var drone: int = pack.add_item("drone", 1)
	bars = _screen.call("stat_bars", drone)
	var cam_damage: float = 0.0
	var cam_range: float = 0.0
	var cam_interval: float = 999.0
	for id: String in CameraDefs.all_ids():
		cam_damage = maxf(cam_damage, CameraDefs.base(id, "damage", 1))
		cam_range = maxf(cam_range, CameraDefs.base(id, "range", 1))
		cam_interval = minf(cam_interval, CameraDefs.base(id, "interval", 1))
	_check(bars.size() == 3 and str(bars[0]["key"]) == "damage" and str(bars[1]["key"]) == "rate" and str(bars[2]["key"]) == "range", "Eine Kamera hat drei Balken: Schaden, Schussfolge, Reichweite.")
	if bars.size() == 3:
		_check(str(bars[0]["text"]) == "15" and is_equal_approx(float(bars[0]["ratio"]), 15.0 / cam_damage), "In der Ablage zeigt die Drohne ihre Grundwerte: Schaden 15 (%s)." % str(bars[0]))
		_check(str(bars[1]["text"]) == "alle 1,2 s" and is_equal_approx(float(bars[1]["ratio"]), cam_interval / 1.2), "Schussfolge der Drohne: alle 1,2 s (%s)." % str(bars[1]))
		_check(str(bars[2]["text"]) == "15 m" and is_equal_approx(float(bars[2]["ratio"]), 15.0 / cam_range), "Reichweite der Drohne: 15 m (%s)." % str(bars[2]))
	# Im Raster mit Zubehör: die fertigen Werte aus Game.cameras.
	var lens: int = pack.add_item("cam_lens", 1)
	var battery: int = pack.add_item("cam_battery", 1)
	_check(pack.place(drone, Vector2i(1, 1), 0) and pack.place(lens, Vector2i(3, 1), 0) and pack.place(battery, Vector2i(2, 2), 1), "Aufbau: Drohne mit Objektiv und Akkupack.")
	_game.call("sync_build")
	var entry: Dictionary = _game.call("camera_entry", "%d:0" % drone)
	bars = _screen.call("stat_bars", drone)
	_check(not entry.is_empty() and bars.size() == 3 and str(bars[0]["text"]) == "18" and is_equal_approx(float(bars[0]["ratio"]), 18.0 / cam_damage),
		"Mit Objektiv zeigt der Balken den fertigen Schaden 18 (%s)." % str(bars[0]))
	_check(str(bars[1]["text"]) == "alle 1,04 s" and is_equal_approx(float(bars[1]["ratio"]), 1.0), "Mit Akkupack nennt der Balken die schnellere Schussfolge, länger als voll wird er nicht (%s)." % str(bars[1]))
	var tele: int = pack.add_item("cam_tele", 1)
	bars = _screen.call("stat_bars", tele)
	_check(bars.size() == 3 and is_equal_approx(float(bars[0]["ratio"]), 1.0) and is_equal_approx(float(bars[1]["ratio"]), cam_interval / CameraDefs.base("cam_tele", "interval", 1))
		and is_equal_approx(float(bars[2]["ratio"]), 1.0), "Die Tele-Kamera hat den meisten Schaden und die größte Reichweite, schießt aber langsam.")
	_screen.call("set_pointer", _cell_center(Vector2i(1, 1)))
	shown = _screen.call("card_bars")
	_check(shown.size() == 3 and str(shown[0]["text"]) == "18" and str(_screen.call("card_text")).contains("Schussfolge: alle 1,04 s"), "Die Karte der Kamera zeigt die drei Balken.")
	_check(_card_has_all(drone) and _card_parts_fit(), "Die Karte der Kamera mit Zubehör enthält alles aus describe.")
	_pointer_away()
	# Regie-Kamera: kein eigener Schaden.
	bars = _screen.call("stat_bars", pack.add_item("cam_director", 2))
	_check(bars.size() == 3 and str(bars[0]["text"]) == "keiner" and is_zero_approx(float(bars[0]["ratio"])), "Die Regie-Kamera hat keinen Schaden: leerer Balken (%s)." % str(bars[0]))
	# Alles andere hat keine Balken.
	_check((_screen.call("stat_bars", lens) as Array).is_empty() and (_screen.call("stat_bars", pack.add_item("bag_small", 1)) as Array).is_empty()
		and (_screen.call("stat_bars", pack.add_item("piggy_bank", 1)) as Array).is_empty() and (_screen.call("stat_bars", 999) as Array).is_empty(),
		"Zubehör, Rucksack-Teile, Verstärker und unbekannte Gegenstände haben keine Balken.")
	_screen.call("set_pointer", _cell_center(Vector2i(3, 1)))
	_check(int(_screen.call("card_uid")) == lens and not (_screen.get("card_bars_box") as Control).visible, "Auf der Karte des Objektivs gibt es keine Balken.")
	_pointer_away()


## Hilfe "So geht es": Knopf "?", F1 und H blenden sie ein und aus.
func _test_help() -> void:
	_fresh_open(62)
	var panel: Control = _screen.get("help_panel") as Control
	var button: Button = _screen.get("help_button") as Button
	var text: Label = _screen.get("help_text_label") as Label
	_check(not bool(_screen.call("is_help_open")) and not panel.visible, "Beim zweiten Öffnen steht die Hilfe nicht mehr von selbst da.")
	_check(button.text == "?" and button.focus_mode == Control.FOCUS_NONE, "Der Hilfe-Knopf zeigt ein Fragezeichen und nimmt der Tab-Taste nichts weg.")
	button.pressed.emit()
	_check(bool(_screen.call("is_help_open")) and panel.visible, "Der Knopf ? blendet die Hilfe ein.")
	var help_room: float = panel.size.y - _box(text).position.y - 6.0
	_check(text.text.contains("Rucksack-Teile") and text.get_minimum_size().y <= help_room + 0.5 and _box(text).end.y <= panel.size.y,
		"Die ganze Erklärung passt in die Tafel (%d von %d)." % [roundi(text.get_minimum_size().y), roundi(help_room)])
	_check(text.get_theme_font_size("font_size") >= 11, "Die Schrift der Hilfe bleibt lesbar groß.")
	var help_rect: Rect2 = Rect2(panel.position, panel.size)
	_check(_board_rect().encloses(help_rect) and not help_rect.intersects(_screen.call("pack_rect") as Rect2) and not help_rect.intersects(_screen.call("storage_area") as Rect2)
		and not help_rect.intersects(_screen.call("sell_rect") as Rect2) and not help_rect.intersects(_screen.call("repair_rect") as Rect2)
		and not help_rect.intersects(_screen.call("scrap_rect") as Rect2), "Die Hilfe liegt im Bild neben Rucksack, Regal und den drei Feldern.")
	_full_raster()
	_check(not help_rect.intersects((_screen.call("pack_rect") as Rect2).grow(6.0)), "Auch neben dem vollen Rucksack verdeckt die Hilfe kein Feld.")
	button.pressed.emit()
	_check(not bool(_screen.call("is_help_open")), "Der Knopf ? blendet sie wieder aus.")
	var f1: InputEventKey = InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	_screen.call("_unhandled_input", f1)
	_check(bool(_screen.call("is_help_open")), "F1 blendet die Hilfe ein.")
	var h_key: InputEventKey = InputEventKey.new()
	h_key.physical_keycode = KEY_H
	h_key.pressed = true
	_screen.call("_unhandled_input", h_key)
	_check(not bool(_screen.call("is_help_open")), "H blendet sie wieder aus.")
	var released: InputEventKey = InputEventKey.new()
	released.keycode = KEY_F1
	released.pressed = false
	_screen.call("_unhandled_input", released)
	_check(not bool(_screen.call("is_help_open")), "Das Loslassen der Taste schaltet nicht um.")
	_screen.call("toggle_help")
	_check(bool(_screen.call("is_help_open")) and _is_open() and _state() == STATE_PACKING, "Die Hilfe ändert nichts am offenen Rucksack.")
	# Mit offener Hilfe lässt sich weiter greifen und ablegen.
	var uid: int = _pack().add_item("luck", 1)
	_check(bool(_screen.call("quick_place", uid)), "Mit offener Hilfe lässt sich weiter einräumen.")
	_check(bool(_screen.call("request_close")), "Der Rucksack lässt sich mit offener Hilfe schließen.")
	_game.call("open_backpack")
	_check(not bool(_screen.call("is_help_open")), "Beim nächsten Öffnen ist die Hilfe wieder zu.")
	# Bei geschlossenem Rucksack tut die Taste nichts.
	_check(bool(_screen.call("request_close")), "Der Rucksack schließt.")
	_screen.call("_unhandled_input", f1)
	_check(not bool(_screen.call("is_help_open")) and not _is_open(), "Bei geschlossenem Rucksack blendet F1 nichts ein.")


func _test_hide_signals() -> void:
	_fresh_open(21)
	var uid: int = _pack().add_item("luck", 1)
	_screen.call("pick_up", uid)
	_check(_is_open(), "Vor dem Game Over ist der Rucksack offen.")
	_events.emit_signal("game_over", {})
	_check(not _is_open() and _held() == -1, "Bei game_over verschwindet der Bildschirm und hält nichts mehr.")
	_fresh_open(22)
	_check(_is_open(), "Der Rucksack ist wieder offen.")
	_check(not bool(_screen.call("is_card_open")), "Nach dem neuen Öffnen ist keine Karte da.")
	var hovered: int = _pack().add_item("luck", 1)
	_screen.call("set_pointer", (_screen.call("item_rect", hovered) as Rect2).get_center())
	_check(int(_screen.call("card_uid")) == hovered, "Die Karte steht am Gegenstand unter dem Zeiger.")
	_game.call("start_run", 23)
	_check(not _is_open(), "Bei run_started verschwindet der Bildschirm.")
	_check(not bool(_screen.call("is_card_open")) and int(_screen.call("card_uid")) == -1, "Mit dem Bildschirm verschwindet auch die Karte.")
	_check(_state() == STATE_PLAYING and not paused, "Der neue Lauf läuft.")
	_game.call("open_backpack")
	_events.emit_signal("backpack_closed")
	_check(not _is_open(), "Bei backpack_closed verschwindet der Bildschirm.")
	_game.call("start_run", 24)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
