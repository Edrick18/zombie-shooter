extends RefCounted
## Upgrades eines Laufs: Stufen, Plätze, Synergien und die daraus abgeleiteten Werte.
## Reine Logik ohne Nodes. Die Upgrades hängen am Spieler und gelten für jede Waffe.
## Besitzer: Fundament. Einbinden mit: const UpgradeState := preload("res://scripts/core/upgrade_state.gd")

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")

const MAX_SLOTS := Balance.UPGRADE_MAX_SLOTS
const MAX_LEVEL := Balance.UPGRADE_MAX_LEVEL

## upgrade_id -> Stufe (1 bis 5). Die Reihenfolge der Schlüssel ist die Reihenfolge des Erwerbs.
var _levels: Dictionary = {}
## Bereits gemeldete Synergien, siehe check_new_synergies.
var _announced_synergies: Array[String] = []
## Abgeleiteter Zustand (aus dem Rucksack, siehe set_derived): Dann gelten diese Synergien statt
## der Stufen-Regel. null = nicht abgeleitet.
var _derived_synergies: Variant = null
## Zusatzwerte neben den Upgrades (Kandidat, Verstärker): "max_hp" in Leben, "speed", "damage",
## "reload" und "points" als Bruchteile (0.1 = 10 %).
var _extra: Dictionary = {}
## Exemplare je Upgrade (aus dem Rucksack): upgrade_id -> Array[int] mit der Stufe jedes
## Exemplars. null = nicht gesetzt, dann zählt je Upgrade ein Exemplar mit der Stufe aus _levels.
## Ist es gesetzt, rechnet value() nur damit: Ein Upgrade ohne Eintrag hat dann den Wert 0, auch
## wenn es in _levels steht (Stern-Gegenstände gelten je Waffe und nicht für alle).
var _copies: Variant = null


## Aktuelle Stufe, 0 wenn nicht im Besitz.
func get_level(id: String) -> int:
	return int(_levels.get(id, 0))


## Erhöht ein Upgrade um so viele Stufen (höchstens bis Stufe 5) und gibt die neue Stufe zurück.
## Ändert nichts bei unbekannter ID, bei levels <= 0 oder wenn das Upgrade neu wäre und kein
## Platz mehr frei ist. Dann kommt die unveränderte Stufe zurück.
func add_levels(id: String, levels: int) -> int:
	var current: int = get_level(id)
	if levels <= 0 or not UpgradeDefs.has(id):
		return current
	if current <= 0 and free_slots() <= 0:
		return current
	var new_level: int = mini(current + levels, MAX_LEVEL)
	_levels[id] = new_level
	# Von Hand gesetzte Stufen verlassen den abgeleiteten Zustand: Synergien gelten dann wieder
	# nach der Stufen-Regel (bis zum nächsten set_derived).
	_derived_synergies = null
	_copies = null
	return new_level


## Setzt den ganzen Zustand auf einmal (der Rucksack berechnet ihn): Stufen je Upgrade (ohne
## Platzgrenze, unbekannte IDs und Stufen unter 1 entfallen, höchstens Stufe 5), die aktiven
## Synergien und die Zusatzwerte. Bereits gemeldete Synergien bleiben gemerkt.
func set_derived(levels: Dictionary, synergies: Array[String], extra: Dictionary = {}, copies: Variant = null) -> void:
	_levels.clear()
	for id: String in levels:
		var level: int = int(levels[id])
		if UpgradeDefs.has(id) and level > 0:
			_levels[id] = mini(level, MAX_LEVEL)
	_derived_synergies = synergies.duplicate()
	_extra = extra.duplicate()
	_copies = (copies as Dictionary).duplicate(true) if copies is Dictionary else null


## Stufen der wirkenden Exemplare dieses Upgrades. Ohne Exemplar-Liste: ein Exemplar mit der
## Stufe aus get_level (oder keines).
func copies(id: String) -> Array:
	if _copies != null:
		return ((_copies as Dictionary).get(id, []) as Array).duplicate()
	var level: int = get_level(id)
	return [level] if level > 0 else []


## Beste Stufe dieses Upgrades hier und in other zusammen (für Kugel-Effekte: allgemeine Upgrades
## plus die der Waffe).
func level_with(other: RefCounted, id: String) -> int:
	var best: int = 0
	for level: Variant in copies(id) + (other.call("copies", id) as Array if other != null else []):
		best = maxi(best, int(level))
	return best


## Wert dieses Upgrades aus den Exemplaren hier und in other zusammen.
func value_with(other: RefCounted, id: String, key: String) -> float:
	return UpgradeDefs.combined_value(id, key, copies(id) + (other.call("copies", id) as Array if other != null else []))


## Kopie der Stufen: upgrade_id -> Stufe.
func levels() -> Dictionary:
	return _levels.duplicate()


## Zusatzwert mit diesem Namen (siehe _extra), 0.0 wenn keiner gesetzt ist.
func extra(key: String) -> float:
	return float(_extra.get(key, 0.0))


## Faktor auf den Waffenschaden: 1,0 ohne Zusatz.
func damage_multiplier() -> float:
	return maxf(0.1, 1.0 + extra("damage"))


## Faktor auf die Nachladezeit: 1,0 ohne Zusatz, kleiner ist schneller (mindestens 0,5).
func reload_time_multiplier() -> float:
	return clampf(1.0 - extra("reload"), 1.0 - Balance.RELOAD_BONUS_MAX, 1.0)


## IDs der Upgrades im Besitz, in der Reihenfolge des Erwerbs.
func owned_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _levels:
		ids.append(id)
	return ids


## Noch freie Plätze (von 6). Synergien belegen keinen Platz.
func free_slots() -> int:
	return maxi(0, MAX_SLOTS - _levels.size())


## Wählbar: bekannt, noch nicht Stufe 5 und entweder schon im Besitz oder ein Platz frei.
func is_eligible(id: String) -> bool:
	if not UpgradeDefs.has(id):
		return false
	var level: int = get_level(id)
	if level >= MAX_LEVEL:
		return false
	return level > 0 or free_slots() > 0


## Alle wählbaren Upgrade-IDs in der festen Reihenfolge von UpgradeDefs.ORDER.
func eligible_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in UpgradeDefs.ORDER:
		if is_eligible(id):
			ids.append(id)
	return ids


## Sind die Voraussetzungen der Synergie erfüllt? (Stufen sinken nie, also bleibt es dabei.)
func has_synergy(id: String) -> bool:
	if _derived_synergies != null:
		return (_derived_synergies as Array).has(id)
	var requires: Dictionary = UpgradeDefs.synergy_requirements(id)
	if requires.is_empty():
		return false
	for upgrade_id: String in requires:
		if get_level(upgrade_id) < int(requires[upgrade_id]):
			return false
	return true


## Synergien, die seit dem letzten Aufruf neu erfüllt sind. Jede wird genau einmal gemeldet.
func check_new_synergies() -> Array[String]:
	var fresh: Array[String] = []
	for id: String in UpgradeDefs.synergy_ids():
		if has_synergy(id) and not _announced_synergies.has(id):
			_announced_synergies.append(id)
			fresh.append(id)
	return fresh


## Alle erfüllten Synergien.
func active_synergies() -> Array[String]:
	var ids: Array[String] = []
	for id: String in UpgradeDefs.synergy_ids():
		if has_synergy(id):
			ids.append(id)
	return ids


## Wert der aktuellen Stufe (Schlüssel siehe UpgradeDefs.UPGRADES), 0.0 wenn nicht im Besitz.
func value(id: String, key: String) -> float:
	return UpgradeDefs.combined_value(id, key, copies(id))


## Faktor auf alle Punkte: 1,0 ohne Glück, 1,1 bis 1,5 mit "luck".
func points_multiplier() -> float:
	return maxf(0.0, 1.0 + value("luck", "points_bonus") + extra("points"))


## Faktor auf das Lauftempo: 1,0 ohne, 1,08 bis 1,4 mit "speed".
func speed_multiplier() -> float:
	return maxf(0.2, 1.0 + value("speed", "bonus") + extra("speed"))


## Zusätzliches Maximal-Leben aus "max_hp" (0 bis 100).
func bonus_max_hp() -> float:
	return value("max_hp", "bonus") + extra("max_hp")


## Glück-Stufe für die Seltenheit der Kisten (Stufe von "luck", 0 bis 5).
func luck_level() -> int:
	return get_level("luck")


## Zusätzliche Kistenchance normaler Zombies als Bruchteil (0.01 je Glück-Stufe).
func chest_chance_bonus() -> float:
	return value("luck", "chest_chance")


## Übersicht für Game Over und HUD: je Upgrade im Besitz ein Dictionary
## { "id": String, "name": String, "level": int }, in der Reihenfolge des Erwerbs.
func summary() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in _levels:
		rows.append({"id": id, "name": UpgradeDefs.display_name(id), "level": int(_levels[id])})
	return rows
