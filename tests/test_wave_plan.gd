extends SceneTree
## Tests für WavePlan: Zusammensetzung und Reihenfolge der Wellen, Lebens-Faktor, Tempo,
## Spawn-Abstand, Effekt-Faktor und die Grundwerte der Zombie-Typen.

const Balance := preload("res://scripts/core/balance.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")

var _failures := 0


func _init() -> void:
	_test_composition()
	_test_order()
	_test_hp_factor()
	_test_walker_speed()
	_test_spawn_interval()
	_test_effect_factor()
	_test_zombie_values()
	_test_plan()
	_test_other_numbers()

	if _failures == 0:
		print("Alle Wellen-Tests bestanden.")
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


## Wellen 1, 2, 3, 6, 10, 15: Schlurfer, Sprinter, Elite laut Abschnitt 8.
func _test_composition() -> void:
	# Welle: [normale (6 + 4 * Welle), Sprinter, Elite]
	var expected: Dictionary = {
		1: [10, 0, 0],
		2: [14, 0, 1],
		3: [18, 4, 1],    # 20 % von 18 = 3,6 -> 4
		6: [30, 11, 2],   # 35 % von 30 = 10,5 -> 11
		10: [46, 16, 3],  # 35 % von 46 = 16,1 -> 16
		15: [66, 23, 3],  # 35 % von 66 = 23,1 -> 23
	}
	for wave: int in expected:
		var normals: int = int(expected[wave][0])
		var sprinters: int = int(expected[wave][1])
		var elites: int = int(expected[wave][2])
		_check(WavePlan.normal_count(wave) == normals, "Welle %d: %d normale Zombies, waren %d." % [wave, normals, WavePlan.normal_count(wave)])
		_check(WavePlan.sprinter_count(wave) == sprinters, "Welle %d: %d Sprinter, waren %d." % [wave, sprinters, WavePlan.sprinter_count(wave)])
		_check(WavePlan.walker_count(wave) == normals - sprinters, "Welle %d: %d Schlurfer, waren %d." % [wave, normals - sprinters, WavePlan.walker_count(wave)])
		_check(WavePlan.elite_count(wave) == elites, "Welle %d: %d Elite, waren %d." % [wave, elites, WavePlan.elite_count(wave)])
		_check(WavePlan.total_count(wave) == normals + elites, "Welle %d: zusammen %d, waren %d." % [wave, normals + elites, WavePlan.total_count(wave)])
		var list: Array[String] = WavePlan.spawn_list(wave)
		_check(list.size() == normals + elites, "Welle %d: Liste hat %d Einträge, waren %d." % [wave, normals + elites, list.size()])
		_check(list.count("walker") == normals - sprinters, "Welle %d: %d Schlurfer in der Liste, waren %d." % [wave, normals - sprinters, list.count("walker")])
		_check(list.count("sprinter") == sprinters, "Welle %d: %d Sprinter in der Liste, waren %d." % [wave, sprinters, list.count("sprinter")])
		_check(list.count("elite") == elites, "Welle %d: %d Elite in der Liste, waren %d." % [wave, elites, list.count("elite")])
	# Schwellen der Anteile und der Elite.
	_check(WavePlan.sprinter_share_percent(2) == 0 and WavePlan.sprinter_share_percent(3) == 20 and WavePlan.sprinter_share_percent(5) == 20, "Sprinter ab Welle 3 mit 20 %.")
	_check(WavePlan.sprinter_share_percent(6) == 35 and WavePlan.sprinter_share_percent(40) == 35, "Sprinter ab Welle 6 mit 35 %.")
	_check(WavePlan.elite_count(1) == 0 and WavePlan.elite_count(5) == 1 and WavePlan.elite_count(9) == 2 and WavePlan.elite_count(30) == 3, "Elite: ab 2 eine, ab 6 zwei, ab 10 drei.")
	# Jede Welle bis 30: Liste passt zu den Zählern und kennt nur die drei Typen.
	for wave: int in range(1, 31):
		var list: Array[String] = WavePlan.spawn_list(wave)
		_check(list.size() == 6 + 4 * wave + WavePlan.elite_count(wave), "Welle %d: Gesamtzahl 6 + 4 * Welle + Elite." % wave)
		_check(list.count("walker") + list.count("sprinter") + list.count("elite") == list.size(), "Welle %d: nur bekannte Typen." % wave)
		_check(list.count("sprinter") == WavePlan.sprinter_count(wave), "Welle %d: Sprinter-Zahl der Liste passt." % wave)


func _test_order() -> void:
	_check(WavePlan.spawn_list(4) == WavePlan.spawn_list(4), "Dieselbe Welle ergibt dieselbe Reihenfolge.")
	for wave: int in [2, 3, 6, 10, 15]:
		var list: Array[String] = WavePlan.spawn_list(wave)
		_check(list[0] != "elite", "Welle %d: Die erste ist keine Elite." % wave)
		var elites: int = WavePlan.elite_count(wave)
		var first_elite: int = list.find("elite")
		_check(first_elite >= list.size() / (elites + 2), "Welle %d: Die erste Elite kommt nicht gleich am Anfang (Stelle %d)." % [wave, first_elite])
	# Eine Elite steht in der Mitte.
	var wave2: Array[String] = WavePlan.spawn_list(2)
	_check(wave2.find("elite") == 7, "Welle 2: Elite nach 7 Schlurfern, war Stelle %d." % wave2.find("elite"))
	# Sprinter sind gestreut, nicht am Stück.
	var wave6: Array[String] = WavePlan.spawn_list(6)
	var longest_run: int = 0
	var run: int = 0
	for type: String in wave6:
		run = run + 1 if type == "sprinter" else 0
		longest_run = maxi(longest_run, run)
	_check(longest_run <= 2, "Welle 6: höchstens 2 Sprinter hintereinander, waren %d." % longest_run)
	_check(wave6.slice(0, 10).has("sprinter") and wave6.slice(wave6.size() - 10).has("sprinter"), "Welle 6: Sprinter am Anfang und am Ende.")
	_check(WavePlan.spawn_list(0) == WavePlan.spawn_list(1) and WavePlan.spawn_list(-4) == WavePlan.spawn_list(1), "Wellen unter 1 zählen als Welle 1.")


## Lebens-Faktor: 1 + 0.12 * (Welle - 1) bis Welle 10, danach je Welle mal 1,1.
func _test_hp_factor() -> void:
	_check_float(WavePlan.hp_factor(1), 1.0, "Lebens-Faktor Welle 1")
	_check_float(WavePlan.hp_factor(2), 1.12, "Lebens-Faktor Welle 2")
	_check_float(WavePlan.hp_factor(5), 1.48, "Lebens-Faktor Welle 5")
	_check_float(WavePlan.hp_factor(10), 2.08, "Lebens-Faktor Welle 10")
	_check_float(WavePlan.hp_factor(11), 2.08 * 1.1, "Lebens-Faktor Welle 11")
	_check_float(WavePlan.hp_factor(11), 2.288, "Lebens-Faktor Welle 11 als Zahl")
	_check_float(WavePlan.hp_factor(12), 2.08 * 1.1 * 1.1, "Lebens-Faktor Welle 12")
	_check_float(WavePlan.hp_factor(12), 2.5168, "Lebens-Faktor Welle 12 als Zahl")
	_check_float(WavePlan.hp_factor(20), 2.08 * pow(1.1, 10.0), "Lebens-Faktor Welle 20")
	_check_float(WavePlan.hp_factor(0), 1.0, "Lebens-Faktor Welle 0 zählt als Welle 1")
	for wave: int in range(1, 30):
		_check(WavePlan.hp_factor(wave + 1) > WavePlan.hp_factor(wave), "Lebens-Faktor steigt von Welle %d zu %d." % [wave, wave + 1])


func _test_walker_speed() -> void:
	_check_float(WavePlan.walker_speed(1), 1.6, "Schlurfer-Tempo Welle 1")
	_check_float(WavePlan.walker_speed(2), 1.7, "Schlurfer-Tempo Welle 2")
	_check_float(WavePlan.walker_speed(10), 2.5, "Schlurfer-Tempo Welle 10")
	_check_float(WavePlan.walker_speed(15), 3.0, "Schlurfer-Tempo Welle 15")
	_check_float(WavePlan.walker_speed(16), 3.0, "Schlurfer-Tempo Welle 16 (Höchstwert)")
	_check_float(WavePlan.walker_speed(50), 3.0, "Schlurfer-Tempo Welle 50 (Höchstwert)")


func _test_spawn_interval() -> void:
	_check_float(WavePlan.spawn_interval(1), 1.4, "Spawn-Abstand Welle 1")
	_check_float(WavePlan.spawn_interval(5), 1.0, "Spawn-Abstand Welle 5")
	_check_float(WavePlan.spawn_interval(10), 0.5, "Spawn-Abstand Welle 10")
	_check_float(WavePlan.spawn_interval(11), 0.4, "Spawn-Abstand Welle 11")
	_check_float(WavePlan.spawn_interval(11), 0.4, "Spawn-Abstand Welle 11")
	_check_float(WavePlan.spawn_interval(12), 0.38, "Spawn-Abstand Welle 12: ab hier je Welle 0,02 s kürzer")
	_check_float(WavePlan.spawn_interval(20), 0.22, "Spawn-Abstand Welle 20")
	_check_float(WavePlan.spawn_interval(25), 0.15, "Spawn-Abstand Welle 25 (Boden)")
	_check_float(WavePlan.spawn_interval(60), 0.15, "Spawn-Abstand Welle 60 (Boden)")
	# Zombies gleichzeitig: 24 bis Welle 10, dann je Welle 2 mehr, höchstens 48.
	_check(WavePlan.max_alive(1) == 24 and WavePlan.max_alive(10) == 24, "Bis Welle 10 leben höchstens 24 Zombies gleichzeitig.")
	_check(WavePlan.max_alive(11) == 26 and WavePlan.max_alive(15) == 34, "Danach je Welle 2 mehr.")
	_check(WavePlan.max_alive(22) == 48 and WavePlan.max_alive(60) == 48, "Höchstens 48 gleichzeitig.")
	# Schaden der Zombies: ab Welle 5 je Welle 5 % mehr.
	_check_float(WavePlan.damage_factor(1), 1.0, "Schadens-Faktor Welle 1")
	_check_float(WavePlan.damage_factor(5), 1.0, "Schadens-Faktor Welle 5")
	_check_float(WavePlan.damage_factor(10), 1.25, "Schadens-Faktor Welle 10")
	_check_float(WavePlan.damage_factor(33), 2.4, "Schadens-Faktor Welle 33")
	_check_float(WavePlan.zombie_damage("walker"), 20.0, "Schaden Schlurfer ohne Welle")
	_check_float(WavePlan.zombie_damage("walker", 33), 48.0, "Schaden Schlurfer Welle 33")
	_check_float(WavePlan.zombie_damage("elite", 10), 35.0 * 1.25, "Schaden Elite Welle 10")


## Effekt-Faktor: 0.75 * Lebens-Faktor, mindestens 1.
func _test_effect_factor() -> void:
	_check_float(WavePlan.effect_factor(1), 1.0, "Effekt-Faktor Welle 1")
	_check_float(WavePlan.effect_factor(3), 1.0, "Effekt-Faktor Welle 3 (0,93 wird 1)")
	_check_float(WavePlan.effect_factor(4), 1.02, "Effekt-Faktor Welle 4")
	_check_float(WavePlan.effect_factor(5), 1.11, "Effekt-Faktor Welle 5")
	_check_float(WavePlan.effect_factor(10), 1.56, "Effekt-Faktor Welle 10")
	# Ab Welle 11 wächst der Effekt-Faktor je Welle nur noch mal 1,04 (das Leben mal 1,1).
	_check_float(WavePlan.effect_factor(10), 0.75 * 2.08, "Effekt-Faktor Welle 10")
	_check_float(WavePlan.effect_factor(11), 0.75 * 2.08 * 1.04, "Effekt-Faktor Welle 11")
	_check_float(WavePlan.effect_factor(33), 0.75 * 2.08 * pow(1.04, 23.0), "Effekt-Faktor Welle 33")
	_check(WavePlan.effect_factor(33) / WavePlan.hp_factor(33) < 0.25, "In Welle 33 halten feste Schadenswerte nur noch ein Viertel mit dem Leben der Zombies mit.")
	_check(WavePlan.effect_factor(33) > WavePlan.effect_factor(20), "Der Effekt-Faktor wächst weiter, nur langsamer.")


func _test_zombie_values() -> void:
	var types: Dictionary = Balance.ZOMBIE_TYPES
	_check(types.size() == 3 and types.has("walker") and types.has("sprinter") and types.has("elite"), "Es gibt walker, sprinter und elite.")
	_check_float(float(types["walker"]["hp"]), 60.0, "Leben Schlurfer")
	_check_float(float(types["sprinter"]["hp"]), 35.0, "Leben Sprinter")
	_check_float(float(types["elite"]["hp"]), 400.0, "Leben Elite")
	_check_float(float(types["elite"]["scale"]), 1.3, "Größe Elite")
	_check(int(types["walker"]["from_wave"]) == 1 and int(types["sprinter"]["from_wave"]) == 3 and int(types["elite"]["from_wave"]) == 2, "Erste Welle je Typ.")
	_check_float(WavePlan.zombie_hp("walker", 1), 60.0, "Schlurfer Welle 1")
	_check_float(WavePlan.zombie_hp("walker", 10), 60.0 * 2.08, "Schlurfer Welle 10")
	_check_float(WavePlan.zombie_hp("sprinter", 3), 35.0 * 1.24, "Sprinter Welle 3")
	_check_float(WavePlan.zombie_hp("elite", 2), 400.0 * 1.12, "Elite Welle 2")
	_check_float(WavePlan.zombie_hp("elite", 12), 400.0 * 2.5168, "Elite Welle 12")
	_check_float(WavePlan.zombie_hp("unbekannt", 1), 60.0, "Unbekannter Typ zählt als Schlurfer")
	_check_float(WavePlan.zombie_speed("walker", 1), 1.6, "Tempo Schlurfer Welle 1")
	_check_float(WavePlan.zombie_speed("walker", 20), 3.0, "Tempo Schlurfer Welle 20")
	_check_float(WavePlan.zombie_speed("sprinter", 3), 5.0, "Tempo Sprinter")
	_check_float(WavePlan.zombie_speed("sprinter", 10), 5.0, "Tempo Sprinter bis Welle 10")
	_check_float(WavePlan.zombie_speed("sprinter", 20), 5.5, "Tempo Sprinter Welle 20: je Welle 0,05 m/s mehr")
	_check_float(WavePlan.zombie_speed("sprinter", 60), 6.4, "Tempo Sprinter höchstens 6,4 m/s (der Spieler sprintet 7)")
	_check_float(WavePlan.zombie_speed("elite", 2), 2.6, "Tempo Elite")
	_check_float(WavePlan.zombie_damage("walker"), 20.0, "Schaden Schlurfer")
	_check_float(WavePlan.zombie_damage("sprinter"), 15.0, "Schaden Sprinter")
	_check_float(WavePlan.zombie_damage("elite"), 35.0, "Schaden Elite")


func _test_plan() -> void:
	var plan: Dictionary = WavePlan.plan(6)
	for key: String in ["wave", "spawns", "total", "hp_factor", "walker_speed", "spawn_interval", "effect_factor"]:
		_check(plan.has(key), "plan() hat den Schlüssel %s." % key)
	_check(plan.size() == 9 and plan.has("max_alive") and plan.has("damage_factor"), "plan() hat genau 9 Schlüssel, darunter max_alive und damage_factor.")
	_check(int(plan["wave"]) == 6, "plan: Welle 6.")
	_check(plan["spawns"] == WavePlan.spawn_list(6), "plan: spawns ist die Spawn-Liste.")
	_check(int(plan["total"]) == 32, "plan: 32 Zombies in Welle 6, waren %s." % plan["total"])
	_check_float(float(plan["hp_factor"]), 1.6, "plan: Lebens-Faktor Welle 6")
	_check_float(float(plan["walker_speed"]), 2.1, "plan: Schlurfer-Tempo Welle 6")
	_check_float(float(plan["spawn_interval"]), 0.9, "plan: Spawn-Abstand Welle 6")
	_check_float(float(plan["effect_factor"]), 1.2, "plan: Effekt-Faktor Welle 6")
	_check(int(WavePlan.plan(0)["wave"]) == 1, "plan: Welle 0 zählt als Welle 1.")


## Weitere Zahlen aus Abschnitt 8, die Zombies und Wellen betreffen.
func _test_other_numbers() -> void:
	_check(Balance.MAX_ZOMBIES_ALIVE == 24, "Höchstens 24 Zombies gleichzeitig.")
	_check_float(Balance.INTERMISSION_SECONDS, 12.0, "Pause zwischen Wellen")
	_check_float(Balance.FIRST_WAVE_DELAY, 4.0, "Erste Welle nach 4 s")
	_check_float(Balance.ZOMBIE_ATTACK_RANGE, 1.4, "Angriffsreichweite")
	_check_float(Balance.ZOMBIE_ATTACK_WINDUP, 0.4, "Ausholen")
	_check_float(Balance.ZOMBIE_ATTACK_COOLDOWN, 1.0, "Pause nach dem Schlag")
	_check_float(Balance.ZOMBIE_REPATH_INTERVAL, 0.25, "Pfad alle 0,25 s")
	_check_float(Balance.PLAYER_MAX_HP, 100.0, "Leben des Spielers")
	_check_float(Balance.WAVE_END_HEAL, 25.0, "Heilung am Wellenende")
	_check_float(Balance.PLAYER_WALK_SPEED, 5.0, "Gehen")
	_check_float(Balance.PLAYER_SPRINT_SPEED, 7.0, "Sprinten")
	_check_float(Balance.PLAYER_JUMP_VELOCITY, 4.5, "Sprung")
	_check_float(Balance.GRAVITY, 12.0, "Schwerkraft")
	_check_float(Balance.PLAYER_EYE_HEIGHT, 1.6, "Augenhöhe")
	_check_float(Balance.PLAYER_FOV, 80.0, "Sichtfeld")
	_check_float(Balance.PLAYER_HIT_INVULNERABILITY, 0.5, "Unverwundbarkeit nach Treffer")
	_check_float(Balance.INTERACT_RANGE, 2.5, "Interaktions-Reichweite")


func _check_float(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) < 0.0001, "%s: erwartet %s, war %s." % [label, expected, actual])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
