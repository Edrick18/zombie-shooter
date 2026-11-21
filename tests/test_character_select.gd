extends SceneTree
## Tests für die Kandidatenwahl (scripts/ui/character_select.gd): Anzeige, Vorauswahl,
## Markieren, Tasten, Maus, Eingabesperre und die Wahl selbst.

const CharacterDefs := preload("res://scripts/core/character_defs.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")

const SCREEN_PATH: String = "res://scripts/ui/character_select.gd"

var _failures: int = 0
var _checks: int = 0
var _game: Node
## Jede Meldung von character_chosen, in der Reihenfolge des Eintreffens.
var _chosen: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum.
	await process_frame
	_game = root.get_node("Game")
	_game.set("character_id", "")
	var screen: CanvasLayer = (load(SCREEN_PATH) as GDScript).new() as CanvasLayer
	_check(screen != null, "Das Skript der Kandidatenwahl lässt sich laden und anlegen.")
	if screen == null:
		quit(1)
		return
	screen.connect("character_chosen", _on_chosen)
	root.add_child(screen)
	await process_frame
	_test_start(screen)
	_test_open_and_cards(screen)
	_test_select(screen)
	await _test_lock(screen)
	_test_arrows(screen)
	_test_number_keys(screen)
	_test_preselection(screen)
	_test_confirm_keys(screen)
	_test_choose(screen)
	_test_mouse(screen)
	_test_open_before_tree()
	_game.set("character_id", "")
	screen.queue_free()
	await process_frame
	if _failures == 0:
		print("Alle %d Prüfungen der Kandidatenwahl bestanden." % _checks)
	else:
		printerr("%d von %d Prüfungen der Kandidatenwahl fehlgeschlagen." % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _on_chosen(id: String) -> void:
	_chosen.append(id)


func _character_id() -> String:
	return str(_game.get("character_id"))


func _test_start(screen: CanvasLayer) -> void:
	_check(not screen.visible and not bool(screen.call("is_open")), "Am Anfang ist die Kandidatenwahl versteckt.")
	_check(int(screen.get("LAYER")) == 40 and screen.layer == 40, "Die Kandidatenwahl liegt auf Ebene 40, war %d." % screen.layer)
	_check(screen.process_mode == Node.PROCESS_MODE_ALWAYS, "Die Kandidatenwahl läuft auch bei pausiertem Baum.")
	_check(not bool(screen.call("is_input_locked")), "Geschlossen gibt es keine Eingabesperre.")
	# Geschlossen wirkt keine Taste und keine Wahl.
	screen.call("_unhandled_input", _key(KEY_1))
	_check(_chosen.is_empty() and _character_id() == "", "Geschlossen wählt eine Zifferntaste nichts.")
	_check(not bool(screen.call("choose", CharacterDefs.DEFAULT)), "choose meldet false, solange die Wahl geschlossen ist.")
	_check(_chosen.is_empty() and _character_id() == "", "choose ändert geschlossen nichts.")


func _test_open_and_cards(screen: CanvasLayer) -> void:
	_game.set("character_id", "")
	screen.call("open")
	_check(screen.visible and bool(screen.call("is_open")), "open zeigt die Kandidatenwahl.")
	_check(bool(screen.call("is_input_locked")), "Direkt nach dem Öffnen ist die Eingabe gesperrt.")
	_check(_character_id() == "", "Das Öffnen allein ändert Game.character_id nicht.")
	_check(str(screen.call("selected_id")) == CharacterDefs.DEFAULT,
			"Ohne Kandidat ist der Standard markiert, war: " + str(screen.call("selected_id")))
	var cards: Array = screen.get("cards")
	_check(cards.size() == CharacterDefs.ORDER.size() and cards.size() == 3, "Es gibt 3 Karten, waren %d." % cards.size())
	var background: ColorRect = screen.get_node_or_null("Root/Background") as ColorRect
	_check(background != null and is_equal_approx(background.color.a, 1.0), "Der Hintergrund deckt die Szene vollständig ab.")
	var previous_x: float = -INF
	for i: int in mini(cards.size(), CharacterDefs.ORDER.size()):
		var id: String = CharacterDefs.ORDER[i]
		var card: Control = cards[i] as Control
		_check(card != null and str(card.get_meta("id", "")) == id, "Karte %d gehört zu %s." % [i + 1, id])
		if card == null:
			continue
		var rest: Vector2 = card.get_meta("rest_position", Vector2.ZERO) as Vector2
		_check(rest.x > previous_x, "Karte %d steht rechts von der vorherigen." % (i + 1))
		previous_x = rest.x
		var texts: Array[String] = _texts(card)
		_check(_has_text(texts, CharacterDefs.display_name(id)), "Karte %s zeigt den Namen." % id)
		_check(_has_text(texts, CharacterDefs.tagline(id)), "Karte %s zeigt den Spruch." % id)
		_check(texts.has(str(i + 1)), "Karte %s zeigt die Taste %d." % [id, i + 1])
		_check(texts.has(str(roundi(CharacterDefs.base_max_hp(id)))), "Karte %s zeigt das Leben." % id)
		var speed: float = float(CharacterDefs.extra(id).get("speed", 0.0))
		_check(texts.has(str(screen.call("speed_text", speed))), "Karte %s zeigt das Tempo." % id)
		_check(not CharacterDefs.weapons(id).is_empty(), "Kandidat %s hat Startwaffen im Rucksack." % id)
		for weapon_id: String in CharacterDefs.weapons(id):
			_check(texts.has(WeaponDefs.display_name(weapon_id)), "Karte %s zeigt die Waffe %s." % [id, weapon_id])
		for entry: Dictionary in CharacterDefs.start_items(id):
			_check(_has_text(texts, ItemDefs.display_name(str(entry["id"]))), "Karte %s zeigt den Gegenstand %s." % [id, str(entry["id"])])
		var has_points: bool = card.get_node_or_null("Facts/Caption_points") != null
		_check(has_points == (CharacterDefs.start_points(id) > 0), "Karte %s zeigt Startpunkte genau dann, wenn es welche gibt." % id)
		var bag: Control = card.get_node_or_null("Bag") as Control
		_check(bag != null, "Karte %s hat die Zeichnung des Start-Rucksacks." % id)
		if bag != null:
			_check((bag.get("cells") as Array) == (CharacterDefs.bag_cells(id) as Array), "Die Zeichnung von %s zeigt die Felder des Start-Rucksacks." % id)
			_check((bag.get("fill") as Color).is_equal_approx(CharacterDefs.color(id)), "Die Zeichnung von %s hat die Farbe des Kandidaten." % id)
	_check(str(screen.call("speed_text", 0.1)) == "+10 %", "Tempo +10 %, war: " + str(screen.call("speed_text", 0.1)))
	_check(str(screen.call("speed_text", -0.05)) == "−5 %", "Tempo −5 %, war: " + str(screen.call("speed_text", -0.05)))
	_check(str(screen.call("speed_text", 0.0)) == "normal", "Tempo normal, war: " + str(screen.call("speed_text", 0.0)))


func _test_select(screen: CanvasLayer) -> void:
	var cards: Array = screen.get("cards")
	screen.call("select", "technician")
	_check(str(screen.call("selected_id")) == "technician", "select markiert den Kandidaten.")
	_check(_character_id() == "" and _chosen.is_empty() and bool(screen.call("is_open")), "select wählt nicht.")
	if cards.size() == 3:
		_check(_is_highlighted(cards[2] as Control) and not _is_highlighted(cards[0] as Control) and not _is_highlighted(cards[1] as Control),
				"Genau die markierte Karte ist hervorgehoben.")
	screen.call("select", "gibt_es_nicht")
	_check(str(screen.call("selected_id")) == "technician", "select mit unbekannter ID ändert nichts.")
	screen.call("select", CharacterDefs.DEFAULT)
	_check(str(screen.call("selected_id")) == CharacterDefs.DEFAULT, "select wechselt zurück.")
	if cards.size() == 3:
		_check(_is_highlighted(cards[0] as Control) and not _is_highlighted(cards[2] as Control), "Die Hervorhebung wandert mit.")


func _test_lock(screen: CanvasLayer) -> void:
	_game.set("character_id", "")
	screen.call("open")
	_check(bool(screen.call("is_input_locked")), "Nach open ist die Eingabe gesperrt.")
	screen.call("_unhandled_input", _key(KEY_2))
	_check(bool(screen.call("is_open")) and _chosen.is_empty() and _character_id() == "", "Die Sperre hält eine Zifferntaste auf.")
	screen.call("_unhandled_input", _key(KEY_ENTER))
	_check(bool(screen.call("is_open")) and _chosen.is_empty(), "Die Sperre hält Enter auf.")
	screen.call("_unhandled_input", _key(KEY_RIGHT))
	_check(str(screen.call("selected_id")) == CharacterDefs.DEFAULT, "Die Sperre hält die Pfeiltasten auf.")
	var cards: Array = screen.get("cards")
	if cards.size() == 3:
		(cards[1] as Control).gui_input.emit(_click())
		_check(bool(screen.call("is_open")) and _chosen.is_empty(), "Die Sperre hält einen Klick auf.")
		(cards[1] as Control).gui_input.emit(InputEventMouseMotion.new())
		_check(str(screen.call("selected_id")) == CharacterDefs.DEFAULT, "Während der Sperre markiert die Maus nichts.")
	# Die Sperre läuft über echte Zeit ab: Bilder abwarten, höchstens 5 Sekunden.
	var deadline: int = Time.get_ticks_msec() + 5000
	while bool(screen.call("is_input_locked")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not bool(screen.call("is_input_locked")), "Die Sperre endet von selbst nach kurzer Zeit.")
	_check(bool(screen.call("is_open")) and _chosen.is_empty(), "Das Ende der Sperre wählt nichts.")
	# Auch bei pausiertem Baum läuft die Sperre ab.
	screen.call("open")
	paused = true
	deadline = Time.get_ticks_msec() + 5000
	while bool(screen.call("is_input_locked")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not bool(screen.call("is_input_locked")), "Die Sperre endet auch bei pausiertem Baum.")
	paused = false


## Erwartet die offene, entsperrte Wahl mit markiertem Standard.
func _test_arrows(screen: CanvasLayer) -> void:
	var order: Array[String] = CharacterDefs.ORDER
	screen.call("select", order[0])
	screen.call("_unhandled_input", _key(KEY_LEFT))
	_check(str(screen.call("selected_id")) == order[order.size() - 1], "Pfeil links springt vom ersten zum letzten Kandidaten.")
	screen.call("_unhandled_input", _key(KEY_RIGHT))
	_check(str(screen.call("selected_id")) == order[0], "Pfeil rechts springt vom letzten zum ersten Kandidaten.")
	screen.call("_unhandled_input", _key(KEY_RIGHT))
	_check(str(screen.call("selected_id")) == order[1], "Pfeil rechts geht einen Kandidaten weiter.")
	screen.call("_unhandled_input", _key(KEY_LEFT))
	_check(str(screen.call("selected_id")) == order[0], "Pfeil links geht einen Kandidaten zurück.")
	var release: InputEventKey = _key(KEY_RIGHT)
	release.pressed = false
	screen.call("_unhandled_input", release)
	_check(str(screen.call("selected_id")) == order[0], "Das Loslassen einer Taste bewirkt nichts.")
	var echo: InputEventKey = _key(KEY_RIGHT)
	echo.echo = true
	screen.call("_unhandled_input", echo)
	_check(str(screen.call("selected_id")) == order[0], "Eine gehaltene Taste wiederholt nichts.")
	_check(_chosen.is_empty() and _character_id() == "" and bool(screen.call("is_open")), "Pfeiltasten wählen nicht.")


func _test_number_keys(screen: CanvasLayer) -> void:
	_chosen.clear()
	screen.call("_unhandled_input", _key(KEY_4))
	_check(bool(screen.call("is_open")) and _chosen.is_empty(), "Taste 4 wählt nichts (es gibt nur 3 Kandidaten).")
	screen.call("_unhandled_input", _key(KEY_3))
	_check(_chosen == (["technician"] as Array[String]), "Taste 3 meldet genau einmal den dritten Kandidaten, war: " + str(_chosen))
	_check(_character_id() == "technician", "Taste 3 setzt Game.character_id.")
	_check(not bool(screen.call("is_open")) and not screen.visible, "Nach der Wahl ist der Bildschirm zu.")
	# Ziffernblock, über _process mit Zeitschritt entsperrt.
	_chosen.clear()
	screen.call("open")
	screen.call("_process", 0.2)
	_check(bool(screen.call("is_input_locked")), "Nach 0,2 Sekunden ist die Eingabe noch gesperrt.")
	screen.call("_process", 0.2)
	_check(not bool(screen.call("is_input_locked")), "Nach 0,4 Sekunden ist die Eingabe frei.")
	screen.call("_unhandled_input", _key(KEY_KP_2))
	_check(_chosen == (["intern"] as Array[String]) and _character_id() == "intern", "Ziffernblock 2 wählt den zweiten Kandidaten.")
	# Taste nur mit keycode (ohne Lage auf der Tastatur) zählt ebenfalls.
	_chosen.clear()
	_open_unlocked(screen)
	var plain: InputEventKey = InputEventKey.new()
	plain.keycode = KEY_1
	plain.pressed = true
	screen.call("_unhandled_input", plain)
	_check(_chosen == (["janitor"] as Array[String]) and _character_id() == "janitor", "Taste 1 wählt den ersten Kandidaten.")


func _test_preselection(screen: CanvasLayer) -> void:
	_game.set("character_id", "technician")
	screen.call("open")
	_check(str(screen.call("selected_id")) == "technician", "Ein gültiger Kandidat aus Game.character_id ist vorausgewählt.")
	var cards: Array = screen.get("cards")
	if cards.size() == 3:
		_check(_is_highlighted(cards[2] as Control) and not _is_highlighted(cards[0] as Control), "Die vorausgewählte Karte ist hervorgehoben.")
	_game.set("character_id", "gibt_es_nicht")
	screen.call("open")
	_check(str(screen.call("selected_id")) == CharacterDefs.DEFAULT, "Ein ungültiger Kandidat fällt auf den Standard zurück.")
	_check(_character_id() == "gibt_es_nicht", "open schreibt Game.character_id nicht um.")
	_game.set("character_id", "")
	screen.call("open")
	_check(str(screen.call("selected_id")) == CharacterDefs.DEFAULT, "Ohne Kandidat ist der Standard vorausgewählt.")


func _test_confirm_keys(screen: CanvasLayer) -> void:
	_chosen.clear()
	_game.set("character_id", "")
	_open_unlocked(screen)
	screen.call("select", "intern")
	screen.call("_unhandled_input", _key(KEY_ENTER))
	_check(_chosen == (["intern"] as Array[String]) and _character_id() == "intern", "Enter bestätigt die markierte Karte.")
	_check(not bool(screen.call("is_open")), "Nach Enter ist der Bildschirm zu.")
	_chosen.clear()
	_open_unlocked(screen)
	_check(str(screen.call("selected_id")) == "intern", "Beim nächsten Öffnen ist die letzte Wahl vorausgewählt.")
	screen.call("_unhandled_input", _key(KEY_RIGHT))
	screen.call("_unhandled_input", _key(KEY_SPACE))
	_check(_chosen == (["technician"] as Array[String]) and _character_id() == "technician", "Die Leertaste bestätigt die markierte Karte.")
	_chosen.clear()
	_open_unlocked(screen)
	screen.call("_unhandled_input", _key(KEY_ESCAPE))
	screen.call("_unhandled_input", _key(KEY_W))
	_check(bool(screen.call("is_open")) and _chosen.is_empty(), "Andere Tasten wählen nichts.")


func _test_choose(screen: CanvasLayer) -> void:
	_chosen.clear()
	_game.set("character_id", "janitor")
	screen.call("open")
	_check(not bool(screen.call("choose", "gibt_es_nicht")), "choose mit unbekannter ID meldet false.")
	_check(bool(screen.call("is_open")) and _chosen.is_empty() and _character_id() == "janitor", "choose mit unbekannter ID ändert nichts.")
	_check(not bool(screen.call("choose", "")), "choose ohne ID meldet false.")
	_check(bool(screen.call("is_input_locked")), "Vor der Wahl per Skript ist die Eingabe noch gesperrt.")
	_check(bool(screen.call("choose", "intern")), "choose wählt trotz Eingabesperre und meldet true.")
	_check(_character_id() == "intern", "choose setzt Game.character_id, war: " + _character_id())
	_check(_chosen == (["intern"] as Array[String]), "choose meldet character_chosen genau einmal mit der ID, war: " + str(_chosen))
	_check(not bool(screen.call("is_open")) and not screen.visible, "choose schließt den Bildschirm.")
	_check(not bool(screen.call("is_input_locked")), "Geschlossen ist nichts mehr gesperrt.")
	_check(not bool(screen.call("choose", "technician")), "Ein zweites choose bei geschlossenem Bildschirm meldet false.")
	_check(_character_id() == "intern" and _chosen.size() == 1, "Das zweite choose ändert nichts.")
	screen.call("_unhandled_input", _key(KEY_1))
	_check(_character_id() == "intern" and _chosen.size() == 1, "Nach der Wahl wirken die Tasten nicht mehr.")
	# close schließt ohne Wahl.
	screen.call("open")
	screen.call("close")
	_check(not bool(screen.call("is_open")) and _character_id() == "intern" and _chosen.size() == 1, "close schließt ohne Wahl.")


func _test_mouse(screen: CanvasLayer) -> void:
	var cards: Array = screen.get("cards")
	if cards.size() != 3:
		return
	_chosen.clear()
	_game.set("character_id", "")
	_open_unlocked(screen)
	(cards[2] as Control).gui_input.emit(InputEventMouseMotion.new())
	_check(str(screen.call("selected_id")) == "technician", "Die Maus markiert die Karte, über die sie bewegt wird.")
	_check(_chosen.is_empty() and bool(screen.call("is_open")), "Die Mausbewegung wählt nicht.")
	var right_click: InputEventMouseButton = _click()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	(cards[1] as Control).gui_input.emit(right_click)
	_check(_chosen.is_empty() and bool(screen.call("is_open")), "Ein Rechtsklick wählt nicht.")
	var release: InputEventMouseButton = _click()
	release.pressed = false
	(cards[1] as Control).gui_input.emit(release)
	_check(_chosen.is_empty() and bool(screen.call("is_open")), "Das Loslassen der Maustaste wählt nicht.")
	(cards[1] as Control).gui_input.emit(_click())
	_check(_chosen == (["intern"] as Array[String]) and _character_id() == "intern", "Ein Klick auf die Karte wählt den Kandidaten.")
	_check(not bool(screen.call("is_open")), "Nach dem Klick ist der Bildschirm zu.")
	(cards[0] as Control).gui_input.emit(_click())
	_check(_chosen.size() == 1 and _character_id() == "intern", "Ein Klick bei geschlossenem Bildschirm wählt nichts.")


## open vor dem Einhängen in den Baum darf nicht scheitern.
func _test_open_before_tree() -> void:
	_game.set("character_id", "intern")
	var screen: CanvasLayer = (load(SCREEN_PATH) as GDScript).new() as CanvasLayer
	screen.call("open")
	_check(bool(screen.call("is_open")) and (screen.get("cards") as Array).size() == 3, "open baut die Karten auch vor dem Einhängen in den Baum.")
	_check(str(screen.call("selected_id")) == "intern", "Auch dann gilt die Vorauswahl.")
	root.add_child(screen)
	_check(bool(screen.call("is_open")) and (screen.get("cards") as Array).size() == 3, "Das Einhängen lässt die offene Wahl offen und baut nichts doppelt.")
	screen.call("close")
	screen.queue_free()


# --- Helfer ---------------------------------------------------------------------------

## Öffnet die Wahl und lässt die Eingabesperre ablaufen.
func _open_unlocked(screen: CanvasLayer) -> void:
	screen.call("open")
	screen.call("_process", 1.0)


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _click() -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


## Alle Texte der Labels unter diesem Knoten.
func _texts(node: Node) -> Array[String]:
	var result: Array[String] = []
	var label: Label = node as Label
	if label != null:
		result.append(label.text)
	for child: Node in node.get_children():
		result.append_array(_texts(child))
	return result


## Kommt der Text in einem der Texte vor (auch als Teil)?
func _has_text(texts: Array[String], wanted: String) -> bool:
	for text: String in texts:
		if text.contains(wanted):
			return true
	return false


## Hervorgehoben: der Aufkleber "Pick" ist zu sehen und die Karte ist nicht abgedunkelt.
func _is_highlighted(card: Control) -> bool:
	var pick: Control = card.get_node_or_null("Pick") as Control
	return pick != null and pick.visible and card.modulate.is_equal_approx(Color.WHITE)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
