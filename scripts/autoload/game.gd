extends Node
## Zustand eines Laufs (Autoload "Game"): Punkte, Welle, Kills, Upgrades, Kistenwahl, Pause.
## Dazu der Fortschritt über alle Läufe (Konto und freigeschaltete Pakete, Abschnitt 22.5).
## Kennt keine konkreten Level- oder UI-Knoten. Besitzer: Fundament.
##
## Ablauf: main.gd baut alle Module und ruft danach start_run(). Module richten sich bei
## Events.run_started ein. restart_run() lädt die Szene neu, main.gd startet dann den nächsten Lauf.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")
const ShaderKeep := preload("res://scripts/game/fx/shader_keep.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")
const CharacterDefs := preload("res://scripts/core/character_defs.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")
const UnlockDefs := preload("res://scripts/core/unlock_defs.gd")
const ProgressState := preload("res://scripts/core/progress_state.gd")

## Datei für den Fortschritt über alle Läufe (Abschnitt 22.5) und ihr Abschnitt.
const PROGRESS_PATH: String = "user://progress.cfg"
const PROGRESS_SECTION: String = "progress"

## PACKING: Der Rucksack ist offen (Spiel pausiert). Neue Werte nur hinten anhängen: Tests und
## Skripte ohne Zugriff auf den Typ benutzen die Zahlen.
enum State { MENU, PLAYING, CHOOSING, PAUSED, GAME_OVER, PACKING }

var state: State = State.MENU
var points: int = 0
## Aktuelle Welle, 0 vor dem Start. Wird bei Events.wave_started gesetzt.
var wave: int = 0
var kills: int = 0
var total_points_earned: int = 0
## Upgrades des Laufs. Wird bei start_run neu angelegt: nie zwischenspeichern, immer Game.upgrades lesen.
## Stufen, Synergien und Zusatzwerte werden aus dem Rucksack berechnet (sync_build).
var upgrades: UpgradeState = UpgradeState.new()
## Kandidat des Laufs (CharacterDefs), "" = keiner. Bleibt über Läufe erhalten. Vor start_run setzen.
var character_id: String = CharacterDefs.NONE
## Rucksack des Laufs. Wird bei start_run neu angelegt. Wer ihn ändert, ruft danach sync_build().
var backpack: BackpackState = BackpackState.new()
## true: Ein Gegenstand aus der Kiste wird sofort selbst eingeräumt (zusammengelegt, sonst an die
## erste passende Stelle, sonst bleibt er in der Ablage) und der Rucksack öffnet sich nicht. Für
## Tests und Messungen. Ein kaputtes Fundstück bleibt dabei in der Ablage (siehe broken_loot).
var auto_pack: bool = false
## Material des Laufs (Abschnitt 26): die zweite Währung, zum Reparieren kaputter Fundstücke. Nur
## lesen, ändern über add_materials, repair_item und scrap_item.
var materials: int = 0
## true: Gegenstände aus Kisten kommen kaputt in die Ablage (Rucksack-Teile nie). Ohne Bildschirm
## (Tests) false, damit die Fundstücke dort gleich benutzbar sind. Bleibt über Läufe erhalten.
var broken_loot: bool = false
## Zufall des Laufs. Module nehmen für Spielzufall diesen Generator (Tests werden so wiederholbar).
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Wird vom Spieler in _ready gesetzt, sonst null. Vor Zugriff is_instance_valid prüfen.
var player: Node3D = null
## Angebote der offenen Kiste (nur im State CHOOSING gefüllt), siehe ChestRoller.build_offers.
var current_offers: Array[Dictionary] = []
## Seltenheit der offenen Kiste (nur im State CHOOSING von Bedeutung).
var current_rarity: int = 0
## Upgrade-Stufen beim Öffnen des Rucksacks, für die Meldungen beim Schließen.
var _levels_at_open: Dictionary = {}
## Die Waffen in der Hand, von der linken zur rechten Hand (siehe BackpackState.loadout). Liegt
## keine Waffe im Rucksack, steht hier die Dienstpistole mit der uid 0. Wird in sync_build neu
## berechnet: Wer sie braucht (Waffensteuerung, HUD), liest sie bei build_changed neu.
var loadout: Array[Dictionary] = []
## Upgrades je Waffe (uid -> UpgradeState): die Stern-Gegenstände, die auf sie wirken.
var _weapon_upgrades: Dictionary = {}
## Die Kameras im Spiel (Abschnitt 22.1): je Exemplar ein Eintrag mit den fertigen Werten, also
## BackpackState.cameras() ("key", "uid", "copy", "id", "level", "mods") zusammen mit
## CameraDefs.stats ("damage", "interval", "range", "pierce", "slow", "slow_duration", "mark",
## "mark_duration", "second", "cone_deg", "damage_bonus", "rate_bonus", "range_bonus"). Wird in
## sync_build neu berechnet. Das Array wird nur ersetzt, wenn sich etwas geändert hat, dann kommt
## Events.cameras_changed. Nur lesen.
var cameras: Array[Dictionary] = []
## Fortschritt über alle Läufe: Konto, gekaufte Pakete, beste Welle (Abschnitt 22.5). Ohne
## Bildschirm (Tests) wird er nie geladen oder gespeichert und alles gilt als freigeschaltet.
var progress: ProgressState = ProgressState.new()
## false: Der Fortschritt wird weder geladen noch gespeichert (ohne Bildschirm immer).
var progress_file_enabled: bool = false
## Punkte, die in diesem Lauf verdient wurden und am Laufende aufs Konto kommen: alles außer den
## Erlösen aus dem Verkauf von Gegenständen. Ausgaben werden nicht abgezogen.
var bank_points_earned: int = 0
## Was der zuletzt beendete Lauf aufs Konto gebracht hat (für Game Over).
var last_bank_gain: int = 0
## Ist der laufende Lauf schon abgerechnet? true auch, solange noch kein Lauf begonnen hat.
var _run_settled: bool = true
## Kisten in Folge ohne Rucksack-Teil im Angebot (für die Garantie Balance.CHEST_BAG_PITY).
var _chests_without_bag: int = 0
## Gegenstände aus der letzten Kiste: Sie kommen in der nächsten seltener.
var _recent_offer_ids: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Jede Material-Art, die irgendwo im Spiel auftaucht, behält ihren Shader (kein Ruckler beim
	# nächsten Mal). Game lebt über alle Läufe, deshalb hängt die Verbindung hier.
	get_tree().node_added.connect(ShaderKeep.track_node)
	Events.zombie_damaged.connect(_on_zombie_damaged)
	Events.zombie_killed.connect(_on_zombie_killed)
	Events.player_died.connect(_on_player_died)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_cleared.connect(_on_wave_cleared)
	broken_loot = DisplayServer.get_name() != "headless"
	# Fortschritt: Mit Bildschirm aus der Datei, ohne (Tests) nie lesen oder schreiben und alles frei.
	progress_file_enabled = DisplayServer.get_name() != "headless"
	if progress_file_enabled:
		load_progress_from(PROGRESS_PATH)
	else:
		progress.unlock_all = true


func _notification(what: int) -> void:
	# Fenster zu mitten im Lauf: Die verdienten Punkte gehen nicht verloren.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_settle_run()


## Beginnt einen Lauf: setzt Punkte, Material, Welle, Kills und Upgrades zurück, State PLAYING,
## Pause aus, sendet run_started, points_changed und materials_changed(stand, 0).
## seed_value >= 0 macht den Zufall wiederholbar.
## Game.player bleibt unberührt (der Spieler-Knoten existiert schon).
func start_run(seed_value: int = -1) -> void:
	# Ein Lauf, der ohne Game Over verlassen wurde, wird hier noch abgerechnet.
	_settle_run()
	_reset_state()
	_run_settled = false
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	state = State.PLAYING
	_set_tree_paused(false)
	_apply_mouse_mode()
	Events.run_started.emit()
	Events.points_changed.emit(points)
	Events.materials_changed.emit(materials, 0)


## Schreibt Punkte gut und wendet den Punkte-Faktor der Upgrades an (kaufmännisch gerundet).
func add_points(base_amount: int) -> void:
	if base_amount <= 0:
		return
	_grant_points(roundi(float(base_amount) * upgrades.points_multiplier()))


## Reichen die Punkte für diesen Preis?
func can_afford(cost: int) -> bool:
	return cost >= 0 and points >= cost


## Zieht den Preis ab und gibt true zurück. Ohne genug Punkte passiert nichts (false).
func spend_points(cost: int) -> bool:
	if not can_afford(cost):
		return false
	points -= cost
	Events.points_changed.emit(points)
	return true


## Schreibt Material gut und sendet materials_changed(stand, amount). 0 oder weniger ändert nichts.
func add_materials(amount: int) -> void:
	if amount <= 0:
		return
	materials += amount
	Events.materials_changed.emit(materials, amount)


## Was die Reparatur dieses Gegenstands kostet (Balance.REPAIR_COST nach Rarität). 0, wenn es ihn
## nicht gibt oder er nicht kaputt ist.
func repair_cost(uid: int) -> int:
	if not backpack.is_broken(uid):
		return 0
	return Balance.REPAIR_COST[int(backpack.item(uid)["level"]) - 1]


## Material, das das Verschrotten dieses Gegenstands bringt (Balance.SCRAP_YIELD nach Rarität, ein
## Rucksack-Teil Balance.SCRAP_YIELD_BAG), gleich ob er kaputt oder heil ist. 0, wenn es ihn nicht gibt.
func scrap_value(uid: int) -> int:
	var entry: Dictionary = backpack.item(uid)
	if entry.is_empty():
		return 0
	if ItemDefs.is_bag(str(entry["id"])):
		return Balance.SCRAP_YIELD_BAG
	return Balance.SCRAP_YIELD[int(entry["level"]) - 1]


## Lässt sich dieser Gegenstand jetzt reparieren? Er ist kaputt und das Material reicht.
func can_repair(uid: int) -> bool:
	return backpack.is_broken(uid) and materials >= repair_cost(uid)


## Repariert einen kaputten Gegenstand für repair_cost(uid) Material. Er bleibt in der Ablage
## liegen und lässt sich danach einräumen und kombinieren. Sendet materials_changed(stand, -kosten)
## und item_repaired(uid). Kein build_changed: Am Build ändert sich nichts. Gibt false zurück (und
## ändert nichts), wenn er nicht kaputt ist oder das Material nicht reicht.
func repair_item(uid: int) -> bool:
	if not can_repair(uid):
		return false
	var cost: int = repair_cost(uid)
	backpack.repair(uid)
	materials -= cost
	Events.materials_changed.emit(materials, -cost)
	Events.item_repaired.emit(uid)
	return true


## Verschrottet einen Gegenstand aus Rucksack oder Ablage (kaputt oder heil): Er verschwindet, der
## Build wird abgeglichen (build_changed), dann kommt scrap_value(uid) Material dazu
## (materials_changed) und item_scrapped(uid, material). Gibt das Material zurück, 0 wenn es ihn
## nicht gibt.
func scrap_item(uid: int) -> int:
	var amount: int = scrap_value(uid)
	if backpack.remove(uid).is_empty():
		return 0
	sync_build()
	add_materials(amount)
	Events.item_scrapped.emit(uid, amount)
	return amount


## Öffnet eine Kiste: würfelt Angebote, pausiert, State CHOOSING, sendet chest_opened.
## Wirkt nur im State PLAYING, sonst passiert nichts.
func open_chest(rarity: int) -> void:
	if state != State.PLAYING:
		return
	current_rarity = clampi(rarity, Balance.RARITY_BRONZE, Balance.RARITY_GOLD)
	current_offers = ChestRoller.build_item_offers(rng, backpack, current_rarity,
			_chests_without_bag >= Balance.CHEST_BAG_PITY, _recent_offer_ids, progress)
	_chests_without_bag = 0 if ChestRoller.offers_have_bag(current_offers) else _chests_without_bag + 1
	_recent_offer_ids = ChestRoller.offer_ids(current_offers)
	state = State.CHOOSING
	_set_tree_paused(true)
	_apply_mouse_mode()
	Events.chest_opened.emit(current_rarity, current_offers)


## Nimmt das Angebot mit diesem Index (0 bis 2) an.
## Gegenstand: Er kommt in die Ablage des Rucksacks, der State wird PACKING (weiter pausiert) und
## backpack_opened(uid) wird gesendet. Der Lauf geht mit close_backpack() weiter. Mit auto_pack
## wird er stattdessen sofort eingeräumt und es geht direkt weiter. Mit broken_loot kommt er kaputt
## in die Ablage (Rucksack-Teile nie) und bleibt dort auch mit auto_pack liegen.
## Trostpreis: gibt Punkte oder Heilung, danach State PLAYING und Pause aus.
## Wirkt nur im State CHOOSING, ein ungültiger Index ändert nichts.
func choose_offer(index: int) -> void:
	if state != State.CHOOSING:
		return
	if index < 0 or index >= current_offers.size():
		return
	var offer: Dictionary = current_offers[index]
	current_offers = []
	if String(offer.get("kind", "")) == ChestRoller.KIND_ITEM:
		_levels_at_open = _build_levels()
		var uid: int = backpack.add_item(String(offer.get("id", "")), int(offer.get("level", 1)), broken_loot)
		if auto_pack or uid == -1:
			_auto_pack(uid)
			state = State.PLAYING
			_set_tree_paused(false)
			_apply_mouse_mode()
			_announce_build_changes()
		else:
			state = State.PACKING
			_apply_mouse_mode()
			Events.backpack_opened.emit(uid)
		return
	state = State.PLAYING
	_set_tree_paused(false)
	_apply_mouse_mode()
	match String(offer.get("kind", "")):
		ChestRoller.KIND_UPGRADE:
			var id: String = String(offer["id"])
			var gain: int = int(offer["to_level"]) - int(offer["from_level"])
			var new_level: int = upgrades.add_levels(id, gain)
			Events.upgrade_chosen.emit(id, new_level)
			for synergy_id: String in upgrades.check_new_synergies():
				Events.synergy_unlocked.emit(synergy_id)
		ChestRoller.KIND_POINTS:
			# Trostpreis: genau der angezeigte Betrag, ohne Punkte-Faktor.
			_grant_points(int(offer.get("amount", 0)))
		ChestRoller.KIND_HEAL:
			if is_instance_valid(player) and player.has_method("heal"):
				player.call("heal", float(offer.get("amount", 0)))


## Öffnet den Rucksack (Taste): State PACKING, Pause an, sendet backpack_opened(-1).
## Wirkt nur im State PLAYING.
func open_backpack() -> void:
	if state != State.PLAYING:
		return
	_levels_at_open = _build_levels()
	state = State.PACKING
	_set_tree_paused(true)
	_apply_mouse_mode()
	Events.backpack_opened.emit(-1)


## Schließt den Rucksack: State PLAYING, Pause aus. Für jedes Upgrade, das seit dem Öffnen
## gestiegen ist, kommt upgrade_chosen, für jede neue Verbindung synergy_unlocked, zum Schluss
## backpack_closed. Gibt false zurück, wenn der State nicht PACKING ist. Die Ablage hat keine
## Grenze mehr (Abschnitt 26): Wie viel dort liegt, hält den Rucksack nicht offen.
func close_backpack() -> bool:
	if state != State.PACKING:
		return false
	state = State.PLAYING
	_set_tree_paused(false)
	_apply_mouse_mode()
	_announce_build_changes()
	Events.backpack_closed.emit()
	return true


## Berechnet Game.upgrades neu aus Rucksack und Kandidat und sendet build_changed.
## Nach jeder Änderung am Rucksack aufrufen.
func sync_build() -> void:
	backpack.apply_to(upgrades, CharacterDefs.extra(character_id))
	_refresh_loadout()
	if _refresh_cameras():
		Events.cameras_changed.emit()
	Events.build_changed.emit()


## Rechnet Game.cameras neu aus Rucksack und Sendeleitungen. true, wenn sich die Liste geändert hat.
func _refresh_cameras() -> bool:
	var fresh: Array[Dictionary] = []
	var uplinks: Array = upgrades.copies(CameraDefs.MOD_UPLINK)
	for entry: Dictionary in backpack.cameras():
		var stats: Dictionary = CameraDefs.stats(str(entry["id"]), int(entry["level"]), entry["mods"] as Dictionary, uplinks)
		if stats.is_empty():
			continue
		stats.merge(entry)
		fresh.append(stats)
	if fresh == cameras:
		return false
	cameras = fresh
	return true


## Einträge aus Game.cameras mit diesem Kameratyp (z. B. "drone"), in der Reihenfolge des Erwerbs.
func cameras_of(camera_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in cameras:
		if str(entry["id"]) == camera_id:
			result.append(entry)
	return result


## Eintrag aus Game.cameras mit diesem Schlüssel ("key"), leer wenn es ihn nicht gibt.
func camera_entry(key: String) -> Dictionary:
	for entry: Dictionary in cameras:
		if str(entry["key"]) == key:
			return entry
	return {}


## Beste Rarität je Kameratyp im Spiel: camera_id -> 1 bis 5 (für Übersichten).
func camera_levels() -> Dictionary:
	var levels: Dictionary = {}
	for entry: Dictionary in cameras:
		levels[str(entry["id"])] = maxi(int(levels.get(str(entry["id"]), 0)), int(entry["level"]))
	return levels


## Stufen für die Meldungen beim Schließen des Rucksacks: Upgrades und Kameras zusammen.
func _build_levels() -> Dictionary:
	var levels: Dictionary = upgrades.levels()
	levels.merge(camera_levels())
	return levels


## Liest die Bewaffnung aus dem Rucksack und baut die Upgrades je Waffe.
func _refresh_loadout() -> void:
	loadout = backpack.loadout()
	if loadout.is_empty():
		# Ohne Waffe im Rucksack hält der Spieler die Dienstpistole (Notlösung, kein Gegenstand).
		loadout = [{"uid": 0, "id": WeaponDefs.START_WEAPON, "level": 1, "hands": 1, "copies": {}, "damage": 0.0, "reload": 0.0}]
	_weapon_upgrades.clear()
	for weapon: Dictionary in loadout:
		var copies: Dictionary = weapon["copies"]
		var levels: Dictionary = {}
		for id: String in copies:
			for level: Variant in copies[id] as Array:
				levels[id] = maxi(int(levels.get(id, 0)), int(level))
		var state: UpgradeState = UpgradeState.new()
		state.set_derived(levels, [] as Array[String], {"damage": float(weapon["damage"]), "reload": float(weapon["reload"])}, copies)
		_weapon_upgrades[int(weapon["uid"])] = state


## Upgrades, die nur für diese Waffe gelten (ihre Stern-Gegenstände). Für eine unbekannte uid
## kommt ein leerer Zustand zurück.
func weapon_upgrades(weapon_uid: int) -> UpgradeState:
	if _weapon_upgrades.has(weapon_uid):
		return _weapon_upgrades[weapon_uid] as UpgradeState
	return UpgradeState.new()


## Eintrag der Waffe mit dieser uid in loadout, leer wenn sie nicht in der Hand ist.
func loadout_entry(weapon_uid: int) -> Dictionary:
	for weapon: Dictionary in loadout:
		if int(weapon["uid"]) == weapon_uid:
			return weapon
	return {}


## Wert eines Kugel-Effekts für diese Waffe: alle allgemein wirkenden Exemplare und die auf dieser
## Waffe zusammen (UpgradeDefs.combined_value). weapon_uid -1 = nur die allgemeinen.
func bullet_value(weapon_uid: int, id: String, key: String) -> float:
	return upgrades.value_with(weapon_upgrades(weapon_uid), id, key)


## Beste Stufe eines Kugel-Effekts für diese Waffe (0 = wirkt nicht).
func bullet_level(weapon_uid: int, id: String) -> int:
	return upgrades.level_with(weapon_upgrades(weapon_uid), id)


## Faktor auf den Schaden dieser Waffe: Rarität der Waffe mal (1 + Zusatz des Kandidaten +
## Verstärker auf der Waffe).
func weapon_damage_multiplier(weapon_uid: int) -> float:
	var entry: Dictionary = loadout_entry(weapon_uid)
	var rarity: float = ItemDefs.weapon_damage_factor(int(entry.get("level", 1)))
	return rarity * maxf(0.1, 1.0 + upgrades.extra("damage") + weapon_upgrades(weapon_uid).extra("damage"))


## Faktor auf die Nachladezeit dieser Waffe (1,0 = normal, mindestens 0,5).
func weapon_reload_multiplier(weapon_uid: int) -> float:
	var bonus: float = upgrades.extra("reload") + weapon_upgrades(weapon_uid).extra("reload")
	return clampf(1.0 - bonus, 1.0 - Balance.RELOAD_BONUS_MAX, 1.0)


## Gibt dem Spieler einen Gegenstand außerhalb einer Kiste: Er kommt in die Ablage
## und der Rucksack öffnet sich (mit auto_pack räumt er sich selbst ein). Wirkt nur im State
## PLAYING. Gibt die uid zurück, -1 wenn es nicht geht. Fragt nicht nach dem Freischalten.
## broken = true: Er kommt kaputt in die Ablage (ein Rucksack-Teil nie). Ohne den Parameter ist er
## heil, gleich wie broken_loot steht.
func grant_item(id: String, level: int = 1, broken: bool = false) -> int:
	if state != State.PLAYING or not ItemDefs.has(id):
		return -1
	_levels_at_open = _build_levels()
	var uid: int = backpack.add_item(id, level, broken)
	if auto_pack:
		_auto_pack(uid)
		_announce_build_changes()
		return uid
	state = State.PACKING
	_set_tree_paused(true)
	_apply_mouse_mode()
	Events.backpack_opened.emit(uid)
	return uid


## Verkauft einen Gegenstand aus Rucksack oder Ablage: gibt genau seinen Verkaufswert in Punkten
## (ohne Punkte-Faktor) und gleicht den Build ab. Gibt die Punkte zurück, 0 wenn es ihn nicht gibt.
## Ein kaputter Gegenstand bringt denselben Wert wie ein heiler.
func sell_item(uid: int) -> int:
	var entry: Dictionary = backpack.remove(uid)
	if entry.is_empty():
		return 0
	var amount: int = ItemDefs.sell_value(String(entry["id"]), int(entry["level"]))
	sync_build()
	# Verkaufserlöse zählen nicht fürs Konto (Abschnitt 22.5).
	_grant_points(amount, false)
	return amount


## Räumt einen Gegenstand aus der Ablage selbst ein: mit einem gleichen Gegenstand gleicher
## Rarität kombinieren (und das Ergebnis gleich weiter, solange es einen Partner gibt), sonst an
## die erste passende Stelle. Passt er nirgends, ist keine Hand frei oder ist er kaputt, bleibt er
## in der Ablage (sie hat keine Grenze). Repariert wird hier nichts.
func _auto_pack(uid: int) -> void:
	if not backpack.has_item(uid):
		return
	var partner: int = backpack.find_merge_partner(uid)
	if partner != -1 and backpack.merge(uid, partner):
		# Kette: Zwei Gewöhnliche werden Ungewöhnlich, liegt schon ein Ungewöhnlicher da, geht es weiter.
		var current: int = partner
		var next: int = backpack.find_merge_partner(current)
		while next != -1 and backpack.merge(current, next):
			current = next
			next = backpack.find_merge_partner(current)
		sync_build()
		return
	if backpack.auto_place(uid):
		sync_build()


## Meldet, was seit _levels_at_open besser geworden ist: upgrade_chosen je gestiegenem Upgrade
## und je neuer oder besserer Kamera (id = Kameratyp), synergy_unlocked je neuer Verbindung.
func _announce_build_changes() -> void:
	var now: Dictionary = _build_levels()
	for id: String in now:
		if int(now[id]) > int(_levels_at_open.get(id, 0)):
			Events.upgrade_chosen.emit(id, int(now[id]))
	_levels_at_open = now
	for synergy_id: String in upgrades.check_new_synergies():
		Events.synergy_unlocked.emit(synergy_id)


## Pausemenü: wechselt zwischen PLAYING und PAUSED. In jedem anderen State passiert nichts.
func set_paused(paused: bool) -> void:
	if paused and state == State.PLAYING:
		state = State.PAUSED
	elif not paused and state == State.PAUSED:
		state = State.PLAYING
	else:
		return
	_set_tree_paused(paused)
	_apply_mouse_mode()


## Beendet den Lauf: State GAME_OVER, Pause an, die verdienten Punkte kommen aufs Konto
## (bank_changed), dann game_over(stats). Mehrfacher Aufruf wirkt einmal.
func end_run() -> void:
	if state == State.GAME_OVER:
		return
	current_offers = []
	state = State.GAME_OVER
	_set_tree_paused(true)
	_apply_mouse_mode()
	_settle_run()
	Events.game_over.emit(get_stats())


## Rechnet den Lauf ab, genau einmal: Die im Lauf verdienten Punkte (bank_points_earned) kommen
## aufs Konto, der Lauf zählt für beste Welle und Zahl der Läufe, der Fortschritt wird gespeichert
## und bank_changed(bank, gained) gesendet. Läuft am Game Over, beim Neustart oder Beenden aus der
## Pause und beim Schließen des Fensters.
func _settle_run() -> void:
	if _run_settled:
		return
	_run_settled = true
	last_bank_gain = progress.add_bank(bank_points_earned)
	progress.record_run(wave)
	_autosave_progress()
	Events.bank_changed.emit(progress.bank, last_bank_gain)


## Kauft ein Paket vom Konto (Abschnitt 22.5). true, wenn es geklappt hat: Dann ist der Fortschritt
## gespeichert, und pack_unlocked(pack_id) und bank_changed(bank, -preis) wurden gesendet.
func buy_pack(pack_id: String) -> bool:
	var price: int = UnlockDefs.pack_price(pack_id)
	if not progress.buy(pack_id):
		return false
	_autosave_progress()
	Events.pack_unlocked.emit(pack_id)
	Events.bank_changed.emit(progress.bank, -price)
	return true


## Speichert den Fortschritt in diese Datei. false, wenn das Schreiben scheitert. Das Spiel selbst
## speichert über _autosave_progress nach PROGRESS_PATH (ohne Bildschirm nie).
func save_progress_to(path: String) -> bool:
	var file: ConfigFile = ConfigFile.new()
	var data: Dictionary = progress.to_dict()
	for key: String in data:
		file.set_value(PROGRESS_SECTION, key, data[key])
	return file.save(path) == OK


## Lädt den Fortschritt aus dieser Datei. Fehlt sie oder ist sie kaputt, bleibt der Fortschritt,
## wie er ist (false).
func load_progress_from(path: String) -> bool:
	var file: ConfigFile = ConfigFile.new()
	if file.load(path) != OK or not file.has_section(PROGRESS_SECTION):
		return false
	var data: Dictionary = {}
	for key: String in file.get_section_keys(PROGRESS_SECTION):
		data[key] = file.get_value(PROGRESS_SECTION, key)
	progress.from_dict(data)
	return true


func _autosave_progress() -> void:
	if progress_file_enabled:
		save_progress_to(PROGRESS_PATH)


## Statistik des Laufs:
## { "wave": int, "kills": int, "points": int (insgesamt verdient), "upgrades": Array von
##   { "id", "name", "level" } (wirksame Stufen), "synergies": Array[String] mit Synergie-IDs,
##   "character": String (Kandidaten-ID, "" = keiner), "items": Array von { "id", "name", "level" }
##   (eingeräumte Gegenstände), "cameras": Array von { "id", "name", "level" } (je Kamera-Exemplar),
##   "bank_gained": int (was dieser Lauf aufs Konto bringt oder gebracht hat), "bank": int (Konto),
##   "materials": int (Material am Ende des Laufs) }.
func get_stats() -> Dictionary:
	var camera_rows: Array[Dictionary] = []
	for entry: Dictionary in cameras:
		camera_rows.append({"id": str(entry["id"]), "name": CameraDefs.display_name(str(entry["id"])), "level": int(entry["level"])})
	return {
		"wave": wave,
		"kills": kills,
		"points": total_points_earned,
		"upgrades": upgrades.summary(),
		"synergies": upgrades.active_synergies(),
		"character": character_id,
		"items": backpack.summary(),
		"cameras": camera_rows,
		"bank_gained": last_bank_gain if _run_settled else bank_points_earned,
		"bank": progress.bank,
		"materials": materials,
	}


## Neustart: Pause aus, Zustand zurück, aktuelle Szene neu laden (main.gd ruft dann start_run).
## Ohne aktuelle Szene (Tests ohne current_scene) beginnt sofort ein neuer Lauf.
func restart_run() -> void:
	# Neustart aus der Pause: Der abgebrochene Lauf wird noch abgerechnet.
	_settle_run()
	_reset_state()
	state = State.MENU
	player = null
	_set_tree_paused(false)
	_apply_mouse_mode()
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree.current_scene != null:
		tree.reload_current_scene()
	else:
		start_run()


## Beendet das Programm (Knopf "Beenden").
func quit_game() -> void:
	_settle_run()
	if is_inside_tree():
		get_tree().quit()


## Läuft das Spiel gerade (weder Wahl noch Pause noch Game Over)?
func is_playing() -> bool:
	return state == State.PLAYING


## Effekt-Faktor der aktuellen Welle für feste Schadenswerte der Upgrades (mindestens 1).
func effect_factor() -> float:
	return WavePlan.effect_factor(maxi(wave, 1))


func _reset_state() -> void:
	points = Balance.POINTS_START + CharacterDefs.start_points(character_id)
	materials = Balance.MATERIAL_START
	wave = 0
	kills = 0
	total_points_earned = 0
	bank_points_earned = 0
	upgrades = UpgradeState.new()
	backpack = CharacterDefs.build_backpack(character_id)
	backpack.apply_to(upgrades, CharacterDefs.extra(character_id))
	_refresh_loadout()
	_refresh_cameras()
	# Start-Gegenstände gelten nicht als neue Errungenschaft: schon erfüllte Verbindungen vormerken.
	upgrades.check_new_synergies()
	_levels_at_open = _build_levels()
	_chests_without_bag = 0
	_recent_offer_ids = []
	rng = RandomNumberGenerator.new()
	current_offers = []
	current_rarity = 0


## banked = false: Der Betrag zählt nicht fürs Konto (Verkauf von Gegenständen).
func _grant_points(amount: int, banked: bool = true) -> void:
	if amount <= 0:
		return
	points += amount
	total_points_earned += amount
	if banked:
		bank_points_earned += amount
	Events.points_changed.emit(points)


func _set_tree_paused(paused: bool) -> void:
	if is_inside_tree():
		get_tree().paused = paused


## Maus im State PLAYING gefangen, sonst sichtbar. Ohne Bildschirm (headless) passiert nichts.
func _apply_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if state == State.PLAYING:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_zombie_damaged(_zombie: Node3D, _amount: float, info: Dictionary) -> void:
	# Nur Kugeltreffer geben Treffer-Punkte.
	if String(info.get("source", "")) == "bullet":
		add_points(Balance.POINTS_BULLET_HIT)


func _on_zombie_killed(zombie: Node3D, info: Dictionary) -> void:
	kills += 1
	var is_elite: bool = is_instance_valid(zombie) and String(zombie.get("zombie_type")) == "elite"
	var amount: int = Balance.POINTS_ELITE_KILL if is_elite else Balance.POINTS_KILL
	if bool(info.get("headshot", false)):
		amount += Balance.POINTS_HEADSHOT_KILL_BONUS
	add_points(amount)


func _on_player_died() -> void:
	end_run()


func _on_wave_started(wave_number: int, _total_zombies: int) -> void:
	wave = wave_number


## Wellen-Prämie (Abschnitt 26): Material für jede geschaffte Welle, nur in einem laufenden Lauf.
func _on_wave_cleared(_wave_number: int) -> void:
	if state == State.MENU or state == State.GAME_OVER:
		return
	add_materials(Balance.MATERIAL_PER_WAVE)
