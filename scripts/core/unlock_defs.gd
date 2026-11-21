extends RefCounted
## Freischalten zwischen den Läufen (Abschnitt 22.5): Startvorrat und Pakete.
## Reine Daten, keine Nodes. Den Besitz hält ProgressState.
## Einbinden mit: const UnlockDefs := preload("res://scripts/core/unlock_defs.gd")
##
## Jeder Gegenstand aus ItemDefs.ORDER steht entweder im Startvorrat oder in genau einem Paket
## (geprüft in tests/test_progress.gd). Kisten bieten nur an, was freigeschaltet ist.

## Von Anfang an frei, dazu die drei Rucksack-Teile.
const START: Array[String] = [
	"pistol", "revolver", "smg", "shotgun",
	"chain_lightning", "pierce", "burn", "lifesteal", "max_hp",
	"corpse_explosion", "reload_shockwave", "drone", "speed", "luck",
	"spotlight", "speed_loader", "piggy_bank",
	"bag_tiny", "bag_small", "bag_medium", "bag_large",
]

## Feste Reihenfolge der Pakete (aufsteigend nach Preis, so stehen sie im Bildschirm "Programm").
const PACK_ORDER: Array[String] = [
	"camera_team", "rapid_fire", "first_aid", "poison_kitchen", "precision", "big_bang",
	"control_room", "sustained_fire", "high_voltage", "grand_finale", "special_broadcast",
]

## Je Paket: name (im Spiel), price (Punkte vom Konto), items (vier Gegenstände oder Waffen).
const PACKS: Dictionary = {
	"camera_team": {"name": "Kamerateam", "price": 2000, "items": ["cam_tele", "cam_lens", "cam_battery", "cam_zoom"]},
	"rapid_fire": {"name": "Schnellfeuer", "price": 2000, "items": ["machine_pistol", "nail_gun", "fire_rate", "big_mag"]},
	"first_aid": {"name": "Erste Hilfe", "price": 2500, "items": ["shield", "kill_heal", "snack", "dash"]},
	"poison_kitchen": {"name": "Giftküche", "price": 3000, "items": ["poison", "frost", "flamethrower", "sawed_off"]},
	"precision": {"name": "Präzision", "price": 3500, "items": ["sniper", "crossbow", "scope", "crit"]},
	"big_bang": {"name": "Knallbonbon", "price": 4000, "items": ["grenade_launcher", "punchline", "mine", "extra_shot"]},
	"control_room": {"name": "Regieraum-Technik", "price": 4500, "items": ["cam_flash", "cam_slow", "cam_second", "cam_uplink"]},
	"sustained_fire": {"name": "Dauerfeuer", "price": 5000, "items": ["rifle", "lmg", "burst_pistol", "opener"]},
	"high_voltage": {"name": "Hochspannung", "price": 6000, "items": ["tesla", "jammer", "ricochet", "disco_ball"]},
	"grand_finale": {"name": "Großes Finale", "price": 8000, "items": ["minigun", "rocket_launcher", "auto_shotgun", "beam"]},
	"special_broadcast": {"name": "Sondersendung", "price": 10000, "items": ["replay", "revive", "thorns", "cam_director"]},
}


## Alle Paket-IDs in fester Reihenfolge.
static func all_pack_ids() -> Array[String]:
	return PACK_ORDER.duplicate()


## Gibt es dieses Paket?
static func has_pack(pack_id: String) -> bool:
	return PACKS.has(pack_id)


## Name des Pakets im Spiel, bei unbekannter ID die ID selbst.
static func pack_name(pack_id: String) -> String:
	return str((PACKS.get(pack_id, {}) as Dictionary).get("name", pack_id))


## Preis des Pakets in Punkten vom Konto, 0 bei unbekannter ID.
static func pack_price(pack_id: String) -> int:
	return int((PACKS.get(pack_id, {}) as Dictionary).get("price", 0))


## Inhalt des Pakets (IDs aus ItemDefs), leer bei unbekannter ID.
static func pack_items(pack_id: String) -> Array[String]:
	var result: Array[String] = []
	for id: Variant in (PACKS.get(pack_id, {}) as Dictionary).get("items", []):
		result.append(str(id))
	return result


## Ist dieser Gegenstand von Anfang an frei?
static func is_start_item(item_id: String) -> bool:
	return START.has(item_id)


## Paket, das diesen Gegenstand freischaltet. "" wenn er in keinem Paket steht (Startvorrat oder
## unbekannt).
static func pack_of(item_id: String) -> String:
	for pack_id: String in PACK_ORDER:
		if ((PACKS[pack_id] as Dictionary)["items"] as Array).has(item_id):
			return pack_id
	return ""


## Der Startvorrat (Kopie).
static func start_items() -> Array[String]:
	return START.duplicate()
