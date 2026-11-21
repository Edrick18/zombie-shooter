extends RefCounted
## Upgrade-Tabelle (Abschnitt 8 "Upgrades"): Namen, Texte, Stufenwerte und die Synergie.
## Reine Daten und Textfunktionen, keine Nodes.
## Besitzer: Fundament. Einbinden mit: const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")

const Balance := preload("res://scripts/core/balance.gd")

const MAX_LEVEL: int = Balance.UPGRADE_MAX_LEVEL

## Feste Reihenfolge der ursprünglichen Upgrades (für Listen und Tests). Die Kameradrohne steht
## seit Abschnitt 22 nicht mehr hier: Kameras sind eine eigene Art mit festen Werten (CameraDefs).
const ORDER: Array[String] = [
	"chain_lightning", "pierce", "burn", "lifesteal", "max_hp",
	"corpse_explosion", "reload_shockwave", "speed", "luck",
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
	# --- Abschnitt 19: Gegenstände, die es nur im Rucksack gibt (nicht in ORDER) ---
	"extra_shot": {
		"name": "Zugabe",
		"description": "Die Waffe schießt je Schuss {shots} zusätzliche Kugel mit {damage_factor} % Schaden.",
		"values": {
			"shots": [1, 1, 1, 1, 1],
			"damage_factor": [0.5, 0.6, 0.7, 0.85, 1.0],
		},
		"fixed": {},
		"format": {"shots": "number", "damage_factor": "percent"},
	},
	"poison": {
		"name": "Kantinenessen",
		"description": "Treffer vergiften Zombies {duration} s lang: {dps} Schaden je Sekunde.",
		"values": {
			"dps": [6, 10, 14, 18, 24],
		},
		"fixed": {"duration": Balance.POISON_DURATION},
		"format": {"dps": "number", "duration": "number"},
	},
	"crit": {
		"name": "Glücksrad",
		"description": "{chance} % Chance auf einen kritischen Treffer mit {multiplier}-fachem Schaden.",
		"values": {
			"chance": [0.10, 0.15, 0.20, 0.25, 0.30],
		},
		"fixed": {"multiplier": Balance.CRIT_MULTIPLIER},
		"format": {"chance": "percent", "multiplier": "number"},
	},
	"big_mag": {
		"name": "Überlänge",
		"description": "+{bonus} % Magazingröße.",
		"values": {
			"bonus": [0.3, 0.45, 0.6, 0.8, 1.0],
		},
		"fixed": {},
		"format": {"bonus": "percent"},
	},
	"scope": {
		"name": "Teleprompter",
		"description": "Halbe Streuung und +{headshot_bonus} % Kopfschuss-Schaden.",
		"values": {
			"headshot_bonus": [0.25, 0.35, 0.5, 0.6, 0.75],
		},
		"fixed": {},
		"format": {"headshot_bonus": "percent"},
	},
	"fire_rate": {
		"name": "Schnelldurchlauf",
		"description": "Die Waffe schießt {bonus} % schneller.",
		"values": {
			"bonus": [0.10, 0.15, 0.20, 0.25, 0.30],
		},
		"fixed": {},
		"format": {"bonus": "percent"},
	},
	"shield": {
		"name": "Sicherheitsglas",
		"description": "Schild mit {amount} Punkten. Es lädt sich wieder auf, wenn du {delay} s keinen Schaden nimmst.",
		"values": {
			"amount": [20, 30, 40, 50, 60],
		},
		"fixed": {"delay": Balance.SHIELD_RECHARGE_DELAY},
		"format": {"amount": "number", "delay": "number"},
	},
	"kill_heal": {
		"name": "Trostpflaster",
		"description": "Jeder Kill heilt {heal} Leben.",
		"values": {
			"heal": [2, 3, 4, 5, 6],
		},
		"fixed": {},
		"format": {"heal": "number"},
	},
	"disco_ball": {
		"name": "Discokugel",
		"description": "Kreist um dich und macht {damage} Schaden an jedem Zombie, den sie berührt. Mehrere Kugeln teilen ihre Kraft.",
		"values": {
			"damage": [15, 22, 30, 40, 55],
		},
		"fixed": {},
		"format": {"damage": "number"},
	},
	"jammer": {
		"name": "Störsender",
		"description": "Alle {pause} s ein Elektroschlag auf Zombies im Umkreis von {radius} m: {damage} Schaden.",
		"values": {
			"damage": [30, 45, 60, 80, 100],
			"radius": [4.0, 4.5, 5.0, 5.5, 6.0],
		},
		"fixed": {"pause": Balance.JAMMER_INTERVAL},
		"format": {"damage": "number", "radius": "number", "pause": "number"},
	},
	"dash": {
		"name": "Notausgang",
		"description": "Ausweichsprung in Laufrichtung mit der Taste Q. Abklingzeit {cooldown} s. Jedes weitere Exemplar gibt einen Sprung mehr.",
		"values": {
			"cooldown": [4.0, 3.5, 3.0, 2.5, 2.0],
			"charges": [1, 1, 1, 1, 1],
		},
		"fixed": {},
		"format": {"cooldown": "number", "charges": "number"},
	},
	# --- Abschnitt 22.3: für die Waffe auf den Sternen ---
	"frost": {
		"name": "Trockeneis",
		"description": "Kugeltreffer machen Zombies {duration} s lang {slow} % langsamer (Elite: halbe Wirkung).",
		"values": {
			"slow": [0.20, 0.25, 0.30, 0.35, 0.40],
		},
		"fixed": {"duration": Balance.FROST_DURATION},
		"format": {"slow": "percent", "duration": "number"},
	},
	"opener": {
		"name": "Eröffnungsgag",
		"description": "Die erste Kugel jedes Magazins macht +{bonus} % Schaden.",
		"values": {
			"bonus": [1.0, 1.5, 2.0, 2.75, 3.5],
		},
		"fixed": {},
		"format": {"bonus": "percent"},
	},
	"punchline": {
		"name": "Schlusspointe",
		"description": "Die letzte Kugel jedes Magazins explodiert am Einschlag: Radius {radius} m, Schaden {damage}.",
		"values": {
			"damage": [60, 90, 120, 160, 200],
		},
		"fixed": {"radius": Balance.PUNCHLINE_RADIUS},
		"format": {"damage": "number", "radius": "number"},
	},
	"ricochet": {
		"name": "Querschläger",
		"description": "Kugeltreffer springen mit {chance} % auf einen weiteren Zombie im Umkreis von {radius} m, mit {factor} % des Schadens.",
		"values": {
			"chance": [0.20, 0.30, 0.40, 0.50, 0.60],
		},
		"fixed": {"radius": Balance.RICOCHET_RADIUS, "factor": Balance.RICOCHET_DAMAGE_FACTOR},
		"format": {"chance": "percent", "radius": "number", "factor": "percent"},
	},
	# --- Abschnitt 22.3: für den Spieler als Ganzes ---
	"thorns": {
		"name": "Kaktus-Requisite",
		"description": "Trifft dich ein Zombie, nehmen alle Zombies im Umkreis von {radius} m {damage} Schaden.",
		"values": {
			"damage": [40, 60, 80, 110, 140],
		},
		"fixed": {"radius": Balance.THORNS_RADIUS},
		"format": {"damage": "number", "radius": "number"},
	},
	"revive": {
		"name": "Zweite Staffel",
		"description": "Ein tödlicher Treffer tötet dich nicht: Du stehst mit {hp} % Leben wieder auf, bist {safe} s unverwundbar und stößt alle Zombies weg. Kommt nach {waves} geschafften Wellen wieder. Jedes Exemplar ist eine Ladung.",
		"values": {
			"waves": [5, 4, 4, 3, 3],
		},
		"fixed": {"hp": Balance.REVIVE_HP_SHARE, "safe": Balance.REVIVE_INVULNERABILITY},
		"format": {"waves": "number", "hp": "percent", "safe": "number"},
	},
	"snack": {
		"name": "Pausensnack",
		"description": "Am Ende jeder Welle heilst du zusätzlich {heal} Leben.",
		"values": {
			"heal": [10, 15, 20, 25, 35],
		},
		"fixed": {},
		"format": {"heal": "number"},
	},
	"mine": {
		"name": "Requisitenbombe",
		"description": "Legt alle {interval} s eine Mine an deine Füße (höchstens {limit} zugleich). Kommt ein Zombie heran, explodiert sie: Radius {radius} m, Schaden {damage}.",
		"values": {
			"interval": [8.0, 7.0, 6.0, 5.0, 4.0],
			"damage": [70, 100, 130, 170, 220],
		},
		"fixed": {"limit": Balance.MINE_MAX_ACTIVE, "radius": Balance.MINE_RADIUS},
		"format": {"interval": "number", "damage": "number", "limit": "number", "radius": "number"},
	},
	# --- Abschnitt 22.1: Kamera-Gegenstände (wirken auf die Kamera auf ihren Sternen, die
	# Sendeleitung ohne Sterne auf alle Kameras). Die Rechnung steht in CameraDefs.stats. ---
	"cam_lens": {
		"name": "Großes Objektiv",
		"description": "+{bonus} % Schaden für die Kamera.",
		"values": {
			"bonus": [0.20, 0.30, 0.40, 0.55, 0.70],
		},
		"fixed": {},
		"format": {"bonus": "percent"},
	},
	"cam_zoom": {
		"name": "Zoom",
		"description": "+{bonus} % Reichweite für die Kamera.",
		"values": {
			"bonus": [0.20, 0.30, 0.40, 0.50, 0.60],
		},
		"fixed": {},
		"format": {"bonus": "percent"},
	},
	"cam_battery": {
		"name": "Akkupack",
		"description": "Die Kamera schießt {bonus} % schneller.",
		"values": {
			"bonus": [0.15, 0.25, 0.35, 0.45, 0.60],
		},
		"fixed": {},
		"format": {"bonus": "percent"},
	},
	"cam_second": {
		"name": "Zweitkamera",
		"description": "Jeder Schuss der Kamera trifft ein zweites Ziel mit {share} % der Wirkung.",
		"values": {
			"share": [0.40, 0.55, 0.70, 0.85, 1.0],
		},
		"fixed": {},
		"format": {"share": "percent"},
	},
	"cam_uplink": {
		"name": "Sendeleitung",
		"description": "Alle Kameras machen +{bonus} % Schaden und schießen {bonus} % schneller.",
		"values": {
			"bonus": [0.08, 0.12, 0.16, 0.20, 0.25],
		},
		"fixed": {},
		"format": {"bonus": "percent"},
	},
}

## Upgrades aus den Abschnitten 19 und 22: Es gibt sie nur als Gegenstand im Rucksack. Sie stehen
## nicht in ORDER (das sind die ursprünglichen Upgrades).
const ITEM_ONLY: Array[String] = [
	"extra_shot", "poison", "crit", "big_mag", "scope", "fire_rate",
	"shield", "kill_heal", "disco_ball", "jammer", "dash",
	"frost", "opener", "punchline", "ricochet",
	"thorns", "revive", "snack", "mine",
	"cam_lens", "cam_zoom", "cam_battery", "cam_second", "cam_uplink",
]

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
## Abschnitt 22: "slow" (Trockeneis) nimmt den stärksten Wert, weil auch am Zombie nur die
## stärkste Verlangsamung gilt. "waves" (Zweite Staffel) nimmt den kleinsten, die Ladungen selbst
## zählt man über UpgradeState.copies("revive"). "interval" der Requisitenbombe nimmt wie alle
## Abstände den kleinsten, ihr "damage" addiert sich.
const STACK_MODES: Dictionary = {
	"radius": "max", "range": "max", "damage_factor": "max", "damage_percent": "max", "interval": "min",
	"cooldown": "min", "slow": "max", "waves": "min",
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


## Schadensfaktor je Begleiter, wenn count gleiche Begleiter unterwegs sind (Discokugeln):
## 1 / count hoch Balance.COMPANION_STACK_EXPONENT. Ein einzelner macht vollen Schaden.
## Für Kameras gilt er seit Abschnitt 22 nicht mehr: Sie haben feste Werte.
static func companion_factor(count: int) -> float:
	return 1.0 / pow(float(maxi(count, 1)), Balance.COMPANION_STACK_EXPONENT)


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
