extends SceneTree
## Tests für den Rucksack (Abschnitt 16): Gegenstände, Raster, Zusammenlegen, Nachbarschaft,
## Verbindungen, Kandidaten, Kisten-Angebote und der Ablauf in Game (Kiste, Rucksack, Verkaufen).

const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")
const CharacterDefs := preload("res://scripts/core/character_defs.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")
const WeaponState := preload("res://scripts/core/weapon_state.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")

const STATE_PLAYING: int = 1
const STATE_CHOOSING: int = 2
const STATE_PACKING: int = 5

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
var _chosen: Array[String] = []
var _synergies: Array[String] = []
var _build_changes: int = 0
var _opened: Array[int] = []
var _closed: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum.
	await process_frame
	_game = root.get_node("Game")
	_events = root.get_node("Events")
	_events.connect("upgrade_chosen", func(id: String, _level: int) -> void: _chosen.append(id))
	_events.connect("synergy_unlocked", func(id: String) -> void: _synergies.append(id))
	_events.connect("build_changed", func() -> void: _build_changes += 1)
	_events.connect("backpack_opened", func(uid: int) -> void: _opened.append(uid))
	_events.connect("backpack_closed", func() -> void: _closed += 1)

	_test_item_table()
	_test_shapes()
	_test_grid_and_placing()
	_test_storage_and_remove()
	_test_broken()
	_test_merge()
	_test_bags()
	_test_hands()
	_test_stars()
	_test_stat_boosters()
	_test_stacking()
	_test_new_items()
	_test_replay()
	_test_synergy()
	_test_upgrade_state_derived()
	_test_characters()
	_test_item_offers()
	_test_game_flow()
	_test_game_auto_pack()
	_test_game_character()

	paused = false
	_game.set("character_id", "")
	_game.set("auto_pack", false)
	if _failures == 0:
		print("Alle Rucksack-Tests bestanden (%d Prüfungen)." % _checks)
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


# --- Gegenstände ----------------------------------------------------------------------

func _test_item_table() -> void:
	_check(ItemDefs.ORDER.size() == ItemDefs.ITEMS.size(), "ORDER nennt jeden Gegenstand genau einmal.")
	var weapons: int = 0
	var upgrades: int = 0
	var boosters: int = 0
	var bags: int = 0
	var cameras: int = 0
	for id: String in ItemDefs.ORDER:
		_check(ItemDefs.has(id), "Gegenstand %s steht in der Tabelle." % id)
		_check(not ItemDefs.display_name(id).is_empty(), "%s hat einen Namen." % id)
		_check(not ItemDefs.description(id, 1).is_empty(), "%s hat einen Wirkungstext." % id)
		_check(not ItemDefs.subtitle(id, 1).is_empty(), "%s hat eine Unterzeile." % id)
		_check(ItemDefs.cell_count(id) >= 1 and ItemDefs.cell_count(id) <= 6, "%s hat 1 bis 6 Felder." % id)
		_check(ItemDefs.weight(id) > 0.0, "%s hat ein Gewicht für Kisten." % id)
		_check(ItemDefs.sell_value(id, 1) > 0, "%s hat einen Verkaufswert." % id)
		# Die Form hängt zusammen: Jedes Feld grenzt an ein anderes (außer bei einem Feld).
		var cells: Array[Vector2i] = ItemDefs.cells(id, 0)
		for cell: Vector2i in cells:
			var touches: bool = cells.size() == 1
			for other: Vector2i in cells:
				if absi(other.x - cell.x) + absi(other.y - cell.y) == 1:
					touches = true
			_check(touches, "Die Form von %s hängt zusammen." % id)
		# Sterne liegen neben der Form, nie auf ihr, in jeder Drehung.
		for rot: int in 4:
			var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
			for star: Vector2i in ItemDefs.stars(id, rot):
				_check(not shape.has(star), "Ein Stern von %s liegt nicht auf der eigenen Form (Drehung %d)." % [id, rot])
			_check(ItemDefs.stars(id, rot).size() == ItemDefs.stars(id, 0).size(), "%s behält beim Drehen alle Sterne." % id)
		match ItemDefs.kind(id):
			ItemDefs.KIND_WEAPON:
				weapons += 1
				_check(ItemDefs.hands(id) == 1 or ItemDefs.hands(id) == 2, "Waffe %s braucht eine oder zwei Hände." % id)
				_check(not ItemDefs.has_stars(id), "Waffe %s hat keine Sterne." % id)
			ItemDefs.KIND_UPGRADE:
				upgrades += 1
				_check(UpgradeDefs.has(id), "Upgrade-Gegenstand %s gibt es auch als Upgrade." % id)
				_check(ItemDefs.tags(id).size() >= 1, "Upgrade-Gegenstand %s hat eine Gruppe." % id)
				_check(ItemDefs.cell_count(id) <= 4, "Upgrade-Gegenstand %s hat höchstens 4 Felder." % id)
				_check(ItemDefs.hands(id) == 0, "%s braucht keine Hand." % id)
			ItemDefs.KIND_BOOSTER:
				boosters += 1
				_check(ItemDefs.is_replay(id) or (not ItemDefs.stat(id).is_empty() and ItemDefs.stat_amount(id, 1) > 0.0), "Verstärker %s gibt einen Wert oder ist die Wiederholung." % id)
			ItemDefs.KIND_BAG:
				bags += 1
			ItemDefs.KIND_CAMERA:
				cameras += 1
				_check(CameraDefs.has(id) and ItemDefs.is_camera(id), "Kamera %s steht in CameraDefs." % id)
				_check(not ItemDefs.has_stars(id) and ItemDefs.hands(id) == 0, "Kamera %s hat keine Sterne und braucht keine Hand." % id)
				_check(ItemDefs.has_rarity(id) and not UpgradeDefs.has(id), "Kamera %s hat eine Rarität und ist kein Upgrade." % id)
			_:
				_check(false, "%s hat eine unbekannte Art." % id)
	_check(weapons == 19, "Es gibt 19 Waffen, waren %d." % weapons)
	_check(upgrades == 33, "Es gibt 33 Upgrade-Gegenstände (9 ursprüngliche, 11 aus Abschnitt 19, 8 und 5 Kamera-Gegenstände aus Abschnitt 22), waren %d." % upgrades)
	_check(cameras == 5, "Es gibt 5 Kameras, waren %d." % cameras)
	_check(boosters == 4, "Es gibt 4 Verstärker (mit der Wiederholung), waren %d." % boosters)
	_check(ItemDefs.ORDER.size() == 65, "Zusammen 65 Gegenstände, waren %d." % ItemDefs.ORDER.size())
	for id: String in WeaponDefs.ORDER:
		_check(ItemDefs.is_weapon(id), "Jede Waffe hat einen Gegenstand: %s." % id)
	for id: String in CameraDefs.ORDER:
		_check(ItemDefs.is_camera(id), "Jede Kamera hat einen Gegenstand: %s." % id)
	for id: String in UpgradeDefs.ITEM_ONLY:
		_check(ItemDefs.is_upgrade(id), "Jeder Gegenstand aus ITEM_ONLY steht in ItemDefs: %s." % id)
	_check(bags == 4, "Es gibt 4 Rucksack-Teile, waren %d." % bags)
	for id: String in UpgradeDefs.ORDER:
		_check(ItemDefs.is_upgrade(id), "Jedes Upgrade hat einen Gegenstand: %s." % id)
	# Hände.
	_check(ItemDefs.hands("pistol") == 1 and ItemDefs.hands("revolver") == 1 and ItemDefs.hands("smg") == 1 and ItemDefs.hands("sawed_off") == 1, "Vier Einhand-Waffen.")
	for two_handed: String in ["shotgun", "rifle", "sniper", "minigun", "rocket_launcher", "flamethrower", "beam", "tesla", "lmg", "auto_shotgun"]:
		_check(ItemDefs.hands(two_handed) == 2, "%s braucht zwei Hände." % two_handed)
	for one_handed: String in ["burst_pistol", "nail_gun", "machine_pistol", "crossbow", "grenade_launcher"]:
		_check(ItemDefs.hands(one_handed) == 1, "%s braucht eine Hand." % one_handed)
	# Sterne: Kugel-Effekte und zwei Verstärker zielen auf Waffen, alles andere wirkt für sich.
	for mod: String in ["chain_lightning", "pierce", "burn"]:
		_check(ItemDefs.is_weapon_mod(mod) and ItemDefs.star_target(mod) == ItemDefs.STAR_WEAPON, "%s wirkt über Sterne auf Waffen." % mod)
	for plain: String in ["lifesteal", "max_hp", "corpse_explosion", "reload_shockwave", "drone", "speed", "luck", "piggy_bank"]:
		_check(not ItemDefs.has_stars(plain) and not ItemDefs.is_weapon_mod(plain), "%s wirkt ohne Sterne." % plain)
	_check(ItemDefs.has_stars("spotlight") and ItemDefs.has_stars("speed_loader"), "Scheinwerfer und Ladehilfe haben Sterne.")
	# Raritäten.
	_check(ItemDefs.sell_value("burn", 1) == 100 and ItemDefs.sell_value("burn", 3) == 400 and ItemDefs.sell_value("burn", 5) == 1600, "Verkaufswert verdoppelt sich je Rarität: 100, 400, 1600.")
	_check(ItemDefs.sell_value("pistol", 2) == 200 and ItemDefs.sell_value("spotlight", 2) == 200 and ItemDefs.sell_value("bag_small") == 150, "Waffen und Verstärker wie Upgrade-Gegenstände, Rucksack-Teil 150.")
	_check(ItemDefs.RARITY_NAMES == (["Gewöhnlich", "Ungewöhnlich", "Selten", "Episch", "Legendär"] as Array[String]), "Fünf Raritäten von Gewöhnlich bis Legendär.")
	_check(ItemDefs.RARITY_COLORS.size() == 5 and ItemDefs.MAX_RARITY == 5, "Jede Rarität hat eine Farbe.")
	_check(ItemDefs.rarity_name(1) == "Gewöhnlich" and ItemDefs.rarity_name(5) == "Legendär" and ItemDefs.rarity_name(99) == "Legendär" and ItemDefs.rarity_name(0) == "Gewöhnlich", "rarity_name begrenzt auf 1 bis 5.")
	_check(ItemDefs.has_rarity("burn") and ItemDefs.has_rarity("spotlight") and ItemDefs.has_rarity("pistol") and not ItemDefs.has_rarity("bag_small"), "Alles außer Rucksack-Teilen hat eine Rarität.")
	_check(ItemDefs.subtitle("burn", 3) == "Selten · Feuer · 3 Felder", "Unterzeile nennt die Rarität, war: " + ItemDefs.subtitle("burn", 3))
	_check(ItemDefs.subtitle("pistol", 1) == "Gewöhnlich · Waffe · 1 Hand · 2 Felder", "Unterzeile der Pistole, war: " + ItemDefs.subtitle("pistol", 1))
	_check(ItemDefs.subtitle("shotgun", 2) == "Ungewöhnlich · Waffe · 2 Hände · 4 Felder", "Unterzeile der Schrotflinte, war: " + ItemDefs.subtitle("shotgun", 2))
	_check(ItemDefs.subtitle("spotlight", 2) == "Ungewöhnlich · Verstärker · 2 Felder", "Unterzeile des Verstärkers, war: " + ItemDefs.subtitle("spotlight", 2))
	_near(ItemDefs.weapon_damage_factor(1), 1.0, "Eine gewöhnliche Waffe macht den Grundschaden.")
	_near(ItemDefs.weapon_damage_factor(5), 2.2, "Eine legendäre Waffe macht den 2,2-fachen Schaden.")
	_check(ItemDefs.description("spotlight", 1) == "+10 % Schaden für Waffen auf den Sternen." and ItemDefs.description("spotlight", 5) == "+30 % Schaden für Waffen auf den Sternen.", "Text des Scheinwerfers wächst mit der Rarität, war: " + ItemDefs.description("spotlight", 1))
	_check(ItemDefs.description("speed_loader", 2) == "Waffen auf den Sternen laden 15 % schneller nach.", "Text der Ladehilfe, war: " + ItemDefs.description("speed_loader", 2))
	_check(ItemDefs.description("piggy_bank", 3) == "+12 % Punkte.", "Text des Sparschweins, war: " + ItemDefs.description("piggy_bank", 3))
	_check(ItemDefs.description("pierce", 1).ends_with("Gilt für Waffen auf den Sternen."), "Kugel-Effekte nennen die Sterne.")
	_check(ItemDefs.description("pistol", 1).contains("Eine Hand.") and ItemDefs.description("shotgun", 1).contains("Zwei Hände."), "Der Text einer Waffe nennt die Hände.")
	_check(ItemDefs.kind("gibt_es_nicht") == "" and ItemDefs.cells("gibt_es_nicht").is_empty() and ItemDefs.stars("gibt_es_nicht").is_empty(), "Unbekannte Gegenstände sind harmlos.")
	# Abschnitt 22: Kameras und neue Waffen in Text und Unterzeile.
	_check(ItemDefs.subtitle("drone", 3) == "Selten · Kamera · 2 Felder", "Unterzeile der Kameradrohne, war: " + ItemDefs.subtitle("drone", 3))
	_check(ItemDefs.display_name("drone") == "Kameradrohne" and ItemDefs.display_name("cam_director") == "Regie-Kamera", "Kameras nehmen ihren Namen aus CameraDefs.")
	_check(ItemDefs.description("drone", 2) == CameraDefs.effect_text("drone", 2) and ItemDefs.description("drone", 2).contains("21"), "Der Text der Kameradrohne nennt die festen Werte der Rarität: " + ItemDefs.description("drone", 2))
	_check(ItemDefs.color("drone") == ItemDefs.CAMERA_COLOR and ItemDefs.sell_value("cam_tele", 2) == 200, "Kameras haben eine eigene Farbe und einen Verkaufswert wie alle Gegenstände mit Rarität.")
	_check(ItemDefs.description("cam_lens", 1).ends_with("Gilt für Kameras auf den Sternen.") and not ItemDefs.description("cam_uplink", 1).contains("Sternen"), "Kamera-Gegenstände nennen die Sterne, die Sendeleitung nicht.")
	_check(ItemDefs.description("burst_pistol", 1).contains("Salven je Sekunde mit je 3 Schuss"), "Die Salvenpistole nennt die Salve: " + ItemDefs.description("burst_pistol", 1))
	_check(ItemDefs.description("crossbow", 1).contains("Durchschlägt 3 weitere Zombies") and ItemDefs.description("nail_gun", 1).contains("Durchschlägt einen weiteren Zombie"), "Armbrust und Nagelpistole nennen den Durchschlag.")
	_check(ItemDefs.description("grenade_launcher", 1).contains("Granate im Bogen") and ItemDefs.description("grenade_launcher", 1).contains("Explosion 110 im Umkreis von 3 m"), "Der Granatwerfer nennt Bogen und Explosion: " + ItemDefs.description("grenade_launcher", 1))
	_check(ItemDefs.description("flamethrower", 1).contains("Flammen bis 7 m") and ItemDefs.description("beam", 1).contains("Dauerstrahl") and ItemDefs.description("tesla", 1).contains("Springt auf 3 weitere Zombies mit 60 %"), "Flammenwerfer, Strahl und Tesla nennen ihre Besonderheit.")
	_check(ItemDefs.description("pistol", 1) == "Schaden 25 · 5 Schuss je Sekunde · Magazin 10 · Nachladen 1,2 s. Eine Hand.", "Der Text der Dienstpistole bleibt, wie er war: " + ItemDefs.description("pistol", 1))


func _test_shapes() -> void:
	# Feuershow: L aus drei Feldern.
	_check(ItemDefs.cells("burn", 0) == ([Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)] as Array[Vector2i]), "Feuershow ungedreht.")
	_check(ItemDefs.cells("burn", 1) == ([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)] as Array[Vector2i]), "Feuershow eine Vierteldrehung, war %s." % str(ItemDefs.cells("burn", 1)))
	_check(ItemDefs.cells("burn", 4) == ItemDefs.cells("burn", 0), "Vier Vierteldrehungen ergeben die Ausgangsform.")
	_check(ItemDefs.cells("burn", -1) == ItemDefs.cells("burn", 3), "Negative Drehung zählt rückwärts.")
	_check(ItemDefs.size("corpse_explosion", 0) == Vector2i(3, 1) and ItemDefs.size("corpse_explosion", 1) == Vector2i(1, 3), "Die Konfetti-Kanone ist 3 mal 1, gedreht 1 mal 3.")
	# Sterne drehen sich mit der Form: Die Spezialmunition hat ihre Sterne erst oben, dann rechts.
	_check(ItemDefs.stars("pierce", 0) == ([Vector2i(0, -1), Vector2i(1, -1)] as Array[Vector2i]), "Spezialmunition ungedreht: Sterne über der Form, war %s." % str(ItemDefs.stars("pierce", 0)))
	_check(ItemDefs.stars("pierce", 1) == ([Vector2i(1, 0), Vector2i(1, 1)] as Array[Vector2i]), "Eine Vierteldrehung: Sterne rechts, war %s." % str(ItemDefs.stars("pierce", 1)))
	_check(ItemDefs.stars("pierce", 2) == ([Vector2i(1, 1), Vector2i(0, 1)] as Array[Vector2i]), "Halbe Drehung: Sterne unter der Form, war %s." % str(ItemDefs.stars("pierce", 2)))
	_check(ItemDefs.stars("lifesteal", 0).is_empty(), "Ohne Sterne ist die Liste leer.")
	for id: String in ItemDefs.ORDER:
		for rot: int in 4:
			var cells: Array[Vector2i] = ItemDefs.cells(id, rot)
			var min_x: int = 99
			var min_y: int = 99
			for cell: Vector2i in cells:
				min_x = mini(min_x, cell.x)
				min_y = mini(min_y, cell.y)
			_check(cells.size() == ItemDefs.cell_count(id) and min_x == 0 and min_y == 0, "%s Drehung %d beginnt bei (0, 0) und behält alle Felder." % [id, rot])


# --- Raster ---------------------------------------------------------------------------

func _test_grid_and_placing() -> void:
	var backpack: BackpackState = _grid(4, 3)
	_check(backpack.cell_count() == 12 and backpack.free_cell_count() == 12, "4 mal 3 ergibt 12 freie Felder.")
	_check(backpack.has_cell(Vector2i(3, 2)) and not backpack.has_cell(Vector2i(4, 0)), "Nur die Felder der Startform existieren.")
	var burn: int = backpack.add_item("burn", 2)
	_check(burn > 0 and not backpack.is_placed(burn), "Ein neuer Gegenstand liegt in der Ablage.")
	_check(backpack.upgrade_levels().is_empty(), "In der Ablage wirkt ein Gegenstand nicht.")
	_check(backpack.add_item("gibt_es_nicht") == -1, "Unbekannte Gegenstände kommen nicht in den Rucksack.")
	_check(not backpack.can_place(burn, Vector2i(3, 0), 0), "Die Feuershow ragt bei (3, 0) über den Rand.")
	_check(not backpack.can_place(burn, Vector2i(0, 2), 0), "Die Feuershow ragt bei (0, 2) unten heraus.")
	_check(backpack.can_place(burn, Vector2i(0, 0), 0), "Die Feuershow passt bei (0, 0).")
	_check(not backpack.place(burn, Vector2i(3, 2), 0) and not backpack.is_placed(burn), "Ein Fehlversuch ändert nichts.")
	_check(backpack.place(burn, Vector2i(0, 0), 0), "Einräumen bei (0, 0).")
	_check(backpack.is_placed(burn) and backpack.free_cell_count() == 9, "Drei Felder sind belegt.")
	_check(backpack.occupant(Vector2i(1, 0)) == burn and backpack.occupant(Vector2i(1, 1)) == -1, "Belegt sind genau die Felder der Form.")
	_check(int(backpack.item(burn)["level"]) == 2 and backpack.upgrade_levels().is_empty(), "Die Feuershow liegt im Raster, wirkt ohne Waffe aber noch nicht.")
	var pierce: int = backpack.add_item("pierce", 1)
	_check(not backpack.can_place(pierce, Vector2i(0, 0), 0), "Belegte Felder sind gesperrt.")
	_check(backpack.can_place(pierce, Vector2i(1, 1), 0), "Die Spezialmunition passt in die Lücke des L.")
	_check(backpack.place(pierce, Vector2i(1, 1), 0), "Zweiten Gegenstand einräumen.")
	# Verschieben: Die eigenen Felder zählen als frei.
	_check(backpack.can_place(burn, Vector2i(0, 0), 0), "Ein Gegenstand darf auf seiner eigenen Stelle bleiben.")
	_check(not backpack.place(burn, Vector2i(1, 0), 0), "Verschieben auf die Spezialmunition geht nicht.")
	_check(backpack.place(burn, Vector2i(2, 0), 1), "Verschieben mit Drehung an eine freie Stelle.")
	_check(backpack.cells_of(burn) == ([Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, 1)] as Array[Vector2i]), "Die Feuershow liegt gedreht rechts oben, war %s." % str(backpack.cells_of(burn)))
	_check(backpack.neighbors(burn) == ([pierce] as Array[int]), "Feuershow und Spezialmunition sind Nachbarn.")
	_check(backpack.are_neighbors(pierce, burn), "Nachbarschaft gilt in beide Richtungen.")
	# Übereck ist keine Nachbarschaft.
	var small: BackpackState = _grid(2, 2)
	var a: int = small.add_item("luck")
	var b: int = small.add_item("lifesteal")
	small.place(a, Vector2i(0, 0), 0)
	small.place(b, Vector2i(1, 1), 0)
	_check(small.neighbors(a).is_empty(), "Übereck liegende Gegenstände sind keine Nachbarn.")
	_check(small.free_neighbor_cells(a) == 2, "Neben (0, 0) sind zwei freie Felder.")
	# Selbst einräumen.
	var auto: BackpackState = _grid(2, 2)
	var tall: int = auto.add_item("max_hp")
	_check(auto.find_spot(tall).is_empty() and not auto.auto_place(tall), "Drei Felder in einer Reihe passen nicht in 2 mal 2.")
	var wide: int = auto.add_item("pierce")
	_check(auto.auto_place(wide) and auto.cells_of(wide) == ([Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i]), "auto_place nimmt die erste passende Stelle.")
	var upright: int = auto.add_item("chain_lightning")
	_check(auto.auto_place(upright) and auto.free_cell_count() == 0, "auto_place dreht, wenn es nur gedreht passt.")


func _test_storage_and_remove() -> void:
	var backpack: BackpackState = _grid(4, 3)
	var luck: int = backpack.add_item("luck", 2)
	backpack.place(luck, Vector2i(0, 0), 0)
	_check(backpack.store(luck) and not backpack.is_placed(luck), "store legt einen Gegenstand in die Ablage.")
	_check(not backpack.store(luck), "Was schon in der Ablage liegt, lässt sich nicht noch einmal ablegen.")
	_check(backpack.upgrade_levels().is_empty() and backpack.storage_items().size() == 1, "In der Ablage wirkt er nicht mehr.")
	_check(int(backpack.item(luck)["level"]) == 2, "Die Stufe bleibt in der Ablage erhalten.")
	# Die Ablage hat keine Grenze (Abschnitt 26).
	for _i: int in 40:
		backpack.add_item("lifesteal")
	_check(backpack.storage_items().size() == 41, "41 Gegenstände liegen in der Ablage, waren %d." % backpack.storage_items().size())
	_check(not backpack.storage_overflow(), "Die veraltete Hülle storage_overflow meldet nie einen Überlauf.")
	_check(BackpackState.STORAGE_CAPACITY > 100000, "Die veraltete Hülle STORAGE_CAPACITY ist so groß, dass sie nie erreicht wird.")
	var extra: int = backpack.add_item("lifesteal")
	var removed: Dictionary = backpack.remove(extra)
	_check(str(removed.get("id", "")) == "lifesteal" and not backpack.has_item(extra), "remove gibt den Gegenstand zurück und löscht ihn.")
	_check(backpack.remove(9999).is_empty(), "Unbekannte uid: remove gibt nichts zurück.")
	_check(backpack.storage_items().size() == 41, "Nach dem Entfernen liegen wieder 41 in der Ablage.")
	_check(backpack.item(9999).is_empty() and backpack.cells_of(9999).is_empty(), "Unbekannte uid ist harmlos.")


## Kaputte Gegenstände (Abschnitt 26): Feld broken, Sperre beim Einräumen und Kombinieren, keine
## Wirkung, Reparatur. Die Regeln mit Material stehen in test_materials.gd.
func _test_broken() -> void:
	var backpack: BackpackState = _grid(7, 5)
	# Das Feld steht in jedem Eintrag.
	var whole: int = backpack.add_item("luck", 2)
	var broken: int = backpack.add_item("luck", 2, true)
	_check(backpack.item(whole).has("broken") and not bool(backpack.item(whole)["broken"]), "Ohne den dritten Parameter ist ein Gegenstand heil.")
	_check(bool(backpack.item(broken)["broken"]) and backpack.is_broken(broken) and not backpack.is_broken(whole), "Mit broken = true ist er kaputt.")
	_check(not backpack.is_broken(9999) and not backpack.set_broken(9999, true) and not backpack.repair(9999), "Unbekannte uid ist weder kaputt noch zu reparieren.")
	var stored: Array[Dictionary] = backpack.storage_items()
	_check(stored.size() == 2 and not bool(stored[0]["broken"]) and bool(stored[1]["broken"]), "storage_items zeigt das Feld broken.")
	_check(int(backpack.item(broken)["level"]) == 2 and backpack.highest_level("luck") == 2, "Die Rarität bleibt, auch ein kaputter Gegenstand zählt als Besitz.")
	# Rucksack-Teile sind nie kaputt.
	var bag: int = backpack.add_item("bag_small", 1, true)
	_check(not backpack.is_broken(bag) and not bool(backpack.item(bag)["broken"]), "Ein Rucksack-Teil ist nie kaputt, auch mit broken = true.")
	_check(not backpack.set_broken(bag, true) and not backpack.is_broken(bag), "set_broken macht ein Rucksack-Teil nicht kaputt.")
	backpack.remove(bag)
	# Einräumen ist gesperrt.
	_check(not backpack.can_place(broken, Vector2i(0, 0), 0) and not backpack.place(broken, Vector2i(0, 0), 0), "can_place und place lehnen einen kaputten Gegenstand ab.")
	_check(backpack.find_spot(broken).is_empty() and not backpack.auto_place(broken) and not backpack.is_placed(broken), "find_spot und auto_place auch.")
	backpack.set_rotation(broken, 1)
	_check(int(backpack.item(broken)["rot"]) == 1, "Drehen in der Ablage geht auch kaputt (nur Anzeige).")
	# Kombinieren ist in beide Richtungen gesperrt, in der Ablage und mit dem Ziel im Raster.
	_check(not backpack.can_merge(broken, whole) and not backpack.can_merge(whole, broken), "can_merge ist mit einem Kaputten in beiden Richtungen false.")
	_check(not backpack.merge(broken, whole) and not backpack.merge(whole, broken), "merge lehnt ab.")
	_check(backpack.find_storage_merge_partner(whole) == -1 and backpack.find_storage_merge_partner(broken) == -1, "find_storage_merge_partner findet keinen Kaputten und nichts für ihn.")
	_check(backpack.place(whole, Vector2i(0, 0), 0), "Der heile lässt sich einräumen.")
	_check(backpack.merge_target(broken, Vector2i(0, 0)) == -1 and backpack.find_merge_partner(broken) == -1, "merge_target und find_merge_partner geben für einen Kaputten nichts.")
	_check(not backpack.can_merge(broken, whole) and not backpack.can_merge(whole, broken), "Auch mit dem Ziel im Raster nicht.")
	_check(backpack.has_item(broken) and backpack.has_item(whole) and int(backpack.item(whole)["level"]) == 2, "Beide sind unverändert da.")
	# In der Ablage wirkt er nicht.
	_check(backpack.upgrade_levels() == {"luck": 2} and (backpack.global_copies()["luck"] as Array) == [2], "Nur der heile zählt.")
	# Reparieren.
	_check(backpack.repair(broken) and not backpack.is_broken(broken) and not bool(backpack.item(broken)["broken"]), "repair macht ihn heil.")
	_check(not backpack.repair(broken) and not backpack.set_broken(broken, false), "Ein heiler Gegenstand lässt sich nicht noch einmal reparieren.")
	_check(not backpack.is_placed(broken), "Nach der Reparatur liegt er weiter in der Ablage.")
	_check(backpack.merge_target(broken, Vector2i(0, 0)) == whole and backpack.can_merge(broken, whole), "Repariert lässt er sich kombinieren.")
	_check(not backpack.find_spot(broken).is_empty(), "Repariert findet er einen Platz.")
	_check(backpack.merge(broken, whole) and int(backpack.item(whole)["level"]) == 3 and not bool(backpack.item(whole)["broken"]), "Aus zwei Ungewöhnlichen wird ein heiler Seltener.")
	# Geht etwas Eingeräumtes kaputt, fällt es in die Ablage und zählt nirgends mehr mit.
	var build: BackpackState = _grid(7, 5)
	var pistol: int = build.add_item("pistol", 1)
	var chain: int = build.add_item("chain_lightning", 3)
	var drone: int = build.add_item("drone", 2)
	_check(build.place(pistol, Vector2i(2, 2), 0) and build.place(chain, Vector2i(1, 2), 0) and build.auto_place(drone), "Pistole, Blitz und Kamera einräumen.")
	_check(build.loadout().size() == 1 and ((build.loadout()[0]["copies"] as Dictionary).get("chain_lightning", []) as Array) == [3], "Der Blitz wirkt über seinen Stern auf die Pistole.")
	_check(build.cameras().size() == 1 and build.placed_items().size() == 3, "Die Kamera zählt als Exemplar.")
	for entry: Dictionary in build.placed_items():
		_check(entry.has("broken") and not bool(entry["broken"]), "placed_items zeigt das Feld broken (%s)." % str(entry["id"]))
	_check(build.set_broken(chain, true) and not build.is_placed(chain) and build.cells_of(chain).is_empty(), "Ein eingeräumter Gegenstand, der kaputtgeht, liegt danach in der Ablage.")
	_check((build.loadout()[0]["copies"] as Dictionary).is_empty() and build.mods_of(pistol).is_empty() and build.upgrade_levels().is_empty(), "Sein Stern wirkt nicht mehr auf die Waffe.")
	_check(not build.is_active(chain) and build.star_cells_of(chain).is_empty(), "Er ist nicht aktiv und hat keine Sternfelder.")
	_check(build.set_broken(drone, true) and build.cameras().is_empty(), "Eine kaputte Kamera ist kein Exemplar.")
	_check(build.set_broken(pistol, true) and build.loadout().is_empty() and build.hands_used() == 0, "Eine kaputte Waffe ist nicht in der Hand und braucht keine.")
	_check(build.placed_items().is_empty() and build.storage_items().size() == 3 and build.free_cell_count() == build.cell_count(), "Alle drei liegen in der Ablage, das Raster ist frei.")
	_check(build.summary().is_empty() and build.stats() == {"damage": 0.0, "reload": 0.0, "points": 0.0}, "Übersicht und Zusatzwerte sind leer.")
	_check(build.repair(pistol) and build.place(pistol, Vector2i(2, 2), 0) and build.loadout().size() == 1, "Repariert kommt die Waffe wieder in die Hand.")
	# remove gibt den Eintrag mit dem Feld zurück (Verkaufen und Verschrotten gehen auch kaputt).
	_check(bool(build.remove(chain).get("broken", false)) and not build.has_item(chain), "Ein kaputter Gegenstand lässt sich entfernen.")


func _test_merge() -> void:
	# Kombinieren: zwei gleiche Gegenstände gleicher Rarität werden einer der nächsten Rarität.
	var backpack: BackpackState = _grid(4, 3)
	var first: int = backpack.add_item("burn", 1)
	backpack.place(first, Vector2i(0, 0), 0)
	var second: int = backpack.add_item("burn", 1)
	_check(backpack.merge_target(second, Vector2i(1, 0)) == first, "Gleicher Gegenstand gleicher Rarität auf einem belegten Feld ist ein Ziel zum Kombinieren.")
	_check(backpack.merge_target(second, Vector2i(3, 2)) == -1, "Ein leeres Feld ist kein Ziel.")
	_check(backpack.find_merge_partner(second) == first, "find_merge_partner findet den Partner.")
	_check(backpack.merge(second, first), "Kombinieren klappt.")
	_check(not backpack.has_item(second) and int(backpack.item(first)["level"]) == 2, "Aus zwei Gewöhnlichen wird ein Ungewöhnlicher, der zweite verschwindet.")
	_check(backpack.upgrade_levels().is_empty(), "Ohne Waffe auf ihren Sternen wirkt die Feuershow nicht.")
	# Verschiedene Rarität: kein Kombinieren.
	var common: int = backpack.add_item("burn", 1)
	_check(backpack.merge_target(common, Vector2i(0, 0)) == -1 and not backpack.merge(common, first), "Gewöhnlich und Ungewöhnlich lassen sich nicht kombinieren.")
	_check(backpack.find_merge_partner(common) == -1, "Ohne passenden Partner gibt es keinen.")
	_check(int(backpack.item(first)["level"]) == 2 and backpack.has_item(common), "Ein Fehlversuch ändert nichts.")
	# Bis Legendär, dann ist Schluss.
	for wanted: int in [2, 3, 4]:
		var copy: int = backpack.add_item("burn", wanted)
		_check(backpack.merge(copy, first) and int(backpack.item(first)["level"]) == wanted + 1, "Zwei der Rarität %d ergeben %d." % [wanted, wanted + 1])
	_check(int(backpack.item(first)["level"]) == Balance.UPGRADE_MAX_LEVEL, "Nach vier Schritten ist der Gegenstand Legendär.")
	var top: int = backpack.add_item("burn", 5)
	_check(backpack.merge_target(top, Vector2i(0, 0)) == -1 and not backpack.merge(top, first), "Zwei Legendäre lassen sich nicht weiter kombinieren.")
	var other: int = backpack.add_item("pierce", 5)
	_check(backpack.merge_target(other, Vector2i(0, 0)) == -1, "Verschiedene Gegenstände lassen sich nicht kombinieren.")
	# Verstärker und Waffen haben auch Raritäten und lassen sich kombinieren.
	var pig: int = backpack.add_item("piggy_bank", 1)
	backpack.place(pig, Vector2i(3, 2), 0)
	var pig_two: int = backpack.add_item("piggy_bank", 1)
	_check(backpack.merge_target(pig_two, Vector2i(3, 2)) == pig and backpack.merge(pig_two, pig), "Zwei gleiche Verstärker lassen sich kombinieren.")
	_check(int(backpack.item(pig)["level"]) == 2, "Der Verstärker ist danach Ungewöhnlich.")
	var gun: int = backpack.add_item("pistol", 1)
	backpack.place(gun, Vector2i(2, 1), 0)
	var gun_two: int = backpack.add_item("pistol", 1)
	_check(backpack.find_merge_partner(gun_two) == gun and backpack.merge(gun_two, gun) and int(backpack.item(gun)["level"]) == 2, "Zwei gleiche Waffen werden eine der nächsten Rarität.")
	# Rucksack-Teile haben keine Rarität: kein Ziel, kein Partner.
	var bag: int = backpack.add_item("bag_small", 4)
	_check(int(backpack.item(bag)["level"]) == 1 and backpack.find_merge_partner(bag) == -1, "Rucksack-Teile haben keine Rarität.")
	# Derselbe Gegenstand mehrfach: Jedes Exemplar wirkt. upgrade_levels nennt für Übersichten die
	# beste Rarität, global_copies jedes Exemplar.
	var split: BackpackState = _grid(4, 3)
	var one: int = split.add_item("luck", 2)
	var two: int = split.add_item("luck", 2)
	split.place(one, Vector2i(0, 0), 0)
	split.place(two, Vector2i(3, 2), 0)
	_check(split.upgrade_levels() == {"luck": 2}, "upgrade_levels nennt die beste Rarität.")
	_check(split.global_copies() == {"luck": [2, 2]}, "global_copies nennt jedes Exemplar.")
	var three: int = split.add_item("luck", 4)
	split.place(three, Vector2i(2, 0), 0)
	_check(split.upgrade_levels() == {"luck": 4} and split.global_copies() == {"luck": [2, 2, 4]}, "Ein drittes Exemplar kommt dazu.")
	_check(split.highest_level("luck") == 4 and split.highest_level("burn") == 0, "highest_level nennt die beste Rarität im Besitz.")
	# Kombinieren zweier eingeräumter Gegenstände gibt Platz frei.
	_check(split.merge(two, one) and split.free_cell_count() == 10, "Kombinieren im Rucksack macht ein Feld frei.")
	_check(int(split.item(one)["level"]) == 3, "Zwei Ungewöhnliche ergeben einen Seltenen.")
	# Kombinieren geht auch in der Ablage: Ablage auf Ablage, Raster auf Ablage, Ablage auf Raster.
	var shelf: BackpackState = BackpackState.new()
	shelf.setup([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)] as Array[Vector2i])
	var stored_a: int = shelf.add_item("luck", 1)
	var stored_b: int = shelf.add_item("luck", 1)
	_check(shelf.find_merge_partner(stored_a) == -1, "find_merge_partner sucht weiter nur im Raster.")
	_check(shelf.find_storage_merge_partner(stored_a) == stored_b, "find_storage_merge_partner findet den Partner in der Ablage.")
	_check(shelf.can_merge(stored_a, stored_b) and not shelf.can_merge(stored_a, stored_a), "Zwei gleiche in der Ablage lassen sich kombinieren, einer mit sich selbst nicht.")
	_check(shelf.merge(stored_a, stored_b), "Kombinieren in der Ablage klappt.")
	_check(not shelf.has_item(stored_a) and int(shelf.item(stored_b)["level"]) == 2 and not bool(shelf.item(stored_b)["placed"]), "Das Ziel steigt um eine Rarität und bleibt in der Ablage.")
	_check(shelf.storage_items().size() == 1, "Die Ablage hat danach einen Gegenstand weniger.")
	var placed_c: int = shelf.add_item("luck", 2)
	_check(shelf.place(placed_c, Vector2i(0, 0), 0) and shelf.can_merge(placed_c, stored_b), "Ein eingeräumter passt zu einem gleichen in der Ablage.")
	_check(shelf.merge(placed_c, stored_b) and int(shelf.item(stored_b)["level"]) == 3 and shelf.placed_items().is_empty(), "Raster auf Ablage: Das Ergebnis liegt in der Ablage, das Feld ist frei.")
	var placed_d: int = shelf.add_item("luck", 3)
	_check(shelf.place(placed_d, Vector2i(0, 0), 0) and shelf.merge(stored_b, placed_d) and int(shelf.item(placed_d)["level"]) == 4 and bool(shelf.item(placed_d)["placed"]), "Ablage auf Raster: Das Ergebnis bleibt im Raster.")
	var other_level: int = shelf.add_item("luck", 2)
	var other_item: int = shelf.add_item("burn", 4)
	_check(not shelf.can_merge(other_level, placed_d) and not shelf.merge(other_level, placed_d), "Verschiedene Raritäten lassen sich auch in der Ablage nicht kombinieren.")
	_check(not shelf.can_merge(other_item, placed_d), "Verschiedene Gegenstände lassen sich nicht kombinieren.")
	var top_a: int = shelf.add_item("speed", 5)
	var top_b: int = shelf.add_item("speed", 5)
	_check(not shelf.can_merge(top_a, top_b), "Zwei Legendäre lassen sich auch in der Ablage nicht kombinieren.")
	var bag_a: int = shelf.add_item("bag_small")
	var bag_b: int = shelf.add_item("bag_small")
	_check(not shelf.can_merge(bag_a, bag_b), "Rucksack-Teile lassen sich nicht kombinieren.")
	# Auch aus der Ablage heraus zählt die Rarität für highest_level.
	var stored: int = split.add_item("burn", 5)
	_check(split.highest_level("burn") == 5 and not split.is_placed(stored), "highest_level zählt auch die Ablage.")


func _test_bags() -> void:
	var backpack: BackpackState = BackpackState.new()
	backpack.setup([Vector2i(2, 2), Vector2i(3, 2)] as Array[Vector2i])
	var bag: int = backpack.add_item("bag_small")
	_check(not backpack.can_place(bag, Vector2i(2, 2), 0), "Ein Rucksack-Teil passt nicht auf vorhandene Felder.")
	_check(not backpack.can_place(bag, Vector2i(5, 0), 0), "Ein Rucksack-Teil muss an den Rucksack grenzen.")
	_check(not backpack.can_place(bag, Vector2i(6, 2), 0), "Ein Rucksack-Teil darf nicht über das Raster hinausragen.")
	_check(backpack.can_place(bag, Vector2i(2, 1), 0), "Direkt über dem Rucksack passt der Jutebeutel.")
	_check(backpack.can_place(bag, Vector2i(4, 2), 1), "Gedreht rechts daneben passt er auch.")
	_check(backpack.upgrade_levels().is_empty(), "Ein Rucksack-Teil wirkt nicht als Upgrade.")
	_check(backpack.place(bag, Vector2i(2, 1), 0), "Rucksack-Teil einräumen.")
	_check(backpack.cell_count() == 4 and backpack.has_cell(Vector2i(3, 1)), "Der Rucksack hat jetzt 4 Felder.")
	_check(not backpack.has_item(bag), "Das Rucksack-Teil ist verbraucht.")
	var burn: int = backpack.add_item("burn")
	_check(backpack.place(burn, Vector2i(2, 1), 0), "Auf den neuen Feldern lässt sich etwas einräumen.")
	# Bis zum Rand des Rasters.
	var large: int = backpack.add_item("bag_large")
	_check(backpack.can_place(large, Vector2i(4, 1), 0), "Der Reisekoffer passt bis an den rechten Rand.")
	_check(not backpack.can_place(large, Vector2i(5, 1), 0), "Über den rechten Rand hinaus passt er nicht.")
	_check(backpack.auto_place(large) and backpack.cell_count() == 10, "auto_place findet auch für Rucksack-Teile eine Stelle.")
	# Bauchtasche: genau ein Feld.
	_check(ItemDefs.is_bag("bag_tiny") and ItemDefs.cell_count("bag_tiny") == 1, "Die Bauchtasche ist ein Rucksack-Teil mit einem Feld.")
	_check(ItemDefs.display_name("bag_tiny") == "Bauchtasche" and ItemDefs.sell_value("bag_tiny") == Balance.ITEM_SELL_BAG, "Name und Verkaufswert der Bauchtasche.")
	var tiny: int = backpack.add_item("bag_tiny")
	var cells_before: int = backpack.cell_count()
	_check(not backpack.can_place(tiny, Vector2i(2, 2), 0), "Die Bauchtasche passt nicht auf ein vorhandenes Feld.")
	_check(backpack.auto_place(tiny), "Die Bauchtasche findet eine Stelle am Rand.")
	_check(backpack.cell_count() == cells_before + 1, "Die Bauchtasche gibt genau ein Feld (%d -> %d)." % [cells_before, backpack.cell_count()])
	_check(not backpack.has_item(tiny), "Die Bauchtasche ist danach verbraucht.")


func _test_hands() -> void:
	var backpack: BackpackState = _grid(7, 5)
	_check(backpack.hands_used() == 0 and backpack.loadout().is_empty(), "Ohne Waffe sind beide Hände frei.")
	var first: int = backpack.add_item("pistol", 1)
	_check(backpack.has_free_hands(first), "In der Ablage braucht eine Waffe noch keine Hand.")
	_check(backpack.place(first, Vector2i(3, 0), 0) and backpack.hands_used() == 1, "Eine Pistole braucht eine Hand.")
	var second: int = backpack.add_item("pistol", 1)
	_check(backpack.place(second, Vector2i(0, 0), 0) and backpack.hands_used() == 2, "Zwei Pistolen: beide Hände voll (Akimbo).")
	var third: int = backpack.add_item("revolver", 1)
	_check(not backpack.has_free_hands(third) and not backpack.can_place(third, Vector2i(0, 2), 0), "Für eine dritte Waffe ist keine Hand frei.")
	_check(backpack.find_spot(third).is_empty() and not backpack.auto_place(third), "Ohne freie Hand findet auch auto_place keine Stelle.")
	# Eine eingeräumte Waffe darf verschoben werden: Sie zählt nicht gegen sich selbst.
	_check(backpack.place(second, Vector2i(0, 3), 0), "Eine Waffe in der Hand lässt sich im Raster verschieben.")
	# Reihenfolge der Hände: von links nach rechts.
	var hands: Array[Dictionary] = backpack.loadout()
	_check(hands.size() == 2 and int(hands[0]["uid"]) == second and int(hands[1]["uid"]) == first, "Die linke Hand hält die Waffe, die weiter links liegt.")
	_check(int(hands[0]["hands"]) == 1 and str(hands[0]["id"]) == "pistol" and int(hands[0]["level"]) == 1, "Der Eintrag nennt Waffe, Rarität und Hände.")
	# Zweihand-Waffe: braucht beide Hände.
	var shotgun: int = backpack.add_item("shotgun", 2)
	_check(not backpack.can_place(shotgun, Vector2i(0, 1), 0), "Neben zwei Pistolen passt keine Schrotflinte.")
	backpack.store(first)
	_check(not backpack.can_place(shotgun, Vector2i(0, 1), 0), "Auch neben einer Pistole ist keine zweite Hand frei.")
	backpack.store(second)
	_check(backpack.place(shotgun, Vector2i(0, 1), 0) and backpack.hands_used() == 2, "Ohne andere Waffe passt die Schrotflinte, sie braucht zwei Hände.")
	_check(not backpack.can_place(first, Vector2i(3, 0), 0), "Zur Schrotflinte passt keine Pistole mehr.")
	hands = backpack.loadout()
	_check(hands.size() == 1 and int(hands[0]["hands"]) == 2 and int(hands[0]["level"]) == 2, "Die Bewaffnung ist die eine Zweihand-Waffe.")
	# Gegenstände ohne Hände sind nie gesperrt.
	var luck: int = backpack.add_item("luck", 1)
	_check(backpack.has_free_hands(luck) and backpack.place(luck, Vector2i(6, 4), 0), "Andere Gegenstände brauchen keine Hand.")
	_check(not backpack.has_free_hands(9999), "Unbekannte uid hat keine freien Hände.")


func _test_stars() -> void:
	# Raster 7 x 5, Pistole auf (2, 2) und (3, 2).
	var backpack: BackpackState = _grid(7, 5)
	var pistol: int = backpack.add_item("pistol", 1)
	backpack.place(pistol, Vector2i(2, 2), 0)
	var pierce: int = backpack.add_item("pierce", 2)
	_check(backpack.star_cells_of(pierce).is_empty() and not backpack.is_active(pierce), "In der Ablage hat ein Gegenstand keine Sterne.")
	# Abseits: Die Sterne liegen über der Form und damit außerhalb des Rasters.
	backpack.place(pierce, Vector2i(5, 0), 0)
	_check(backpack.star_cells_of(pierce) == ([Vector2i(5, -1), Vector2i(6, -1)] as Array[Vector2i]), "Sternfelder können außerhalb des Rasters liegen.")
	_check(backpack.star_targets(pierce).is_empty() and not backpack.is_active(pierce), "Ohne Waffe auf einem Stern wirkt der Gegenstand nicht.")
	_check(backpack.upgrade_levels().is_empty() and backpack.global_copies().is_empty(), "Er steht dann in keiner Übersicht.")
	_check((backpack.loadout()[0]["copies"] as Dictionary).is_empty(), "Die Waffe hat keinen Effekt.")
	# Unter die Pistole gelegt: Beide Sterne liegen auf der Waffe.
	backpack.place(pierce, Vector2i(2, 3), 0)
	_check(backpack.star_targets(pierce) == ([pistol] as Array[int]), "Die Sterne treffen die Pistole (ohne Doppelte).")
	_check(backpack.is_star_lit(pierce, Vector2i(2, 2)) and backpack.is_star_lit(pierce, Vector2i(3, 2)), "Beide Sterne leuchten.")
	_check(not backpack.is_star_lit(pierce, Vector2i(0, 0)), "Ein Feld ohne Stern leuchtet nicht.")
	_check(backpack.is_active(pierce) and backpack.mods_of(pistol) == ([pierce] as Array[int]), "Der Gegenstand wirkt auf die Pistole.")
	_check(backpack.loadout()[0]["copies"] == {"pierce": [2]}, "Die Waffe hat die Spezialmunition in ihrer Rarität.")
	_check(backpack.upgrade_levels() == {"pierce": 2}, "Die Übersicht nennt den wirkenden Gegenstand.")
	_check(backpack.global_copies().is_empty(), "Stern-Gegenstände gelten nicht für alle Waffen.")
	# Ein zweites Exemplar von oben (halbe Drehung: Sterne unter der Form): Beide wirken.
	var second: int = backpack.add_item("pierce", 1)
	_check(backpack.place(second, Vector2i(2, 1), 2), "Zweite Spezialmunition über der Pistole.")
	_check(backpack.loadout()[0]["copies"] == {"pierce": [2, 1]}, "Beide Exemplare wirken auf die Waffe.")
	# Ein Stern auf einem Gegenstand, der keine Waffe ist, leuchtet nicht.
	var luck: int = backpack.add_item("luck", 1)
	backpack.place(luck, Vector2i(6, 4), 0)
	var lonely: int = backpack.add_item("pierce", 1)
	backpack.place(lonely, Vector2i(5, 3), 1)
	_check(backpack.star_cells_of(lonely).has(Vector2i(6, 4)) and not backpack.is_star_lit(lonely, Vector2i(6, 4)), "Ein Stern auf dem Publikumsliebling leuchtet nicht.")
	_check(backpack.is_active(luck) and backpack.global_copies() == {"luck": [1]}, "Gegenstände ohne Sterne wirken immer.")
	# Akimbo: Ein Gegenstand zwischen zwei Pistolen wirkt auf beide, ein Verstärker nur auf eine.
	var akimbo: BackpackState = _grid(7, 5)
	var left: int = akimbo.add_item("pistol", 1)
	var right: int = akimbo.add_item("pistol", 3)
	akimbo.place(left, Vector2i(0, 0), 0)
	akimbo.place(right, Vector2i(3, 0), 0)
	var chain: int = akimbo.add_item("chain_lightning", 4)
	_check(akimbo.place(chain, Vector2i(2, 0), 0), "Der Starkstrom-Sponsor liegt zwischen den Pistolen.")
	_check(akimbo.star_targets(chain).size() == 2, "Seine Sterne treffen beide Pistolen.")
	var spot: int = akimbo.add_item("spotlight", 1)
	_check(akimbo.place(spot, Vector2i(3, 1), 2), "Der Scheinwerfer liegt unter der rechten Pistole (Sterne nach oben).")
	var hands: Array[Dictionary] = akimbo.loadout()
	_check(hands.size() == 2 and hands[0]["copies"] == {"chain_lightning": [4]} and hands[1]["copies"] == {"chain_lightning": [4]}, "Beide Pistolen haben den Blitz.")
	_near(float(hands[0]["damage"]), 0.0, "Die linke Pistole hat keinen Scheinwerfer.")
	_near(float(hands[1]["damage"]), 0.1, "Die rechte Pistole hat 10 % mehr Schaden.")
	_check(akimbo.mods_of(right).size() == 2 and akimbo.mods_of(left).size() == 1, "mods_of nennt die wirkenden Gegenstände je Waffe.")
	# Nimmt man die Waffe heraus, wirkt der Gegenstand nicht mehr.
	akimbo.store(left)
	akimbo.store(right)
	_check(not akimbo.is_active(chain) and akimbo.upgrade_levels().is_empty(), "Ohne Waffe wirkt der Starkstrom-Sponsor nicht.")


func _test_stat_boosters() -> void:
	var backpack: BackpackState = _grid(7, 5)
	_check(backpack.stats() == {"damage": 0.0, "reload": 0.0, "points": 0.0}, "Ohne Verstärker gibt es keine Zusatzwerte.")
	# Sparschwein: wirkt immer, jedes Exemplar zählt, die Rarität vervielfacht.
	var pig: int = backpack.add_item("piggy_bank", 1)
	backpack.place(pig, Vector2i(6, 4), 0)
	_near(float(backpack.stats()["points"]), 0.06, "Ein Sparschwein gibt 6 % Punkte.")
	_near(backpack.stat_contribution(pig), 0.06, "Sein Beitrag ist 6 %.")
	var rare_pig: int = backpack.add_item("piggy_bank", 3)
	backpack.place(rare_pig, Vector2i(5, 4), 0)
	_near(float(backpack.stats()["points"]), 0.18, "Ein seltenes dazu: 6 % + 12 %.")
	# Scheinwerfer: nur für die Waffe auf seinen Sternen.
	var spot: int = backpack.add_item("spotlight", 5)
	backpack.place(spot, Vector2i(0, 0), 0)
	_near(backpack.stat_contribution(spot), 0.0, "Ein Scheinwerfer ohne Waffe gibt nichts.")
	var pistol: int = backpack.add_item("pistol", 1)
	backpack.place(pistol, Vector2i(0, 1), 0)
	_near(backpack.stat_contribution(spot), 0.3, "Legendär auf einer Waffe: 30 %.")
	_near(float(backpack.loadout()[0]["damage"]), 0.3, "Die Waffe hat 30 % mehr Schaden.")
	_near(float(backpack.stats()["damage"]), 0.0, "Der Schaden steht je Waffe, nicht in den allgemeinen Werten.")
	# Ladehilfe: Mehrere addieren sich, zusammen höchstens 50 %.
	var loader: int = backpack.add_item("speed_loader", 5)
	backpack.place(loader, Vector2i(2, 1), 0)
	_near(float(backpack.loadout()[0]["reload"]), 0.3, "Eine legendäre Ladehilfe: 30 % schnelleres Nachladen.")
	var loader_two: int = backpack.add_item("speed_loader", 5)
	backpack.place(loader_two, Vector2i(0, 2), 0)
	_near(float(backpack.loadout()[0]["reload"]), Balance.RELOAD_BONUS_MAX, "Zwei davon: höchstens 50 %.")


func _test_stacking() -> void:
	# Mehrere Exemplare desselben Upgrades: Die meisten Werte addieren sich.
	_near(UpgradeDefs.combined_value("lifesteal", "ratio", [1]), UpgradeDefs.value("lifesteal", "ratio", 1), "Ein Exemplar ergibt den einfachen Wert.")
	_near(UpgradeDefs.combined_value("lifesteal", "ratio", [1, 1]), 0.04, "Zwei gewöhnliche Blutspenden: 2 % + 2 %.")
	_near(UpgradeDefs.combined_value("lifesteal", "ratio", [1, 3]), 0.08, "Gewöhnlich und Selten: 2 % + 6 %.")
	_near(UpgradeDefs.combined_value("pierce", "targets", [2, 2, 1]), 5.0, "Durchschlag addiert die Ziele.")
	_near(UpgradeDefs.combined_value("max_hp", "bonus", [1, 1, 1]), 60.0, "Drei Stuntdoubles: dreimal 20 Leben.")
	# Chancen enden bei 100 %.
	_near(UpgradeDefs.combined_value("corpse_explosion", "chance", [5, 5, 5]), 1.0, "Eine Chance wird nie größer als 100 %.")
	_near(UpgradeDefs.combined_value("chain_lightning", "chance", [1, 2]), 0.25, "Blitz-Chancen addieren sich: 10 % + 15 %.")
	# Reichweiten und Schadensanteile nehmen den besten Wert.
	_near(UpgradeDefs.combined_value("corpse_explosion", "radius", [1, 5]), UpgradeDefs.value("corpse_explosion", "radius", 5), "Beim Radius zählt der beste.")
	_near(UpgradeDefs.combined_value("chain_lightning", "damage_factor", [1, 5, 2]), UpgradeDefs.value("chain_lightning", "damage_factor", 5), "Beim Schadensanteil zählt der beste.")
	_near(UpgradeDefs.combined_value("lifesteal", "ratio", []), 0.0, "Ohne Exemplar ist der Wert 0.")
	_near(UpgradeDefs.combined_value("lifesteal", "ratio", [0, 2]), 0.04, "Stufe 0 zählt nicht mit.")
	# UpgradeState mit Exemplaren.
	var state: UpgradeState = UpgradeState.new()
	state.set_derived({"lifesteal": 3, "pierce": 2}, [] as Array[String], {}, {"lifesteal": [1, 3]})
	_near(state.value("lifesteal", "ratio"), 0.08, "value rechnet mit allen Exemplaren.")
	_check(state.get_level("lifesteal") == 3 and state.get_level("pierce") == 2, "get_level nennt die beste Stufe für die Übersicht.")
	_near(state.value("pierce", "targets"), 0.0, "Ein Upgrade ohne Exemplar-Eintrag hat hier den Wert 0 (es gilt je Waffe).")
	_check(state.copies("lifesteal") == [1, 3] and state.copies("pierce").is_empty(), "copies nennt die Exemplare.")
	# Allgemeine Upgrades und die einer Waffe zusammen.
	var weapon: UpgradeState = UpgradeState.new()
	weapon.set_derived({"pierce": 2}, [] as Array[String], {}, {"pierce": [2, 1]})
	_near(state.value_with(weapon, "pierce", "targets"), 3.0, "value_with nimmt die Exemplare der Waffe dazu.")
	_check(state.level_with(weapon, "pierce") == 2 and state.level_with(weapon, "burn") == 0, "level_with nennt die beste Stufe aus beiden.")
	_near(state.value_with(null, "lifesteal", "ratio"), 0.08, "Ohne Waffe zählen nur die allgemeinen.")
	# Von Hand gesetzte Stufen (Tests): ein Exemplar je Upgrade.
	var manual: UpgradeState = UpgradeState.new()
	manual.add_levels("burn", 3)
	_check(manual.copies("burn") == [3], "add_levels ergibt ein Exemplar.")
	_near(manual.value("burn", "dps_percent"), UpgradeDefs.value("burn", "dps_percent", 3), "Der Wert ist der der Stufe.")
	manual.set_derived({"burn": 1}, [] as Array[String], {}, {})
	_near(manual.value("burn", "dps_percent"), 0.0, "Mit leerer Exemplar-Liste wirkt nichts allgemein.")
	manual.add_levels("burn", 1)
	_check(manual.copies("burn") == [2], "add_levels verlässt die Exemplar-Liste wieder.")


func _test_new_items() -> void:
	# Abschnitt 19: sechs Gegenstände für die Waffe (mit Sternen), fünf für den Spieler.
	for mod: String in ["extra_shot", "poison", "crit", "big_mag", "scope", "fire_rate"]:
		_check(ItemDefs.is_upgrade(mod) and ItemDefs.is_weapon_mod(mod) and ItemDefs.star_target(mod) == ItemDefs.STAR_WEAPON, "%s wirkt über Sterne auf Waffen." % mod)
		_check(ItemDefs.description(mod, 1).ends_with("Gilt für Waffen auf den Sternen."), "%s nennt die Sterne im Text." % mod)
	for plain: String in ["shield", "kill_heal", "disco_ball", "jammer", "dash"]:
		_check(ItemDefs.is_upgrade(plain) and not ItemDefs.has_stars(plain), "%s wirkt ohne Sterne für den Spieler." % plain)
	# Abschnitt 22.3: vier für die Waffe, vier für den Spieler.
	for mod: String in ["frost", "opener", "punchline", "ricochet"]:
		_check(ItemDefs.is_upgrade(mod) and ItemDefs.is_weapon_mod(mod) and not ItemDefs.is_camera_mod(mod), "%s wirkt über Sterne auf Waffen." % mod)
		_check(ItemDefs.description(mod, 1).ends_with("Gilt für Waffen auf den Sternen."), "%s nennt die Sterne im Text." % mod)
	for plain: String in ["thorns", "revive", "snack", "mine"]:
		_check(ItemDefs.is_upgrade(plain) and not ItemDefs.has_stars(plain), "%s wirkt ohne Sterne für den Spieler." % plain)
	_check(ItemDefs.stars("frost", 0) == ([Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)] as Array[Vector2i]), "Trockeneis: drei Sterne in einer Reihe darüber.")
	_check(ItemDefs.stars("opener", 0) == ([Vector2i(-1, 0), Vector2i(0, -1)] as Array[Vector2i]), "Eröffnungsgag: links und über dem Eckfeld.")
	_check(ItemDefs.stars("punchline", 0) == ([Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2)] as Array[Vector2i]), "Schlusspointe: drei Sterne in einer Reihe darunter.")
	_check(ItemDefs.stars("ricochet", 0) == ([Vector2i(1, -1), Vector2i(1, 1)] as Array[Vector2i]), "Querschläger: rechts oben und rechts unten.")
	# Kein Sternmuster kommt unter Gegenständen derselben Art mit demselben Ziel zweimal vor, auch
	# nicht gedreht (Form und Sterne zusammen).
	var patterns: Dictionary = {}
	for id: String in ItemDefs.ORDER:
		if not ItemDefs.has_stars(id):
			continue
		var same: bool = false
		for rot: int in 4:
			var key: String = "%s|%s|%s|%s" % [ItemDefs.kind(id), ItemDefs.star_target(id), str(ItemDefs.cells(id, rot)), str(_sorted(ItemDefs.stars(id, rot)))]
			if patterns.has(key) and str(patterns[key]) != id:
				same = true
				_check(false, "%s hat dasselbe Sternmuster wie %s." % [id, str(patterns[key])])
		if not same:
			for rot: int in 4:
				patterns["%s|%s|%s|%s" % [ItemDefs.kind(id), ItemDefs.star_target(id), str(ItemDefs.cells(id, rot)), str(_sorted(ItemDefs.stars(id, rot)))]] = id
	# Jeder hat ein eigenes Sternmuster.
	_check(ItemDefs.stars("extra_shot", 0) == ([Vector2i(2, 0), Vector2i(3, 0)] as Array[Vector2i]), "Zugabe: zwei Sterne in einer Linie nach vorn.")
	_check(ItemDefs.stars("poison", 0).size() == 4 and ItemDefs.stars("poison", 0).has(Vector2i(-1, -1)) and ItemDefs.stars("poison", 0).has(Vector2i(1, 1)), "Kantinenessen: die vier Ecken.")
	_check(ItemDefs.stars("crit", 0) == ([Vector2i(-1, 0), Vector2i(1, 0)] as Array[Vector2i]), "Glücksrad: links und rechts.")
	_check(ItemDefs.stars("big_mag", 0).size() == 4, "Überlänge: über und unter beiden Feldern.")
	_check(ItemDefs.stars("scope", 0) == ([Vector2i(1, 0)] as Array[Vector2i]), "Teleprompter: ein Stern in der Innenecke.")
	_check(ItemDefs.stars("fire_rate", 0).size() == 6, "Schnelldurchlauf: ein Ring aus sechs Feldern.")
	# Die Zugabe reicht zwei Felder weit: Sie wirkt auch mit einem Feld Abstand.
	var backpack: BackpackState = _grid(7, 5)
	var pistol: int = backpack.add_item("pistol", 1)
	backpack.place(pistol, Vector2i(4, 0), 0)
	var extra: int = backpack.add_item("extra_shot", 2)
	backpack.place(extra, Vector2i(1, 0), 0)
	_check(backpack.star_targets(extra) == ([pistol] as Array[int]), "Die Zugabe trifft die Pistole über ein freies Feld hinweg.")
	_check(backpack.is_star_lit(extra, Vector2i(4, 0)) and not backpack.is_star_lit(extra, Vector2i(3, 0)), "Der ferne Stern leuchtet, der nahe liegt auf einem leeren Feld.")
	# Kantinenessen wirkt nur übereck.
	var poison: int = backpack.add_item("poison", 1)
	backpack.place(poison, Vector2i(6, 0), 0)
	_check(backpack.star_targets(poison).is_empty(), "Direkt neben der Pistole wirkt das Kantinenessen nicht (nur übereck).")
	backpack.place(poison, Vector2i(6, 1), 0)
	_check(backpack.star_targets(poison) == ([pistol] as Array[int]), "Übereck wirkt es.")
	var hands: Array[Dictionary] = backpack.loadout()
	_check(hands[0]["copies"] == {"extra_shot": [2], "poison": [1]}, "Die Pistole hat Zugabe und Kantinenessen, war %s." % str(hands[0]["copies"]))
	# Werte: mehrere Exemplare.
	_near(UpgradeDefs.combined_value("extra_shot", "shots", [1, 3]), 2.0, "Zwei Zugaben: zwei zusätzliche Kugeln.")
	_near(UpgradeDefs.combined_value("extra_shot", "damage_factor", [1, 3]), 0.7, "Die Zusatzkugeln nehmen den besten Schadensanteil.")
	_near(UpgradeDefs.combined_value("crit", "chance", [5, 5, 5, 5]), 1.0, "Krit-Chance endet bei 100 %.")
	_near(UpgradeDefs.combined_value("big_mag", "bonus", [1, 1]), 0.6, "Zwei Überlängen: 60 % mehr Magazin.")
	_near(UpgradeDefs.combined_value("shield", "amount", [1, 5]), 80.0, "Schilde addieren sich.")
	_near(UpgradeDefs.combined_value("dash", "cooldown", [1, 4]), 2.5, "Beim Ausweichsprung zählt die kürzeste Abklingzeit.")
	_near(UpgradeDefs.combined_value("dash", "charges", [1, 4]), 2.0, "Jedes Exemplar gibt einen Sprung mehr.")
	_near(UpgradeDefs.combined_value("jammer", "radius", [1, 5]), 6.0, "Beim Störsender zählt der größte Umkreis.")
	_near(UpgradeDefs.combined_value("jammer", "damage", [1, 5]), 130.0, "Sein Schaden addiert sich.")


func _test_replay() -> void:
	_check(ItemDefs.is_replay("replay") and ItemDefs.is_booster("replay") and ItemDefs.star_target("replay") == ItemDefs.STAR_ITEM, "Die Wiederholung zielt mit ihrem Stern auf Gegenstände.")
	_check(ItemDefs.min_rarity("replay") == Balance.RARITY_GOLD, "Die Wiederholung gibt es nur in Gold-Kisten.")
	_check(ItemDefs.star_hits("replay", "luck") and not ItemDefs.star_hits("replay", "pistol") and not ItemDefs.star_hits("replay", "replay") and not ItemDefs.star_hits("replay", "spotlight"), "Sie wirkt auf Upgrade-Gegenstände, nicht auf Waffen, Verstärker oder sich selbst.")
	_check(ItemDefs.star_hits("replay", "drone") and ItemDefs.star_hits("replay", "cam_lens"), "Sie wirkt auch auf Kameras und Kamera-Gegenstände.")
	_check(ItemDefs.star_hits("pierce", "pistol") and not ItemDefs.star_hits("pierce", "luck"), "Waffen-Sterne wirken nur auf Waffen.")
	var backpack: BackpackState = _grid(7, 5)
	# Auf einen Gegenstand für den Spieler: Er zählt doppelt.
	var luck: int = backpack.add_item("luck", 2)
	backpack.place(luck, Vector2i(1, 0), 0)
	var replay: int = backpack.add_item("replay", 3)
	_check(backpack.place(replay, Vector2i(0, 0), 0), "Die Wiederholung liegt links neben dem Publikumsliebling.")
	_check(backpack.star_targets(replay) == ([luck] as Array[int]) and backpack.is_star_lit(replay, Vector2i(1, 0)), "Ihr Stern trifft ihn.")
	_check(backpack.is_active(replay) and backpack.mods_of(luck) == ([replay] as Array[int]), "Sie wirkt auf ihn.")
	_check(backpack.copy_levels(luck) == ([2, 2] as Array[int]), "Der Publikumsliebling zählt zweimal.")
	_check(backpack.global_copies() == {"luck": [2, 2]}, "global_copies nennt beide.")
	# Das zweite Mal höchstens in der Rarität der Wiederholung.
	var strong: int = backpack.add_item("lifesteal", 5)
	backpack.place(strong, Vector2i(1, 2), 0)
	var weak_replay: int = backpack.add_item("replay", 3)
	backpack.place(weak_replay, Vector2i(0, 2), 0)
	_check(backpack.copy_levels(strong) == ([5, 3] as Array[int]), "Legendär mit seltener Wiederholung: einmal Legendär, einmal Selten.")
	# Zwei Wiederholungen auf demselben Gegenstand: dreifach.
	var second: int = backpack.add_item("replay", 3)
	backpack.place(second, Vector2i(2, 0), 2)
	_check(backpack.star_targets(second) == ([luck] as Array[int]), "Eine zweite Wiederholung von rechts (halbe Drehung).")
	_check(backpack.copy_levels(luck) == ([2, 2, 2] as Array[int]), "Zwei Wiederholungen: dreifach.")
	# Auf eine Waffe wirkt sie nicht.
	var pistol: int = backpack.add_item("pistol", 1)
	backpack.place(pistol, Vector2i(4, 4), 0)
	var useless: int = backpack.add_item("replay", 3)
	backpack.place(useless, Vector2i(3, 4), 0)
	_check(backpack.star_targets(useless).is_empty() and not backpack.is_active(useless) and not backpack.is_star_lit(useless, Vector2i(4, 4)), "Auf eine Waffe wirkt die Wiederholung nicht.")
	# Auf einen Kugel-Effekt: Die Waffe bekommt ihn doppelt.
	var pierce: int = backpack.add_item("pierce", 2)
	_check(backpack.place(pierce, Vector2i(4, 3), 2), "Spezialmunition über der Pistole (Sterne nach unten).")
	_check(backpack.star_targets(pierce) == ([pistol] as Array[int]), "Sie trifft die Pistole.")
	backpack.store(useless)
	_check(backpack.place(useless, Vector2i(3, 3), 0), "Die Wiederholung liegt jetzt links neben der Spezialmunition.")
	_check(backpack.copy_levels(pierce) == ([2, 2] as Array[int]), "Die Spezialmunition zählt doppelt.")
	_check(backpack.loadout()[0]["copies"] == {"pierce": [2, 2]}, "Die Pistole bekommt sie zweimal.")
	_check(backpack.copy_levels(pistol).is_empty() and backpack.copy_levels(replay).is_empty() and backpack.copy_levels(9999).is_empty(), "copy_levels gilt nur für eingeräumte Upgrade-Gegenstände.")
	# In der Ablage zählt nichts.
	backpack.store(luck)
	_check(backpack.copy_levels(luck).is_empty() and not backpack.is_active(replay), "In der Ablage zählt der Gegenstand nicht, die Wiederholung wirkt dann auf nichts.")


func _test_synergy() -> void:
	# Gewitterfront: Blitz und Durchschlag wirken beide Legendär auf dieselbe Waffe.
	var backpack: BackpackState = _grid(7, 5)
	var pistol: int = backpack.add_item("pistol", 1)
	backpack.place(pistol, Vector2i(2, 2), 0)
	var chain: int = backpack.add_item("chain_lightning", 5)
	var pierce: int = backpack.add_item("pierce", 5)
	backpack.place(chain, Vector2i(1, 2), 0)
	backpack.place(pierce, Vector2i(5, 0), 0)
	_check(backpack.active_synergies().is_empty(), "Wirkt der Durchschlag auf keine Waffe, gibt es keine Verbindung.")
	_check(backpack.synergy_links().is_empty(), "Dann gibt es auch keine Verbindungslinie.")
	backpack.place(pierce, Vector2i(2, 3), 0)
	_check(backpack.star_targets(chain) == ([pistol] as Array[int]) and backpack.star_targets(pierce) == ([pistol] as Array[int]), "Beide wirken auf die Pistole.")
	_check(backpack.active_synergies() == (["storm_front"] as Array[String]), "Beide Legendär auf derselben Waffe: Gewitterfront.")
	_check(backpack.synergy_links().size() == 1, "Die beiden Gegenstände sind verbunden.")
	# Auf verschiedenen Waffen gibt es keine Verbindung.
	var split: BackpackState = _grid(7, 5)
	var left: int = split.add_item("pistol", 1)
	var right: int = split.add_item("pistol", 1)
	split.place(left, Vector2i(1, 0), 0)
	split.place(right, Vector2i(4, 2), 0)
	var split_chain: int = split.add_item("chain_lightning", 5)
	var split_pierce: int = split.add_item("pierce", 5)
	split.place(split_chain, Vector2i(0, 0), 0)
	split.place(split_pierce, Vector2i(4, 3), 0)
	_check(split.star_targets(split_chain) == ([left] as Array[int]) and split.star_targets(split_pierce) == ([right] as Array[int]), "Jeder wirkt auf eine andere Pistole.")
	_check(split.active_synergies().is_empty() and split.synergy_links().is_empty(), "Auf verschiedenen Waffen entsteht keine Gewitterfront.")
	# Auf derselben Waffe, aber zu schwach.
	var weak: BackpackState = _grid(7, 5)
	var weak_pistol: int = weak.add_item("pistol", 1)
	weak.place(weak_pistol, Vector2i(2, 2), 0)
	var weak_chain: int = weak.add_item("chain_lightning", 4)
	var weak_pierce: int = weak.add_item("pierce", 5)
	weak.place(weak_chain, Vector2i(1, 2), 0)
	weak.place(weak_pierce, Vector2i(2, 3), 0)
	_check(weak.active_synergies().is_empty(), "Episch reicht nicht.")
	_check(weak.synergy_links().size() == 1, "Die mögliche Verbindung wird schon gezeigt.")


func _test_upgrade_state_derived() -> void:
	var state: UpgradeState = UpgradeState.new()
	_near(state.damage_multiplier(), 1.0, "Ohne Zusatz ist der Schadensfaktor 1.")
	_near(state.reload_time_multiplier(), 1.0, "Ohne Zusatz ist der Nachlade-Faktor 1.")
	state.set_derived({"burn": 3, "speed": 9, "luck": 0, "gibt_es_nicht": 2}, ["storm_front"] as Array[String],
		{"max_hp": 30.0, "speed": -0.05, "damage": 0.2, "reload": 0.9, "points": 0.08})
	_check(state.get_level("burn") == 3 and state.get_level("speed") == 5, "Stufen werden übernommen und bei 5 gekappt.")
	_check(state.get_level("luck") == 0 and state.owned_ids().size() == 2, "Stufe 0 und unbekannte IDs entfallen.")
	_check(state.has_synergy("storm_front") and state.active_synergies().size() == 1, "Abgeleitete Synergien gelten ohne Stufen-Regel.")
	_check(state.check_new_synergies() == (["storm_front"] as Array[String]) and state.check_new_synergies().is_empty(), "Eine neue Synergie wird genau einmal gemeldet.")
	_near(state.bonus_max_hp(), 30.0, "Zusatz-Leben kommt aus den Zusatzwerten.")
	_near(state.speed_multiplier(), 1.0 + UpgradeDefs.value("speed", "bonus", 5) - 0.05, "Tempo: Upgrade plus Zusatz.")
	_near(state.damage_multiplier(), 1.2, "Schadensfaktor 1,2.")
	_near(state.reload_time_multiplier(), 0.5, "Der Nachlade-Faktor fällt nicht unter 0,5.")
	_near(state.points_multiplier(), 1.08, "Punkte-Faktor aus dem Zusatz.")
	# Mehr als 6 Upgrades sind abgeleitet erlaubt (Platz begrenzt der Rucksack).
	var all: Dictionary = {}
	for id: String in UpgradeDefs.ORDER:
		all[id] = 1
	state.set_derived(all, [] as Array[String])
	_check(state.owned_ids().size() == 9, "Abgeleitet gelten alle 9 Upgrades gleichzeitig.")
	_check(not state.has_synergy("storm_front"), "Ohne Eintrag ist die Synergie wieder aus.")
	# Der Nachlade-Faktor wirkt auf die Waffe.
	var weapon: WeaponState = WeaponState.new("pistol")
	var normal: float = weapon.reload_duration()
	weapon.reload_factor = 0.5
	_near(weapon.reload_duration(), normal * 0.5, "reload_factor halbiert die Nachladezeit.")


# --- Kandidaten -----------------------------------------------------------------------

func _test_characters() -> void:
	_check(CharacterDefs.ORDER.size() == 3 and CharacterDefs.CHARACTERS.size() == 3, "Es gibt 3 Kandidaten.")
	_check(CharacterDefs.has(CharacterDefs.DEFAULT), "Die Vorauswahl ist ein Kandidat.")
	for id: String in CharacterDefs.ORDER:
		_check(not CharacterDefs.display_name(id).is_empty() and not CharacterDefs.tagline(id).is_empty() and not CharacterDefs.text(id).is_empty(), "%s hat Name, Spruch und Text." % id)
		var cells: Array[Vector2i] = CharacterDefs.bag_cells(id)
		_check(cells.size() == 12, "%s startet mit 12 Feldern, waren %d." % [id, cells.size()])
		for cell: Vector2i in cells:
			_check(BackpackState.in_bounds(cell), "Start-Rucksack von %s liegt im Raster." % id)
		var backpack: BackpackState = CharacterDefs.build_backpack(id)
		_check(backpack.cell_count() == 12, "Der Rucksack von %s hat 12 Felder." % id)
		_check(backpack.storage_items().is_empty(), "Alle Start-Gegenstände von %s sind eingeräumt." % id)
		_check(backpack.placed_items().size() == CharacterDefs.start_items(id).size(), "%s hat seine Start-Gegenstände." % id)
		_check(CharacterDefs.base_max_hp(id) >= 50.0, "%s hat genug Leben." % id)
		_check(not CharacterDefs.weapons(id).is_empty() and backpack.loadout().size() == CharacterDefs.weapons(id).size(), "%s hält seine Startwaffen in der Hand." % id)
		_check(backpack.hands_used() >= 1 and backpack.hands_used() <= Balance.PLAYER_HANDS, "%s braucht höchstens zwei Hände." % id)
		for entry: Dictionary in backpack.placed_items():
			_check(backpack.is_active(int(entry["uid"])), "Jeder Start-Gegenstand von %s wirkt (Sterne liegen auf der Waffe): %s." % [id, str(entry["id"])])
	_near(CharacterDefs.base_max_hp("janitor"), 130.0, "Der Hausmeister hat 130 Leben.")
	_near(CharacterDefs.base_max_hp("intern"), 80.0, "Die Praktikantin hat 80 Leben.")
	_check(CharacterDefs.start_points("technician") == 500, "Der Tontechniker startet mit 500 Punkten.")
	_check(CharacterDefs.weapons("janitor") == (["shotgun"] as Array[String]), "Der Hausmeister startet mit der Schrotflinte.")
	_check(CharacterDefs.weapons("intern") == (["smg", "pistol"] as Array[String]), "Die Praktikantin startet mit Maschinenpistole und Pistole.")
	var intern: Array[Dictionary] = CharacterDefs.build_backpack("intern").loadout()
	_check(intern.size() == 2 and str(intern[0]["id"]) == "smg" and str(intern[1]["id"]) == "pistol", "Die Praktikantin hält links die MP und rechts die Pistole.")
	var tech: Array[Dictionary] = CharacterDefs.build_backpack("technician").loadout()
	_check(tech.size() == 1 and str(tech[0]["id"]) == "pistol", "Der Tontechniker hält die Dienstpistole.")
	_check(tech[0]["copies"] == {"chain_lightning": [1]}, "Der Starkstrom-Sponsor wirkt auf seine Pistole.")
	_near(float(tech[0]["damage"]), 0.1, "Der Scheinwerfer gibt seiner Pistole 10 % Schaden.")
	# Ohne Kandidat: leerer Standard-Rucksack, keine Eigenheiten, keine Waffe im Rucksack.
	var plain: BackpackState = CharacterDefs.build_backpack(CharacterDefs.NONE)
	_check(plain.cell_count() == 12 and plain.placed_items().is_empty() and plain.loadout().is_empty(), "Ohne Kandidat: 12 leere Felder.")
	_check(CharacterDefs.extra("").is_empty() and CharacterDefs.weapons("").is_empty() and CharacterDefs.start_points("") == 0, "Ohne Kandidat gibt es keine Eigenheiten.")
	_check(CharacterDefs.valid_id("gibt_es_nicht") == CharacterDefs.DEFAULT and CharacterDefs.valid_id("intern") == "intern", "valid_id fällt auf die Vorauswahl zurück.")


# --- Kisten ---------------------------------------------------------------------------

func _test_item_offers() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var backpack: BackpackState = _grid(4, 3)
	var seen: Dictionary = {}
	for round_index: int in 1500:
		var rarity: int = round_index % 3
		var offers: Array[Dictionary] = ChestRoller.build_item_offers(rng, backpack, rarity)
		_check(offers.size() == 3, "Eine Kiste bietet immer 3 an.")
		var ids: Array[String] = []
		var bag_count: int = 0
		var upgrade_count: int = 0
		for offer: Dictionary in offers:
			var id: String = str(offer.get("id", ""))
			if str(offer.get("kind", "")) != ChestRoller.KIND_ITEM:
				_check(false, "Mit vollem Angebot gibt es keine Trostpreise.")
				continue
			seen[id] = true
			if ids.has(id):
				_check(false, "Kein Gegenstand kommt in einer Kiste doppelt vor.")
			ids.append(id)
			if ItemDefs.min_rarity(id) > rarity:
				_check(false, "%s darf in Seltenheit %d nicht vorkommen." % [id, rarity])
			if ItemDefs.is_bag(id):
				bag_count += 1
			if ItemDefs.is_upgrade(id) or ItemDefs.is_camera(id):
				upgrade_count += 1
				if int(offer["level"]) != ChestRoller.levels_for_rarity(rarity):
					_check(false, "Upgrade-Gegenstände haben die Stufe der Seltenheit.")
			elif not ItemDefs.is_bag(id) and int(offer["level"]) != ChestRoller.levels_for_rarity(rarity):
				_check(false, "Verstärker und Waffen haben die Rarität der Kiste.")
			elif ItemDefs.is_bag(id) and int(offer["level"]) != 1:
				_check(false, "Rucksack-Teile haben keine Rarität.")
		_check(bag_count <= 1 and upgrade_count >= 1, "Höchstens ein Rucksack-Teil, mindestens ein Upgrade-Gegenstand oder eine Kamera.")
	_check(seen.size() == ItemDefs.ORDER.size(), "Über viele Kisten kommt jeder Gegenstand vor, waren %d von %d." % [seen.size(), ItemDefs.ORDER.size()])
	# Gleicher Seed, gleiches Angebot.
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 99
	rng_b.seed = 99
	_check(str(ChestRoller.build_item_offers(rng_a, backpack, 1)) == str(ChestRoller.build_item_offers(rng_b, backpack, 1)), "Gleicher Seed ergibt dasselbe Angebot.")
	# Auch was der Spieler schon in Legendär hat, wird weiter angeboten. owned_level stimmt.
	var burn: int = backpack.add_item("burn", 5)
	backpack.place(burn, Vector2i(0, 0), 0)
	var luck: int = backpack.add_item("luck", 2)
	backpack.place(luck, Vector2i(3, 2), 0)
	var luck_seen: bool = false
	var burn_seen: bool = false
	for _i: int in 200:
		for offer: Dictionary in ChestRoller.build_item_offers(rng, backpack, 0):
			if str(offer.get("id", "")) == "burn":
				burn_seen = true
				if int(offer["owned_level"]) != 5:
					_check(false, "owned_level nennt Legendär für die Feuershow.")
			if str(offer.get("id", "")) == "luck":
				luck_seen = true
				if int(offer["owned_level"]) != 2:
					_check(false, "owned_level nennt die wirksame Stufe im Rucksack.")
	_check(luck_seen, "Der Publikumsliebling wird weiter angeboten.")
	_check(burn_seen, "Auch die legendäre Feuershow wird weiter angeboten.")
	# Volles Raster: keine Rucksack-Teile mehr.
	var full: BackpackState = _grid(BackpackState.COLS, BackpackState.ROWS)
	for _i: int in 200:
		for offer: Dictionary in ChestRoller.build_item_offers(rng, full, 2):
			if ItemDefs.is_bag(str(offer.get("id", ""))):
				_check(false, "Bei vollem Raster gibt es keine Rucksack-Teile.")
	# Rucksack-Teile: mit force_bag sicher, sonst etwa in jeder dritten Kiste, nie zwei.
	var plain: BackpackState = _grid(4, 3)
	var with_bag: int = 0
	for _i: int in 400:
		if ChestRoller.offers_have_bag(ChestRoller.build_item_offers(rng, plain, 0)):
			with_bag += 1
	_check(with_bag > 80 and with_bag < 170, "Ohne Garantie bietet etwa jede dritte Kiste ein Rucksack-Teil an (waren %d von 400)." % with_bag)
	for _i: int in 100:
		var forced: Array[Dictionary] = ChestRoller.build_item_offers(rng, plain, _i % 3, true)
		var forced_bags: int = 0
		for offer: Dictionary in forced:
			if ItemDefs.is_bag(str(offer.get("id", ""))):
				forced_bags += 1
		if forced_bags != 1:
			_check(false, "Mit force_bag enthält die Kiste genau ein Rucksack-Teil.")
	_check(not ChestRoller.offers_have_bag(ChestRoller.build_item_offers(rng, full, 2, true)), "Bei vollem Raster gibt es auch mit Garantie kein Rucksack-Teil.")
	# Abwechslung: Was in der letzten Kiste lag, kommt in der nächsten deutlich seltener.
	var favourites: Array[String] = ["burn", "luck", "spotlight"]
	var repeats_plain: int = 0
	var repeats_recent: int = 0
	for _i: int in 400:
		for id: String in ChestRoller.offer_ids(ChestRoller.build_item_offers(rng, plain, 0)):
			if favourites.has(id):
				repeats_plain += 1
		for id: String in ChestRoller.offer_ids(ChestRoller.build_item_offers(rng, plain, 0, false, favourites)):
			if favourites.has(id):
				repeats_recent += 1
	_check(repeats_recent * 2 < repeats_plain, "Gegenstände aus der letzten Kiste kommen viel seltener (%d statt %d)." % [repeats_recent, repeats_plain])
	# Texte der Karten.
	var offer_new: Dictionary = {"kind": "item", "id": "burn", "level": 2, "owned_level": 0}
	_check(ChestRoller.offer_title(offer_new) == "Feuershow", "Der Titel ist der Name des Gegenstands.")
	_check(ChestRoller.offer_level_text(offer_new) == "Neu: Ungewöhnlich", "Neuer Gegenstand: Neu mit Rarität.")
	_check(ChestRoller.offer_level_text({"kind": "item", "id": "burn", "level": 1, "owned_level": 3}) == "Gewöhnlich · du hast Selten", "Vorhandener Gegenstand nennt die Rarität im Besitz.")
	_check(ChestRoller.offer_level_text({"kind": "item", "id": "spotlight", "level": 3}) == "Neu: Selten", "Auch Verstärker nennen ihre Rarität.")
	_check(ChestRoller.offer_level_text({"kind": "item", "id": "pistol", "level": 2, "owned_level": 1}) == "Ungewöhnlich · du hast Gewöhnlich", "Auch Waffen nennen ihre Rarität.")
	_check(ChestRoller.offer_title({"kind": "item", "id": "pistol", "level": 1}) == WeaponDefs.display_name("pistol"), "Der Titel einer Waffe ist ihr Name.")
	_check(ChestRoller.offer_level_text({"kind": "item", "id": "bag_small", "level": 1}) == "Mehr Platz", "Rucksack-Teile versprechen Platz.")
	_check(ChestRoller.offer_description(offer_new) == ItemDefs.description("burn", 2) and ChestRoller.offer_description(offer_new).begins_with(UpgradeDefs.effect_text("burn", 2)), "Die Beschreibung nennt die Zahlen der Rarität.")


# --- Ablauf in Game -------------------------------------------------------------------

func _state() -> int:
	return int(_game.get("state"))


func _backpack() -> BackpackState:
	return _game.get("backpack") as BackpackState


func _upgrades() -> UpgradeState:
	return _game.get("upgrades") as UpgradeState


func _reset_log() -> void:
	_chosen.clear()
	_synergies.clear()
	_opened.clear()
	_build_changes = 0
	_closed = 0


func _test_game_flow() -> void:
	_game.set("character_id", "")
	_game.set("auto_pack", false)
	_game.call("start_run", 5)
	_reset_log()
	_check(_backpack().cell_count() == 12 and _backpack().placed_items().is_empty(), "Ohne Kandidat startet der Lauf mit leerem Rucksack.")
	_check(_upgrades().owned_ids().is_empty(), "Ohne Gegenstände gibt es keine Upgrades.")
	# Kiste öffnen und einen Gegenstand wählen.
	_game.call("open_chest", Balance.RARITY_SILVER)
	_check(_state() == STATE_CHOOSING and paused, "Die Kiste öffnet die Wahl und pausiert.")
	var offers: Array = _game.get("current_offers")
	_check(offers.size() == 3 and str((offers[0] as Dictionary)["kind"]) == "item", "Die Kiste bietet Gegenstände an.")
	var wanted: Dictionary = offers[0]
	_game.call("choose_offer", 0)
	_check(_state() == STATE_PACKING and paused, "Nach der Wahl ist der Rucksack offen und das Spiel pausiert.")
	_check(_opened.size() == 1 and _opened[0] > 0, "backpack_opened nennt den neuen Gegenstand.")
	var uid: int = _opened[0] if not _opened.is_empty() else -1
	_check(str(_backpack().item(uid).get("id", "")) == str(wanted["id"]) and not _backpack().is_placed(uid), "Der gewählte Gegenstand liegt in der Ablage.")
	_check(_chosen.is_empty(), "Solange nichts eingeräumt ist, gibt es keine Meldung.")
	# Einräumen und abgleichen.
	_check(_backpack().auto_place(uid) or ItemDefs.is_bag(str(wanted["id"])), "Der Gegenstand lässt sich einräumen.")
	_game.call("sync_build")
	_check(_build_changes == 1, "sync_build sendet build_changed.")
	_check(_chosen.is_empty(), "Meldungen kommen erst beim Schließen.")
	_check(bool(_game.call("close_backpack")), "Der Rucksack lässt sich schließen.")
	_check(_state() == STATE_PLAYING and not paused and _closed == 1, "Nach dem Schließen läuft das Spiel weiter.")
	if ItemDefs.is_upgrade(str(wanted["id"])) and not ItemDefs.is_weapon_mod(str(wanted["id"])):
		_check(_chosen == ([str(wanted["id"])] as Array[String]), "Für das neue Upgrade kommt upgrade_chosen.")
		_check(_upgrades().get_level(str(wanted["id"])) == 2, "Silber gibt Stufe 2.")
	_check(not bool(_game.call("close_backpack")), "Ein geschlossener Rucksack lässt sich nicht noch einmal schließen.")
	# Mit der Taste öffnen: Verschieben meldet nichts Neues.
	_reset_log()
	_game.call("open_backpack")
	_check(_state() == STATE_PACKING and paused and _opened == ([-1] as Array[int]), "open_backpack öffnet ohne neuen Gegenstand.")
	_game.call("open_backpack")
	_check(_opened.size() == 1, "Ein offener Rucksack öffnet sich nicht noch einmal.")
	_game.call("close_backpack")
	_check(_chosen.is_empty() and _synergies.is_empty(), "Ohne Änderung gibt es beim Schließen keine Meldung.")
	# Die Ablage hat keine Grenze (Abschnitt 26): Auch eine volle Ablage hält den Rucksack nicht offen.
	_game.call("open_backpack")
	var extras: Array[int] = []
	for _i: int in 12:
		extras.append(_backpack().add_item("lifesteal"))
	_check(bool(_game.call("close_backpack")) and _state() == STATE_PLAYING and not paused, "Mit zwölf Gegenständen in der Ablage schließt der Rucksack.")
	_check(_backpack().storage_items().size() >= 12, "Die Gegenstände liegen weiter in der Ablage.")
	# Verkaufen gibt Punkte.
	_game.call("open_backpack")
	var points_before: int = int(_game.get("points"))
	_check(int(_game.call("sell_item", extras[0])) == 100, "Ein Gegenstand der Stufe 1 bringt 100 Punkte.")
	_check(int(_game.get("points")) == points_before + 100, "Die Punkte kommen aufs Konto.")
	_check(int(_game.call("sell_item", 99999)) == 0, "Unbekannte uid: Verkaufen gibt nichts.")
	_check(bool(_game.call("close_backpack")), "Nach dem Verkauf lässt sich der Rucksack schließen.")
	# Gewitterfront über den Rucksack: Blitz und Durchschlag wirken beide Legendär auf die Pistole.
	_game.call("start_run", 6)
	_reset_log()
	var fallback: Array = _game.get("loadout")
	_check(fallback.size() == 1 and int((fallback[0] as Dictionary)["uid"]) == 0 and str((fallback[0] as Dictionary)["id"]) == "pistol", "Ohne Waffe im Rucksack hält der Spieler die Dienstpistole (uid 0).")
	_near(float(_game.call("weapon_damage_multiplier", 0)), 1.0, "Die Dienstpistole macht den Grundschaden.")
	_near(float(_game.call("weapon_reload_multiplier", 0)), 1.0, "Sie lädt normal nach.")
	_game.call("open_backpack")
	# Der Rucksack ohne Kandidat hat die Felder (1, 1) bis (4, 3).
	var pistol: int = _backpack().add_item("pistol", 3)
	var chain: int = _backpack().add_item("chain_lightning", 5)
	var pierce: int = _backpack().add_item("pierce", 5)
	_check(_backpack().place(pistol, Vector2i(2, 2), 0) and _backpack().place(chain, Vector2i(1, 2), 0) and _backpack().place(pierce, Vector2i(2, 3), 0), "Pistole, Blitz und Durchschlag einräumen.")
	_game.call("sync_build")
	var hands: Array = _game.get("loadout")
	_check(hands.size() == 1 and int((hands[0] as Dictionary)["uid"]) == pistol, "Die Pistole aus dem Rucksack ist jetzt in der Hand.")
	_check(_upgrades().has_synergy("storm_front"), "Im Build ist die Gewitterfront aktiv.")
	_check(int(_game.call("bullet_level", pistol, "chain_lightning")) == 5 and int(_game.call("bullet_level", pistol, "burn")) == 0, "bullet_level nennt die Effekte dieser Waffe.")
	_near(float(_game.call("bullet_value", pistol, "pierce", "targets")), 5.0, "bullet_value nennt den Wert für diese Waffe.")
	_near(float(_game.call("bullet_value", 0, "pierce", "targets")), 0.0, "Für eine andere Waffe gilt der Effekt nicht.")
	_near(_upgrades().value("pierce", "targets"), 0.0, "Allgemein gilt er auch nicht.")
	_check(_upgrades().get_level("pierce") == 5, "In der Übersicht steht er trotzdem.")
	_near(float(_game.call("weapon_damage_multiplier", pistol)), 1.5, "Eine seltene Pistole macht den 1,5-fachen Schaden.")
	_check(_synergies.is_empty(), "Die Meldung kommt erst beim Schließen.")
	_game.call("close_backpack")
	_check(_synergies == (["storm_front"] as Array[String]), "Beim Schließen kommt synergy_unlocked.")
	_check(_chosen.has("chain_lightning") and _chosen.has("pierce"), "Beide Upgrades werden gemeldet.")
	# Herausnehmen schaltet die Verbindung ab, erneutes Einräumen meldet sie nicht noch einmal.
	_reset_log()
	_game.call("open_backpack")
	_backpack().store(pierce)
	_game.call("sync_build")
	_check(not _upgrades().has_synergy("storm_front") and _upgrades().get_level("pierce") == 0, "Aus dem Rucksack genommen wirkt der Gegenstand nicht mehr.")
	_backpack().place(pierce, Vector2i(2, 3), 0)
	_game.call("sync_build")
	_game.call("close_backpack")
	_check(_synergies.is_empty() and _chosen.is_empty(), "Herausnehmen und Zurücklegen meldet nichts doppelt.")
	# Ein Scheinwerfer und eine Ladehilfe auf der Pistole.
	_game.call("open_backpack")
	var spot: int = _backpack().add_item("spotlight", 1)
	_check(_backpack().place(spot, Vector2i(2, 1), 0), "Der Scheinwerfer liegt über der Pistole (Sterne nach unten).")
	var loader: int = _backpack().add_item("speed_loader", 2)
	_check(_backpack().place(loader, Vector2i(4, 2), 0), "Die Ladehilfe liegt rechts neben der Pistole.")
	_game.call("sync_build")
	_near(float(_game.call("weapon_damage_multiplier", pistol)), 1.5 * 1.1, "Seltene Pistole mit Scheinwerfer: 1,5 mal 1,1.")
	_near(float(_game.call("weapon_reload_multiplier", pistol)), 0.85, "Mit ungewöhnlicher Ladehilfe: 15 % schneller.")
	_game.call("close_backpack")
	# Statistik.
	var stats: Dictionary = _game.call("get_stats")
	_check((stats["items"] as Array).size() == 5 and str(stats["character"]) == "", "Die Statistik nennt Gegenstände und Kandidat.")
	_check((stats["synergies"] as Array).has("storm_front"), "Die Statistik nennt die Verbindung.")
	# Wandkauf: Der Gegenstand kommt in die Ablage und der Rucksack öffnet sich.
	_reset_log()
	var bought: int = int(_game.call("grant_item", "revolver", 1))
	_check(bought > 0 and _state() == STATE_PACKING and paused and _opened == ([bought] as Array[int]), "grant_item öffnet den Rucksack mit dem neuen Gegenstand.")
	_check(not _backpack().is_placed(bought), "Der gekaufte Gegenstand liegt in der Ablage.")
	_check(int(_game.call("grant_item", "revolver", 1)) == -1, "Bei offenem Rucksack gibt grant_item nichts.")
	_game.call("close_backpack")
	_check(int(_game.call("grant_item", "gibt_es_nicht", 1)) == -1 and _state() == STATE_PLAYING, "Unbekannte Gegenstände gibt es nicht.")


func _test_game_auto_pack() -> void:
	_game.set("character_id", "")
	_game.set("auto_pack", true)
	_game.call("start_run", 8)
	_reset_log()
	var opened: int = 0
	for round_index: int in 40:
		_game.call("open_chest", round_index % 3)
		if _state() != STATE_CHOOSING:
			_check(false, "Die Kiste öffnet die Wahl.")
			break
		_game.call("choose_offer", round_index % 3)
		opened += 1
		if _state() != STATE_PLAYING or paused:
			_check(false, "Mit auto_pack geht es nach der Wahl sofort weiter.")
			break
	_check(opened == 40 and _opened.is_empty(), "Mit auto_pack öffnet sich der Rucksack nie.")
	# Mit auto_pack kombiniert sich alles von selbst: Kein Gegenstand liegt doppelt in gleicher Rarität.
	var seen_pairs: Dictionary = {}
	for entry: Dictionary in _backpack().placed_items():
		var pair_key: String = "%s:%d" % [str(entry["id"]), int(entry["level"])]
		if seen_pairs.has(pair_key) and int(entry["level"]) < Balance.UPGRADE_MAX_LEVEL:
			_check(false, "auto_pack lässt kein kombinierbares Paar liegen: %s." % pair_key)
		seen_pairs[pair_key] = true
	_check(_backpack().cell_count() > 12, "In 40 Kisten kam mindestens ein Rucksack-Teil (Garantie), der Rucksack ist gewachsen.")
	_check(_backpack().hands_used() <= Balance.PLAYER_HANDS, "Auch mit auto_pack sind höchstens zwei Hände belegt.")
	_check((_game.get("loadout") as Array).size() >= 1, "Der Spieler hält immer mindestens eine Waffe.")
	_check(_upgrades().owned_ids().size() >= 3, "Nach 40 Kisten wirken mehrere Upgrades.")
	_check(_chosen.size() >= 3, "Auch mit auto_pack kommt upgrade_chosen.")
	_check(_backpack().cell_count() >= 12, "Der Rucksack ist nicht geschrumpft.")
	# Was nirgends passt, bleibt in der Ablage, gleich wie viel dort liegt (Abschnitt 26: Verkauft
	# wird nichts mehr). Die Schrotflinte braucht beide Hände, jede weitere Waffe wartet.
	_game.call("start_run", 9)
	var points_before: int = int(_game.get("points"))
	var waiting: Array = [["shotgun", 1], ["pistol", 1], ["pistol", 2], ["pistol", 3], ["pistol", 4], ["revolver", 1], ["revolver", 2], ["revolver", 3]]
	for pair: Array in waiting:
		_game.call("open_chest", Balance.RARITY_BRONZE)
		(_game.get("current_offers") as Array)[0] = {"kind": "item", "id": str(pair[0]), "level": int(pair[1]), "owned_level": 0}
		_game.call("choose_offer", 0)
	_check(_backpack().placed_items().size() == 1 and _backpack().storage_items().size() == 7, "Sieben Waffen ohne freie Hand warten in der Ablage, waren %d." % _backpack().storage_items().size())
	_check(int(_game.get("points")) == points_before and _state() == STATE_PLAYING, "auto_pack verkauft nichts, auch wenn viel in der Ablage liegt.")
	_game.set("auto_pack", false)


func _test_game_character() -> void:
	_game.set("character_id", "technician")
	_game.call("start_run", 3)
	_check(int(_game.get("points")) == 500, "Der Tontechniker startet mit 500 Punkten.")
	var tech: Array = _game.get("loadout")
	_check(tech.size() == 1 and str((tech[0] as Dictionary)["id"]) == "pistol" and int((tech[0] as Dictionary)["uid"]) > 0, "Der Tontechniker hält seine Pistole aus dem Rucksack.")
	var tech_uid: int = int((tech[0] as Dictionary)["uid"])
	_check(int(_game.call("bullet_level", tech_uid, "chain_lightning")) == 1, "Der Starkstrom-Sponsor wirkt auf seine Pistole.")
	_near(float(_game.call("weapon_damage_multiplier", tech_uid)), 1.1, "Der Scheinwerfer gibt 10 % Schaden.")
	_check(_upgrades().get_level("chain_lightning") == 1, "Der Starkstrom-Sponsor steht in der Übersicht.")
	_game.set("character_id", "janitor")
	_game.call("start_run", 3)
	_near(_upgrades().bonus_max_hp(), 30.0, "Der Hausmeister hat 30 Leben mehr.")
	_near(_upgrades().speed_multiplier(), 0.95, "Der Hausmeister ist 5 % langsamer.")
	_check(_upgrades().get_level("reload_shockwave") == 1, "Der Hausmeister startet mit der Werbepause.")
	var janitor: Array = _game.get("loadout")
	_check(janitor.size() == 1 and str((janitor[0] as Dictionary)["id"]) == "shotgun" and int((janitor[0] as Dictionary)["hands"]) == 2, "Der Hausmeister hält die Schrotflinte in beiden Händen.")
	_check(int(_game.get("points")) == 0, "Der Hausmeister startet ohne Punkte.")
	_game.set("character_id", "intern")
	_game.call("start_run", 3)
	var intern: Array = _game.get("loadout")
	_check(intern.size() == 2 and str((intern[0] as Dictionary)["id"]) == "smg" and str((intern[1] as Dictionary)["id"]) == "pistol", "Die Praktikantin hält MP und Pistole.")
	_game.set("character_id", "")
	_game.call("start_run", 3)
	_near(_upgrades().bonus_max_hp(), 0.0, "Ohne Kandidat gibt es kein Zusatz-Leben.")
	_check((_game.get("loadout") as Array).size() == 1 and int(((_game.get("loadout") as Array)[0] as Dictionary)["uid"]) == 0, "Ohne Kandidat hält der Spieler die Dienstpistole.")


## Kopie einer Feldliste, zeilenweise sortiert (zum Vergleichen von Sternmustern).
func _sorted(cells: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = cells.duplicate()
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


func _near(value: float, expected: float, message: String) -> void:
	_check(absf(value - expected) < 0.0001, "%s (erwartet %s, war %s)" % [message, expected, value])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
