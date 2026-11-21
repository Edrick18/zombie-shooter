extends SceneTree
## Tests für den Bildschirm „Programm“ (scripts/ui/unlock_screen.gd, Abschnitt 22.5): Karten der
## elf Pakete, Zustände (gekauft, kaufbar, zu teuer), Kaufen über Knopf, Taste und Skript,
## Kontostand und Fortschritt, die Tafel mit dem Inhalt, Tasten, Schließen und das Zusammenspiel
## mit Kandidatenwahl und Game Over (öffnen, Eingabe sperren, zurückkehren).
##
## Headless gilt in Game.progress alles als freigeschaltet. Der Test setzt einen frischen
## Fortschritt ohne unlock_all ein und stellt am Ende den alten Stand wieder her (frischer
## Fortschritt mit unlock_all = true), damit andere Tests nicht leiden.

const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UnlockDefs := preload("res://scripts/core/unlock_defs.gd")
const ProgressState := preload("res://scripts/core/progress_state.gd")
const CharacterDefs := preload("res://scripts/core/character_defs.gd")

const SCREEN_PATH: String = "res://scripts/ui/unlock_screen.gd"
const STATE_PLAYING: int = 1
const STATE_GAME_OVER: int = 4

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
var _screen: CanvasLayer
var _closed: int = 0
var _unlocked: Array[String] = []
var _bank_changes: Array[int] = []
var _run_starts: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum.
	await process_frame
	_game = root.get_node("Game")
	_events = root.get_node("Events")
	_game.set("character_id", "")
	_events.connect("pack_unlocked", func(pack_id: String) -> void: _unlocked.append(pack_id))
	_events.connect("bank_changed", func(_bank: int, gained: int) -> void: _bank_changes.append(gained))
	_events.connect("run_started", func() -> void: _run_starts += 1)
	_fresh_progress(0)
	var script: GDScript = load(SCREEN_PATH) as GDScript
	_check(script != null, "unlock_screen.gd lädt.")
	if script != null:
		_screen = script.new() as CanvasLayer
		_screen.connect("closed", func() -> void: _closed += 1)
		root.add_child(_screen)
		await process_frame
		_test_start()
		_test_cards()
		_test_empty_bank()
		_test_states_and_lock()
		_test_buy()
		_test_detail()
		await _test_layout()
		_test_keys()
		_test_signals_from_outside()
		_test_all_bought()
		_test_open_before_tree(script)
		await _test_character_select()
		await _test_game_over()
		_screen.queue_free()
		await process_frame
	# Alten Stand wiederherstellen: ohne Bildschirm gilt alles als freigeschaltet.
	var restored: ProgressState = ProgressState.new()
	restored.unlock_all = true
	_game.set("progress", restored)
	_game.set("character_id", "")
	paused = false
	(load("res://scripts/ui/hud.gd") as GDScript).call("clear_font_cache")
	await process_frame
	await process_frame
	if _failures == 0:
		print("Alle %d Prüfungen für den Bildschirm Programm bestanden." % _checks)
	else:
		printerr("%d von %d Prüfungen für den Bildschirm Programm fehlgeschlagen." % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


# --- Helfer ---------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures += 1
		printerr("FEHLER: %s (erwartet %s, bekommen %s)" % [message, str(expected), str(actual)])


func _progress() -> ProgressState:
	return _game.get("progress") as ProgressState


## Setzt einen frischen Fortschritt ohne unlock_all und mit diesem Konto ein.
func _fresh_progress(bank: int) -> ProgressState:
	var progress: ProgressState = ProgressState.new()
	progress.unlock_all = false
	progress.add_bank(bank)
	_game.set("progress", progress)
	return progress


func _label(property: String) -> Label:
	var label: Label = _screen.get(property) as Label
	if label == null:
		_failures += 1
		printerr("FEHLER: Label-Eigenschaft fehlt: %s" % property)
		return Label.new()
	return label


func _card(pack_id: String) -> Control:
	var card: Control = _screen.call("card_of", pack_id) as Control
	if card == null:
		_failures += 1
		printerr("FEHLER: Karte fehlt: %s" % pack_id)
		return Control.new()
	return card


func _text(node: Node, path: String) -> String:
	var label: Label = node.get_node_or_null(path) as Label
	if label == null:
		_failures += 1
		printerr("FEHLER: Label fehlt: %s" % path)
		return ""
	return label.text


func _state(pack_id: String) -> String:
	return str(_screen.call("pack_state", pack_id))


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


## Öffnet den Bildschirm und lässt die Eingabesperre ablaufen.
func _open_unlocked() -> void:
	_screen.call("open")
	for _i: int in 12:
		_screen.call("_process", 0.05)


func _plain(text: String) -> String:
	return text.replace(String.chr(0x00A0), " ")


func _font() -> Font:
	return (load("res://scripts/ui/hud.gd") as GDScript).call("show_font") as Font


func _format(value: int) -> String:
	return str((load("res://scripts/ui/hud.gd") as GDScript).call("format_int", value))


# --- Tests ----------------------------------------------------------------------------

func _test_start() -> void:
	_check(not _screen.visible and not bool(_screen.call("is_open")), "Am Anfang ist das Programm versteckt.")
	_equal(_screen.layer, 45, "Das Programm liegt auf Ebene 45 (über Game Over 30 und Kandidatenwahl 40).")
	_equal(_screen.process_mode, Node.PROCESS_MODE_ALWAYS, "Das Programm läuft auch bei pausiertem Baum.")
	_check(not bool(_screen.call("is_input_locked")), "Geschlossen gibt es keine Eingabesperre.")
	_check(not bool(_screen.call("buy", "camera_team")), "Geschlossen kauft buy nichts.")
	_screen.call("close")
	_equal(_closed, 0, "close bei geschlossenem Bildschirm meldet nichts.")
	_screen.call("_unhandled_input", _key(KEY_ENTER))
	_check(_unlocked.is_empty(), "Geschlossen wirkt keine Taste.")


func _test_cards() -> void:
	var cards: Array = _screen.get("cards")
	_equal(cards.size(), UnlockDefs.PACK_ORDER.size(), "Je Paket gibt es eine Karte.")
	_equal(cards.size(), 11, "Es sind elf Karten.")
	for i: int in mini(cards.size(), UnlockDefs.PACK_ORDER.size()):
		var pack_id: String = UnlockDefs.PACK_ORDER[i]
		var card: Control = cards[i] as Control
		_equal(str(card.get_meta("id", "")), pack_id, "Karte %d gehört zum Paket %s." % [i + 1, pack_id])
		_check(_screen.call("card_of", pack_id) == card, "card_of findet die Karte von %s." % pack_id)
		_equal(_text(card, "Name"), UnlockDefs.pack_name(pack_id), "Die Karte von %s zeigt den Namen." % pack_id)
		_check(_text(card, "Price").contains(_format(UnlockDefs.pack_price(pack_id))), "Die Karte von %s zeigt den Preis, war: %s" % [pack_id, _text(card, "Price")])
		var items: Array[String] = UnlockDefs.pack_items(pack_id)
		for n: int in items.size():
			_equal(_text(card, "Items/Item_%d" % n), ItemDefs.display_name(items[n]), "Die Karte von %s nennt Teil %d." % [pack_id, n + 1])
			var dot: ColorRect = card.get_node_or_null("Items/Dot_%d" % n) as ColorRect
			_check(dot != null and dot.color.is_equal_approx(ItemDefs.color(items[n])), "Teil %d von %s hat das Farbfeld seiner Art." % [n + 1, pack_id])
		_check(card.get_node_or_null("Buy") is Button, "Die Karte von %s hat einen Kaufknopf." % pack_id)
	_check(_screen.call("card_of", "gibt_es_nicht") == null, "card_of kennt kein unbekanntes Paket.")
	# Art eines Teils in einfachen Worten.
	_equal(str(_screen.call("kind_text", "machine_pistol")), "Waffe · 1 Hand", "Eine Einhand-Waffe nennt eine Hand.")
	_equal(str(_screen.call("kind_text", "minigun")), "Waffe · 2 Hände", "Eine Zweihand-Waffe nennt zwei Hände.")
	_equal(str(_screen.call("kind_text", "cam_tele")), "Kamera", "Eine Kamera heißt Kamera.")
	_equal(str(_screen.call("kind_text", "cam_lens")), "Kamera-Zubehör", "Das Objektiv ist Kamera-Zubehör.")
	_equal(str(_screen.call("kind_text", "cam_uplink")), "Kamera-Zubehör", "Die Sendeleitung ist Kamera-Zubehör.")
	_equal(str(_screen.call("kind_text", "replay")), "Verstärker", "Die Wiederholung ist ein Verstärker.")
	_equal(str(_screen.call("kind_text", "snack")), "Gegenstand", "Der Pausensnack ist ein Gegenstand.")


func _test_empty_bank() -> void:
	_fresh_progress(0)
	_screen.call("open")
	_check(_screen.visible and bool(_screen.call("is_open")), "open zeigt das Programm.")
	_equal(_label("headline_label").text, "DAS PROGRAMM", "Überschrift.")
	_equal(_label("bank_label").text, "0", "Ohne Konto steht dort 0.")
	_equal(_label("progress_label").text, "0 VON 11 PAKETEN", "Fortschritt ohne Kauf.")
	_equal(_label("best_wave_label").text, "Beste Welle: 0", "Beste Welle ohne Lauf.")
	_equal(_label("runs_label").text, "Läufe: 0", "Zahl der Läufe ohne Lauf.")
	_equal(str(_screen.call("selected_id")), UnlockDefs.PACK_ORDER[0], "Ohne kaufbares Paket ist das erste markiert.")
	for pack_id: String in UnlockDefs.PACK_ORDER:
		var card: Control = _card(pack_id)
		var price: int = UnlockDefs.pack_price(pack_id)
		_equal(_state(pack_id), "locked", "Ohne Konto ist %s zu teuer." % pack_id)
		_equal(int(_screen.call("missing_points", pack_id)), price, "Es fehlt der ganze Preis von %s." % pack_id)
		_equal(_text(card, "State"), "Es fehlen %s" % _format(price), "Die Karte von %s nennt den fehlenden Betrag." % pack_id)
		_check((card.get_node("State") as Control).visible and not (card.get_node("Buy") as Control).visible,
				"Die Karte von %s zeigt den fehlenden Betrag statt des Kaufknopfs." % pack_id)
	var buy_button: Button = _screen.get("buy_button") as Button
	_check(buy_button.visible and buy_button.disabled, "Der große Kaufknopf ist ausgegraut, wenn das Konto nicht reicht.")
	_check(buy_button.text.contains(_format(UnlockDefs.pack_price(UnlockDefs.PACK_ORDER[0]))), "Der große Knopf nennt, was fehlt, war: " + buy_button.text)
	_check(not bool(_screen.call("buy", "camera_team")), "Ohne Konto kauft buy nichts.")
	_check(_unlocked.is_empty() and _progress().packs.is_empty() and _progress().bank == 0, "Der gescheiterte Kauf ändert nichts.")
	_equal(_state("gibt_es_nicht"), "", "Ein unbekanntes Paket hat keinen Zustand.")
	_equal(int(_screen.call("missing_points", "gibt_es_nicht")), 0, "Einem unbekannten Paket fehlt nichts.")


func _test_states_and_lock() -> void:
	var progress: ProgressState = _fresh_progress(5200)
	progress.record_run(7)
	progress.record_run(4)
	_screen.call("open")
	_equal(_label("bank_label").text, "5.200", "Der Kontostand steht mit Tausenderpunkt da.")
	_equal(_label("best_wave_label").text, "Beste Welle: 7", "Die beste Welle kommt aus Game.progress.")
	_equal(_label("runs_label").text, "Läufe: 2", "Die Zahl der Läufe kommt aus Game.progress.")
	var buyable: int = 0
	for pack_id: String in UnlockDefs.PACK_ORDER:
		var card: Control = _card(pack_id)
		var price: int = UnlockDefs.pack_price(pack_id)
		if price <= 5200:
			buyable += 1
			_equal(_state(pack_id), "buyable", "Mit 5.200 ist %s kaufbar." % pack_id)
			_equal(int(_screen.call("missing_points", pack_id)), 0, "Für %s fehlt nichts." % pack_id)
			_check((card.get_node("Buy") as Control).visible and not (card.get_node("State") as Control).visible,
					"Die Karte von %s zeigt den Kaufknopf." % pack_id)
		else:
			_equal(_state(pack_id), "locked", "Mit 5.200 ist %s zu teuer." % pack_id)
			_equal(_text(card, "State"), "Es fehlen %s" % _format(price - 5200), "Die Karte von %s nennt, was fehlt." % pack_id)
	_equal(buyable, 8, "Mit 5.200 sind acht Pakete kaufbar.")
	_equal(str(_screen.call("selected_id")), "camera_team", "Markiert ist das erste kaufbare Paket.")
	# Sperre direkt nach dem Öffnen: Knopf und Taste kaufen nichts.
	_check(bool(_screen.call("is_input_locked")), "Direkt nach dem Öffnen ist das Kaufen gesperrt.")
	(_card("camera_team").get_node("Buy") as Button).pressed.emit()
	(_screen.get("buy_button") as Button).pressed.emit()
	_screen.call("_unhandled_input", _key(KEY_ENTER))
	_check(not bool(_screen.call("request_buy", "camera_team")), "request_buy lehnt während der Sperre ab.")
	_check(_unlocked.is_empty() and _progress().bank == 5200, "Während der Sperre wird nichts gekauft.")
	for _i: int in 12:
		_screen.call("_process", 0.05)
	_check(not bool(_screen.call("is_input_locked")), "Die Sperre endet nach kurzer Zeit.")


## Erwartet das offene, entsperrte Programm mit 5.200 auf dem Konto.
func _test_buy() -> void:
	_unlocked.clear()
	_bank_changes.clear()
	# Knopf auf der Karte.
	(_card("rapid_fire").get_node("Buy") as Button).pressed.emit()
	_equal(_unlocked, ["rapid_fire"] as Array[String], "Der Knopf auf der Karte kauft das Paket (pack_unlocked).")
	_equal(_bank_changes, [-2000] as Array[int], "Der Kauf meldet bank_changed mit dem negativen Preis.")
	_check(_progress().has_pack("rapid_fire") and _progress().bank == 3200, "Das Paket ist gekauft und der Preis abgezogen.")
	_equal(_label("bank_label").text, "3.200", "Der Kontostand ist sofort neu.")
	_equal(_label("progress_label").text, "1 VON 11 PAKETEN", "Der Fortschritt zählt das Paket.")
	_equal(_state("rapid_fire"), "owned", "Das Paket gilt als gekauft.")
	var bought: Control = _card("rapid_fire")
	_equal(_text(bought, "State"), "GEKAUFT", "Die Karte zeigt GEKAUFT.")
	_check(not (bought.get_node("Buy") as Control).visible, "Die gekaufte Karte hat keinen Kaufknopf mehr.")
	_equal(str(_screen.call("selected_id")), "rapid_fire", "Das gekaufte Paket ist markiert.")
	_check(absf(float((_screen.get("progress_bar") as Control).get("ratio")) - 1.0 / 11.0) < 0.001, "Der Balken zeigt den Anteil gekaufter Pakete.")
	# Andere Karten folgen dem neuen Konto: Präzision (3.500) ist jetzt zu teuer.
	_equal(_state("precision"), "locked", "Nach dem Kauf ist Präzision zu teuer.")
	_equal(_text(_card("precision"), "State"), "Es fehlen 300", "Die Karte von Präzision nennt den neuen fehlenden Betrag.")
	_equal(_state("poison_kitchen"), "buyable", "Die Giftküche (3.000) ist weiter kaufbar.")
	# Zweimal kaufen geht nicht.
	_check(not bool(_screen.call("buy", "rapid_fire")), "Ein gekauftes Paket lässt sich nicht noch einmal kaufen.")
	_check(not bool(_screen.call("buy", "gibt_es_nicht")), "Ein unbekanntes Paket lässt sich nicht kaufen.")
	_check(not bool(_screen.call("buy", "grand_finale")), "Ein zu teures Paket lässt sich nicht kaufen.")
	_equal(_progress().bank, 3200, "Die gescheiterten Käufe kosten nichts.")
	_equal(_unlocked.size(), 1, "Die gescheiterten Käufe melden nichts.")
	# Großer Knopf der Tafel kauft das markierte Paket.
	_screen.call("select", "first_aid")
	var buy_button: Button = _screen.get("buy_button") as Button
	_check(buy_button.visible and not buy_button.disabled and buy_button.text == "KAUFEN: 2.500", "Der große Knopf nennt den Preis, war: " + buy_button.text)
	buy_button.pressed.emit()
	_check(_progress().has_pack("first_aid") and _progress().bank == 700, "Der große Knopf kauft das markierte Paket.")
	_check(not buy_button.visible and (_screen.get("owned_label") as Control).visible, "Danach steht in der Tafel GEKAUFT statt des Knopfs.")
	_equal(_label("progress_label").text, "2 VON 11 PAKETEN", "Zwei Pakete sind gekauft.")
	# buy(pack_id) kauft sofort und ohne Sperre.
	_progress().add_bank(1300)
	_screen.call("open")
	_check(bool(_screen.call("is_input_locked")), "Nach erneutem Öffnen ist die Eingabe wieder gesperrt.")
	_check(bool(_screen.call("buy", "camera_team")), "buy kauft trotz Sperre.")
	_check(_progress().has_pack("camera_team") and _progress().bank == 0, "Das Kamerateam ist gekauft, das Konto leer.")
	_equal(_progress().packs, ["rapid_fire", "first_aid", "camera_team"] as Array[String], "Die Pakete stehen in der Reihenfolge des Kaufs.")
	_check(_progress().is_item_unlocked("cam_tele") and not _progress().is_item_unlocked("minigun"), "Nur der Inhalt gekaufter Pakete ist freigeschaltet.")


func _test_detail() -> void:
	_fresh_progress(2500)
	_open_unlocked()
	var items_root: Control = _screen.get("detail_items") as Control
	for pack_id: String in UnlockDefs.PACK_ORDER:
		_screen.call("select", pack_id)
		_equal(str(_screen.call("selected_id")), pack_id, "select markiert %s." % pack_id)
		_equal(_label("detail_name_label").text, UnlockDefs.pack_name(pack_id), "Die Tafel nennt das Paket %s." % pack_id)
		var blocks: Array[Node] = []
		for child: Node in items_root.get_children():
			if not child.is_queued_for_deletion():
				blocks.append(child)
		var items: Array[String] = UnlockDefs.pack_items(pack_id)
		_equal(blocks.size(), items.size(), "Die Tafel zeigt alle Teile von %s." % pack_id)
		for n: int in mini(blocks.size(), items.size()):
			var block: Node = blocks[n]
			_equal(str(block.name), "Item_%s" % items[n], "Teil %d von %s steht an seiner Stelle." % [n + 1, pack_id])
			_equal(_text(block, "Name"), ItemDefs.display_name(items[n]), "Die Tafel nennt den Namen von %s." % items[n])
			_equal(_text(block, "Kind"), str(_screen.call("kind_text", items[n])), "Die Tafel nennt die Art von %s." % items[n])
			_equal(_plain(_text(block, "Text")), ItemDefs.description(items[n], 1), "Die Tafel zeigt den Wirkungstext von %s." % items[n])
			_check(block.get_node_or_null("Icon") != null, "Die Tafel zeigt ein Bild von %s." % items[n])
		var price: int = UnlockDefs.pack_price(pack_id)
		var state_text: String = _label("detail_state_label").text
		var buy_button: Button = _screen.get("buy_button") as Button
		if price <= 2500:
			_check(state_text.contains(_format(price)) and not state_text.contains("fehlen"), "Die Tafel nennt den Preis von %s, war: %s" % [pack_id, state_text])
			_check(not buy_button.disabled, "Der Kaufknopf ist frei für %s." % pack_id)
		else:
			_check(state_text.contains(_format(price)) and state_text.contains("es fehlen %s" % _format(price - 2500)),
					"Die Tafel nennt Preis und fehlenden Betrag von %s, war: %s" % [pack_id, state_text])
			_check(buy_button.disabled and buy_button.text == "ES FEHLEN %s" % _format(price - 2500), "Der Kaufknopf nennt, was für %s fehlt, war: %s" % [pack_id, buy_button.text])
	_screen.call("select", "gibt_es_nicht")
	_equal(str(_screen.call("selected_id")), UnlockDefs.PACK_ORDER[UnlockDefs.PACK_ORDER.size() - 1], "select mit unbekannter ID ändert nichts.")
	# Markierung: genau die markierte Karte ist hervorgehoben (weißer Rand, etwas größer).
	_screen.call("select", "precision")
	for pack_id: String in UnlockDefs.PACK_ORDER:
		var card: Control = _card(pack_id)
		var box: StyleBoxFlat = card.get_meta("box") as StyleBoxFlat
		var highlighted: bool = box.border_color.is_equal_approx(Color.WHITE) and card.scale.x > 1.0
		_equal(highlighted, pack_id == "precision", "Hervorgehoben ist nur die markierte Karte (%s)." % pack_id)
	# Maus: Darüberfahren markiert, ein Klick auf die Karte kauft nicht.
	_card("big_bang").mouse_entered.emit()
	_equal(str(_screen.call("selected_id")), "big_bang", "Die Maus markiert die Karte, über die sie fährt.")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_card("camera_team").gui_input.emit(click)
	_equal(str(_screen.call("selected_id")), "camera_team", "Ein Klick auf die Karte markiert sie.")
	_check(_progress().packs.is_empty() and _progress().bank == 2500, "Ein Klick auf die Karte kauft noch nichts: Dafür gibt es den Knopf.")


## Bei 1280x720 liegt alles im Bild, nichts überlappt, und jeder Text passt in sein Feld.
func _test_layout() -> void:
	_fresh_progress(2500)
	_open_unlocked()
	await process_frame
	await process_frame
	var view: Rect2 = root.get_visible_rect()
	_check(view.size.x >= 1279.0 and view.size.y >= 719.0, "Aufbau: Das Bild ist 1280 x 720 groß, war %s." % str(view.size))
	var font: Font = _font()
	var cards: Array = _screen.get("cards")
	var rects: Array[Rect2] = []
	var detail: Control = _screen.get_node("Root/Stage/Detail") as Control
	var detail_rect: Rect2 = detail.get_global_rect()
	_check(view.encloses(detail_rect), "Die Tafel liegt ganz im Bild (%s)." % str(detail_rect))
	for entry: Variant in cards:
		var card: Control = entry as Control
		# Die markierte Karte ist etwas vergrößert: Gemessen wird ihre Grundfläche.
		var rect: Rect2 = Rect2(card.get_parent_control().global_position + card.position, card.size)
		_check(view.encloses(rect), "Die Karte %s liegt ganz im Bild (%s)." % [card.name, str(rect)])
		_check(not rect.intersects(detail_rect), "Die Karte %s überdeckt die Tafel nicht." % card.name)
		for other: Rect2 in rects:
			_check(not rect.intersects(other), "Die Karte %s überlappt keine andere." % card.name)
		rects.append(rect)
		for child: Node in card.find_children("*", "Label", true, false):
			var label: Label = child as Label
			var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x
			_check(width <= label.size.x + 1.0, "Der Text „%s“ passt in sein Feld auf der Karte %s (%d von %d)." % [label.text, card.name, roundi(width), roundi(label.size.x)])
			_check(label.position.x >= -0.5 and label.position.x + label.size.x <= (label.get_parent() as Control).size.x + 0.5, "Das Feld von „%s“ bleibt in der Karte." % label.text)
	var stats: Control = _screen.get_node("Root/Stage/Cards/Stats") as Control
	var stats_rect: Rect2 = stats.get_global_rect()
	_check(view.encloses(stats_rect), "Das Fach mit dem Fortschritt liegt ganz im Bild.")
	for other: Rect2 in rects:
		_check(not stats_rect.intersects(other), "Das Fach mit dem Fortschritt überlappt keine Karte.")
	var back: Button = _screen.get("back_button") as Button
	_check(stats_rect.encloses(back.get_global_rect()), "Der Knopf Zurück liegt im Fach mit dem Fortschritt.")
	var bank: Control = _screen.get_node("Root/Stage/Bank") as Control
	_check(view.encloses(bank.get_global_rect()), "Der Kontostand liegt ganz im Bild.")
	# Tafel: Für jedes Paket passen alle vier Teile mit ihrem ganzen Text hinein.
	var items_root: Control = _screen.get("detail_items") as Control
	for pack_id: String in UnlockDefs.PACK_ORDER:
		_screen.call("select", pack_id)
		await process_frame
		var bottom: float = 0.0
		for child: Node in items_root.get_children():
			if child.is_queued_for_deletion():
				continue
			var block: Control = child as Control
			bottom = maxf(bottom, block.position.y + block.size.y)
			var text_label: Label = block.get_node("Text") as Label
			var line_step: float = float(text_label.get_line_height()) + float(text_label.get_theme_constant("line_spacing"))
			var needed: float = float(text_label.get_line_count()) * line_step - float(text_label.get_theme_constant("line_spacing"))
			_check(needed <= text_label.size.y + 1.0, "Der Wirkungstext von %s passt in sein Feld (%d von %d)." % [block.name, roundi(needed), roundi(text_label.size.y)])
			_check(text_label.get_theme_font_size("font_size") >= 11, "Der Wirkungstext von %s ist mindestens 11 Punkt groß." % block.name)
			var name_label: Label = block.get_node("Name") as Label
			var kind_label: Label = block.get_node("Kind") as Label
			_check(name_label.position.x + name_label.size.x <= kind_label.position.x + 0.5, "Name und Art von %s stehen nebeneinander." % block.name)
		_check(bottom <= items_root.size.y + 0.5, "Die Teile von %s passen in die Tafel (%d von %d)." % [pack_id, roundi(bottom), roundi(items_root.size.y)])
	# Ein sehr großes Konto passt in sein Feld.
	_progress().add_bank(98765432)
	_screen.call("refresh")
	var bank_label: Label = _label("bank_label")
	var bank_width: float = (load("res://scripts/ui/hud.gd") as GDScript).call("show_font", true).get_string_size(bank_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, bank_label.get_theme_font_size("font_size")).x
	_check(bank_width <= bank_label.size.x + 1.0, "Auch ein Konto von %s passt in sein Feld." % bank_label.text)


func _test_keys() -> void:
	_fresh_progress(4000)
	_open_unlocked()
	var order: Array[String] = UnlockDefs.PACK_ORDER
	_screen.call("select", order[0])
	_screen.call("_unhandled_input", _key(KEY_RIGHT))
	_equal(str(_screen.call("selected_id")), order[1], "Pfeil rechts geht ein Paket weiter.")
	_screen.call("_unhandled_input", _key(KEY_DOWN))
	_equal(str(_screen.call("selected_id")), order[5], "Pfeil unten geht eine Zeile tiefer (vier Spalten).")
	_screen.call("_unhandled_input", _key(KEY_LEFT))
	_equal(str(_screen.call("selected_id")), order[4], "Pfeil links geht ein Paket zurück.")
	_screen.call("_unhandled_input", _key(KEY_UP))
	_equal(str(_screen.call("selected_id")), order[0], "Pfeil oben geht eine Zeile höher.")
	_screen.call("_unhandled_input", _key(KEY_UP))
	_equal(str(_screen.call("selected_id")), order[0], "Am oberen Rand bleibt die Markierung stehen.")
	_screen.call("_unhandled_input", _key(KEY_LEFT))
	_equal(str(_screen.call("selected_id")), order[order.size() - 1], "Pfeil links springt vom ersten zum letzten Paket.")
	_screen.call("_unhandled_input", _key(KEY_DOWN))
	_equal(str(_screen.call("selected_id")), order[order.size() - 1], "Am unteren Rand bleibt die Markierung stehen.")
	_screen.call("_unhandled_input", _key(KEY_RIGHT))
	_equal(str(_screen.call("selected_id")), order[0], "Pfeil rechts springt vom letzten zum ersten Paket.")
	var release: InputEventKey = _key(KEY_RIGHT)
	release.pressed = false
	_screen.call("_unhandled_input", release)
	_equal(str(_screen.call("selected_id")), order[0], "Das Loslassen einer Taste bewirkt nichts.")
	# Enter kauft das markierte Paket, die Leertaste auch.
	_unlocked.clear()
	_screen.call("_unhandled_input", _key(KEY_ENTER))
	_equal(_unlocked, ["camera_team"] as Array[String], "Enter kauft das markierte Paket.")
	_screen.call("_unhandled_input", _key(KEY_ENTER))
	_equal(_unlocked.size(), 1, "Ein zweites Enter kauft dasselbe Paket nicht noch einmal.")
	_screen.call("select", "rapid_fire")
	_screen.call("_unhandled_input", _key(KEY_SPACE))
	_equal(_unlocked, ["camera_team", "rapid_fire"] as Array[String], "Die Leertaste kauft das markierte Paket.")
	_equal(_progress().bank, 0, "Beide Käufe sind bezahlt.")
	# Esc schließt und meldet closed, der Knopf Zurück auch.
	_closed = 0
	_screen.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(not bool(_screen.call("is_open")), "Esc schließt das Programm.")
	_equal(_closed, 1, "Das Schließen meldet closed genau einmal.")
	_screen.call("_unhandled_input", _key(KEY_ENTER))
	_equal(_unlocked.size(), 2, "Geschlossen kauft Enter nichts.")
	_open_unlocked()
	_equal((_screen.get("back_button") as Button).text, "ZURÜCK", "Der Knopf heißt Zurück.")
	(_screen.get("back_button") as Button).pressed.emit()
	_check(not bool(_screen.call("is_open")), "Der Knopf Zurück schließt das Programm.")
	_equal(_closed, 2, "Auch der Knopf meldet closed.")


## Konto und Pakete ändern sich von außen: Die Anzeige folgt den Signalen.
func _test_signals_from_outside() -> void:
	_fresh_progress(0)
	_open_unlocked()
	_equal(_state("camera_team"), "locked", "Aufbau: Ohne Konto ist das Kamerateam zu teuer.")
	_progress().add_bank(2600)
	_events.emit_signal("bank_changed", 2600, 2600)
	_equal(_label("bank_label").text, "2.600", "bank_changed bringt den neuen Kontostand.")
	_check((_card("camera_team").get_node("Buy") as Control).visible, "bank_changed macht die Karte kaufbar.")
	_check(bool(_game.call("buy_pack", "first_aid")), "Game.buy_pack kauft die Erste Hilfe.")
	_equal(_text(_card("first_aid"), "State"), "GEKAUFT", "Ein Kauf über Game.buy_pack erscheint sofort auf der Karte.")
	_equal(_label("bank_label").text, "100", "Der Kontostand folgt dem Kauf von außen.")
	_equal(_state("camera_team"), "locked", "Danach reicht das Konto nicht mehr für das Kamerateam.")
	# Ein neuer Lauf schließt das Programm.
	_closed = 0
	_game.call("start_run", 3)
	_check(not bool(_screen.call("is_open")), "Bei run_started schließt sich das Programm.")
	_equal(_closed, 1, "Auch dabei kommt closed.")
	_game.call("end_run")
	paused = false


func _test_all_bought() -> void:
	var progress: ProgressState = _fresh_progress(100000)
	var total_price: int = 0
	for pack_id: String in UnlockDefs.PACK_ORDER:
		total_price += UnlockDefs.pack_price(pack_id)
		progress.buy(pack_id)
	_open_unlocked()
	_equal(_label("progress_label").text, "11 VON 11 PAKETEN", "Alle Pakete sind gekauft.")
	_equal(str(_screen.call("selected_id")), UnlockDefs.PACK_ORDER[0], "Ist alles gekauft, ist das erste Paket markiert.")
	for pack_id: String in UnlockDefs.PACK_ORDER:
		_equal(_state(pack_id), "owned", "%s ist gekauft." % pack_id)
		_equal(_text(_card(pack_id), "State"), "GEKAUFT", "Die Karte von %s zeigt GEKAUFT." % pack_id)
	_check(not (_screen.get("buy_button") as Control).visible and (_screen.get("owned_label") as Control).visible, "In der Tafel steht GEKAUFT.")
	_check(_label("detail_state_label").text.begins_with("Gekauft"), "Die Tafel sagt, dass das Paket gekauft ist.")
	_screen.call("_unhandled_input", _key(KEY_ENTER))
	_equal(progress.bank, 100000 - total_price, "Enter kauft nichts mehr: Das Konto bleibt, wie es nach den elf Käufen war.")
	_screen.call("close")


## open vor dem Einhängen in den Baum darf nicht scheitern.
func _test_open_before_tree(script: GDScript) -> void:
	_fresh_progress(2000)
	var screen: CanvasLayer = script.new() as CanvasLayer
	screen.call("open")
	_check(bool(screen.call("is_open")) and (screen.get("cards") as Array).size() == 11, "open baut die Karten auch vor dem Einhängen in den Baum.")
	_equal((screen.get("bank_label") as Label).text, "2.000", "Auch dann stimmt der Kontostand.")
	root.add_child(screen)
	_check(bool(screen.call("is_open")) and (screen.get("cards") as Array).size() == 11, "Das Einhängen baut nichts doppelt.")
	screen.call("close")
	screen.queue_free()


## Kandidatenwahl: Knopf und Taste P öffnen das Programm darüber, die Wahl nimmt solange keine
## Eingabe an und ist danach wieder da.
func _test_character_select() -> void:
	_fresh_progress(12340)
	_game.set("character_id", "")
	var select: CanvasLayer = (load("res://scripts/ui/character_select.gd") as GDScript).new() as CanvasLayer
	var chosen: Array[String] = []
	var requests: Array[int] = [0]
	select.connect("character_chosen", func(id: String) -> void: chosen.append(id))
	select.connect("program_requested", func() -> void: requests[0] += 1)
	root.add_child(select)
	await process_frame
	select.set("unlock_screen", _screen)
	select.call("open")
	_equal((select.get("bank_label") as Label).text, "KONTO  12.340", "Die Kandidatenwahl zeigt den Kontostand.")
	var button: Button = select.get("program_button") as Button
	_equal(button.text, "PROGRAMM", "Die Kandidatenwahl hat den Knopf Programm.")
	# Während der Sperre nach dem Öffnen wirkt der Knopf nicht.
	button.pressed.emit()
	_check(not bool(_screen.call("is_open")), "Während der Eingabesperre öffnet der Knopf nichts.")
	select.call("_process", 1.0)
	button.pressed.emit()
	_check(bool(_screen.call("is_open")), "Der Knopf öffnet das Programm.")
	_equal(requests[0], 1, "Die Kandidatenwahl meldet program_requested.")
	_check(bool(select.call("is_open")) and bool(select.call("is_program_open")), "Die Kandidatenwahl bleibt darunter offen.")
	_check(_screen.layer > select.layer, "Das Programm liegt über der Kandidatenwahl.")
	# Solange das Programm offen ist, wählt die Kandidatenwahl nichts.
	select.call("_unhandled_input", _key(KEY_1))
	select.call("_unhandled_input", _key(KEY_ENTER))
	var cards: Array = select.get("cards")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(cards[1] as Control).gui_input.emit(click)
	_check(chosen.is_empty() and str(_game.get("character_id")) == "", "Unter dem offenen Programm wählt die Kandidatenwahl nichts.")
	_check(not bool(select.call("choose", CharacterDefs.DEFAULT)), "Auch choose wählt nicht, solange das Programm offen ist.")
	_check(not bool(select.call("open_program")), "Ein zweites open_program meldet false.")
	# Kauf im Programm: Der Kontostand der Kandidatenwahl folgt.
	_check(bool(_screen.call("buy", "camera_team")), "Im Programm lässt sich kaufen.")
	_equal((select.get("bank_label") as Label).text, "KONTO  10.340", "Der Kontostand der Kandidatenwahl folgt dem Kauf.")
	_screen.call("close")
	_check(bool(select.call("is_open")) and not bool(select.call("is_program_open")), "Nach dem Schließen ist die Kandidatenwahl wieder da.")
	# Taste P öffnet das Programm ebenfalls.
	select.call("_unhandled_input", _key(KEY_P))
	_check(bool(_screen.call("is_open")), "Die Taste P öffnet das Programm.")
	_screen.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(not bool(_screen.call("is_open")) and bool(select.call("is_open")), "Esc führt zurück zur Kandidatenwahl.")
	select.call("_unhandled_input", _key(KEY_2))
	_equal(chosen, ["intern"] as Array[String], "Danach wählt die Kandidatenwahl wieder.")
	# Ohne zugewiesenen Bildschirm meldet der Knopf nur das Signal.
	select.set("unlock_screen", null)
	select.call("open")
	_check(bool(select.call("open_program")) and requests[0] == 3, "Ohne Bildschirm meldet open_program nur program_requested.")
	_check(not bool(select.call("is_program_open")), "Ohne Bildschirm ist kein Programm offen.")
	select.call("close")
	_check(not bool(select.call("open_program")), "Bei geschlossener Kandidatenwahl öffnet open_program nichts.")
	_game.set("character_id", "")
	select.queue_free()
	await process_frame


## Game Over: Knopf und Taste P öffnen das Programm darüber, R startet solange nicht neu, danach
## ist das Game Over wieder da und zeigt den neuen Kontostand.
func _test_game_over() -> void:
	_fresh_progress(3000)
	var over: CanvasLayer = (load("res://scripts/ui/game_over.gd") as GDScript).new() as CanvasLayer
	root.add_child(over)
	await process_frame
	over.set("unlock_screen", _screen)
	_game.call("start_run", 5)
	_events.emit_signal("wave_started", 4, 20)
	_game.call("add_points", 1500)
	_game.call("end_run")
	_check(bool(over.call("is_open")), "Aufbau: Das Game Over ist offen.")
	_equal((over.get("bank_gain_label") as Label).text, "+1.500", "Das Game Over zeigt die Gutschrift des Laufs.")
	_equal((over.get("bank_label") as Label).text, "4.500", "Das Game Over zeigt den neuen Kontostand.")
	_equal(_progress().bank, 4500, "Der Lauf hat 1.500 aufs Konto gebracht.")
	var button: Button = over.get("program_button") as Button
	_equal(button.text, "PROGRAMM", "Das Game Over hat den Knopf Programm.")
	_check(button.disabled, "Direkt nach dem Öffnen ist der Knopf gesperrt.")
	button.pressed.emit()
	over.call("_unhandled_input", _key(KEY_P))
	_check(not bool(_screen.call("is_open")), "Während der Sperre öffnet sich das Programm nicht.")
	var deadline: int = Time.get_ticks_msec() + 3000
	while bool(over.call("is_input_locked")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not button.disabled, "Nach der Sperre ist der Knopf frei.")
	button.pressed.emit()
	_check(bool(_screen.call("is_open")) and bool(over.call("is_program_open")), "Der Knopf öffnet das Programm über dem Game Over.")
	_check(bool(over.call("is_open")), "Das Game Over bleibt darunter offen.")
	_check(_screen.layer > over.layer, "Das Programm liegt über dem Game Over.")
	_equal(int(_game.get("state")), STATE_GAME_OVER, "Das Programm ändert den Spielzustand nicht.")
	_check(paused, "Der Baum bleibt im Game Over pausiert.")
	# Solange das Programm offen ist, startet R nicht neu.
	var starts_before: int = _run_starts
	over.call("_unhandled_input", _key(KEY_R))
	(over.get("restart_button") as Button).pressed.emit()
	_check(not bool(over.call("request_restart")), "request_restart lehnt ab, solange das Programm offen ist.")
	_equal(_run_starts, starts_before, "Unter dem offenen Programm startet nichts neu.")
	# Kauf: Der Kontostand im Game Over folgt, die Gutschrift bleibt.
	_check(bool(_screen.call("buy", "first_aid")), "Im Programm lässt sich kaufen.")
	_equal((over.get("bank_label") as Label).text, "2.000", "Der Kontostand im Game Over folgt dem Kauf.")
	_equal((over.get("bank_gain_label") as Label).text, "+1.500", "Die Gutschrift des Laufs bleibt stehen.")
	_screen.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(not bool(_screen.call("is_open")) and bool(over.call("is_open")), "Esc führt zurück zum Game Over.")
	# Taste P öffnet das Programm ebenfalls.
	over.call("_unhandled_input", _key(KEY_P))
	_check(bool(_screen.call("is_open")), "Die Taste P öffnet das Programm.")
	(_screen.get("back_button") as Button).pressed.emit()
	_check(not bool(_screen.call("is_open")), "Zurück schließt das Programm.")
	# Danach startet R wieder neu, und der neue Lauf lässt das Programm zu.
	over.call("_unhandled_input", _key(KEY_R))
	_equal(_run_starts, starts_before + 1, "Nach dem Schließen startet R neu.")
	_equal(int(_game.get("state")), STATE_PLAYING, "Der neue Lauf läuft.")
	_check(not bool(over.call("is_open")) and not bool(_screen.call("is_open")), "Im neuen Lauf sind Game Over und Programm zu.")
	_check(not bool(over.call("open_program")), "Bei geschlossenem Game Over öffnet open_program nichts.")
	_game.call("end_run")
	over.call("close")
	paused = false
	over.queue_free()
	await process_frame
