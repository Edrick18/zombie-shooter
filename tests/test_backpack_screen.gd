extends SceneTree
## Tests für den Rucksack-Bildschirm (scripts/ui/backpack_screen.gd): Öffnen und Schließen,
## Greifen, Drehen, Einräumen, Zusammenlegen, Rucksack-Teile, Ablage, Verkaufen, Überlauf der
## Ablage, Tasten und Maus, dazu Sterne (star_marks), Hände und Waffen im Raster.
## Der Bildschirm wird über seine öffentlichen Funktionen bedient.
##
## Der Rucksack ohne Kandidat hat die Felder x 1 bis 4, y 1 bis 3. Die Tests zu Sternen nutzen:
## Dienstpistole auf (2, 2) belegt (2, 2) und (3, 2). Spezialmunition auf (2, 3) hat ihre Sterne
## auf (2, 2) und (3, 2), Starkstrom-Sponsor auf (1, 2) hat Sterne auf (0, 2) und (2, 2),
## Scheinwerfer auf (2, 1) hat Sterne auf (2, 2) und (3, 2).

const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")

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
		_test_overflow_and_close()
		_test_keys()
		_test_chest()
		_test_mouse()
		_test_info_texts()
		await _test_stars()
		_test_held_weapon_stars()
		_test_hands()
		_test_weapon_merge_and_sell()
		_test_names(script)
		_test_hide_signals()
		await process_frame
		_screen.queue_free()
		await process_frame
	paused = false
	_game.set("character_id", "")
	_game.set("auto_pack", false)
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
	return int(levels.get(upgrade_id, 0))


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
	_check(_screen.get("hands_label") is Label, "Die Anzeige der Hände gibt es.")


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


func _test_overflow_and_close() -> void:
	_fresh_open(16)
	var pack: BackpackState = _pack()
	var warning: Label = _screen.get("warning_label") as Label
	var uids: Array[int] = []
	for id: String in ["luck", "drone", "lifesteal", "speed_loader", "piggy_bank", "spotlight"]:
		uids.append(pack.add_item(id, 1))
	_check(pack.storage_overflow(), "Sechs Gegenstände überfüllen die Ablage.")
	_screen.call("pick_up", uids[0])
	_check(not bool(_screen.call("request_close")), "Bei überfüllter Ablage wird das Schließen abgelehnt.")
	_check(_is_open() and _state() == STATE_PACKING and paused, "Der Rucksack bleibt offen und das Spiel pausiert.")
	_check(_held() == -1, "Der Versuch zu schließen legt den gehaltenen Gegenstand zurück.")
	_check(warning.visible and warning.text.contains("Ablage voll"), "Die Warnung zur vollen Ablage ist zu sehen.")
	var last: Rect2 = _screen.call("storage_rect", 5)
	var first: Rect2 = _screen.call("storage_rect", 0)
	_check(last.position.x > first.position.x and not last.intersects(first), "Der Überlauf hat ein eigenes Fach neben den anderen.")
	_check(int(_screen.call("item_at", last.get_center())) == uids[5], "Im Fach des Überlaufs liegt der sechste Gegenstand.")
	# Einen verkaufen: Dann geht es weiter.
	_screen.call("pick_up", uids[5])
	_check(bool(_screen.call("drop_on_sell")), "Der überzählige Gegenstand lässt sich verkaufen.")
	_check(not warning.visible, "Ohne Überlauf verschwindet die Warnung.")
	_check(bool(_screen.call("request_close")), "Jetzt lässt sich der Rucksack schließen.")
	_check(_state() == STATE_PLAYING and not paused, "Nach dem Schließen läuft das Spiel weiter.")
	_check(not _is_open(), "Der Bildschirm ist zu.")
	_check(not bool(_screen.call("pick_up", uids[0])), "Bei geschlossenem Bildschirm lässt sich nichts greifen.")
	# Der Knopf FERTIG schließt ebenfalls.
	_game.call("open_backpack")
	(_screen.get("done_button") as Button).pressed.emit()
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
		var title: String = (_screen.get("info_name_label") as Label).text
		_check(title.begins_with("NEU: ") and title.contains(ItemDefs.display_name(offer_id)), "Die Info-Tafel stellt den neuen Gegenstand vor, war: " + title)
		_check(int(_screen.call("item_at", (_screen.call("storage_rect", 0) as Rect2).get_center())) == uid, "Er liegt im ersten Fach der Ablage.")
		if _pack().find_spot(uid).is_empty():
			# Eine lange Waffe passt nicht in den Start-Rucksack: Dann bleibt nur das Verkaufen.
			_check(not bool(_screen.call("quick_place", uid)), "Was nirgends passt, räumt quick_place nicht ein.")
			_screen.call("pick_up", uid)
			_check(bool(_screen.call("drop_on_sell")), "Der neue Gegenstand lässt sich verkaufen.")
		else:
			_check(bool(_screen.call("quick_place", uid)), "Der neue Gegenstand lässt sich in den leeren Rucksack räumen.")
		_check(not (_screen.get("info_name_label") as Label).text.begins_with("NEU: "), "Danach gilt er nicht mehr als neu.")
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
	# Die Tafel folgt dem gehaltenen Gegenstand und dem Zeiger.
	_screen.call("pick_up", light)
	_check((_screen.get("info_name_label") as Label).text == ItemDefs.display_name("spotlight"), "Die Tafel zeigt den gehaltenen Gegenstand.")
	_screen.call("cancel_hold")
	_screen.call("set_pointer", _cell_center(Vector2i(1, 2)))
	_check((_screen.get("info_name_label") as Label).text == ItemDefs.display_name("chain_lightning"), "Die Tafel zeigt den Gegenstand unter dem Zeiger.")
	_screen.call("set_pointer", Vector2(-40.0, -40.0))
	_check((_screen.get("info_text_label") as Label).text.contains("Sternen") and (_screen.get("info_text_label") as Label).text.contains("zwei Hände"),
		"Ohne Gegenstand erklärt die Tafel Bedienung, Hände und Sterne.")
	_check(str((_screen.get("storage_label") as Label).text).contains("2 / %d" % BackpackState.STORAGE_CAPACITY), "Die Ablage zeigt, wie viel darin liegt.")


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
	_check(str((_screen.call("describe", third) as Dictionary)["extra"]).contains("Keine Hand frei"), "Die Info-Tafel der Waffe in der Ablage nennt den Grund.")
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
	# Zu viel in der Ablage: Beim Schließen geht die Warnung zur Ablage vor.
	for id: String in ["luck", "luck", "luck"]:
		pack.add_item(id, 1)
	_check(pack.storage_overflow() and not bool(_screen.call("request_close")), "Mit überfüllter Ablage bleibt der Rucksack offen.")
	_check(_warning().visible and _warning().text.contains("Ablage voll"), "Dann steht die Warnung zur Ablage da, war: " + _warning().text)


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
	_check(str((_screen.call("describe", first) as Dictionary)["subtitle"]) == ItemDefs.subtitle("pistol", 2), "Die Info-Tafel zeigt die neue Rarität.")
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


func _test_names(script: GDScript) -> void:
	var hyphens: Dictionary = script.get_script_constant_map().get("NAME_HYPHENS", {})
	var font: Font = (load("res://scripts/ui/hud.gd") as GDScript).call("show_font") as Font
	var cell: float = float(script.get_script_constant_map().get("CELL", 64.0))
	for id: String in ItemDefs.ORDER:
		var weapon: bool = ItemDefs.is_weapon(id)
		# Waffen sind im Raster mindestens zwei Felder breit oder hoch: Ihr Name hat die Zeile über
		# zwei Felder. Alles andere muss in ein einzelnes Feld mit Kästchen für die Rarität passen.
		var width: float = cell * 2.0 - 12.0 if weapon else cell - 12.0
		var height: float = cell - 35.0 if weapon else cell - 25.0
		var layout: Dictionary = _screen.call("name_layout", id, width, height)
		var lines: PackedStringArray = layout["lines"]
		_check(not lines.is_empty() and not str(lines[0]).is_empty(), "Der Name von %s wird gesetzt." % id)
		var fits: bool = true
		for line: String in lines:
			if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(layout["size"])).x > width + 0.5:
				fits = false
		_check(fits, "Jede Zeile des Namens von %s passt in die Breite, war: %s" % [id, " / ".join(lines)])
		_check(float(lines.size()) * float(layout["line_height"]) <= height + 0.5 or lines.size() == 1, "Der Name von %s passt in die Höhe." % id)
		if weapon:
			# Die Namen der Waffen gehören dem Waffen-Modul und können sich ändern: Ein Eintrag mit
			# Trennstellen ist freiwillig, ohne ihn wird an Bindestrich und Leerzeichen getrennt.
			continue
		_check(hyphens.has(id), "Für %s gibt es Trennstellen." % id)
		_check(str(hyphens.get(id, "")).replace("|", "").replace("'", "") == ItemDefs.display_name(id), "Die Trennstellen von %s passen zum Namen." % id)
		_check(not "".join(lines).contains("…"), "Der Name von %s passt ungekürzt in ein Feld, war: %s" % [id, " / ".join(lines)])
	# Ein Name ohne passende Trennstellen wird nur an Bindestrich und Leerzeichen getrennt und
	# notfalls gekürzt statt übergelaufen.
	var narrow: Dictionary = _screen.call("name_layout", "corpse_explosion", 30.0, 12.0)
	_check((narrow["lines"] as PackedStringArray).size() == 1 and str((narrow["lines"] as PackedStringArray)[0]).ends_with("…"),
		"Was nicht passt, wird mit Auslassungszeichen gekürzt.")
	var unknown: Dictionary = _screen.call("name_layout", "kein_gegenstand", cell * 2.0, cell)
	_check("".join(unknown["lines"] as PackedStringArray) == "kein_gegenstand", "Ein Name ohne Trennstellen bleibt ganz, wenn er passt.")


func _test_hide_signals() -> void:
	_fresh_open(21)
	var uid: int = _pack().add_item("luck", 1)
	_screen.call("pick_up", uid)
	_check(_is_open(), "Vor dem Game Over ist der Rucksack offen.")
	_events.emit_signal("game_over", {})
	_check(not _is_open() and _held() == -1, "Bei game_over verschwindet der Bildschirm und hält nichts mehr.")
	_fresh_open(22)
	_check(_is_open(), "Der Rucksack ist wieder offen.")
	_game.call("start_run", 23)
	_check(not _is_open(), "Bei run_started verschwindet der Bildschirm.")
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
