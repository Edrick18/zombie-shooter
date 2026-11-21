extends RefCounted
## Wellenplan (Abschnitt 8 "Zombies"): Zusammensetzung, Reihenfolge und Faktoren je Welle.
## Reine Rechenfunktionen ohne Zufall: dieselbe Welle ergibt immer dieselbe Liste.
## Besitzer: Fundament. Einbinden mit: const WavePlan := preload("res://scripts/core/wave_plan.gd")

const Balance := preload("res://scripts/core/balance.gd")

const TYPE_WALKER: String = "walker"
const TYPE_SPRINTER: String = "sprinter"
const TYPE_ELITE: String = "elite"


## Zombies der Welle ohne Elite: 6 + 4 * Welle.
static func normal_count(wave: int) -> int:
	var w: int = maxi(wave, 1)
	return Balance.WAVE_BASE_COUNT + Balance.WAVE_COUNT_PER_WAVE * w


## Sprinter-Anteil der Welle in Prozent (0, 20 oder 35).
static func sprinter_share_percent(wave: int) -> int:
	return _step_value(Balance.SPRINTER_SHARE_STEPS, wave)


## Anzahl Sprinter: Anteil von normal_count, kaufmännisch gerundet (ab ,5 aufwärts).
static func sprinter_count(wave: int) -> int:
	return (normal_count(wave) * sprinter_share_percent(wave) + 50) / 100


## Anzahl Schlurfer der Welle.
static func walker_count(wave: int) -> int:
	return normal_count(wave) - sprinter_count(wave)


## Anzahl Elite-Zombies (zusätzlich zu normal_count): ab Welle 2 eine, ab 6 zwei, ab 10 drei.
static func elite_count(wave: int) -> int:
	return _step_value(Balance.ELITE_COUNT_STEPS, wave)


## Alle Zombies der Welle einschließlich Elite.
static func total_count(wave: int) -> int:
	return normal_count(wave) + elite_count(wave)


## Geordnete Spawn-Liste der Welle mit den Typen "walker", "sprinter", "elite".
## Sprinter sind gleichmäßig zwischen die Schlurfer gestreut, Elite gleichmäßig über die Welle
## verteilt (eine Elite kommt in der Mitte, nie als Erste).
static func spawn_list(wave: int) -> Array[String]:
	var normals: int = normal_count(wave)
	var sprinters: int = sprinter_count(wave)
	var elites: int = elite_count(wave)
	var list: Array[String] = []
	var elites_placed: int = 0
	for i: int in normals:
		# Sprinter an den Stellen, an denen der gestreckte Zähler eine ganze Zahl überschreitet.
		var is_sprinter: bool = ((i + 1) * sprinters) / normals > (i * sprinters) / normals
		list.append(TYPE_SPRINTER if is_sprinter else TYPE_WALKER)
		# Elite j (ab 1) folgt nach j * normals / (elites + 1) normalen Zombies.
		while elites_placed < elites and i + 1 >= ((elites_placed + 1) * normals) / (elites + 1):
			list.append(TYPE_ELITE)
			elites_placed += 1
	return list


## Lebens-Faktor: 1 + 0.12 * (Welle - 1) bis Welle 10, danach je weiterer Welle mal 1,1
## (Welle 11 = Faktor von Welle 10 mal 1,1, Welle 12 mal 1,21 usw.).
static func hp_factor(wave: int) -> float:
	var w: int = maxi(wave, 1)
	var linear_wave: int = mini(w, Balance.HP_FACTOR_LINEAR_UNTIL_WAVE)
	var factor: float = 1.0 + Balance.HP_FACTOR_PER_WAVE * float(linear_wave - 1)
	if w > Balance.HP_FACTOR_LINEAR_UNTIL_WAVE:
		factor *= pow(Balance.HP_FACTOR_LATE_MULTIPLIER, float(w - Balance.HP_FACTOR_LINEAR_UNTIL_WAVE))
	return factor


## Tempo der Schlurfer: 1,6 m/s in Welle 1, je Welle +0,1 bis höchstens 3,0.
static func walker_speed(wave: int) -> float:
	var w: int = maxi(wave, 1)
	return minf(Balance.WALKER_SPEED_MAX, Balance.WALKER_SPEED_START + Balance.WALKER_SPEED_PER_WAVE * float(w - 1))


## Sekunden zwischen zwei Spawns: max(0.4, 1.5 - 0.1 * Welle).
static func spawn_interval(wave: int) -> float:
	var w: int = maxi(wave, 1)
	return maxf(Balance.SPAWN_INTERVAL_MIN, Balance.SPAWN_INTERVAL_BASE - Balance.SPAWN_INTERVAL_PER_WAVE * float(w))


## Effekt-Faktor für feste Schadenswerte der Upgrades: 0.75 * Lebens-Faktor, mindestens 1.
static func effect_factor(wave: int) -> float:
	return maxf(Balance.EFFECT_FACTOR_MIN, Balance.EFFECT_FACTOR_SHARE * hp_factor(wave))


## Maximal-Leben eines Zombies dieses Typs in dieser Welle (Grundwert mal Lebens-Faktor).
static func zombie_hp(type: String, wave: int) -> float:
	return float(_type_def(type)["hp"]) * hp_factor(wave)


## Lauftempo eines Zombies dieses Typs in dieser Welle.
static func zombie_speed(type: String, wave: int) -> float:
	if type == TYPE_WALKER:
		return walker_speed(wave)
	return float(_type_def(type)["speed"])


## Schaden eines Schlags dieses Zombie-Typs (wächst nicht mit der Welle).
static func zombie_damage(type: String) -> float:
	return float(_type_def(type)["damage"])


## Alles Wichtige einer Welle in einem Dictionary mit den Schlüsseln:
## wave (int), spawns (Array[String]), total (int), hp_factor (float), walker_speed (float),
## spawn_interval (float), effect_factor (float).
static func plan(wave: int) -> Dictionary:
	var w: int = maxi(wave, 1)
	var spawns: Array[String] = spawn_list(w)
	return {
		"wave": w,
		"spawns": spawns,
		"total": spawns.size(),
		"hp_factor": hp_factor(w),
		"walker_speed": walker_speed(w),
		"spawn_interval": spawn_interval(w),
		"effect_factor": effect_factor(w),
	}


static func _type_def(type: String) -> Dictionary:
	if Balance.ZOMBIE_TYPES.has(type):
		return Balance.ZOMBIE_TYPES[type]
	return Balance.ZOMBIE_TYPES[TYPE_WALKER]


## Wert des letzten Eintrags [ab Welle, Wert], dessen Welle erreicht ist, sonst 0.
static func _step_value(steps: Array, wave: int) -> int:
	var result: int = 0
	for step: Array in steps:
		if wave >= int(step[0]):
			result = int(step[1])
	return result
