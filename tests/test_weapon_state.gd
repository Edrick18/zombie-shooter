extends SceneTree
## Tests für WeaponDefs und WeaponState: Waffentabelle mit 19 Waffen (neun alte, zehn neue aus
## Abschnitt 22.2 mit Schussart, Salve, Durchschlag und eingebautem Blitz), Schussfolge, Magazin,
## unendliche Munition (Nachladen ist immer möglich), Schussrate bei verschiedenen Bildraten,
## dazu die Rechenhelfer und Faktoren der Gegenstände je Waffe (Abschnitt 19.1): Überlänge
## (Magazingröße), Schnelldurchlauf (Schussrate), Teleprompter (Streuung, Kopftreffer), Zugabe
## und Glücksrad (Schadensfaktor).

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
	_test_item_helpers()
	_test_magazine_bonus()
	_test_fire_rate_factor()
	_test_unknown_weapon()
	_test_new_weapons()
	_test_burst()

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
	_check(WeaponDefs.WEAPONS.size() == 19, "Es gibt genau 19 Waffen (9 alte, 10 neue).")
	_check(WeaponDefs.ORDER.slice(0, 9) == order and WeaponDefs.all_ids() == WeaponDefs.ORDER, "Die neun alten Waffen stehen vorn: erst Einhand, dann Zweihand.")
	for id: String in order:
		_check(WeaponDefs.mode(id) == WeaponDefs.MODE_BULLET and WeaponDefs.burst(id) == 1 and WeaponDefs.pierce(id) == 0 and WeaponDefs.arc_jumps(id) == 0,
			"Alte Waffe %s: Kugel, keine Salve, kein Durchschlag, kein Blitz." % id)
		_check(is_equal_approx(WeaponDefs.reach(id), Balance.WEAPON_RANGE), "Alte Waffe %s reicht 60 m." % id)
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
		# Der Granatwerfer macht den Großteil über die Explosion, die Armbrust über den Durchschlag.
		var least: float = 60.0 if id == "grenade_launcher" else 120.0
		_check(dps >= least - 0.01 and dps <= 260.0 + 0.01, "%s liegt zwischen %s und 260 Schaden je Sekunde, war %s." % [id, least, dps])
		var def: Dictionary = WeaponDefs.get_def(id)
		_check(int(def["magazine"]) >= 1 and float(def["reload_time"]) > 0.0 and float(def["fire_rate"]) > 0.0 and int(def["pellets"]) >= 1,
			"%s hat Magazin, Nachladezeit, Schussrate und Kugeln." % id)
		_check((int(def["price"]) > 0) == (id != WeaponDefs.START_WEAPON), "%s: Nur die Startwaffe kostet nichts." % id)
		if ItemDefs.hands(id) == 1:
			one_handed.append(dps)
		else:
			two_handed.append(dps)
	_check(one_handed.size() == 9 and two_handed.size() == 10, "Neun Einhand- und zehn Zweihand-Waffen, waren %d und %d." % [one_handed.size(), two_handed.size()])
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


## Rechenhelfer in WeaponDefs für die Gegenstände je Waffe.
func _test_item_helpers() -> void:
	_check(is_equal_approx(WeaponDefs.EXTRA_SHOT_SPREAD_DEG, 1.5), "Die Zusatzkugel fliegt um höchstens 1,5 Grad versetzt.")
	_check(is_equal_approx(Balance.CRIT_MULTIPLIER, 2.0) and is_equal_approx(Balance.SCOPE_SPREAD_FACTOR, 0.5),
		"Kritischer Treffer mal 2, Teleprompter halbiert die Streuung.")
	# Magazingröße: Grundgröße mal (1 + Zusatz), aufgerundet.
	_check(WeaponDefs.magazine_size("pistol") == 10 and WeaponDefs.magazine_size("pistol", 0.0) == 10, "Pistole ohne Zusatz: 10.")
	_check(WeaponDefs.magazine_size("pistol", 0.3) == 13, "Pistole +30 %%: 13, war %d." % WeaponDefs.magazine_size("pistol", 0.3))
	_check(WeaponDefs.magazine_size("pistol", 0.45) == 15, "Pistole +45 %%: 14,5 wird 15, war %d." % WeaponDefs.magazine_size("pistol", 0.45))
	_check(WeaponDefs.magazine_size("revolver", 0.3) == 8, "Revolver +30 %%: 7,8 wird 8, war %d." % WeaponDefs.magazine_size("revolver", 0.3))
	_check(WeaponDefs.magazine_size("sawed_off", 0.3) == 3, "Abgesägte +30 %%: 2,6 wird 3, war %d." % WeaponDefs.magazine_size("sawed_off", 0.3))
	_check(WeaponDefs.magazine_size("rocket_launcher", 0.3) == 2, "Raketenwerfer +30 %%: 1,3 wird 2, war %d." % WeaponDefs.magazine_size("rocket_launcher", 0.3))
	_check(WeaponDefs.magazine_size("smg", 1.0) == 60 and WeaponDefs.magazine_size("minigun", 0.3) == 156, "MP +100 %: 60, Minigun +30 %: 156.")
	_check(WeaponDefs.magazine_size("pistol", -0.5) == 10, "Ein negativer Zusatz verkleinert das Magazin nicht.")
	_check(WeaponDefs.magazine_size("unbekannt", 0.3) == 0, "Unbekannte Waffe: Magazin 0.")
	# Jede Waffe mit jedem Zusatz, auch mit mehreren Exemplaren zusammen (die Zusätze addieren
	# sich). Die erwartete Größe ist mit ganzen Zahlen gerechnet, also ohne Rundungsfehler.
	var bonuses: Array = [[0.3, 30], [0.45, 45], [0.6, 60], [0.8, 80], [1.0, 100], [0.3 + 0.3, 60],
		[0.3 + 0.45, 75], [0.45 + 0.45, 90], [0.8 + 0.3, 110], [1.0 + 1.0 + 0.3, 230], [0.3 + 0.3 + 0.3, 90]]
	for id: String in WeaponDefs.ORDER:
		var base: int = int(WeaponDefs.get_def(id)["magazine"])
		for pair: Array in bonuses:
			@warning_ignore("integer_division")
			var expected: int = (base * (100 + int(pair[1])) + 99) / 100
			var got: int = WeaponDefs.magazine_size(id, float(pair[0]))
			_check(got == expected, "%s mit +%d %%: Magazin %d erwartet, war %d." % [id, int(pair[1]), expected, got])
	# Schussfolge mit Schnelldurchlauf.
	_check(is_equal_approx(WeaponDefs.fire_interval("smg", 0.2), 1.0 / 14.4), "MP 20 % schneller: 14,4 Schuss je Sekunde.")
	_check(is_equal_approx(WeaponDefs.fire_interval("pistol", 0.3), 0.2 / 1.3), "Pistole 30 % schneller: 0,2 s durch 1,3.")
	_check(is_equal_approx(WeaponDefs.fire_interval("pistol", 0.0), 0.2), "Ohne Zusatz bleibt die Schussfolge.")
	_check(WeaponDefs.fire_interval("unbekannt", 0.3) == 0.0, "Unbekannte Waffe: keine Schussfolge.")
	# Streuung mit Teleprompter.
	for id: String in WeaponDefs.ORDER:
		var spread: float = float(WeaponDefs.get_def(id)["spread_deg"])
		_check(is_equal_approx(WeaponDefs.spread_deg(id), spread) and is_equal_approx(WeaponDefs.spread_deg(id, false), spread),
			"%s: Streuung ohne Teleprompter wie in der Tabelle." % id)
		_check(is_equal_approx(WeaponDefs.spread_deg(id, true), spread * 0.5), "%s: Teleprompter halbiert die Streuung." % id)
	_check(WeaponDefs.spread_deg("sniper", true) == 0.0 and WeaponDefs.spread_deg("unbekannt", true) == 0.0,
		"Ohne Streuung bleibt es bei 0.")
	# Kopftreffer mit Teleprompter: zusätzlich mal (1 + Zusatz).
	_check(is_equal_approx(WeaponDefs.bullet_damage("pistol", true, 0, 0.25), 62.5), "Pistole Kopfschuss +25 %: 62,5.")
	_check(is_equal_approx(WeaponDefs.bullet_damage("pistol", false, 0, 0.25), 25.0), "Der Zusatz gilt nur für Kopftreffer.")
	_check(is_equal_approx(WeaponDefs.bullet_damage("sniper", true, 0, 0.75), 840.0), "Scharfschützengewehr Kopfschuss +75 %: 840.")
	_check(is_equal_approx(WeaponDefs.bullet_damage("smg", true, 2, 0.5), 16.0 * 2.0 * 1.5 * 0.7225), "Kopftreffer-Zusatz und Durchschlag zusammen.")
	_check(is_equal_approx(WeaponDefs.bullet_damage("pistol", true, 0, 0.0), 50.0) and is_equal_approx(WeaponDefs.bullet_damage("pistol", true, 0, -1.0), 50.0),
		"Ohne Zusatz (oder mit einem negativen) bleibt der Kopftreffer bei mal 2.")
	# Zugabe und Glücksrad.
	_check(WeaponDefs.bonus_damage_factor(1.0, false) == 1.0, "Normale Kugel ohne kritischen Treffer: genau Faktor 1.")
	_check(is_equal_approx(WeaponDefs.bonus_damage_factor(0.5, false), 0.5), "Zusatzkugel mit 50 %: Faktor 0,5.")
	_check(is_equal_approx(WeaponDefs.bonus_damage_factor(1.0, true), 2.0), "Kritischer Treffer: Faktor 2.")
	_check(is_equal_approx(WeaponDefs.bonus_damage_factor(0.7, true), 1.4), "Kritische Zusatzkugel mit 70 %: Faktor 1,4.")
	_check(WeaponDefs.bonus_damage_factor(-1.0, true) == 0.0, "Ein negativer Anteil macht keinen Schaden.")


## Überlänge im Zustand: magazine_bonus vergrößert das Magazin, füllt es aber nicht.
func _test_magazine_bonus() -> void:
	var pistol: WeaponState = WeaponState.new("pistol")
	_check(pistol.magazine_bonus == 0.0 and pistol.fire_rate_factor == 1.0, "Neue Waffe: kein Zusatz, Schussrate normal.")
	pistol.set_magazine_bonus(0.3)
	_check(pistol.magazine_size() == 13 and is_equal_approx(pistol.magazine_bonus, 0.3), "+30 %: Magazingröße 13.")
	_check(pistol.mag == 10, "Das größere Magazin füllt sich nicht von selbst, waren %d." % pistol.mag)
	_check(pistol.can_reload() and not pistol.needs_reload(), "Es lässt sich nachladen, nötig ist es nicht.")
	_check(pistol.start_reload() and pistol.tick(1.3) and pistol.mag == 13, "Nachladen füllt bis zur neuen Größe (13), waren %d." % pistol.mag)
	_check(not pistol.can_reload(), "Mit 13 von 13 ist das Magazin voll.")
	pistol.mag = 2
	pistol.refill()
	_check(pistol.mag == 13, "refill füllt bis zur neuen Größe.")
	pistol.set_magazine_bonus(1.0)
	_check(pistol.magazine_size() == 20 and pistol.mag == 13, "+100 %: Größe 20, die 13 Kugeln bleiben.")
	pistol.set_magazine_bonus(0.0)
	_check(pistol.magazine_size() == 10 and pistol.mag == 10, "Ohne Zusatz: Größe 10, der Rest über 10 verfällt (waren %d)." % pistol.mag)
	pistol.mag = 4
	pistol.set_magazine_bonus(0.3)
	_check(pistol.mag == 4, "Ein angebrochenes Magazin bleibt beim Vergrößern, wie es ist.")
	pistol.set_magazine_bonus(0.0)
	_check(pistol.mag == 4, "Ein angebrochenes Magazin bleibt beim Verkleinern, wenn es noch passt.")
	pistol.set_magazine_bonus(-2.0)
	_check(pistol.magazine_bonus == 0.0 and pistol.magazine_size() == 10, "Ein negativer Zusatz zählt als 0.")
	# Der Zusatz ändert sich mitten im Nachladen: Am Ende gilt die neue Größe.
	pistol.mag = 2
	pistol.start_reload()
	pistol.tick(0.5)
	pistol.set_magazine_bonus(0.6)
	_check(pistol.is_reloading and pistol.mag == 2, "Der neue Zusatz bricht das Nachladen nicht ab.")
	_check(pistol.tick(1.0) and pistol.mag == 16, "Das laufende Nachladen füllt bis zur neuen Größe (16), waren %d." % pistol.mag)
	# Verkleinern mitten im Nachladen: Das Magazin ist danach voll, nie voller.
	pistol.mag = 15
	pistol.start_reload()
	pistol.set_magazine_bonus(0.0)
	_check(pistol.mag == 10 and pistol.tick(2.0) and pistol.mag == 10, "Nach dem Verkleinern endet das Nachladen bei 10.")
	# Der Raketenwerfer bekommt eine zweite Rakete.
	var launcher: WeaponState = WeaponState.new("rocket_launcher")
	launcher.set_magazine_bonus(0.3)
	launcher.refill()
	_check(launcher.mag == 2 and launcher.fire() and launcher.mag == 1 and not launcher.needs_reload(), "Mit Überlänge hat der Raketenwerfer zwei Raketen.")
	launcher.tick(1.1)
	_check(launcher.fire() and launcher.mag == 0 and launcher.needs_reload(), "Nach der zweiten Rakete ist das Rohr leer.")
	# Jede Waffe: neuer Zustand mit Zusatz, nach refill voll und schussbereit.
	for id: String in WeaponDefs.ORDER:
		var state: WeaponState = WeaponState.new(id)
		state.set_magazine_bonus(0.8)
		state.refill()
		_check(state.mag == WeaponDefs.magazine_size(id, 0.8) and state.mag > int(WeaponDefs.get_def(id)["magazine"]) and state.can_fire(),
			"%s mit +80 %%: volles größeres Magazin." % id)


## Schnelldurchlauf im Zustand: fire_rate_factor teilt die Schussfolge, bei jeder Bildrate genau.
func _test_fire_rate_factor() -> void:
	var smg: WeaponState = WeaponState.new("smg")
	_check(is_equal_approx(smg.fire_interval(), 1.0 / 12.0), "MP ohne Faktor: ein Zwölftel s.")
	smg.fire_rate_factor = 1.2
	_check(is_equal_approx(smg.fire_interval(), 1.0 / 14.4), "MP mit Faktor 1,2: 14,4 Schuss je Sekunde.")
	smg.fire()
	_check(is_equal_approx(smg.cooldown_left, 1.0 / 14.4), "Der Schuss sperrt die kürzere Zeit.")
	smg.tick(0.06)
	_check(not smg.can_fire(), "Nach 0,06 s ist die schnellere MP (0,069 s) noch gesperrt.")
	smg.tick(0.012)
	_check(smg.can_fire(), "Nach 0,072 s schießt sie wieder (ohne Faktor wären es 0,083 s).")
	var pistol: WeaponState = WeaponState.new("pistol")
	pistol.fire_rate_factor = 1.3
	pistol.fire()
	pistol.tick(0.16)
	_check(pistol.can_fire(), "Pistole mit Faktor 1,3: nach 0,16 s wieder schussbereit.")
	# Ein unsinniger Faktor sperrt die Waffe nicht für immer.
	var odd: WeaponState = WeaponState.new("pistol")
	odd.fire_rate_factor = 0.0
	_check(odd.fire_interval() > 0.0 and is_finite(odd.fire_interval()), "Faktor 0 ergibt eine endliche Schussfolge.")
	# Dauerfeuer trifft die schnellere Rate bei jeder Bildrate.
	_check_rate("smg", 60, 10.0, 144, 1.2)
	_check_rate("smg", 144, 10.0, 144, 1.2)
	_check_rate("smg", 30, 10.0, 144, 1.2)
	_check_rate("smg", 10, 10.0, _exact_shots("smg", 10, 10.0, 1.2), 1.2)
	_check_rate("smg", 6, 10.0, _exact_shots("smg", 6, 10.0, 1.2), 1.2)
	_check_rate("minigun", 60, 10.0, 260, 1.3)
	_check_rate("minigun", 20, 10.0, _exact_shots("minigun", 20, 10.0, 1.3), 1.3)
	_check_rate("minigun", 15, 10.0, _exact_shots("minigun", 15, 10.0, 1.3), 1.3)
	_check_rate("rifle", 60, 10.0, 99, 1.1)
	_check_rate("pistol", 60, 10.0, 65, 1.3)
	_check_rate("shotgun", 60, 8.0, 12, 1.2)
	# Fünf legendäre Exemplare zusammen: +150 %.
	_check_rate("smg", 60, 10.0, 300, 2.5)
	_check_rate("smg", 20, 10.0, _exact_shots("smg", 20, 10.0, 2.5), 2.5)
	_check(_exact_shots("smg", 60, 10.0, 1.2) == 144 and _exact_shots("minigun", 60, 10.0, 1.3) == 260,
		"Die Rechnung der erwarteten Schüsse stimmt auch mit Faktor (144 / 260).")


## Schüsse, die bei Dauerfeuer in seconds genau fallen: der erste im ersten Bild, dann einer je
## Schussfolge bis zum Ende. rate_factor ist der Faktor auf die Schussrate (Schnelldurchlauf).
func _exact_shots(weapon_id: String, fps: int, seconds: float, rate_factor: float = 1.0) -> int:
	var fire_rate: float = float(WeaponDefs.get_def(weapon_id)["fire_rate"]) * rate_factor
	return floori((seconds - 1.0 / float(fps)) * fire_rate + 0.0001) + 1


## Hält seconds lang den Abzug bei fps Bildern je Sekunde und vergleicht die Zahl der Schüsse.
## rate_factor kommt als fire_rate_factor in den Zustand.
func _check_rate(weapon_id: String, fps: int, seconds: float, expected_shots: int, rate_factor: float = 1.0) -> void:
	var state: WeaponState = WeaponState.new(weapon_id)
	state.fire_rate_factor = rate_factor
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
	var fire_rate: float = float(state.get_def()["fire_rate"]) * rate_factor
	_check(most_per_frame <= ceili(fire_rate / float(fps)), "%s (Faktor %s) bei %d Bildern/s: höchstens %d Schüsse je Bild, waren %d." % [weapon_id, rate_factor, fps, ceili(fire_rate / float(fps)), most_per_frame])
	_check(absi(shots - expected_shots) <= 1, "%s (Faktor %s) bei %d Bildern/s: %d Schüsse in %s s erwartet, waren %d." % [weapon_id, rate_factor, fps, expected_shots, seconds, shots])


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


## Abschnitt 22.2: die zehn neuen Waffen, jede Zahl gegen die Tabelle.
func _test_new_weapons() -> void:
	# id: [Name, Hände, Schaden, Schuss/s, Magazin, Nachladen, Streuung, Kugeln, Dauerfeuer]
	var expected: Dictionary = {
		"burst_pistol": ["Dreierpack", 1, 22.0, 2.2, 15, 1.4, 1.0, 1, false],
		"nail_gun": ["Bühnenbau", 1, 9.0, 14.0, 40, 1.6, 2.2, 1, true],
		"machine_pistol": ["Werbeblock", 1, 11.0, 18.0, 20, 1.2, 3.0, 1, true],
		"crossbow": ["Zielgerade", 1, 110.0, 1.1, 1, 1.3, 0.0, 1, false],
		"grenade_launcher": ["Knalleffekt", 1, 60.0, 1.0, 4, 2.8, 0.5, 1, false],
		"flamethrower": ["Heiße Phase", 2, 9.0, 15.0, 100, 3.0, 0.0, 1, true],
		"beam": ["Rotlicht", 2, 9.0, 20.0, 80, 2.6, 0.0, 1, true],
		"tesla": ["Kurzschluss", 2, 45.0, 3.0, 12, 2.4, 0.6, 1, false],
		"lmg": ["Marathonsendung", 2, 20.0, 11.0, 100, 4.5, 2.0, 1, true],
		"auto_shotgun": ["Zuschauerfrage", 2, 11.0, 3.0, 8, 2.6, 6.5, 7, true],
	}
	var new_order: Array[String] = ["burst_pistol", "nail_gun", "machine_pistol", "crossbow", "grenade_launcher", "flamethrower", "beam", "tesla", "lmg", "auto_shotgun"]
	_check(WeaponDefs.ORDER.slice(9) == new_order, "Die zehn neuen Waffen stehen hinter den alten: erst Einhand, dann Zweihand.")
	var names: Dictionary = {}
	for id: String in WeaponDefs.ORDER:
		names[WeaponDefs.display_name(id)] = true
	_check(names.size() == 19, "Alle 19 Waffen haben verschiedene Namen.")
	for id: String in expected:
		var want: Array = expected[id]
		_check(WeaponDefs.has(id), "Waffe %s fehlt." % id)
		var def: Dictionary = WeaponDefs.get_def(id)
		_check(WeaponDefs.display_name(id) == str(want[0]) and ItemDefs.display_name(id) == str(want[0]), "%s heißt %s." % [id, str(want[0])])
		_check(ItemDefs.is_weapon(id) and ItemDefs.hands(id) == int(want[1]), "%s braucht %d Hand oder Hände." % [id, int(want[1])])
		_check(is_equal_approx(float(def["damage"]), float(want[2])), "%s: Schaden %s, war %s." % [id, want[2], def["damage"]])
		_check(is_equal_approx(float(def["fire_rate"]), float(want[3])), "%s: Schussrate %s, war %s." % [id, want[3], def["fire_rate"]])
		_check(int(def["magazine"]) == int(want[4]) and WeaponDefs.magazine_size(id) == int(want[4]), "%s: Magazin %d, war %s." % [id, int(want[4]), def["magazine"]])
		_check(is_equal_approx(float(def["reload_time"]), float(want[5])), "%s: Nachladen %s s, war %s." % [id, want[5], def["reload_time"]])
		_check(is_equal_approx(float(def["spread_deg"]), float(want[6])), "%s: Streuung %s, war %s." % [id, want[6], def["spread_deg"]])
		_check(int(def["pellets"]) == int(want[7]), "%s: %d Kugeln je Schuss, waren %s." % [id, int(want[7]), def["pellets"]])
		_check(bool(def["automatic"]) == bool(want[8]) and WeaponDefs.is_automatic(id) == bool(want[8]), "%s: Dauerfeuer %s." % [id, str(want[8])])
		# Die alten Schlüssel sind alle da: Die Waffensteuerung liest sie ohne Rückfrage.
		for key: String in ["name", "damage", "fire_rate", "magazine", "reload_time", "spread_deg", "pellets", "automatic", "price", "explosion_radius", "explosion_damage"]:
			_check(def.has(key), "%s hat den alten Schlüssel %s." % [id, key])
		_check(int(def["price"]) > 0, "%s hat einen Preis (für einen späteren Händler)." % id)
		var state: WeaponState = WeaponState.new(id)
		_check(state.mag == int(want[4]) and state.can_fire() and state.fire() and state.mag == int(want[4]) - 1, "%s lässt sich als WeaponState anlegen und schießt." % id)
	# Schussarten.
	_check(WeaponDefs.mode("grenade_launcher") == WeaponDefs.MODE_GRENADE and WeaponDefs.mode("flamethrower") == WeaponDefs.MODE_FLAME and WeaponDefs.mode("beam") == WeaponDefs.MODE_BEAM, "Granate, Flamme und Strahl haben ihre Schussart.")
	for id: String in ["burst_pistol", "nail_gun", "machine_pistol", "crossbow", "tesla", "lmg", "auto_shotgun"]:
		_check(WeaponDefs.mode(id) == WeaponDefs.MODE_BULLET, "%s schießt Kugeln." % id)
	_check(WeaponDefs.MODE_BULLET == "bullet" and WeaponDefs.MODE_GRENADE == "grenade" and WeaponDefs.MODE_FLAME == "flame" and WeaponDefs.MODE_BEAM == "beam", "Die Schussarten heißen bullet, grenade, flame, beam.")
	# Salve.
	_check(WeaponDefs.burst("burst_pistol") == 3 and is_equal_approx(WeaponDefs.burst_interval("burst_pistol"), 0.07), "Dreierpack: Salve aus 3 Schüssen mit 0,07 s Abstand.")
	_check(WeaponDefs.burst("pistol") == 1 and WeaponDefs.burst_interval("pistol") == 0.0 and WeaponDefs.burst("lmg") == 1, "Alle anderen Waffen haben keine Salve.")
	_check(is_equal_approx(WeaponDefs.dps("burst_pistol"), 22.0 * 3.0 * 2.2), "Der Schaden je Sekunde zählt alle Schüsse der Salve (145,2).")
	# Durchschlag.
	_check(WeaponDefs.pierce("nail_gun") == 1 and WeaponDefs.pierce("crossbow") == 3, "Nagelpistole durchschlägt 1, Armbrust 3 weitere Zombies.")
	_check(WeaponDefs.pierce("beam") == WeaponDefs.PIERCE_ALL and WeaponDefs.PIERCE_ALL >= 100, "Der Strahl geht durch alle Zombies.")
	_check(WeaponDefs.pierce("lmg") == 0 and WeaponDefs.pierce("sniper") == 0, "Andere Waffen durchschlagen von sich aus nichts.")
	# Eingebauter Blitz.
	_check(WeaponDefs.arc_jumps("tesla") == 3 and is_equal_approx(WeaponDefs.arc_factor("tesla"), 0.6) and is_equal_approx(WeaponDefs.arc_radius("tesla"), 5.0), "Kurzschluss: 3 Sprünge mit 60 % im Umkreis von 5 m.")
	_check(WeaponDefs.arc_jumps("rifle") == 0 and WeaponDefs.arc_factor("rifle") == 0.0, "Andere Waffen haben keinen eingebauten Blitz.")
	# Flamme.
	_check(is_equal_approx(WeaponDefs.reach("flamethrower"), 7.0) and WeaponDefs.cone_deg("flamethrower") > 0.0, "Heiße Phase: Kegel bis 7 m.")
	_check(is_equal_approx(WeaponDefs.burn_dps("flamethrower"), 8.0) and is_equal_approx(WeaponDefs.burn_time("flamethrower"), 3.0), "Heiße Phase: Brand 8 je Sekunde für 3 s.")
	_check(is_equal_approx(WeaponDefs.reach("beam"), Balance.WEAPON_RANGE) and WeaponDefs.cone_deg("beam") == 0.0 and WeaponDefs.burn_dps("beam") == 0.0, "Andere Waffen reichen 60 m, ohne Kegel und Brand.")
	# Granate.
	_check(WeaponDefs.is_explosive("grenade_launcher") and is_equal_approx(float(WeaponDefs.get_def("grenade_launcher")["explosion_radius"]), 3.0) and is_equal_approx(float(WeaponDefs.get_def("grenade_launcher")["explosion_damage"]), 110.0), "Knalleffekt: Explosion 110 im Radius 3 m.")
	_check(WeaponDefs.projectile_speed("grenade_launcher") > 0.0 and WeaponDefs.projectile_gravity("grenade_launcher") > 0.0, "Die Granate hat Tempo und Schwerkraft.")
	_check(WeaponDefs.projectile_speed("rocket_launcher") == 0.0, "Die Rakete bleibt ein Strahl ohne Flugbahn.")
	for id: String in new_order:
		if id != "grenade_launcher":
			_check(not WeaponDefs.is_explosive(id), "%s explodiert nicht." % id)
	# Schussfolgen.
	_check(is_equal_approx(WeaponDefs.fire_interval("beam"), 0.05) and is_equal_approx(WeaponDefs.fire_interval("flamethrower"), 1.0 / 15.0), "Strahl 20 Treffer je Sekunde, Flamme 15 Stöße je Sekunde.")
	_check(is_equal_approx(WeaponDefs.fire_interval("burst_pistol"), 1.0 / 2.2), "Dreierpack: 2,2 Salven je Sekunde.")
	# Unbekannte Waffe.
	_check(WeaponDefs.mode("unbekannt") == "" and WeaponDefs.burst("unbekannt") == 0 and WeaponDefs.pierce("unbekannt") == 0 and WeaponDefs.reach("unbekannt") == 0.0 and not WeaponDefs.is_automatic("unbekannt"), "Unbekannte Waffe: keine Schussart, keine Salve, nichts.")
	# Jede neue Waffe hat einen Kamera-Rückstoß.
	for id: String in WeaponDefs.ORDER:
		_check(Balance.CAMERA_RECOIL_KICK_DEG.has(id), "%s hat einen Kamera-Rückstoß in Balance." % id)


## Salve (Dreierpack): Ein Abzug gibt drei Schüsse, jeder kostet eine Kugel.
func _test_burst() -> void:
	var state: WeaponState = WeaponState.new("burst_pistol")
	_check(state.burst_size() == 3 and is_equal_approx(state.burst_interval(), 0.07) and not state.is_bursting(), "Dreierpack: Salve aus 3, 0,07 s Abstand.")
	_check(not state.burst_shot_due() and not state.fire_burst_shot(), "Ohne Abzug ist kein Salvenschuss fällig.")
	_check(state.fire() and state.mag == 14, "Der Abzug gibt den ersten Schuss.")
	_check(state.is_bursting() and state.burst_left == 2 and not state.burst_shot_due(), "Zwei Schüsse stehen noch aus, der nächste ist nicht sofort fällig.")
	_check(not state.can_fire(), "Während der Salve ist der Abzug gesperrt (Schussfolge).")
	state.tick(0.03)
	_check(not state.burst_shot_due(), "Nach 0,03 s ist der zweite Schuss noch nicht fällig.")
	state.tick(0.04)
	_check(state.burst_shot_due() and state.fire_burst_shot() and state.mag == 13 and state.burst_left == 1, "Nach 0,07 s fällt der zweite Schuss.")
	_check(not state.burst_shot_due(), "Der dritte ist erst nach weiteren 0,07 s fällig.")
	state.tick(0.07)
	_check(state.fire_burst_shot() and state.mag == 12 and not state.is_bursting(), "Der dritte Schuss beendet die Salve.")
	_check(not state.fire_burst_shot() and state.mag == 12, "Danach folgt kein vierter.")
	_check(not state.can_fire(), "Die nächste Salve wartet auf die Schussfolge.")
	state.tick(1.0 / 2.2 - 0.14 + 0.001)
	_check(state.can_fire(), "Nach 1 / 2,2 s seit dem Abzug ist die nächste Salve möglich.")
	# Ein langer Zeitschritt: Beide Folgeschüsse sind im selben Schritt fällig.
	state = WeaponState.new("burst_pistol")
	state.fire()
	state.tick(0.2)
	var in_step: int = 0
	while state.burst_shot_due() and in_step < 10:
		state.fire_burst_shot()
		in_step += 1
	_check(in_step == 2 and state.mag == 12, "Nach einem langen Schritt fallen beide Folgeschüsse nacheinander (waren %d)." % in_step)
	# Das Magazin begrenzt die Salve.
	state = WeaponState.new("burst_pistol")
	state.mag = 2
	_check(state.fire() and state.mag == 1 and state.burst_left == 1, "Mit zwei Kugeln hat die Salve nur einen Folgeschuss.")
	state.tick(0.07)
	_check(state.fire_burst_shot() and state.mag == 0 and not state.is_bursting() and not state.burst_shot_due(), "Mit der letzten Kugel endet die Salve, das Magazin wird nie negativ.")
	state = WeaponState.new("burst_pistol")
	state.mag = 1
	_check(state.fire() and state.mag == 0 and not state.is_bursting(), "Mit einer Kugel gibt es nur den einen Schuss.")
	# Nachladen bricht die Salve ab.
	state = WeaponState.new("burst_pistol")
	state.fire()
	_check(state.start_reload() and not state.is_bursting() and not state.burst_shot_due(), "Nachladen bricht eine laufende Salve ab.")
	state.tick(10.0)
	_check(state.mag == state.magazine_size() and not state.burst_shot_due(), "Nach dem Nachladen ist das Magazin voll und keine Salve offen.")
	# Schnelldurchlauf verkürzt auch den Abstand in der Salve.
	state.fire_rate_factor = 2.0
	_check(is_equal_approx(state.burst_interval(), 0.035), "Mit doppelter Schussrate halbiert sich der Abstand in der Salve.")
	state.fire_rate_factor = 1.0
	state.cancel_burst()
	# Über Zeit: 2,2 Salven je Sekunde mit je 3 Schüssen, bei jeder Bildrate.
	for fps: int in [30, 60, 144]:
		var timed: WeaponState = WeaponState.new("burst_pistol")
		var shots: int = 0
		var salvos: int = 0
		var step: float = 1.0 / float(fps)
		for _frame: int in fps * 10:
			timed.tick(step)
			timed.mag = timed.magazine_size()
			while timed.burst_shot_due():
				timed.fire_burst_shot()
				shots += 1
			if timed.fire():
				shots += 1
				salvos += 1
		_check(absi(salvos - 22) <= 1, "Dreierpack bei %d Bildern/s: 22 Salven in 10 s, waren %d." % [fps, salvos])
		_check(absi(shots - salvos * 3) <= 2, "Dreierpack bei %d Bildern/s: je Salve 3 Schüsse (%d Schüsse in %d Salven)." % [fps, shots, salvos])
	# Waffen ohne Salve: nie ein Folgeschuss.
	var plain: WeaponState = WeaponState.new("pistol")
	_check(plain.burst_size() == 1 and plain.fire() and not plain.is_bursting(), "Die Dienstpistole hat keine Salve.")
	plain.tick(1.0)
	_check(not plain.burst_shot_due() and not plain.fire_burst_shot() and plain.mag == 9, "Ohne Salve folgt kein Schuss von selbst.")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
