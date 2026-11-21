extends RefCounted
## Upgrade-Tabelle (Abschnitt 8 "Upgrades"): Namen, Texte, Stufenwerte und die Synergie.
## Reine Daten und Textfunktionen, keine Nodes.
## Besitzer: Fundament. Einbinden mit: const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")

const Balance := preload("res://scripts/core/balance.gd")

const MAX_LEVEL: int = Balance.UPGRADE_MAX_LEVEL

## Feste Reihenfolge aller Upgrades (für Listen und Tests).
const ORDER: Array[String] = [
	"chain_lightning", "pierce", "burn", "lifesteal", "max_hp",
	"corpse_explosion", "reload_shockwave", "drone", "speed", "luck",
]

## Je Upgrade:
## name        Name im Spiel
## description Textvorlage mit {schlüssel}-Platzhaltern für Stufenwerte und feste Werte
## values      Stufenwerte: schlüssel -> Array mit 5 Werten (Index 0 = Stufe 1)
## fixed       feste Werte aus Balance, nur für den Text
## format      Darstellung je Schlüssel: "percent" (0.15 -> "15") oder "number" (3.25 -> "3,25")
##
## Anteile und Chancen stehen als Bruchteil (0.1 = 10 %), nicht als Prozentzahl.
const UPGRADES: Dictionary = {
	"chain_lightning": {
		"name": "Starkstrom-Sponsor",
		"description": "Kugeltreffer lösen mit {chance} % einen Blitz aus. Er springt auf {jumps} weitere Zombies im Umkreis von {radius} m und macht {damage_factor} % des Kugelschadens.",
		"values": {
			"chance": [0.10, 0.15, 0.20, 0.25, 0.30],
			"jumps": [2, 3, 4, 5, 6],
			"damage_factor": [0.5, 0.6, 0.7, 0.8, 1.0],
		},
		"fixed": {"radius": Balance.CHAIN_RADIUS},
		"format": {"chance": "percent", "jumps": "number", "damage_factor": "percent", "radius": "number"},
	},
	"pierce": {
		"name": "Spezialmunition",
		"description": "Kugeln durchschlagen Zombies. Zusätzliche Ziele je Kugel: {targets}. Je weiterem Ziel −{falloff} % Schaden.",
		"values": {
			"targets": [1, 2, 3, 4, 5],
		},
		"fixed": {"falloff": Balance.PIERCE_DAMAGE_FALLOFF},
		"format": {"targets": "number", "falloff": "percent"},
	},
	"burn": {
		"name": "Feuershow",
		"description": "Kugeltreffer setzen Zombies {duration} s in Brand: {dps_percent} % ihres Maximal-Lebens je Sekunde.",
		"values": {
			"dps_percent": [0.03, 0.05, 0.07, 0.09, 0.12],
		},
		"fixed": {"duration": Balance.BURN_DURATION},
		"format": {"dps_percent": "percent", "duration": "number"},
	},
	"lifesteal": {
		"name": "Blutspende-Aktion",
		"description": "{ratio} % allen verursachten Schadens heilen dich, höchstens {cap} Leben je Sekunde.",
		"values": {
			"ratio": [0.02, 0.04, 0.06, 0.08, 0.10],
		},
		"fixed": {"cap": Balance.LIFESTEAL_MAX_PER_SECOND},
		"format": {"ratio": "percent", "cap": "number"},
	},
	"max_hp": {
		"name": "Stuntdouble",
		"description": "+{bonus} Maximal-Leben. Heilt beim Erhalt um den Zuwachs.",
		"values": {
			"bonus": [20, 40, 60, 80, 100],
		},
		"fixed": {},
		"format": {"bonus": "number"},
	},
	"corpse_explosion": {
		"name": "Konfetti-Kanone",
		"description": "Getötete Zombies explodieren mit {chance} % in Konfetti: Radius {radius} m, Schaden {damage_percent} % des Maximal-Lebens des Toten.",
		"values": {
			"chance": [0.15, 0.20, 0.25, 0.30, 0.35],
			"radius": [3.0, 3.25, 3.5, 3.75, 4.0],
			"damage_percent": [0.30, 0.40, 0.50, 0.60, 0.75],
		},
		"fixed": {},
		"format": {"chance": "percent", "radius": "number", "damage_percent": "percent"},
	},
	"reload_shockwave": {
		"name": "Werbepause",
		"description": "Beim Nachladen stößt eine Druckwelle Zombies weg: Radius {radius} m, Schaden {damage}. Abklingzeit {cooldown} s.",
		"values": {
			"radius": [4.0, 4.5, 5.0, 5.5, 6.0],
			"damage": [20, 35, 50, 65, 80],
		},
		"fixed": {"cooldown": Balance.SHOCKWAVE_COOLDOWN},
		"format": {"radius": "number", "damage": "number", "cooldown": "number"},
	},
	"drone": {
		"name": "Kameradrohne",
		"description": "Eine fliegende Kamera schießt alle {interval} s auf den nächsten Zombie in {range} m. Schaden {damage}.",
		"values": {
			"interval": [1.2, 1.0, 0.8, 0.65, 0.5],
			"damage": [12, 16, 20, 24, 30],
		},
		"fixed": {"range": Balance.DRONE_RANGE},
		"format": {"interval": "number", "damage": "number", "range": "number"},
	},
	"speed": {
		"name": "Turbo-Turnschuhe",
		"description": "+{bonus} % Lauftempo.",
		"values": {
			"bonus": [0.08, 0.16, 0.24, 0.32, 0.40],
		},
		"fixed": {},
		"format": {"bonus": "percent"},
	},
	"luck": {
		"name": "Publikumsliebling",
		"description": "+{points_bonus} % Punkte, +{chest_chance} %-Punkte Kistenchance bei normalen Zombies, bessere Kisten.",
		"values": {
			"points_bonus": [0.10, 0.20, 0.30, 0.40, 0.50],
			"chest_chance": [0.01, 0.02, 0.03, 0.04, 0.05],
		},
		"fixed": {},
		"format": {"points_bonus": "percent", "chest_chance": "percent"},
	},
}

## Synergien: name, description (Textvorlage), requires (upgrade_id -> Mindeststufe),
## fixed und format wie bei den Upgrades. Eine Synergie belegt keinen Platz.
const SYNERGIES: Dictionary = {
	"storm_front": {
		"name": "Gewitterfront",
		"description": "Jeder Kugeltreffer löst sicher einen Blitz aus, höchstens {max_procs} Blitze je Schuss.",
		"requires": {"chain_lightning": 5, "pierce": 5},
		"fixed": {"max_procs": Balance.STORM_FRONT_MAX_PROCS_PER_SHOT},
		"format": {"max_procs": "number"},
	},
}


## Alle Upgrade-IDs in fester Reihenfolge.
static func all_ids() -> Array[String]:
	return ORDER.duplicate()


## Gibt es dieses Upgrade?
static func has(upgrade_id: String) -> bool:
	return UPGRADES.has(upgrade_id)


## Name im Spiel, bei unbekannter ID die ID selbst.
static func display_name(upgrade_id: String) -> String:
	if not UPGRADES.has(upgrade_id):
		return upgrade_id
	return String(UPGRADES[upgrade_id]["name"])


## Schlüssel der Stufenwerte eines Upgrades (z. B. ["chance", "jumps", "damage_factor"]).
static func value_keys(upgrade_id: String) -> Array[String]:
	var keys: Array[String] = []
	if UPGRADES.has(upgrade_id):
		for key: String in UPGRADES[upgrade_id]["values"]:
			keys.append(key)
	return keys


## Wert eines Schlüssels auf einer Stufe (1 bis 5). 0.0 bei Stufe 0, unbekannter ID oder
## unbekanntem Schlüssel. Stufen über 5 liefern den Wert der Stufe 5.
static func value(upgrade_id: String, key: String, level: int) -> float:
	if level <= 0 or not UPGRADES.has(upgrade_id):
		return 0.0
	var values: Dictionary = UPGRADES[upgrade_id]["values"]
	if not values.has(key):
		return 0.0
	var per_level: Array = values[key]
	return float(per_level[mini(level, MAX_LEVEL) - 1])


## Wie sich die Werte mehrerer Exemplare desselben Upgrades verbinden. Standard: addieren.
## "max": der beste Wert zählt (Reichweiten, Schadensanteile). "min": der kleinste (Abstände).
## Werte mit dem Schlüssel "chance" addieren sich und enden bei 1,0.
const STACK_MODES: Dictionary = {
	"radius": "max", "range": "max", "damage_factor": "max", "damage_percent": "max", "interval": "min",
}


## Wert von mehreren Exemplaren desselben Upgrades zusammen. levels sind die Stufen (Raritäten)
## der Exemplare. Ein Exemplar ergibt dasselbe wie value().
static func combined_value(upgrade_id: String, key: String, levels: Array) -> float:
	var mode: String = str(STACK_MODES.get(key, "sum"))
	var result: float = 0.0
	var first: bool = true
	for level: Variant in levels:
		if int(level) <= 0:
			continue
		var single: float = value(upgrade_id, key, int(level))
		if first:
			result = single
			first = false
		elif mode == "max":
			result = maxf(result, single)
		elif mode == "min":
			result = minf(result, single)
		else:
			result += single
	if key == "chance":
		result = minf(result, 1.0)
	return result


## Deutscher Wirkungstext eines Upgrades mit den Zahlen der angegebenen Stufe (1 bis 5).
## Für Kistenwahl und HUD. Leerer Text bei unbekannter ID.
static func effect_text(upgrade_id: String, level: int) -> String:
	if not UPGRADES.has(upgrade_id):
		return ""
	var def: Dictionary = UPGRADES[upgrade_id]
	var shown_level: int = clampi(level, 1, MAX_LEVEL)
	var formats: Dictionary = def["format"]
	var fields: Dictionary = {}
	var values: Dictionary = def["values"]
	for key: String in values:
		fields[key] = _format_value(float(values[key][shown_level - 1]), String(formats.get(key, "number")))
	var fixed: Dictionary = def["fixed"]
	for key: String in fixed:
		fields[key] = _format_value(float(fixed[key]), String(formats.get(key, "number")))
	return String(def["description"]).format(fields)


## Alle Synergie-IDs.
static func synergy_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in SYNERGIES:
		ids.append(id)
	return ids


## Name der Synergie im Spiel, bei unbekannter ID die ID selbst.
static func synergy_name(synergy_id: String) -> String:
	if not SYNERGIES.has(synergy_id):
		return synergy_id
	return String(SYNERGIES[synergy_id]["name"])


## Deutscher Wirkungstext der Synergie. Leerer Text bei unbekannter ID.
static func synergy_text(synergy_id: String) -> String:
	if not SYNERGIES.has(synergy_id):
		return ""
	var def: Dictionary = SYNERGIES[synergy_id]
	var formats: Dictionary = def["format"]
	var fields: Dictionary = {}
	var fixed: Dictionary = def["fixed"]
	for key: String in fixed:
		fields[key] = _format_value(float(fixed[key]), String(formats.get(key, "number")))
	return String(def["description"]).format(fields)


## Voraussetzungen der Synergie: upgrade_id -> Mindeststufe. Leer bei unbekannter ID.
static func synergy_requirements(synergy_id: String) -> Dictionary:
	if not SYNERGIES.has(synergy_id):
		return {}
	return SYNERGIES[synergy_id]["requires"]


## Zahl in deutscher Schreibweise: höchstens zwei Nachkommastellen, Komma, keine Null-Enden
## (3.25 -> "3,25", 4.0 -> "4", 0.5 -> "0,5").
static func format_number(number: float) -> String:
	var text: String = "%.2f" % number
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return text.replace(".", ",")


## Bruchteil als ganze Prozentzahl ohne Zeichen (0.15 -> "15").
static func format_percent(fraction: float) -> String:
	return str(roundi(fraction * 100.0))


static func _format_value(number: float, kind: String) -> String:
	if kind == "percent":
		return format_percent(number)
	return format_number(number)
