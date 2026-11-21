extends RefCounted
## Rucksack eines Laufs (Abschnitte 16 bis 18): Raster, eingeräumte Gegenstände, Ablage und alle
## Regeln dazu (Einräumen, Drehen, Kombinieren, Vergrößern, Hände, Sterne, Bewaffnung).
## Reine Logik ohne Nodes. Einbinden mit:
##   const BackpackState := preload("res://scripts/core/backpack_state.gd")
##
## Raster: höchstens COLS mal ROWS Felder, davon existieren nur die Felder des Rucksacks
## (Startform des Kandidaten plus eingeräumte Rucksack-Teile). x läuft nach rechts, y nach unten.
##
## Ein Gegenstand ist ein Dictionary:
##   { "uid": int, "id": String, "level": int, "rot": int, "placed": bool, "pos": Vector2i }
## uid ist je Rucksack eindeutig und größer als 0. "level" ist die Rarität (1 bis 5). Nicht
## eingeräumte Gegenstände liegen in der Ablage (placed = false) und wirken nicht. pos ist die
## linke obere Ecke der gedrehten Form.
##
## Waffen und Hände: Jede eingeräumte Waffe hält der Spieler in der Hand. Zusammen dürfen die
## eingeräumten Waffen höchstens Balance.PLAYER_HANDS Hände brauchen, sonst passt die Waffe nicht.
##
## Sterne: Gegenstände mit Sternfeldern (ItemDefs.stars) wirken nur für die Waffen, die eines
## ihrer Sternfelder belegen. Ohne Waffe auf einem Stern wirken sie nicht. Die Sterne der
## Kamera-Gegenstände zielen genauso auf Kameras (Abschnitt 22.1), der Stern der Wiederholung auf
## einen Upgrade-Gegenstand oder eine Kamera.
##
## Kameras: Jede eingeräumte Kamera ist ein eigenes Exemplar (cameras()). Sie wirken nicht über
## UpgradeState, sondern über Game.cameras.
##
## Jedes wirkende Exemplar zählt einzeln: Mehrere gleiche Gegenstände addieren ihre Wirkung
## (wie genau, steht je Wert in UpgradeDefs.combined_value).

const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")

const COLS: int = Balance.BACKPACK_COLS
const ROWS: int = Balance.BACKPACK_ROWS
const STORAGE_CAPACITY: int = Balance.BACKPACK_STORAGE
const NEIGHBOR_STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Vorhandene Felder des Rasters: Vector2i -> true.
var _cells: Dictionary = {}
## Alle Gegenstände (eingeräumt und in der Ablage) in der Reihenfolge des Erwerbs.
var _items: Array[Dictionary] = []
var _next_uid: int = 1


# --- Raster ---------------------------------------------------------------------------

## Legt die Startform fest und leert den Rucksack. Felder außerhalb von COLS mal ROWS entfallen.
func setup(start_cells: Array[Vector2i]) -> void:
	_cells.clear()
	_items.clear()
	_next_uid = 1
	for cell: Vector2i in start_cells:
		if in_bounds(cell):
			_cells[cell] = true


static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < COLS and cell.y < ROWS


## Gehört dieses Feld zum Rucksack?
func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


func cell_count() -> int:
	return _cells.size()


## Alle Felder des Rucksacks, zeilenweise sortiert.
func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in _cells:
		result.append(cell)
	result.sort_custom(_cell_before)
	return result


## Felder des Rucksacks, auf denen nichts liegt.
func free_cell_count() -> int:
	return _cells.size() - _occupancy().size()


## uid des Gegenstands auf diesem Feld, -1 wenn das Feld frei ist oder nicht existiert.
func occupant(cell: Vector2i) -> int:
	return int(_occupancy().get(cell, -1))


# --- Gegenstände ----------------------------------------------------------------------

## Neuer Gegenstand in die Ablage. Gibt seine uid zurück, -1 bei unbekannter ID.
func add_item(id: String, level: int = 1) -> int:
	if not ItemDefs.has(id):
		return -1
	var uid: int = _next_uid
	_next_uid += 1
	# "level" ist die Rarität (1 = Gewöhnlich bis 5 = Legendär). Rucksack-Teile haben keine.
	var item_level: int = clampi(level, 1, Balance.UPGRADE_MAX_LEVEL) if ItemDefs.has_rarity(id) else 1
	_items.append({"uid": uid, "id": id, "level": item_level, "rot": 0, "placed": false, "pos": Vector2i.ZERO})
	return uid


## Kopie des Gegenstands mit dieser uid, leer wenn es ihn nicht gibt.
func item(uid: int) -> Dictionary:
	var index: int = _index_of(uid)
	return _items[index].duplicate() if index >= 0 else {}


func has_item(uid: int) -> bool:
	return _index_of(uid) >= 0


func is_placed(uid: int) -> bool:
	var index: int = _index_of(uid)
	return index >= 0 and bool(_items[index]["placed"])


## Kopien aller eingeräumten Gegenstände in der Reihenfolge des Erwerbs.
func placed_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _items:
		if bool(entry["placed"]):
			result.append(entry.duplicate())
	return result


## Kopien der Gegenstände in der Ablage in der Reihenfolge des Erwerbs.
func storage_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _items:
		if not bool(entry["placed"]):
			result.append(entry.duplicate())
	return result


## Liegt mehr in der Ablage, als hineinpasst? Dann darf der Rucksack nicht geschlossen werden.
func storage_overflow() -> bool:
	return storage_items().size() > STORAGE_CAPACITY


## Höchste Rarität (1 bis 5), in der dieser Gegenstand im Rucksack oder in der Ablage liegt.
## 0, wenn er nirgends liegt.
func highest_level(id: String) -> int:
	var best: int = 0
	for entry: Dictionary in _items:
		if str(entry["id"]) == id:
			best = maxi(best, int(entry["level"]))
	return best


## Felder, die der Gegenstand belegt (leer, wenn er in der Ablage liegt).
func cells_of(uid: int) -> Array[Vector2i]:
	var index: int = _index_of(uid)
	if index < 0 or not bool(_items[index]["placed"]):
		return []
	var entry: Dictionary = _items[index]
	return shape_at(str(entry["id"]), entry["pos"] as Vector2i, int(entry["rot"]))


## Felder, die die Form von id an pos mit Drehung rot belegen würde.
static func shape_at(id: String, pos: Vector2i, rot: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in ItemDefs.cells(id, rot):
		result.append(pos + cell)
	return result


## Sternfelder, die id an pos mit Drehung rot hätte (auch außerhalb des Rucksacks).
static func stars_at(id: String, pos: Vector2i, rot: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in ItemDefs.stars(id, rot):
		result.append(pos + cell)
	return result


# --- Hände ----------------------------------------------------------------------------

## Hände, die die eingeräumten Waffen zusammen brauchen. exclude_uid zählt nicht mit.
func hands_used(exclude_uid: int = -1) -> int:
	var total: int = 0
	for entry: Dictionary in _items:
		if bool(entry["placed"]) and int(entry["uid"]) != exclude_uid:
			total += ItemDefs.hands(str(entry["id"]))
	return total


## Hat der Spieler für diesen Gegenstand noch genug Hände frei? Immer true für alles, was keine
## Waffe ist. Eine schon eingeräumte Waffe zählt dabei nicht gegen sich selbst.
func has_free_hands(uid: int) -> bool:
	var index: int = _index_of(uid)
	if index < 0:
		return false
	var needed: int = ItemDefs.hands(str(_items[index]["id"]))
	return needed == 0 or hands_used(uid) + needed <= Balance.PLAYER_HANDS


# --- Einräumen, Bewegen, Entfernen ----------------------------------------------------

## Passt der Gegenstand an diese Stelle?
## Waffen, Upgrade-Gegenstände und Verstärker: alle Felder gehören zum Rucksack und sind frei
## (eigene Felder zählen als frei, damit ein Gegenstand verschoben werden kann). Waffen brauchen
## dazu freie Hände (has_free_hands).
## Rucksack-Teile: alle Felder liegen im Raster, existieren noch nicht, und mindestens eines grenzt
## an ein vorhandenes Feld.
func can_place(uid: int, pos: Vector2i, rot: int) -> bool:
	var index: int = _index_of(uid)
	if index < 0:
		return false
	var id: String = str(_items[index]["id"])
	var wanted: Array[Vector2i] = shape_at(id, pos, rot)
	if wanted.is_empty():
		return false
	if ItemDefs.is_bag(id):
		var touches: bool = false
		for cell: Vector2i in wanted:
			if not in_bounds(cell) or _cells.has(cell):
				return false
			for step: Vector2i in NEIGHBOR_STEPS:
				if _cells.has(cell + step):
					touches = true
		return touches
	if not has_free_hands(uid):
		return false
	var taken: Dictionary = _occupancy()
	for cell: Vector2i in wanted:
		if not _cells.has(cell):
			return false
		var other: int = int(taken.get(cell, -1))
		if other != -1 and other != uid:
			return false
	return true


## Räumt den Gegenstand ein oder verschiebt ihn. Ein Rucksack-Teil vergrößert das Raster und ist
## danach verbraucht. Gibt false zurück (und ändert nichts), wenn er dort nicht passt.
func place(uid: int, pos: Vector2i, rot: int) -> bool:
	if not can_place(uid, pos, rot):
		return false
	var index: int = _index_of(uid)
	var id: String = str(_items[index]["id"])
	if ItemDefs.is_bag(id):
		for cell: Vector2i in shape_at(id, pos, rot):
			_cells[cell] = true
		_items.remove_at(index)
		return true
	_items[index]["placed"] = true
	_items[index]["pos"] = pos
	_items[index]["rot"] = posmod(rot, 4)
	return true


## Erste passende Stelle für den Gegenstand (zeilenweise, Drehungen 0 bis 3):
## { "pos": Vector2i, "rot": int }, leer wenn er nirgends passt.
func find_spot(uid: int) -> Dictionary:
	if not has_item(uid):
		return {}
	for rot: int in 4:
		for y: int in ROWS:
			for x: int in COLS:
				if can_place(uid, Vector2i(x, y), rot):
					return {"pos": Vector2i(x, y), "rot": rot}
	return {}


## Räumt den Gegenstand an die erste passende Stelle. false, wenn er nirgends passt.
func auto_place(uid: int) -> bool:
	var spot: Dictionary = find_spot(uid)
	if spot.is_empty():
		return false
	return place(uid, spot["pos"] as Vector2i, int(spot["rot"]))


## Nimmt einen eingeräumten Gegenstand heraus und legt ihn in die Ablage.
func store(uid: int) -> bool:
	var index: int = _index_of(uid)
	if index < 0 or not bool(_items[index]["placed"]):
		return false
	_items[index]["placed"] = false
	return true


## Merkt sich die Drehung eines Gegenstands in der Ablage (nur Anzeige).
func set_rotation(uid: int, rot: int) -> void:
	var index: int = _index_of(uid)
	if index >= 0 and not bool(_items[index]["placed"]):
		_items[index]["rot"] = posmod(rot, 4)


## Entfernt den Gegenstand ganz (Verkaufen) und gibt ihn zurück. Leer, wenn es ihn nicht gibt.
func remove(uid: int) -> Dictionary:
	var index: int = _index_of(uid)
	if index < 0:
		return {}
	var entry: Dictionary = _items[index]
	_items.remove_at(index)
	return entry


## uid des eingeräumten Gegenstands auf cell, mit dem sich uid kombinieren lässt: derselbe
## Gegenstand in derselben Rarität, ein anderer als uid, noch nicht Legendär. Sonst -1.
func merge_target(uid: int, cell: Vector2i) -> int:
	var index: int = _index_of(uid)
	if index < 0 or not ItemDefs.has_rarity(str(_items[index]["id"])):
		return -1
	var other: int = occupant(cell)
	if other == -1 or other == uid:
		return -1
	var other_index: int = _index_of(other)
	if str(_items[other_index]["id"]) != str(_items[index]["id"]):
		return -1
	if int(_items[other_index]["level"]) != int(_items[index]["level"]):
		return -1
	if int(_items[other_index]["level"]) >= Balance.UPGRADE_MAX_LEVEL:
		return -1
	return other


## Kombiniert uid mit target: target steigt um eine Rarität, uid verschwindet.
func merge(uid: int, target_uid: int) -> bool:
	var target_index: int = _index_of(target_uid)
	if target_index < 0 or not bool(_items[target_index]["placed"]):
		return false
	var first_cell: Array[Vector2i] = cells_of(target_uid)
	if first_cell.is_empty() or merge_target(uid, first_cell[0]) != target_uid:
		return false
	_items[target_index]["level"] = int(_items[target_index]["level"]) + 1
	_items.remove_at(_index_of(uid))
	return true


## uid eines eingeräumten Gegenstands, mit dem sich uid kombinieren lässt (derselbe Gegenstand,
## dieselbe Rarität), -1 wenn es keinen gibt.
func find_merge_partner(uid: int) -> int:
	var index: int = _index_of(uid)
	if index < 0:
		return -1
	for entry: Dictionary in _items:
		if not bool(entry["placed"]) or int(entry["uid"]) == uid:
			continue
		var cells_here: Array[Vector2i] = cells_of(int(entry["uid"]))
		if not cells_here.is_empty() and merge_target(uid, cells_here[0]) == int(entry["uid"]):
			return int(entry["uid"])
	return -1


# --- Nachbarschaft und Sterne ---------------------------------------------------------

## uids der eingeräumten Gegenstände, die mit einer Kante an uid grenzen (ohne Doppelte).
func neighbors(uid: int) -> Array[int]:
	var result: Array[int] = []
	var taken: Dictionary = _occupancy()
	for cell: Vector2i in cells_of(uid):
		for step: Vector2i in NEIGHBOR_STEPS:
			var other: int = int(taken.get(cell + step, -1))
			if other != -1 and other != uid and not result.has(other):
				result.append(other)
	return result


func are_neighbors(uid_a: int, uid_b: int) -> bool:
	return neighbors(uid_a).has(uid_b)


## Zahl der freien Felder des Rucksacks, die mit einer Kante an uid grenzen.
func free_neighbor_cells(uid: int) -> int:
	var seen: Dictionary = {}
	var taken: Dictionary = _occupancy()
	for cell: Vector2i in cells_of(uid):
		for step: Vector2i in NEIGHBOR_STEPS:
			var next: Vector2i = cell + step
			if _cells.has(next) and not taken.has(next):
				seen[next] = true
	return seen.size()


## Sternfelder eines eingeräumten Gegenstands (leer in der Ablage und ohne Sterne). Die Felder
## können außerhalb des Rucksacks liegen.
func star_cells_of(uid: int) -> Array[Vector2i]:
	var index: int = _index_of(uid)
	if index < 0 or not bool(_items[index]["placed"]):
		return []
	var entry: Dictionary = _items[index]
	return stars_at(str(entry["id"]), entry["pos"] as Vector2i, int(entry["rot"]))


## uids der eingeräumten Gegenstände, auf die die Sterne von uid wirken (ohne Doppelte): bei
## Waffen-Sternen die Waffen auf den Sternfeldern, bei Kamera-Sternen die Kameras, bei der
## Wiederholung die Upgrade-Gegenstände und Kameras.
func star_targets(uid: int) -> Array[int]:
	var result: Array[int] = []
	var index: int = _index_of(uid)
	if index < 0:
		return result
	var owner_id: String = str(_items[index]["id"])
	var taken: Dictionary = _occupancy()
	for cell: Vector2i in star_cells_of(uid):
		var other: int = int(taken.get(cell, -1))
		if other == -1 or other == uid or result.has(other):
			continue
		if ItemDefs.star_hits(owner_id, str(_items[_index_of(other)]["id"])):
			result.append(other)
	return result


## Liegt auf diesem Sternfeld von uid etwas, worauf der Stern wirkt? (Für die Anzeige: gefüllter
## oder leerer Stern.)
func is_star_lit(uid: int, cell: Vector2i) -> bool:
	if not star_cells_of(uid).has(cell):
		return false
	var other: int = occupant(cell)
	if other == -1 or other == uid:
		return false
	return ItemDefs.star_hits(str(_items[_index_of(uid)]["id"]), str(_items[_index_of(other)]["id"]))


## uids der eingeräumten Stern-Gegenstände, die auf diesen Gegenstand wirken: bei einer Waffe
## ihre Kugel-Effekte und Verstärker, bei einem Upgrade-Gegenstand die Wiederholungen, bei einer
## Kamera ihre Kamera-Gegenstände und die Wiederholungen.
func mods_of(target_uid: int) -> Array[int]:
	var result: Array[int] = []
	for entry: Dictionary in _items:
		if bool(entry["placed"]) and ItemDefs.has_stars(str(entry["id"])) and star_targets(int(entry["uid"])).has(target_uid):
			result.append(int(entry["uid"]))
	return result


## Raritäten, mit denen ein eingeräumter Upgrade-Gegenstand oder eine eingeräumte Kamera zählt:
## die eigene und je Wiederholung, deren Stern darauf liegt, noch einmal (höchstens in der Rarität
## der Wiederholung). Leer für alles andere.
func copy_levels(uid: int) -> Array[int]:
	var index: int = _index_of(uid)
	var levels: Array[int] = []
	if index < 0 or not bool(_items[index]["placed"]):
		return levels
	if not ItemDefs.is_upgrade(str(_items[index]["id"])) and not ItemDefs.is_camera(str(_items[index]["id"])):
		return levels
	var level: int = int(_items[index]["level"])
	levels.append(level)
	for mod_uid: int in mods_of(uid):
		var mod: Dictionary = _items[_index_of(mod_uid)]
		if ItemDefs.is_replay(str(mod["id"])):
			levels.append(mini(level, int(mod["level"])))
	return levels


## Wirkt dieser Gegenstand gerade? Eingeräumt, und wenn er Sterne hat, liegt etwas darauf, worauf
## sie zielen (Waffe, Kamera oder bei der Wiederholung ein Upgrade-Gegenstand oder eine Kamera).
func is_active(uid: int) -> bool:
	var index: int = _index_of(uid)
	if index < 0 or not bool(_items[index]["placed"]):
		return false
	if not ItemDefs.has_stars(str(_items[index]["id"])):
		return true
	return not star_targets(uid).is_empty()


# --- Bewaffnung und Wirkung -----------------------------------------------------------

## Die Waffen in der Hand: eingeräumte Waffen von links nach rechts (bei gleicher Spalte von oben
## nach unten), die erste ist die linke Hand. Je Waffe:
##   { "uid": int, "id": String, "level": int, "hands": int,
##     "copies": Dictionary (upgrade_id -> Array[int] mit den Raritäten der Stern-Gegenstände,
##               die auf diese Waffe wirken),
##     "damage": float, "reload": float (Zusatzwerte aus Verstärkern auf dieser Waffe) }
## Leer, wenn keine Waffe eingeräumt ist (Game gibt dem Spieler dann die Dienstpistole).
func loadout() -> Array[Dictionary]:
	var weapons: Array[Dictionary] = []
	for entry: Dictionary in _items:
		if bool(entry["placed"]) and ItemDefs.is_weapon(str(entry["id"])):
			weapons.append(entry)
	weapons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pos_a: Vector2i = a["pos"] as Vector2i
		var pos_b: Vector2i = b["pos"] as Vector2i
		if pos_a.x != pos_b.x:
			return pos_a.x < pos_b.x
		if pos_a.y != pos_b.y:
			return pos_a.y < pos_b.y
		return int(a["uid"]) < int(b["uid"]))
	var result: Array[Dictionary] = []
	for weapon: Dictionary in weapons:
		var uid: int = int(weapon["uid"])
		var copies: Dictionary = {}
		var damage: float = 0.0
		var reload: float = 0.0
		for mod_uid: int in mods_of(uid):
			var mod: Dictionary = _items[_index_of(mod_uid)]
			var mod_id: String = str(mod["id"])
			if ItemDefs.is_upgrade(mod_id):
				if not copies.has(mod_id):
					copies[mod_id] = []
				(copies[mod_id] as Array).append_array(copy_levels(mod_uid))
			elif ItemDefs.stat(mod_id) == "damage":
				damage += ItemDefs.stat_amount(mod_id, int(mod["level"]))
			elif ItemDefs.stat(mod_id) == "reload":
				reload += ItemDefs.stat_amount(mod_id, int(mod["level"]))
		result.append({
			"uid": uid, "id": str(weapon["id"]), "level": int(weapon["level"]),
			"hands": ItemDefs.hands(str(weapon["id"])), "copies": copies,
			"damage": damage, "reload": minf(reload, Balance.RELOAD_BONUS_MAX),
		})
	return result


## Die Kameras im Rucksack (Abschnitt 22.1): je Exemplar ein Eintrag, in der Reihenfolge des
## Erwerbs. Eine Wiederholung auf einer Kamera ergibt ein zweites Exemplar, höchstens in der
## Rarität der Wiederholung. Es hat dieselben Kamera-Gegenstände wie das erste. Eine Wiederholung
## auf einem Kamera-Gegenstand zählt ihn doppelt (copy_levels). Je Eintrag:
##   { "key": String    eindeutig je Exemplar: "<uid>:<nummer>", das erste Exemplar hat ":0"
##     "uid": int       uid der Kamera im Rucksack
##     "copy": int      0 = die Kamera selbst, ab 1 die Exemplare aus Wiederholungen
##     "id": String     Kameratyp (CameraDefs)
##     "level": int     Rarität dieses Exemplars
##     "mods": Dictionary  Kamera-Gegenstände, deren Sterne auf der Kamera liegen:
##                         mod_id -> Array[int] mit der Rarität jedes Exemplars }
## Die Sendeleitung (ohne Sterne) steht nicht hier, sondern in global_copies().
func cameras() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _items:
		var id: String = str(entry["id"])
		if not bool(entry["placed"]) or not ItemDefs.is_camera(id):
			continue
		var uid: int = int(entry["uid"])
		var mods: Dictionary = {}
		for mod_uid: int in mods_of(uid):
			var mod_id: String = str(_items[_index_of(mod_uid)]["id"])
			if not ItemDefs.is_camera_mod(mod_id):
				continue
			if not mods.has(mod_id):
				mods[mod_id] = []
			(mods[mod_id] as Array).append_array(copy_levels(mod_uid))
		var levels: Array[int] = copy_levels(uid)
		for copy: int in levels.size():
			result.append({
				"key": "%d:%d" % [uid, copy], "uid": uid, "copy": copy, "id": id,
				"level": levels[copy], "mods": mods.duplicate(true),
			})
	return result


## Upgrade-Gegenstände ohne Sterne, die für den Spieler als Ganzes wirken:
## upgrade_id -> Array[int] mit der Rarität jedes eingeräumten Exemplars.
func global_copies() -> Dictionary:
	var copies: Dictionary = {}
	for entry: Dictionary in _items:
		var id: String = str(entry["id"])
		if not bool(entry["placed"]) or not ItemDefs.is_upgrade(id) or ItemDefs.has_stars(id):
			continue
		if not copies.has(id):
			copies[id] = []
		(copies[id] as Array).append_array(copy_levels(int(entry["uid"])))
	return copies


## Beste wirkende Rarität je Upgrade: upgrade_id -> 1 bis 5, in der Reihenfolge des Erwerbs.
## Für Übersichten (HUD, Game Over) und die Kisten. Stern-Gegenstände ohne Ziel fehlen. Kameras
## sind keine Upgrades und stehen nicht hier (siehe cameras()).
func upgrade_levels() -> Dictionary:
	var levels: Dictionary = {}
	for entry: Dictionary in _items:
		var id: String = str(entry["id"])
		if not ItemDefs.is_upgrade(id) or not is_active(int(entry["uid"])):
			continue
		levels[id] = maxi(int(levels.get(id, 0)), int(entry["level"]))
	return levels


## Aktive Verbindungen (Synergien aus UpgradeDefs): Eine Waffe hat alle beteiligten Gegenstände
## in der verlangten Rarität auf sich wirken (Gegenstände ohne Sterne zählen für jede Waffe).
func active_synergies() -> Array[String]:
	var result: Array[String] = []
	var general: Dictionary = global_copies()
	var weapons: Array[Dictionary] = loadout()
	for synergy_id: String in UpgradeDefs.synergy_ids():
		var requires: Dictionary = UpgradeDefs.synergy_requirements(synergy_id)
		if requires.is_empty():
			continue
		for weapon: Dictionary in weapons:
			var copies: Dictionary = weapon["copies"]
			var enough: bool = true
			for upgrade_id: String in requires:
				var best: int = 0
				for level: Variant in (copies.get(upgrade_id, []) as Array) + (general.get(upgrade_id, []) as Array):
					best = maxi(best, int(level))
				if best < int(requires[upgrade_id]):
					enough = false
			if enough:
				result.append(synergy_id)
				break
	return result


## Paare [uid_a, uid_b] von Stern-Gegenständen, die zur selben Verbindung gehören und auf dieselbe
## Waffe wirken (für die Anzeige, auch wenn die Raritäten noch nicht reichen).
func synergy_links() -> Array[Array]:
	var links: Array[Array] = []
	for synergy_id: String in UpgradeDefs.synergy_ids():
		var ids: Array = UpgradeDefs.synergy_requirements(synergy_id).keys()
		for weapon: Dictionary in loadout():
			var mods: Array[int] = mods_of(int(weapon["uid"]))
			for i: int in mods.size():
				for j: int in range(i + 1, mods.size()):
					var id_a: String = str(_items[_index_of(mods[i])]["id"])
					var id_b: String = str(_items[_index_of(mods[j])]["id"])
					var pair: Array = [mini(mods[i], mods[j]), maxi(mods[i], mods[j])]
					if id_a != id_b and ids.has(id_a) and ids.has(id_b) and not links.has(pair):
						links.append(pair)
	return links


## Zusatzwerte, die für den Spieler als Ganzes gelten: { "damage": 0.0, "reload": 0.0,
## "points": float }. Schaden und Nachladen aus Verstärkern gelten je Waffe (siehe loadout),
## deshalb stehen sie hier auf 0.
func stats() -> Dictionary:
	var totals: Dictionary = {"damage": 0.0, "reload": 0.0, "points": 0.0}
	for entry: Dictionary in _items:
		var id: String = str(entry["id"])
		if bool(entry["placed"]) and ItemDefs.stat(id) == "points":
			totals["points"] = float(totals["points"]) + ItemDefs.stat_amount(id, int(entry["level"]))
	return totals


## Beitrag eines Verstärkers zu seinem Wert (für die Anzeige): sein Betrag, solange er wirkt.
func stat_contribution(uid: int) -> float:
	var index: int = _index_of(uid)
	if index < 0 or ItemDefs.stat(str(_items[index]["id"])).is_empty() or not is_active(uid):
		return 0.0
	return ItemDefs.stat_amount(str(_items[index]["id"]), int(_items[index]["level"]))


## Schreibt die für den Spieler als Ganzes geltenden Upgrades, die Verbindungen und Zusatzwerte
## in upgrades. extra sind weitere Zusatzwerte (vom Kandidaten), sie addieren sich zu stats().
## Die Stern-Gegenstände stecken nicht in den Werten (sie gelten je Waffe), wohl aber in den
## Stufen für die Übersicht.
func apply_to(upgrades: UpgradeState, extra: Dictionary = {}) -> void:
	var totals: Dictionary = stats()
	for key: String in extra:
		totals[key] = float(totals.get(key, 0.0)) + float(extra[key])
	upgrades.set_derived(upgrade_levels(), active_synergies(), totals, global_copies())


## Übersicht für Game Over: je eingeräumtem Gegenstand { "id", "name", "level" }.
func summary() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Dictionary in _items:
		if bool(entry["placed"]):
			rows.append({"id": str(entry["id"]), "name": ItemDefs.display_name(str(entry["id"])), "level": int(entry["level"])})
	return rows


# --- Intern ---------------------------------------------------------------------------

func _index_of(uid: int) -> int:
	for i: int in _items.size():
		if int(_items[i]["uid"]) == uid:
			return i
	return -1


## Belegte Felder: Vector2i -> uid.
func _occupancy() -> Dictionary:
	var taken: Dictionary = {}
	for entry: Dictionary in _items:
		if not bool(entry["placed"]):
			continue
		for cell: Vector2i in shape_at(str(entry["id"]), entry["pos"] as Vector2i, int(entry["rot"])):
			taken[cell] = int(entry["uid"])
	return taken


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
