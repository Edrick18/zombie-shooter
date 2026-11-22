extends SceneTree
## Tests für Ausbau 4 (Abschnitt 26): Material, Wellen-Prämie, kaputte Fundstücke, Reparieren,
## Verschrotten und die Ablage ohne Grenze, alles über Game und Events.
##
## Ohne Bildschirm ist Game.broken_loot aus. Dieser Test schaltet es selbst ein und am Ende wieder
## aus.

const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")

const STATE_PLAYING: int = 1
const STATE_GAME_OVER: int = 4
const STATE_PACKING: int = 5

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
## Signale in der Reihenfolge des Eintreffens (nur die Namen).
var _log: Array[String] = []
## Je materials_changed ein Paar [total, delta].
var _material_events: Array[Array] = []
var _repaired: Array[int] = []
## Je item_scrapped ein Paar [uid, amount].
var _scrapped: Array[Array] = []
var _opened: Array[int] = []
var _points_events: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum.
	await process_frame
	_game = root.get_node("Game")
	_events = root.get_node("Events")
	_events.connect("materials_changed", func(total: int, delta: int) -> void:
		_log.append("materials_changed")
		_material_events.append([total, delta]))
	_events.connect("item_repaired", func(uid: int) -> void:
		_log.append("item_repaired")
		_repaired.append(uid))
	_events.connect("item_scrapped", func(uid: int, amount: int) -> void:
		_log.append("item_scrapped")
		_scrapped.append([uid, amount]))
	_events.connect("build_changed", func() -> void: _log.append("build_changed"))
	_events.connect("backpack_opened", func(uid: int) -> void: _opened.append(uid))
	_events.connect("points_changed", func(_total: int) -> void: _points_events += 1)

	_check(not bool(_game.get("broken_loot")), "Ohne Bildschirm ist broken_loot aus.")
	_game.set("character_id", "")
	_game.set("auto_pack", false)
	_game.set("broken_loot", true)

	_test_numbers()
	_test_start_and_wave_bonus()
	_test_repair_cost_and_scrap_value()
	_test_repair()
	_test_scrap()
	_test_broken_is_locked()
	_test_chest_choice()
	_test_grant_and_start_items()
	_test_unlimited_storage()
	_test_new_run_resets()

	paused = false
	_game.set("broken_loot", false)
	_game.set("auto_pack", false)
	_game.set("character_id", "")
	if _failures == 0:
		print("Alle Material-Tests bestanden (%d Prüfungen)." % _checks)
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


func _state() -> int:
	return int(_game.get("state"))


func _materials() -> int:
	return int(_game.get("materials"))


func _backpack() -> BackpackState:
	return _game.get("backpack") as BackpackState


func _upgrades() -> UpgradeState:
	return _game.get("upgrades") as UpgradeState


func _reset_log() -> void:
	_log.clear()
	_material_events.clear()
	_repaired.clear()
	_scrapped.clear()
	_opened.clear()
	_points_events = 0


## Öffnet eine Kiste und nimmt genau diesen Gegenstand daraus (er liegt als erstes Angebot drin).
func _choose_from_chest(id: String, level: int) -> void:
	_game.call("open_chest", Balance.RARITY_BRONZE)
	var offers: Array = _game.get("current_offers")
	offers[0] = {"kind": "item", "id": id, "level": level, "owned_level": 0}
	_game.call("choose_offer", 0)


# --- Zahlen aus Abschnitt 26.1 ----------------------------------------------------------

func _test_numbers() -> void:
	_check(Balance.MATERIAL_START == 3, "Ein Lauf beginnt mit 3 Material.")
	_check(Balance.MATERIAL_PER_WAVE == 2, "Jede geschaffte Welle gibt 2 Material.")
	_check(Balance.REPAIR_COST == ([1, 2, 3, 4, 5] as Array[int]), "Reparieren kostet 1, 2, 3, 4, 5 nach Rarität.")
	_check(Balance.SCRAP_YIELD == ([1, 2, 3, 4, 6] as Array[int]), "Verschrotten gibt 1, 2, 3, 4, 6 nach Rarität.")
	_check(Balance.SCRAP_YIELD_BAG == 1, "Ein Rucksack-Teil gibt 1 Material.")
	_check(Balance.REPAIR_COST.size() == Balance.UPGRADE_MAX_LEVEL and Balance.SCRAP_YIELD.size() == Balance.UPGRADE_MAX_LEVEL, "Für jede Rarität gibt es einen Preis und einen Ertrag.")


# --- Start und Wellen-Prämie -------------------------------------------------------------

func _test_start_and_wave_bonus() -> void:
	_reset_log()
	_game.call("start_run", 1)
	_check(_materials() == 3, "Der Lauf beginnt mit 3 Material, waren %d." % _materials())
	_check(_material_events == ([[3, 0]] as Array[Array]), "start_run sendet materials_changed(3, 0), war %s." % str(_material_events))
	_check(int((_game.call("get_stats") as Dictionary)["materials"]) == 3, "get_stats nennt das Material.")
	# Gutschreiben.
	_reset_log()
	_game.call("add_materials", 4)
	_check(_materials() == 7 and _material_events == ([[7, 4]] as Array[Array]), "add_materials schreibt gut und meldet Stand und Änderung, war %s." % str(_material_events))
	_game.call("add_materials", 0)
	_game.call("add_materials", -5)
	_check(_materials() == 7 and _material_events.size() == 1, "0 oder weniger Material ändert nichts und meldet nichts.")
	# Wellen-Prämie.
	_game.call("start_run", 1)
	_reset_log()
	_events.emit_signal("wave_cleared", 1)
	_check(_materials() == 5 and _material_events == ([[5, 2]] as Array[Array]), "Eine geschaffte Welle gibt 2 Material, Stand %d, Meldung %s." % [_materials(), str(_material_events)])
	_events.emit_signal("wave_cleared", 2)
	_events.emit_signal("wave_cleared", 3)
	_check(_materials() == 9 and _material_events.size() == 3, "Jede Welle gibt ihre Prämie, Stand war %d." % _materials())
	_check(_points_events == 0, "Die Wellen-Prämie ändert die Punkte nicht.")
	# Auch bei offenem Rucksack zählt die Prämie, nach dem Ende des Laufs nicht mehr.
	_game.call("open_backpack")
	_events.emit_signal("wave_cleared", 4)
	_check(_materials() == 11, "Die Prämie kommt auch bei offenem Rucksack.")
	_game.call("close_backpack")
	_game.call("end_run")
	_check(_state() == STATE_GAME_OVER and int((_game.call("get_stats") as Dictionary)["materials"]) == 11, "Die Statistik am Ende nennt das Material.")
	_events.emit_signal("wave_cleared", 5)
	_check(_materials() == 11, "Nach dem Ende des Laufs gibt es keine Prämie mehr.")


# --- Preise und Erträge ------------------------------------------------------------------

func _test_repair_cost_and_scrap_value() -> void:
	_game.call("start_run", 2)
	var costs: Array[int] = [1, 2, 3, 4, 5]
	var yields: Array[int] = [1, 2, 3, 4, 6]
	for level: int in range(1, 6):
		var broken: int = _backpack().add_item("luck", level, true)
		var whole: int = _backpack().add_item("pistol", level)
		_check(int(_game.call("repair_cost", broken)) == costs[level - 1], "Reparatur in Rarität %d kostet %d, war %d." % [level, costs[level - 1], int(_game.call("repair_cost", broken))])
		_check(int(_game.call("repair_cost", whole)) == 0, "Ein heiler Gegenstand kostet keine Reparatur (Rarität %d)." % level)
		_check(int(_game.call("scrap_value", broken)) == yields[level - 1], "Ein kaputter Gegenstand der Rarität %d gibt %d Material, waren %d." % [level, yields[level - 1], int(_game.call("scrap_value", broken))])
		_check(int(_game.call("scrap_value", whole)) == yields[level - 1], "Ein heiler Gegenstand der Rarität %d gibt %d Material, waren %d." % [level, yields[level - 1], int(_game.call("scrap_value", whole))])
	var bag: int = _backpack().add_item("bag_small", 1, true)
	_check(int(_game.call("scrap_value", bag)) == 1, "Ein Rucksack-Teil gibt 1 Material.")
	_check(int(_game.call("repair_cost", bag)) == 0 and not bool(_game.call("can_repair", bag)), "Ein Rucksack-Teil ist nie kaputt und braucht keine Reparatur.")
	_check(int(_game.call("repair_cost", 99999)) == 0 and int(_game.call("scrap_value", 99999)) == 0 and not bool(_game.call("can_repair", 99999)), "Unbekannte uid: kein Preis, kein Ertrag, keine Reparatur.")


# --- Reparieren --------------------------------------------------------------------------

func _test_repair() -> void:
	_game.call("start_run", 3)
	_game.call("open_backpack")
	var legend: int = _backpack().add_item("luck", 5, true)
	_reset_log()
	# Zu wenig Material: 3 von 5.
	_check(not bool(_game.call("can_repair", legend)), "Mit 3 Material lässt sich ein Legendärer (5) nicht reparieren.")
	_check(not bool(_game.call("repair_item", legend)), "repair_item lehnt ohne genug Material ab.")
	_check(_materials() == 3 and _backpack().is_broken(legend) and _log.is_empty(), "Ohne genug Material ändert sich nichts und es kommt kein Signal, war %s." % str(_log))
	# Genau genug: 5 von 5.
	_game.call("add_materials", 2)
	_reset_log()
	_check(bool(_game.call("can_repair", legend)), "Mit genau 5 Material geht die Reparatur.")
	_check(bool(_game.call("repair_item", legend)), "repair_item repariert.")
	_check(_materials() == 0, "Die Reparatur kostet 5 Material, Stand war %d." % _materials())
	_check(not _backpack().is_broken(legend) and not bool(_backpack().item(legend)["broken"]), "Danach ist der Gegenstand heil.")
	_check(_backpack().has_item(legend) and not _backpack().is_placed(legend), "Er bleibt in der Ablage liegen.")
	_check(_material_events == ([[0, -5]] as Array[Array]), "materials_changed nennt Stand 0 und Änderung -5, war %s." % str(_material_events))
	_check(_repaired == ([legend] as Array[int]), "item_repaired nennt die uid, war %s." % str(_repaired))
	_check(_log == (["materials_changed", "item_repaired"] as Array[String]), "Reihenfolge: materials_changed, item_repaired, ohne build_changed, war %s." % str(_log))
	_check(int(_game.call("repair_cost", legend)) == 0 and not bool(_game.call("can_repair", legend)), "Ein reparierter Gegenstand kostet nichts mehr.")
	# Ein zweites Mal und Unbekanntes.
	_reset_log()
	_check(not bool(_game.call("repair_item", legend)) and not bool(_game.call("repair_item", 99999)) and _log.is_empty(), "Heile und unbekannte Gegenstände lassen sich nicht reparieren.")
	# Mehr als genug: Der Rest bleibt.
	_game.call("add_materials", 4)
	var common: int = _backpack().add_item("burn", 1, true)
	_reset_log()
	_check(bool(_game.call("repair_item", common)) and _materials() == 3, "Ein Gewöhnlicher kostet 1 Material, es bleiben 3, waren %d." % _materials())
	_check(_material_events == ([[3, -1]] as Array[Array]), "materials_changed(3, -1), war %s." % str(_material_events))
	_game.call("close_backpack")


# --- Verschrotten ------------------------------------------------------------------------

func _test_scrap() -> void:
	_game.call("start_run", 4)
	_game.call("open_backpack")
	var yields: Array[int] = [1, 2, 3, 4, 6]
	# Aus der Ablage, je Rarität, kaputt und heil.
	var expected: int = 3
	for level: int in range(1, 6):
		for broken: bool in [true, false]:
			var uid: int = _backpack().add_item("lifesteal", level, broken)
			_reset_log()
			var got: int = int(_game.call("scrap_item", uid))
			expected += yields[level - 1]
			_check(got == yields[level - 1], "Verschrotten in Rarität %d (kaputt %s) gibt %d Material, waren %d." % [level, str(broken), yields[level - 1], got])
			_check(not _backpack().has_item(uid), "Der verschrottete Gegenstand ist weg.")
			_check(_materials() == expected, "Das Material kommt dazu, Stand %d, erwartet %d." % [_materials(), expected])
			_check(_material_events == ([[expected, yields[level - 1]]] as Array[Array]), "materials_changed nennt Stand und Ertrag, war %s." % str(_material_events))
			_check(_scrapped == ([[uid, yields[level - 1]]] as Array[Array]), "item_scrapped nennt uid und Ertrag, war %s." % str(_scrapped))
			_check(_log == (["build_changed", "materials_changed", "item_scrapped"] as Array[String]), "Reihenfolge: build_changed, materials_changed, item_scrapped, war %s." % str(_log))
	# Rucksack-Teil.
	var bag: int = _backpack().add_item("bag_small")
	_reset_log()
	_check(int(_game.call("scrap_item", bag)) == 1 and not _backpack().has_item(bag), "Ein Rucksack-Teil gibt 1 Material und ist weg.")
	_check(_scrapped == ([[bag, 1]] as Array[Array]), "item_scrapped für das Rucksack-Teil, war %s." % str(_scrapped))
	expected += 1
	# Aus dem Raster: Der Build wird abgeglichen.
	var luck: int = _backpack().add_item("luck", 3)
	_check(_backpack().auto_place(luck), "Der Glücksbringer lässt sich einräumen.")
	var shotgun: int = _backpack().add_item("shotgun", 2)
	_check(_backpack().auto_place(shotgun), "Die Schrotflinte lässt sich einräumen.")
	_game.call("sync_build")
	_check(_upgrades().get_level("luck") == 3 and int(((_game.get("loadout") as Array)[0] as Dictionary)["uid"]) == shotgun, "Beide wirken.")
	var cells_before: int = _backpack().free_cell_count()
	_reset_log()
	var points_before: int = int(_game.get("points"))
	_check(int(_game.call("scrap_item", luck)) == 3, "Ein Seltener aus dem Raster gibt 3 Material.")
	expected += 3
	_check(not _backpack().has_item(luck) and _backpack().free_cell_count() > cells_before, "Er ist aus dem Raster verschwunden und seine Felder sind frei.")
	_check(_upgrades().get_level("luck") == 0, "Nach dem Verschrotten wirkt er nicht mehr (sync_build lief).")
	_check(_log == (["build_changed", "materials_changed", "item_scrapped"] as Array[String]), "Aus dem Raster kommen dieselben Signale, war %s." % str(_log))
	_check(int(_game.get("points")) == points_before and _points_events == 0, "Verschrotten gibt keine Punkte.")
	_check(int(_game.call("scrap_item", shotgun)) == 2, "Eine ungewöhnliche Waffe aus dem Raster gibt 2 Material.")
	expected += 2
	var hands: Array = _game.get("loadout")
	_check(hands.size() == 1 and int((hands[0] as Dictionary)["uid"]) == 0, "Ohne Waffe im Rucksack hält der Spieler wieder die Dienstpistole.")
	_check(_materials() == expected, "Stand nach allem Verschrotten: %d, erwartet %d." % [_materials(), expected])
	# Unbekanntes.
	_reset_log()
	_check(int(_game.call("scrap_item", 99999)) == 0 and int(_game.call("scrap_item", luck)) == 0, "Unbekannte oder schon verschrottete Gegenstände geben nichts.")
	_check(_materials() == expected and _log.is_empty(), "Dabei ändert sich nichts und es kommt kein Signal, war %s." % str(_log))
	# Verkaufen bleibt daneben bestehen, auch für Kaputtes zum vollen Wert, und gibt kein Material.
	var junk: int = _backpack().add_item("luck", 3, true)
	_reset_log()
	_check(int(_game.call("sell_item", junk)) == ItemDefs.sell_value("luck", 3) and ItemDefs.sell_value("luck", 3) == 400, "Ein kaputter Seltener bringt beim Verkaufen die vollen 400 Punkte.")
	_check(int(_game.get("points")) == points_before + 400 and _materials() == expected and _material_events.is_empty(), "Verkaufen gibt Punkte und kein Material.")
	_game.call("close_backpack")


# --- Kaputt: nicht einräumen, nicht kombinieren, wirkt nicht -----------------------------

func _test_broken_is_locked() -> void:
	_game.call("start_run", 5)
	_game.call("add_materials", 20)
	_game.call("open_backpack")
	var pack: BackpackState = _backpack()
	# Einräumen.
	var luck: int = pack.add_item("luck", 3, true)
	_check(pack.is_broken(luck) and bool(pack.item(luck)["broken"]), "Der Gegenstand ist kaputt.")
	_check(pack.find_spot(luck).is_empty() and not pack.auto_place(luck), "Ein kaputter Gegenstand findet keinen Platz und räumt sich nicht ein.")
	var any_spot: bool = false
	for cell: Vector2i in pack.cells():
		for rot: int in 4:
			if pack.can_place(luck, cell, rot) or pack.place(luck, cell, rot):
				any_spot = true
	_check(not any_spot and not pack.is_placed(luck), "can_place und place lehnen ihn auf jedem Feld in jeder Drehung ab.")
	_game.call("sync_build")
	_check(_upgrades().get_level("luck") == 0 and pack.upgrade_levels().is_empty(), "In der Ablage wirkt er nicht.")
	# Kombinieren: weder als Quelle noch als Ziel, weder in der Ablage noch im Raster.
	var twin: int = pack.add_item("luck", 3)
	_check(not pack.can_merge(luck, twin) and not pack.can_merge(twin, luck), "Kaputt mit heil lässt sich in keiner Richtung kombinieren.")
	_check(not pack.merge(luck, twin) and not pack.merge(twin, luck) and pack.has_item(luck) and pack.has_item(twin), "merge lehnt ab und beide bleiben.")
	_check(pack.find_storage_merge_partner(twin) == -1 and pack.find_storage_merge_partner(luck) == -1, "In der Ablage findet sich kein Partner.")
	_check(pack.auto_place(twin), "Der heile Zwilling lässt sich einräumen.")
	_check(pack.find_merge_partner(luck) == -1 and pack.merge_target(luck, pack.cells_of(twin)[0]) == -1, "Der Kaputte findet auch im Raster kein Ziel.")
	_check(not pack.can_merge(luck, twin) and not pack.can_merge(twin, luck), "Auch mit dem Ziel im Raster geht es nicht.")
	var broken_twin: int = pack.add_item("luck", 3, true)
	_check(not pack.can_merge(luck, broken_twin) and not pack.can_merge(broken_twin, luck), "Zwei Kaputte lassen sich nicht kombinieren.")
	# Nach der Reparatur geht beides.
	_check(bool(_game.call("repair_item", luck)), "Der Gegenstand wird repariert.")
	_check(not pack.can_merge(luck, broken_twin) and not pack.can_merge(broken_twin, luck), "Solange der andere kaputt ist, geht es weiter nicht.")
	_check(pack.can_merge(luck, twin) and pack.find_merge_partner(luck) == twin, "Repariert lässt er sich mit dem heilen kombinieren.")
	_check(not pack.find_spot(luck).is_empty(), "Repariert findet er einen Platz.")
	_check(pack.merge(luck, twin) and int(pack.item(twin)["level"]) == 4, "Zwei Seltene werden Episch.")
	_game.call("sync_build")
	_check(_upgrades().get_level("luck") == 4, "Das Ergebnis wirkt.")
	_check(bool(_game.call("repair_item", broken_twin)) and pack.auto_place(broken_twin), "Auch der zweite lässt sich nach der Reparatur einräumen.")
	# Eine kaputte Waffe kommt nicht in die Hand.
	var gun: int = pack.add_item("revolver", 2, true)
	_check(not pack.auto_place(gun) and pack.hands_used() == 0, "Eine kaputte Waffe braucht keine Hand und lässt sich nicht einräumen.")
	_game.call("sync_build")
	_check(int(((_game.get("loadout") as Array)[0] as Dictionary)["uid"]) == 0, "Mit kaputter Waffe in der Ablage bleibt die Dienstpistole.")
	_check(bool(_game.call("repair_item", gun)) and pack.auto_place(gun), "Repariert lässt sie sich einräumen.")
	_game.call("sync_build")
	_check(int(((_game.get("loadout") as Array)[0] as Dictionary)["uid"]) == gun, "Dann hält der Spieler sie.")
	# Wird etwas Eingeräumtes kaputt, fällt es in die Ablage und wirkt nicht mehr.
	_check(pack.set_broken(gun, true) and not pack.is_placed(gun) and pack.is_broken(gun), "Eine eingeräumte Waffe, die kaputtgeht, liegt danach in der Ablage.")
	_game.call("sync_build")
	_check(int(((_game.get("loadout") as Array)[0] as Dictionary)["uid"]) == 0 and pack.hands_used() == 0, "Sie ist nicht mehr in der Hand.")
	_game.call("close_backpack")


# --- Kistenwahl --------------------------------------------------------------------------

func _test_chest_choice() -> void:
	# broken_loot an: Der gewählte Gegenstand kommt kaputt in die Ablage.
	_game.set("broken_loot", true)
	_game.set("auto_pack", false)
	_game.call("start_run", 6)
	_reset_log()
	_choose_from_chest("luck", 2)
	_check(_state() == STATE_PACKING and _opened.size() == 1 and _opened[0] > 0, "Nach der Wahl öffnet sich der Rucksack mit dem neuen Gegenstand.")
	var uid: int = _opened[0] if not _opened.is_empty() else -1
	_check(str(_backpack().item(uid).get("id", "")) == "luck" and int(_backpack().item(uid).get("level", 0)) == 2, "Der gewählte Gegenstand liegt im Rucksack.")
	_check(_backpack().is_broken(uid) and not _backpack().is_placed(uid), "Mit broken_loot ist er kaputt und liegt in der Ablage.")
	_check(_backpack().storage_items().size() == 1 and bool(_backpack().storage_items()[0]["broken"]), "storage_items zeigt das Feld broken.")
	_check(not _backpack().auto_place(uid), "Er lässt sich nicht einräumen.")
	_check(_materials() == 3 and _material_events.is_empty(), "Die Kistenwahl kostet kein Material.")
	_check(bool(_game.call("close_backpack")) and _state() == STATE_PLAYING, "Der Rucksack lässt sich mit dem Kaputten in der Ablage schließen.")
	_check(_upgrades().get_level("luck") == 0, "Der Kaputte wirkt nicht.")
	# Reparieren und einräumen.
	_game.call("open_backpack")
	_check(bool(_game.call("repair_item", uid)) and _materials() == 1, "Ein Ungewöhnlicher kostet 2 von 3 Material.")
	_check(_backpack().auto_place(uid), "Repariert lässt er sich einräumen.")
	_game.call("sync_build")
	_game.call("close_backpack")
	_check(_upgrades().get_level("luck") == 2, "Repariert und eingeräumt wirkt er.")
	# Ein Rucksack-Teil aus der Kiste ist heil.
	_reset_log()
	_choose_from_chest("bag_small", 1)
	var bag: int = _opened[0] if not _opened.is_empty() else -1
	_check(_backpack().has_item(bag) and not _backpack().is_broken(bag) and not bool(_backpack().item(bag)["broken"]), "Ein Rucksack-Teil aus der Kiste ist heil.")
	var cells_before: int = _backpack().cell_count()
	_check(_backpack().auto_place(bag) and _backpack().cell_count() > cells_before, "Es lässt sich sofort anlegen und vergrößert den Rucksack.")
	_game.call("sync_build")
	_game.call("close_backpack")
	# Mit auto_pack bleibt das kaputte Fundstück in der Ablage: nicht eingeräumt, nicht kombiniert,
	# nicht repariert, nicht verkauft.
	_game.set("auto_pack", true)
	_reset_log()
	var points_before: int = int(_game.get("points"))
	_choose_from_chest("luck", 2)
	_check(_state() == STATE_PLAYING and not paused and _opened.is_empty(), "Mit auto_pack geht es ohne Rucksack weiter.")
	var stored: Array[Dictionary] = _backpack().storage_items()
	_check(stored.size() == 1 and str(stored[0]["id"]) == "luck" and bool(stored[0]["broken"]), "Das kaputte Fundstück wartet in der Ablage.")
	_check(_backpack().placed_items().size() == 1 and _upgrades().get_level("luck") == 2, "Mit dem eingeräumten gleichen Gegenstand wurde es nicht kombiniert.")
	_check(_materials() == 1 and int(_game.get("points")) == points_before, "auto_pack repariert und verkauft nichts.")
	# Ein Rucksack-Teil räumt sich mit auto_pack weiter selbst ein.
	cells_before = _backpack().cell_count()
	_choose_from_chest("bag_small", 1)
	_check(_backpack().cell_count() > cells_before, "Ein Rucksack-Teil räumt sich auch mit broken_loot selbst ein.")
	_game.set("auto_pack", false)
	# broken_loot aus: Der Gegenstand ist heil.
	_game.set("broken_loot", false)
	_game.call("start_run", 6)
	_reset_log()
	_choose_from_chest("luck", 2)
	var whole: int = _opened[0] if not _opened.is_empty() else -1
	_check(_backpack().has_item(whole) and not _backpack().is_broken(whole), "Ohne broken_loot ist der Gegenstand aus der Kiste heil.")
	_check(_backpack().auto_place(whole), "Er lässt sich sofort einräumen.")
	_game.call("sync_build")
	_game.call("close_backpack")
	_check(_upgrades().get_level("luck") == 2, "Und er wirkt.")
	_game.set("broken_loot", true)


# --- grant_item und Startgegenstände -----------------------------------------------------

func _test_grant_and_start_items() -> void:
	_game.set("broken_loot", true)
	_game.set("character_id", "")
	_game.call("start_run", 7)
	# Ohne den dritten Parameter heil, auch mit broken_loot.
	var bought: int = int(_game.call("grant_item", "revolver", 1))
	_check(bought > 0 and _state() == STATE_PACKING and not _backpack().is_broken(bought), "grant_item ohne dritten Parameter gibt einen heilen Gegenstand.")
	_check(_backpack().auto_place(bought), "Er lässt sich einräumen.")
	_game.call("sync_build")
	_game.call("close_backpack")
	# Mit broken = true kaputt.
	var found: int = int(_game.call("grant_item", "burn", 2, true))
	_check(found > 0 and _backpack().is_broken(found) and not _backpack().is_placed(found), "grant_item mit broken = true gibt einen kaputten Gegenstand in die Ablage.")
	_game.call("close_backpack")
	# Ein Rucksack-Teil ist auch dann heil.
	var bag: int = int(_game.call("grant_item", "bag_small", 1, true))
	_check(bag > 0 and not _backpack().is_broken(bag), "Ein Rucksack-Teil ist auch mit broken = true heil.")
	_game.call("close_backpack")
	# Mit auto_pack bleibt der kaputte liegen, der heile räumt sich ein.
	_game.set("auto_pack", true)
	var auto_broken: int = int(_game.call("grant_item", "luck", 1, true))
	_check(_state() == STATE_PLAYING and _backpack().has_item(auto_broken) and not _backpack().is_placed(auto_broken), "Mit auto_pack bleibt ein kaputter Gegenstand in der Ablage.")
	var auto_whole: int = int(_game.call("grant_item", "luck", 1))
	_check(_backpack().is_placed(auto_whole), "Ein heiler räumt sich mit auto_pack ein.")
	_game.set("auto_pack", false)
	# Startgegenstände der Kandidaten sind heil, auch mit broken_loot.
	for character: String in ["technician", "janitor", "intern"]:
		_game.set("character_id", character)
		_game.call("start_run", 7)
		var items: Array[Dictionary] = _backpack().placed_items()
		_check(not items.is_empty() and _backpack().storage_items().is_empty(), "Kandidat %s startet mit eingeräumten Gegenständen." % character)
		for entry: Dictionary in items:
			_check(entry.has("broken") and not bool(entry["broken"]), "Startgegenstand %s von %s ist heil." % [str(entry["id"]), character])
		_check(int(((_game.get("loadout") as Array)[0] as Dictionary)["uid"]) > 0, "Kandidat %s hält seine Waffe aus dem Rucksack." % character)
		_check(_materials() == 3, "Auch Kandidat %s beginnt mit 3 Material." % character)
	_game.set("character_id", "")


# --- Ablage ohne Grenze ------------------------------------------------------------------

func _test_unlimited_storage() -> void:
	_game.set("broken_loot", true)
	_game.set("auto_pack", false)
	_game.call("start_run", 8)
	_game.call("open_backpack")
	for index: int in 30:
		_backpack().add_item("lifesteal", 1 + index % 5, index % 2 == 0)
	_check(_backpack().storage_items().size() == 30, "30 Gegenstände liegen in der Ablage.")
	_check(bool(_game.call("close_backpack")) and _state() == STATE_PLAYING and not paused, "Auch mit 30 Gegenständen in der Ablage schließt der Rucksack.")
	# Mit auto_pack wird nichts verkauft, wenn die Ablage voller wird.
	_game.set("auto_pack", true)
	var points_before: int = int(_game.get("points"))
	for index: int in 12:
		_choose_from_chest("burn", 1 + index % 5)
	_check(_state() == STATE_PLAYING and _backpack().storage_items().size() == 42, "Zwölf kaputte Fundstücke kommen dazu, es lagen %d in der Ablage." % _backpack().storage_items().size())
	_check(int(_game.get("points")) == points_before, "Nichts davon wurde verkauft.")
	_game.set("auto_pack", false)


# --- Neuer Lauf --------------------------------------------------------------------------

func _test_new_run_resets() -> void:
	_game.call("start_run", 9)
	_game.call("add_materials", 10)
	_events.emit_signal("wave_cleared", 1)
	_check(_materials() == 15, "Im Lauf sammelt sich Material, Stand war %d." % _materials())
	_reset_log()
	_game.call("start_run", 10)
	_check(_materials() == 3 and _material_events == ([[3, 0]] as Array[Array]), "Ein neuer Lauf setzt das Material auf 3 zurück, Meldung war %s." % str(_material_events))
	_check(bool(_game.get("broken_loot")), "broken_loot bleibt über Läufe erhalten.")
	# Auch der Neustart nach Game Over (ohne Szene beginnt sofort ein neuer Lauf).
	_game.call("add_materials", 6)
	_game.call("end_run")
	_reset_log()
	_game.call("restart_run")
	_check(_state() == STATE_PLAYING and _materials() == 3, "restart_run setzt das Material zurück, Stand war %d." % _materials())
	_check(_material_events == ([[3, 0]] as Array[Array]), "Auch der Neustart meldet materials_changed(3, 0), war %s." % str(_material_events))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
