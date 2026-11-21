extends RefCounted
## Kameras (Abschnitt 22.1): fünf Kameratypen mit festen Werten je Rarität und die Rechnung, die
## aus Typ, Rarität und den Kamera-Gegenständen die fertigen Werte einer Kamera macht.
## Reine Daten und Rechenfunktionen, keine Nodes.
## Einbinden mit: const CameraDefs := preload("res://scripts/core/camera_defs.gd")
##
## Eine Kamera ist ein Gegenstand der Art "camera" (ItemDefs). Jedes eingeräumte Exemplar ist im
## Spiel ein eigener Knoten. Die Werte sind fest: kein Game.effect_factor(), kein
## UpgradeDefs.companion_factor. Stärker wird eine Kamera nur durch ihre Rarität und durch die
## Kamera-Gegenstände (Art "upgrade", ihre Stufenwerte stehen in UpgradeDefs):
##   cam_lens     Sterne auf der Kamera: mehr Schaden            (Schlüssel "bonus")
##   cam_zoom     Sterne auf der Kamera: mehr Reichweite          (Schlüssel "bonus")
##   cam_battery  Sterne auf der Kamera: schnellere Schussfolge   (Schlüssel "bonus")
##   cam_second   Sterne auf der Kamera: zweites Ziel mit Anteil  (Schlüssel "share")
##   cam_uplink   ohne Sterne: alle Kameras mehr Schaden und schnellere Schussfolge ("bonus")
## Mehrere Exemplare addieren sich. Schaden: Grundwert mal (1 + Objektive + Sendeleitungen).
## Abstand: Grundwert durch (1 + Akkupacks + Sendeleitungen). Reichweite: Grundwert mal (1 + Zooms).

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")

## Feste Reihenfolge der Kameratypen. "drone" ist die Kameradrohne von früher.
const ORDER: Array[String] = ["drone", "cam_tele", "cam_flash", "cam_slow", "cam_director"]
## Die Kamera-Gegenstände in fester Reihenfolge.
const MOD_ORDER: Array[String] = ["cam_lens", "cam_zoom", "cam_battery", "cam_second", "cam_uplink"]
const MOD_DAMAGE: String = "cam_lens"
const MOD_RANGE: String = "cam_zoom"
const MOD_RATE: String = "cam_battery"
const MOD_SECOND: String = "cam_second"
const MOD_UPLINK: String = "cam_uplink"

## Zeitlupen-Kamera: so lange bleibt ein getroffener Zombie langsamer (Sekunden).
const SLOW_DURATION: float = 2.0
## Regie-Kamera: so lange bleibt ein Zombie markiert (Sekunden).
const MARK_DURATION: float = 4.0
## Blitzlicht-Kamera: voller Öffnungswinkel des Kegels in Grad.
const FLASH_CONE_DEG: float = 90.0
## Zweitkamera auf der Blitzlicht-Kamera: so viel später kommt der zweite Blitz (Sekunden).
const SECOND_FLASH_DELAY: float = 0.4
## Kleinster Abstand zwischen zwei Schüssen, gleich wie viele Akkupacks wirken (Sekunden).
const MIN_INTERVAL: float = 0.05

## Je Kamera:
## name        Name im Spiel
## description Textvorlage mit {schlüssel}-Platzhaltern
## damage      Schaden je Schuss, 5 Werte (Gewöhnlich bis Legendär). Fehlt: kein Schaden.
## interval    Sekunden zwischen zwei Schüssen, 5 Werte
## range       Reichweite in Metern (für alle Raritäten gleich)
## pierce      Tele-Kamera: so viele weitere Zombies in der Linie trifft der Schuss, 5 Werte
## slow        Zeitlupen-Kamera: Verlangsamung als Bruchteil (0.3 = 30 % langsamer), 5 Werte
## mark        Regie-Kamera: Mehr-Schaden an Markierten als Bruchteil, 5 Werte
const CAMERAS: Dictionary = {
	"drone": {
		"name": "Kameradrohne",
		"description": "Eine fliegende Kamera schießt alle {interval} s auf den nächsten Zombie in {range} m. Schaden {damage}.",
		"damage": [15.0, 21.0, 28.0, 36.0, 46.0],
		"interval": [1.2, 1.0, 0.8, 0.65, 0.5],
		"range": 15.0,
	},
	"cam_tele": {
		"name": "Tele-Kamera",
		"description": "Schießt alle {interval} s einen starken Schuss bis {range} m weit. Schaden {damage}. Durchschlag {pierce}: So viele Zombies dahinter trifft er auch.",
		"damage": [70.0, 100.0, 135.0, 175.0, 220.0],
		"interval": [3.2, 2.9, 2.6, 2.3, 2.0],
		"range": 30.0,
		"pierce": [1, 1, 2, 2, 3],
	},
	"cam_flash": {
		"name": "Blitzlicht-Kamera",
		"description": "Blitzt alle {interval} s: {damage} Schaden an allen Zombies in einem Kegel von {cone} Grad bis {range} m.",
		"damage": [18.0, 25.0, 33.0, 42.0, 52.0],
		"interval": [3.0, 2.8, 2.6, 2.4, 2.2],
		"range": 7.0,
	},
	"cam_slow": {
		"name": "Zeitlupen-Kamera",
		"description": "Schießt alle {interval} s auf einen Zombie in {range} m: {damage} Schaden, und er ist {slow_duration} s lang {slow} % langsamer (Elite: halbe Wirkung).",
		"damage": [4.0, 6.0, 8.0, 10.0, 12.0],
		"interval": [1.5, 1.4, 1.3, 1.2, 1.1],
		"range": 12.0,
		"slow": [0.30, 0.35, 0.40, 0.45, 0.50],
	},
	"cam_director": {
		"name": "Regie-Kamera",
		"description": "Markiert alle {interval} s einen Zombie in {range} m für {mark_duration} s (zuerst Elite). Markierte nehmen aus jeder Quelle {mark} % mehr Schaden. Macht selbst keinen Schaden.",
		"interval": [3.0, 2.7, 2.4, 2.1, 1.8],
		"range": 18.0,
		"mark": [0.20, 0.25, 0.30, 0.40, 0.50],
	},
}


## Alle Kameratypen in fester Reihenfolge.
static func all_ids() -> Array[String]:
	return ORDER.duplicate()


## Gibt es diesen Kameratyp?
static func has(camera_id: String) -> bool:
	return CAMERAS.has(camera_id)


## Ist das ein Kamera-Gegenstand (Objektiv, Zoom, Akkupack, Zweitkamera, Sendeleitung)?
static func is_mod(item_id: String) -> bool:
	return MOD_ORDER.has(item_id)


## Name im Spiel, bei unbekannter ID die ID selbst.
static func display_name(camera_id: String) -> String:
	if not CAMERAS.has(camera_id):
		return camera_id
	return str(CAMERAS[camera_id]["name"])


## Grundwert einer Kamera für die Rarität level (1 bis 5), ohne Gegenstände. key: "damage",
## "interval", "range", "pierce", "slow", "mark". 0.0 bei unbekannter Kamera, unbekanntem
## Schlüssel oder level <= 0. Raritäten über 5 liefern den Wert der Rarität 5.
static func base(camera_id: String, key: String, level: int) -> float:
	if level <= 0 or not CAMERAS.has(camera_id):
		return 0.0
	var def: Dictionary = CAMERAS[camera_id]
	if not def.has(key):
		return 0.0
	var entry: Variant = def[key]
	if entry is Array:
		var per_level: Array = entry
		return float(per_level[mini(level, Balance.UPGRADE_MAX_LEVEL) - 1])
	return float(entry)


## Summe der Stufenwerte eines Kamera-Gegenstands über alle Exemplare (levels = ihre Raritäten).
static func mod_total(mod_id: String, key: String, levels: Variant) -> float:
	var total: float = 0.0
	if levels is Array:
		for level: Variant in levels as Array:
			total += UpgradeDefs.value(mod_id, key, int(level))
	return total


## Die fertigen Werte einer Kamera (reine Funktion).
## camera_id  Kameratyp
## level      Rarität der Kamera (1 bis 5)
## mods       Kamera-Gegenstände, deren Sterne auf dieser Kamera liegen:
##            mod_id -> Array mit der Rarität jedes Exemplars (eine Wiederholung zählt als weiteres)
## uplinks    Raritäten aller wirkenden Sendeleitungen (cam_uplink)
## Ergebnis (leer bei unbekannter Kamera):
##   { "id": String, "level": int,
##     "damage": float        Schaden je Schuss, 0 bei der Regie-Kamera
##     "interval": float      Sekunden zwischen zwei Schüssen
##     "range": float         Reichweite in Metern
##     "pierce": int          so viele weitere Zombies in der Linie (nur Tele-Kamera, sonst 0)
##     "slow": float          Verlangsamung als Bruchteil (nur Zeitlupen-Kamera, sonst 0)
##     "slow_duration": float Sekunden (SLOW_DURATION)
##     "mark": float          Mehr-Schaden an Markierten als Bruchteil (nur Regie-Kamera, sonst 0)
##     "mark_duration": float Sekunden (MARK_DURATION)
##     "second": float        Anteil der Wirkung für das zweite Ziel (0 = keine Zweitkamera)
##     "cone_deg": float      Öffnungswinkel des Blitzes (nur Blitzlicht-Kamera, sonst 0)
##     "damage_bonus", "rate_bonus", "range_bonus": float  die Zuschläge als Bruchteile (Anzeige) }
static func stats(camera_id: String, level: int, mods: Dictionary = {}, uplinks: Array = []) -> Dictionary:
	if not CAMERAS.has(camera_id):
		return {}
	var rarity: int = clampi(level, 1, Balance.UPGRADE_MAX_LEVEL)
	var uplink: float = mod_total(MOD_UPLINK, "bonus", uplinks)
	var damage_bonus: float = mod_total(MOD_DAMAGE, "bonus", mods.get(MOD_DAMAGE, [])) + uplink
	var rate_bonus: float = mod_total(MOD_RATE, "bonus", mods.get(MOD_RATE, [])) + uplink
	var range_bonus: float = mod_total(MOD_RANGE, "bonus", mods.get(MOD_RANGE, []))
	return {
		"id": camera_id,
		"level": rarity,
		"damage": base(camera_id, "damage", rarity) * (1.0 + damage_bonus),
		"interval": maxf(base(camera_id, "interval", rarity) / (1.0 + rate_bonus), MIN_INTERVAL),
		"range": base(camera_id, "range", rarity) * (1.0 + range_bonus),
		"pierce": int(base(camera_id, "pierce", rarity)),
		"slow": base(camera_id, "slow", rarity),
		"slow_duration": SLOW_DURATION,
		"mark": base(camera_id, "mark", rarity),
		"mark_duration": MARK_DURATION,
		"second": mod_total(MOD_SECOND, "share", mods.get(MOD_SECOND, [])),
		"cone_deg": FLASH_CONE_DEG if camera_id == "cam_flash" else 0.0,
		"damage_bonus": damage_bonus,
		"rate_bonus": rate_bonus,
		"range_bonus": range_bonus,
	}


## Deutscher Wirkungstext einer Kamera mit den Grundwerten der Rarität (ohne Gegenstände).
## Leerer Text bei unbekannter ID.
static func effect_text(camera_id: String, level: int) -> String:
	if not CAMERAS.has(camera_id):
		return ""
	var rarity: int = clampi(level, 1, Balance.UPGRADE_MAX_LEVEL)
	var fields: Dictionary = {
		"damage": UpgradeDefs.format_number(base(camera_id, "damage", rarity)),
		"interval": UpgradeDefs.format_number(base(camera_id, "interval", rarity)),
		"range": UpgradeDefs.format_number(base(camera_id, "range", rarity)),
		"pierce": UpgradeDefs.format_number(base(camera_id, "pierce", rarity)),
		"slow": UpgradeDefs.format_percent(base(camera_id, "slow", rarity)),
		"mark": UpgradeDefs.format_percent(base(camera_id, "mark", rarity)),
		"slow_duration": UpgradeDefs.format_number(SLOW_DURATION),
		"mark_duration": UpgradeDefs.format_number(MARK_DURATION),
		"cone": UpgradeDefs.format_number(FLASH_CONE_DEG),
	}
	return str(CAMERAS[camera_id]["description"]).format(fields)
