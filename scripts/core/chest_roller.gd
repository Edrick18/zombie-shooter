extends RefCounted
## Kisten-Regeln (Abschnitt 8 "Kisten"): Fallchance, Seltenheit, Angebote, Trostpreise.
## Reine Logik, Zufall nur über den übergebenen RandomNumberGenerator.
## Besitzer: Fundament. Einbinden mit: const ChestRoller := preload("res://scripts/core/chest_roller.gd")

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")

const KIND_UPGRADE: String = "upgrade"
const KIND_POINTS: String = "points"
const KIND_HEAL: String = "heal"
## Gegenstand für den Rucksack: { "kind": "item", "id": String, "level": int, "owned_level": int }
const KIND_ITEM: String = "item"


## Chance (0 bis 1), dass ein getöteter Zombie eine Kiste fallen lässt.
## Elite: immer 1,0. Normale: 3 % plus Glück (1 Prozentpunkt je Stufe).
static func drop_chance(is_elite: bool, upgrades: UpgradeState) -> float:
	if is_elite:
		return 1.0
	var bonus: float = upgrades.chest_chance_bonus() if upgrades != null else 0.0
	return clampf(Balance.CHEST_DROP_CHANCE_NORMAL + bonus, 0.0, 1.0)


## Würfelt, ob eine Kiste fällt. Bei Elite wird kein Zufallswert verbraucht.
static func should_drop(rng: RandomNumberGenerator, is_elite: bool, upgrades: UpgradeState) -> bool:
	if is_elite:
		return true
	return rng.randf() < drop_chance(false, upgrades)


## Seltenheits-Verteilung in Prozent als [Bronze, Silber, Gold], Summe 100.
## Normale Kiste 70/25/5, Elite-Kiste 50/40/10. Je Glück-Stufe wandern 4 Punkte von Bronze zu
## Silber und 2 zu Gold. Bronze wird nie negativ.
static func rarity_weights(is_elite: bool, luck_level: int) -> Array[float]:
	var base: Array[float] = Balance.CHEST_RARITY_ELITE if is_elite else Balance.CHEST_RARITY_NORMAL
	var luck: float = float(clampi(luck_level, 0, Balance.UPGRADE_MAX_LEVEL))
	var to_silver: float = Balance.LUCK_SHIFT_TO_SILVER * luck
	var to_gold: float = Balance.LUCK_SHIFT_TO_GOLD * luck
	var shift: float = to_silver + to_gold
	if shift > base[0] and shift > 0.0:
		var scale: float = base[0] / shift
		to_silver *= scale
		to_gold *= scale
	var weights: Array[float] = [base[0] - to_silver - to_gold, base[1] + to_silver, base[2] + to_gold]
	return weights


## Würfelt die Seltenheit einer Kiste: 0 = Bronze, 1 = Silber, 2 = Gold.
static func roll_rarity(rng: RandomNumberGenerator, is_elite: bool, luck_level: int) -> int:
	var weights: Array[float] = rarity_weights(is_elite, luck_level)
	var roll: float = rng.randf() * 100.0
	if roll < weights[Balance.RARITY_GOLD]:
		return Balance.RARITY_GOLD
	if roll < weights[Balance.RARITY_GOLD] + weights[Balance.RARITY_SILVER]:
		return Balance.RARITY_SILVER
	return Balance.RARITY_BRONZE


## Stufen, die das gewählte Upgrade bekommt: Bronze 1, Silber 2, Gold 3.
static func levels_for_rarity(rarity: int) -> int:
	var index: int = clampi(rarity, 0, Balance.CHEST_LEVELS_BY_RARITY.size() - 1)
	return Balance.CHEST_LEVELS_BY_RARITY[index]


## Name der Seltenheit: "Bronze", "Silber", "Gold".
static func rarity_name(rarity: int) -> String:
	return Balance.RARITY_NAMES[clampi(rarity, 0, Balance.RARITY_NAMES.size() - 1)]


## Farbe der Seltenheit für Kiste und Karten.
static func rarity_color(rarity: int) -> Color:
	return Balance.RARITY_COLORS[clampi(rarity, 0, Balance.RARITY_COLORS.size() - 1)]


## Baut das Angebot einer Kiste: immer genau 3 Einträge.
## Zuerst bis zu 3 verschiedene, zufällig gezogene wählbare Upgrades als
## { "kind": "upgrade", "id": String, "from_level": int, "to_level": int }
## (to_level = from_level + Stufen der Seltenheit, höchstens 5).
## Gibt es weniger als 3 wählbare, folgen Trostpreise im Wechsel:
## { "kind": "points", "amount": 500 }, { "kind": "heal", "amount": 50 }, wieder Punkte.
static func build_offers(rng: RandomNumberGenerator, upgrades: UpgradeState, rarity: int) -> Array[Dictionary]:
	var pool: Array[String] = upgrades.eligible_ids()
	# Fisher-Yates mit dem übergebenen Zufall, damit das Ergebnis vom Seed abhängt.
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: String = pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	var gain: int = levels_for_rarity(rarity)
	var offers: Array[Dictionary] = []
	for id: String in pool:
		if offers.size() >= Balance.CHEST_OFFER_COUNT:
			break
		var from_level: int = upgrades.get_level(id)
		offers.append({
			"kind": KIND_UPGRADE,
			"id": id,
			"from_level": from_level,
			"to_level": mini(from_level + gain, Balance.UPGRADE_MAX_LEVEL),
		})
	var consolation_index: int = 0
	while offers.size() < Balance.CHEST_OFFER_COUNT:
		offers.append(consolation_offer(consolation_index))
		consolation_index += 1
	return offers


## Baut das Angebot einer Kiste für den Rucksack: immer genau 3 Einträge.
## Je Eintrag { "kind": "item", "id": String, "level": int, "owned_level": int }. level ist die
## Rarität des Gegenstands (1 = Gewöhnlich bis 5 = Legendär): Bronze-Kisten geben Gewöhnlich,
## Silber Ungewöhnlich, Gold Selten. Rucksack-Teile haben keine Rarität (level 1). owned_level
## ist die höchste Rarität, in der der Spieler den Gegenstand schon hat (0 = noch nicht).
##
## Regeln:
## - Gegenstände mit höherer Mindest-Seltenheit fehlen in schlechteren Kisten.
## - Was der Spieler schon in Legendär hat, wird nicht mehr angeboten (es ließe sich nicht mehr
##   kombinieren).
## - Der erste Eintrag ist ein Upgrade-Gegenstand, solange es noch einen gibt.
## - Rucksack-Teil: Mit force_bag enthält die Kiste sicher eines, sonst mit der Chance
##   Balance.CHEST_BAG_CHANCE. Nie mehr als eines, und nur, solange es noch ins Raster passt.
## - recent: IDs aus der letzten Kiste. Sie kommen seltener (Gewicht mal
##   Balance.CHEST_REPEAT_WEIGHT), damit nicht ständig dasselbe angeboten wird.
## Gezogen wird nach Gewicht ohne Zurücklegen, danach gemischt. Reicht die Auswahl nicht für 3,
## folgen Trostpreise.
static func build_item_offers(rng: RandomNumberGenerator, backpack: BackpackState, rarity: int,
		force_bag: bool = false, recent: Array[String] = []) -> Array[Dictionary]:
	var room: int = BackpackState.COLS * BackpackState.ROWS - (backpack.cell_count() if backpack != null else 0)
	var upgrades: Array[String] = []
	var others: Array[String] = []
	var bags: Array[String] = []
	for id: String in ItemDefs.ORDER:
		if ItemDefs.min_rarity(id) > rarity or ItemDefs.weight(id) <= 0.0:
			continue
		if ItemDefs.is_bag(id):
			if ItemDefs.cell_count(id) <= room:
				bags.append(id)
			continue
		if backpack != null and backpack.highest_level(id) >= ItemDefs.MAX_RARITY:
			continue
		if ItemDefs.is_upgrade(id):
			upgrades.append(id)
		else:
			others.append(id)
	var chosen: Array[String] = []
	var first: String = _draw_weighted(rng, upgrades, recent)
	if not first.is_empty():
		chosen.append(first)
	# Der Zufallswert für das Rucksack-Teil wird immer gezogen, damit ein Lauf mit Seed gleich bleibt.
	var bag_roll: float = rng.randf()
	if not bags.is_empty() and (force_bag or bag_roll < Balance.CHEST_BAG_CHANCE):
		chosen.append(_draw_weighted(rng, bags, []))
	var pool: Array[String] = upgrades + others
	while chosen.size() < Balance.CHEST_OFFER_COUNT and not pool.is_empty():
		var pick: String = _draw_weighted(rng, pool, recent)
		if pick.is_empty():
			break
		chosen.append(pick)
	# Mischen, damit das sichere Upgrade nicht immer auf Karte 1 liegt.
	for i: int in range(chosen.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: String = chosen[i]
		chosen[i] = chosen[j]
		chosen[j] = swap
	var gain: int = levels_for_rarity(rarity)
	var offers: Array[Dictionary] = []
	for id: String in chosen:
		offers.append({
			"kind": KIND_ITEM,
			"id": id,
			"level": gain if ItemDefs.has_rarity(id) else 1,
			"owned_level": backpack.highest_level(id) if backpack != null else 0,
		})
	var consolation_index: int = 0
	while offers.size() < Balance.CHEST_OFFER_COUNT:
		offers.append(consolation_offer(consolation_index))
		consolation_index += 1
	return offers


## Enthält dieses Angebot ein Rucksack-Teil?
static func offers_have_bag(offers: Array) -> bool:
	for offer: Variant in offers:
		if offer is Dictionary and ItemDefs.is_bag(String((offer as Dictionary).get("id", ""))):
			return true
	return false


## IDs der Gegenstände in diesem Angebot (ohne Trostpreise).
static func offer_ids(offers: Array) -> Array[String]:
	var ids: Array[String] = []
	for offer: Variant in offers:
		if offer is Dictionary and String((offer as Dictionary).get("kind", "")) == KIND_ITEM:
			ids.append(String((offer as Dictionary).get("id", "")))
	return ids


## Zieht eine ID nach Gewicht aus pool und entfernt sie dort. "" bei leerer Auswahl.
## IDs aus recent zählen nur mit Balance.CHEST_REPEAT_WEIGHT ihres Gewichts.
static func _draw_weighted(rng: RandomNumberGenerator, pool: Array[String], recent: Array[String]) -> String:
	var total: float = 0.0
	for id: String in pool:
		total += _weight(id, recent)
	if pool.is_empty() or total <= 0.0:
		return ""
	var roll: float = rng.randf() * total
	var pick: String = pool[pool.size() - 1]
	for id: String in pool:
		roll -= _weight(id, recent)
		if roll < 0.0:
			pick = id
			break
	pool.erase(pick)
	return pick


static func _weight(id: String, recent: Array[String]) -> float:
	var weight: float = ItemDefs.weight(id)
	return weight * Balance.CHEST_REPEAT_WEIGHT if recent.has(id) else weight


## Trostpreis Nummer index (ab 0): gerade = 500 Punkte, ungerade = 50 Leben.
static func consolation_offer(index: int) -> Dictionary:
	if index % 2 == 0:
		return {"kind": KIND_POINTS, "amount": Balance.CONSOLATION_POINTS}
	return {"kind": KIND_HEAL, "amount": Balance.CONSOLATION_HEAL}


## Überschrift einer Angebotskarte: Upgrade-Name oder Name des Trostpreises.
static func offer_title(offer: Dictionary) -> String:
	match String(offer.get("kind", "")):
		KIND_UPGRADE:
			return UpgradeDefs.display_name(String(offer.get("id", "")))
		KIND_ITEM:
			return ItemDefs.display_name(String(offer.get("id", "")))
		KIND_POINTS:
			return "Trostpreis: Punkte"
		KIND_HEAL:
			return "Trostpreis: Erste Hilfe"
	return ""


## Zeile unter dem Namen einer Angebotskarte. Gegenstand: "Neu: Selten" oder "Selten · du hast
## Gewöhnlich", Rucksack-Teil: "Mehr Platz". Alte Upgrade-Angebote: "Neu: Stufe 2" oder
## "Stufe 2 → 4". Leer bei Trostpreisen.
static func offer_level_text(offer: Dictionary) -> String:
	if String(offer.get("kind", "")) == KIND_ITEM:
		var item_id: String = String(offer.get("id", ""))
		if ItemDefs.is_bag(item_id):
			return "Mehr Platz"
		var rarity_name: String = ItemDefs.rarity_name(int(offer.get("level", 1)))
		var owned: int = int(offer.get("owned_level", 0))
		if owned <= 0:
			return "Neu: %s" % rarity_name
		return "%s · du hast %s" % [rarity_name, ItemDefs.rarity_name(owned)]
	if String(offer.get("kind", "")) != KIND_UPGRADE:
		return ""
	var from_level: int = int(offer.get("from_level", 0))
	var to_level: int = int(offer.get("to_level", 0))
	if from_level <= 0:
		return "Neu: Stufe %d" % to_level
	return "Stufe %d → %d" % [from_level, to_level]


## Wirkungstext einer Angebotskarte mit den Zahlen der neuen Stufe.
static func offer_description(offer: Dictionary) -> String:
	match String(offer.get("kind", "")):
		KIND_UPGRADE:
			return UpgradeDefs.effect_text(String(offer.get("id", "")), int(offer.get("to_level", 1)))
		KIND_ITEM:
			return ItemDefs.description(String(offer.get("id", "")), int(offer.get("level", 1)))
		KIND_POINTS:
			return "+%d Punkte sofort aufs Konto." % int(offer.get("amount", 0))
		KIND_HEAL:
			return "Heilt dich sofort um %d Leben." % int(offer.get("amount", 0))
	return ""
