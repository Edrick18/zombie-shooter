extends SceneTree
## Tests für WeaponDefs und WeaponState: Waffentabelle mit neun Waffen, Schussfolge, Magazin,
## unendliche Munition (Nachladen ist immer möglich), Schussrate bei verschiedenen Bildraten.

const Balance := preload("res://scripts/core/balance.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const WeaponState := preload("res://scripts/core/weapon_state.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_test_table()
	_test_balance()
	_test_damage_helpers()
	_test_fire_and_cooldown()
	_test_reload()
	_test_reload_always_possible()
	_test_reload_rules()
	_test_refill()
	_test_fire_rate_over_time()
	_test_unknown_weapon()

	if _failures == 0:
		print("Alle Waffen-Tests bestanden (%d Prüfungen)." % _checks)
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


## Die Tabelle aus Abschnitt 18: neun Waffen, ohne Vorrat und ohne Munitionspreis.
func _test_table() -> void:
	# id: [Name, Schaden, Schuss/s, Magazin, Nachladen, Streuung, Kugeln, Auto, Preis, Radius, Explosionsschaden]
	var expected: Dictionary = {
		"pistol": ["Dienstpistole", 25.0, 5.0, 10, 1.2, 0.5, 1, false, 0, 0.0, 0.0],
		"revolver": ["Kandidatenschreck", 70.0, 2.0, 6, 1.9, 0.3, 1, false, 400, 0.0, 0.0],
		"smg": ["Quotenhammer", 16.0, 12.0, 30, 1.8, 1.8, 1, true, 1000, 0.0, 0.0],
		"sawed_off": ["Blitzrunde", 14.0, 2.0, 2, 1.4, 8.0, 5, false, 400, 0.0, 0.0],
		"shotgun": ["Publikumsjoker", 14.0, 1.25, 6, 2.2, 5.0, 8, false, 500, 0.0, 0.0],
		"rifle": ["Dauerbrenner", 24.0, 9.0, 30, 2.0, 1.0, 1, true, 1250, 0.0, 0.0],
		"sniper": ["Fernbedienung", 240.0, 0.8, 5, 2.6, 0.0, 1, false, 1250, 0.0, 0.0],
		"minigun": ["Applausmaschine", 13.0, 20.0, 120, 4.0, 2.6, 1, true, 2000, 0.0, 0.0],
		"rocket_launcher": ["Showfinale", 250.0, 1.0, 1, 2.4, 0.3, 1, false, 2000, 3.5, 150.0],
	}
	var keys: Array[String] = ["name", "damage", "fire_rate", "magazine", "reload_time", "spread_deg", "pellets", "automatic", "price", "explosion_radius", "explosion_damage"]
	var order: Array[String] = ["pistol", "revolver", "smg", "sawed_off", "shotgun", "rifle", "sniper", "minigun", "rocket_launcher"]
	_check(WeaponDefs.WEAPONS.size() == 9, "Es gibt genau 9 Waffen.")
	_check(WeaponDefs.ORDER == order and WeaponDefs.all_ids() == order, "Reihenfolge der neun Waffen: erst Einhand, dann Zweihand.")
	_check(WeaponDefs.START_WEAPON == "pistol", "Startwaffe ist die Pistole.")
	_check(WeaponDefs.INFINITE_RESERVE == -1, "Unendlicher Vorrat ist -1 (für das alte Signal ammo_changed).")
	var names: Dictionary = {}
	for id: String in expected:
		_check(WeaponDefs.has(id), "Waffe %s fehlt." % id)
		var def: Dictionary = WeaponDefs.get_def(id)
		_check(def.size() == keys.size(), "%s hat genau %d Schlüssel, waren %d." % [id, keys.size(), def.size()])
		_check(not def.has("reserve") and not def.has("ammo_price"), "%s hat weder Vorrat noch Munitionspreis." % id)
		for i: int in keys.size():
			var key: String = keys[i]
			_check(def.has(key), "%s: Schlüssel %s fehlt." % [id, key])
			var want: Variant = expected[id][i]
			var got: Variant = def.get(key)
			var same: bool = is_equal_approx(float(got), float(want)) if want is float else got == want
			_check(same, "%s.%s: erwartet %s, war %s." % [id, key, want, got])
		_check(WeaponDefs.display_name(id) == String(expected[id][0]), "Name von %s." % id)
		names[WeaponDefs.display_name(id)] = true
		# Jede Waffe ist auch ein Gegenstand für den Rucksack mit einer oder zwei Händen.
		_check(ItemDefs.is_weapon(id) and ItemDefs.hands(id) >= 1, "%s ist ein Waffen-Gegenstand." % id)
		_check(ItemDefs.display_name(id) == WeaponDefs.display_name(id), "Der Gegenstand %s heißt wie die Waffe." % id)
	_check(names.size() == 9, "Jede Waffe hat ihren eigenen Namen.")
	for id: String in ItemDefs.all_ids():
		if ItemDefs.is_weapon(id):
			_check(WeaponDefs.has(id), "Der Waffen-Gegenstand %s steht in der Waffentabelle." % id)
	_check(is_equal_approx(WeaponDefs.fire_interval("pistol"), 0.2), "Pistole: 0,2 s zwischen Schüssen.")
	_check(is_equal_approx(WeaponDefs.fire_interval("shotgun"), 0.8), "Schrotflinte: 0,8 s zwischen Schüssen.")
	_check(is_equal_approx(WeaponDefs.fire_interval("smg"), 1.0 / 12.0), "MP: ein Zwölftel s zwischen Schüssen.")
	_check(is_equal_approx(WeaponDefs.fire_interval("minigun"), 0.05), "Minigun: ein Zwanzigstel s zwischen Schüssen.")
	_check(WeaponDefs.is_explosive("rocket_launcher"), "Der Raketenwerfer explodiert.")
	for id: String in order:
		if id != "rocket_launcher":
			_check(not WeaponDefs.is_explosive(id), "%s explodiert nicht." % id)
	_check(is_equal_approx(Balance.WEAPON_RANGE, 60.0), "Reichweite 60 m.")
	_check(is_equal_approx(Balance.HEADSHOT_MULTIPLIER, 2.0), "Kopfschuss mal 2.")
	_check(Balance.HEADSHOT_HEIGHT_RATIO > 0.5 and Balance.HEADSHOT_HEIGHT_RATIO < 1.0, "Kopfbereich liegt im oberen Teil des Körpers.")
	_check(Balance.POINTS_BULLET_HIT == 10 and Balance.POINTS_KILL == 60 and Balance.POINTS_HEADSHOT_KILL_BONUS == 30 and Balance.POINTS_ELITE_KILL == 150, "Punkte: 10 / 60 / +30 / 150.")
	_check(Balance.POINTS_START == 0 and Balance.DOOR_COST == 750, "Start 0 Punkte, Tür 750.")


## Schaden je Sekunde: zwischen Pistole (125) und etwa 260, Zweihand-Waffen im Schnitt stärker.
func _test_balance() -> void:
	_check(is_equal_approx(WeaponDefs.dps("pistol"), 125.0), "Pistole: 125 Schaden je Sekunde.")
	_check(is_equal_approx(WeaponDefs.dps("shotgun"), 140.0), "Schrotflinte: 8 Kugeln zählen mit (140).")
	_check(WeaponDefs.dps("unbekannt") == 0.0, "Unbekannte Waffe: 0 Schaden je Sekunde.")
	var one_handed: Array[float] = []
	var two_handed: Array[float] = []
	for id: String in WeaponDefs.ORDER:
		var dps: float = WeaponDefs.dps(id)
		_check(dps >= 125.0 - 0.01 and dps <= 260.0 + 0.01, "%s liegt zwischen 125 und 260 Schaden je Sekunde, war %s." % [id, dps])
		var def: Dictionary = WeaponDefs.get_def(id)
		_check(int(def["magazine"]) >= 1 and float(def["reload_time"]) > 0.0 and float(def["fire_rate"]) > 0.0 and int(def["pellets"]) >= 1,
			"%s hat Magazin, Nachladezeit, Schussrate und Kugeln." % id)
		_check((int(def["price"]) > 0) == (id != WeaponDefs.START_WEAPON), "%s: Nur die Startwaffe kostet nichts." % id)
		if ItemDefs.hands(id) == 1:
			one_handed.append(dps)
		else:
			two_handed.append(dps)
	_check(one_handed.size() == 4 and two_handed.size() == 5, "Vier Einhand- und fünf Zweihand-Waffen.")
	_check(_average(two_handed) > _average(one_handed), "Zweihand-Waffen sind im Schnitt stärker (%s gegen %s)." % [_average(two_handed), _average(one_handed)])
	_check(two_handed.max() > one_handed.max(), "Die stärkste Waffe braucht zwei Hände.")
	_check(int(WeaponDefs.get_def("rocket_launcher")["magazine"]) == 1, "Der Raketenwerfer hat eine Rakete je Magazin.")
	_check(int(WeaponDefs.get_def("sawed_off")["magazine"]) == 2, "Die abgesägte Schrotflinte hat zwei Patronen.")
	_check(float(WeaponDefs.get_def("sawed_off")["spread_deg"]) > float(WeaponDefs.get_def("shotgun")["spread_deg"])
		and int(WeaponDefs.get_def("sawed_off")["pellets"]) < int(WeaponDefs.get_def("shotgun")["pellets"]),
		"Die abgesägte Schrotflinte streut breiter und hat weniger Kugeln.")
	_check(float(WeaponDefs.get_def("minigun")["reload_time"]) > float(WeaponDefs.get_def("rifle")["reload_time"])
		and int(WeaponDefs.get_def("minigun")["magazine"]) > int(WeaponDefs.get_def("rifle")["magazine"]),
		"Die Minigun hat das größere Magazin und lädt länger nach.")


func _average(values: Array[float]) -> float:
	var sum: float = 0.0
	for value: float in values:
		sum += value
	return sum / float(maxi(values.size(), 1))


func _test_damage_helpers() -> void:
	_check(is_equal_approx(WeaponDefs.bullet_damage("pistol", false), 25.0), "Pistole: 25 Schaden.")
	_check(is_equal_approx(WeaponDefs.bullet_damage("pistol", true), 50.0), "Pistole Kopfschuss: 50 Schaden.")
	_check(is_equal_approx(WeaponDefs.bullet_damage("shotgun", false), 14.0), "Schrotkugel: 14 Schaden.")
	_check(is_equal_approx(WeaponDefs.bullet_damage("sniper", true), 480.0), "Scharfschützengewehr Kopfschuss: 480 Schaden.")
	_check(is_equal_approx(WeaponDefs.pierce_damage_factor(0), 1.0), "Erstes Ziel: voller Schaden.")
	_check(is_equal_approx(WeaponDefs.pierce_damage_factor(1), 0.85), "Zweites Ziel: 85 %.")
	_check(is_equal_approx(WeaponDefs.pierce_damage_factor(2), 0.7225), "Drittes Ziel: 72,25 %.")
	_check(is_equal_approx(WeaponDefs.pierce_damage_factor(5), pow(0.85, 5.0)), "Sechstes Ziel: 0,85 hoch 5.")
	_check(is_equal_approx(WeaponDefs.pierce_damage_factor(-1), 1.0), "Negative Zielnummer zählt als erstes Ziel.")
	_check(is_equal_approx(WeaponDefs.bullet_damage("smg", true, 1), 16.0 * 2.0 * 0.85), "MP, Kopfschuss, zweites Ziel.")
	_check(WeaponDefs.bullet_damage("unbekannt", false) == 0.0, "Unbekannte Waffe macht keinen Schaden.")


func _test_fire_and_cooldown() -> void:
	var pistol: WeaponState = WeaponState.new("pistol")
	_check(pistol.weapon_id == "pistol" and pistol.mag == 10, "Neue Pistole: 10 im Magazin.")
	_check(pistol.get("reserve") == null, "Der Zustand kennt keinen Vorrat mehr.")
	_check(pistol.can_fire(), "Neue Waffe ist schussbereit.")
	_check(pistol.fire(), "Erster Schuss fällt.")
	_check(pistol.mag == 9, "Ein Schuss kostet eine Kugel.")
	_check(not pistol.can_fire() and not pistol.fire(), "Direkt danach sperrt die Schussfolge.")
	_check(pistol.mag == 9, "Ein gesperrter Schuss kostet nichts.")
	pistol.tick(0.1)
	_check(not pistol.can_fire(), "Nach 0,1 s ist die Pistole (0,2 s) noch gesperrt.")
	pistol.tick(0.11)
	_check(pistol.can_fire(), "Nach 0,21 s ist sie wieder schussbereit.")
	_check(pistol.fire() and pistol.mag == 8, "Zweiter Schuss fällt.")
	_check(not pistol.tick(1.0), "tick ohne Nachladen gibt false zurück.")
	_check(not pistol.tick(0.0) and not pistol.tick(-1.0), "tick mit delta <= 0 ändert nichts.")

	var shotgun: WeaponState = WeaponState.new("shotgun")
	_check(shotgun.mag == 6, "Neue Schrotflinte: 6 im Magazin.")
	_check(shotgun.fire() and shotgun.mag == 5, "Ein Schrotschuss kostet eine Patrone, nicht 8.")
	shotgun.tick(0.79)
	_check(not shotgun.can_fire(), "Schrotflinte ist nach 0,79 s noch gesperrt.")
	shotgun.tick(0.02)
	_check(shotgun.can_fire(), "Schrotflinte ist nach 0,81 s schussbereit.")
	# Jede Waffe beginnt mit vollem Magazin.
	for id: String in WeaponDefs.ORDER:
		var state: WeaponState = WeaponState.new(id)
		_check(state.mag == int(WeaponDefs.get_def(id)["magazine"]) and state.magazine_size() == state.mag and state.can_fire(),
			"%s beginnt mit vollem Magazin und ist schussbereit." % id)


func _test_reload() -> void:
	var pistol: WeaponState = WeaponState.new("pistol")
	for i: int in 10:
		_check(pistol.fire(), "Schuss %d von 10 fällt." % (i + 1))
		pistol.tick(0.25)
	_check(pistol.mag == 0, "Magazin ist nach 10 Schüssen leer.")
	_check(not pistol.can_fire() and not pistol.fire(), "Mit leerem Magazin kein Schuss.")
	_check(pistol.needs_reload(), "Leeres Magazin verlangt Nachladen.")
	_check(is_equal_approx(pistol.reload_duration(), 1.2), "Pistole lädt 1,2 s.")
	_check(pistol.start_reload(), "Nachladen beginnt.")
	_check(pistol.is_reloading and is_equal_approx(pistol.reload_left, 1.2), "Nachladen läuft mit 1,2 s Restzeit.")
	_check(not pistol.can_fire(), "Beim Nachladen kein Schuss.")
	_check(not pistol.start_reload(), "Kein zweites Nachladen während des ersten.")
	_check(not pistol.needs_reload(), "Während des Nachladens verlangt die Waffe kein weiteres.")
	_check(not pistol.tick(1.19), "Nach 1,19 s ist das Nachladen noch nicht fertig.")
	_check(pistol.is_reloading and pistol.mag == 0, "Magazin bleibt bis zum Ende leer.")
	_check(pistol.tick(0.02), "tick meldet das fertige Nachladen mit true.")
	_check(not pistol.is_reloading and pistol.mag == 10, "Danach ist das Magazin voll.")
	_check(pistol.can_fire(), "Nach dem Nachladen schussbereit.")
	_check(not pistol.tick(0.5), "Das fertige Nachladen wird nur einmal gemeldet.")
	# Teilweise leeres Magazin: Nachladen füllt es ganz.
	var shotgun: WeaponState = WeaponState.new("shotgun")
	shotgun.fire()
	shotgun.tick(1.0)
	shotgun.fire()
	shotgun.tick(1.0)
	_check(shotgun.mag == 4, "Nach 2 Schüssen 4 im Magazin.")
	_check(shotgun.start_reload(), "Nachladen mit teilweise leerem Magazin beginnt.")
	_check(shotgun.tick(2.3), "Nach 2,3 s ist die Schrotflinte geladen.")
	_check(shotgun.mag == 6, "Das Magazin ist wieder voll, war %d." % shotgun.mag)
	# Verstärker verkürzen das Nachladen über reload_factor.
	var smg: WeaponState = WeaponState.new("smg")
	smg.mag = 0
	smg.reload_factor = 0.5
	_check(is_equal_approx(smg.reload_duration(), 0.9), "reload_factor 0,5 halbiert die Nachladezeit der MP (0,9 s).")
	_check(smg.start_reload() and is_equal_approx(smg.reload_left, 0.9), "Das Nachladen läuft mit der verkürzten Zeit.")
	_check(not smg.tick(0.85) and smg.tick(0.1) and smg.mag == 30, "Nach 0,9 s ist die MP geladen.")


## Unendliche Munition: Nachladen geht beliebig oft, das Magazin wird jedes Mal voll.
func _test_reload_always_possible() -> void:
	for id: String in WeaponDefs.ORDER:
		var state: WeaponState = WeaponState.new(id)
		var size: int = state.magazine_size()
		var rounds_ok: bool = true
		for round_index: int in 25:
			state.mag = 0
			if not state.needs_reload() or not state.start_reload():
				rounds_ok = false
				break
			if not state.tick(state.reload_duration() + 0.01) or state.mag != size:
				rounds_ok = false
				break
		_check(rounds_ok, "%s lädt 25 Mal hintereinander ein volles Magazin nach." % id)
	# Der Raketenwerfer: ein Schuss, dann nachladen, dann wieder ein Schuss.
	var launcher: WeaponState = WeaponState.new("rocket_launcher")
	_check(launcher.fire() and launcher.mag == 0 and launcher.needs_reload(), "Nach der einen Rakete ist das Rohr leer.")
	launcher.start_reload()
	_check(launcher.tick(2.5) and launcher.mag == 1 and launcher.can_fire(), "Nach dem Nachladen steckt wieder eine Rakete im Rohr.")


func _test_reload_rules() -> void:
	var pistol: WeaponState = WeaponState.new("pistol")
	_check(not pistol.can_reload() and not pistol.start_reload(), "Mit vollem Magazin kein Nachladen.")
	_check(not pistol.needs_reload(), "Volles Magazin verlangt kein Nachladen.")
	pistol.fire()
	_check(pistol.can_reload() and not pistol.needs_reload(), "Nach einem Schuss ist Nachladen möglich, aber nicht nötig.")
	pistol.start_reload()
	pistol.tick(0.5)
	pistol.cancel_reload()
	_check(not pistol.is_reloading and pistol.mag == 9, "Abgebrochenes Nachladen füllt nichts auf.")
	_check(not pistol.tick(2.0) and pistol.mag == 9, "Nach dem Abbruch läuft kein Nachladen weiter.")
	_check(pistol.can_fire(), "Nach dem Abbruch kann wieder geschossen werden.")
	_check(pistol.start_reload() and is_equal_approx(pistol.reload_left, 1.2), "Neues Nachladen beginnt wieder bei der vollen Dauer.")


func _test_refill() -> void:
	var smg: WeaponState = WeaponState.new("smg")
	smg.mag = 2
	smg.start_reload()
	smg.refill()
	_check(smg.mag == 30 and not smg.is_reloading, "refill: volles Magazin, kein Nachladen, war %d." % smg.mag)
	_check(not smg.tick(5.0) and smg.mag == 30, "Nach refill läuft kein Nachladen weiter.")
	var pistol: WeaponState = WeaponState.new("pistol")
	pistol.mag = 1
	pistol.refill()
	_check(pistol.mag == 10, "refill der Pistole: volles Magazin.")


## Dauerfeuer trifft die Schussrate bei jeder Bildrate (der Rest der Schussfolge wird angerechnet).
func _test_fire_rate_over_time() -> void:
	_check_rate("smg", 60, 10.0, 120)
	_check_rate("smg", 144, 10.0, 120)
	_check_rate("smg", 30, 10.0, 120)
	# Unter 12 Bildern je Sekunde ist ein Bild länger als die Schussfolge der MP: Dann fallen
	# mehrere Schüsse in einem Bild, die Rate stimmt trotzdem. Erwartet ist die genaue Zahl:
	# Der erste Schuss fällt im ersten Bild (nach 1/fps s), danach alle 1/Schussrate s einer.
	_check_rate("smg", 10, 10.0, _exact_shots("smg", 10, 10.0))
	_check_rate("smg", 7, 10.0, _exact_shots("smg", 7, 10.0))
	_check_rate("smg", 4, 10.0, _exact_shots("smg", 4, 10.0))
	_check_rate("smg", 3, 10.0, _exact_shots("smg", 3, 10.0))
	_check_rate("pistol", 4, 10.0, _exact_shots("pistol", 4, 10.0))
	_check(_exact_shots("smg", 60, 10.0) == 120 and _exact_shots("smg", 10, 10.0) == 119 and _exact_shots("smg", 3, 10.0) == 117,
		"Die Rechnung der erwarteten Schüsse stimmt (120 / 119 / 117).")
	_check_rate("pistol", 60, 10.0, 50)
	_check_rate("shotgun", 60, 8.0, 10)
	# Die neuen Waffen: Minigun mit 20 Schuss je Sekunde auch bei 15 und 10 Bildern je Sekunde.
	_check_rate("minigun", 60, 10.0, 200)
	_check_rate("minigun", 15, 10.0, _exact_shots("minigun", 15, 10.0))
	_check_rate("minigun", 10, 10.0, _exact_shots("minigun", 10, 10.0))
	_check_rate("rifle", 60, 10.0, 90)
	_check_rate("revolver", 60, 10.0, 20)
	_check_rate("sawed_off", 60, 10.0, 20)
	_check_rate("sniper", 60, 10.0, 8)
	_check_rate("rocket_launcher", 60, 10.0, 10)
	# Wer wartet, spart keinen Schnellschuss an.
	var smg: WeaponState = WeaponState.new("smg")
	smg.fire()
	for i: int in 120:
		smg.tick(1.0 / 60.0)
	_check(smg.cooldown_left == 0.0, "Nach langer Pause ist die Schussfolge genau 0, war %s." % smg.cooldown_left)
	smg.fire()
	_check(is_equal_approx(smg.cooldown_left, 1.0 / 12.0), "Der Schuss nach der Pause sperrt die volle Zeit.")
	# Ein langer Ruckler wird kein Feuerstoß: höchstens Balance.FIRE_MAX_SHOTS_PER_FRAME Schüsse
	# in dem einen Bild, danach sperrt die Schussfolge wieder.
	smg.tick(5.0)
	var hitch_shots: int = 0
	while hitch_shots < 100 and smg.fire():
		hitch_shots += 1
	_check(hitch_shots >= 1 and hitch_shots <= Balance.FIRE_MAX_SHOTS_PER_FRAME,
		"Nach einem Ruckler von 5 s fallen höchstens %d Schüsse in einem Bild, waren %d." % [Balance.FIRE_MAX_SHOTS_PER_FRAME, hitch_shots])
	_check(smg.cooldown_left > 0.0, "Nach dem Ruckler sperrt die Schussfolge wieder, war %s." % smg.cooldown_left)
	# Der Rest verfällt, wenn im Bild nach dem Ruckler nicht geschossen wird.
	smg.tick(5.0)
	smg.tick(1.0 / 60.0)
	_check(smg.cooldown_left == 0.0, "Ohne Schuss verfällt der Rest eines Rucklers, war %s." % smg.cooldown_left)


## Schüsse, die bei Dauerfeuer in seconds genau fallen: der erste im ersten Bild, dann einer je
## Schussfolge bis zum Ende.
func _exact_shots(weapon_id: String, fps: int, seconds: float) -> int:
	var fire_rate: float = float(WeaponDefs.get_def(weapon_id)["fire_rate"])
	return floori((seconds - 1.0 / float(fps)) * fire_rate + 0.0001) + 1


## Hält seconds lang den Abzug bei fps Bildern je Sekunde und vergleicht die Zahl der Schüsse.
func _check_rate(weapon_id: String, fps: int, seconds: float, expected_shots: int) -> void:
	var state: WeaponState = WeaponState.new(weapon_id)
	var delta: float = 1.0 / float(fps)
	var shots: int = 0
	var most_per_frame: int = 0
	for i: int in roundi(seconds * fps):
		state.tick(delta)
		state.mag = state.magazine_size()
		# Wie der WeaponController: schießen, solange die Schussfolge es in diesem Bild erlaubt.
		var in_frame: int = 0
		while in_frame < Balance.FIRE_MAX_SHOTS_PER_FRAME and state.fire():
			in_frame += 1
		shots += in_frame
		most_per_frame = maxi(most_per_frame, in_frame)
	var fire_rate: float = float(state.get_def()["fire_rate"])
	_check(most_per_frame <= ceili(fire_rate / float(fps)), "%s bei %d Bildern/s: höchstens %d Schüsse je Bild, waren %d." % [weapon_id, fps, ceili(fire_rate / float(fps)), most_per_frame])
	_check(absi(shots - expected_shots) <= 1, "%s bei %d Bildern/s: %d Schüsse in %s s erwartet, waren %d." % [weapon_id, fps, expected_shots, seconds, shots])


func _test_unknown_weapon() -> void:
	_check(not WeaponDefs.has("unbekannt") and WeaponDefs.get_def("unbekannt").is_empty(), "Unbekannte Waffe hat keine Daten.")
	_check(WeaponDefs.display_name("unbekannt") == "unbekannt", "Unbekannte Waffe: Name ist die ID.")
	_check(WeaponDefs.fire_interval("unbekannt") == 0.0 and not WeaponDefs.is_explosive("unbekannt"), "Unbekannte Waffe: keine Schussfolge, keine Explosion.")
	var state: WeaponState = WeaponState.new("unbekannt")
	_check(state.mag == 0 and state.magazine_size() == 0, "Unbekannte Waffe hat keine Munition.")
	_check(not state.can_fire() and not state.fire(), "Unbekannte Waffe schießt nicht.")
	_check(not state.can_reload() and not state.start_reload() and not state.needs_reload(), "Unbekannte Waffe lädt nicht nach.")
	_check(not state.tick(1.0), "tick einer unbekannten Waffe ist harmlos.")
	var default_state: WeaponState = WeaponState.new()
	_check(default_state.weapon_id == "pistol", "Ohne Angabe entsteht die Startwaffe.")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
