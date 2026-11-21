extends SceneTree
## Tests für das Freischalten zwischen den Läufen (Abschnitt 22.5): UnlockDefs (Startvorrat,
## Pakete), ProgressState (Konto, Kaufen, Speichern), Kisten mit Fortschritt und der Ablauf in
## Game (Punkte fürs Konto, Gutschrift am Laufende, buy_pack, Laden und Speichern).

const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UnlockDefs := preload("res://scripts/core/unlock_defs.gd")
const ProgressState := preload("res://scripts/core/progress_state.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")

## Abschrift der Tabelle aus Abschnitt 22.5: Paket -> [Name, Preis, Inhalt].
const EXPECTED_PACKS: Dictionary = {
	"camera_team": ["Kamerateam", 2000, ["cam_tele", "cam_lens", "cam_battery", "cam_zoom"]],
	"rapid_fire": ["Schnellfeuer", 2000, ["machine_pistol", "nail_gun", "fire_rate", "big_mag"]],
	"first_aid": ["Erste Hilfe", 2500, ["shield", "kill_heal", "snack", "dash"]],
	"poison_kitchen": ["Giftküche", 3000, ["poison", "frost", "flamethrower", "sawed_off"]],
	"precision": ["Präzision", 3500, ["sniper", "crossbow", "scope", "crit"]],
	"big_bang": ["Knallbonbon", 4000, ["grenade_launcher", "punchline", "mine", "extra_shot"]],
	"control_room": ["Regieraum-Technik", 4500, ["cam_flash", "cam_slow", "cam_second", "cam_uplink"]],
	"sustained_fire": ["Dauerfeuer", 5000, ["rifle", "lmg", "burst_pistol", "opener"]],
	"high_voltage": ["Hochspannung", 6000, ["tesla", "jammer", "ricochet", "disco_ball"]],
	"grand_finale": ["Großes Finale", 8000, ["minigun", "rocket_launcher", "auto_shotgun", "beam"]],
	"special_broadcast": ["Sondersendung", 10000, ["replay", "revive", "thorns", "cam_director"]],
}
const EXPECTED_START: Array[String] = [
	"pistol", "revolver", "smg", "shotgun", "chain_lightning", "pierce", "burn", "lifesteal", "max_hp",
	"corpse_explosion", "reload_shockwave", "drone", "speed", "luck", "spotlight", "speed_loader", "piggy_bank",
	"bag_tiny", "bag_small", "bag_medium", "bag_large",
]
const TEMP_FILE: String = "user://test_progress_tmp.cfg"

var _failures: int = 0
var _checks: int = 0
var _game: Node
var _events: Node
## Empfangene Signale: [name, argumente].
var _log: Array[Array] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum und ihr _ready ist gelaufen.
	await process_frame
	_game = root.get_node("Game")
	_events = root.get_node("Events")
	_events.connect("bank_changed", func(bank: int, gained: int) -> void: _log.append(["bank_changed", [bank, gained]]))
	_events.connect("pack_unlocked", func(pack_id: String) -> void: _log.append(["pack_unlocked", [pack_id]]))
	_events.connect("game_over", func(stats: Dictionary) -> void: _log.append(["game_over", [stats]]))

	_test_unlock_defs()
	_test_progress_state()
	_test_save_format()
	_test_chest_offers()
	_test_game_headless()
	_test_game_bank()
	_test_game_buy_and_chests()
	_test_game_files()

	paused = false
	if DirAccess.dir_exists_absolute("user://") and FileAccess.file_exists(TEMP_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_FILE))
	if _failures == 0:
		print("Alle Fortschritt-Tests bestanden (%d Prüfungen)." % _checks)
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


func _count(signal_name: String) -> int:
	var total: int = 0
	for entry: Array in _log:
		if str(entry[0]) == signal_name:
			total += 1
	return total


func _last(signal_name: String) -> Array:
	for i: int in range(_log.size() - 1, -1, -1):
		if str(_log[i][0]) == signal_name:
			return _log[i][1]
	return []


func _progress() -> ProgressState:
	return _game.get("progress") as ProgressState


func _grid(width: int, height: int) -> BackpackState:
	var cells: Array[Vector2i] = []
	for y: int in height:
		for x: int in width:
			cells.append(Vector2i(x, y))
	var backpack: BackpackState = BackpackState.new()
	backpack.setup(cells)
	return backpack


# --- UnlockDefs -----------------------------------------------------------------------

func _test_unlock_defs() -> void:
	_check(UnlockDefs.START == EXPECTED_START and UnlockDefs.start_items() == EXPECTED_START, "Der Startvorrat ist genau der aus Abschnitt 22.5 (17 Gegenstände und 3 Rucksack-Teile).")
	_check(UnlockDefs.PACK_ORDER.size() == 11 and UnlockDefs.PACKS.size() == 11 and UnlockDefs.all_pack_ids() == UnlockDefs.PACK_ORDER, "Es gibt 11 Pakete in fester Reihenfolge.")
	var last_price: int = 0
	for pack_id: String in UnlockDefs.PACK_ORDER:
		_check(EXPECTED_PACKS.has(pack_id), "Paket %s steht in der Tabelle." % pack_id)
		if not EXPECTED_PACKS.has(pack_id):
			continue
		var want: Array = EXPECTED_PACKS[pack_id]
		_check(UnlockDefs.has_pack(pack_id) and UnlockDefs.pack_name(pack_id) == str(want[0]), "Paket %s heißt %s, war %s." % [pack_id, str(want[0]), UnlockDefs.pack_name(pack_id)])
		_check(UnlockDefs.pack_price(pack_id) == int(want[1]), "Paket %s kostet %d, waren %d." % [pack_id, int(want[1]), UnlockDefs.pack_price(pack_id)])
		var items: Array[String] = UnlockDefs.pack_items(pack_id)
		_check(items.size() == 4 and str(items) == str(want[2]), "Paket %s enthält %s, war %s." % [pack_id, str(want[2]), str(items)])
		_check(UnlockDefs.pack_price(pack_id) >= last_price, "Die Pakete stehen nach Preis geordnet (%s)." % pack_id)
		last_price = UnlockDefs.pack_price(pack_id)
		for item_id: String in items:
			_check(ItemDefs.has(item_id), "%s aus dem Paket %s ist ein Gegenstand." % [item_id, pack_id])
			_check(UnlockDefs.pack_of(item_id) == pack_id and not UnlockDefs.is_start_item(item_id), "%s gehört zum Paket %s und nicht zum Startvorrat." % [item_id, pack_id])
	for item_id: String in UnlockDefs.START:
		_check(ItemDefs.has(item_id) and UnlockDefs.is_start_item(item_id) and UnlockDefs.pack_of(item_id) == "", "%s aus dem Startvorrat ist ein Gegenstand und steht in keinem Paket." % item_id)
	# Jeder Gegenstand steht entweder im Startvorrat oder in genau einem Paket.
	var placed: int = 0
	for item_id: String in ItemDefs.ORDER:
		var homes: int = 1 if UnlockDefs.START.has(item_id) else 0
		for pack_id: String in UnlockDefs.PACK_ORDER:
			homes += (UnlockDefs.PACKS[pack_id]["items"] as Array).count(item_id)
		_check(homes == 1, "%s steht genau einmal im Startvorrat oder in einem Paket, war %d-mal." % [item_id, homes])
		placed += homes
		if ItemDefs.is_bag(item_id):
			_check(UnlockDefs.is_start_item(item_id), "Rucksack-Teil %s ist von Anfang an frei." % item_id)
	_check(placed == ItemDefs.ORDER.size() and UnlockDefs.START.size() + 11 * 4 == ItemDefs.ORDER.size(), "Startvorrat und Pakete decken alle %d Gegenstände ab." % ItemDefs.ORDER.size())
	_check(not UnlockDefs.has_pack("gibt_es_nicht") and UnlockDefs.pack_price("gibt_es_nicht") == 0 and UnlockDefs.pack_items("gibt_es_nicht").is_empty() and UnlockDefs.pack_name("gibt_es_nicht") == "gibt_es_nicht", "Unbekannte Pakete sind harmlos.")
	_check(UnlockDefs.pack_of("gibt_es_nicht") == "" and not UnlockDefs.is_start_item("gibt_es_nicht"), "Unbekannte Gegenstände stehen nirgends.")


# --- ProgressState --------------------------------------------------------------------

func _test_progress_state() -> void:
	var progress: ProgressState = ProgressState.new()
	_check(progress.bank == 0 and progress.packs.is_empty() and not progress.unlock_all and progress.best_wave == 0 and progress.runs == 0, "Ein neuer Fortschritt ist leer.")
	# Freigeschaltet: Startvorrat ja, Paketinhalt nein.
	for item_id: String in UnlockDefs.START:
		_check(progress.is_item_unlocked(item_id), "%s ist von Anfang an frei." % item_id)
	for pack_id: String in UnlockDefs.PACK_ORDER:
		for item_id: String in UnlockDefs.pack_items(pack_id):
			_check(not progress.is_item_unlocked(item_id), "%s ist ohne das Paket %s gesperrt." % [item_id, pack_id])
	_check(progress.open_packs() == UnlockDefs.PACK_ORDER, "Am Anfang sind alle Pakete offen.")
	# Konto.
	_check(progress.add_bank(1500) == 1500 and progress.bank == 1500, "add_bank schreibt gut und nennt den Betrag.")
	_check(progress.add_bank(0) == 0 and progress.add_bank(-200) == 0 and progress.bank == 1500, "Nichts oder Negatives ändert das Konto nicht.")
	# Kaufen.
	_check(not progress.can_buy("camera_team") and not progress.buy("camera_team"), "Mit 1500 Punkten ist das Kamerateam (2000) zu teuer.")
	_check(progress.bank == 1500 and progress.packs.is_empty(), "Ein Fehlkauf ändert nichts.")
	progress.add_bank(2500)
	_check(progress.can_buy("camera_team") and progress.can_buy("first_aid") and progress.can_buy("big_bang"), "Mit 4000 Punkten gehen Pakete bis 4000.")
	_check(not progress.can_buy("control_room"), "Die Regieraum-Technik (4500) ist noch zu teuer.")
	_check(progress.buy("first_aid") and progress.bank == 1500 and progress.has_pack("first_aid"), "Kaufen zieht den Preis ab: Erste Hilfe für 2500.")
	_check(progress.packs == (["first_aid"] as Array[String]), "Das Paket steht in der Liste.")
	for item_id: String in UnlockDefs.pack_items("first_aid"):
		_check(progress.is_item_unlocked(item_id), "%s ist nach dem Kauf frei." % item_id)
	_check(not progress.is_item_unlocked("cam_tele") and not progress.is_item_unlocked("replay"), "Andere Pakete bleiben gesperrt.")
	progress.add_bank(10000)
	_check(not progress.can_buy("first_aid") and not progress.buy("first_aid") and progress.bank == 11500, "Ein Paket lässt sich nicht zweimal kaufen.")
	_check(not progress.can_buy("gibt_es_nicht") and not progress.buy("gibt_es_nicht"), "Unbekannte Pakete lassen sich nicht kaufen.")
	# Beliebige Reihenfolge.
	_check(progress.buy("special_broadcast") and progress.bank == 1500 and progress.is_item_unlocked("replay"), "Die Sondersendung (10000) geht auch vor den billigeren Paketen.")
	_check(progress.packs == (["first_aid", "special_broadcast"] as Array[String]) and progress.open_packs().size() == 9 and not progress.open_packs().has("first_aid"), "open_packs nennt die neun übrigen.")
	# Genau der Preis reicht.
	var exact: ProgressState = ProgressState.new()
	exact.add_bank(2000)
	_check(exact.buy("rapid_fire") and exact.bank == 0, "Genau der Preis auf dem Konto reicht.")
	# Läufe.
	progress.record_run(7)
	progress.record_run(4)
	_check(progress.runs == 2 and progress.best_wave == 7, "record_run zählt Läufe und merkt die beste Welle.")
	# unlock_all: alles frei, auch ohne Paket.
	var cheat: ProgressState = ProgressState.new()
	cheat.unlock_all = true
	for item_id: String in ItemDefs.ORDER:
		_check(cheat.is_item_unlocked(item_id), "Mit unlock_all ist %s frei." % item_id)
	_check(not cheat.has_pack("camera_team") and not cheat.can_buy("camera_team"), "unlock_all kauft nichts und füllt kein Konto.")
	# Was in keinem Paket steht, ist frei.
	_check(progress.is_item_unlocked("gibt_es_nicht"), "Ein Gegenstand ohne Paket gilt als frei.")


func _test_save_format() -> void:
	var progress: ProgressState = ProgressState.new()
	progress.add_bank(9000)
	progress.buy("precision")
	progress.buy("camera_team")
	progress.record_run(12)
	progress.unlock_all = true
	var data: Dictionary = progress.to_dict()
	_check(data == {"bank": 3500, "packs": ["precision", "camera_team"], "best_wave": 12, "runs": 1}, "to_dict nennt Konto, Pakete, beste Welle und Läufe, war %s." % str(data))
	_check(not data.has("unlock_all"), "unlock_all wird nicht gespeichert.")
	var copy: ProgressState = ProgressState.new()
	copy.from_dict(data)
	_check(copy.bank == 3500 and copy.packs == (["precision", "camera_team"] as Array[String]) and copy.best_wave == 12 and copy.runs == 1, "from_dict stellt den Zustand wieder her.")
	_check(not copy.unlock_all and copy.is_item_unlocked("sniper") and not copy.is_item_unlocked("rifle"), "Geladen gilt wieder nur, was gekauft ist.")
	_check(copy.to_dict() == data, "Hin und zurück ergibt dasselbe.")
	# Die gespeicherte Liste ist eine Kopie.
	(data["packs"] as Array).append("big_bang")
	_check(progress.packs.size() == 2, "to_dict gibt eine Kopie der Paketliste.")
	# Kaputte Daten: unbekannte und doppelte Pakete entfallen, Unsinn wird zu 0.
	var broken: ProgressState = ProgressState.new()
	broken.unlock_all = true
	broken.from_dict({"bank": -50, "packs": ["precision", "gibt_es_nicht", "precision", 7], "best_wave": "9", "runs": "viele"})
	_check(broken.bank == 0 and broken.best_wave == 9 and broken.runs == 0, "Negatives und Unsinn werden zu 0, Zahlen als Text gelten.")
	_check(broken.packs == (["precision"] as Array[String]), "Unbekannte und doppelte Pakete entfallen, war %s." % str(broken.packs))
	_check(broken.unlock_all, "from_dict lässt unlock_all, wie es ist.")
	broken.from_dict({})
	_check(broken.bank == 0 and broken.packs.is_empty() and broken.best_wave == 0 and broken.runs == 0, "Leere Daten ergeben einen leeren Fortschritt.")
	broken.from_dict({"packs": "precision", "bank": 12.0})
	_check(broken.packs.is_empty() and broken.bank == 12, "Ein falscher Typ für die Pakete ergibt eine leere Liste.")


# --- Kisten ---------------------------------------------------------------------------

func _test_chest_offers() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var backpack: BackpackState = _grid(4, 3)
	# Ohne gekaufte Pakete: nur der Startvorrat.
	var fresh: ProgressState = ProgressState.new()
	var seen: Dictionary = {}
	for round_index: int in 600:
		var offers: Array[Dictionary] = ChestRoller.build_item_offers(rng, backpack, round_index % 3, false, [] as Array[String], fresh)
		_check(offers.size() == 3, "Eine Kiste bietet immer 3 an.")
		for offer: Dictionary in offers:
			if str(offer.get("kind", "")) != ChestRoller.KIND_ITEM:
				_check(false, "Der Startvorrat reicht für 3 Angebote: keine Trostpreise.")
				continue
			var id: String = str(offer["id"])
			seen[id] = true
			if not UnlockDefs.is_start_item(id):
				_check(false, "Ohne Pakete kommt nur der Startvorrat, war %s." % id)
	_check(seen.size() == UnlockDefs.START.size(), "Über viele Kisten kommt der ganze Startvorrat vor, waren %d von %d." % [seen.size(), UnlockDefs.START.size()])
	# Mit einem Paket: sein Inhalt kommt dazu, sonst nichts.
	var some: ProgressState = ProgressState.new()
	some.add_bank(20000)
	some.buy("special_broadcast")
	some.buy("camera_team")
	seen.clear()
	var replay_outside_gold: bool = false
	for round_index: int in 1500:
		var rarity: int = round_index % 3
		for offer: Dictionary in ChestRoller.build_item_offers(rng, backpack, rarity, false, [] as Array[String], some):
			var id: String = str(offer.get("id", ""))
			seen[id] = true
			if not some.is_item_unlocked(id):
				_check(false, "%s ist nicht freigeschaltet und darf nicht in der Kiste liegen." % id)
			if id == "replay" and rarity != Balance.RARITY_GOLD:
				replay_outside_gold = true
	for item_id: String in UnlockDefs.pack_items("special_broadcast") + UnlockDefs.pack_items("camera_team"):
		_check(seen.has(item_id), "%s aus einem gekauften Paket kommt in Kisten vor." % item_id)
	_check(seen.size() == UnlockDefs.START.size() + 8, "Angeboten werden Startvorrat und die 8 Gegenstände der zwei Pakete, waren %d." % seen.size())
	_check(not replay_outside_gold, "Die Wiederholung gibt es auch freigeschaltet nur in Gold-Kisten.")
	# Rucksack-Teile gehen immer, auch mit Garantie.
	for _i: int in 50:
		_check(ChestRoller.offers_have_bag(ChestRoller.build_item_offers(rng, backpack, 0, true, [] as Array[String], fresh)), "Mit Garantie liegt auch ohne Pakete ein Rucksack-Teil in der Kiste.")
	# unlock_all und kein Fortschritt (null): alles.
	var all: ProgressState = ProgressState.new()
	all.unlock_all = true
	for progress: ProgressState in [all, null]:
		seen.clear()
		for round_index: int in 1500:
			for offer: Dictionary in ChestRoller.build_item_offers(rng, backpack, round_index % 3, false, [] as Array[String], progress):
				seen[str(offer.get("id", ""))] = true
		_check(seen.size() == ItemDefs.ORDER.size(), "Mit unlock_all oder ohne Fortschritt kommt jeder Gegenstand vor, waren %d von %d." % [seen.size(), ItemDefs.ORDER.size()])
	# Gleicher Seed, gleicher Fortschritt: gleiches Angebot.
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 31
	rng_b.seed = 31
	_check(str(ChestRoller.build_item_offers(rng_a, backpack, 1, false, [] as Array[String], some)) == str(ChestRoller.build_item_offers(rng_b, backpack, 1, false, [] as Array[String], some)), "Gleicher Seed ergibt dasselbe Angebot.")


# --- Game -----------------------------------------------------------------------------

func _test_game_headless() -> void:
	_check(DisplayServer.get_name() == "headless", "Der Test läuft ohne Bildschirm.")
	_check(_progress() != null and _progress().unlock_all, "Ohne Bildschirm gilt alles als freigeschaltet.")
	_check(not bool(_game.get("progress_file_enabled")), "Ohne Bildschirm wird der Fortschritt weder geladen noch gespeichert.")
	_check(_progress().bank == 0 and _progress().packs.is_empty() and _progress().runs == 0, "Der Fortschritt beginnt im Test leer (nichts geladen).")
	_check(str(_game.get("PROGRESS_PATH")) == "user://progress.cfg", "Der Fortschritt liegt in user://progress.cfg.")


func _test_game_bank() -> void:
	_game.set("character_id", "technician")
	_game.set("auto_pack", false)
	_game.call("start_run", 3)
	_log.clear()
	_check(int(_game.get("points")) == 500 and int(_game.get("bank_points_earned")) == 0, "Startpunkte des Kandidaten zählen nicht fürs Konto.")
	_check(_progress().runs == 0 and _progress().bank == 0, "Der erste start_run rechnet nichts ab.")
	_game.set("character_id", "")
	_game.call("start_run", 3)
	_check(_count("bank_changed") == 1 and _last("bank_changed") == [0, 0] and _progress().runs == 1, "Ein verlassener Lauf wird beim nächsten start_run abgerechnet (hier mit 0 Punkten).")
	_log.clear()
	# Verdienen: Treffer, Kills, Wellen-Prämien laufen alle über add_points.
	_game.call("add_points", 700)
	_events.emit_signal("zombie_damaged", null, 10.0, {"source": "bullet"})
	_events.emit_signal("zombie_killed", null, {"source": "bullet", "headshot": true})
	_check(int(_game.get("bank_points_earned")) == 700 + 10 + 90, "Treffer, Kills und add_points zählen fürs Konto, waren %d." % int(_game.get("bank_points_earned")))
	# Ausgaben werden nicht abgezogen.
	_check(bool(_game.call("spend_points", 500)) and int(_game.get("bank_points_earned")) == 800, "Ausgaben im Lauf mindern die Gutschrift nicht.")
	# Verkaufserlöse zählen nicht.
	var backpack: BackpackState = _game.get("backpack") as BackpackState
	var uid: int = backpack.add_item("luck", 3)
	_check(int(_game.call("sell_item", uid)) == 400 and int(_game.get("points")) == 700, "Der Verkauf gibt 400 Punkte für den Lauf.")
	_check(int(_game.get("bank_points_earned")) == 800 and int(_game.get("total_points_earned")) == 1200, "Verkaufserlöse zählen nicht fürs Konto, wohl aber für die Statistik.")
	# Trostpreis-Punkte aus einer Kiste zählen (kein Verkauf).
	_game.call("open_chest", 0)
	(_game.get("current_offers") as Array)[0] = {"kind": "points", "amount": 500}
	_game.call("choose_offer", 0)
	_check(int(_game.get("bank_points_earned")) == 1300, "Punkte aus einem Trostpreis zählen fürs Konto.")
	# Der Punkte-Faktor zählt mit: Es zählt, was wirklich gutgeschrieben wurde.
	var pig: int = backpack.add_item("piggy_bank", 5)
	backpack.auto_place(pig)
	_game.call("sync_build")
	_game.call("add_points", 100)
	_check(int(_game.get("bank_points_earned")) == 1300 + 118, "Mit Sparschwein zählen die erhöhten Punkte, waren %d." % int(_game.get("bank_points_earned")))
	_check(_progress().bank == 0 and _count("bank_changed") == 0, "Während des Laufs ändert sich das Konto nicht.")
	var pending: Dictionary = _game.call("get_stats")
	_check(int(pending["bank_gained"]) == 1418 and int(pending["bank"]) == 0, "Vor dem Ende nennt die Statistik, was der Lauf bringen wird.")
	# Laufende: Gutschrift genau einmal, vor game_over.
	_events.emit_signal("wave_started", 6, 30)
	_events.emit_signal("player_died")
	_check(_progress().bank == 1418 and _progress().runs == 2 and _progress().best_wave == 6, "Am Laufende kommen die Punkte aufs Konto, der Lauf zählt.")
	_check(_count("bank_changed") == 1 and _last("bank_changed") == [1418, 1418], "bank_changed nennt Konto und Gutschrift, war %s." % str(_last("bank_changed")))
	_check(int(_game.get("last_bank_gain")) == 1418, "last_bank_gain merkt die Gutschrift.")
	_check(_log.size() == 2 and str(_log[0][0]) == "bank_changed" and str(_log[1][0]) == "game_over", "bank_changed kommt vor game_over.")
	var stats: Dictionary = _last("game_over")[0]
	_check(int(stats["bank_gained"]) == 1418 and int(stats["bank"]) == 1418, "game_over nennt Gutschrift und Kontostand.")
	_game.call("end_run")
	_events.emit_signal("player_died")
	_check(_progress().bank == 1418 and _count("bank_changed") == 1 and _progress().runs == 2, "Ein zweites Ende schreibt nichts mehr gut.")
	# Neustart nach Game Over: keine zweite Gutschrift.
	_game.call("restart_run")
	_check(_progress().bank == 1418 and _count("bank_changed") == 1 and _progress().runs == 2, "restart_run nach Game Over rechnet nicht noch einmal ab.")
	_check(int(_game.get("bank_points_earned")) == 0, "Der neue Lauf beginnt mit 0 verdienten Punkten.")
	# Neustart mitten im Lauf (aus der Pause): Der abgebrochene Lauf wird abgerechnet.
	_game.call("add_points", 250)
	_events.emit_signal("wave_started", 2, 14)
	_game.call("set_paused", true)
	_game.call("restart_run")
	_check(_progress().bank == 1668 and _last("bank_changed") == [1668, 250] and _progress().runs == 3, "Ein Neustart aus der Pause rechnet den Lauf ab.")
	_check(_progress().best_wave == 6, "Die beste Welle bleibt die höhere.")
	# Ein Lauf ohne Punkte: Gutschrift 0, bank_changed kommt trotzdem (für die Anzeige).
	_log.clear()
	_game.call("end_run")
	_check(_last("bank_changed") == [1668, 0] and _progress().runs == 4, "Ein Lauf ohne Punkte bringt 0, zählt aber als Lauf.")
	_game.call("start_run", 4)
	_check(_count("bank_changed") == 1, "start_run nach Game Over rechnet nicht noch einmal ab.")


func _test_game_buy_and_chests() -> void:
	var progress: ProgressState = _progress()
	progress.unlock_all = false
	_log.clear()
	var bank_before: int = progress.bank
	_check(bank_before == 1668, "Ausgangslage: 1668 Punkte auf dem Konto.")
	_check(not bool(_game.call("buy_pack", "camera_team")) and _log.is_empty() and progress.bank == bank_before, "Ohne genug Punkte scheitert buy_pack ohne Signal.")
	_check(not bool(_game.call("buy_pack", "gibt_es_nicht")), "Unbekannte Pakete kauft buy_pack nicht.")
	progress.add_bank(4000)
	_check(bool(_game.call("buy_pack", "camera_team")), "Mit genug Punkten klappt der Kauf.")
	_check(progress.bank == 3668 and progress.has_pack("camera_team"), "Der Preis ist abgezogen, das Paket gehört dem Spieler.")
	_check(_log.size() == 2 and _log[0] == ["pack_unlocked", ["camera_team"]] and _log[1] == ["bank_changed", [3668, -2000]], "pack_unlocked und bank_changed(Konto, -Preis) kamen, war %s." % str(_log))
	_check(not bool(_game.call("buy_pack", "camera_team")) and _log.size() == 2, "Ein zweiter Kauf desselben Pakets scheitert.")
	# Kisten im Lauf bieten nur Freigeschaltetes an.
	_game.set("character_id", "")
	_game.set("auto_pack", true)
	_game.call("start_run", 9)
	var seen: Dictionary = {}
	for round_index: int in 300:
		_game.call("open_chest", round_index % 3)
		for offer: Variant in _game.get("current_offers") as Array:
			var id: String = str((offer as Dictionary).get("id", ""))
			if id.is_empty():
				continue
			seen[id] = true
			if not progress.is_item_unlocked(id):
				_check(false, "Die Kiste bietet %s an, obwohl es nicht freigeschaltet ist." % id)
		# Einen Trostpreis wählen, damit der Rucksack leer bleibt und die Kisten voll.
		(_game.get("current_offers") as Array)[0] = {"kind": "heal", "amount": 1}
		_game.call("choose_offer", 0)
	_check(seen.has("cam_tele") and seen.has("cam_lens") and seen.has("drone"), "Der Inhalt des gekauften Pakets und der Startvorrat kommen vor.")
	_check(not seen.has("sniper") and not seen.has("replay") and not seen.has("minigun"), "Gesperrte Gegenstände kommen nicht vor.")
	# grant_item fragt nicht nach dem Freischalten, Kandidaten auch nicht.
	var granted: int = int(_game.call("grant_item", "minigun", 1))
	_check(granted > 0 and str((_game.get("backpack") as BackpackState).item(granted).get("id", "")) == "minigun", "grant_item gibt auch einen gesperrten Gegenstand.")
	_game.set("auto_pack", false)
	progress.unlock_all = true


func _test_game_files() -> void:
	var progress: ProgressState = _progress()
	var expected: Dictionary = progress.to_dict()
	_check(bool(_game.call("save_progress_to", TEMP_FILE)) and FileAccess.file_exists(TEMP_FILE), "save_progress_to schreibt die Datei.")
	var file: ConfigFile = ConfigFile.new()
	_check(file.load(TEMP_FILE) == OK and file.has_section("progress"), "Die Datei hat den Abschnitt progress.")
	_check(int(file.get_value("progress", "bank", -1)) == progress.bank and int(file.get_value("progress", "runs", -1)) == progress.runs and int(file.get_value("progress", "best_wave", -1)) == progress.best_wave, "Konto, Läufe und beste Welle stehen in der Datei.")
	_check(str(file.get_value("progress", "packs", [])) == str(progress.packs), "Die gekauften Pakete stehen in der Datei.")
	# Zustand verändern und wieder laden.
	progress.bank = 5
	progress.packs.clear()
	progress.best_wave = 0
	progress.runs = 0
	_check(bool(_game.call("load_progress_from", TEMP_FILE)), "load_progress_from liest die Datei.")
	_check(_progress().to_dict() == expected, "Geladen ist wieder der gespeicherte Zustand, war %s." % str(_progress().to_dict()))
	_check(_progress().unlock_all, "Laden ändert unlock_all nicht.")
	# Eine fehlende Datei ändert nichts.
	_check(not bool(_game.call("load_progress_from", "user://gibt_es_nicht_progress.cfg")) and _progress().to_dict() == expected, "Eine fehlende Datei lässt den Fortschritt, wie er ist.")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
