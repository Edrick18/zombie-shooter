extends SceneTree
## Tests der Oberfläche (scripts/ui): HUD, Kistenwahl, Pausemenü und Game Over.
## Jeder Bildschirm wird einzeln an die Wurzel gehängt (ohne Level und Spieler), die passenden
## Events werden gesendet und Texte, Sichtbarkeit und die Wirkung auf Game geprüft.
##
## Startet in _initialize und wartet ein Bild: Erst dann hängen die Autoloads im Baum. Sie werden
## über root.get_node geholt, die UI-Skripte zur Laufzeit mit load (siehe Architektur 13.7).

const Balance := preload("res://scripts/core/balance.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const ItemIcons := preload("res://scripts/ui/item_icons.gd")

const STATE_PLAYING: int = 1
const STATE_CHOOSING: int = 2
const STATE_PAUSED: int = 3
const STATE_GAME_OVER: int = 4


## Ersatz für den WeaponController: Das HUD liest nur get_hands().
class FakeController:
	extends Node
	var hands: Array[Dictionary] = [
		{"hand": 0, "uid": 3, "id": "smg", "level": 1, "hands": 1, "mag": 12, "magazine": 30, "reloading": false},
	]

	func get_hands() -> Array[Dictionary]:
		return hands


## Ersatz-Spieler: Das HUD holt sich bei run_started Leben und Waffe.
class FakePlayer:
	extends Node3D
	var hp: float = 80.0
	var max_hp: float = 120.0
	## Zweite Staffel: bereite Ladungen und Ladungen im Rucksack (wie in player.gd).
	var revive_charges: int = 1
	var max_revive_charges: int = 2
	var controller: FakeController = FakeController.new()

	func _init() -> void:
		add_child(controller)

	func get_weapon_controller() -> Node:
		return controller

	func heal(_amount: float) -> void:
		pass


## Ersatz-Kiste: Das HUD liest nur rarity.
class FakeChest:
	extends Node3D
	var rarity: int = 2


var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
var _hud_script: GDScript
var _run_starts: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_game = root.get_node_or_null("Game")
	_events = root.get_node_or_null("Events")
	_check(_game != null, "Autoload Game hängt im Baum.")
	_check(_events != null, "Autoload Events hängt im Baum.")
	if _game != null and _events != null:
		_events.connect("run_started", func() -> void: _run_starts += 1)
		_hud_script = load("res://scripts/ui/hud.gd") as GDScript
		_check(_hud_script != null, "hud.gd lädt.")
		_test_style_helpers()
		await _test_hud()
		await _test_hud_with_player()
		await _test_chest_choice()
		await _test_pause_menu()
		await _test_game_over()
		paused = false
		_game.set("player", null)
		# Gemerkte Schriften freigeben, damit beim Beenden nichts als Leck gemeldet wird.
		_hud_script.call("clear_font_cache")
		await process_frame
		await process_frame
	if _failures == 0:
		print("Alle Oberflächen-Tests bestanden (%d Prüfungen)." % _checks)
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


# --- Helfer ---------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)


## Die Karten halten Zahl und Einheit mit einem geschützten Leerzeichen zusammen ("15 m").
## Für den Vergleich mit dem Text aus UpgradeDefs wird es wieder ein gewöhnliches.
func _plain(text: String) -> String:
	return text.replace(String.chr(0x00A0), " ")


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures += 1
		printerr("FEHLER: %s (erwartet %s, bekommen %s)" % [message, str(expected), str(actual)])


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


## Wartet, bis die Bedingung gilt, höchstens timeout Sekunden. Gibt zurück, ob sie eintrat.
func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return bool(condition.call())


func _add_screen(path: String) -> Node:
	var script: GDScript = load(path) as GDScript
	var node: Node = script.new()
	root.add_child(node)
	return node


func _remove(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
	await _frames(2)


func _text(node: Node, path: String) -> String:
	var label: Label = node.get_node_or_null(path) as Label
	if label == null:
		_failures += 1
		printerr("FEHLER: Label fehlt: %s" % path)
		return ""
	return label.text


func _label(owner: Node, property: String) -> Label:
	var label: Label = owner.get(property) as Label
	if label == null:
		_failures += 1
		printerr("FEHLER: Label-Eigenschaft fehlt: %s" % property)
		return Label.new()
	return label


## Kasten einer Hand in der Waffenanzeige des HUD (0 = linke Hand).
func _hand_box(hud: Node, hand: int) -> Control:
	var boxes: Array = hud.get("hand_boxes")
	if hand >= boxes.size() or not boxes[hand] is Control:
		_failures += 1
		printerr("FEHLER: Kasten der Hand %d fehlt." % hand)
		return Control.new()
	return boxes[hand] as Control


func _control(owner: Node, property: String) -> Control:
	var control: Control = owner.get(property) as Control
	if control == null:
		_failures += 1
		printerr("FEHLER: Control-Eigenschaft fehlt: %s" % property)
		return Control.new()
	return control


func _key(physical_keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.pressed = true
	return event


func _click() -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _state() -> int:
	return int(_game.get("state"))


func _upgrades() -> RefCounted:
	return _game.get("upgrades") as RefCounted


func _floater_texts(hud: Node) -> Array[String]:
	var texts: Array[String] = []
	for child: Node in _control(hud, "floaters").get_children():
		if child is Label and not child.is_queued_for_deletion():
			texts.append((child as Label).text)
	return texts


# --- Stil-Helfer ----------------------------------------------------------------------

func _test_style_helpers() -> void:
	_equal(_hud_script.call("format_int", 0), "0", "format_int(0)")
	_equal(_hud_script.call("format_int", 999), "999", "format_int(999)")
	_equal(_hud_script.call("format_int", 12340), "12.340", "format_int(12340)")
	_equal(_hud_script.call("format_int", 1234567), "1.234.567", "format_int(1234567)")
	_equal(_hud_script.call("format_int", -1500), "-1.500", "format_int(-1500)")
	var fitted: int = int(_hud_script.call("fit_font_size", "Ein ziemlich langer Text für wenig Platz", 40, 120.0))
	_check(fitted < 40, "fit_font_size verkleinert die Schrift, wenn der Text nicht passt.")
	_equal(int(_hud_script.call("fit_font_size", "Kurz", 40, 900.0)), 40, "fit_font_size lässt passende Schrift stehen.")


# --- HUD ------------------------------------------------------------------------------

func _test_hud() -> void:
	_game.set("player", null)
	var hud: Node = _add_screen("res://scripts/ui/hud.gd")
	await _frames(1)
	_equal(int(hud.get("layer")), 1, "HUD liegt auf Ebene 1.")
	_game.call("start_run", 5)
	await _frames(1)

	# Ohne Spieler: Startwerte.
	_equal(_label(hud, "wave_label").text, "SHOWSTART", "Vor der ersten Welle steht SHOWSTART.")
	_equal(_label(hud, "health_label").text, "100", "Leben ohne Spieler: Startwert.")
	_equal(_label(hud, "health_max_label").text, "/ 100", "Maximal-Leben ohne Spieler: Startwert.")
	_equal(_label(hud, "weapon_label").text, "DIENSTPISTOLE", "Startwaffe wird angezeigt.")
	_equal(_label(hud, "ammo_label").text, "10", "Magazin der Startwaffe.")
	_equal(_label(hud, "magazine_label").text, "/ 10", "Daneben steht die Größe des Magazins (Munition ist unendlich).")
	_check(_hand_box(hud, 0).visible and not _hand_box(hud, 1).visible, "Mit einer Waffe ist nur eine Hand zu sehen.")
	_check(not (_hand_box(hud, 0).get_node("Side") as Label).visible, "Mit einer Waffe steht keine Seite dabei.")
	_equal(_label(hud, "points_label").text, "0", "Punkte beginnen bei 0.")
	_equal(_label(hud, "buff_header").text, "BUFFS · TAB: RUCKSACK", "Die Kopfzeile der Buff-Anzeige nennt die Taste für den Rucksack.")
	_equal(_control(hud, "buff_rows").get_child_count(), 0, "Ohne Boni ist die Buff-Anzeige leer.")
	_check(not _control(hud, "prompt_panel").visible, "Interaktions-Hinweis ist anfangs aus.")
	_check(not _control(hud, "banner_panel").visible, "Banner ist anfangs aus.")
	_check(not _control(hud, "countdown_box").visible, "Countdown ist anfangs aus.")

	# Punkte: Zahl sofort, Gewinn als schwebende Anzeige, schnelle Gewinne zählen zusammen.
	_game.call("add_points", 60)
	_equal(_label(hud, "points_label").text, "60", "Punktestand folgt points_changed.")
	await _frames(2)
	_check(_floater_texts(hud).has("+60"), "Gewinn erscheint als schwebendes +60.")
	_game.call("add_points", 10)
	_game.call("add_points", 60)
	await _frames(2)
	_check(_floater_texts(hud).has("+130"), "Schnelle Gewinne zählen in derselben Anzeige zusammen (+130).")
	_equal(_floater_texts(hud).size(), 1, "Es bleibt bei einer Gewinn-Anzeige.")
	_game.call("spend_points", 100)
	_equal(_label(hud, "points_label").text, "30", "Ausgegebene Punkte gehen ab.")
	_check(_floater_texts(hud).has("−100"), "Ausgabe erscheint als schwebendes −100.")
	_events.emit_signal("points_changed", 12340)
	_equal(_label(hud, "points_label").text, "12.340", "Große Punktzahlen mit Tausenderpunkt.")

	# Material (Abschnitt 26): klein unter den Punkten, mit kurzem "+2" beim Zuwachs.
	var material_label: Label = _label(hud, "material_label")
	var material_gain: Label = _label(hud, "material_gain_label")
	var material_icon: Control = _control(hud, "material_icon")
	_equal(material_label.text, "MATERIAL %d" % Balance.MATERIAL_START, "Das HUD zeigt das Material des Laufs.")
	_check(is_zero_approx(material_gain.modulate.a), "Ohne Zuwachs ist kein +N zu sehen.")
	_game.call("add_materials", 2)
	_equal(material_label.text, "MATERIAL %d" % (Balance.MATERIAL_START + 2), "Das Material im HUD folgt materials_changed.")
	_check(material_gain.text == "+2" and material_gain.modulate.a > 0.9, "Beim Zuwachs steht kurz +2 daneben, war: " + material_gain.text)
	await _frames(2)
	var material_rect: Rect2 = material_label.get_global_rect()
	var points_rect: Rect2 = _label(hud, "points_label").get_global_rect()
	_check(material_rect.position.y >= points_rect.get_center().y and material_rect.end.x <= points_rect.end.x + 1.0 and material_rect.size.x > 40.0,
		"Das Material steht rechts unter den Punkten.")
	_check(material_label.get_theme_font_size("font_size") * 2 < _label(hud, "points_label").get_theme_font_size("font_size"), "Das Material ist klein neben dem Punktestand.")
	_check(material_icon.get_global_rect().end.x <= material_rect.position.x + 0.5 and material_icon.size.x >= 16.0, "Vor dem Material steht sein Zeichen, das Zahnrad.")
	_check(material_gain.get_global_rect().end.x <= material_icon.get_global_rect().position.x + 0.5, "Das +2 steht links daneben.")
	_check(_control(hud, "floaters").get_global_rect().position.y >= material_rect.end.y - 4.0, "Die schwebenden Punkte beginnen unter dem Material.")
	_check(root.get_visible_rect().encloses(material_rect), "Das Material liegt im Bild.")
	_events.emit_signal("materials_changed", 1, -4)
	_check(material_label.text == "MATERIAL 1" and is_zero_approx(material_gain.modulate.a), "Ausgegebenes Material geht ab, ohne +N.")
	_events.emit_signal("materials_changed", 1234, 3)
	_check(material_label.text == "MATERIAL 1.234" and material_gain.text == "+3", "Viel Material steht mit Tausenderpunkt da.")
	_events.emit_signal("materials_changed", int(_game.get("materials")), 0)
	_check(material_label.text == "MATERIAL %d" % (Balance.MATERIAL_START + 2) and is_zero_approx(material_gain.modulate.a), "Eine Meldung ohne Änderung setzt die Anzeige zurück.")

	# Welle, Zombies, Countdown.
	_events.emit_signal("intermission_tick", 4)
	_check(_control(hud, "countdown_box").visible, "Countdown erscheint bei intermission_tick.")
	_equal(_label(hud, "countdown_label").text, "4", "Countdown zeigt die Sekunden.")
	_equal(_label(hud, "countdown_title").text, "DIE SHOW BEGINNT IN", "Vor Welle 1 kündigt der Countdown die Show an.")
	_events.emit_signal("intermission_tick", 0)
	_check(not _control(hud, "countdown_box").visible, "Countdown verschwindet bei 0.")
	_events.emit_signal("wave_started", 3, 19)
	_equal(_label(hud, "wave_label").text, "WELLE 3", "Wellennummer.")
	_equal(_label(hud, "zombies_label").text, "NOCH 19 ZOMBIES", "Zombies der Welle.")
	_events.emit_signal("zombies_left_changed", 1)
	_equal(_label(hud, "zombies_label").text, "NOCH 1 ZOMBIE", "Einzahl bei einem Zombie.")
	_events.emit_signal("wave_cleared", 3)
	_equal(_label(hud, "zombies_label").text, "GESCHAFFT!", "Welle geschafft.")
	_events.emit_signal("intermission_tick", 12)
	_equal(_label(hud, "countdown_title").text, "NÄCHSTE WELLE IN", "Zwischen den Wellen zählt der Countdown zur nächsten.")
	_equal(_label(hud, "countdown_label").text, "12", "Countdown zwischen den Wellen.")
	_events.emit_signal("intermission_tick", 0)

	# Leben und roter Rand.
	_events.emit_signal("player_health_changed", 64.2, 100.0)
	_equal(_label(hud, "health_label").text, "65", "Leben wird aufgerundet angezeigt.")
	var healthy_color: Color = _label(hud, "health_label").get_theme_color("font_color")
	_events.emit_signal("player_health_changed", 20.0, 140.0)
	_events.emit_signal("player_damaged", 35.0)
	_equal(_label(hud, "health_label").text, "20", "Leben nach Schaden.")
	_equal(_label(hud, "health_max_label").text, "/ 140", "Maximal-Leben mit Bonus.")
	_check(_label(hud, "health_label").get_theme_color("font_color") != healthy_color, "Farbe des Lebens wechselt bei wenig Leben.")
	await _frames(2)
	_check(_control(hud, "vignette").visible, "Roter Rand nach Schaden.")
	var bar: Control = _control(hud, "health_bar")
	_check(absf(float(bar.get("ratio")) - 20.0 / 140.0) < 0.001, "Lebensbalken zeigt den Anteil.")

	# Waffe, Munition, Nachladen. Ohne Spieler liest das HUD die Waffen aus Game.loadout, sobald
	# loadout_changed kommt (das sendet sonst die Waffensteuerung).
	var backpack: RefCounted = _game.get("backpack") as RefCounted
	var shotgun_uid: int = int(backpack.call("add_item", "shotgun", 1))
	_check(bool(backpack.call("auto_place", shotgun_uid)), "Aufbau: Die Schrotflinte passt in den Rucksack.")
	_game.call("sync_build")
	_events.emit_signal("loadout_changed")
	_equal(_label(hud, "weapon_label").text, "PUBLIKUMSJOKER", "Waffenname.")
	_equal(_label(hud, "ammo_label").text, "6", "Magazin.")
	_equal(_label(hud, "magazine_label").text, "/ 6", "Größe des Magazins.")
	_check(not _hand_box(hud, 1).visible, "Eine Zweihand-Waffe zeigt nur eine Hand.")
	_check(not _label(hud, "low_ammo_label").visible, "Volles Magazin: kein Hinweis.")
	_events.emit_signal("hand_ammo_changed", 0, 1, 6)
	_equal(_label(hud, "ammo_label").text, "1", "Magazin folgt hand_ammo_changed.")
	_check(_label(hud, "low_ammo_label").visible, "Fast leeres Magazin: Hinweis WENIG MUNITION.")
	_equal(_label(hud, "low_ammo_label").text, "WENIG MUNITION", "Text bei wenig Munition.")
	_check(not _label(hud, "reload_hint_label").visible, "Noch Kugeln: kein Nachladen-Hinweis.")
	_events.emit_signal("hand_ammo_changed", 0, 0, 6)
	_check(_label(hud, "reload_hint_label").visible, "Leeres Magazin: Nachladen-Hinweis.")
	_equal(_label(hud, "reload_hint_label").text, "NACHLADEN [R]", "Text des Nachladen-Hinweises.")
	_events.emit_signal("hand_reload_started", 0, 2.2)
	_check(_control(hud, "reload_bar").visible, "Nachladebalken läuft.")
	_check(_label(hud, "reload_label").visible, "Beim Nachladen steht LÄDT NACH da.")
	_check(not _label(hud, "reload_hint_label").visible, "Beim Nachladen kein Nachladen-Hinweis.")
	await _frames(3)
	_check(float(_control(hud, "reload_bar").get("ratio")) > 0.0, "Nachladebalken füllt sich.")
	_events.emit_signal("hand_ammo_changed", 0, 6, 6)
	_events.emit_signal("hand_reload_finished", 0)
	_check(not _control(hud, "reload_bar").visible, "Nachladebalken verschwindet nach dem Nachladen.")
	_check(not _label(hud, "reload_label").visible, "Danach ist auch LÄDT NACH weg.")
	_equal(_label(hud, "ammo_label").text, "6", "Nach dem Nachladen ist das Magazin voll.")
	_events.emit_signal("hand_reload_started", 0, 2.2)
	_events.emit_signal("loadout_changed")
	_check(not _control(hud, "reload_bar").visible, "Ein neuer Abgleich ohne laufendes Nachladen räumt den Balken weg.")
	_events.emit_signal("hand_ammo_changed", 1, 3, 10)
	_check(not _hand_box(hud, 1).visible, "Ein Signal für eine Hand, die es nicht gibt, ändert nichts.")
	_events.emit_signal("ammo_changed", 2, -1)
	_equal(_label(hud, "ammo_label").text, "6", "Das HUD folgt den Signalen je Hand, nicht mehr ammo_changed.")
	_events.emit_signal("weapon_fired", "shotgun")
	_check(float(_control(hud, "crosshair").get("kick")) > 0.0, "Fadenkreuz reagiert auf den Schuss.")

	# Zwei Waffen: jede Hand mit Name, Magazin und eigenem Nachladebalken.
	backpack.call("store", shotgun_uid)
	var pistol_uid: int = int(backpack.call("add_item", "pistol", 1))
	var smg_uid: int = int(backpack.call("add_item", "smg", 1))
	_check(bool(backpack.call("auto_place", pistol_uid)) and bool(backpack.call("auto_place", smg_uid)), "Aufbau: Pistole und MP passen in den Rucksack.")
	_game.call("sync_build")
	_events.emit_signal("loadout_changed")
	var left_box: Control = _hand_box(hud, 0)
	var right_box: Control = _hand_box(hud, 1)
	_check(left_box.visible and right_box.visible, "Mit zwei Waffen sind beide Hände zu sehen.")
	_equal(_text(left_box, "Name"), "DIENSTPISTOLE", "Linke Hand: Name der Pistole.")
	_equal(_text(right_box, "Name"), "QUOTENHAMMER", "Rechte Hand: Name der MP.")
	_equal(_text(left_box, "AmmoRow/Ammo"), "10", "Linke Hand: Magazin der Pistole.")
	_equal(_text(left_box, "AmmoRow/Magazine"), "/ 10", "Linke Hand: Größe des Magazins.")
	_equal(_text(right_box, "AmmoRow/Ammo"), "30", "Rechte Hand: Magazin der MP.")
	_equal(_text(right_box, "AmmoRow/Magazine"), "/ 30", "Rechte Hand: Größe des Magazins.")
	_equal(_text(left_box, "Side"), "LINKS", "Die linke Hand ist beschriftet.")
	_equal(_text(right_box, "Side"), "RECHTS", "Die rechte Hand ist beschriftet.")
	_check((left_box.get_node("Side") as Label).visible and (right_box.get_node("Side") as Label).visible, "Bei zwei Waffen stehen die Seiten dabei.")
	_check(left_box.offset_right <= right_box.offset_left, "Die linke Hand steht links neben der rechten.")
	_check(right_box.offset_right <= 0.0 and left_box.offset_left < 0.0 and left_box.offset_left > -640.0, "Beide Kästen liegen in der rechten unteren Ecke.")
	for box: Control in [left_box, right_box]:
		var name_label: Label = box.get_node("Name") as Label
		_check(name_label.get_minimum_size().x <= name_label.size.x + 0.5, "Der Name %s passt in seinen Kasten." % name_label.text)
	_equal(_label(hud, "weapon_label").text, "DIENSTPISTOLE", "weapon_label ist der Name der linken Hand.")
	_events.emit_signal("hand_ammo_changed", 1, 4, 30)
	_equal(_text(right_box, "AmmoRow/Ammo"), "4", "Das Magazin der rechten Hand zählt für sich.")
	_equal(_text(left_box, "AmmoRow/Ammo"), "10", "Das Magazin der linken Hand bleibt.")
	_check(_label(hud, "low_ammo_label").visible, "Wenig Munition in einer Hand zeigt den Hinweis.")
	var bars: Array = hud.get("reload_bars")
	_equal(bars.size(), 2, "Es gibt je Hand einen Nachladebalken.")
	_events.emit_signal("hand_reload_started", 1, 1.8)
	_check((bars[1] as Control).visible and not (bars[0] as Control).visible, "Nur der Balken der rechten Hand läuft.")
	_check(not _label(hud, "low_ammo_label").visible, "Die nachladende Hand zählt nicht mehr als knapp.")
	_events.emit_signal("hand_reload_started", 0, 1.2)
	_check((bars[0] as Control).visible and (bars[1] as Control).visible, "Beide Hände laden nach: zwei Balken.")
	_check((bars[0] as Control).offset_right <= (bars[1] as Control).offset_left, "Der Balken der linken Hand liegt links von dem der rechten.")
	await _frames(3)
	_check(float((bars[0] as Control).get("ratio")) > float((bars[1] as Control).get("ratio")) and float((bars[1] as Control).get("ratio")) > 0.0,
		"Jeder Balken läuft in seiner eigenen Zeit (der kürzere ist weiter).")
	_events.emit_signal("hand_reload_finished", 1)
	_check((bars[0] as Control).visible and not (bars[1] as Control).visible, "Die rechte Hand ist fertig, die linke lädt noch.")
	_check(_label(hud, "reload_label").visible, "Solange eine Hand lädt, steht LÄDT NACH da.")
	_events.emit_signal("hand_reload_finished", 0)
	_check(not (bars[0] as Control).visible and not _label(hud, "reload_label").visible, "Danach läuft kein Balken mehr.")
	# Zurück auf die Dienstpistole.
	for uid: int in [shotgun_uid, pistol_uid, smg_uid]:
		backpack.call("remove", uid)
	_game.call("sync_build")
	_events.emit_signal("loadout_changed")
	_check(left_box.visible and not right_box.visible, "Ohne Waffe im Rucksack ist wieder nur eine Hand zu sehen.")
	_equal(_label(hud, "weapon_label").text, "DIENSTPISTOLE", "Ohne Waffe im Rucksack: Dienstpistole.")
	_equal(_label(hud, "ammo_label").text, "10", "Die Dienstpistole hat ein volles Magazin.")

	# Treffermarker: Treffer, Kopftreffer, Kill. Ein Kill wird nicht vom Treffer verdrängt.
	var marker: Control = _control(hud, "hit_marker")
	_events.emit_signal("bullet_hit", null, 25.0, {"source": "bullet", "headshot": false})
	_equal(int(marker.get("kind")), 0, "Treffermarker bei Kugeltreffer.")
	_events.emit_signal("bullet_hit", null, 50.0, {"source": "bullet", "headshot": true})
	_equal(int(marker.get("kind")), 1, "Treffermarker bei Kopftreffer.")
	_events.emit_signal("zombie_killed", null, {"source": "bullet", "headshot": true})
	_equal(int(marker.get("kind")), 3, "Treffermarker bei Kopfschuss-Kill.")
	_events.emit_signal("bullet_hit", null, 50.0, {"source": "bullet", "headshot": false})
	_equal(int(marker.get("kind")), 3, "Kill-Marker bleibt trotz nachfolgendem Treffer.")
	_check(_label(hud, "kill_label").visible, "KOPFSCHUSS-Text erscheint.")
	_equal(_label(hud, "kill_label").text, "KOPFSCHUSS!", "Text beim Kopfschuss-Kill.")

	# Interaktions-Hinweis: die Texte der Türen (door.gd) mit allen vier Räumen und ihren Preisen.
	_events.emit_signal("interact_prompt_changed", "E – Backstage öffnen (750)")
	_check(_control(hud, "prompt_panel").visible, "Interaktions-Hinweis erscheint.")
	_equal(_label(hud, "prompt_label").text, "E – Backstage öffnen (750)", "Text des Hinweises.")
	var prompt_font: Font = _hud_script.call("show_font", false) as Font
	var room_names: Array[String] = ["Backstage", "Kantine", "Garderobe", "Regieraum"]
	for i: int in room_names.size():
		var cost: int = Balance.DOOR_COSTS[i]
		for prompt: String in ["E – %s öffnen (%d)" % [room_names[i], cost], "%s (%d) – dir fehlen %d Punkte" % [room_names[i], cost, cost - 1]]:
			_events.emit_signal("interact_prompt_changed", prompt)
			var prompt_label: Label = _label(hud, "prompt_label")
			_equal(prompt_label.text, prompt, "Der Hinweis zeigt den Text der Tür.")
			var prompt_size: int = prompt_label.get_theme_font_size("font_size")
			_check(prompt_size >= 20, "Der Tür-Hinweis „%s“ bleibt groß (%d Punkt)." % [prompt, prompt_size])
			_check(prompt_font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, prompt_size).x <= 620.0, "Der Tür-Hinweis „%s“ passt in die Plakette." % prompt)
	_equal(Balance.DOOR_COSTS.size(), room_names.size(), "Aufbau: Es gibt vier kaufbare Räume.")
	_events.emit_signal("interact_prompt_changed", "")
	_check(not _control(hud, "prompt_panel").visible, "Leerer Hinweis blendet aus.")

	# Kameras (Abschnitt 22.1) stehen in der Buff-Anzeige: je Kameratyp eine Zeile mit Zahl und Name.
	var buff_rows: Control = _control(hud, "buff_rows")
	_equal(buff_rows.get_child_count(), 0, "Aufbau: Vor den Kameras ist die Buff-Anzeige leer.")
	var camera_uids: Array[int] = []
	for camera_id: String in ["drone", "drone", "cam_slow"]:
		var camera_uid: int = int(backpack.call("add_item", camera_id, 2 if camera_uids.is_empty() else 1))
		_check(bool(backpack.call("auto_place", camera_uid)), "Aufbau: Die Kamera %s passt in den Rucksack." % camera_id)
		camera_uids.append(camera_uid)
	_game.call("sync_build")
	_equal((_game.get("cameras") as Array).size(), 3, "Aufbau: Drei Kameras sind im Spiel.")
	_equal(buff_rows.get_child_count(), 2, "Zwei Kameratypen: zwei Zeilen in der Buff-Anzeige.")
	_equal(_text(buff_rows, "Buff_camera_drone/Text"), "2 × %s" % ItemDefs.display_name("drone"), "Zwei Drohnen stehen als eine Zeile mit Zahl da.")
	_equal(_text(buff_rows, "Buff_camera_cam_slow/Text"), ItemDefs.display_name("cam_slow"), "Eine einzelne Kamera steht mit ihrem Namen da.")
	_check(buff_rows.get_node_or_null("Buff_camera_drone/Icon") != null, "Die Kamera-Zeile zeigt ein Bild.")
	# Das Bild kommt aus ItemIcons (dasselbe wie im Rucksack) und wird wirklich gezeichnet.
	var camera_icon: Control = buff_rows.get_node_or_null("Buff_camera_drone/Icon") as Control
	_check(camera_icon != null and str(camera_icon.get("item_id")) == "drone" and ItemIcons.has("drone"), "Die Kamera-Zeile zeigt das Bild der Kameradrohne aus ItemIcons.")
	await _frames(2)
	_check(camera_icon != null and int(camera_icon.get("draw_count")) >= 1 and camera_icon.size.x >= 16.0, "Das Bild der Kamera wird gezeichnet.")
	var camera_text: Label = buff_rows.get_node("Buff_camera_cam_slow/Text") as Label
	_check(prompt_font.get_string_size(camera_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, camera_text.get_theme_font_size("font_size")).x <= camera_text.size.x + 0.5,
		"Der Name der Kamera passt in die Zeile.")
	var camera_rows: Array = _hud_script.call("camera_entries", [{"id": "cam_tele", "level": 2}, {"id": "drone", "level": 1}, {"id": "cam_tele", "level": 4}, "kaputt", {}])
	_equal(camera_rows.size(), 2, "camera_entries fasst gleiche Kameras zusammen und überspringt Unbrauchbares.")
	if camera_rows.size() == 2:
		_equal(str(camera_rows[0]["key"]), "camera_cam_tele", "Die Zeilen stehen in der Reihenfolge des Erwerbs.")
		_equal(str(camera_rows[0]["text"]), "2 × Tele-Kamera", "Die Zeile nennt Zahl und Namen.")
		_equal(int(camera_rows[0]["level"]), 4, "Die Zeile merkt sich die beste Rarität.")
		_equal(str(camera_rows[1]["text"]), "Kameradrohne", "Eine einzelne Kamera steht ohne Zahl da.")
	# Alle fünf Kameratypen passen mit ihrem Namen in eine Zeile, auch mit Zahl davor.
	for camera_id: String in ["drone", "cam_tele", "cam_flash", "cam_slow", "cam_director"]:
		var many_text: String = "3 × %s" % ItemDefs.display_name(camera_id)
		var many_size: int = int(_hud_script.call("fit_font_size", many_text, 15, 154.0, false, 11))
		_check(prompt_font.get_string_size(many_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, many_size).x <= 158.0, "„%s“ passt in eine Zeile der Buff-Anzeige." % many_text)
	backpack.call("remove", camera_uids[0])
	_game.call("sync_build")
	_equal(_text(buff_rows, "Buff_camera_drone/Text"), ItemDefs.display_name("drone"), "Nach dem Verkauf einer Drohne steht die andere allein da.")
	for camera_uid: int in camera_uids:
		backpack.call("remove", camera_uid)
	_game.call("sync_build")
	_equal(buff_rows.get_child_count(), 0, "Ohne Kameras ist die Buff-Anzeige wieder leer.")

	# Ladungen der Zweiten Staffel: nur sichtbar mit Gegenstand, neben der Sprung-Anzeige.
	var revive_box: Control = _control(hud, "revive_box")
	var revive_pips: Control = _control(hud, "revive_pips")
	var dash_box: Control = _control(hud, "dash_box")
	_check(not revive_box.visible, "Ohne Zweite Staffel ist die Anzeige der Ladungen aus.")
	_events.emit_signal("revive_charges_changed", 1, 2)
	_check(revive_box.visible, "Mit Zweiter Staffel erscheint die Anzeige der Ladungen.")
	_equal(int(revive_pips.get("max_level")), 2, "Je Ladung gibt es ein Kästchen.")
	_equal(int(revive_pips.get("level")), 1, "Bereite Ladungen sind gefüllt.")
	_equal(_text(revive_box, "ReviveTag"), "2. STAFFEL", "Die Anzeige ist beschriftet.")
	_check(not dash_box.visible and is_equal_approx(revive_box.offset_top, dash_box.offset_top), "Ohne Notausgang steht die Anzeige am Platz der Sprung-Anzeige.")
	_events.emit_signal("dash_charges_changed", 1, 2)
	_check(dash_box.visible and revive_box.offset_bottom <= dash_box.offset_top + 0.5, "Mit Notausgang steht sie direkt über der Sprung-Anzeige.")
	_check(is_equal_approx(revive_box.offset_left, dash_box.offset_left), "Beide Anzeigen stehen untereinander neben dem Lebensbalken.")
	_events.emit_signal("revive_charges_changed", 0, 2)
	_equal(int(revive_pips.get("level")), 0, "Eine verbrauchte Ladung ist leer.")
	_check(revive_box.visible, "Auch ohne bereite Ladung bleibt die Anzeige stehen.")
	_events.emit_signal("revive_charges_changed", 3, 3)
	_equal(int(revive_pips.get("max_level")), 3, "Ein weiteres Exemplar ist eine weitere Ladung.")
	_check(revive_pips.offset_right - revive_pips.offset_left > 26.0 * 3.0 - 0.5, "Die Kästchen bekommen Platz für drei Ladungen.")
	_events.emit_signal("revive_charges_changed", 0, 0)
	_check(not revive_box.visible, "Ohne Zweite Staffel verschwindet die Anzeige wieder.")
	_events.emit_signal("dash_charges_changed", 0, 0)
	_events.emit_signal("revive_charges_changed", 2, 2)
	_game.call("start_run", 5)
	_check(not revive_box.visible, "Ein neuer Lauf ohne Spieler stellt die Anzeige zurück.")
	backpack = _game.get("backpack") as RefCounted

	# Buff-Anzeige: Sie zeigt Boni und Verbindungen, nicht die Gegenstände selbst.
	var upgrades: RefCounted = _upgrades()
	var rows: Control = _control(hud, "buff_rows")
	_events.emit_signal("upgrade_chosen", "pierce", int(upgrades.call("add_levels", "pierce", 2)))
	_equal(rows.get_child_count(), 0, "Ein Upgrade ohne Zusatzwert steht nicht in der Buff-Anzeige.")
	_events.emit_signal("upgrade_chosen", "speed", int(upgrades.call("add_levels", "speed", 2)))
	_equal(rows.get_child_count(), 1, "Mehr Tempo ist ein Buff.")
	_equal(_text(rows, "Buff_speed/Text"), "Tempo +16 %", "Der Buff nennt den Wert.")
	_events.emit_signal("upgrade_chosen", "max_hp", int(upgrades.call("add_levels", "max_hp", 1)))
	_events.emit_signal("upgrade_chosen", "luck", int(upgrades.call("add_levels", "luck", 1)))
	_equal(_text(rows, "Buff_max_hp/Text"), "Leben +20", "Zusatz-Leben steht in der Buff-Anzeige.")
	_equal(_text(rows, "Buff_points/Text"), "Punkte +10 %", "Der Punkte-Bonus steht in der Buff-Anzeige.")
	# Abgeleiteter Zustand mit allen Werten, einem Malus und einer Verbindung.
	upgrades.call("set_derived", {"speed": 1}, ["storm_front"] as Array[String],
		{"damage": 0.12, "reload": 0.2, "speed": -0.18, "points": 0.08, "max_hp": -20.0})
	_events.emit_signal("build_changed")
	_equal(rows.get_child_count(), 6, "Vier Werte, Leben und die Verbindung stehen in der Buff-Anzeige.")
	_equal(_text(rows, "Buff_damage/Text"), "Schaden +12 %", "Waffenschaden als Buff.")
	_equal(_text(rows, "Buff_reload/Text"), "Nachladen +20 %", "Schnelleres Nachladen als Buff (wie im Rucksack: 20 % kürzere Nachladezeit).")
	_equal(_text(rows, "Buff_speed/Text"), "Tempo −10 %", "Ein Malus steht mit Minus da.")
	_equal(_text(rows, "Buff_max_hp/Text"), "Leben −20", "Weniger Leben steht mit Minus da.")
	_equal(_text(rows, "Buff_synergy_storm_front/Text"), "GEWITTERFRONT", "Die aktive Verbindung steht in der Buff-Anzeige.")
	var last_row: Control = rows.get_child(rows.get_child_count() - 1) as Control
	_check(last_row.position.y + last_row.size.y <= rows.size.y + 0.5, "Sechs Zeilen passen in die Buff-Anzeige.")
	# Zurück auf von Hand gesetzte Stufen für die Synergie-Meldung.
	upgrades.call("set_derived", {}, [] as Array[String], {})
	_events.emit_signal("build_changed")
	_equal(rows.get_child_count(), 0, "Ohne Boni ist die Buff-Anzeige wieder leer.")
	upgrades.call("add_levels", "chain_lightning", 5)
	upgrades.call("add_levels", "pierce", 5)
	for synergy_id: String in upgrades.call("check_new_synergies"):
		_events.emit_signal("synergy_unlocked", synergy_id)
	_equal(_text(rows, "Buff_synergy_storm_front/Text"), "GEWITTERFRONT", "Eine neue Synergie erscheint in der Buff-Anzeige.")
	_check(_label(hud, "banner_label").text.contains("Gewitterfront"), "Synergie wird als Banner gemeldet.")

	# Banner: nacheinander, nie zwei zugleich, gleiche Meldung nur einmal.
	_game.call("start_run", 5)
	await _frames(1)
	_equal(rows.get_child_count(), 0, "Neuer Lauf leert die Upgrade-Leiste.")
	_equal(_label(hud, "wave_label").text, "SHOWSTART", "Neuer Lauf stellt die Welle zurück.")
	_events.emit_signal("banner", "Welle 1")
	_events.emit_signal("banner", "Zweite Meldung")
	_events.emit_signal("banner", "Welle 1")
	_check(_control(hud, "banner_panel").visible, "Banner erscheint.")
	_equal(_label(hud, "banner_label").text, "Welle 1", "Die erste Meldung läuft zuerst.")
	_equal(int(hud.call("get_banner_queue_size")), 1, "Die zweite wartet, die doppelte entfällt.")
	var second_shown: bool = await _wait_until(func() -> bool: return _label(hud, "banner_label").text == "Zweite Meldung", 4.0)
	_check(second_shown, "Die zweite Meldung folgt nach der ersten.")
	var banner_done: bool = await _wait_until(func() -> bool: return not bool(hud.call("is_banner_active")), 5.0)
	_check(banner_done, "Nach der letzten Meldung ist das Banner aus.")
	_check(not _control(hud, "banner_panel").visible, "Banner-Plakette ist danach unsichtbar.")
	var chest: FakeChest = FakeChest.new()
	root.add_child(chest)
	_events.emit_signal("chest_dropped", chest)
	_events.emit_signal("banner", "Eine Kiste ist gefallen")
	_equal(_label(hud, "banner_label").text, "Gold-Kiste gefallen!", "Gefallene Kiste wird gemeldet.")
	_equal(int(hud.call("get_banner_queue_size")), 0, "Eine zweite Kisten-Meldung entfällt.")
	# Jede Kiste wird gemeldet: Eine zweite Kiste anderer Seltenheit kurz danach bekommt ihr
	# eigenes Banner (Elite-Kiste plus Glückskiste aus demselben Schuss). Nur dieselbe Meldung
	# entfällt innerhalb von 3 s.
	var bronze: FakeChest = FakeChest.new()
	bronze.rarity = Balance.RARITY_BRONZE
	root.add_child(bronze)
	_events.emit_signal("chest_dropped", bronze)
	_equal(int(hud.call("get_banner_queue_size")), 1, "Eine Kiste anderer Seltenheit wird zusätzlich gemeldet.")
	_events.emit_signal("chest_dropped", chest)
	_events.emit_signal("chest_dropped", bronze)
	_events.emit_signal("banner", "Noch eine Kiste!")
	_equal(int(hud.call("get_banner_queue_size")), 1, "Dieselbe Kisten-Meldung und fremde Kisten-Banner entfallen weiterhin.")
	var bronze_shown: bool = await _wait_until(func() -> bool: return _label(hud, "banner_label").text == "Bronze-Kiste gefallen!", 4.0)
	_check(bronze_shown, "Nach der Gold-Kiste läuft das Banner der Bronze-Kiste.")
	bronze.queue_free()
	chest.queue_free()

	# Game Over blendet das Fadenkreuz aus, ein neuer Lauf wieder ein.
	_game.call("end_run")
	_check(not _control(hud, "crosshair").is_visible_in_tree(), "Im Game Over ist das Fadenkreuz aus.")
	_game.call("start_run", 5)
	_check(_control(hud, "crosshair").is_visible_in_tree(), "Im neuen Lauf ist das Fadenkreuz wieder da.")
	await _remove(hud)


func _test_hud_with_player() -> void:
	var player: FakePlayer = FakePlayer.new()
	root.add_child(player)
	_game.set("player", player)
	var hud: Node = _add_screen("res://scripts/ui/hud.gd")
	_game.call("start_run", 5)
	await _frames(1)
	_equal(_label(hud, "health_label").text, "80", "HUD holt das Leben vom Spieler.")
	_equal(_label(hud, "health_max_label").text, "/ 120", "HUD holt das Maximal-Leben vom Spieler.")
	_equal(_label(hud, "weapon_label").text, "QUOTENHAMMER", "HUD holt die Waffe vom Spieler.")
	_equal(_label(hud, "ammo_label").text, "12", "HUD holt das Magazin vom Spieler.")
	_equal(_label(hud, "magazine_label").text, "/ 30", "HUD holt die Größe des Magazins vom Spieler.")
	_check(not _hand_box(hud, 1).visible, "Eine Waffe beim Spieler: eine Hand.")
	_check(_control(hud, "revive_box").visible, "HUD holt die Ladungen der Zweiten Staffel vom Spieler.")
	_equal(int(_control(hud, "revive_pips").get("max_level")), 2, "Ladungen im Rucksack des Spielers.")
	_equal(int(_control(hud, "revive_pips").get("level")), 1, "Bereite Ladungen des Spielers.")
	# Der Spieler hält jetzt zwei Waffen, die rechte lädt gerade nach (halb fertig).
	player.controller.hands = [
		{"hand": 0, "uid": 3, "id": "smg", "level": 1, "hands": 1, "mag": 12, "magazine": 30, "reloading": false},
		{"hand": 1, "uid": 4, "id": "revolver", "level": 2, "hands": 1, "mag": 0, "magazine": 6, "reloading": true,
			"reload_left": 0.95, "reload_duration": 1.9},
	]
	_events.emit_signal("loadout_changed")
	_check(_hand_box(hud, 0).visible and _hand_box(hud, 1).visible, "loadout_changed: Das HUD zeigt beide Hände des Spielers.")
	_equal(_text(_hand_box(hud, 0), "Name"), "QUOTENHAMMER", "Linke Hand des Spielers.")
	_equal(_text(_hand_box(hud, 1), "Name"), "KANDIDATENSCHRECK", "Rechte Hand des Spielers.")
	_equal(_text(_hand_box(hud, 1), "AmmoRow/Ammo"), "0", "Magazin der rechten Hand.")
	_equal(_text(_hand_box(hud, 1), "AmmoRow/Magazine"), "/ 6", "Größe des Magazins der rechten Hand.")
	var player_bars: Array = hud.get("reload_bars")
	_check((player_bars[1] as Control).visible and not (player_bars[0] as Control).visible, "Das laufende Nachladen der rechten Hand wird übernommen.")
	_check(absf(float((player_bars[1] as Control).get("ratio")) - 0.5) < 0.05, "Der Balken beginnt beim Stand des Nachladens (etwa die Hälfte).")
	_check(not _label(hud, "reload_hint_label").visible, "Die leere Hand lädt schon nach: kein Nachladen-Hinweis.")
	# Der Spieler verschwindet mitten im Lauf: Das HUD darf nicht stolpern.
	_game.set("player", null)
	player.free()
	_game.call("start_run", 5)
	await _frames(2)
	_equal(_label(hud, "health_label").text, "100", "Ohne Spieler gelten wieder die Startwerte.")
	_check(not _control(hud, "revive_box").visible, "Ohne Spieler gibt es keine Ladungen der Zweiten Staffel.")
	await _remove(hud)


# --- Kistenwahl -----------------------------------------------------------------------

func _test_chest_choice() -> void:
	var choice: Node = _add_screen("res://scripts/ui/chest_choice.gd")
	await _frames(1)
	_equal(int(choice.get("layer")), 10, "Kistenwahl liegt auf Ebene 10.")
	_equal(int(choice.get("process_mode")), Node.PROCESS_MODE_ALWAYS, "Kistenwahl läuft auch in der Pause.")
	# Gewählte Gegenstände räumen sich in diesem Test selbst ein (der Rucksack-Bildschirm hat
	# seinen eigenen Test).
	_game.set("auto_pack", true)
	_game.call("start_run", 7)
	_check(not bool(choice.call("is_open")), "Kistenwahl ist anfangs zu.")

	# Öffnen über Game.open_chest: drei Karten mit den Texten der Angebote.
	_game.call("open_chest", Balance.RARITY_SILVER)
	_check(bool(choice.call("is_open")), "Kistenwahl öffnet bei chest_opened.")
	_check(paused, "Bei offener Wahl ist das Spiel pausiert.")
	_equal(_state(), STATE_CHOOSING, "State CHOOSING bei offener Wahl.")
	var cards: Array = choice.get("cards")
	var offers: Array = choice.get("offers")
	_equal(cards.size(), 3, "Drei Karten.")
	_equal(_label(choice, "headline_label").text, "SILBER-KISTE!", "Überschrift nennt die Seltenheit.")
	for i: int in mini(cards.size(), offers.size()):
		var card: Node = cards[i]
		var offer: Dictionary = offers[i]
		_equal(_text(card, "Key"), str(i + 1), "Karte %d zeigt ihre Taste." % (i + 1))
		_equal(String(offer.get("kind", "")), "item", "Karte %d ist ein Gegenstand." % (i + 1))
		_equal(_text(card, "Name"), ChestRoller.offer_title(offer), "Karte %d zeigt den Namen des Gegenstands." % (i + 1))
		var card_icon: Control = card.get_node_or_null("Icon") as Control
		_check(card_icon is ItemIcons.View and str(card_icon.get("item_id")) == String(offer["id"]), "Karte %d zeigt das Bild ihres Gegenstands." % (i + 1))
		_check(card.get_node_or_null("Shape") != null, "Karte %d zeigt daneben klein die Form im Rucksack." % (i + 1))
		_check(card.get_node_or_null("Broken") == null, "Karte %d: Ohne kaputte Fundstücke steht kein Hinweis auf der Karte." % (i + 1))
		if UpgradeDefs.has(String(offer["id"])):
			_equal(_text(card, "Level"), "NEU · Ungewöhnlich", "Karte %d: neuer Upgrade-Gegenstand aus der Silber-Kiste." % (i + 1))
			_equal(_text(card, "Tag"), "UNGEWÖHNLICH", "Karte %d zeigt die Rarität des Gegenstands." % (i + 1))
			# Der Text des Gegenstands: bei Stern-Gegenständen mit dem Hinweis auf die Sterne.
			_equal(_plain(_text(card, "Text")), ItemDefs.description(String(offer["id"]), 2), "Karte %d zeigt die Wirkung der Stufe." % (i + 1))
			_check(card.get_node_or_null("Pips") != null, "Karte %d zeigt Raritäts-Punkte." % (i + 1))
		else:
			var is_bag: bool = String(offer["id"]).begins_with("bag_")
			if is_bag:
				_equal(_text(card, "Level"), "Mehr Platz", "Karte %d: Rucksack-Teil verspricht Platz." % (i + 1))
				_equal(_text(card, "Tag"), "RUCKSACK", "Karte %d ist als Rucksack markiert." % (i + 1))
				_check(card.get_node_or_null("Pips") == null, "Karte %d (Rucksack-Teil) hat keine Raritäts-Punkte." % (i + 1))
			else:
				# Waffen sind seit Abschnitt 18 auch Gegenstände: Die Karte nennt dann "Waffe".
				var kind_text: String = "Waffe" if ItemDefs.is_weapon(String(offer["id"])) else "Verstärker"
				# Kameras sind seit Abschnitt 22 eine eigene Art.
				if ItemDefs.is_camera(String(offer["id"])):
					kind_text = "Kamera"
				_equal(_text(card, "Level"), "%s · NEU · Ungewöhnlich" % kind_text, "Karte %d: %s mit Rarität." % [i + 1, kind_text])
				_equal(_text(card, "Tag"), "UNGEWÖHNLICH", "Karte %d zeigt die Rarität." % (i + 1))
				_check(card.get_node_or_null("Pips") != null, "Karte %d (%s) zeigt Raritäts-Punkte." % [i + 1, kind_text])
			_equal(_plain(_text(card, "Text")), ChestRoller.offer_description(offer), "Karte %d zeigt die Wirkung." % (i + 1))
		_check(not _text(card, "Text").contains(" m ") and not _text(card, "Text").contains(" % "), "Karte %d trennt Zahl und Einheit nicht (geschütztes Leerzeichen)." % (i + 1))

	# Eingabesperre direkt nach dem Öffnen: Taste und Klick wählen nichts.
	_check(bool(choice.call("is_input_locked")), "Direkt nach dem Öffnen ist die Eingabe gesperrt.")
	choice.call("_unhandled_input", _key(KEY_1))
	choice.call("_on_card_gui_input", _click(), 2)
	_check(not bool(choice.call("request_choice", 0)), "request_choice lehnt während der Sperre ab.")
	await _frames(3)
	_check(bool(choice.call("is_open")), "Während der Sperre bleibt die Wahl offen.")
	_equal(_state(), STATE_CHOOSING, "Während der Sperre bleibt der State CHOOSING.")
	var unlocked: bool = await _wait_until(func() -> bool: return not bool(choice.call("is_input_locked")), 3.0)
	_check(unlocked, "Die Sperre endet von selbst.")

	# Taste 2 wählt die zweite Karte: Game.choose_offer läuft, Pause aus.
	var second: Dictionary = offers[1]
	choice.call("_unhandled_input", _key(KEY_2))
	_check(bool(choice.call("is_input_locked")), "Nach der Eingabe ist die Wahl bis zur Bestätigung gesperrt.")
	var chosen: bool = await _wait_until(func() -> bool: return not bool(choice.call("is_open")), 3.0)
	_check(chosen, "Taste 2 schließt die Wahl.")
	_equal(_state(), STATE_PLAYING, "Nach der Wahl läuft das Spiel (State PLAYING).")
	_check(not paused, "Nach der Wahl ist die Pause aus.")
	if UpgradeDefs.has(String(second["id"])):
		_equal(int(_upgrades().call("get_level", String(second["id"]))), int(second["level"]), "Der gewählte Upgrade-Gegenstand wirkt mit seiner Stufe.")
	_check((_game.get("backpack").call("storage_items") as Array).is_empty(), "Der gewählte Gegenstand wurde eingeräumt.")
	_equal((choice.get("cards") as Array).size(), 0, "Nach der Wahl sind die Karten weg.")

	# Mausklick auf die erste Karte.
	_game.call("open_chest", Balance.RARITY_BRONZE)
	offers = choice.get("offers")
	var first: Dictionary = offers[0]
	var level_before: int = int(_upgrades().call("get_level", String(first.get("id", ""))))
	# Der Zeiger steht nach dem Gefecht in der Bildmitte, also auf der mittleren Karte. Die Wahl
	# setzt ihn auf die Hinweiszeile: Dort liegt keine Karte, auch keine vergrößerte.
	await _frames(2)
	var rest: Vector2 = choice.call("get_pointer_rest_position")
	var screen: Rect2 = root.get_visible_rect()
	_check(screen.has_point(rest), "Die Ruhestelle des Zeigers liegt im Bild (%s in %s)." % [str(rest), str(screen)])
	var middle_card: Control = (choice.get("cards") as Array)[1] as Control
	var center_on_card: bool = Rect2(middle_card.get_parent_control().global_position + (middle_card.get_meta("rest_position") as Vector2), middle_card.size).has_point(screen.get_center())
	_check(center_on_card, "Aufbau: Die Bildmitte liegt auf der mittleren Karte.")
	for card_variant: Variant in choice.get("cards") as Array:
		var parked_card: Control = card_variant as Control
		var card_rect: Rect2 = Rect2(parked_card.get_parent_control().global_position + (parked_card.get_meta("rest_position") as Vector2), parked_card.size)
		_check(not card_rect.grow(parked_card.size.y * 0.08).has_point(rest), "Die Ruhestelle des Zeigers liegt auf keiner Karte (%s)." % parked_card.name)
	# Klicks zählen später als Tasten: Schnelles Klicken aus dem Gefecht wählt nichts blind.
	await _wait_until(func() -> bool: return not bool(choice.call("is_input_locked")), 3.0)
	_check(bool(choice.call("is_click_locked")), "Nach der Tasten-Sperre sind Klicks noch gesperrt.")
	choice.call("_on_card_gui_input", _click(), 1)
	_check(not bool(choice.call("is_input_locked")), "Ein Klick während der Klick-Sperre wählt nichts.")
	await _frames(3)
	_check(bool(choice.call("is_open")), "Nach dem zu frühen Klick ist die Wahl noch offen.")
	var click_unlocked: bool = await _wait_until(func() -> bool: return not bool(choice.call("is_click_locked")), 3.0)
	_check(click_unlocked, "Die Klick-Sperre endet von selbst.")
	choice.call("_on_card_gui_input", _click(), 0)
	chosen = await _wait_until(func() -> bool: return not bool(choice.call("is_open")), 3.0)
	_check(chosen, "Ein Klick auf die Karte schließt die Wahl.")
	_check(not paused, "Nach dem Klick ist die Pause aus.")
	if UpgradeDefs.has(String(first["id"])):
		_check(int(_upgrades().call("get_level", String(first["id"]))) >= mini(level_before + 1, Balance.UPGRADE_MAX_LEVEL), "Bronze gibt dem angeklickten Upgrade mindestens eine Stufe.")

	# choose(index) wirkt sofort und ohne Sperre (für Tests und andere Module).
	_game.call("open_chest", Balance.RARITY_GOLD)
	_equal(_label(choice, "headline_label").text, "GOLD-KISTE! JACKPOT!", "Gold-Überschrift.")
	choice.call("choose", 7)
	_check(bool(choice.call("is_open")), "Ein ungültiger Index ändert nichts.")
	_check(not bool(choice.call("request_choice", 7)), "request_choice lehnt ungültige Indizes ab.")
	choice.call("choose", 2)
	_check(not bool(choice.call("is_open")), "choose schließt sofort.")
	_equal(_state(), STATE_PLAYING, "choose ruft Game.choose_offer (State PLAYING).")
	_check(not paused, "choose hebt die Pause auf.")

	# Darstellung: Aufstieg "Stufe 2 → 4" und Trostpreise.
	var shown: Array = [
		{"kind": "upgrade", "id": "pierce", "from_level": 2, "to_level": 4},
		{"kind": "points", "amount": 500},
		{"kind": "heal", "amount": 50},
	]
	choice.call("show_offers", Balance.RARITY_SILVER, shown)
	cards = choice.get("cards")
	_equal(cards.size(), 3, "Drei Karten auch mit Trostpreisen.")
	await _frames(2)
	if cards.size() == 3:
		_equal(_text(cards[0], "Level"), "Stufe 2 → 4", "Aufstieg als Stufe 2 → 4.")
		_equal(_plain(_text(cards[0], "Text")), UpgradeDefs.effect_text("pierce", 4), "Wirkungstext der Zielstufe.")
		_check((cards[0] as Node).get_node_or_null("Pips") != null, "Upgrade-Karte hat Stufen-Punkte.")
		_equal(_text(cards[1], "Tag"), "TROSTPREIS", "Trostpreis ist als solcher markiert.")
		_equal(_text(cards[1], "Name"), "Punkte", "Trostpreis Punkte.")
		_equal(_text(cards[1], "Level"), "+500 PUNKTE", "Trostpreis zeigt den Betrag.")
		_equal(_text(cards[2], "Name"), "Erste Hilfe", "Trostpreis Heilung.")
		_equal(_text(cards[2], "Level"), "+50 LEBEN", "Trostpreis zeigt die Heilung.")
		_equal(_text(cards[2], "Text"), ChestRoller.offer_description(shown[2]), "Trostpreis-Text aus dem ChestRoller.")
		_check((cards[2] as Node).get_node_or_null("Pips") == null, "Trostpreis hat keine Stufen-Punkte.")
		# Bilder: Das Upgrade zeigt das Bild seines Gegenstands, Trostpreise ihr eigenes Symbol.
		var upgrade_icon: Control = (cards[0] as Node).get_node_or_null("Icon") as Control
		_check(upgrade_icon is ItemIcons.View and str(upgrade_icon.get("item_id")) == "pierce", "Die Upgrade-Karte zeigt das Bild des Gegenstands.")
		_equal(str(((cards[1] as Node).get_node("Icon") as Control).get("icon_id")), "points", "Der Trostpreis Punkte zeigt sein Symbol.")
		_equal(str(((cards[2] as Node).get_node("Icon") as Control).get("icon_id")), "heal", "Der Trostpreis Heilung zeigt sein Symbol.")
		for card_variant: Variant in cards:
			_check((card_variant as Node).get_node_or_null("Shape") == null, "Upgrades und Trostpreise zeigen keine Form im Rucksack.")
			_check((card_variant as Node).get_node_or_null("Broken") == null, "Upgrades und Trostpreise kommen nie kaputt an.")
		# Nichts ragt aus der Karte: Jedes Textfeld liegt innerhalb der Kartengröße.
		for card_variant: Variant in cards:
			var card_control: Control = card_variant as Control
			for child: Node in card_control.get_children():
				var part: Control = child as Control
				if part == null or part.name == "NewSticker":
					continue
				_check(part.position.x >= -0.5 and part.position.y >= -0.5
						and part.position.x + part.size.x <= card_control.size.x + 0.5
						and part.position.y + part.size.y <= card_control.size.y + 0.5,
						"Kartenteil %s bleibt innerhalb der Karte." % part.name)
	choice.call("close")
	_check(not bool(choice.call("is_open")), "close schließt ohne Wahl.")
	await _test_all_item_cards(choice, false)
	await _test_all_item_cards(choice, true)
	_test_broken_note(choice)
	choice.call("show_offers", Balance.RARITY_BRONZE, [])
	_check(not bool(choice.call("is_open")), "Ohne Angebote bleibt die Wahl zu.")

	# Game Over und neuer Lauf schließen die Wahl.
	_game.call("start_run", 7)
	_game.call("open_chest", Balance.RARITY_BRONZE)
	_check(bool(choice.call("is_open")), "Wahl ist wieder offen.")
	_game.call("start_run", 7)
	_check(not bool(choice.call("is_open")), "Ein neuer Lauf schließt die Wahl.")
	await _remove(choice)
	_game.set("auto_pack", false)


## Der Hinweis auf kaputte Fundstücke als Text (Abschnitt 26.1): Preis der Reparatur je Rarität,
## nichts bei Rucksack-Teilen, nichts ohne kaputte Fundstücke.
func _test_broken_note(choice: Node) -> void:
	for level: int in range(1, 6):
		_equal(str(choice.call("broken_note", "rifle", level, true)), "Kommt kaputt in die Ablage · Reparatur: %d Material" % Balance.REPAIR_COST[level - 1],
			"Der Hinweis nennt den Preis der Reparatur für Rarität %d." % level)
	_equal(str(choice.call("broken_note", "cam_flash", 3, true)), "Kommt kaputt in die Ablage · Reparatur: 3 Material", "Auch eine Kamera kommt kaputt an.")
	_equal(str(choice.call("broken_note", "replay", 9, true)), "Kommt kaputt in die Ablage · Reparatur: %d Material" % Balance.REPAIR_COST[4], "Eine zu hohe Rarität gilt als Legendär.")
	_equal(str(choice.call("broken_note", "rifle", 0, true)), "Kommt kaputt in die Ablage · Reparatur: %d Material" % Balance.REPAIR_COST[0], "Eine zu kleine Rarität gilt als Gewöhnlich.")
	for bag_id: String in ["bag_tiny", "bag_small", "bag_medium", "bag_large"]:
		_equal(str(choice.call("broken_note", bag_id, 1, true)), "", "Das Rucksack-Teil %s kommt nie kaputt an." % bag_id)
	_equal(str(choice.call("broken_note", "rifle", 2, false)), "", "Ohne kaputte Fundstücke gibt es keinen Hinweis.")
	_equal(str(choice.call("broken_note", "gibt_es_nicht", 2, true)), "", "Eine unbekannte ID bekommt keinen Hinweis.")
	_equal(str(choice.call("broken_note", "", 2, true)), "", "Ohne ID gibt es keinen Hinweis.")


## Die Karte jedes Gegenstands aus ItemDefs.ORDER (65, darunter die Kameras und alles Neue aus
## Abschnitt 22): Bild, Name, Zeile mit Art und Rarität und Wirkungstext passen in ihre Felder,
## lange Namen brechen nur an Leerzeichen und Bindestrichen um, nichts ragt aus der Karte.
## broken_loot: Fundstücke kommen kaputt an (Game.broken_loot), dann steht auf jeder Karte außer
## denen der Rucksack-Teile der Hinweis mit dem Preis der Reparatur.
func _test_all_item_cards(choice: Node, broken_loot: bool) -> void:
	var loot_before: Variant = _game.get("broken_loot")
	_game.set("broken_loot", broken_loot)
	_equal(_game.get("broken_loot") == true, broken_loot, "Aufbau: Game.broken_loot lässt sich auf %s stellen." % str(broken_loot))
	var slanted: Font = _hud_script.call("show_font", true) as Font
	var upright: Font = _hud_script.call("show_font", false) as Font
	var ids: Array[String] = ItemDefs.all_ids()
	_equal(ids.size(), 65, "Aufbau: Es gibt 65 Gegenstände.")
	var seen: int = 0
	for start: int in range(0, ids.size(), 3):
		var shown: Array = []
		for i: int in range(start, mini(start + 3, ids.size())):
			# Abwechselnd alle Raritäten, damit auch die längsten Zeilen ("… · NEU · Ungewöhnlich") vorkommen.
			shown.append({"kind": "item", "id": ids[i], "level": 1 + (i % 5), "owned_level": 0 if i % 2 == 0 else 1 + (i % 5)})
		choice.call("show_offers", Balance.RARITY_GOLD, shown)
		await _frames(1)
		var cards: Array = choice.get("cards")
		_equal(cards.size(), shown.size(), "Je Angebot eine Karte (ab %s)." % ids[start])
		for n: int in mini(cards.size(), shown.size()):
			var card: Control = cards[n] as Control
			var offer: Dictionary = shown[n]
			var id: String = str(offer["id"])
			seen += 1
			_equal(_text(card, "Name"), ItemDefs.display_name(id), "Die Karte von %s zeigt den Namen." % id)
			_equal(_plain(_text(card, "Text")), ItemDefs.description(id, int(offer["level"])), "Die Karte von %s zeigt die Wirkung." % id)
			# Bild: das gezeichnete Bild des Gegenstands, groß und mittig, daneben klein die Form.
			var icon: Control = card.get_node_or_null("Icon") as Control
			_check(icon is ItemIcons.View and str(icon.get("item_id")) == id, "Die Karte von %s zeigt das Bild des Gegenstands." % id)
			_check(icon.size.x >= 96.0 and is_equal_approx(icon.size.x, icon.size.y), "Das Bild von %s ist groß und quadratisch (%s)." % [id, str(icon.size)])
			_check(absf(icon.position.x + icon.size.x * 0.5 - card.size.x * 0.5) < 0.5, "Das Bild von %s sitzt in der Mitte der Karte." % id)
			var small_shape: Control = card.get_node_or_null("Shape") as Control
			_check(small_shape != null and str(small_shape.get("item_id")) == id, "Die Karte von %s zeigt klein die Form im Rucksack." % id)
			if small_shape != null:
				_check(small_shape.position.x + small_shape.size.x <= icon.position.x + 0.5, "Die kleine Form von %s steht links neben dem Bild." % id)
			_check(icon.position.y + icon.size.y <= (card.get_node("Name") as Control).position.y + 0.5, "Das Bild von %s endet über dem Namen." % id)
			# Hinweis auf kaputte Fundstücke.
			var note_label: Label = card.get_node_or_null("Broken") as Label
			var expects_note: bool = broken_loot and not ItemDefs.is_bag(id)
			_equal(note_label != null, expects_note, "Die Karte von %s zeigt den Hinweis auf die Reparatur genau dann, wenn das Fundstück kaputt ankommt." % id)
			if note_label != null:
				_equal(_plain(note_label.text), "Kommt kaputt in die Ablage · Reparatur: %d Material" % Balance.REPAIR_COST[int(offer["level"]) - 1],
					"Die Karte von %s nennt den Preis der Reparatur." % id)
				_check(note_label.get_line_count() <= 2, "Der Hinweis von %s braucht höchstens zwei Zeilen." % id)
				var note_spacing: float = float(note_label.get_theme_constant("line_spacing"))
				var note_needed: float = float(note_label.get_line_count()) * (float(note_label.get_line_height()) + note_spacing) - note_spacing
				_check(note_needed <= note_label.size.y + 0.5, "Der Hinweis von %s passt in seinen Streifen (%d von %d)." % [id, roundi(note_needed), roundi(note_label.size.y)])
				for line: String in note_label.text.split(" · "):
					_check(upright.get_string_size(line + " ·", HORIZONTAL_ALIGNMENT_LEFT, -1.0, note_label.get_theme_font_size("font_size")).x <= note_label.size.x + 0.5,
						"Die Zeile „%s“ des Hinweises von %s passt in die Karte." % [line, id])
				var text_part: Control = card.get_node("Text") as Control
				_check(text_part.position.y + text_part.size.y <= note_label.position.y + 0.5, "Der Wirkungstext von %s endet über dem Hinweis." % id)
			# Name: höchstens zwei Zeilen, kein Wort wird mittendrin getrennt.
			var name_label: Label = card.get_node("Name") as Label
			var name_size: int = name_label.get_theme_font_size("font_size")
			_check(name_label.get_line_count() <= 2, "Der Name von %s braucht höchstens zwei Zeilen." % id)
			for word: String in name_label.text.split(" ", false):
				_check(slanted.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, name_size).x <= name_label.size.x + 0.5,
					"Das Wort „%s“ im Namen von %s passt in die Karte." % [word, id])
			# Zeile mit Art und Rarität: passt in einer Zeile in die Karte.
			var level_label: Label = card.get_node("Level") as Label
			_check(slanted.get_string_size(level_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, level_label.get_theme_font_size("font_size")).x <= level_label.size.x + 0.5,
				"Die Zeile „%s“ von %s passt in die Karte." % [level_label.text, id])
			# Wirkungstext: Alle Zeilen passen in das Feld, die Schrift bleibt lesbar.
			var text_label: Label = card.get_node("Text") as Label
			var spacing: float = float(text_label.get_theme_constant("line_spacing"))
			var needed: float = float(text_label.get_line_count()) * (float(text_label.get_line_height()) + spacing) - spacing
			_check(needed <= text_label.size.y + 0.5, "Der Wirkungstext von %s passt in die Karte (%d von %d)." % [id, roundi(needed), roundi(text_label.size.y)])
			_check(text_label.get_theme_font_size("font_size") >= 11, "Der Wirkungstext von %s ist mindestens 11 Punkt groß." % id)
			for child: Node in card.get_children():
				var part: Control = child as Control
				if part == null or part.name == "NewSticker":
					continue
				_check(part.position.x >= -0.5 and part.position.y >= -0.5
						and part.position.x + part.size.x <= card.size.x + 0.5
						and part.position.y + part.size.y <= card.size.y + 0.5,
						"Kartenteil %s von %s bleibt innerhalb der Karte." % [part.name, id])
			# Der Aufkleber NEU überdeckt das Bild nicht.
			var sticker: Control = card.get_node_or_null("NewSticker") as Control
			_equal(sticker != null, ItemDefs.has_rarity(id) and int(offer["owned_level"]) <= 0, "Die Karte von %s trägt den Aufkleber NEU genau dann, wenn der Gegenstand neu ist." % id)
			if sticker != null:
				var drawn_right: float = icon.position.x + icon.size.x
				_check(drawn_right <= sticker.position.x + 4.0, "Das Bild von %s endet vor dem Aufkleber NEU (%d vor %d)." % [id, roundi(drawn_right), roundi(sticker.position.x)])
			if ItemDefs.is_camera(id):
				_check(_text(card, "Level").begins_with("Kamera · "), "Die Karte der Kamera %s nennt die Art, war: %s" % [id, _text(card, "Level")])
			elif ItemDefs.is_weapon(id):
				_check(_text(card, "Level").begins_with("Waffe · "), "Die Karte der Waffe %s nennt die Art." % id)
				_check(_text(card, "Text").contains("Hand") or _text(card, "Text").contains("Hände"), "Die Karte der Waffe %s nennt die Hände." % id)
	_equal(seen, ids.size(), "Jeder Gegenstand hatte seine Karte.")
	choice.call("close")
	_game.set("broken_loot", loot_before == true)


# --- Pausemenü ------------------------------------------------------------------------

func _test_pause_menu() -> void:
	var menu: Node = _add_screen("res://scripts/ui/pause_menu.gd")
	await _frames(1)
	_equal(int(menu.get("layer")), 20, "Pausemenü liegt auf Ebene 20.")
	_game.call("start_run", 9)
	_check(not bool(menu.call("is_open")), "Pausemenü ist anfangs zu.")
	_equal((menu.get("resume_button") as Button).text, "WEITER", "Knopf Weiter.")
	_equal((menu.get("restart_button") as Button).text, "NEUSTART", "Knopf Neustart.")
	_equal((menu.get("quit_button") as Button).text, "BEENDEN", "Knopf Beenden.")
	_check((menu.get("quit_button") as Button).pressed.get_connections().size() > 0, "Beenden ist verdrahtet.")

	# Esc schaltet um.
	menu.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(bool(menu.call("is_open")), "Esc öffnet das Pausemenü.")
	_equal(_state(), STATE_PAUSED, "State PAUSED im Pausemenü.")
	_check(paused, "Im Pausemenü ist das Spiel pausiert.")
	menu.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(not bool(menu.call("is_open")), "Esc schließt das Pausemenü.")
	_equal(_state(), STATE_PLAYING, "Nach Esc läuft das Spiel.")
	_check(not paused, "Nach Esc ist die Pause aus.")

	# Knopf Weiter.
	menu.call("open")
	_check(bool(menu.call("is_open")), "open öffnet das Menü.")
	(menu.get("resume_button") as Button).pressed.emit()
	_check(not bool(menu.call("is_open")), "Weiter schließt das Menü.")
	_check(not paused, "Weiter hebt die Pause auf.")
	_check(not (menu.get("resume_button") as Button).has_focus(), "Im laufenden Spiel hat kein Menü-Knopf den Fokus.")

	# In der Kistenwahl wirkt Esc nicht.
	_game.call("open_chest", Balance.RARITY_BRONZE)
	menu.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(not bool(menu.call("is_open")), "In der Kistenwahl öffnet Esc kein Pausemenü.")
	_equal(_state(), STATE_CHOOSING, "Kistenwahl bleibt bestehen.")
	_game.call("choose_offer", 0)

	# Knopf Neustart ruft Game.restart_run (ohne current_scene beginnt sofort ein neuer Lauf).
	_game.call("add_points", 500)
	menu.call("open")
	var starts_before: int = _run_starts
	(menu.get("restart_button") as Button).pressed.emit()
	_equal(_run_starts, starts_before + 1, "Neustart beginnt einen neuen Lauf.")
	_equal(int(_game.get("points")), 0, "Neustart setzt die Punkte zurück.")
	_check(not bool(menu.call("is_open")), "Nach dem Neustart ist das Menü zu.")
	_check(not paused, "Nach dem Neustart ist die Pause aus.")

	# Im Game Over bleibt das Menü zu.
	_game.call("end_run")
	menu.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(not bool(menu.call("is_open")), "Im Game Over öffnet Esc kein Pausemenü.")
	_game.call("start_run", 9)
	await _remove(menu)


# --- Game Over ------------------------------------------------------------------------

func _test_game_over() -> void:
	var screen: Node = _add_screen("res://scripts/ui/game_over.gd")
	await _frames(1)
	_equal(int(screen.get("layer")), 30, "Game Over liegt auf Ebene 30.")
	_game.call("start_run", 11)
	_check(not bool(screen.call("is_open")), "Game Over ist anfangs zu.")

	# Ein Lauf mit Welle, Kills, Punkten und Upgrades.
	_events.emit_signal("wave_started", 7, 34)
	_events.emit_signal("zombie_killed", null, {"source": "bullet"})
	_events.emit_signal("zombie_killed", null, {"source": "bullet"})
	_game.call("add_points", 12220)
	var upgrades: RefCounted = _upgrades()
	upgrades.call("add_levels", "pierce", 5)
	upgrades.call("add_levels", "chain_lightning", 5)
	upgrades.call("add_levels", "burn", 2)
	_game.call("end_run")
	_check(bool(screen.call("is_open")), "Game Over öffnet bei game_over.")
	_equal(_label(screen, "headline_label").text, "SENDESCHLUSS!", "Überschrift.")
	_check(_label(screen, "subline_label").text.begins_with("Game Over."), "Unterzeile nennt Game Over.")
	_equal(_label(screen, "wave_value_label").text, "7", "Erreichte Welle.")
	_equal(_label(screen, "kills_value_label").text, "2", "Kills.")
	_equal(_label(screen, "points_value_label").text, "12.340", "Insgesamt verdiente Punkte (2 Kills + 12.220).")
	var list: Control = _control(screen, "upgrade_list")
	_equal(list.get_child_count(), 4, "Drei Upgrades und die Synergie.")
	_equal(_text(list, "Row_pierce/Name"), "Spezialmunition", "Upgrade-Name in der Liste.")
	_equal(_text(list, "Row_pierce/Rarity"), "LEGENDÄR", "Stufe 5 heißt Legendär.")
	_equal(_text(list, "Row_burn/Rarity"), "UNGEWÖHNLICH", "Die Zeile nennt die Rarität des Upgrades.")
	_equal(_text(list, "Synergy_storm_front/Name"), "Gewitterfront", "Synergie in der Liste.")
	_check(not _label(screen, "empty_label").visible, "Mit Upgrades kein Leer-Hinweis.")
	# Jede Zeile zeigt das Bild ihres Gegenstands (item_icons.gd), die Synergie ihr eigenes Symbol.
	for row_id: String in ["pierce", "chain_lightning", "burn"]:
		var row_icon: Control = list.get_node_or_null("Row_%s/Icon" % row_id) as Control
		_check(row_icon is ItemIcons.View and str(row_icon.get("item_id")) == row_id, "Die Zeile von %s zeigt das Bild des Gegenstands." % row_id)
		if row_icon != null:
			var row_control: Control = list.get_node("Row_%s" % row_id) as Control
			_check(row_icon.position.x >= 0.0 and row_icon.position.y >= 0.0 and row_icon.position.y + row_icon.size.y <= row_control.size.y + 0.5,
				"Das Bild von %s bleibt in seiner Zeile." % row_id)
			_check(row_icon.position.x + row_icon.size.x <= (row_control.get_node("Name") as Control).position.x + 0.5, "Das Bild von %s steht vor dem Namen." % row_id)
			_check(is_equal_approx(row_icon.size.x, row_icon.size.y) and row_icon.size.x >= 24.0, "Das Bild von %s ist quadratisch und mindestens 24 Pixel groß." % row_id)
	_equal(str((list.get_node("Synergy_storm_front/Icon") as Control).get("icon_id")), "synergy", "Die Synergie behält ihr Symbol.")
	_equal((screen.get("restart_button") as Button).text, "NEUSTART", "Knopf Neustart.")
	_equal((screen.get("quit_button") as Button).text, "BEENDEN", "Knopf Beenden.")
	_check((screen.get("quit_button") as Button).pressed.get_connections().size() > 0, "Beenden ist verdrahtet.")
	# Konto (Abschnitt 22.5): Gutschrift des Laufs und neuer Kontostand.
	var run_stats: Dictionary = screen.get("stats")
	_equal(int(run_stats.get("bank_gained", -1)), 12340, "Aufbau: Der Lauf bringt 12.340 aufs Konto.")
	_equal(_label(screen, "bank_gain_label").text, "+12.340", "Game Over zeigt die Gutschrift des Laufs.")
	_equal(_label(screen, "bank_label").text, str(_hud_script.call("format_int", int(run_stats.get("bank", -1)))), "Game Over zeigt den neuen Kontostand.")
	_equal(int(run_stats.get("bank", -1)), int((_game.get("progress") as RefCounted).get("bank")), "Der Kontostand ist der aus Game.progress.")
	var program_button: Button = screen.get("program_button") as Button
	_equal(program_button.text, "PROGRAMM", "Knopf Programm.")
	_check(program_button.disabled, "Der Knopf Programm ist direkt nach dem Öffnen gesperrt wie die anderen.")
	# Die drei Knöpfe stehen nebeneinander und überlappen nicht.
	var restart_rect: Rect2 = Rect2((screen.get("restart_button") as Button).position, (screen.get("restart_button") as Button).size)
	var program_rect: Rect2 = Rect2(program_button.position, program_button.size)
	var quit_rect: Rect2 = Rect2((screen.get("quit_button") as Button).position, (screen.get("quit_button") as Button).size)
	_check(restart_rect.end.x <= program_rect.position.x and program_rect.end.x <= quit_rect.position.x, "Neustart, Programm und Beenden stehen nebeneinander.")
	var stage: Control = screen.get_node("Root/Stage") as Control
	_check(restart_rect.position.x >= 0.0 and quit_rect.end.x <= stage.size.x + 0.5, "Die drei Knöpfe passen auf die Bühne.")
	var requests: Array[int] = [0]
	screen.connect("program_requested", func() -> void: requests[0] += 1)
	program_button.pressed.emit()
	screen.call("_unhandled_input", _key(KEY_P))
	_equal(requests[0], 0, "Während der Sperre öffnet nichts das Programm.")

	# Sperre direkt nach dem Öffnen: R und Knopf starten nicht neu.
	_check(bool(screen.call("is_input_locked")), "Direkt nach dem Öffnen ist die Eingabe gesperrt.")
	var starts_before: int = _run_starts
	screen.call("_unhandled_input", _key(KEY_R))
	(screen.get("restart_button") as Button).pressed.emit()
	_equal(_run_starts, starts_before, "Während der Sperre startet nichts neu.")
	_equal(_state(), STATE_GAME_OVER, "State bleibt GAME_OVER.")
	var unlocked: bool = await _wait_until(func() -> bool: return not bool(screen.call("is_input_locked")), 3.0)
	_check(unlocked, "Die Sperre endet von selbst.")
	_check(not (screen.get("restart_button") as Button).disabled, "Nach der Sperre ist der Knopf frei.")
	# Programm: Knopf und Taste P melden program_requested (ohne zugewiesenen Bildschirm nur das).
	_check(not program_button.disabled, "Nach der Sperre ist auch der Knopf Programm frei.")
	program_button.pressed.emit()
	_equal(requests[0], 1, "Der Knopf Programm meldet program_requested.")
	screen.call("_unhandled_input", _key(KEY_P))
	_equal(requests[0], 2, "Die Taste P meldet program_requested.")
	_check(bool(screen.call("is_open")) and not bool(screen.call("is_program_open")), "Ohne zugewiesenen Bildschirm bleibt das Game Over allein offen.")
	_equal(_state(), STATE_GAME_OVER, "Das Programm zu öffnen ändert den Spielzustand nicht.")
	# Der Kontostand folgt bank_changed (ein Kauf im Programm zieht ab), die Gutschrift bleibt.
	_events.emit_signal("bank_changed", 777, -2000)
	_equal(_label(screen, "bank_label").text, "777", "Der Kontostand folgt bank_changed.")
	_equal(_label(screen, "bank_gain_label").text, "+12.340", "Die Gutschrift des Laufs bleibt stehen.")

	# Taste R startet neu.
	screen.call("_unhandled_input", _key(KEY_R))
	_equal(_run_starts, starts_before + 1, "R startet neu.")
	_equal(_state(), STATE_PLAYING, "Nach R läuft das Spiel.")
	_check(not paused, "Nach R ist die Pause aus.")
	_check(not bool(screen.call("is_open")), "Der neue Lauf schließt das Game Over.")

	# Lauf ohne Upgrades, Neustart über den Knopf.
	_game.call("end_run")
	_check(bool(screen.call("is_open")), "Game Over öffnet erneut.")
	_equal(_label(screen, "wave_value_label").text, "0", "Welle 0 ohne Wellenstart.")
	_equal(list.get_child_count(), 0, "Keine Upgrade-Zeilen.")
	_check(_label(screen, "empty_label").visible, "Ohne Upgrades erscheint der Leer-Hinweis.")
	await _wait_until(func() -> bool: return not bool(screen.call("is_input_locked")), 3.0)
	starts_before = _run_starts
	(screen.get("restart_button") as Button).pressed.emit()
	_equal(_run_starts, starts_before + 1, "Der Knopf Neustart startet neu.")
	_check(not bool(screen.call("is_open")), "Nach dem Neustart ist das Game Over zu.")

	# Kameras stehen in der Liste des Builds (stats["cameras"], ein Eintrag je Exemplar): je
	# Kameratyp eine Zeile, gleiche zusammengefasst, mit der besten Rarität.
	screen.call("show_stats", {
		"wave": 9, "kills": 120, "points": 9000, "bank_gained": 9000, "bank": 1234567,
		"upgrades": [{"id": "burn", "name": "Feuershow", "level": 3}, {"id": "revive", "name": "Zweite Staffel", "level": 2}],
		"synergies": ["storm_front"],
		"cameras": [{"id": "drone", "name": "Kameradrohne", "level": 2}, {"id": "cam_flash", "name": "Blitzlicht-Kamera", "level": 4},
			{"id": "drone", "name": "Kameradrohne", "level": 3}],
	})
	_equal(list.get_child_count(), 5, "Zwei Upgrades, zwei Kameratypen und die Synergie.")
	_equal(_text(list, "Row_drone/Name"), "2 × Kameradrohne", "Zwei Drohnen stehen als eine Zeile mit Zahl da.")
	_equal(_text(list, "Row_drone/Rarity"), "SELTEN", "Die Zeile nennt die beste Rarität der Drohnen.")
	_equal(_text(list, "Row_cam_flash/Name"), "Blitzlicht-Kamera", "Die Blitzlicht-Kamera steht in der Liste.")
	_equal(_text(list, "Row_cam_flash/Rarity"), "EPISCH", "Die Kamera nennt ihre Rarität.")
	_equal(_text(list, "Row_revive/Name"), "Zweite Staffel", "Neue Gegenstände stehen mit ihrem Namen in der Liste.")
	for camera_row_id: String in ["cam_flash", "drone", "revive", "burn"]:
		var camera_icon: Control = list.get_node_or_null("Row_%s/Icon" % camera_row_id) as Control
		_check(camera_icon is ItemIcons.View and str(camera_icon.get("item_id")) == camera_row_id, "Die Zeile von %s zeigt das Bild aus item_icons.gd." % camera_row_id)
	_check(list.get_child(2).name == "Row_drone" and list.get_child(4).name == "Synergy_storm_front", "Reihenfolge: Upgrades, Kameras, Synergien.")
	_equal(_label(screen, "bank_gain_label").text, "+9.000", "Die Gutschrift steht mit Tausenderpunkt da.")
	_equal(_label(screen, "bank_label").text, "1.234.567", "Auch ein Millionen-Konto steht ganz da.")
	var bank_label: Label = _label(screen, "bank_label")
	var slanted: Font = _hud_script.call("show_font", true) as Font
	_check(slanted.get_string_size(bank_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, bank_label.get_theme_font_size("font_size")).x <= bank_label.size.x + 0.5,
		"Das Millionen-Konto passt in sein Feld.")
	_check(not _label(screen, "empty_label").visible, "Mit Kameras kein Leer-Hinweis.")
	# Nur Kameras: Auch das ist ein Build.
	screen.call("show_stats", {"wave": 2, "cameras": [{"id": "cam_slow", "name": "Zeitlupen-Kamera", "level": 1}]})
	_equal(list.get_child_count(), 1, "Eine Kamera allein steht in der Liste.")
	_check(not _label(screen, "empty_label").visible, "Mit einer Kamera kein Leer-Hinweis.")
	_equal(_label(screen, "bank_gain_label").text, "+0", "Ohne Angabe steht +0 als Gutschrift.")
	# Viele Einträge (der Rucksack fasst mehr als zwölf verschiedene Gegenstände): Die Liste
	# bleibt in ihrem Rahmen, was nicht passt, zählt der letzte Platz.
	for count: int in [8, 9, 12, 13, 20, 24]:
		var many: Array = []
		for i: int in count:
			var many_id: String = UpgradeDefs.UPGRADES.keys()[i]
			many.append({"id": many_id, "name": UpgradeDefs.display_name(many_id), "level": 1 + (i % 5)})
		screen.call("show_stats", {"wave": 5, "upgrades": many, "synergies": [], "cameras": []})
		var shown_rows: int = 0
		var rows_fit: bool = true
		var overlap: bool = false
		var icons_fit: bool = true
		var rects: Array[Rect2] = []
		for child: Node in list.get_children():
			if child.is_queued_for_deletion():
				continue
			var row: Control = child as Control
			var rect: Rect2 = Rect2(row.position, row.size)
			if rect.position.x < -0.5 or rect.position.y < -0.5 or rect.end.x > list.size.x + 0.5 or rect.end.y > list.size.y + 0.5:
				rows_fit = false
			for other: Rect2 in rects:
				if rect.intersects(other):
					overlap = true
			rects.append(rect)
			if str(row.name).begins_with("Row_"):
				shown_rows += 1
				var many_icon: Control = row.get_node_or_null("Icon") as Control
				icons_fit = icons_fit and many_icon is ItemIcons.View and many_icon.position.y >= 0.0 \
						and many_icon.position.y + many_icon.size.y <= row.size.y + 0.5 \
						and many_icon.position.x + many_icon.size.x <= (row.get_node("Name") as Control).position.x + 0.5
		_check(rows_fit, "Mit %d Einträgen bleibt die Liste in ihrem Rahmen." % count)
		_check(not overlap, "Mit %d Einträgen überlappt keine Zeile." % count)
		_check(icons_fit, "Mit %d Einträgen hat jede Zeile ihr Bild, und es bleibt in der Zeile vor dem Namen." % count)
		if count <= 20:
			_equal(shown_rows, count, "Mit %d Einträgen stehen alle in der Liste." % count)
			_check(list.get_node_or_null("More") == null, "Mit %d Einträgen fehlt nichts." % count)
		else:
			_equal(shown_rows, 19, "Mit %d Einträgen stehen 19 in der Liste." % count)
			_equal(_text(list, "More"), "+%d weitere" % (count - 19), "Der letzte Platz nennt, wie viele fehlen.")
	# Ein echter Lauf mit einer Kamera im Rucksack: Game.get_stats() liefert sie mit.
	_game.call("start_run", 11)
	var pack: RefCounted = _game.get("backpack") as RefCounted
	var drone_uid: int = int(pack.call("add_item", "drone", 2))
	_check(bool(pack.call("auto_place", drone_uid)), "Aufbau: Die Kameradrohne passt in den Rucksack.")
	_game.call("sync_build")
	_game.call("end_run")
	_equal(_text(list, "Row_drone/Name"), ItemDefs.display_name("drone"), "Die Kamera aus dem Rucksack steht im Game Over.")
	_equal(_text(list, "Row_drone/Rarity"), "UNGEWÖHNLICH", "Mit ihrer Rarität.")
	_equal(_label(screen, "bank_gain_label").text, "+0", "Ein Lauf ohne Punkte bringt nichts aufs Konto.")

	# show_stats verträgt eine lückenhafte Statistik.
	screen.call("show_stats", {})
	_equal(_label(screen, "points_value_label").text, "0", "Leere Statistik zeigt 0 Punkte.")
	_equal(_label(screen, "bank_gain_label").text, "+0", "Leere Statistik zeigt +0 als Gutschrift.")
	screen.call("close")
	_check(not bool(screen.call("is_open")), "close blendet aus.")
	await _remove(screen)
