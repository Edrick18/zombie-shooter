extends RefCounted
## Kandidaten (Abschnitt 16): Namen, Eigenheiten, Startwaffen, Start-Rucksack und Start-Gegenstände.
## Reine Daten, keine Nodes.
## Einbinden mit: const CharacterDefs := preload("res://scripts/core/character_defs.gd")

const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")

## Kein Kandidat: Grundwerte ohne Eigenheiten, leerer Rucksack in Standardform, nur die
## Dienstpistole. So starten Tests und jeder Lauf ohne Kandidatenwahl.
const NONE: String = ""
## Vorauswahl in der Kandidatenwahl.
const DEFAULT: String = "janitor"
## Start-Rucksack ohne Kandidat.
const DEFAULT_BAG: Array[String] = ["####", "####", "####"]

## Feste Reihenfolge (Kandidatenwahl von links nach rechts).
const ORDER: Array[String] = ["janitor", "intern", "technician"]

## Je Kandidat:
## name, tagline  Name und Spruch für die Kandidatenwahl
## text           Eigenheiten in einem Satz
## color          Farbe der Karte
## extra          Zusatzwerte wie in UpgradeState.set_derived: "max_hp" (Leben), "speed", "damage",
##                "reload", "points" (Bruchteile)
## start_points   Punkte zu Beginn des Laufs
## bag            Zeilen des Start-Rucksacks, "#" = Feld, "." = kein Feld. Die Form wird im Raster
##                von 7 mal 5 Feldern mittig ausgerichtet.
## items          Start-Gegenstände, auch die Waffen: [id, Rarität] wird an die erste passende
##                Stelle geräumt, [id, Rarität, x, y, Drehung] an eine feste Stelle (x und y in den
##                Feldern von bag, also ohne die Ausrichtung im Raster). Feste Stellen sorgen dafür,
##                dass Sterne von Anfang an auf der Waffe liegen.
const CHARACTERS: Dictionary = {
	"janitor": {
		"name": "Der Hausmeister",
		"tagline": "Hat schon Schlimmeres aufgewischt.",
		"text": "130 Leben, aber 5 % langsamer. Startet mit Schrotflinte (zwei Hände) und Werbepause.",
		"color": Color(1.0, 0.56, 0.1),
		"extra": {"max_hp": 30.0, "speed": -0.05},
		"start_points": 0,
		"bag": ["####", "####", "####"],
		"items": [["shotgun", 1, 0, 0, 0], ["reload_shockwave", 1]],
	},
	"intern": {
		"name": "Die Praktikantin",
		"tagline": "Unbezahlt, übermotiviert, unaufhaltsam.",
		"text": "80 Leben, dafür 10 % schneller. Startet beidhändig mit Maschinenpistole und Dienstpistole und mit Turbo-Turnschuhen.",
		"color": Color(1.0, 0.35, 0.75),
		"extra": {"max_hp": -20.0, "speed": 0.10},
		"start_points": 0,
		"bag": ["######", "######"],
		"items": [["smg", 1, 0, 0, 0], ["pistol", 1, 2, 0, 0], ["speed", 1]],
	},
	"technician": {
		"name": "Der Tontechniker",
		"tagline": "Eins, zwei. Eins, zwei. Stirb.",
		"text": "100 Leben und 500 Punkte. Startet mit Dienstpistole, auf die Starkstrom-Sponsor und Scheinwerfer wirken.",
		"color": Color(0.25, 0.85, 1.0),
		"extra": {},
		"start_points": 500,
		"bag": [".##.", "####", "####", ".##."],
		"items": [["pistol", 1, 1, 1, 0], ["chain_lightning", 1, 0, 1, 0], ["spotlight", 1, 1, 0, 0]],
	},
}


static func all_ids() -> Array[String]:
	return ORDER.duplicate()


static func has(id: String) -> bool:
	return CHARACTERS.has(id)


## Gültige Kandidaten-ID: id selbst, wenn es sie gibt, sonst der Standard.
static func valid_id(id: String) -> String:
	return id if CHARACTERS.has(id) else DEFAULT


static func display_name(id: String) -> String:
	return str((CHARACTERS.get(id, {}) as Dictionary).get("name", id))


static func tagline(id: String) -> String:
	return str((CHARACTERS.get(id, {}) as Dictionary).get("tagline", ""))


static func text(id: String) -> String:
	return str((CHARACTERS.get(id, {}) as Dictionary).get("text", ""))


static func color(id: String) -> Color:
	return (CHARACTERS.get(id, {}) as Dictionary).get("color", Color.WHITE) as Color


## Startwaffen des Kandidaten (die Waffen unter seinen Start-Gegenständen).
static func weapons(id: String) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in start_items(id):
		if ItemDefs.is_weapon(str(entry["id"])):
			result.append(str(entry["id"]))
	return result


## Zusatzwerte des Kandidaten (Kopie).
static func extra(id: String) -> Dictionary:
	return ((CHARACTERS.get(id, {}) as Dictionary).get("extra", {}) as Dictionary).duplicate()


static func start_points(id: String) -> int:
	return int((CHARACTERS.get(id, {}) as Dictionary).get("start_points", 0))


## Maximal-Leben des Kandidaten ohne Gegenstände.
static func base_max_hp(id: String) -> float:
	return Balance.PLAYER_MAX_HP + float(extra(id).get("max_hp", 0.0))


## Verschiebung des Start-Rucksacks im Raster (er liegt mittig).
static func bag_offset(id: String) -> Vector2i:
	var rows: Array = (CHARACTERS.get(id, {}) as Dictionary).get("bag", DEFAULT_BAG)
	var width: int = 0
	for row: Variant in rows:
		width = maxi(width, str(row).length())
	@warning_ignore("integer_division")
	var offset: Vector2i = Vector2i((BackpackState.COLS - width) / 2, (BackpackState.ROWS - rows.size()) / 2)
	return Vector2i(maxi(offset.x, 0), maxi(offset.y, 0))


## Felder des Start-Rucksacks, im Raster mittig ausgerichtet.
static func bag_cells(id: String) -> Array[Vector2i]:
	var rows: Array = (CHARACTERS.get(id, {}) as Dictionary).get("bag", DEFAULT_BAG)
	var offset: Vector2i = bag_offset(id)
	var result: Array[Vector2i] = []
	for y: int in rows.size():
		var row: String = str(rows[y])
		for x: int in row.length():
			if row[x] == "#":
				result.append(offset + Vector2i(x, y))
	return result


## Start-Gegenstände als Array aus { "id": String, "level": int } und, bei fester Stelle, dazu
## { "pos": Vector2i (im Raster), "rot": int }.
static func start_items(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var offset: Vector2i = bag_offset(id)
	for entry: Variant in (CHARACTERS.get(id, {}) as Dictionary).get("items", []):
		var parts: Array = entry
		var item: Dictionary = {"id": str(parts[0]), "level": int(parts[1])}
		if parts.size() >= 5:
			item["pos"] = offset + Vector2i(int(parts[2]), int(parts[3]))
			item["rot"] = int(parts[4])
		result.append(item)
	return result


## Neuer Rucksack des Kandidaten: Startform, Start-Gegenstände eingeräumt. Eine unbekannte ID
## (auch NONE) ergibt den leeren Standard-Rucksack.
static func build_backpack(id: String) -> BackpackState:
	var backpack: BackpackState = BackpackState.new()
	backpack.setup(bag_cells(id))
	for entry: Dictionary in start_items(id):
		var uid: int = backpack.add_item(str(entry["id"]), int(entry["level"]))
		if uid == -1:
			continue
		if not entry.has("pos") or not backpack.place(uid, entry["pos"] as Vector2i, int(entry.get("rot", 0))):
			backpack.auto_place(uid)
	return backpack
