extends SceneTree
## Tests für ChestRoller: Fallchance, Seltenheits-Verteilung mit und ohne Glück, Angebote,
## Stufengewinn je Seltenheit, Trostpreise und Kartentexte.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")

const ROLLS: int = 40000
## Erlaubte Abweichung der gewürfelten Anteile in Prozentpunkten.
const TOLERANCE: float = 1.0

var _failures := 0


func _init() -> void:
	_test_weights()
	_test_rarity_distribution()
	_test_drop_chance()
	_test_levels_and_names()
	_test_offers_fresh()
	_test_offers_seeded()
	_test_offers_level_cap()
	_test_offers_full_slots()
	_test_consolation()
	_test_offer_texts()

	if _failures == 0:
		print("Alle Kisten-Tests bestanden.")
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


func _test_weights() -> void:
	_check_weights(false, 0, [70.0, 25.0, 5.0])
	_check_weights(true, 0, [50.0, 40.0, 10.0])
	_check_weights(false, 1, [64.0, 29.0, 7.0])
	_check_weights(false, 3, [52.0, 37.0, 11.0])
	_check_weights(false, 5, [40.0, 45.0, 15.0])
	_check_weights(true, 2, [38.0, 48.0, 14.0])
	_check_weights(true, 5, [20.0, 60.0, 20.0])
	# Glück außerhalb von 0 bis 5 wird begrenzt.
	_check_weights(false, 9, [40.0, 45.0, 15.0])
	_check_weights(false, -3, [70.0, 25.0, 5.0])


func _check_weights(is_elite: bool, luck: int, expected: Array) -> void:
	var weights: Array[float] = ChestRoller.rarity_weights(is_elite, luck)
	var label: String = "%s-Kiste mit Glück %d" % ["Elite" if is_elite else "Normale", luck]
	_check(weights.size() == 3, "%s: drei Gewichte." % label)
	var sum: float = 0.0
	for i: int in 3:
		sum += weights[i]
		_check(is_equal_approx(weights[i], float(expected[i])), "%s: %s erwartet %s, war %s." % [label, Balance.RARITY_NAMES[i], expected[i], weights[i]])
		_check(weights[i] >= 0.0, "%s: kein negatives Gewicht." % label)
	_check(is_equal_approx(sum, 100.0), "%s: Summe 100, war %s." % [label, sum])


func _test_rarity_distribution() -> void:
	_check_distribution(false, 0, 11)
	_check_distribution(true, 0, 12)
	_check_distribution(false, 3, 13)
	_check_distribution(false, 5, 14)
	_check_distribution(true, 5, 15)
	# Glück verschiebt wirklich: weniger Bronze, mehr Gold.
	var plain: Array[int] = _roll_counts(false, 0, 21)
	var lucky: Array[int] = _roll_counts(false, 5, 21)
	_check(lucky[0] < plain[0] and lucky[1] > plain[1] and lucky[2] > plain[2], "Glück 5: weniger Bronze, mehr Silber und Gold (%s gegen %s)." % [lucky, plain])
	# Gleicher Seed, gleiches Ergebnis.
	_check(_roll_counts(true, 2, 99) == _roll_counts(true, 2, 99), "Gleicher Seed ergibt dieselben Seltenheiten.")


func _roll_counts(is_elite: bool, luck: int, seed_value: int) -> Array[int]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var counts: Array[int] = [0, 0, 0]
	for i: int in ROLLS:
		var rarity: int = ChestRoller.roll_rarity(rng, is_elite, luck)
		if rarity < 0 or rarity > 2:
			_check(false, "Seltenheit außerhalb 0 bis 2: %d." % rarity)
			return counts
		counts[rarity] += 1
	return counts


func _check_distribution(is_elite: bool, luck: int, seed_value: int) -> void:
	var counts: Array[int] = _roll_counts(is_elite, luck, seed_value)
	var expected: Array[float] = ChestRoller.rarity_weights(is_elite, luck)
	for i: int in 3:
		var share: float = 100.0 * float(counts[i]) / float(ROLLS)
		_check(absf(share - expected[i]) <= TOLERANCE, "%s-Kiste, Glück %d: %s erwartet %.1f %%, gewürfelt %.2f %%." % ["Elite" if is_elite else "Normale", luck, Balance.RARITY_NAMES[i], expected[i], share])


func _test_drop_chance() -> void:
	var state: UpgradeState = UpgradeState.new()
	_check(ChestRoller.drop_chance(true, state) == 1.0, "Elite lässt immer eine Kiste fallen.")
	_check(is_equal_approx(ChestRoller.drop_chance(false, state), 0.03), "Normale Zombies: 3 %.")
	_check(is_equal_approx(ChestRoller.drop_chance(false, null), 0.03), "Ohne Upgrade-Zustand gelten 3 %.")
	state.add_levels("luck", 3)
	_check(is_equal_approx(ChestRoller.drop_chance(false, state), 0.06), "Glück 3: 6 %%, war %s." % ChestRoller.drop_chance(false, state))
	state.add_levels("luck", 2)
	_check(is_equal_approx(ChestRoller.drop_chance(false, state), 0.08), "Glück 5: 8 %%, war %s." % ChestRoller.drop_chance(false, state))
	_check(ChestRoller.drop_chance(true, state) == 1.0, "Elite bleibt bei 100 %.")

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var before: int = rng.state
	for i: int in 50:
		_check(ChestRoller.should_drop(rng, true, null), "Elite: should_drop ist immer wahr.")
	_check(rng.state == before, "Elite verbraucht keinen Zufallswert.")
	var plain: UpgradeState = UpgradeState.new()
	var drops: int = 0
	for i: int in ROLLS:
		if ChestRoller.should_drop(rng, false, plain):
			drops += 1
	var share: float = 100.0 * float(drops) / float(ROLLS)
	_check(absf(share - 3.0) <= 0.5, "Normale Zombies lassen in etwa 3 %% fallen, gewürfelt %.2f %%." % share)
	drops = 0
	for i: int in ROLLS:
		if ChestRoller.should_drop(rng, false, state):
			drops += 1
	share = 100.0 * float(drops) / float(ROLLS)
	_check(absf(share - 8.0) <= 0.7, "Mit Glück 5 in etwa 8 %%, gewürfelt %.2f %%." % share)


func _test_levels_and_names() -> void:
	_check(ChestRoller.levels_for_rarity(0) == 1, "Bronze gibt 1 Stufe.")
	_check(ChestRoller.levels_for_rarity(1) == 2, "Silber gibt 2 Stufen.")
	_check(ChestRoller.levels_for_rarity(2) == 3, "Gold gibt 3 Stufen.")
	_check(ChestRoller.rarity_name(0) == "Bronze" and ChestRoller.rarity_name(1) == "Silber" and ChestRoller.rarity_name(2) == "Gold", "Namen der Seltenheiten.")
	_check(ChestRoller.rarity_color(0) != ChestRoller.rarity_color(1) and ChestRoller.rarity_color(1) != ChestRoller.rarity_color(2), "Jede Seltenheit hat eine eigene Farbe.")
	_check(Balance.CONSOLATION_POINTS == 500 and Balance.CONSOLATION_HEAL == 50, "Trostpreise: 500 Punkte oder 50 Leben.")
	_check(Balance.GUARANTEED_CHEST_WAVE == 1, "Welle 1 hat die sichere Kiste.")


## Ohne Upgrades: drei verschiedene neue Upgrades, Stufengewinn nach Seltenheit.
func _test_offers_fresh() -> void:
	var seen: Dictionary = {}
	for rarity: int in 3:
		for seed_value: int in 60:
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = seed_value
			var state: UpgradeState = UpgradeState.new()
			var offers: Array[Dictionary] = ChestRoller.build_offers(rng, state, rarity)
			_check(offers.size() == 3, "Ein Angebot hat immer 3 Einträge, waren %d." % offers.size())
			var ids: Dictionary = {}
			for offer: Dictionary in offers:
				_check(offer.get("kind", "") == "upgrade", "Mit freien Plätzen gibt es nur Upgrades, war %s." % [offer])
				_check(offer.size() == 4 and offer.has("id") and offer.has("from_level") and offer.has("to_level"), "Angebot hat genau kind, id, from_level, to_level: %s." % [offer])
				var id: String = String(offer.get("id", ""))
				_check(UpgradeDefs.has(id), "Angebotenes Upgrade %s ist bekannt." % id)
				_check(int(offer.get("from_level", -1)) == 0, "Neues Upgrade kommt von Stufe 0.")
				_check(int(offer.get("to_level", -1)) == rarity + 1, "Seltenheit %d bringt auf Stufe %d, war %s." % [rarity, rarity + 1, offer.get("to_level")])
				ids[id] = true
				seen[id] = true
			_check(ids.size() == 3, "Die 3 Angebote sind verschieden: %s." % [offers])
			_check(state.owned_ids().is_empty(), "build_offers ändert den Zustand nicht.")
	_check(seen.size() == 10, "Über viele Seeds kommt jedes der 10 Upgrades vor, gesehen %d." % seen.size())


func _test_offers_seeded() -> void:
	var state: UpgradeState = UpgradeState.new()
	var first: Array[Dictionary] = _offers_for_seed(state, 1234)
	var again: Array[Dictionary] = _offers_for_seed(state, 1234)
	_check(first == again, "Gleicher Seed ergibt dasselbe Angebot.")
	var different: int = 0
	for seed_value: int in 30:
		if _offers_for_seed(state, seed_value) != first:
			different += 1
	_check(different >= 20, "Andere Seeds ergeben meist andere Angebote (%d von 30)." % different)


func _offers_for_seed(state: UpgradeState, seed_value: int) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return ChestRoller.build_offers(rng, state, 0)


## Der Stufengewinn endet bei Stufe 5.
func _test_offers_level_cap() -> void:
	var state: UpgradeState = UpgradeState.new()
	for id: String in ["burn", "drone", "luck", "pierce", "max_hp", "speed"]:
		state.add_levels(id, 4)
	for rarity: int in 3:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 77 + rarity
		for offer: Dictionary in ChestRoller.build_offers(rng, state, rarity):
			_check(int(offer["from_level"]) == 4 and int(offer["to_level"]) == 5, "Von Stufe 4 geht es höchstens auf 5: %s." % [offer])
	var low: UpgradeState = UpgradeState.new()
	for id: String in ["burn", "drone", "luck", "pierce", "max_hp", "speed"]:
		low.add_levels(id, 3)
	var rng_low: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_low.seed = 3
	for offer: Dictionary in ChestRoller.build_offers(rng_low, low, 1):
		_check(int(offer["from_level"]) == 3 and int(offer["to_level"]) == 5, "Silber: von 3 auf 5: %s." % [offer])
	rng_low.seed = 4
	for offer: Dictionary in ChestRoller.build_offers(rng_low, low, 0):
		_check(int(offer["to_level"]) == 4, "Bronze: von 3 auf 4: %s." % [offer])


## Sind alle 6 Plätze belegt, kommen nur Upgrades im Besitz, und Stufe 5 wird nie angeboten.
func _test_offers_full_slots() -> void:
	var owned: Array[String] = ["burn", "drone", "luck", "pierce", "max_hp", "speed"]
	var state: UpgradeState = UpgradeState.new()
	for id: String in owned:
		state.add_levels(id, 1)
	state.add_levels("burn", 4)
	for seed_value: int in 80:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		var offers: Array[Dictionary] = ChestRoller.build_offers(rng, state, 2)
		var ids: Dictionary = {}
		for offer: Dictionary in offers:
			_check(offer["kind"] == "upgrade", "Mit 5 wählbaren gibt es keine Trostpreise.")
			var id: String = String(offer["id"])
			_check(owned.has(id), "Bei vollen Plätzen nur Upgrades im Besitz, war %s." % id)
			_check(id != "burn", "Ein Upgrade auf Stufe 5 wird nicht angeboten.")
			_check(int(offer["from_level"]) == 1 and int(offer["to_level"]) == 4, "Gold: von 1 auf 4: %s." % [offer])
			ids[id] = true
		_check(ids.size() == 3, "Auch bei vollen Plätzen 3 verschiedene: %s." % [offers])


func _test_consolation() -> void:
	var owned: Array[String] = ["burn", "drone", "luck", "pierce", "max_hp", "speed"]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8

	# Zwei wählbare: zwei Upgrades, dann Punkte.
	var two: UpgradeState = _state_with_maxed(owned, 4)
	var offers: Array[Dictionary] = ChestRoller.build_offers(rng, two, 0)
	_check(offers.size() == 3, "Zwei wählbare: trotzdem 3 Einträge.")
	_check(offers[0]["kind"] == "upgrade" and offers[1]["kind"] == "upgrade", "Zwei wählbare: erst die beiden Upgrades.")
	_check(offers[0]["id"] != offers[1]["id"], "Die beiden Upgrades sind verschieden.")
	_check(offers[2] == {"kind": "points", "amount": 500}, "Dritter Eintrag: 500 Punkte, war %s." % [offers[2]])

	# Eine wählbare: Upgrade, Punkte, Heilung.
	var one: UpgradeState = _state_with_maxed(owned, 5)
	offers = ChestRoller.build_offers(rng, one, 1)
	_check(offers.size() == 3 and offers[0]["kind"] == "upgrade" and offers[0]["id"] == "speed", "Eine wählbare: zuerst dieses Upgrade, war %s." % [offers])
	_check(int(offers[0]["from_level"]) == 1 and int(offers[0]["to_level"]) == 3, "Silber: von 1 auf 3.")
	_check(offers[1] == {"kind": "points", "amount": 500}, "Zweiter Eintrag: 500 Punkte, war %s." % [offers[1]])
	_check(offers[2] == {"kind": "heal", "amount": 50}, "Dritter Eintrag: 50 Leben, war %s." % [offers[2]])

	# Keine wählbare: Punkte, Heilung, Punkte.
	var none: UpgradeState = _state_with_maxed(owned, 6)
	_check(none.eligible_ids().is_empty(), "Alles auf Stufe 5: nichts wählbar.")
	offers = ChestRoller.build_offers(rng, none, 2)
	_check(offers.size() == 3, "Keine wählbare: 3 Trostpreise.")
	_check(offers[0] == {"kind": "points", "amount": 500}, "Erster Trostpreis: 500 Punkte.")
	_check(offers[1] == {"kind": "heal", "amount": 50}, "Zweiter Trostpreis: 50 Leben.")
	_check(offers[2] == {"kind": "points", "amount": 500}, "Dritter Trostpreis: 500 Punkte.")
	_check(ChestRoller.consolation_offer(0)["kind"] == "points" and ChestRoller.consolation_offer(1)["kind"] == "heal", "Trostpreise wechseln sich ab.")


## Zustand mit den 6 Upgrades, von denen die ersten maxed_count auf Stufe 5 stehen, der Rest auf 1.
func _state_with_maxed(owned: Array[String], maxed_count: int) -> UpgradeState:
	var state: UpgradeState = UpgradeState.new()
	for i: int in owned.size():
		state.add_levels(owned[i], 5 if i < maxed_count else 1)
	return state


func _test_offer_texts() -> void:
	var fresh: Dictionary = {"kind": "upgrade", "id": "burn", "from_level": 0, "to_level": 2}
	_check(ChestRoller.offer_title(fresh) == "Feuershow", "Titel ist der Upgrade-Name.")
	_check(ChestRoller.offer_level_text(fresh) == "Neu: Stufe 2", "Neues Upgrade: 'Neu: Stufe 2', war '%s'." % ChestRoller.offer_level_text(fresh))
	_check(ChestRoller.offer_description(fresh) == UpgradeDefs.effect_text("burn", 2), "Beschreibung nennt die Zahlen der neuen Stufe.")
	var raise: Dictionary = {"kind": "upgrade", "id": "drone", "from_level": 2, "to_level": 4}
	_check(ChestRoller.offer_level_text(raise) == "Stufe 2 → 4", "Aufwertung: 'Stufe 2 → 4', war '%s'." % ChestRoller.offer_level_text(raise))
	_check(ChestRoller.offer_description(raise).contains("0,65 s"), "Drohne auf Stufe 4 nennt 0,65 s.")
	var points: Dictionary = ChestRoller.consolation_offer(0)
	_check(ChestRoller.offer_title(points).contains("Punkte") and ChestRoller.offer_description(points).contains("500"), "Punkte-Trostpreis nennt 500 Punkte.")
	_check(ChestRoller.offer_level_text(points) == "", "Trostpreise haben keine Stufenzeile.")
	var heal: Dictionary = ChestRoller.consolation_offer(1)
	_check(ChestRoller.offer_title(heal) != "" and ChestRoller.offer_description(heal).contains("50"), "Heil-Trostpreis nennt 50 Leben.")
	_check(ChestRoller.offer_title({}) == "" and ChestRoller.offer_description({}) == "", "Leeres Angebot ergibt leere Texte.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
