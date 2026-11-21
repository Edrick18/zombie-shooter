extends SceneTree
## Tests für den Kern der Kameras (Abschnitt 22.1): CameraDefs (Tabelle, fertige Werte),
## Kamera-Gegenstände und ihre Sterne in ItemDefs, BackpackState.cameras() und Game.cameras.

const Balance := preload("res://scripts/core/balance.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")

## Abschrift der Tabelle aus Abschnitt 22.1.
const EXPECTED: Dictionary = {
	"drone": {
		"name": "Kameradrohne", "range": 15.0,
		"damage": [15.0, 21.0, 28.0, 36.0, 46.0], "interval": [1.2, 1.0, 0.8, 0.65, 0.5],
	},
	"cam_tele": {
		"name": "Tele-Kamera", "range": 30.0,
		"damage": [70.0, 100.0, 135.0, 175.0, 220.0], "interval": [3.2, 2.9, 2.6, 2.3, 2.0],
		"pierce": [1.0, 1.0, 2.0, 2.0, 3.0],
	},
	"cam_flash": {
		"name": "Blitzlicht-Kamera", "range": 7.0,
		"damage": [18.0, 25.0, 33.0, 42.0, 52.0], "interval": [3.0, 2.8, 2.6, 2.4, 2.2],
	},
	"cam_slow": {
		"name": "Zeitlupen-Kamera", "range": 12.0,
		"damage": [4.0, 6.0, 8.0, 10.0, 12.0], "interval": [1.5, 1.4, 1.3, 1.2, 1.1],
		"slow": [0.30, 0.35, 0.40, 0.45, 0.50],
	},
	"cam_director": {
		"name": "Regie-Kamera", "range": 18.0,
		"interval": [3.0, 2.7, 2.4, 2.1, 1.8], "mark": [0.20, 0.25, 0.30, 0.40, 0.50],
	},
}

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
var _camera_changes: int = 0
var _build_changes: int = 0
var _chosen: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum.
	await process_frame
	_game = root.get_node("Game")
	_events = root.get_node("Events")
	_events.connect("cameras_changed", func() -> void: _camera_changes += 1)
	_events.connect("build_changed", func() -> void: _build_changes += 1)
	_events.connect("upgrade_chosen", func(id: String, _level: int) -> void: _chosen.append(id))

	_test_table()
	_test_stats()
	_test_texts()
	_test_items()
	_test_backpack_cameras()
	_test_backpack_replay()
	_test_game_cameras()

	paused = false
	_game.set("character_id", "")
	if _failures == 0:
		print("Alle Kamera-Kern-Tests bestanden (%d Prüfungen)." % _checks)
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


func _grid(width: int, height: int) -> BackpackState:
	var cells: Array[Vector2i] = []
	for y: int in height:
		for x: int in width:
			cells.append(Vector2i(x, y))
	var backpack: BackpackState = BackpackState.new()
	backpack.setup(cells)
	return backpack


## Legt einen Gegenstand an eine feste Stelle und prüft, dass es klappt.
func _put(backpack: BackpackState, id: String, level: int, pos: Vector2i, rot: int = 0) -> int:
	var uid: int = backpack.add_item(id, level)
	_check(backpack.place(uid, pos, rot), "%s lässt sich bei %s einräumen." % [id, str(pos)])
	return uid


# --- CameraDefs -----------------------------------------------------------------------

func _test_table() -> void:
	_check(CameraDefs.ORDER == (["drone", "cam_tele", "cam_flash", "cam_slow", "cam_director"] as Array[String]) and CameraDefs.all_ids() == CameraDefs.ORDER, "Fünf Kameratypen in fester Reihenfolge.")
	_check(CameraDefs.CAMERAS.size() == 5, "Die Tabelle hat genau 5 Kameras.")
	_check(CameraDefs.MOD_ORDER == (["cam_lens", "cam_zoom", "cam_battery", "cam_second", "cam_uplink"] as Array[String]), "Fünf Kamera-Gegenstände in fester Reihenfolge.")
	for id: String in EXPECTED:
		var want: Dictionary = EXPECTED[id]
		_check(CameraDefs.has(id), "Kamera %s steht in der Tabelle." % id)
		_check(CameraDefs.display_name(id) == str(want["name"]), "Name von %s war '%s'." % [id, CameraDefs.display_name(id)])
		for level: int in range(1, 6):
			_near(CameraDefs.base(id, "range", level), float(want["range"]), "%s Reichweite Rarität %d." % [id, level])
			for key: String in ["damage", "interval", "pierce", "slow", "mark"]:
				var expected: float = float((want[key] as Array)[level - 1]) if want.has(key) else 0.0
				_near(CameraDefs.base(id, key, level), expected, "%s.%s Rarität %d." % [id, key, level])
	_near(CameraDefs.base("drone", "damage", 0), 0.0, "Rarität 0 liefert 0.")
	_near(CameraDefs.base("drone", "damage", 9), 46.0, "Raritäten über 5 liefern den Wert der Rarität 5.")
	_near(CameraDefs.base("gibt_es_nicht", "damage", 3), 0.0, "Unbekannte Kamera liefert 0.")
	_near(CameraDefs.base("drone", "gibt_es_nicht", 3), 0.0, "Unbekannter Schlüssel liefert 0.")
	_check(not CameraDefs.has("gibt_es_nicht") and CameraDefs.display_name("gibt_es_nicht") == "gibt_es_nicht", "Unbekannte Kamera: Name ist die ID.")
	_check(CameraDefs.is_mod("cam_lens") and CameraDefs.is_mod("cam_uplink") and not CameraDefs.is_mod("drone") and not CameraDefs.is_mod("luck"), "is_mod kennt genau die Kamera-Gegenstände.")
	_near(CameraDefs.SLOW_DURATION, 2.0, "Zeitlupe hält 2 s.")
	_near(CameraDefs.MARK_DURATION, 4.0, "Die Markierung hält 4 s.")
	_near(CameraDefs.FLASH_CONE_DEG, 90.0, "Der Blitz hat 90 Grad.")
	_near(CameraDefs.SECOND_FLASH_DELAY, 0.4, "Der zweite Blitz kommt 0,4 s später.")
	# Die Kameradrohne ist kein Upgrade mehr.
	_check(not UpgradeDefs.has("drone") and not UpgradeDefs.ORDER.has("drone"), "Die Kameradrohne steht nicht mehr in UpgradeDefs.")
	for mod: String in CameraDefs.MOD_ORDER:
		_check(UpgradeDefs.has(mod) and UpgradeDefs.ITEM_ONLY.has(mod), "Der Kamera-Gegenstand %s hat seine Werte in UpgradeDefs." % mod)


func _test_stats() -> void:
	# Ohne Gegenstände: die Grundwerte der Rarität.
	for id: String in CameraDefs.ORDER:
		for level: int in range(1, 6):
			var plain: Dictionary = CameraDefs.stats(id, level)
			_check(str(plain["id"]) == id and int(plain["level"]) == level, "%s Rarität %d: Eintrag nennt Typ und Rarität." % [id, level])
			_near(float(plain["damage"]), CameraDefs.base(id, "damage", level), "%s Rarität %d: Schaden ohne Gegenstände." % [id, level])
			_near(float(plain["interval"]), CameraDefs.base(id, "interval", level), "%s Rarität %d: Abstand ohne Gegenstände." % [id, level])
			_near(float(plain["range"]), CameraDefs.base(id, "range", level), "%s Rarität %d: Reichweite ohne Gegenstände." % [id, level])
			_check(int(plain["pierce"]) == int(CameraDefs.base(id, "pierce", level)), "%s Rarität %d: Durchschlag." % [id, level])
			_near(float(plain["slow"]), CameraDefs.base(id, "slow", level), "%s Rarität %d: Verlangsamung." % [id, level])
			_near(float(plain["mark"]), CameraDefs.base(id, "mark", level), "%s Rarität %d: Markierung." % [id, level])
			_near(float(plain["second"]), 0.0, "%s Rarität %d: ohne Zweitkamera kein zweites Ziel." % [id, level])
			_near(float(plain["damage_bonus"]) + float(plain["rate_bonus"]) + float(plain["range_bonus"]), 0.0, "%s Rarität %d: keine Zuschläge." % [id, level])
	var keys: Array[String] = ["id", "level", "damage", "interval", "range", "pierce", "slow", "slow_duration", "mark", "mark_duration", "second", "cone_deg", "damage_bonus", "rate_bonus", "range_bonus"]
	var entry: Dictionary = CameraDefs.stats("drone", 1)
	_check(entry.size() == keys.size(), "Ein Eintrag hat genau %d Schlüssel, waren %d." % [keys.size(), entry.size()])
	for key: String in keys:
		_check(entry.has(key), "Der Eintrag hat den Schlüssel %s." % key)
	_near(float(entry["slow_duration"]), 2.0, "Der Eintrag nennt die Dauer der Zeitlupe.")
	_near(float(entry["mark_duration"]), 4.0, "Der Eintrag nennt die Dauer der Markierung.")
	_near(float(CameraDefs.stats("cam_flash", 1)["cone_deg"]), 90.0, "Nur die Blitzlicht-Kamera hat einen Kegel.")
	_near(float(entry["cone_deg"]), 0.0, "Die Drohne hat keinen Kegel.")
	_near(float(CameraDefs.stats("cam_director", 5)["damage"]), 0.0, "Die Regie-Kamera macht keinen Schaden.")
	_near(float(CameraDefs.stats("cam_director", 5)["mark"]), 0.5, "Legendär markiert sie mit 50 %.")
	_check(int(CameraDefs.stats("cam_tele", 5)["pierce"]) == 3, "Die legendäre Tele-Kamera geht durch 3 weitere Zombies.")
	_check(CameraDefs.stats("gibt_es_nicht", 3).is_empty(), "Unbekannte Kamera: leerer Eintrag.")
	_check(int(CameraDefs.stats("drone", 0)["level"]) == 1 and int(CameraDefs.stats("drone", 99)["level"]) == 5, "Die Rarität wird auf 1 bis 5 begrenzt.")
	# Objektiv: mehr Schaden, sonst nichts.
	var lens: Dictionary = CameraDefs.stats("drone", 1, {"cam_lens": [1]})
	_near(float(lens["damage"]), 15.0 * 1.2, "Gewöhnliches Objektiv: +20 % Schaden.")
	_near(float(lens["interval"]), 1.2, "Das Objektiv ändert den Abstand nicht.")
	_near(float(lens["range"]), 15.0, "Das Objektiv ändert die Reichweite nicht.")
	_near(float(CameraDefs.stats("drone", 5, {"cam_lens": [5]})["damage"]), 46.0 * 1.7, "Legendäres Objektiv auf legendärer Drohne: 46 mal 1,7.")
	_near(float(CameraDefs.stats("drone", 1, {"cam_lens": [1, 3]})["damage"]), 15.0 * 1.6, "Zwei Objektive addieren sich: +20 % und +40 %.")
	# Zoom: mehr Reichweite.
	var zoom: Dictionary = CameraDefs.stats("cam_tele", 2, {"cam_zoom": [4]})
	_near(float(zoom["range"]), 30.0 * 1.5, "Epischer Zoom: +50 % Reichweite.")
	_near(float(zoom["damage"]), 100.0, "Der Zoom ändert den Schaden nicht.")
	_near(float(zoom["range_bonus"]), 0.5, "Der Eintrag nennt den Zuschlag auf die Reichweite.")
	# Akkupack: Abstand durch 1 + Bonus.
	var battery: Dictionary = CameraDefs.stats("drone", 1, {"cam_battery": [5]})
	_near(float(battery["interval"]), 1.2 / 1.6, "Legendärer Akkupack: Abstand durch 1,6.")
	_near(float(battery["damage"]), 15.0, "Der Akkupack ändert den Schaden nicht.")
	_near(float(CameraDefs.stats("drone", 1, {"cam_battery": [1, 1]})["interval"]), 1.2 / 1.3, "Zwei Akkupacks addieren sich: Abstand durch 1,3.")
	# Zweitkamera: Anteil fürs zweite Ziel.
	_near(float(CameraDefs.stats("cam_flash", 3, {"cam_second": [1]})["second"]), 0.4, "Gewöhnliche Zweitkamera: 40 %.")
	_near(float(CameraDefs.stats("cam_flash", 3, {"cam_second": [5]})["second"]), 1.0, "Legendäre Zweitkamera: 100 %.")
	_near(float(CameraDefs.stats("cam_flash", 3, {"cam_second": [1, 2]})["second"]), 0.95, "Zwei Zweitkameras addieren ihre Anteile.")
	# Sendeleitung: alle Kameras mehr Schaden und schnellere Schussfolge.
	var uplink: Dictionary = CameraDefs.stats("drone", 1, {}, [1])
	_near(float(uplink["damage"]), 15.0 * 1.08, "Gewöhnliche Sendeleitung: +8 % Schaden.")
	_near(float(uplink["interval"]), 1.2 / 1.08, "Gewöhnliche Sendeleitung: Abstand durch 1,08.")
	_near(float(uplink["range"]), 15.0, "Die Sendeleitung ändert die Reichweite nicht.")
	_near(float(CameraDefs.stats("drone", 1, {}, [5, 5])["damage"]), 15.0 * 1.5, "Zwei legendäre Sendeleitungen: +50 % Schaden.")
	# Alles zusammen: Zuschläge derselben Art addieren sich.
	var full: Dictionary = CameraDefs.stats("cam_slow", 4, {"cam_lens": [2], "cam_zoom": [1], "cam_battery": [3], "cam_second": [2]}, [2])
	_near(float(full["damage"]), 10.0 * (1.0 + 0.3 + 0.12), "Objektiv und Sendeleitung addieren sich beim Schaden.")
	_near(float(full["interval"]), 1.2 / (1.0 + 0.35 + 0.12), "Akkupack und Sendeleitung addieren sich bei der Schussfolge.")
	_near(float(full["range"]), 12.0 * 1.2, "Zoom wirkt auf die Reichweite.")
	_near(float(full["second"]), 0.55, "Zweitkamera Ungewöhnlich: 55 %.")
	_near(float(full["slow"]), 0.45, "Die Verlangsamung bleibt der Wert der Rarität.")
	_near(float(full["damage_bonus"]), 0.42, "Der Eintrag nennt den Zuschlag auf den Schaden.")
	_near(float(full["rate_bonus"]), 0.47, "Der Eintrag nennt den Zuschlag auf die Schussfolge.")
	# Fremde Einträge stören nicht, der Abstand wird nie kleiner als die Untergrenze.
	_near(float(CameraDefs.stats("drone", 1, {"luck": [5], "cam_lens": []})["damage"]), 15.0, "Fremde oder leere Einträge ändern nichts.")
	var battery_many: Array = []
	for _i: int in 200:
		battery_many.append(5)
	_near(float(CameraDefs.stats("drone", 5, {"cam_battery": battery_many})["interval"]), CameraDefs.MIN_INTERVAL, "Der Abstand fällt nie unter die Untergrenze.")
	# Die Funktion ändert ihre Eingaben nicht.
	var mods: Dictionary = {"cam_lens": [1]}
	CameraDefs.stats("drone", 1, mods, [1])
	_check(mods == {"cam_lens": [1]}, "stats ändert die übergebenen Gegenstände nicht.")


func _test_texts() -> void:
	for id: String in CameraDefs.ORDER:
		for level: int in range(1, 6):
			var text: String = CameraDefs.effect_text(id, level)
			_check(text.length() > 20 and not text.contains("{") and not text.contains("}"), "%s Rarität %d hat einen Text ohne offene Platzhalter: %s" % [id, level, text])
			_check(text.length() <= 220, "%s Rarität %d: Text passt auf eine Karte (%d Zeichen)." % [id, level, text.length()])
	var drone: String = CameraDefs.effect_text("drone", 4)
	_check(drone.contains("0,65 s") and drone.contains("36") and drone.contains("15 m"), "Drohne Episch nennt 0,65 s, 36 und 15 m: %s" % drone)
	_check(not drone.contains("teilen"), "Der Text spricht nicht mehr vom Teilen der Kraft.")
	var tele: String = CameraDefs.effect_text("cam_tele", 5)
	_check(tele.contains("220") and tele.contains("30 m") and tele.contains("Durchschlag 3"), "Tele Legendär nennt 220, 30 m und Durchschlag 3: %s" % tele)
	var flash: String = CameraDefs.effect_text("cam_flash", 1)
	_check(flash.contains("90 Grad") and flash.contains("7 m") and flash.contains("18"), "Blitzlicht Gewöhnlich nennt 90 Grad, 7 m und 18: %s" % flash)
	var slow: String = CameraDefs.effect_text("cam_slow", 3)
	_check(slow.contains("40 %") and slow.contains("2 s") and slow.contains("12 m"), "Zeitlupe Selten nennt 40 %%, 2 s und 12 m: %s" % slow)
	var director: String = CameraDefs.effect_text("cam_director", 2)
	_check(director.contains("25 %") and director.contains("4 s") and director.contains("18 m"), "Regie Ungewöhnlich nennt 25 %%, 4 s und 18 m: %s" % director)
	_check(CameraDefs.effect_text("gibt_es_nicht", 1) == "", "Unbekannte Kamera hat keinen Text.")


# --- ItemDefs -------------------------------------------------------------------------

func _test_items() -> void:
	var shapes: Dictionary = {}
	for id: String in CameraDefs.ORDER:
		_check(ItemDefs.is_camera(id) and ItemDefs.kind(id) == ItemDefs.KIND_CAMERA, "%s ist ein Gegenstand der Art Kamera." % id)
		_check(not ItemDefs.is_upgrade(id) and not ItemDefs.is_weapon(id) and not ItemDefs.is_booster(id), "%s ist nichts anderes." % id)
		# Jede Kamera hat ihre eigene Form (auch gedreht keine doppelt).
		for rot: int in 4:
			var key: String = str(ItemDefs.cells(id, rot))
			_check(not shapes.has(key) or str(shapes[key]) == id, "%s hat eine andere Form als %s." % [id, str(shapes.get(key, ""))])
			shapes[key] = id
	_check(ItemDefs.cell_count("drone") == 2 and ItemDefs.cell_count("cam_slow") == 1 and ItemDefs.cell_count("cam_tele") == 3 and ItemDefs.cell_count("cam_director") == 3 and ItemDefs.cell_count("cam_flash") == 4, "Felder: Drohne 2, Zeitlupe 1, Tele 3, Regie 3, Blitzlicht 4.")
	_check(not ItemDefs.is_camera("luck") and not ItemDefs.is_camera("cam_lens") and not ItemDefs.is_camera("gibt_es_nicht"), "Alles andere ist keine Kamera.")
	# Kamera-Gegenstände: Art Upgrade, vier mit Sternen auf Kameras, die Sendeleitung ohne.
	for mod: String in ["cam_lens", "cam_zoom", "cam_battery", "cam_second"]:
		_check(ItemDefs.is_upgrade(mod) and ItemDefs.is_camera_mod(mod) and ItemDefs.star_target(mod) == ItemDefs.STAR_CAMERA, "%s zielt mit seinen Sternen auf Kameras." % mod)
		_check(not ItemDefs.is_weapon_mod(mod), "%s ist kein Kugel-Effekt." % mod)
		_check(ItemDefs.star_hits(mod, "drone") and ItemDefs.star_hits(mod, "cam_director"), "%s trifft Kameras." % mod)
		_check(not ItemDefs.star_hits(mod, "pistol") and not ItemDefs.star_hits(mod, "luck") and not ItemDefs.star_hits(mod, "cam_lens"), "%s trifft weder Waffen noch andere Gegenstände." % mod)
	_check(ItemDefs.is_upgrade("cam_uplink") and not ItemDefs.has_stars("cam_uplink") and not ItemDefs.is_camera_mod("cam_uplink"), "Die Sendeleitung hat keine Sterne.")
	_check(not ItemDefs.star_hits("pierce", "drone") and not ItemDefs.star_hits("spotlight", "drone"), "Waffen-Sterne treffen keine Kamera.")
	_check(not ItemDefs.is_weapon_mod("drone") and not ItemDefs.is_camera_mod("drone") and not ItemDefs.is_camera_mod("pierce"), "Kameras und Kugel-Effekte sind keine Kamera-Gegenstände.")
	# Sternmuster (ungedreht).
	_check(ItemDefs.stars("cam_lens", 0) == ([Vector2i(-1, 0), Vector2i(1, 0)] as Array[Vector2i]), "Objektiv: links und rechts.")
	_check(ItemDefs.stars("cam_zoom", 0) == ([Vector2i(1, 0), Vector2i(1, 1)] as Array[Vector2i]) and ItemDefs.cell_count("cam_zoom") == 2, "Zoom: zwei Felder senkrecht, Sterne rechts daneben.")
	_check(ItemDefs.stars("cam_battery", 0) == ([Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)] as Array[Vector2i]), "Akkupack: links, rechts und unten.")
	_check(ItemDefs.stars("cam_second", 0) == ([Vector2i(2, 0)] as Array[Vector2i]) and ItemDefs.cell_count("cam_second") == 2, "Zweitkamera: zwei Felder waagerecht, ein Stern davor.")
	_check(ItemDefs.cell_count("cam_uplink") == 3, "Sendeleitung: L aus drei Feldern.")


# --- BackpackState --------------------------------------------------------------------

func _test_backpack_cameras() -> void:
	var backpack: BackpackState = _grid(7, 5)
	_check(backpack.cameras().is_empty(), "Ohne Kamera ist die Liste leer.")
	var drone: int = backpack.add_item("drone", 3)
	_check(backpack.cameras().is_empty(), "Eine Kamera in der Ablage zählt nicht.")
	_check(backpack.place(drone, Vector2i(2, 2), 0), "Die Drohne liegt auf (2, 2) und (3, 2).")
	var list: Array[Dictionary] = backpack.cameras()
	_check(list.size() == 1, "Eine eingeräumte Kamera ergibt einen Eintrag.")
	_check(list[0] == {"key": "%d:0" % drone, "uid": drone, "copy": 0, "id": "drone", "level": 3, "mods": {}}, "Der Eintrag nennt Schlüssel, uid, Exemplar, Typ, Rarität und Gegenstände, war %s." % str(list[0]))
	_check(backpack.is_active(drone) and backpack.hands_used() == 0, "Eine Kamera wirkt immer und braucht keine Hand.")
	_check(backpack.upgrade_levels().is_empty() and backpack.global_copies().is_empty(), "Kameras stehen nicht unter den Upgrades.")
	_check(backpack.copy_levels(drone) == ([3] as Array[int]), "copy_levels gilt auch für Kameras.")
	# Objektiv rechts daneben: Sein linker Stern liegt auf der Drohne.
	var lens: int = _put(backpack, "cam_lens", 2, Vector2i(4, 2))
	_check(backpack.star_targets(lens) == ([drone] as Array[int]) and backpack.is_star_lit(lens, Vector2i(3, 2)) and not backpack.is_star_lit(lens, Vector2i(5, 2)), "Der Stern des Objektivs trifft die Drohne.")
	_check(backpack.is_active(lens) and backpack.mods_of(drone) == ([lens] as Array[int]), "Das Objektiv wirkt auf die Drohne.")
	_check(backpack.cameras()[0]["mods"] == {"cam_lens": [2]}, "Der Eintrag nennt das Objektiv mit seiner Rarität.")
	_check(backpack.upgrade_levels() == {"cam_lens": 2}, "Ein wirkender Kamera-Gegenstand steht in der Übersicht.")
	_check(backpack.global_copies().is_empty(), "Er gilt aber nicht für den Spieler als Ganzes.")
	# Abseits wirkt ein Kamera-Gegenstand nicht.
	var lonely: int = _put(backpack, "cam_lens", 5, Vector2i(6, 4))
	_check(not backpack.is_active(lonely) and backpack.cameras()[0]["mods"] == {"cam_lens": [2]}, "Ein Objektiv ohne Kamera auf dem Stern wirkt nicht.")
	# Zoom links daneben (Sterne rechts von beiden Feldern), Akkupack darüber (Stern unten).
	_put(backpack, "cam_zoom", 1, Vector2i(1, 2))
	_put(backpack, "cam_battery", 4, Vector2i(2, 1))
	# Zweitkamera darunter: hochkant gedreht, ihr Stern zeigt nach oben auf die Drohne.
	var second: int = backpack.add_item("cam_second", 5)
	var second_placed: bool = false
	for rot: int in 4:
		for y: int in BackpackState.ROWS:
			for x: int in BackpackState.COLS:
				if not second_placed and backpack.can_place(second, Vector2i(x, y), rot) and BackpackState.stars_at("cam_second", Vector2i(x, y), rot).has(Vector2i(3, 2)):
					second_placed = backpack.place(second, Vector2i(x, y), rot)
	_check(second_placed and backpack.star_targets(second) == ([drone] as Array[int]), "Die Zweitkamera lässt sich so legen, dass ihr Stern die Drohne trifft.")
	_check(backpack.cameras()[0]["mods"] == {"cam_lens": [2], "cam_zoom": [1], "cam_battery": [4], "cam_second": [5]}, "Alle vier Gegenstände stehen im Eintrag, war %s." % str(backpack.cameras()[0]["mods"]))
	# Zwei gleiche Gegenstände auf derselben Kamera: beide zählen.
	_put(backpack, "cam_battery", 1, Vector2i(2, 3), 2)
	_check((backpack.cameras()[0]["mods"] as Dictionary)["cam_battery"] == [4, 1], "Zwei Akkupacks auf derselben Kamera zählen beide.")
	# Sendeleitung: ohne Sterne, steht bei den allgemeinen Gegenständen.
	var uplink: int = _put(backpack, "cam_uplink", 3, Vector2i(5, 0))
	_check(backpack.is_active(uplink) and backpack.global_copies() == {"cam_uplink": [3]}, "Die Sendeleitung wirkt immer und steht in global_copies.")
	_check(not (backpack.cameras()[0]["mods"] as Dictionary).has("cam_uplink"), "Im Eintrag der Kamera steht sie nicht.")
	# Ein Objektiv zwischen zwei Kameras wirkt auf beide. Reihenfolge: wie erworben.
	var pair: BackpackState = _grid(7, 5)
	var slow: int = _put(pair, "cam_slow", 1, Vector2i(4, 0))
	var first: int = _put(pair, "drone", 2, Vector2i(0, 0))
	var between: int = _put(pair, "cam_lens", 3, Vector2i(3, 0))
	var second_drone: int = _put(pair, "drone", 5, Vector2i(0, 2))
	_check(pair.star_targets(between) == ([slow] as Array[int]), "Das Objektiv trifft nur die Zeitlupen-Kamera rechts daneben: Die Drohne liegt ein Feld zu weit links.")
	list = pair.cameras()
	_check(list.size() == 3 and int(list[0]["uid"]) == slow and int(list[1]["uid"]) == first and int(list[2]["uid"]) == second_drone, "Die Kameras stehen in der Reihenfolge des Erwerbs.")
	_check(list[0]["mods"] == {"cam_lens": [3]}, "Das Objektiv wirkt auf die Zeitlupen-Kamera rechts daneben.")
	_check((list[1]["mods"] as Dictionary).is_empty() and (list[2]["mods"] as Dictionary).is_empty(), "Auf die beiden Drohnen wirkt es nicht.")
	pair.place(first, Vector2i(1, 0), 0)
	list = pair.cameras()
	_check(list[0]["mods"] == {"cam_lens": [3]} and list[1]["mods"] == {"cam_lens": [3]}, "Zwischen zwei Kameras wirkt ein Objektiv auf beide.")
	var keys: Dictionary = {}
	for entry: Dictionary in list:
		keys[str(entry["key"])] = true
	_check(keys.size() == 3, "Jeder Eintrag hat seinen eigenen Schlüssel.")
	# Kameras und Waffen stören einander nicht: Ein Kugel-Effekt neben einer Kamera wirkt nicht,
	# ein Kamera-Gegenstand neben einer Waffe auch nicht.
	var mixed: BackpackState = _grid(7, 5)
	var pistol: int = _put(mixed, "pistol", 1, Vector2i(2, 2))
	var cam: int = _put(mixed, "drone", 1, Vector2i(2, 0))
	var pierce: int = _put(mixed, "pierce", 1, Vector2i(2, 1))
	var lens_on_gun: int = _put(mixed, "cam_lens", 1, Vector2i(4, 2))
	_check(mixed.star_targets(pierce).is_empty() and not mixed.is_active(pierce), "Die Sterne der Spezialmunition liegen auf der Kamera: Sie wirkt nicht.")
	_check(mixed.star_targets(lens_on_gun).is_empty() and not mixed.is_active(lens_on_gun), "Der Stern des Objektivs liegt auf der Pistole: Es wirkt nicht.")
	_check((mixed.loadout()[0]["copies"] as Dictionary).is_empty() and (mixed.cameras()[0]["mods"] as Dictionary).is_empty(), "Weder die Waffe noch die Kamera bekommt etwas ab.")
	_check(mixed.mods_of(pistol).is_empty() and mixed.mods_of(cam).is_empty(), "mods_of nennt für beide nichts.")
	# Zwei gleiche Kameras lassen sich kombinieren.
	var merge: BackpackState = _grid(4, 3)
	var cam_a: int = _put(merge, "drone", 1, Vector2i(0, 0))
	var cam_b: int = merge.add_item("drone", 1)
	_check(merge.find_merge_partner(cam_b) == cam_a and merge.merge(cam_b, cam_a) and int(merge.cameras()[0]["level"]) == 2, "Zwei gewöhnliche Drohnen werden eine ungewöhnliche.")


func _test_backpack_replay() -> void:
	# Wiederholung auf einer Kamera: ein zweites Exemplar, höchstens in der Rarität der Wiederholung.
	var backpack: BackpackState = _grid(7, 5)
	var drone: int = _put(backpack, "drone", 5, Vector2i(2, 2))
	var lens: int = _put(backpack, "cam_lens", 2, Vector2i(4, 2))
	var replay: int = _put(backpack, "replay", 3, Vector2i(1, 2))
	_check(backpack.star_targets(replay) == ([drone] as Array[int]) and backpack.is_active(replay), "Der Stern der Wiederholung trifft die Drohne.")
	_check(backpack.copy_levels(drone) == ([5, 3] as Array[int]), "Die Drohne zählt zweimal: Legendär und Selten.")
	var list: Array[Dictionary] = backpack.cameras()
	_check(list.size() == 2, "Eine Wiederholung auf der Kamera ergibt ein zweites Exemplar.")
	_check(str(list[0]["key"]) == "%d:0" % drone and str(list[1]["key"]) == "%d:1" % drone, "Die Schlüssel unterscheiden die Exemplare.")
	_check(int(list[0]["level"]) == 5 and int(list[1]["level"]) == 3 and int(list[1]["copy"]) == 1 and int(list[1]["uid"]) == drone, "Das zweite Exemplar hat die gedeckelte Rarität.")
	_check(list[0]["mods"] == {"cam_lens": [2]} and list[1]["mods"] == {"cam_lens": [2]}, "Beide Exemplare haben das Objektiv.")
	# Die Wiederholung ist kein Kamera-Gegenstand: Sie steht nicht unter den mods.
	_check(backpack.mods_of(drone).has(replay) and not (list[0]["mods"] as Dictionary).has("replay"), "Die Wiederholung selbst steht nicht im Eintrag.")
	# Wiederholung auf einem Kamera-Gegenstand: Er zählt doppelt.
	var lens_replay: int = backpack.add_item("replay", 1)
	_check(backpack.place(lens_replay, Vector2i(5, 2), 2), "Eine zweite Wiederholung rechts vom Objektiv (halbe Drehung: Stern nach links).")
	_check(backpack.star_targets(lens_replay) == ([lens] as Array[int]), "Ihr Stern trifft das Objektiv.")
	_check(backpack.copy_levels(lens) == ([2, 1] as Array[int]), "Das Objektiv zählt doppelt, das zweite Mal höchstens Gewöhnlich.")
	list = backpack.cameras()
	_check(list[0]["mods"] == {"cam_lens": [2, 1]} and list[1]["mods"] == {"cam_lens": [2, 1]}, "Beide Exemplare der Kamera bekommen das Objektiv doppelt.")
	# Die Einträge teilen sich keine Listen: Ändern eines Eintrags ändert den anderen nicht.
	((list[0]["mods"] as Dictionary)["cam_lens"] as Array).append(9)
	_check((list[1]["mods"] as Dictionary)["cam_lens"] == [2, 1], "Jeder Eintrag hat seine eigene Kopie der Gegenstände.")
	# Wiederholung auf der Sendeleitung: Sie zählt in global_copies doppelt.
	var uplink: int = _put(backpack, "cam_uplink", 4, Vector2i(1, 3))
	var uplink_replay: int = _put(backpack, "replay", 2, Vector2i(0, 3))
	_check(backpack.star_targets(uplink_replay) == ([uplink] as Array[int]) and backpack.global_copies() == {"cam_uplink": [4, 2]}, "Die Sendeleitung zählt mit Wiederholung doppelt.")
	# Aus dem Rucksack genommen zählt die Kamera nicht mehr, die Wiederholung wirkt dann auf nichts.
	backpack.store(drone)
	_check(backpack.cameras().is_empty() and not backpack.is_active(replay) and not backpack.is_active(lens), "Ohne die Kamera wirken Wiederholung und Objektiv nicht.")


# --- Game -----------------------------------------------------------------------------

func _test_game_cameras() -> void:
	_game.set("character_id", "")
	_game.set("auto_pack", false)
	_game.call("start_run", 21)
	_camera_changes = 0
	_build_changes = 0
	_chosen.clear()
	var backpack: BackpackState = _game.get("backpack") as BackpackState
	_check((_game.get("cameras") as Array).is_empty(), "Ein neuer Lauf ohne Kandidat hat keine Kamera.")
	# Der Rucksack ohne Kandidat hat die Felder (1, 1) bis (4, 3).
	_game.call("open_backpack")
	var drone: int = _put(backpack, "drone", 2, Vector2i(2, 2))
	var before: Array = _game.get("cameras")
	_game.call("sync_build")
	var cameras: Array = _game.get("cameras")
	_check(cameras.size() == 1 and not is_same(cameras, before), "sync_build baut Game.cameras neu.")
	_check(_camera_changes == 1 and _build_changes == 1, "cameras_changed und build_changed kamen je einmal.")
	var entry: Dictionary = cameras[0]
	_check(str(entry["id"]) == "drone" and int(entry["level"]) == 2 and int(entry["uid"]) == drone and str(entry["key"]) == "%d:0" % drone and int(entry["copy"]) == 0, "Der Eintrag nennt Typ, Rarität, uid, Schlüssel und Exemplar.")
	_near(float(entry["damage"]), 21.0, "Ungewöhnliche Drohne: fester Schaden 21.")
	_near(float(entry["interval"]), 1.0, "Ungewöhnliche Drohne: Abstand 1,0 s.")
	_near(float(entry["range"]), 15.0, "Reichweite 15 m.")
	_check((entry["mods"] as Dictionary).is_empty(), "Ohne Kamera-Gegenstände ist mods leer.")
	for key: String in ["key", "uid", "copy", "id", "level", "mods", "damage", "interval", "range", "pierce", "slow", "slow_duration", "mark", "mark_duration", "second", "cone_deg", "damage_bonus", "rate_bonus", "range_bonus"]:
		_check(entry.has(key), "Der Eintrag in Game.cameras hat den Schlüssel %s." % key)
	_check(entry.size() == 19, "Der Eintrag hat genau 19 Schlüssel, waren %d." % entry.size())
	# Die Welle ändert nichts: feste Werte, kein Effekt-Faktor.
	_events.emit_signal("wave_started", 30, 100)
	_check(float(_game.call("effect_factor")) > 2.0, "In Welle 30 ist der Effekt-Faktor groß.")
	_game.call("sync_build")
	_near(float((_game.get("cameras") as Array)[0]["damage"]), 21.0, "Der Schaden der Kamera wächst nicht mit der Welle.")
	# Ohne Änderung bleibt das Array dasselbe und es kommt kein cameras_changed.
	_check(is_same(_game.get("cameras"), cameras) and _camera_changes == 1 and _build_changes == 2, "Ohne Änderung bleibt Game.cameras dasselbe Array, nur build_changed kommt.")
	# Die Kamera ist kein Upgrade.
	var upgrades: RefCounted = _game.get("upgrades")
	_check(int(upgrades.call("get_level", "drone")) == 0 and (upgrades.call("copies", "drone") as Array).is_empty(), "Game.upgrades kennt die Kameradrohne nicht mehr.")
	_check(_game.call("camera_levels") == {"drone": 2}, "camera_levels nennt die beste Rarität je Typ.")
	_check((_game.call("cameras_of", "drone") as Array).size() == 1 and (_game.call("cameras_of", "cam_tele") as Array).is_empty(), "cameras_of filtert nach Typ.")
	_check(_game.call("camera_entry", "%d:0" % drone) == entry and (_game.call("camera_entry", "gibt_es_nicht") as Dictionary).is_empty(), "camera_entry findet den Eintrag über den Schlüssel.")
	# Objektiv und Sendeleitung.
	_put(backpack, "cam_lens", 1, Vector2i(4, 2))
	_put(backpack, "cam_uplink", 5, Vector2i(1, 1), 0)
	_game.call("sync_build")
	entry = (_game.get("cameras") as Array)[0]
	_check(_camera_changes == 2, "Ein neuer Kamera-Gegenstand sendet cameras_changed.")
	_near(float(entry["damage"]), 21.0 * (1.0 + 0.2 + 0.25), "Objektiv (+20 %) und legendäre Sendeleitung (+25 %) addieren sich.")
	_near(float(entry["interval"]), 1.0 / 1.25, "Die Sendeleitung verkürzt den Abstand.")
	_check(entry["mods"] == {"cam_lens": [1]}, "mods nennt das Objektiv.")
	_check((upgrades.call("copies", "cam_uplink") as Array) == [5], "Die Sendeleitung steht in Game.upgrades.copies.")
	# Eine zweite Kamera: zwei Einträge, die Sendeleitung wirkt auf beide.
	_put(backpack, "cam_slow", 3, Vector2i(3, 1))
	_game.call("sync_build")
	cameras = _game.get("cameras")
	_check(cameras.size() == 2 and str((cameras[1] as Dictionary)["id"]) == "cam_slow", "Die Zeitlupen-Kamera kommt als zweiter Eintrag dazu.")
	_near(float((cameras[1] as Dictionary)["damage"]), 8.0 * 1.25, "Die Sendeleitung wirkt auch auf die zweite Kamera.")
	_near(float((cameras[1] as Dictionary)["slow"]), 0.40, "Sie verlangsamt mit dem Wert ihrer Rarität.")
	_check(_game.call("camera_levels") == {"drone": 2, "cam_slow": 3}, "camera_levels nennt beide Typen.")
	# Beim Schließen meldet upgrade_chosen auch die neuen Kameras.
	_check(_chosen.is_empty(), "Meldungen kommen erst beim Schließen.")
	_check(bool(_game.call("close_backpack")), "Der Rucksack lässt sich schließen.")
	_check(_chosen.has("drone") and _chosen.has("cam_slow") and _chosen.has("cam_lens") and _chosen.has("cam_uplink"), "upgrade_chosen kam für Kameras und Kamera-Gegenstände, war %s." % str(_chosen))
	# Statistik.
	var stats: Dictionary = _game.call("get_stats")
	_check(stats["cameras"] == [{"id": "drone", "name": "Kameradrohne", "level": 2}, {"id": "cam_slow", "name": "Zeitlupen-Kamera", "level": 3}], "Die Statistik nennt die Kameras, war %s." % str(stats["cameras"]))
	# Verkaufen nimmt die Kamera weg.
	var points: int = int(_game.get("points"))
	_check(int(_game.call("sell_item", drone)) == ItemDefs.sell_value("drone", 2) and int(_game.get("points")) == points + 200, "Eine ungewöhnliche Drohne bringt 200 Punkte.")
	_check((_game.get("cameras") as Array).size() == 1 and str(((_game.get("cameras") as Array)[0] as Dictionary)["id"]) == "cam_slow", "Nach dem Verkauf bleibt nur die Zeitlupen-Kamera.")
	# Kiste: Eine Kamera aus der Kiste räumt sich mit auto_pack ein.
	_game.set("auto_pack", true)
	_game.call("start_run", 22)
	_chosen.clear()
	_game.call("open_chest", 1)
	(_game.get("current_offers") as Array)[0] = {"kind": "item", "id": "cam_tele", "level": 2, "owned_level": 0}
	_game.call("choose_offer", 0)
	cameras = _game.get("cameras")
	_check(cameras.size() == 1 and str((cameras[0] as Dictionary)["id"]) == "cam_tele" and int((cameras[0] as Dictionary)["pierce"]) == 1, "Die Tele-Kamera aus der Kiste steht in Game.cameras.")
	_check(_chosen == (["cam_tele"] as Array[String]), "Für die neue Kamera kommt upgrade_chosen.")
	# Ein neuer Lauf beginnt ohne Kameras.
	_game.call("start_run", 23)
	_check((_game.get("cameras") as Array).is_empty(), "Ein neuer Lauf räumt Game.cameras ab.")
	_game.set("auto_pack", false)


func _near(value: float, expected: float, message: String) -> void:
	_check(absf(value - expected) < 0.0001, "%s (erwartet %s, war %s)" % [message, expected, value])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
