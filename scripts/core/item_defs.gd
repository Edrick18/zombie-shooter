extends RefCounted
## Gegenstände für den Rucksack (Abschnitte 16 bis 18): Formen, Arten, Sterne, Texte, Verkaufswert.
## Reine Daten und Textfunktionen, keine Nodes.
## Einbinden mit: const ItemDefs := preload("res://scripts/core/item_defs.gd")
##
## Fünf Arten:
##   "weapon"   Waffe (id = Waffen-ID aus WeaponDefs). Was als Waffe im Raster liegt, hält der
##              Spieler in der Hand. Jede Waffe braucht eine oder zwei Hände ("hands").
##   "upgrade"  wirkt wie das gleichnamige Upgrade aus UpgradeDefs (id = Upgrade-ID)
##   "booster"  Verstärker: gibt einen Zusatzwert
##   "bag"      Rucksack-Teil: vergrößert das Raster um seine Form und ist danach verbraucht
##   "camera"   Kamera (Abschnitt 22.1, id = Kamera-ID aus CameraDefs): Jedes eingeräumte Exemplar
##              ist im Spiel ein eigener Knoten mit festen Werten je Rarität
##
## Sterne: Manche Gegenstände wirken nicht für sich, sondern auf das, was auf ihren Sternfeldern
## liegt ("stars", Felder neben der Form, sie drehen sich mit). Die meisten Sterne zielen auf
## Waffen: Der Gegenstand wirkt dann nur für die Waffen, die eines seiner Sternfelder belegen.
## Ohne Waffe auf einem Stern wirkt er nicht. Die Sterne der Kamera-Gegenstände zielen genauso auf
## Kameras, der Stern der Wiederholung auf einen Upgrade-Gegenstand oder eine Kamera.
## Gegenstände ohne Sterne wirken immer.
##
## Raritäten: Waffen, Upgrade-Gegenstände und Verstärker haben eine von fünf Raritäten
## (Gewöhnlich bis Legendär). Im Code ist das die Zahl 1 bis 5 im Feld "level": Sie ist bei
## Upgrade-Gegenständen zugleich die Stufe in UpgradeDefs. Zwei gleiche Gegenstände gleicher
## Rarität lassen sich zu einem der nächsten Rarität kombinieren (BackpackState.merge).
## Jedes eingeräumte Exemplar wirkt für sich: Mehrere gleiche Gegenstände addieren ihre Wirkung.
##
## Formen sind Listen von Feldern (x nach rechts, y nach unten). cells(id, rot) liefert die
## gedrehte Form, so verschoben, dass sie bei (0, 0) beginnt. stars(id, rot) liefert die
## Sternfelder im selben Koordinatensystem (sie können negativ sein).

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")

const KIND_WEAPON: String = "weapon"
const KIND_UPGRADE: String = "upgrade"
const KIND_BOOSTER: String = "booster"
const KIND_BAG: String = "bag"
const KIND_CAMERA: String = "camera"

## Worauf Sterne zielen: auf Waffen (Standard) oder auf Upgrade-Gegenstände.
const STAR_WEAPON: String = "weapon"
const STAR_ITEM: String = "item"
const STAR_CAMERA: String = "camera"

## Gruppen der Upgrade-Gegenstände (bestimmen nur noch die Farbe).
const TAG_TECH: String = "technik"
const TAG_FIRE: String = "feuer"
const TAG_BODY: String = "koerper"
const TAG_SHOW: String = "show"
const TAG_CHEMISTRY: String = "chemie"
const TAG_NAMES: Dictionary = {
	"technik": "Technik", "feuer": "Feuer", "koerper": "Körper", "show": "Show", "chemie": "Chemie",
}
const TAG_COLORS: Dictionary = {
	"technik": Color(0.25, 0.85, 1.0), "feuer": Color(1.0, 0.5, 0.15),
	"koerper": Color(0.4, 0.95, 0.4), "show": Color(1.0, 0.35, 0.75),
	"chemie": Color(0.72, 0.9, 0.2),
}
const BOOSTER_COLOR: Color = Color(1.0, 0.86, 0.2)
const BAG_COLOR: Color = Color(0.72, 0.58, 0.42)
const WEAPON_COLOR: Color = Color(0.72, 0.78, 0.9)
const CAMERA_COLOR: Color = Color(0.58, 0.52, 1.0)

## Raritäten in aufsteigender Reihenfolge (Index 0 = "level" 1).
const MAX_RARITY: int = Balance.UPGRADE_MAX_LEVEL
const RARITY_NAMES: Array[String] = ["Gewöhnlich", "Ungewöhnlich", "Selten", "Episch", "Legendär"]
const RARITY_COLORS: Array[Color] = [
	Color(0.82, 0.84, 0.88), Color(0.4, 0.92, 0.4), Color(0.35, 0.65, 1.0),
	Color(0.78, 0.45, 1.0), Color(1.0, 0.64, 0.12),
]
## Verstärker: Faktor auf amount je eigener Rarität.
const STAT_FACTORS: Array[float] = [1.0, 1.5, 2.0, 2.5, 3.0]

## Feste Reihenfolge aller Gegenstände (für Listen, Angebote und Tests).
const ORDER: Array[String] = [
	"pistol", "revolver", "smg", "sawed_off", "shotgun", "rifle", "sniper", "minigun", "rocket_launcher",
	"burst_pistol", "nail_gun", "machine_pistol", "crossbow", "grenade_launcher",
	"flamethrower", "beam", "tesla", "lmg", "auto_shotgun",
	"chain_lightning", "pierce", "burn", "lifesteal", "max_hp",
	"corpse_explosion", "reload_shockwave", "speed", "luck",
	"extra_shot", "poison", "crit", "big_mag", "scope", "fire_rate",
	"shield", "kill_heal", "disco_ball", "jammer", "dash",
	"frost", "opener", "punchline", "ricochet",
	"thorns", "revive", "snack", "mine",
	"drone", "cam_tele", "cam_flash", "cam_slow", "cam_director",
	"cam_lens", "cam_zoom", "cam_battery", "cam_second", "cam_uplink",
	"spotlight", "speed_loader", "piggy_bank", "replay",
	"bag_tiny", "bag_small", "bag_medium", "bag_large",
]

## Je Gegenstand:
## kind        Art (siehe oben)
## shape       Felder der Form
## hands       Waffen: 1 oder 2 Hände
## stars       Sternfelder neben der Form (ungedreht, im Koordinatensystem von shape)
## star_target worauf die Sterne zielen: STAR_WEAPON (Standard), STAR_ITEM oder STAR_CAMERA
## tags        Gruppen (nur Upgrade-Gegenstände, für die Farbe)
## name        Name (Waffen nehmen ihn aus WeaponDefs, Upgrade-Gegenstände aus UpgradeDefs)
## text        Wirkungstext der Rucksack-Teile
## stat, amount
##             Verstärker: gibt amount (mal STAT_FACTORS) auf den Wert stat. "damage" und "reload"
##             gelten für die Waffen auf den Sternen, "points" gilt immer.
## min_rarity  kleinste Kisten-Seltenheit, in der der Gegenstand angeboten wird (Standard Bronze)
## weight      Gewicht im Angebot einer Kiste
const ITEMS: Dictionary = {
	"pistol": {"kind": "weapon", "hands": 1, "shape": [Vector2i(0, 0), Vector2i(1, 0)], "weight": 5.0},
	"revolver": {"kind": "weapon", "hands": 1, "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "weight": 4.0},
	"smg": {"kind": "weapon", "hands": 1, "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)], "weight": 4.0},
	"sawed_off": {"kind": "weapon", "hands": 1, "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "weight": 4.0},
	"shotgun": {"kind": "weapon", "hands": 2, "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], "weight": 4.0},
	"rifle": {
		"kind": "weapon", "hands": 2, "weight": 4.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 1)],
	},
	"sniper": {
		"kind": "weapon", "hands": 2, "weight": 3.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)],
	},
	"minigun": {
		"kind": "weapon", "hands": 2, "weight": 3.0, "min_rarity": 1,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	},
	"rocket_launcher": {
		"kind": "weapon", "hands": 2, "weight": 3.0, "min_rarity": 1,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1)],
	},
	# --- Abschnitt 22.2: zehn neue Waffen ---
	"burst_pistol": {"kind": "weapon", "hands": 1, "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "weight": 4.0},
	"nail_gun": {
		"kind": "weapon", "hands": 1, "weight": 4.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	},
	"machine_pistol": {"kind": "weapon", "hands": 1, "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)], "weight": 4.0},
	"crossbow": {
		"kind": "weapon", "hands": 1, "weight": 4.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	},
	"grenade_launcher": {
		"kind": "weapon", "hands": 1, "weight": 3.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)],
	},
	"flamethrower": {
		"kind": "weapon", "hands": 2, "weight": 3.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(2, 1), Vector2i(3, 1)],
	},
	"beam": {
		"kind": "weapon", "hands": 2, "weight": 3.0, "min_rarity": 1,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, 1)],
	},
	"tesla": {
		"kind": "weapon", "hands": 2, "weight": 3.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)],
	},
	"lmg": {
		"kind": "weapon", "hands": 2, "weight": 3.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 1), Vector2i(2, 1)],
	},
	"auto_shotgun": {
		"kind": "weapon", "hands": 2, "weight": 3.0, "min_rarity": 1,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1)],
	},
	"chain_lightning": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(0, 1)], "tags": ["technik"], "weight": 10.0,
		"stars": [Vector2i(-1, 0), Vector2i(1, 0)],
	},
	"pierce": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0)], "tags": ["technik"], "weight": 10.0,
		"stars": [Vector2i(0, -1), Vector2i(1, -1)],
	},
	"burn": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "tags": ["feuer"], "weight": 10.0,
		"stars": [Vector2i(1, 1), Vector2i(2, 0)],
	},
	"lifesteal": {"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["koerper"], "weight": 10.0},
	"max_hp": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)], "tags": ["koerper"], "weight": 10.0},
	"corpse_explosion": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "tags": ["feuer"], "weight": 10.0},
	"reload_shockwave": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)], "tags": ["show"], "weight": 10.0},
	"speed": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(0, 1)], "tags": ["koerper"], "weight": 10.0},
	"luck": {"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["show"], "weight": 10.0},
	# --- Abschnitt 19: für die Waffe auf den Sternen ---
	"extra_shot": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0)], "tags": ["technik"], "weight": 8.0,
		"stars": [Vector2i(2, 0), Vector2i(3, 0)],
	},
	"poison": {
		"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["chemie"], "weight": 8.0,
		"stars": [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)],
	},
	"crit": {
		"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["show"], "weight": 8.0,
		"stars": [Vector2i(-1, 0), Vector2i(1, 0)],
	},
	"big_mag": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0)], "tags": ["technik"], "weight": 8.0,
		"stars": [Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 1), Vector2i(1, 1)],
	},
	"scope": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)], "tags": ["show"], "weight": 8.0,
		"stars": [Vector2i(1, 0)],
	},
	"fire_rate": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0)], "tags": ["technik"], "weight": 8.0,
		"stars": [Vector2i(-1, 0), Vector2i(2, 0), Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 1), Vector2i(1, 1)],
	},
	# --- Abschnitt 19: für den Spieler als Ganzes ---
	"shield": {
		"kind": "upgrade", "tags": ["koerper"], "weight": 8.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	},
	"kill_heal": {"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["koerper"], "weight": 8.0},
	"disco_ball": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(0, 1)], "tags": ["show"], "weight": 8.0},
	"jammer": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "tags": ["technik"], "weight": 8.0},
	"dash": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0)], "tags": ["koerper"], "weight": 8.0},
	# --- Abschnitt 22.3: für die Waffe auf den Sternen ---
	"frost": {
		"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["chemie"], "weight": 8.0,
		"stars": [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)],
	},
	"opener": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "tags": ["show"], "weight": 8.0,
		"stars": [Vector2i(-1, 0), Vector2i(0, -1)],
	},
	"punchline": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(0, 1)], "tags": ["feuer"], "weight": 8.0,
		"stars": [Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2)],
	},
	"ricochet": {
		"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["technik"], "weight": 8.0,
		"stars": [Vector2i(1, -1), Vector2i(1, 1)],
	},
	# --- Abschnitt 22.3: für den Spieler als Ganzes ---
	"thorns": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)], "tags": ["koerper"], "weight": 8.0},
	"revive": {
		"kind": "upgrade", "tags": ["show"], "weight": 5.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	},
	"snack": {"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["koerper"], "weight": 8.0},
	"mine": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0)], "tags": ["feuer"], "weight": 8.0},
	# --- Abschnitt 22.1: Kameras (eigene Art, feste Werte in CameraDefs) ---
	"drone": {"kind": "camera", "shape": [Vector2i(0, 0), Vector2i(1, 0)], "weight": 10.0},
	"cam_tele": {"kind": "camera", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "weight": 7.0},
	"cam_flash": {
		"kind": "camera", "weight": 7.0,
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	},
	"cam_slow": {"kind": "camera", "shape": [Vector2i(0, 0)], "weight": 7.0},
	"cam_director": {"kind": "camera", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "weight": 6.0},
	# --- Abschnitt 22.1: Kamera-Gegenstände (Sterne zielen auf Kameras) ---
	"cam_lens": {
		"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["technik"], "weight": 7.0,
		"stars": [Vector2i(-1, 0), Vector2i(1, 0)], "star_target": "camera",
	},
	"cam_zoom": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(0, 1)], "tags": ["technik"], "weight": 7.0,
		"stars": [Vector2i(1, 0), Vector2i(1, 1)], "star_target": "camera",
	},
	"cam_battery": {
		"kind": "upgrade", "shape": [Vector2i(0, 0)], "tags": ["technik"], "weight": 7.0,
		"stars": [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)], "star_target": "camera",
	},
	"cam_second": {
		"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0)], "tags": ["technik"], "weight": 6.0,
		"stars": [Vector2i(2, 0)], "star_target": "camera",
	},
	"cam_uplink": {"kind": "upgrade", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "tags": ["technik"], "weight": 6.0},
	"spotlight": {
		"kind": "booster", "name": "Scheinwerfer", "shape": [Vector2i(0, 0), Vector2i(1, 0)],
		"stars": [Vector2i(0, 1), Vector2i(1, 1)],
		"stat": "damage", "amount": 0.1, "weight": 6.0,
	},
	"speed_loader": {
		"kind": "booster", "name": "Ladehilfe", "shape": [Vector2i(0, 0)],
		"stars": [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)],
		"stat": "reload", "amount": 0.1, "weight": 6.0,
	},
	"piggy_bank": {
		"kind": "booster", "name": "Sparschwein", "shape": [Vector2i(0, 0)],
		"stat": "points", "amount": 0.06, "weight": 6.0,
	},
	# Wiederholung: Ihr Stern zielt auf einen Upgrade-Gegenstand. Der zählt dann doppelt.
	"replay": {
		"kind": "booster", "name": "Wiederholung", "shape": [Vector2i(0, 0)],
		"stars": [Vector2i(1, 0)], "star_target": "item", "weight": 4.0, "min_rarity": 2,
		"text": "Der Gegenstand oder die Kamera auf dem Stern wirkt, als läge er zweimal im Rucksack (das zweite Mal höchstens in der Rarität dieser Wiederholung). Wirkt nicht auf Waffen, Verstärker und andere Wiederholungen.",
	},
	# Kleinstes Rucksack-Teil: ein einzelnes Feld, passt in jede Lücke am Rand.
	"bag_tiny": {
		"kind": "bag", "name": "Bauchtasche", "shape": [Vector2i(0, 0)],
		"text": "Vergrößert den Rucksack um 1 Feld. An den Rand des Rucksacks legen.", "weight": 5.0,
	},
	"bag_small": {
		"kind": "bag", "name": "Jutebeutel", "shape": [Vector2i(0, 0), Vector2i(1, 0)],
		"text": "Vergrößert den Rucksack um 2 Felder. An den Rand des Rucksacks legen.", "weight": 7.0,
	},
	"bag_medium": {
		"kind": "bag", "name": "Sporttasche", "shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"text": "Vergrößert den Rucksack um 4 Felder. An den Rand des Rucksacks legen.", "weight": 5.0, "min_rarity": 1,
	},
	"bag_large": {
		"kind": "bag", "name": "Reisekoffer",
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		"text": "Vergrößert den Rucksack um 6 Felder. An den Rand des Rucksacks legen.", "weight": 4.0, "min_rarity": 2,
	},
}


static func all_ids() -> Array[String]:
	return ORDER.duplicate()


static func has(id: String) -> bool:
	return ITEMS.has(id)


## Art des Gegenstands, "" bei unbekannter ID.
static func kind(id: String) -> String:
	return str((ITEMS.get(id, {}) as Dictionary).get("kind", ""))


static func is_weapon(id: String) -> bool:
	return kind(id) == KIND_WEAPON


static func is_upgrade(id: String) -> bool:
	return kind(id) == KIND_UPGRADE


static func is_booster(id: String) -> bool:
	return kind(id) == KIND_BOOSTER


static func is_bag(id: String) -> bool:
	return kind(id) == KIND_BAG


## Ist das eine Kamera (Kameradrohne, Tele-, Blitzlicht-, Zeitlupen-, Regie-Kamera)?
static func is_camera(id: String) -> bool:
	return kind(id) == KIND_CAMERA


## Hände, die eine Waffe braucht (1 oder 2), 0 bei allem anderen.
static func hands(id: String) -> int:
	if not is_weapon(id):
		return 0
	return clampi(int((ITEMS.get(id, {}) as Dictionary).get("hands", 1)), 1, Balance.PLAYER_HANDS)


## Name im Spiel.
static func display_name(id: String) -> String:
	if is_upgrade(id):
		return UpgradeDefs.display_name(id)
	if is_weapon(id):
		return WeaponDefs.display_name(id)
	if is_camera(id):
		return CameraDefs.display_name(id)
	return str((ITEMS.get(id, {}) as Dictionary).get("name", id))


## Gruppen eines Upgrade-Gegenstands (leer bei allem anderen).
static func tags(id: String) -> Array[String]:
	var result: Array[String] = []
	for tag: Variant in (ITEMS.get(id, {}) as Dictionary).get("tags", []):
		result.append(str(tag))
	return result


static func has_tag(id: String, tag: String) -> bool:
	return tags(id).has(tag)


## Gruppen als Text: "Technik". Leer ohne Gruppe.
static func tags_text(id: String) -> String:
	var names: PackedStringArray = PackedStringArray()
	for tag: String in tags(id):
		names.append(str(TAG_NAMES.get(tag, tag)))
	return ", ".join(names)


## Hat dieser Gegenstand eine Rarität? (Alles außer Rucksack-Teilen.)
static func has_rarity(id: String) -> bool:
	return is_weapon(id) or is_upgrade(id) or is_booster(id) or is_camera(id)


## Name der Rarität zu "level" 1 bis 5.
static func rarity_name(level: int) -> String:
	return RARITY_NAMES[clampi(level, 1, MAX_RARITY) - 1]


## Farbe der Rarität zu "level" 1 bis 5.
static func rarity_color(level: int) -> Color:
	return RARITY_COLORS[clampi(level, 1, MAX_RARITY) - 1]


## Faktor auf den Schaden einer Waffe dieser Rarität.
static func weapon_damage_factor(level: int) -> float:
	return Balance.WEAPON_RARITY_DAMAGE[clampi(level, 1, MAX_RARITY) - 1]


## Wert, den ein Verstärker erhöht ("damage", "reload", "points"), "" wenn keiner.
static func stat(id: String) -> String:
	return str((ITEMS.get(id, {}) as Dictionary).get("stat", ""))


## Betrag eines Verstärkers dieser Rarität (Bruchteil, 0.1 = 10 %).
static func stat_amount(id: String, level: int = 1) -> float:
	var base: float = float((ITEMS.get(id, {}) as Dictionary).get("amount", 0.0))
	return base * STAT_FACTORS[clampi(level, 1, MAX_RARITY) - 1]


static func min_rarity(id: String) -> int:
	return int((ITEMS.get(id, {}) as Dictionary).get("min_rarity", Balance.RARITY_BRONZE))


static func weight(id: String) -> float:
	return float((ITEMS.get(id, {}) as Dictionary).get("weight", 0.0))


## Felder der Form nach rot Vierteldrehungen im Uhrzeigersinn, bei (0, 0) beginnend und sortiert.
static func cells(id: String, rot: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = _rotated(id, "shape", rot)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


## Hat der Gegenstand Sternfelder?
static func has_stars(id: String) -> bool:
	return not ((ITEMS.get(id, {}) as Dictionary).get("stars", []) as Array).is_empty()


## Sternfelder nach rot Vierteldrehungen, im Koordinatensystem von cells(id, rot): relativ zur
## linken oberen Ecke der gedrehten Form, also auch mit negativen Werten.
static func stars(id: String, rot: int = 0) -> Array[Vector2i]:
	return _rotated(id, "stars", rot)


## Worauf die Sterne zielen: STAR_WEAPON, STAR_ITEM oder STAR_CAMERA, "" ohne Sterne.
static func star_target(id: String) -> String:
	if not has_stars(id):
		return ""
	return str((ITEMS.get(id, {}) as Dictionary).get("star_target", STAR_WEAPON))


## Kann der Stern von owner_id auf den Gegenstand target_id wirken? Waffen-Sterne wirken auf
## Waffen, Kamera-Sterne auf Kameras. Gegenstands-Sterne (Wiederholung) wirken auf
## Upgrade-Gegenstände und auf Kameras.
static func star_hits(owner_id: String, target_id: String) -> bool:
	match star_target(owner_id):
		STAR_WEAPON:
			return is_weapon(target_id)
		STAR_ITEM:
			return is_upgrade(target_id) or is_camera(target_id)
		STAR_CAMERA:
			return is_camera(target_id)
	return false


## Wirkt dieser Upgrade-Gegenstand nur für die Waffen auf seinen Sternen (Kugel-Effekte)?
static func is_weapon_mod(id: String) -> bool:
	return is_upgrade(id) and star_target(id) == STAR_WEAPON


## Wirkt dieser Upgrade-Gegenstand nur für die Kameras auf seinen Sternen (Objektiv, Zoom,
## Akkupack, Zweitkamera)? Die Sendeleitung hat keine Sterne und zählt hier nicht.
static func is_camera_mod(id: String) -> bool:
	return is_upgrade(id) and star_target(id) == STAR_CAMERA


## Ist das die Wiederholung (ihr Stern verdoppelt einen Upgrade-Gegenstand oder eine Kamera)?
static func is_replay(id: String) -> bool:
	return is_booster(id) and star_target(id) == STAR_ITEM


## Breite und Höhe der gedrehten Form in Feldern.
static func size(id: String, rot: int = 0) -> Vector2i:
	var extent: Vector2i = Vector2i.ZERO
	for cell: Vector2i in cells(id, rot):
		extent = Vector2i(maxi(extent.x, cell.x + 1), maxi(extent.y, cell.y + 1))
	return extent


static func cell_count(id: String) -> int:
	return ((ITEMS.get(id, {}) as Dictionary).get("shape", []) as Array).size()


## Farbe des Gegenstands: Upgrade-Gegenstände nach Gruppe, Verstärker gelb, Waffen stahlblau,
## Kameras violett, Rucksack-Teile braun.
static func color(id: String) -> Color:
	match kind(id):
		KIND_UPGRADE:
			var item_tags: Array[String] = tags(id)
			if not item_tags.is_empty():
				return TAG_COLORS.get(item_tags[0], Color.WHITE) as Color
		KIND_BOOSTER:
			return BOOSTER_COLOR
		KIND_BAG:
			return BAG_COLOR
		KIND_WEAPON:
			return WEAPON_COLOR
		KIND_CAMERA:
			return CAMERA_COLOR
	return Color.WHITE


## Wirkungstext mit den Zahlen der Rarität.
static func description(id: String, level: int = 1) -> String:
	if is_upgrade(id):
		var text: String = UpgradeDefs.effect_text(id, clampi(level, 1, MAX_RARITY))
		if is_weapon_mod(id):
			text += " Gilt für Waffen auf den Sternen."
		elif is_camera_mod(id):
			text += " Gilt für Kameras auf den Sternen."
		return text
	if is_weapon(id):
		return weapon_text(id, level)
	if is_camera(id):
		return CameraDefs.effect_text(id, level)
	if is_booster(id):
		var percent: String = UpgradeDefs.format_percent(stat_amount(id, level))
		match stat(id):
			"damage":
				return "+%s %% Schaden für Waffen auf den Sternen." % percent
			"reload":
				return "Waffen auf den Sternen laden %s %% schneller nach." % percent
			"points":
				return "+%s %% Punkte." % percent
	return str((ITEMS.get(id, {}) as Dictionary).get("text", ""))


## Kurze Daten einer Waffe: Schaden (mit dem Faktor der Rarität), Schussfolge, Magazin, Hände.
static func weapon_text(id: String, level: int = 1) -> String:
	var def: Dictionary = WeaponDefs.get_def(id)
	var hand_text: String = "Eine Hand." if hands(id) == 1 else "Zwei Hände."
	if def.is_empty():
		return hand_text
	var damage: float = float(def.get("damage", 0.0)) * weapon_damage_factor(level)
	var pellets: int = int(def.get("pellets", 1))
	var damage_text: String = UpgradeDefs.format_number(snappedf(damage, 0.1))
	if pellets > 1:
		damage_text = "%d × %s" % [pellets, damage_text]
	var rate_text: String = "%s Schuss je Sekunde" % UpgradeDefs.format_number(float(def.get("fire_rate", 0.0)))
	var burst: int = WeaponDefs.burst(id)
	if burst > 1:
		rate_text = "%s Salven je Sekunde mit je %d Schuss" % [UpgradeDefs.format_number(float(def.get("fire_rate", 0.0))), burst]
	return "Schaden %s · %s · Magazin %d · Nachladen %s s. %s%s" % [
		damage_text, rate_text, int(def.get("magazine", 0)),
		UpgradeDefs.format_number(float(def.get("reload_time", 0.0))), _weapon_traits(id), hand_text]


## Besonderheiten einer Waffe aus Abschnitt 22.2 als Sätze (mit Leerzeichen am Ende), "" wenn
## sie keine hat.
static func _weapon_traits(id: String) -> String:
	var traits: String = ""
	match WeaponDefs.mode(id):
		WeaponDefs.MODE_GRENADE:
			traits += "Granate im Bogen. "
		WeaponDefs.MODE_FLAME:
			traits += "Flammen bis %s m, setzt in Brand. " % UpgradeDefs.format_number(WeaponDefs.reach(id))
		WeaponDefs.MODE_BEAM:
			traits += "Dauerstrahl durch alle Zombies. "
	var radius: float = float(WeaponDefs.get_def(id).get("explosion_radius", 0.0))
	if radius > 0.0:
		traits += "Explosion %s im Umkreis von %s m. " % [
			UpgradeDefs.format_number(float(WeaponDefs.get_def(id).get("explosion_damage", 0.0))), UpgradeDefs.format_number(radius)]
	var pierce: int = WeaponDefs.pierce(id)
	if pierce == 1:
		traits += "Durchschlägt einen weiteren Zombie. "
	elif pierce > 1 and pierce < WeaponDefs.PIERCE_ALL:
		traits += "Durchschlägt %d weitere Zombies. " % pierce
	if WeaponDefs.arc_jumps(id) > 0:
		traits += "Springt auf %d weitere Zombies mit %s %% Schaden. " % [WeaponDefs.arc_jumps(id), UpgradeDefs.format_percent(WeaponDefs.arc_factor(id))]
	return traits


## Zeile unter dem Namen: "Selten · Technik · 2 Felder", "Selten · Waffe · 1 Hand · 2 Felder",
## "Selten · Verstärker · 1 Feld", "Rucksack · 4 Felder".
static func subtitle(id: String, level: int = 1) -> String:
	var count: int = cell_count(id)
	var fields: String = "1 Feld" if count == 1 else "%d Felder" % count
	match kind(id):
		KIND_UPGRADE:
			return "%s · %s · %s" % [rarity_name(level), tags_text(id), fields]
		KIND_WEAPON:
			return "%s · Waffe · %s · %s" % [rarity_name(level), "1 Hand" if hands(id) == 1 else "2 Hände", fields]
		KIND_BOOSTER:
			return "%s · Verstärker · %s" % [rarity_name(level), fields]
		KIND_BAG:
			return "Rucksack · %s" % fields
		KIND_CAMERA:
			return "%s · Kamera · %s" % [rarity_name(level), fields]
	return ""


## Punkte beim Verkaufen: Gewöhnlich 100, jede Rarität darüber das Doppelte. Rucksack-Teile fest.
static func sell_value(id: String, level: int = 1) -> int:
	if is_bag(id):
		return Balance.ITEM_SELL_BAG
	if has_rarity(id):
		return Balance.ITEM_SELL_BASE << (clampi(level, 1, MAX_RARITY) - 1)
	return 0


## Felder einer Liste ("shape" oder "stars") gedreht und so verschoben, dass die Form bei (0, 0)
## beginnt.
static func _rotated(id: String, key: String, rot: int) -> Array[Vector2i]:
	var entry: Dictionary = ITEMS.get(id, {})
	var shape: Array[Vector2i] = []
	for cell: Variant in entry.get("shape", []):
		shape.append(_turn(cell as Vector2i, rot))
	var result: Array[Vector2i] = []
	if shape.is_empty():
		return result
	var origin: Vector2i = shape[0]
	for cell: Vector2i in shape:
		origin = Vector2i(mini(origin.x, cell.x), mini(origin.y, cell.y))
	if key == "shape":
		for cell: Vector2i in shape:
			result.append(cell - origin)
		return result
	for cell: Variant in entry.get(key, []):
		result.append(_turn(cell as Vector2i, rot) - origin)
	return result


static func _turn(cell: Vector2i, rot: int) -> Vector2i:
	var turned: Vector2i = cell
	for _i: int in posmod(rot, 4):
		turned = Vector2i(-turned.y, turned.x)
	return turned
