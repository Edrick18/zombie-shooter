extends RefCounted
## Waffentabelle (Abschnitt 18). Reine Daten und kleine Rechenhelfer, keine Nodes.
## Besitzer: Waffen. Einbinden mit: const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
##
## Munition ist unendlich: Jede Waffe hat nur ihr Magazin, nachgeladen wird beliebig oft. Wie viele
## Hände eine Waffe braucht und welche Form sie im Rucksack hat, steht in ItemDefs.

const Balance := preload("res://scripts/core/balance.gd")

## Wert für "Vorrat" im alten Signal ammo_changed: Es gibt keinen Vorrat mehr, er ist unendlich.
const INFINITE_RESERVE: int = -1
## Ohne Waffe im Rucksack hält der Spieler diese Waffe.
const START_WEAPON: String = "pistol"
## Feste Reihenfolge der Waffen (erst Einhand, dann Zweihand), wie in ItemDefs.ORDER.
const ORDER: Array[String] = [
	"pistol", "revolver", "smg", "sawed_off", "shotgun", "rifle", "sniper", "minigun", "rocket_launcher",
]

## Schlüssel je Waffe:
## name (String), damage (float, je Kugel), fire_rate (float, Schuss je Sekunde), magazine (int),
## reload_time (float, s), spread_deg (float, halber Streuwinkel in Grad), pellets (int, Kugeln je
## Schuss), automatic (bool, Dauerfeuer bei gehaltenem Abzug), price (int, Preis am Wandkauf,
## 0 = Startwaffe), explosion_radius (float, m, 0 = keine Explosion), explosion_damage (float,
## Schaden an allen Zombies im Radius außer dem direkt getroffenen).
##
## Schaden je Sekunde bei Dauerfeuer (damage * pellets * fire_rate): Dienstpistole 125,
## Kandidatenschreck 140, Quotenhammer 192, Blitzrunde 140, Publikumsjoker 140, Dauerbrenner 216,
## Fernbedienung 192, Applausmaschine 260, Showfinale 250 (dazu die Explosion).
const WEAPONS: Dictionary = {
	"pistol": {
		"name": "Dienstpistole", "damage": 25.0, "fire_rate": 5.0, "magazine": 10,
		"reload_time": 1.2, "spread_deg": 0.5, "pellets": 1, "automatic": false,
		"price": 0, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	# Revolver: langsam, harter Treffer, kleine Trommel.
	"revolver": {
		"name": "Kandidatenschreck", "damage": 70.0, "fire_rate": 2.0, "magazine": 6,
		"reload_time": 1.9, "spread_deg": 0.3, "pellets": 1, "automatic": false,
		"price": 400, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	"smg": {
		"name": "Quotenhammer", "damage": 16.0, "fire_rate": 12.0, "magazine": 30,
		"reload_time": 1.8, "spread_deg": 1.8, "pellets": 1, "automatic": true,
		"price": 1000, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	# Abgesägte Schrotflinte für eine Hand: wenige Kugeln, breite Streuung, zwei Patronen.
	"sawed_off": {
		"name": "Blitzrunde", "damage": 14.0, "fire_rate": 2.0, "magazine": 2,
		"reload_time": 1.4, "spread_deg": 8.0, "pellets": 5, "automatic": false,
		"price": 400, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	"shotgun": {
		"name": "Publikumsjoker", "damage": 14.0, "fire_rate": 1.25, "magazine": 6,
		"reload_time": 2.2, "spread_deg": 5.0, "pellets": 8, "automatic": false,
		"price": 500, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	# Sturmgewehr: Dauerfeuer, genau, großes Magazin.
	"rifle": {
		"name": "Dauerbrenner", "damage": 24.0, "fire_rate": 9.0, "magazine": 30,
		"reload_time": 2.0, "spread_deg": 1.0, "pellets": 1, "automatic": true,
		"price": 1250, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	# Scharfschützengewehr: sehr hoher Schaden, langsam, ohne Streuung. Durchschlägt von selbst nichts.
	"sniper": {
		"name": "Fernbedienung", "damage": 240.0, "fire_rate": 0.8, "magazine": 5,
		"reload_time": 2.6, "spread_deg": 0.0, "pellets": 1, "automatic": false,
		"price": 1250, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	# Minigun: sehr hohe Schussrate, großes Magazin, langes Nachladen, deutliche Streuung.
	"minigun": {
		"name": "Applausmaschine", "damage": 13.0, "fire_rate": 20.0, "magazine": 120,
		"reload_time": 4.0, "spread_deg": 2.6, "pellets": 1, "automatic": true,
		"price": 2000, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	# Raketenwerfer: eine Rakete je Magazin. Sie explodiert am Einschlag und trifft alle im Radius.
	"rocket_launcher": {
		"name": "Showfinale", "damage": 250.0, "fire_rate": 1.0, "magazine": 1,
		"reload_time": 2.4, "spread_deg": 0.3, "pellets": 1, "automatic": false,
		"price": 2000, "explosion_radius": 3.5, "explosion_damage": 150.0,
	},
}


## Gibt es diese Waffe?
static func has(weapon_id: String) -> bool:
	return WEAPONS.has(weapon_id)


## Alle Waffen-IDs in fester Reihenfolge.
static func all_ids() -> Array[String]:
	return ORDER.duplicate()


## Daten einer Waffe (Schlüssel siehe WEAPONS). Leeres Dictionary bei unbekannter ID.
static func get_def(weapon_id: String) -> Dictionary:
	if not WEAPONS.has(weapon_id):
		return {}
	return WEAPONS[weapon_id]


## Anzeigename der Waffe, bei unbekannter ID die ID selbst.
static func display_name(weapon_id: String) -> String:
	if not WEAPONS.has(weapon_id):
		return weapon_id
	return String(WEAPONS[weapon_id]["name"])


## Sekunden zwischen zwei Schüssen.
static func fire_interval(weapon_id: String) -> float:
	if not WEAPONS.has(weapon_id):
		return 0.0
	return 1.0 / float(WEAPONS[weapon_id]["fire_rate"])


## Schaden je Sekunde bei Dauerfeuer auf ein Ziel, ohne Nachladen, Kopftreffer und Explosion.
static func dps(weapon_id: String) -> float:
	if not WEAPONS.has(weapon_id):
		return 0.0
	var def: Dictionary = WEAPONS[weapon_id]
	return float(def["damage"]) * float(int(def["pellets"])) * float(def["fire_rate"])


## Explodiert das Geschoss dieser Waffe am Einschlag?
static func is_explosive(weapon_id: String) -> bool:
	return WEAPONS.has(weapon_id) and float(WEAPONS[weapon_id]["explosion_radius"]) > 0.0


## Schadensfaktor einer Kugel für das wievielte durchschlagene Ziel (0 = erstes Ziel = 1,0).
## Je weiterem Ziel bleiben 85 % des vorherigen Schadens (multiplikativ).
static func pierce_damage_factor(target_index: int) -> float:
	if target_index <= 0:
		return 1.0
	return pow(1.0 - Balance.PIERCE_DAMAGE_FALLOFF, float(target_index))


## Schaden einer Kugel: Grundschaden, bei Kopftreffer mal Balance.HEADSHOT_MULTIPLIER,
## mal Durchschlag-Faktor für das wievielte Ziel.
static func bullet_damage(weapon_id: String, headshot: bool, target_index: int = 0) -> float:
	if not WEAPONS.has(weapon_id):
		return 0.0
	var damage: float = float(WEAPONS[weapon_id]["damage"])
	if headshot:
		damage *= Balance.HEADSHOT_MULTIPLIER
	return damage * pierce_damage_factor(target_index)
