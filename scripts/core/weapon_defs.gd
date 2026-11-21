extends RefCounted
## Waffentabelle (Abschnitte 18 und 22.2). Reine Daten und kleine Rechenhelfer, keine Nodes.
## Besitzer: Waffen. Einbinden mit: const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
##
## Munition ist unendlich: Jede Waffe hat nur ihr Magazin, nachgeladen wird beliebig oft. Wie viele
## Hände eine Waffe braucht und welche Form sie im Rucksack hat, steht in ItemDefs.

const Balance := preload("res://scripts/core/balance.gd")

## Wert für "Vorrat" im alten Signal ammo_changed: Es gibt keinen Vorrat mehr, er ist unendlich.
const INFINITE_RESERVE: int = -1
## Ohne Waffe im Rucksack hält der Spieler diese Waffe.
const START_WEAPON: String = "pistol"
## Zugabe (extra_shot): Die Zusatzkugel fliegt um höchstens so viele Grad neben der normalen Kugel.
const EXTRA_SHOT_SPREAD_DEG: float = 1.5
## Feste Reihenfolge der Waffen (erst Einhand, dann Zweihand), wie in ItemDefs.ORDER.
const ORDER: Array[String] = [
	"pistol", "revolver", "smg", "sawed_off", "shotgun", "rifle", "sniper", "minigun", "rocket_launcher",
	"burst_pistol", "nail_gun", "machine_pistol", "crossbow", "grenade_launcher",
	"flamethrower", "beam", "tesla", "lmg", "auto_shotgun",
]

## Schussarten (Schlüssel "mode", Abschnitt 22.2). Ohne Eintrag gilt MODE_BULLET.
##   bullet   Kugel als Strahl (alle alten Waffen, auch der Raketenwerfer)
##   grenade  Granate im Bogen (Schwerkraft), explodiert am Einschlag
##   flame    Kegel bis "range" Meter: Jeder Stoß trifft alle Zombies im Kegel
##   beam     Dauerstrahl: Jeder Treffer geht durch alle Zombies in der Linie
const MODE_BULLET: String = "bullet"
const MODE_GRENADE: String = "grenade"
const MODE_FLAME: String = "flame"
const MODE_BEAM: String = "beam"
## Wert für "pierce": geht durch alle Zombies in der Linie.
const PIERCE_ALL: int = 999

## Schlüssel je Waffe:
## name (String), damage (float, je Kugel), fire_rate (float, Schuss je Sekunde), magazine (int),
## reload_time (float, s), spread_deg (float, halber Streuwinkel in Grad), pellets (int, Kugeln je
## Schuss), automatic (bool, Dauerfeuer bei gehaltenem Abzug), price (int, Preis am Wandkauf,
## 0 = Startwaffe), explosion_radius (float, m, 0 = keine Explosion), explosion_damage (float,
## Schaden an allen Zombies im Radius außer dem direkt getroffenen).
##
## Neue Schlüssel seit Abschnitt 22.2. Alle sind freiwillig: Fehlt einer, gilt der Standardwert,
## die alten Waffen bleiben also unverändert. Gelesen werden sie über die Funktionen unten.
## mode (String, Standard "bullet"), burst (int, Schüsse je Abzug, Standard 1), burst_interval
## (float, s zwischen den Schüssen einer Salve), pierce (int, durchschlägt von sich aus so viele
## weitere Zombies, Standard 0, PIERCE_ALL = alle), arc_jumps (int), arc_factor (float) und
## arc_radius (float, m): eingebauter Blitz, der von jedem Treffer auf weitere Zombies springt,
## range (float, m, nur "flame": Länge des Kegels), cone_deg (float, nur "flame": halber
## Öffnungswinkel), burn_dps und burn_time (float, nur "flame": Brand in Schaden je Sekunde und
## Sekunden), projectile_speed (float, m/s) und projectile_gravity (float, m/s², nur "grenade").
##
## Schaden je Sekunde bei Dauerfeuer (damage * pellets * fire_rate): Dienstpistole 125,
## Kandidatenschreck 140, Quotenhammer 192, Blitzrunde 140, Publikumsjoker 140, Dauerbrenner 216,
## Fernbedienung 192, Applausmaschine 260, Showfinale 250 (dazu die Explosion). Neu: Dreierpack 145,2
## (3 Schüsse je Salve), Bühnenbau 126, Werbeblock 198, Zielgerade 121, Knalleffekt 60 (dazu die
## Explosion 110), Heiße Phase 135 je Zombie im Kegel (dazu der Brand), Rotlicht 180 je Zombie in
## der Linie, Kurzschluss 135 (dazu die Sprünge), Marathonsendung 220, Zuschauerfrage 231.
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
	# --- Abschnitt 22.2: zehn neue Waffen ---
	# Salvenpistole: Ein Abzug gibt drei Schüsse kurz hintereinander, jeder kostet eine Kugel.
	# fire_rate zählt Salven je Sekunde.
	"burst_pistol": {
		"name": "Dreierpack", "damage": 22.0, "fire_rate": 2.2, "magazine": 15,
		"reload_time": 1.4, "spread_deg": 1.0, "pellets": 1, "automatic": false,
		"price": 900, "explosion_radius": 0.0, "explosion_damage": 0.0,
		"burst": 3, "burst_interval": 0.07,
	},
	# Nagelpistole: schnelle, schwache Nägel, die einen weiteren Zombie durchschlagen.
	"nail_gun": {
		"name": "Bühnenbau", "damage": 9.0, "fire_rate": 14.0, "magazine": 40,
		"reload_time": 1.6, "spread_deg": 2.2, "pellets": 1, "automatic": true,
		"price": 900, "explosion_radius": 0.0, "explosion_damage": 0.0,
		"pierce": 1,
	},
	# Maschinenpistole für eine Hand: sehr schnell, kleines Magazin, streut stark.
	"machine_pistol": {
		"name": "Werbeblock", "damage": 11.0, "fire_rate": 18.0, "magazine": 20,
		"reload_time": 1.2, "spread_deg": 3.0, "pellets": 1, "automatic": true,
		"price": 1000, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	# Armbrust: ein Bolzen je Magazin, genau, geht durch drei weitere Zombies.
	"crossbow": {
		"name": "Zielgerade", "damage": 110.0, "fire_rate": 1.1, "magazine": 1,
		"reload_time": 1.3, "spread_deg": 0.0, "pellets": 1, "automatic": false,
		"price": 1250, "explosion_radius": 0.0, "explosion_damage": 0.0,
		"pierce": 3,
	},
	# Granatwerfer für eine Hand: Die Granate fliegt im Bogen und explodiert am Einschlag.
	"grenade_launcher": {
		"name": "Knalleffekt", "damage": 60.0, "fire_rate": 1.0, "magazine": 4,
		"reload_time": 2.8, "spread_deg": 0.5, "pellets": 1, "automatic": false,
		"price": 1500, "explosion_radius": 3.0, "explosion_damage": 110.0,
		"mode": "grenade", "projectile_speed": 22.0, "projectile_gravity": 12.0,
	},
	# Flammenwerfer: Kegel bis 7 m, jeder Stoß trifft alle Zombies darin und setzt sie in Brand.
	"flamethrower": {
		"name": "Heiße Phase", "damage": 9.0, "fire_rate": 15.0, "magazine": 100,
		"reload_time": 3.0, "spread_deg": 0.0, "pellets": 1, "automatic": true,
		"price": 1750, "explosion_radius": 0.0, "explosion_damage": 0.0,
		"mode": "flame", "range": 7.0, "cone_deg": 14.0, "burn_dps": 8.0, "burn_time": 3.0,
	},
	# Dauerstrahl: 20 Treffer je Sekunde, geht durch alle Zombies in der Linie.
	"beam": {
		"name": "Rotlicht", "damage": 9.0, "fire_rate": 20.0, "magazine": 80,
		"reload_time": 2.6, "spread_deg": 0.0, "pellets": 1, "automatic": true,
		"price": 2000, "explosion_radius": 0.0, "explosion_damage": 0.0,
		"mode": "beam", "pierce": PIERCE_ALL,
	},
	# Teslagewehr: Jeder Treffer springt auf drei weitere Zombies im Umkreis.
	"tesla": {
		"name": "Kurzschluss", "damage": 45.0, "fire_rate": 3.0, "magazine": 12,
		"reload_time": 2.4, "spread_deg": 0.6, "pellets": 1, "automatic": false,
		"price": 1750, "explosion_radius": 0.0, "explosion_damage": 0.0,
		"arc_jumps": 3, "arc_factor": 0.6, "arc_radius": 5.0,
	},
	# Leichtes Maschinengewehr: großes Magazin, langes Nachladen.
	"lmg": {
		"name": "Marathonsendung", "damage": 20.0, "fire_rate": 11.0, "magazine": 100,
		"reload_time": 4.5, "spread_deg": 2.0, "pellets": 1, "automatic": true,
		"price": 1750, "explosion_radius": 0.0, "explosion_damage": 0.0,
	},
	# Automatische Schrotflinte: Dauerfeuer mit sieben Schrotkugeln.
	"auto_shotgun": {
		"name": "Zuschauerfrage", "damage": 11.0, "fire_rate": 3.0, "magazine": 8,
		"reload_time": 2.6, "spread_deg": 6.5, "pellets": 7, "automatic": true,
		"price": 2000, "explosion_radius": 0.0, "explosion_damage": 0.0,
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


## Sekunden zwischen zwei Schüssen. rate_bonus ist der Zusatz vom Schnelldurchlauf (fire_rate):
## 0,2 = 20 % schneller, die Schussfolge wird durch (1 + rate_bonus) geteilt.
static func fire_interval(weapon_id: String, rate_bonus: float = 0.0) -> float:
	if not WEAPONS.has(weapon_id):
		return 0.0
	return 1.0 / (float(WEAPONS[weapon_id]["fire_rate"]) * maxf(1.0 + rate_bonus, 0.01))


## Magazingröße mit dem Zusatz der Überlänge (big_mag): Grundgröße mal (1 + bonus), aufgerundet.
## Ohne Zusatz (oder mit einem negativen) die Grundgröße, 0 bei unbekannter ID.
static func magazine_size(weapon_id: String, bonus: float = 0.0) -> int:
	if not WEAPONS.has(weapon_id):
		return 0
	var base: int = int(WEAPONS[weapon_id]["magazine"])
	if bonus <= 0.0:
		return base
	# Der kleine Abzug fängt Rundungsfehler ab: 10 mal 1,3 soll 13 bleiben und nicht 14 werden.
	return maxi(base, ceili(float(base) * (1.0 + bonus) - 0.0001))


## Streuung der Waffe in Grad (halber Winkel). scoped = true: mit Teleprompter (scope), also mal
## Balance.SCOPE_SPREAD_FACTOR.
static func spread_deg(weapon_id: String, scoped: bool = false) -> float:
	if not WEAPONS.has(weapon_id):
		return 0.0
	var spread: float = float(WEAPONS[weapon_id]["spread_deg"])
	return spread * Balance.SCOPE_SPREAD_FACTOR if scoped else spread


## Schaden je Sekunde bei Dauerfeuer auf ein Ziel, ohne Nachladen, Kopftreffer, Explosion, Brand
## und Sprünge. Eine Salve zählt mit allen ihren Schüssen.
static func dps(weapon_id: String) -> float:
	if not WEAPONS.has(weapon_id):
		return 0.0
	var def: Dictionary = WEAPONS[weapon_id]
	return float(def["damage"]) * float(int(def["pellets"])) * float(burst(weapon_id)) * float(def["fire_rate"])


## Schussart: MODE_BULLET (Standard), MODE_GRENADE, MODE_FLAME oder MODE_BEAM. "" bei unbekannter ID.
static func mode(weapon_id: String) -> String:
	if not WEAPONS.has(weapon_id):
		return ""
	return str((WEAPONS[weapon_id] as Dictionary).get("mode", MODE_BULLET))


## Schüsse je Abzug (Salve), mindestens 1. 0 bei unbekannter ID.
static func burst(weapon_id: String) -> int:
	if not WEAPONS.has(weapon_id):
		return 0
	return maxi(1, int((WEAPONS[weapon_id] as Dictionary).get("burst", 1)))


## Sekunden zwischen zwei Schüssen einer Salve (0 ohne Salve).
static func burst_interval(weapon_id: String) -> float:
	return _number(weapon_id, "burst_interval", 0.0)


## So viele weitere Zombies durchschlägt eine Kugel dieser Waffe von sich aus (0 = keinen,
## PIERCE_ALL = alle). Der Gegenstand Spezialmunition kommt dazu.
static func pierce(weapon_id: String) -> int:
	return int(_number(weapon_id, "pierce", 0.0))


## Eingebauter Blitz: Jeder Treffer springt auf so viele weitere Zombies (0 = keiner).
static func arc_jumps(weapon_id: String) -> int:
	return int(_number(weapon_id, "arc_jumps", 0.0))


## Eingebauter Blitz: Anteil des Treffer-Schadens je Sprung (0,6 = 60 %).
static func arc_factor(weapon_id: String) -> float:
	return _number(weapon_id, "arc_factor", 0.0)


## Eingebauter Blitz: Umkreis in Metern, in dem er das nächste Ziel sucht.
static func arc_radius(weapon_id: String) -> float:
	return _number(weapon_id, "arc_radius", 0.0)


## Reichweite in Metern: bei "flame" die Länge des Kegels, sonst Balance.WEAPON_RANGE.
static func reach(weapon_id: String) -> float:
	return _number(weapon_id, "range", Balance.WEAPON_RANGE)


## Halber Öffnungswinkel des Flammenkegels in Grad (0 bei allen anderen Waffen).
static func cone_deg(weapon_id: String) -> float:
	return _number(weapon_id, "cone_deg", 0.0)


## Brand, den die Waffe von sich aus setzt: Schaden je Sekunde (fest, ohne Effekt-Faktor) und
## Dauer in Sekunden. 0 bei Waffen ohne Brand.
static func burn_dps(weapon_id: String) -> float:
	return _number(weapon_id, "burn_dps", 0.0)


static func burn_time(weapon_id: String) -> float:
	return _number(weapon_id, "burn_time", 0.0)


## Granate: Abschuss-Tempo in m/s und Schwerkraft in m/s² (0 bei allen anderen Waffen).
static func projectile_speed(weapon_id: String) -> float:
	return _number(weapon_id, "projectile_speed", 0.0)


static func projectile_gravity(weapon_id: String) -> float:
	return _number(weapon_id, "projectile_gravity", 0.0)


## Dauerfeuer bei gehaltenem Abzug?
static func is_automatic(weapon_id: String) -> bool:
	return WEAPONS.has(weapon_id) and bool((WEAPONS[weapon_id] as Dictionary).get("automatic", false))


## Zahl aus der Tabelle mit Standardwert. Bei unbekannter Waffe 0.
static func _number(weapon_id: String, key: String, fallback: float) -> float:
	if not WEAPONS.has(weapon_id):
		return 0.0
	return float((WEAPONS[weapon_id] as Dictionary).get(key, fallback))


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
## mal Durchschlag-Faktor für das wievielte Ziel. headshot_bonus ist der Zusatz vom Teleprompter
## (scope): Ein Kopftreffer zählt dann noch einmal mal (1 + headshot_bonus).
static func bullet_damage(weapon_id: String, headshot: bool, target_index: int = 0, headshot_bonus: float = 0.0) -> float:
	if not WEAPONS.has(weapon_id):
		return 0.0
	var damage: float = float(WEAPONS[weapon_id]["damage"])
	if headshot:
		damage *= Balance.HEADSHOT_MULTIPLIER * (1.0 + maxf(headshot_bonus, 0.0))
	return damage * pierce_damage_factor(target_index)


## Faktor eines Treffers aus Zugabe (extra_shot) und Glücksrad (crit): extra_factor ist der Anteil
## der Zusatzkugel am Kugelschaden (1,0 = normale Kugel), ein kritischer Treffer zählt mal
## Balance.CRIT_MULTIPLIER.
static func bonus_damage_factor(extra_factor: float, crit: bool) -> float:
	return maxf(extra_factor, 0.0) * (Balance.CRIT_MULTIPLIER if crit else 1.0)
