extends Node
## Zustand eines Laufs (Autoload "Game"): Punkte, Welle, Kills, Upgrades, Kistenwahl, Pause.
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
## erste passende Stelle, sonst verkauft) und der Rucksack öffnet sich nicht. Für Tests und Messungen.
var auto_pack: bool = false
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


## Beginnt einen Lauf: setzt Punkte, Welle, Kills und Upgrades zurück, State PLAYING, Pause aus,
## sendet run_started und points_changed. seed_value >= 0 macht den Zufall wiederholbar.
## Game.player bleibt unberührt (der Spieler-Knoten existiert schon).
func start_run(seed_value: int = -1) -> void:
	_reset_state()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	state = State.PLAYING
	_set_tree_paused(false)
	_apply_mouse_mode()
	Events.run_started.emit()
	Events.points_changed.emit(points)


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


## Öffnet eine Kiste: würfelt Angebote, pausiert, State CHOOSING, sendet chest_opened.
## Wirkt nur im State PLAYING, sonst passiert nichts.
func open_chest(rarity: int) -> void:
	if state != State.PLAYING:
		return
	current_rarity = clampi(rarity, Balance.RARITY_BRONZE, Balance.RARITY_GOLD)
	current_offers = ChestRoller.build_item_offers(rng, backpack, current_rarity,
			_chests_without_bag >= Balance.CHEST_BAG_PITY, _recent_offer_ids)
	_chests_without_bag = 0 if ChestRoller.offers_have_bag(current_offers) else _chests_without_bag + 1
	_recent_offer_ids = ChestRoller.offer_ids(current_offers)
	state = State.CHOOSING
	_set_tree_paused(true)
	_apply_mouse_mode()
	Events.chest_opened.emit(current_rarity, current_offers)


## Nimmt das Angebot mit diesem Index (0 bis 2) an.
## Gegenstand: Er kommt in die Ablage des Rucksacks, der State wird PACKING (weiter pausiert) und
## backpack_opened(uid) wird gesendet. Der Lauf geht mit close_backpack() weiter. Mit auto_pack
## wird er stattdessen sofort eingeräumt und es geht direkt weiter.
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
		_levels_at_open = upgrades.levels()
		var uid: int = backpack.add_item(String(offer.get("id", "")), int(offer.get("level", 1)))
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
	_levels_at_open = upgrades.levels()
	state = State.PACKING
	_set_tree_paused(true)
	_apply_mouse_mode()
	Events.backpack_opened.emit(-1)


## Schließt den Rucksack: State PLAYING, Pause aus. Für jedes Upgrade, das seit dem Öffnen
## gestiegen ist, kommt upgrade_chosen, für jede neue Verbindung synergy_unlocked, zum Schluss
## backpack_closed. Gibt false zurück (und bleibt offen), wenn die Ablage überfüllt ist oder der
## State nicht PACKING ist.
func close_backpack() -> bool:
	if state != State.PACKING or backpack.storage_overflow():
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
	Events.build_changed.emit()


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


## Gibt dem Spieler einen Gegenstand außerhalb einer Kiste (Wandkauf): Er kommt in die Ablage
## und der Rucksack öffnet sich (mit auto_pack räumt er sich selbst ein). Wirkt nur im State
## PLAYING. Gibt die uid zurück, -1 wenn es nicht geht.
func grant_item(id: String, level: int = 1) -> int:
	if state != State.PLAYING or not ItemDefs.has(id):
		return -1
	_levels_at_open = upgrades.levels()
	var uid: int = backpack.add_item(id, level)
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
func sell_item(uid: int) -> int:
	var entry: Dictionary = backpack.remove(uid)
	if entry.is_empty():
		return 0
	var amount: int = ItemDefs.sell_value(String(entry["id"]), int(entry["level"]))
	sync_build()
	_grant_points(amount)
	return amount


## Räumt einen Gegenstand aus der Ablage selbst ein: mit einem gleichen Gegenstand gleicher
## Rarität kombinieren (und das Ergebnis gleich weiter, solange es einen Partner gibt), sonst an
## die erste passende Stelle, sonst verkaufen.
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
		return
	# Kein Platz oder keine Hand frei: Der Gegenstand wartet in der Ablage. Ist sie überfüllt,
	# wird er verkauft.
	if backpack.storage_overflow():
		sell_item(uid)


## Meldet, was seit _levels_at_open besser geworden ist: upgrade_chosen je gestiegenem Upgrade,
## synergy_unlocked je neuer Verbindung.
func _announce_build_changes() -> void:
	var now: Dictionary = upgrades.levels()
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


## Beendet den Lauf: State GAME_OVER, Pause an, sendet game_over(stats). Mehrfacher Aufruf wirkt einmal.
func end_run() -> void:
	if state == State.GAME_OVER:
		return
	current_offers = []
	state = State.GAME_OVER
	_set_tree_paused(true)
	_apply_mouse_mode()
	Events.game_over.emit(get_stats())


## Statistik des Laufs:
## { "wave": int, "kills": int, "points": int (insgesamt verdient), "upgrades": Array von
##   { "id", "name", "level" } (wirksame Stufen), "synergies": Array[String] mit Synergie-IDs,
##   "character": String (Kandidaten-ID, "" = keiner), "items": Array von { "id", "name", "level" }
##   (eingeräumte Gegenstände) }.
func get_stats() -> Dictionary:
	return {
		"wave": wave,
		"kills": kills,
		"points": total_points_earned,
		"upgrades": upgrades.summary(),
		"synergies": upgrades.active_synergies(),
		"character": character_id,
		"items": backpack.summary(),
	}


## Neustart: Pause aus, Zustand zurück, aktuelle Szene neu laden (main.gd ruft dann start_run).
## Ohne aktuelle Szene (Tests ohne current_scene) beginnt sofort ein neuer Lauf.
func restart_run() -> void:
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
	wave = 0
	kills = 0
	total_points_earned = 0
	upgrades = UpgradeState.new()
	backpack = CharacterDefs.build_backpack(character_id)
	backpack.apply_to(upgrades, CharacterDefs.extra(character_id))
	_refresh_loadout()
	# Start-Gegenstände gelten nicht als neue Errungenschaft: schon erfüllte Verbindungen vormerken.
	upgrades.check_new_synergies()
	_levels_at_open = upgrades.levels()
	_chests_without_bag = 0
	_recent_offer_ids = []
	rng = RandomNumberGenerator.new()
	current_offers = []
	current_rarity = 0


func _grant_points(amount: int) -> void:
	if amount <= 0:
		return
	points += amount
	total_points_earned += amount
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
