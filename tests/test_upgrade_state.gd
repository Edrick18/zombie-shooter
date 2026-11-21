extends SceneTree
## Tests für UpgradeDefs und UpgradeState: jede Stufenzahl gegen die Tabelle der Architektur,
## Plätze, Wählbarkeit, Synergie, abgeleitete Werte und Wirkungstexte.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")

## Abschrift der Tabelle aus Abschnitt 8 "Upgrades" (Anteile als Bruchteil).
const EXPECTED: Dictionary = {
	"chain_lightning": {
		"chance": [0.10, 0.15, 0.20, 0.25, 0.30],
		"jumps": [2.0, 3.0, 4.0, 5.0, 6.0],
		"damage_factor": [0.5, 0.6, 0.7, 0.8, 1.0],
	},
	"pierce": {"targets": [1.0, 2.0, 3.0, 4.0, 5.0]},
	"burn": {"dps_percent": [0.03, 0.05, 0.07, 0.09, 0.12]},
	"lifesteal": {"ratio": [0.02, 0.04, 0.06, 0.08, 0.10]},
	"max_hp": {"bonus": [20.0, 40.0, 60.0, 80.0, 100.0]},
	"corpse_explosion": {
		"chance": [0.15, 0.20, 0.25, 0.30, 0.35],
		"radius": [3.0, 3.25, 3.5, 3.75, 4.0],
		"damage_percent": [0.30, 0.40, 0.50, 0.60, 0.75],
	},
	"reload_shockwave": {
		"radius": [4.0, 4.5, 5.0, 5.5, 6.0],
		"damage": [20.0, 35.0, 50.0, 65.0, 80.0],
	},
	"speed": {"bonus": [0.08, 0.16, 0.24, 0.32, 0.40]},
	"luck": {
		"points_bonus": [0.10, 0.20, 0.30, 0.40, 0.50],
		"chest_chance": [0.01, 0.02, 0.03, 0.04, 0.05],
	},
}

## Abschrift der Tabellen aus Abschnitt 22.1 (Kamera-Gegenstände) und 22.3 (neue Gegenstände).
const EXPECTED_ITEMS: Dictionary = {
	"frost": {"slow": [0.20, 0.25, 0.30, 0.35, 0.40]},
	"opener": {"bonus": [1.0, 1.5, 2.0, 2.75, 3.5]},
	"punchline": {"damage": [60.0, 90.0, 120.0, 160.0, 200.0]},
	"ricochet": {"chance": [0.20, 0.30, 0.40, 0.50, 0.60]},
	"thorns": {"damage": [40.0, 60.0, 80.0, 110.0, 140.0]},
	"revive": {"waves": [5.0, 4.0, 4.0, 3.0, 3.0]},
	"snack": {"heal": [10.0, 15.0, 20.0, 25.0, 35.0]},
	"mine": {
		"interval": [8.0, 7.0, 6.0, 5.0, 4.0],
		"damage": [70.0, 100.0, 130.0, 170.0, 220.0],
	},
	"cam_lens": {"bonus": [0.20, 0.30, 0.40, 0.55, 0.70]},
	"cam_zoom": {"bonus": [0.20, 0.30, 0.40, 0.50, 0.60]},
	"cam_battery": {"bonus": [0.15, 0.25, 0.35, 0.45, 0.60]},
	"cam_second": {"share": [0.40, 0.55, 0.70, 0.85, 1.0]},
	"cam_uplink": {"bonus": [0.08, 0.12, 0.16, 0.20, 0.25]},
}

const EXPECTED_ITEM_NAMES: Dictionary = {
	"frost": "Trockeneis", "opener": "Eröffnungsgag", "punchline": "Schlusspointe", "ricochet": "Querschläger",
	"thorns": "Kaktus-Requisite", "revive": "Zweite Staffel", "snack": "Pausensnack", "mine": "Requisitenbombe",
	"cam_lens": "Großes Objektiv", "cam_zoom": "Zoom", "cam_battery": "Akkupack", "cam_second": "Zweitkamera",
	"cam_uplink": "Sendeleitung",
}

const EXPECTED_NAMES: Dictionary = {
	"chain_lightning": "Starkstrom-Sponsor",
	"pierce": "Spezialmunition",
	"burn": "Feuershow",
	"lifesteal": "Blutspende-Aktion",
	"max_hp": "Stuntdouble",
	"corpse_explosion": "Konfetti-Kanone",
	"reload_shockwave": "Werbepause",
	"speed": "Turbo-Turnschuhe",
	"luck": "Publikumsliebling",
}

var _failures := 0


func _init() -> void:
	_test_table()
	_test_new_item_table()
	_test_fixed_numbers()
	_test_empty_state()
	_test_add_levels()
	_test_slot_limit()
	_test_eligibility()
	_test_synergy()
	_test_derived_values()
	_test_effect_texts()
	_test_summary()

	if _failures == 0:
		print("Alle Upgrade-Tests bestanden.")
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


## Jede Stufe jedes Upgrades stimmt mit der Tabelle überein, über UpgradeDefs und UpgradeState.
func _test_table() -> void:
	_check(UpgradeDefs.all_ids().size() == 9, "Es gibt genau 9 Upgrades (die Kameradrohne ist seit Abschnitt 22 eine Kamera), waren %d." % UpgradeDefs.all_ids().size())
	_check(not UpgradeDefs.has("drone"), "Die Kameradrohne steht nicht mehr in der Upgrade-Tabelle.")
	_check(UpgradeDefs.UPGRADES.size() == 9 + UpgradeDefs.ITEM_ONLY.size() and UpgradeDefs.ITEM_ONLY.size() == 24, "Die Tabelle hat die 9 Upgrades und 24 Gegenstände, die es nur im Rucksack gibt.")
	for item_only: String in UpgradeDefs.ITEM_ONLY:
		_check(UpgradeDefs.has(item_only) and not UpgradeDefs.all_ids().has(item_only), "%s steht in der Tabelle, aber nicht in ORDER." % item_only)
		_check(not UpgradeDefs.display_name(item_only).is_empty() and not UpgradeDefs.effect_text(item_only, 1).is_empty(), "%s hat Name und Text." % item_only)
		_check(not UpgradeDefs.effect_text(item_only, 5).contains("{"), "Der Text von %s hat keine offenen Platzhalter: %s" % [item_only, UpgradeDefs.effect_text(item_only, 5)])
	for id: String in EXPECTED:
		_check(UpgradeDefs.has(id), "Upgrade %s fehlt." % id)
		_check(UpgradeDefs.all_ids().has(id), "Upgrade %s fehlt in der Reihenfolge." % id)
		_check(UpgradeDefs.display_name(id) == String(EXPECTED_NAMES[id]), "Name von %s war '%s'." % [id, UpgradeDefs.display_name(id)])
		var keys: Array[String] = UpgradeDefs.value_keys(id)
		_check(keys.size() == (EXPECTED[id] as Dictionary).size(), "%s hat andere Schlüssel als erwartet: %s." % [id, keys])
		for key: String in EXPECTED[id]:
			_check(keys.has(key), "%s: Schlüssel %s fehlt." % [id, key])
			var state: UpgradeState = UpgradeState.new()
			for level: int in range(1, 6):
				var expected: float = float(EXPECTED[id][key][level - 1])
				var from_defs: float = UpgradeDefs.value(id, key, level)
				_check(is_equal_approx(from_defs, expected), "%s.%s Stufe %d: erwartet %s, war %s." % [id, key, level, expected, from_defs])
				state.add_levels(id, 1)
				_check(state.get_level(id) == level, "%s: Stufe nach %d Schritten war %d." % [id, level, state.get_level(id)])
				_check(is_equal_approx(state.value(id, key), expected), "UpgradeState %s.%s Stufe %d: erwartet %s, war %s." % [id, key, level, expected, state.value(id, key)])
	_check(UpgradeDefs.value("burn", "dps_percent", 0) == 0.0, "Stufe 0 liefert 0.")
	_check(UpgradeDefs.value("burn", "unbekannt", 3) == 0.0, "Unbekannter Schlüssel liefert 0.")
	_check(UpgradeDefs.value("unbekannt", "bonus", 3) == 0.0, "Unbekanntes Upgrade liefert 0.")
	_check(is_equal_approx(UpgradeDefs.value("burn", "dps_percent", 9), 0.12), "Stufen über 5 liefern den Wert der Stufe 5.")


## Abschnitt 22: acht neue Gegenstände und fünf Kamera-Gegenstände, jede Zahl gegen die Tabelle.
func _test_new_item_table() -> void:
	for id: String in EXPECTED_ITEMS:
		_check(UpgradeDefs.has(id) and UpgradeDefs.ITEM_ONLY.has(id), "%s steht in der Tabelle und in ITEM_ONLY." % id)
		_check(UpgradeDefs.display_name(id) == String(EXPECTED_ITEM_NAMES[id]), "Name von %s war '%s'." % [id, UpgradeDefs.display_name(id)])
		var keys: Array[String] = UpgradeDefs.value_keys(id)
		_check(keys.size() == (EXPECTED_ITEMS[id] as Dictionary).size(), "%s hat andere Schlüssel als erwartet: %s." % [id, keys])
		for key: String in EXPECTED_ITEMS[id]:
			for level: int in range(1, 6):
				var expected: float = float(EXPECTED_ITEMS[id][key][level - 1])
				_check(is_equal_approx(UpgradeDefs.value(id, key, level), expected), "%s.%s Rarität %d: erwartet %s, war %s." % [id, key, level, expected, UpgradeDefs.value(id, key, level)])
		for level: int in range(1, 6):
			var text: String = UpgradeDefs.effect_text(id, level)
			_check(text.length() > 10 and not text.contains("{") and not text.contains("}"), "%s Rarität %d hat einen Text ohne offene Platzhalter: %s" % [id, level, text])
	# Feste Zahlen aus Abschnitt 22.3.
	_check(is_equal_approx(Balance.FROST_DURATION, 2.0) and is_equal_approx(Balance.SLOW_ELITE_FACTOR, 0.5), "Trockeneis: 2 s, Elite halbe Wirkung.")
	_check(is_equal_approx(Balance.PUNCHLINE_RADIUS, 3.0), "Schlusspointe: Radius 3 m.")
	_check(is_equal_approx(Balance.RICOCHET_RADIUS, 6.0) and is_equal_approx(Balance.RICOCHET_DAMAGE_FACTOR, 0.6), "Querschläger: 6 m, 60 % Schaden.")
	_check(is_equal_approx(Balance.THORNS_RADIUS, 2.5), "Kaktus-Requisite: Umkreis 2,5 m.")
	_check(is_equal_approx(Balance.REVIVE_HP_SHARE, 0.3) and is_equal_approx(Balance.REVIVE_INVULNERABILITY, 1.5), "Zweite Staffel: 30 % Leben, 1,5 s unverwundbar.")
	_check(Balance.MINE_MAX_ACTIVE == 5 and is_equal_approx(Balance.MINE_TRIGGER_RADIUS, 1.2) and is_equal_approx(Balance.MINE_RADIUS, 3.0), "Requisitenbombe: 5 Minen, Auslöser 1,2 m, Radius 3 m.")
	# Texte nennen die Zahlen.
	var frost: String = UpgradeDefs.effect_text("frost", 3)
	_check(frost.contains("2 s") and frost.contains("30 %"), "Trockeneis Selten nennt 2 s und 30 %%: %s" % frost)
	_check(UpgradeDefs.effect_text("opener", 4).contains("+275 %"), "Eröffnungsgag Episch nennt +275 %.")
	var punchline: String = UpgradeDefs.effect_text("punchline", 2)
	_check(punchline.contains("3 m") and punchline.contains("90"), "Schlusspointe Ungewöhnlich nennt 3 m und 90: %s" % punchline)
	var ricochet: String = UpgradeDefs.effect_text("ricochet", 5)
	_check(ricochet.contains("60 %") and ricochet.contains("6 m"), "Querschläger Legendär nennt 60 %% und 6 m: %s" % ricochet)
	var revive: String = UpgradeDefs.effect_text("revive", 1)
	_check(revive.contains("30 %") and revive.contains("1,5 s") and revive.contains("5 geschafften"), "Zweite Staffel nennt 30 %%, 1,5 s und 5 Wellen: %s" % revive)
	var mine: String = UpgradeDefs.effect_text("mine", 5)
	_check(mine.contains("4 s") and mine.contains("höchstens 5") and mine.contains("220"), "Requisitenbombe Legendär nennt 4 s, 5 Minen und 220: %s" % mine)
	_check(UpgradeDefs.effect_text("cam_uplink", 5).contains("+25 %") and UpgradeDefs.effect_text("cam_second", 5).contains("100 %"), "Sendeleitung und Zweitkamera nennen ihre Prozente.")
	# Mehrere Exemplare.
	_check(is_equal_approx(UpgradeDefs.combined_value("frost", "slow", [1, 5, 2]), 0.40), "Trockeneis: Die stärkste Verlangsamung gilt.")
	_check(is_equal_approx(UpgradeDefs.combined_value("opener", "bonus", [1, 1]), 2.0), "Zwei Eröffnungsgags addieren sich.")
	_check(is_equal_approx(UpgradeDefs.combined_value("punchline", "damage", [1, 2]), 150.0), "Zwei Schlusspointen addieren den Schaden.")
	_check(is_equal_approx(UpgradeDefs.combined_value("ricochet", "chance", [5, 5]), 1.0), "Querschläger-Chance endet bei 100 %.")
	_check(is_equal_approx(UpgradeDefs.combined_value("thorns", "damage", [1, 5]), 180.0), "Kakteen addieren den Schaden.")
	_check(is_equal_approx(UpgradeDefs.combined_value("revive", "waves", [1, 5]), 3.0), "Zweite Staffel: Die kürzeste Wartezeit zählt.")
	_check(is_equal_approx(UpgradeDefs.combined_value("snack", "heal", [1, 5]), 45.0), "Pausensnacks addieren die Heilung.")
	_check(is_equal_approx(UpgradeDefs.combined_value("mine", "interval", [1, 5]), 4.0) and is_equal_approx(UpgradeDefs.combined_value("mine", "damage", [1, 5]), 290.0), "Requisitenbombe: kürzester Abstand, Schaden addiert sich.")
	_check(is_equal_approx(UpgradeDefs.combined_value("cam_lens", "bonus", [1, 2]), 0.5), "Kamera-Gegenstände addieren sich.")


## Feste Zahlen der Upgrades aus Abschnitt 8, die in Balance stehen.
func _test_fixed_numbers() -> void:
	_check(Balance.UPGRADE_MAX_SLOTS == 6 and UpgradeState.MAX_SLOTS == 6, "6 Plätze.")
	_check(Balance.UPGRADE_MAX_LEVEL == 5 and UpgradeState.MAX_LEVEL == 5, "Höchststufe 5.")
	_check(is_equal_approx(Balance.CHAIN_RADIUS, 6.0), "Blitz springt im Umkreis von 6 m.")
	_check(is_equal_approx(Balance.CHAIN_PELLET_CHANCE_FACTOR, 0.35), "Schrotkugel: Blitz-Chance mal 0,35.")
	_check(is_equal_approx(Balance.PIERCE_DAMAGE_FALLOFF, 0.15), "Durchschlag: 15 % weniger je weiterem Ziel.")
	_check(is_equal_approx(Balance.BURN_DURATION, 4.0), "Brand dauert 4 s.")
	_check(is_equal_approx(Balance.BURN_ELITE_FACTOR, 0.3), "Brand an Elite mal 0,3.")
	_check(is_equal_approx(Balance.LIFESTEAL_MAX_PER_SECOND, 15.0), "Lebensraub höchstens 15 je Sekunde.")
	_check(is_equal_approx(Balance.SHOCKWAVE_COOLDOWN, 3.0), "Druckwelle: Abklingzeit 3 s.")
	_check(is_equal_approx(Balance.DRONE_RANGE, 15.0), "Drohne: Reichweite 15 m.")
	_check(Balance.STORM_FRONT_MAX_PROCS_PER_SHOT == 6, "Gewitterfront: höchstens 6 Blitze je Schuss.")
	_check(Balance.EXPLOSION_MAX_CHAIN >= 1, "Explosionsketten sind begrenzt.")


func _test_empty_state() -> void:
	var state: UpgradeState = UpgradeState.new()
	_check(state.owned_ids().is_empty(), "Am Anfang ist kein Upgrade im Besitz.")
	_check(state.free_slots() == 6, "Am Anfang sind 6 Plätze frei.")
	_check(state.get_level("burn") == 0, "Stufe 0 ohne Besitz.")
	_check(state.value("burn", "dps_percent") == 0.0, "Wert 0.0 ohne Besitz.")
	_check(state.points_multiplier() == 1.0, "Punkte-Faktor 1,0 ohne Glück.")
	_check(state.speed_multiplier() == 1.0, "Tempo-Faktor 1,0 ohne Turnschuhe.")
	_check(state.bonus_max_hp() == 0.0, "Kein Bonus-Leben ohne Stuntdouble.")
	_check(state.luck_level() == 0, "Glück-Stufe 0.")
	_check(state.chest_chance_bonus() == 0.0, "Keine Extra-Kistenchance ohne Glück.")
	_check(state.eligible_ids().size() == 9, "Am Anfang sind alle 9 Upgrades wählbar.")
	_check(state.eligible_ids() == UpgradeDefs.all_ids(), "Wählbare kommen in der festen Reihenfolge.")
	_check(not state.has_synergy("storm_front"), "Keine Synergie am Anfang.")
	_check(state.check_new_synergies().is_empty(), "Keine neue Synergie am Anfang.")
	_check(state.summary().is_empty(), "Leere Übersicht am Anfang.")


func _test_add_levels() -> void:
	var state: UpgradeState = UpgradeState.new()
	_check(state.add_levels("burn", 2) == 2, "add_levels gibt die neue Stufe zurück.")
	_check(state.add_levels("burn", 2) == 4, "Stufen addieren sich.")
	_check(state.add_levels("burn", 3) == 5, "Höchstens Stufe 5.")
	_check(state.add_levels("burn", 1) == 5 and state.get_level("burn") == 5, "Stufe 5 bleibt Stufe 5.")
	_check(state.add_levels("unbekannt", 1) == 0 and state.owned_ids().size() == 1, "Unbekannte Upgrades werden nicht aufgenommen.")
	_check(state.add_levels("pierce", 0) == 0 and state.get_level("pierce") == 0, "0 Stufen ändern nichts.")
	_check(state.add_levels("pierce", -2) == 0 and state.get_level("pierce") == 0, "Negative Stufen ändern nichts.")
	_check(state.free_slots() == 5, "Ein Upgrade belegt einen Platz, frei waren %d." % state.free_slots())
	state.add_levels("speed", 1)
	state.add_levels("luck", 1)
	state.add_levels("burn", 1)
	_check(state.add_levels("drone", 1) == 0 and state.get_level("drone") == 0, "Die Kameradrohne ist kein Upgrade mehr: add_levels nimmt sie nicht an.")
	var order: Array[String] = ["burn", "speed", "luck"]
	_check(state.owned_ids() == order, "Besitz in der Reihenfolge des Erwerbs, war %s." % [state.owned_ids()])


func _test_slot_limit() -> void:
	var state: UpgradeState = UpgradeState.new()
	var first_six: Array[String] = ["chain_lightning", "pierce", "burn", "lifesteal", "max_hp", "corpse_explosion"]
	for i: int in first_six.size():
		_check(state.is_eligible(first_six[i]), "%s ist wählbar, solange Platz ist." % first_six[i])
		state.add_levels(first_six[i], 1)
		_check(state.free_slots() == 5 - i, "Nach %d Upgrades sind %d Plätze frei." % [i + 1, 5 - i])
	_check(state.free_slots() == 0, "Nach 6 Upgrades ist kein Platz frei.")
	for id: String in ["reload_shockwave", "speed", "luck"]:
		_check(not state.is_eligible(id), "%s ist ohne freien Platz nicht wählbar." % id)
		_check(state.add_levels(id, 2) == 0, "%s wird ohne freien Platz nicht aufgenommen." % id)
		_check(state.get_level(id) == 0, "%s bleibt auf Stufe 0." % id)
	_check(state.owned_ids().size() == 6, "Es bleiben 6 Upgrades im Besitz.")
	_check(state.eligible_ids() == first_six, "Wählbar sind genau die 6 im Besitz, waren %s." % [state.eligible_ids()])
	_check(state.add_levels("burn", 2) == 3, "Upgrades im Besitz steigen auch bei vollen Plätzen.")
	_check(state.free_slots() == 0, "Freie Plätze werden nie negativ.")


func _test_eligibility() -> void:
	var state: UpgradeState = UpgradeState.new()
	_check(not state.is_eligible("unbekannt"), "Unbekannte Upgrades sind nie wählbar.")
	state.add_levels("speed", 4)
	_check(state.is_eligible("speed"), "Stufe 4 ist noch wählbar.")
	state.add_levels("speed", 1)
	_check(not state.is_eligible("speed"), "Stufe 5 ist nicht mehr wählbar.")
	_check(not state.eligible_ids().has("speed"), "Stufe 5 fehlt in der Liste der wählbaren.")
	_check(state.eligible_ids().size() == 8, "Die anderen 8 bleiben wählbar.")
	# Alle 6 Plätze auf Stufe 5: nichts mehr wählbar.
	for id: String in ["burn", "lifesteal", "luck", "pierce", "max_hp"]:
		state.add_levels(id, 5)
	_check(state.free_slots() == 0 and state.eligible_ids().is_empty(), "Mit 6 Upgrades auf Stufe 5 ist nichts mehr wählbar.")


func _test_synergy() -> void:
	_check(UpgradeDefs.synergy_ids() == (["storm_front"] as Array[String]), "Es gibt genau die Synergie storm_front.")
	_check(UpgradeDefs.synergy_name("storm_front") == "Gewitterfront", "Die Synergie heißt Gewitterfront.")
	var requires: Dictionary = UpgradeDefs.synergy_requirements("storm_front")
	_check(requires.size() == 2 and int(requires.get("chain_lightning", 0)) == 5 and int(requires.get("pierce", 0)) == 5, "Gewitterfront braucht chain_lightning 5 und pierce 5.")
	var state: UpgradeState = UpgradeState.new()
	state.add_levels("chain_lightning", 5)
	_check(not state.has_synergy("storm_front"), "Nur Blitz 5 reicht nicht.")
	_check(state.check_new_synergies().is_empty(), "Noch keine neue Synergie.")
	state.add_levels("pierce", 4)
	_check(not state.has_synergy("storm_front"), "Durchschlag 4 reicht nicht.")
	_check(state.check_new_synergies().is_empty(), "Mit Durchschlag 4 noch keine neue Synergie.")
	state.add_levels("pierce", 1)
	_check(state.has_synergy("storm_front"), "Blitz 5 und Durchschlag 5 ergeben die Gewitterfront.")
	var fresh: Array[String] = state.check_new_synergies()
	_check(fresh.size() == 1 and fresh[0] == "storm_front", "Die Synergie wird gemeldet, war %s." % [fresh])
	_check(state.check_new_synergies().is_empty(), "Die Synergie wird nur einmal gemeldet.")
	state.add_levels("burn", 1)
	_check(state.check_new_synergies().is_empty(), "Auch nach weiteren Upgrades keine zweite Meldung.")
	_check(state.has_synergy("storm_front"), "Die Synergie bleibt bestehen.")
	_check(state.active_synergies() == (["storm_front"] as Array[String]), "active_synergies nennt die Gewitterfront.")
	_check(state.free_slots() == 3, "Die Synergie belegt keinen Platz, frei waren %d." % state.free_slots())
	_check(not state.has_synergy("unbekannt"), "Unbekannte Synergien gibt es nicht.")
	_check(not state.owned_ids().has("storm_front"), "Die Synergie steht nicht unter den Upgrades.")


func _test_derived_values() -> void:
	var state: UpgradeState = UpgradeState.new()
	for level: int in range(1, 6):
		state.add_levels("luck", 1)
		state.add_levels("speed", 1)
		state.add_levels("max_hp", 1)
		_check(is_equal_approx(state.points_multiplier(), 1.0 + 0.1 * level), "Punkte-Faktor Stufe %d war %s." % [level, state.points_multiplier()])
		_check(is_equal_approx(state.speed_multiplier(), 1.0 + 0.08 * level), "Tempo-Faktor Stufe %d war %s." % [level, state.speed_multiplier()])
		_check(is_equal_approx(state.bonus_max_hp(), 20.0 * level), "Bonus-Leben Stufe %d war %s." % [level, state.bonus_max_hp()])
		_check(state.luck_level() == level, "Glück-Stufe %d war %d." % [level, state.luck_level()])
		_check(is_equal_approx(state.chest_chance_bonus(), 0.01 * level), "Kistenchance-Bonus Stufe %d war %s." % [level, state.chest_chance_bonus()])


func _test_effect_texts() -> void:
	for id: String in UpgradeDefs.all_ids():
		for level: int in range(1, 6):
			var text: String = UpgradeDefs.effect_text(id, level)
			_check(text.length() > 10, "%s Stufe %d hat einen Wirkungstext." % [id, level])
			_check(not text.contains("{") and not text.contains("}"), "%s Stufe %d: Platzhalter nicht ersetzt: %s" % [id, level, text])
			_check(text.length() <= 200, "%s Stufe %d: Text passt auf eine Karte (%d Zeichen)." % [id, level, text.length()])
	var explosion: String = UpgradeDefs.effect_text("corpse_explosion", 2)
	_check(explosion.contains("20 %") and explosion.contains("3,25 m") and explosion.contains("40 %"), "Konfetti Stufe 2 nennt 20 %%, 3,25 m und 40 %%: %s" % explosion)
	var chain: String = UpgradeDefs.effect_text("chain_lightning", 5)
	_check(chain.contains("30 %") and chain.contains("6 weitere") and chain.contains("100 %") and chain.contains("6 m"), "Blitz Stufe 5 nennt 30 %%, 6 Sprünge, 100 %% und 6 m: %s" % chain)
	var pierce: String = UpgradeDefs.effect_text("pierce", 3)
	_check(pierce.contains(": 3.") and pierce.contains("15 %"), "Durchschlag Stufe 3 nennt 3 Ziele und 15 %%: %s" % pierce)
	var burn: String = UpgradeDefs.effect_text("burn", 5)
	_check(burn.contains("4 s") and burn.contains("12 %"), "Brand Stufe 5 nennt 4 s und 12 %%: %s" % burn)
	var lifesteal: String = UpgradeDefs.effect_text("lifesteal", 1)
	_check(lifesteal.begins_with("2 %") and lifesteal.contains("15 Leben"), "Lebensraub Stufe 1 nennt 2 %% und 15 Leben: %s" % lifesteal)
	var shockwave: String = UpgradeDefs.effect_text("reload_shockwave", 2)
	_check(shockwave.contains("4,5 m") and shockwave.contains("35") and shockwave.contains("3 s"), "Druckwelle Stufe 2 nennt 4,5 m, 35 und 3 s: %s" % shockwave)
	_check(UpgradeDefs.effect_text("max_hp", 3).contains("+60"), "Stuntdouble Stufe 3 nennt +60.")
	_check(UpgradeDefs.effect_text("speed", 2).contains("+16 %"), "Turnschuhe Stufe 2 nennen +16 %.")
	var luck: String = UpgradeDefs.effect_text("luck", 4)
	_check(luck.contains("+40 %") and luck.contains("+4 %-Punkte"), "Glück Stufe 4 nennt +40 %% und +4 %%-Punkte: %s" % luck)
	_check(UpgradeDefs.effect_text("burn", 0) == UpgradeDefs.effect_text("burn", 1), "Stufe 0 zeigt den Text der Stufe 1.")
	_check(UpgradeDefs.effect_text("unbekannt", 1) == "", "Unbekannte Upgrades haben keinen Text.")
	var synergy: String = UpgradeDefs.synergy_text("storm_front")
	_check(synergy.contains("6 Blitze") and not synergy.contains("{"), "Synergie-Text nennt 6 Blitze: %s" % synergy)
	_check(UpgradeDefs.format_number(3.25) == "3,25" and UpgradeDefs.format_number(4.0) == "4" and UpgradeDefs.format_number(0.5) == "0,5" and UpgradeDefs.format_number(100.0) == "100", "Zahlen in deutscher Schreibweise.")
	_check(UpgradeDefs.format_percent(0.15) == "15" and UpgradeDefs.format_percent(0.07) == "7" and UpgradeDefs.format_percent(1.0) == "100", "Prozent als ganze Zahl.")


func _test_summary() -> void:
	var state: UpgradeState = UpgradeState.new()
	state.add_levels("speed", 2)
	state.add_levels("burn", 1)
	var rows: Array[Dictionary] = state.summary()
	_check(rows.size() == 2, "Übersicht hat zwei Zeilen.")
	_check(rows[0]["id"] == "speed" and rows[0]["name"] == "Turbo-Turnschuhe" and rows[0]["level"] == 2, "Erste Zeile: Turbo-Turnschuhe Stufe 2, war %s." % [rows[0]])
	_check(rows[1]["id"] == "burn" and rows[1]["name"] == "Feuershow" and rows[1]["level"] == 1, "Zweite Zeile: Feuershow Stufe 1, war %s." % [rows[1]])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
