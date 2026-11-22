extends Node
## Modul: Spieler (scripts/game/player).
## Waffen des Spielers (Kind des Spielers, Name "WeaponController"), Abschnitt 18.
##
## Der Spieler hält, was als Waffe im Rucksack liegt (Game.loadout): eine Zweihand-Waffe, eine
## Einhand-Waffe oder zwei Einhand-Waffen (beidhändig). Je gehaltener Waffe gibt es eine Hand mit
## eigenem WeaponState (Magazin, Nachladen, Schussfolge), gemerkt unter der uid der Waffe. Hand 0
## ist die linke. Bei Events.build_changed wird neu abgeglichen: Waffen, deren uid bleibt, behalten
## ihr Magazin. Bei Events.run_started beginnt alles mit vollen Magazinen. Danach kommt
## Events.loadout_changed. Munition ist unendlich, einen Waffenwechsel gibt es nicht.
##
## Schuss: Die Aktion "fire" schießt mit allen gehaltenen Waffen, jede in ihrer eigenen
## Schussfolge (automatisch: Dauerfeuer, sonst ein Schuss je Druck). Je Kugel ein Strahl von der
## Kamera in Blickrichtung mit Streuung (Zufall aus Game.rng). Mit dem Upgrade "pierce" geht die
## Kugel durch weitere Zombies, jeder weitere bekommt weniger Schaden (WeaponDefs.bullet_damage).
## Je Treffer erst zombie.take_damage, danach Events.bullet_hit (Schadensweg, Abschnitt 7). Die
## Treffer-Info trägt "weapon_uid", "weapon" und "hand". Eine Rakete explodiert am Einschlag:
## Der direkt getroffene Zombie bekommt den Kugelschaden (source "bullet"), alle anderen im Radius
## den Explosionsschaden (source "explosion"). Geschossen wird nur im State PLAYING und solange
## der Spieler lebt.
##
## Gegenstände je Waffe (Abschnitt 19.1), gelesen mit Game.bullet_value(uid, ...) für jede Hand
## für sich:
## - Zugabe (extra_shot): Nach den normalen Kugeln fliegen "shots" Zusatzkugeln (bei Schrot je
##   Schuss, beim Raketenwerfer weitere Raketen). Sie kosten keine Munition, fliegen um höchstens
##   WeaponDefs.EXTRA_SHOT_SPREAD_DEG versetzt, haben eine eigene, hellere Leuchtspur und machen
##   den Anteil "damage_factor" des Kugelschadens. In der Treffer-Info steht "extra": true.
## - Glücksrad (crit): Je Kugel (auch je Schrotkugel und je Zusatzkugel) ein Wurf aus Game.rng
##   nach der Streuung. Ein kritischer Treffer zählt mal Balance.CRIT_MULTIPLIER, in der
##   Treffer-Info steht "crit": true. Ohne Chance wird nicht gewürfelt (der Zufall eines Laufs
##   ohne den Gegenstand bleibt, wie er war).
## - Überlänge (big_mag) und Schnelldurchlauf (fire_rate): stehen als magazine_bonus und
##   fire_rate_factor im WeaponState. Gesetzt bei jedem Abgleich, dazu vor jedem Schuss und vor
##   jedem Nachladen. Ein größeres Magazin füllt sich nicht von selbst, ein kleineres verliert
##   den Rest.
## - Teleprompter (scope): Streuung mal Balance.SCOPE_SPREAD_FACTOR, Kopftreffer zusätzlich mal
##   (1 + headshot_bonus).
## Die Explosion einer Rakete übernimmt Anteil, kritischen Treffer und die Marken "extra" und
## "crit" von ihrer Rakete. "extra" und "crit" stehen in jeder Treffer-Info (sonst false).
##
## Signale bei einem Schuss einer Hand: alle bullet_hit, dann weapon_fired, dann hand_ammo_changed,
## bei leerem Magazin zum Schluss hand_reload_started. Die alten Signale ammo_changed,
## reload_started, reload_finished und weapon_changed kommen weiter für die linke Hand,
## weapon_fired für jeden Schuss jeder Hand.
##
## Schussarten und eingebaute Eigenschaften der Waffen aus Abschnitt 22.2 (alles aus WeaponDefs):
## - Salve (burst): Der Abzug gibt den ersten Schuss, die übrigen folgen von selbst im Abstand
##   burst_interval (WeaponState.burst_shot_due, fire_burst_shot). Jeder Schuss der Salve ist ein
##   ganzer Schuss: eine Kugel aus dem Magazin, eigene Zusatzkugeln, eigenes weapon_fired.
## - Durchschlag (pierce): kommt zum Durchschlag aus Gegenständen dazu, mit demselben
##   Schadensabfall je weiterem Ziel.
## - Blitz (arc_jumps): Jeder Kugeltreffer springt auf weitere Zombies über, jeweils zum nächsten
##   noch nicht getroffenen im Umkreis arc_radius, jeder mit arc_factor des Treffer-Schadens und
##   source "lightning" (kein bullet_hit, löst also selbst nichts weiter aus). Sichtbar über
##   Fx.lightning: der Schuss selbst (ab ARC_SHOT_LEAD vor der Mündung) und die Kette der Sprünge.
## - Granate (MODE_GRENADE): fliegt im Bogen (grenade.gd). Am Einschlag bekommt ein direkt
##   getroffener Zombie den Kugelschaden (source "bullet", mit bullet_hit), alle anderen im Radius
##   den Explosionsschaden. Sie prallt nicht ab und explodiert auch an Boden und Wand. Treffer und
##   Explosion kommen also erst nach weapon_fired.
## - Flamme (MODE_FLAME): Jeder Stoß trifft alle lebenden Zombies im Kegel (reach, cone_deg als
##   halber Winkel, gemessen vom Auge in Blickrichtung) mit freier Sicht, von nah nach fern, und
##   setzt jeden mit burn_dps für burn_time in Brand (fester Wert, kein Kopftreffer).
## - Strahl (MODE_BEAM): Jeder Treffer geht ohne Schadensabfall durch alle Zombies in der Linie
##   bis zur Wand. Solange gefeuert wird, steht ein sichtbarer Strahl (beam_fx.gd).
## Flamme und Strahl melden jeden Treffer mit bullet_hit, damit die Gegenstände auf der Waffe
## wirken. Treffer-Punkte gibt es dabei nur für den ersten getroffenen Zombie je Stoß (siehe
## _deal_hit): So bringt eine Flamme durch zehn Zombies nicht zehnmal so viele Punkte wie eine
## Kugelwaffe mit derselben Schussfolge. Zugabe und Glücksrad gelten je Stoß: Die Zugabe gibt
## einen zweiten Stoß mit ihrem Anteil am Schaden, ein Wurf für den kritischen Treffer gilt für
## alle Zombies des Stoßes.
##
## Gegenstände, die den Magazinstand brauchen (Abschnitt 22.3):
## - Eröffnungsgag (opener): Der Schuss aus dem vollen Magazin macht (1 + bonus) mal Schaden.
## - Schlusspointe (punchline): Der Schuss, der das Magazin leert, explodiert an seinem ersten
##   Einschlag (Zombie oder Welt): Radius Balance.PUNCHLINE_RADIUS, Schaden "damage" mal
##   Game.effect_factor() an allen Zombies im Radius, source "explosion".
## Bei Schrot zählt der Schuss (alle Schrotkugeln des ersten Schusses sind stärker, der letzte
## Schuss explodiert einmal), bei einer Salve jede Kugel für sich.
##
## Treffer-Info: Jeder Treffer trägt neben den Schlüsseln aus Abschnitt 18 "mode" (Schussart),
## "opener" (bool) und "scored" (bool, gab der Treffer Treffer-Punkte). Ein Blitzsprung trägt
## "arc": true, die Explosion der Schlusspointe "punchline": true.
##
## Bilder der Treffer (reine Optik, alles über fx.gd, Zufall nie aus Game.rng):
## - Einschlag in der Welt: Fx.impact (Funken, Staub, Einschussmal) an der getroffenen Fläche.
## - Treffer am Zombie: Fx.splatter in Flugrichtung der Kugel, stärker bei Kopftreffer und
##   kritischem Treffer. Schrot, Flamme und Strahl dünnen aus (SPLAT_STRENGTH_*).
## - Trefferzahl: Fx.hint_number direkt vor Events.bullet_hit sagt fx.gd, dass die nächste Zahl
##   mit diesem Betrag ein Kopftreffer oder kritischer Treffer ist.
## - Tod eines Zombies (Events.zombie_killed, egal wodurch): Fx.kill_burst an seiner Körpermitte.

const Balance := preload("res://scripts/core/balance.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const WeaponState := preload("res://scripts/core/weapon_state.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")
const Grenade := preload("res://scripts/game/player/grenade.gd")
const BeamFx := preload("res://scripts/game/player/beam_fx.gd")
const FlameFx := preload("res://scripts/game/player/flame_fx.gd")

# --- Reine Optik ---
const TRACER_COLORS: Dictionary = {
	"pistol": Color(1.0, 0.92, 0.35),
	"revolver": Color(1.0, 0.75, 0.3),
	"smg": Color(0.35, 0.95, 1.0),
	"sawed_off": Color(0.7, 1.0, 0.3),
	"shotgun": Color(1.0, 0.55, 0.15),
	"rifle": Color(0.45, 0.7, 1.0),
	"sniper": Color(0.95, 0.5, 1.0),
	"minigun": Color(1.0, 0.4, 0.75),
	"rocket_launcher": Color(1.0, 0.45, 0.1),
	"burst_pistol": Color(1.0, 0.6, 0.85),
	"nail_gun": Color(0.85, 0.9, 1.0),
	"machine_pistol": Color(0.6, 1.0, 0.55),
	"crossbow": Color(0.4, 1.0, 0.8),
	"grenade_launcher": Color(1.0, 0.65, 0.15),
	"flamethrower": Color(1.0, 0.5, 0.1),
	"beam": Color(1.0, 0.2, 0.15),
	"tesla": Color(0.35, 0.9, 1.0),
	"lmg": Color(1.0, 0.85, 0.5),
	"auto_shotgun": Color(0.3, 0.75, 1.0),
}
## Die Leuchtspur einer Zusatzkugel ist um diesen Anteil zu Weiß hin aufgehellt.
const EXTRA_TRACER_WHITEN: float = 0.55
const EXPLOSION_COLOR: Color = Color(1.0, 0.5, 0.12)
const PUNCHLINE_COLOR: Color = Color(1.0, 0.25, 0.75)
const ARC_NUMBER_COLOR: Color = Color(0.45, 0.9, 1.0)
## Trefferzahlen der Blitzsprünge erscheinen so weit über der Körpermitte.
const ARC_NUMBER_HEIGHT: float = 0.6
## Stärke von Einschlag und Spritzern (1 = voll): Schrot hat viele Kugeln je Schuss, Flamme und
## Strahl treffen 15 bis 20 Mal je Sekunde jeden Zombie in ihrer Bahn.
const FX_STRENGTH_PELLETS: float = 0.45
const FX_STRENGTH_STREAM: float = 0.17
## Die Leuchtspur beginnt erst so weit vor der Mündung (höchstens dieser Anteil ihrer Länge):
## knapp hinter dem Mündungsfeuer.
const TRACER_LEAD: float = 0.2
const TRACER_LEAD_SHARE: float = 0.1
## Strahl und Flamme bleiben nach dem letzten Stoß noch so viele Schussfolgen lang sichtbar: Bei
## Dauerfeuer reißt das Bild so nie ab, nach dem Loslassen ist es sofort weg.
const STREAM_LINGER_SHOTS: float = 1.5
## Obergrenze der Strahl-Abschnitte je Kugel (Durchschlag plus Leichen im Weg).
const MAX_RAY_STEPS: int = 16
## Der Schuss des Kurzschlusses ist ein Blitz. Er beginnt erst so weit vor der Mündung (bis dahin
## eine normale Leuchtspur): Ein breiter Blitz direkt vor der Kamera verdeckte sonst das halbe Bild.
const ARC_SHOT_LEAD: float = 1.6
## Dasselbe für den Dauerstrahl, der durch alle Zombies in der Linie geht.
const BEAM_MAX_RAY_STEPS: int = 96
## Die Mitte einer Explosion liegt so weit vor dem Einschlag (zum Schützen hin), damit die
## Sichtlinien zu den Zombien nicht in der getroffenen Wand beginnen.
const EXPLOSION_BACKOFF: float = 0.12
## So viele Rucksack-Teile legt equip höchstens an, damit eine Waffe in den Rucksack passt.
const EQUIP_MAX_BAGS: int = 6
const VIEW_MODEL_PATH: NodePath = ^"Camera/ViewModel"


## Eine Hand mit ihrer Waffe.
class Hand:
	extends RefCounted
	## uid der Waffe im Rucksack (0 = Dienstpistole ohne Rucksack).
	var uid: int = 0
	var id: String = ""
	## Rarität der Waffe (1 bis 5).
	var level: int = 1
	## Hände, die die Waffe braucht (1 oder 2).
	var hands: int = 1
	var state: WeaponState = null
	## Restzeit, in der ein knapp zu früh gedrückter Abzug noch zählt (nur nicht automatische Waffen).
	var fire_buffer_left: float = 0.0
	## Sichtbarer Dauerstrahl oder sichtbare Flamme dieser Hand (BeamFx oder FlameFx, entsteht beim
	## ersten Stoß) und die Restzeit, in der das Bild nach dem letzten Stoß noch steht.
	var stream: Node3D = null
	var stream_left: float = 0.0


## Ein Schuss einer Hand: alles, was für seine Kugeln gleich ist.
class Shot:
	extends RefCounted
	## Index der Hand (0 = links).
	var index: int = 0
	var hand: Hand = null
	var def: Dictionary = {}
	## Schussart (WeaponDefs.MODE_*).
	var mode: String = WeaponDefs.MODE_BULLET
	## Verliert die Kugel je durchschlagenem Ziel Schaden? (der Dauerstrahl nicht)
	var falloff: bool = true
	## Gibt jeder Treffer Treffer-Punkte? Bei Flamme und Strahl nur der erste des Schusses.
	var score_each: bool = true
	## Hat dieser Schuss schon einen Treffer mit Treffer-Punkten gelandet?
	var scored: bool = false
	## Erster Schuss des Magazins mit Eröffnungsgag (der Zuschlag steckt schon in multiplier).
	var opener: bool = false
	## Schaden der Schlusspointe, wenn dieser Schuss das Magazin leert (0 = keine), und ob sie
	## schon explodiert ist (einmal je Schuss, am ersten Einschlag).
	var punchline_damage: float = 0.0
	var punchline_done: bool = false
	## Eingebauter Blitz: Sprünge, Anteil am Treffer-Schaden, Umkreis in Metern.
	var arc_jumps: int = 0
	var arc_factor: float = 0.0
	var arc_radius: float = 0.0
	## Auge des Spielers und Blickrichtung.
	var from: Vector3 = Vector3.ZERO
	var aim: Vector3 = Vector3.FORWARD
	## Mündung der sichtbaren Waffe (Start der Leuchtspur).
	var muzzle: Vector3 = Vector3.ZERO
	var fx_root: Node = null
	## Weitere Ziele, die eine Kugel durchschlägt.
	var pierce_targets: int = 0
	## Streuung in Grad (mit Teleprompter kleiner).
	var spread_deg: float = 0.0
	## Faktor auf den Schaden: Rarität, Kandidat, Verstärker.
	var multiplier: float = 1.0
	## Chance auf einen kritischen Treffer je Kugel (0 = kein Wurf).
	var crit_chance: float = 0.0
	## Zusatz auf Kopftreffer vom Teleprompter.
	var headshot_bonus: float = 0.0
	## Stärke der Bilder am Einschlag (reine Optik, siehe FX_STRENGTH_*).
	var fx_strength: float = 1.0


## Die Hände in Reihenfolge (Index 0 = linke Hand).
var _hands: Array[Hand] = []
var _player: Node3D = null

## Nach Pause oder Kistenwahl muss der Abzug erst losgelassen werden (der Klick galt dem Menü).
var _fire_blocked_until_release: bool = false
var _last_process_frame: int = -1
var _was_inactive: bool = true


func _ready() -> void:
	_player = get_parent() as Node3D
	_last_process_frame = Engine.get_process_frames()
	Events.run_started.connect(_on_run_started)
	Events.build_changed.connect(_on_build_changed)
	Events.zombie_killed.connect(_on_zombie_killed)
	_sync_loadout(true)


func _process(delta: float) -> void:
	var frame: int = Engine.get_process_frames()
	# Lücke in den Bildern = der Baum war pausiert (Kistenwahl, Pausemenü, Rucksack).
	var resumed: bool = frame - _last_process_frame > 1 or _was_inactive
	_last_process_frame = frame
	_tick_states(delta)
	_tick_streams(delta)
	if not _can_act():
		_was_inactive = true
		_clear_fire_buffers()
		_stop_action()
		return
	_was_inactive = false
	_fire_due_bursts()
	var fire_down: bool = Input.is_action_pressed("fire")
	if resumed:
		# Der Tastendruck dieses Bildes hat ein Menü geschlossen: Er zählt nicht als Spieleingabe.
		_fire_blocked_until_release = fire_down
		_clear_fire_buffers()
		return
	if _fire_blocked_until_release and not fire_down:
		_fire_blocked_until_release = false
	if not _fire_blocked_until_release:
		_handle_fire_input(fire_down, delta)
	if Input.is_action_just_pressed("reload"):
		start_reload()
	_reload_empty_hands()


# --- Öffentliche Schnittstelle ---------------------------------------------------------------


## Die gehaltenen Waffen in Reihenfolge der Hände (Index 0 = linke Hand). Je Hand:
##   { "hand": int, "uid": int, "id": String, "level": int, "hands": int, "mag": int,
##     "magazine": int, "reloading": bool, "reload_left": float, "reload_duration": float }
func get_hands() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in _hands.size():
		var hand: Hand = _hands[index]
		result.append({
			"hand": index, "uid": hand.uid, "id": hand.id, "level": hand.level, "hands": hand.hands,
			"mag": hand.state.mag, "magazine": hand.state.magazine_size(),
			"reloading": hand.state.is_reloading, "reload_left": hand.state.reload_left,
			"reload_duration": hand.state.reload_duration(),
		})
	return result


## WeaponState der gehaltenen Waffe mit dieser uid, null wenn sie nicht in der Hand ist.
func get_state_of(uid: int) -> WeaponState:
	for hand: Hand in _hands:
		if hand.uid == uid:
			return hand.state
	return null


## Streuung der gehaltenen Waffe mit dieser uid in Grad (halber Winkel), so wie der nächste Schuss
## sie benutzt: mit Teleprompter mal Balance.SCOPE_SPREAD_FACTOR. 0, wenn sie nicht in der Hand ist.
func get_spread_of(uid: int) -> float:
	for hand: Hand in _hands:
		if hand.uid == uid:
			return _spread_of(hand)
	return 0.0


## Liest für jede gehaltene Waffe Magazingröße und Schussrate neu aus ihren Gegenständen
## (Überlänge, Schnelldurchlauf) und meldet die Magazine. Das geschieht bei jedem Abgleich von
## selbst. Nötig ist der Aufruf nur, wenn Werte von Hand gesetzt wurden (Game.upgrades.add_levels)
## und sofort gelten sollen, noch vor dem nächsten Schuss oder Nachladen.
func refresh_weapon_stats() -> void:
	for index: int in _hands.size():
		_apply_item_stats(_hands[index])
		_emit_ammo(index)


## Schießt mit jeder gehaltenen Waffe, die gerade schießen kann, ohne Eingabe zu prüfen (auch für
## Tests). Gibt true zurück, wenn mindestens ein Schuss fiel. Eine leere Waffe beginnt nachzuladen.
## Schießt nur im State PLAYING und solange der Spieler lebt.
func try_fire() -> bool:
	if not _can_act() or not _player.is_inside_tree():
		return false
	var fired: bool = false
	for hand: Hand in _hands.duplicate():
		if _fire_hand(hand):
			fired = true
	return fired


## Lädt jede gehaltene Waffe nach, deren Magazin nicht voll ist. Sendet je Hand
## hand_reload_started, für die linke Hand dazu reload_started.
func start_reload() -> void:
	if not _can_act():
		return
	for hand: Hand in _hands.duplicate():
		_start_reload_hand(hand)


## Lädt gerade irgendeine Hand nach?
func is_reloading() -> bool:
	for hand: Hand in _hands:
		if hand.state.is_reloading:
			return true
	return false


## Bild von Dauerstrahl oder Flamme der Hand mit diesem Index (beam_fx.gd oder flame_fx.gd, beide
## mit is_active(), get_from(), get_to()). null, solange die Hand noch keinen Stoß abgegeben hat
## oder ihre Waffe weder Strahl noch Flamme ist.
func get_stream(hand_index: int = 0) -> Node3D:
	if hand_index < 0 or hand_index >= _hands.size():
		return null
	var stream: Node3D = _hands[hand_index].stream
	return stream if is_instance_valid(stream) else null


# --- Helfer für Tests und Werkzeuge (alte Namen) ---------------------------------------------


## Hält der Spieler eine Waffe mit dieser ID?
func has_weapon(weapon_id: String) -> bool:
	return _find_hand(weapon_id) != null


## Gibt dem Spieler genau diese Waffe in die Hand (siehe equip). Unbekannte IDs werden ignoriert.
func give_weapon(weapon_id: String) -> void:
	equip([weapon_id] as Array[String])


## Gibt dem Spieler genau diese Waffen in die Hand, über den Rucksack: Alle eingeräumten Waffen
## kommen in die Ablage, jede gewünschte Waffe wird als gewöhnlicher Gegenstand an die erste
## passende Stelle geräumt (eine gleiche gewöhnliche Waffe aus der Ablage wird dafür wieder
## benutzt), danach Game.sync_build(). Passt eine Waffe nicht in den Rucksack, wächst er um
## kleine Rucksack-Teile. Waffen, für die keine Hand mehr frei ist, und unbekannte IDs entfallen.
func equip(weapon_ids: Array[String]) -> void:
	var wanted: Array[String] = []
	for weapon_id: String in weapon_ids:
		if WeaponDefs.has(weapon_id) and ItemDefs.is_weapon(weapon_id):
			wanted.append(weapon_id)
	if wanted.is_empty():
		return
	var backpack: BackpackState = Game.backpack
	for entry: Dictionary in backpack.placed_items():
		if ItemDefs.is_weapon(String(entry["id"])):
			backpack.store(int(entry["uid"]))
	for weapon_id: String in wanted:
		var uid: int = _stored_common_weapon(backpack, weapon_id)
		var is_new: bool = uid == -1
		if is_new:
			uid = backpack.add_item(weapon_id, 1)
		if uid == -1:
			continue
		if not backpack.has_free_hands(uid) or not _place_with_room(backpack, uid):
			if is_new:
				backpack.remove(uid)
	Game.sync_build()


## Es gibt keinen Waffenwechsel mehr: tut nichts.
func switch_to(_weapon_id: String) -> void:
	pass


## Füllt das Magazin jeder gehaltenen Waffe mit dieser ID. Ein laufendes Nachladen ist damit
## erledigt (hand_reload_finished).
func refill_ammo(weapon_id: String) -> void:
	for index: int in _hands.size():
		var hand: Hand = _hands[index]
		if hand.id != weapon_id:
			continue
		var was_reloading: bool = hand.state.is_reloading
		_apply_item_stats(hand)
		hand.state.refill()
		if was_reloading:
			_emit_reload_finished(index)
		_emit_ammo(index)


## WeaponState der ersten gehaltenen Waffe mit dieser ID, null wenn keine gehalten wird.
func get_state(weapon_id: String) -> WeaponState:
	var hand: Hand = _find_hand(weapon_id)
	return hand.state if hand != null else null


## ID der Waffe in der linken Hand.
func get_current_weapon_id() -> String:
	return _hands[0].id if not _hands.is_empty() else ""


## IDs der gehaltenen Waffen in Reihenfolge der Hände.
func get_owned_weapon_ids() -> Array[String]:
	var ids: Array[String] = []
	for hand: Hand in _hands:
		ids.append(hand.id)
	return ids


# --- Abgleich mit dem Rucksack ---------------------------------------------------------------


func _on_run_started() -> void:
	_sync_loadout(true)


func _on_build_changed() -> void:
	_sync_loadout(false)


## Richtet die Hände nach Game.loadout ein. fresh = true: alle Waffen neu mit vollem Magazin
## (neuer Lauf). Sonst behalten Waffen, deren uid bleibt, ihren Zustand. Magazingröße und
## Schussrate werden für jede Hand neu aus ihren Gegenständen gelesen: Eine Waffe, die bleibt,
## behält ihre Kugeln (höchstens die neue Größe), eine neue beginnt mit vollem Magazin.
func _sync_loadout(fresh: bool) -> void:
	var known: Dictionary = {}
	if not fresh:
		for hand: Hand in _hands:
			known[hand.uid] = hand
	var old_left_id: String = get_current_weapon_id()
	var hands: Array[Hand] = []
	for entry: Dictionary in _loadout_entries():
		var uid: int = int(entry.get("uid", 0))
		var id: String = String(entry.get("id", ""))
		if not WeaponDefs.has(id) or hands.size() >= Balance.PLAYER_HANDS:
			continue
		var hand: Hand = known.get(uid, null) as Hand
		if hand == null or hand.id != id:
			hand = Hand.new()
			hand.uid = uid
			hand.id = id
			hand.state = WeaponState.new(id)
			_apply_item_stats(hand)
			hand.state.refill()
		else:
			_apply_item_stats(hand)
		hand.level = int(entry.get("level", 1))
		hand.hands = int(entry.get("hands", 1))
		hand.fire_buffer_left = 0.0
		hands.append(hand)
	if hands.is_empty():
		var fallback: Hand = Hand.new()
		fallback.id = WeaponDefs.START_WEAPON
		fallback.state = WeaponState.new(fallback.id)
		_apply_item_stats(fallback)
		fallback.state.refill()
		hands.append(fallback)
	# Strahl oder Flamme einer Waffe, die nicht mehr gehalten wird, verschwindet mit ihr.
	for old_hand: Hand in _hands:
		if not hands.has(old_hand):
			_free_stream(old_hand)
	_hands = hands
	var view_model: Node = _view_model()
	if view_model != null and view_model.has_method("set_loadout"):
		view_model.call("set_loadout", get_hands())
	Events.loadout_changed.emit()
	if fresh or get_current_weapon_id() != old_left_id:
		Events.weapon_changed.emit(get_current_weapon_id())
	for index: int in _hands.size():
		_emit_ammo(index)


## Game.loadout, ersatzweise (vor dem ersten Lauf ist es leer) die Dienstpistole mit der uid 0.
func _loadout_entries() -> Array[Dictionary]:
	if not Game.loadout.is_empty():
		return Game.loadout
	return [{"uid": 0, "id": WeaponDefs.START_WEAPON, "level": 1, "hands": 1}]


## Überlänge und Schnelldurchlauf dieser Waffe in ihren Zustand schreiben. Die Kugeln im Magazin
## bleiben, höchstens aber die neue Magazingröße.
func _apply_item_stats(hand: Hand) -> void:
	hand.state.set_magazine_bonus(Game.bullet_value(hand.uid, "big_mag", "bonus"))
	hand.state.fire_rate_factor = 1.0 + maxf(Game.bullet_value(hand.uid, "fire_rate", "bonus"), 0.0)


## Streuung dieser Hand in Grad: die der Waffe, mit Teleprompter kleiner.
func _spread_of(hand: Hand) -> float:
	return WeaponDefs.spread_deg(hand.id, Game.bullet_level(hand.uid, "scope") > 0)


## uid einer gewöhnlichen Waffe mit dieser ID in der Ablage, -1 wenn dort keine liegt.
func _stored_common_weapon(backpack: BackpackState, weapon_id: String) -> int:
	for entry: Dictionary in backpack.storage_items():
		# Eine kaputte Waffe lässt sich nicht einräumen (Abschnitt 26): nicht wiederverwenden.
		if String(entry["id"]) == weapon_id and int(entry["level"]) == 1 and not bool(entry.get("broken", false)):
			return int(entry["uid"])
	return -1


## Räumt den Gegenstand an die erste passende Stelle. Passt er nirgends, wächst der Rucksack um
## kleine Rucksack-Teile, bis er passt (höchstens EQUIP_MAX_BAGS).
func _place_with_room(backpack: BackpackState, uid: int) -> bool:
	if backpack.auto_place(uid):
		return true
	for _attempt: int in EQUIP_MAX_BAGS:
		var bag_uid: int = backpack.add_item("bag_small")
		if bag_uid == -1:
			return false
		if not backpack.auto_place(bag_uid):
			backpack.remove(bag_uid)
			return false
		if backpack.auto_place(uid):
			return true
	return false


# --- Eingabe, Schuss, Nachladen --------------------------------------------------------------


func _can_act() -> bool:
	if Game.state != Game.State.PLAYING or not is_instance_valid(_player):
		return false
	return not bool(_player.get("is_dead"))


## Lässt für alle gehaltenen Waffen Zeit vergehen (Schussfolge, Nachladen).
func _tick_states(delta: float) -> void:
	for index: int in _hands.size():
		if _hands[index].state.tick(delta):
			_emit_reload_finished(index)
			_emit_ammo(index)


## Abzug auswerten, je Hand für sich: Dauerfeuer bei automatischen Waffen (bei langen Bildern
## mehrere Schüsse je Bild, höchstens Balance.FIRE_MAX_SHOTS_PER_FRAME), sonst ein Schuss je
## Druck. Ein knapp zu früh gedrückter Abzug zählt noch (Balance.FIRE_BUFFER_TIME), so fühlt sich
## schnelles Klicken gut an.
func _handle_fire_input(fire_down: bool, delta: float) -> void:
	var just_pressed: bool = Input.is_action_just_pressed("fire")
	for hand: Hand in _hands.duplicate():
		if bool(hand.state.get_def()["automatic"]):
			hand.fire_buffer_left = 0.0
			if fire_down:
				# Ist ein Bild länger als die Schussfolge (niedrige Bildrate, Ruckler), fallen mehrere
				# Schüsse in diesem Bild. So stimmt die Schussrate bei jeder Bildrate.
				for _shot: int in Balance.FIRE_MAX_SHOTS_PER_FRAME:
					if not _fire_hand(hand):
						break
			continue
		if just_pressed:
			hand.fire_buffer_left = Balance.FIRE_BUFFER_TIME
		if hand.fire_buffer_left <= 0.0:
			continue
		if _fire_hand(hand):
			hand.fire_buffer_left = 0.0
		else:
			hand.fire_buffer_left -= delta


func _clear_fire_buffers() -> void:
	for hand: Hand in _hands:
		hand.fire_buffer_left = 0.0


## Eine leere Waffe lädt von selbst nach.
func _reload_empty_hands() -> void:
	for hand: Hand in _hands.duplicate():
		if hand.state.needs_reload():
			_start_reload_hand(hand)


## Ein Schuss dieser Hand. Gibt false zurück, wenn sie gerade nicht schießen kann (ein leeres
## Magazin beginnt dann nachzuladen). Bei einer Salvenwaffe ist das der erste Schuss der Salve,
## die übrigen folgen über _fire_due_bursts.
func _fire_hand(hand: Hand) -> bool:
	var index: int = _hands.find(hand)
	if index < 0:
		return false
	var state: WeaponState = hand.state
	_apply_item_stats(hand)
	if not state.can_fire():
		if state.needs_reload():
			_start_reload_hand(hand)
		return false
	var first_of_magazine: bool = state.mag >= state.magazine_size()
	state.fire()
	_release_shot(hand, index, first_of_magazine)
	return true


## Gibt für jede Hand die fälligen Schüsse einer laufenden Salve ab (nach _tick_states). Bei
## langen Bildern fallen mehrere im selben Bild, höchstens der Rest der Salve.
func _fire_due_bursts() -> void:
	for hand: Hand in _hands.duplicate():
		for _shot: int in hand.state.burst_size():
			var index: int = _hands.find(hand)
			if index < 0 or not hand.state.fire_burst_shot():
				break
			# Ein Schuss mitten in der Salve ist nie der erste des Magazins.
			_release_shot(hand, index, false)


## Wenn nicht gehandelt werden darf (Lauf zu Ende, Spieler tot, Menü): Salven brechen ab, Strahl
## und Flamme gehen aus.
func _stop_action() -> void:
	for hand: Hand in _hands:
		hand.state.cancel_burst()
		_stop_stream(hand)


## Lässt einen Schuss dieser Hand los, dessen Kugel schon aus dem Magazin genommen ist: Erst
## fliegen die normalen Kugeln, dann die Zusatzkugeln der Zugabe (sie kosten keine Munition).
## Danach Rückstoß, weapon_fired, hand_ammo_changed und bei leerem Magazin das Nachladen.
## first_of_magazine: Das Magazin war vor dem Schuss voll (Eröffnungsgag).
func _release_shot(hand: Hand, index: int, first_of_magazine: bool) -> void:
	var state: WeaponState = hand.state
	var shot: Shot = Shot.new()
	shot.index = index
	shot.hand = hand
	shot.def = state.get_def()
	shot.mode = WeaponDefs.mode(hand.id)
	shot.falloff = shot.mode != WeaponDefs.MODE_BEAM
	shot.score_each = shot.mode != WeaponDefs.MODE_BEAM and shot.mode != WeaponDefs.MODE_FLAME
	shot.from = _aim_origin()
	shot.aim = _aim_direction()
	shot.muzzle = _muzzle_position(index, shot.from)
	shot.fx_root = Fx.root_of(self)
	shot.pierce_targets = maxi(0, WeaponDefs.pierce(hand.id) + int(Game.bullet_value(hand.uid, "pierce", "targets")))
	shot.spread_deg = _spread_of(hand)
	shot.multiplier = Game.weapon_damage_multiplier(hand.uid)
	shot.crit_chance = Game.bullet_value(hand.uid, "crit", "chance")
	shot.headshot_bonus = Game.bullet_value(hand.uid, "scope", "headshot_bonus")
	shot.arc_jumps = WeaponDefs.arc_jumps(hand.id)
	shot.arc_factor = WeaponDefs.arc_factor(hand.id)
	shot.arc_radius = WeaponDefs.arc_radius(hand.id)
	if not shot.score_each:
		shot.fx_strength = FX_STRENGTH_STREAM
	elif int(shot.def["pellets"]) > 1:
		shot.fx_strength = FX_STRENGTH_PELLETS
	if first_of_magazine and Game.bullet_level(hand.uid, "opener") > 0:
		shot.opener = true
		shot.multiplier *= 1.0 + maxf(Game.bullet_value(hand.uid, "opener", "bonus"), 0.0)
	if state.mag <= 0 and Game.bullet_level(hand.uid, "punchline") > 0:
		shot.punchline_damage = Game.bullet_value(hand.uid, "punchline", "damage") * Game.effect_factor()
	var extra_shots: int = maxi(0, roundi(Game.bullet_value(hand.uid, "extra_shot", "shots")))
	var extra_factor: float = Game.bullet_value(hand.uid, "extra_shot", "damage_factor")
	for _pellet: int in int(shot.def["pellets"]):
		_fire_projectile(shot, false, 1.0)
	for _extra: int in extra_shots:
		_fire_projectile(shot, true, extra_factor)
	if shot.mode == WeaponDefs.MODE_BEAM or shot.mode == WeaponDefs.MODE_FLAME:
		_show_stream(hand, index)
	var view_model: Node = _view_model()
	if view_model != null and view_model.has_method("play_fire"):
		view_model.call("play_fire", index)
	Events.weapon_fired.emit(hand.id)
	# Ein Treffer kann den Lauf beendet oder die Bewaffnung geändert haben.
	index = _hands.find(hand)
	if index >= 0:
		_emit_ammo(index)
		if state.needs_reload():
			_start_reload_hand(hand)


## Eine Kugel dieses Schusses, je nach Schussart: Granate, Flammenstoß oder Strahl (Kugel und
## Dauerstrahl). extra und extra_factor wie bei _fire_pellet.
func _fire_projectile(shot: Shot, extra: bool, extra_factor: float) -> void:
	match shot.mode:
		WeaponDefs.MODE_GRENADE:
			_launch_grenade(shot, extra, extra_factor)
		WeaponDefs.MODE_FLAME:
			_fire_flame(shot, extra, extra_factor)
		_:
			_fire_pellet(shot, extra, extra_factor)


## Beginnt das Nachladen dieser Hand, wenn es möglich ist. Verstärker verkürzen es.
func _start_reload_hand(hand: Hand) -> void:
	var index: int = _hands.find(hand)
	if index < 0 or not _can_act():
		return
	_apply_item_stats(hand)
	hand.state.reload_factor = Game.weapon_reload_multiplier(hand.uid)
	if not hand.state.start_reload():
		return
	var duration: float = hand.state.reload_duration()
	Events.hand_reload_started.emit(index, duration)
	if index == 0:
		Events.reload_started.emit(hand.id, duration)


func _emit_ammo(index: int) -> void:
	var state: WeaponState = _hands[index].state
	Events.hand_ammo_changed.emit(index, state.mag, state.magazine_size())
	if index == 0:
		Events.ammo_changed.emit(state.mag, WeaponDefs.INFINITE_RESERVE)


func _emit_reload_finished(index: int) -> void:
	Events.hand_reload_finished.emit(index)
	if index == 0:
		Events.reload_finished.emit(_hands[index].id)


func _find_hand(weapon_id: String) -> Hand:
	for hand: Hand in _hands:
		if hand.id == weapon_id:
			return hand
	return null


## Die sichtbaren Waffen vor der Kamera, null wenn es sie nicht gibt.
func _view_model() -> Node:
	if not is_instance_valid(_player):
		return null
	return _player.get_node_or_null(VIEW_MODEL_PATH)


## Start des Schuss-Strahls: das Auge des Spielers.
func _aim_origin() -> Vector3:
	if _player.has_method("get_eye_position"):
		return _player.call("get_eye_position")
	return _player.global_position


## Richtung des Schuss-Strahls: die Blickrichtung der Kamera.
func _aim_direction() -> Vector3:
	if _player.has_method("get_aim_direction"):
		return _player.call("get_aim_direction")
	return -_player.global_transform.basis.z.normalized()


## Startpunkt der Leuchtspur: die Mündung der sichtbaren Waffe dieser Hand, ersatzweise das Auge.
func _muzzle_position(index: int, fallback: Vector3) -> Vector3:
	var view_model: Node = _view_model()
	if view_model != null and view_model.is_inside_tree() and view_model.has_method("get_muzzle_position"):
		return view_model.call("get_muzzle_position", index)
	return fallback


## Eine Kugel: Strahl vom Auge in Blickrichtung mit Streuung. Trifft der Reihe nach Zombies,
## bis der Durchschlag verbraucht ist oder die Kugel in der Welt einschlägt. Ein explodierendes
## Geschoss endet am ersten Einschlag (Zombie oder Welt) mit einer Explosion.
## extra = true: Zusatzkugel der Zugabe. Sie fliegt leicht versetzt, macht nur den Anteil
## extra_factor des Schadens und hat eine hellere Leuchtspur. Je Kugel wird einmal gewürfelt, ob
## sie kritisch trifft: Das gilt dann für jeden Zombie, den sie trifft, und für ihre Explosion.
## Der Dauerstrahl (MODE_BEAM) läuft hier mit: Er geht ohne Schadensabfall durch alle Zombies bis
## zur Wand und hat keine Leuchtspur (nur seine Zusatzkugel zeigt eine).
func _fire_pellet(shot: Shot, extra: bool, extra_factor: float) -> void:
	var hand: Hand = shot.hand
	var from: Vector3 = shot.from
	var fx_root: Node = shot.fx_root
	var direction: Vector3 = _apply_spread(shot.aim, shot.spread_deg)
	if extra:
		direction = _apply_spread(direction, WeaponDefs.EXTRA_SHOT_SPREAD_DEG)
	var crit: bool = _roll_crit(shot.crit_chance)
	# Anteil der Zusatzkugel und kritischer Treffer zusammen (ohne beides genau 1,0).
	var bonus_factor: float = WeaponDefs.bonus_damage_factor(extra_factor if extra else 1.0, crit)
	var to: Vector3 = from + direction * Balance.WEAPON_RANGE
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if _player is CollisionObject3D:
		exclude.append((_player as CollisionObject3D).get_rid())
	var color: Color = TRACER_COLORS.get(hand.id, Color.YELLOW)
	if extra:
		color = color.lerp(Color.WHITE, EXTRA_TRACER_WHITEN)
	var explosive: bool = float(shot.def.get("explosion_radius", 0.0)) > 0.0
	var is_beam: bool = shot.mode == WeaponDefs.MODE_BEAM
	var end: Vector3 = to
	var targets_hit: int = 0
	for _step: int in (BEAM_MAX_RAY_STEPS if is_beam else MAX_RAY_STEPS):
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, to, Balance.MASK_SHOT, exclude)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var hit_position: Vector3 = hit["position"]
		var collider: Object = hit["collider"]
		var zombie: Node3D = _find_zombie(collider)
		if zombie == null:
			if _is_zombie_body(collider):
				# Leiche oder sterbender Zombie im Weg: die Kugel fliegt hindurch.
				exclude.append(hit["rid"])
				continue
			end = hit_position
			if explosive:
				_explode(shot, hit_position - direction * EXPLOSION_BACKOFF, 0, bonus_factor, extra, crit)
			elif not is_beam:
				Fx.impact(fx_root, hit_position, hit["normal"], color, shot.fx_strength)
			_try_punchline(shot, hit_position - direction * EXPLOSION_BACKOFF)
			break
		exclude.append(hit["rid"])
		# Die Nummer merken: Nach take_damage kann der Zombie schon weg sein.
		var zombie_id: int = zombie.get_instance_id()
		var headshot: bool = zombie.has_method("is_headshot") and bool(zombie.call("is_headshot", hit_position))
		var damage: float = WeaponDefs.bullet_damage(hand.id, headshot, targets_hit if shot.falloff else 0,
			shot.headshot_bonus) * shot.multiplier * bonus_factor
		_deal_hit(shot, zombie, damage, _hit_info(shot, hit_position, headshot, extra, crit))
		targets_hit += 1
		if not explosive:
			Fx.splatter(fx_root, hit_position, direction, headshot, crit, shot.fx_strength)
		if explosive:
			end = hit_position
			_explode(shot, hit_position - direction * EXPLOSION_BACKOFF, zombie_id, bonus_factor, extra, crit)
		_try_punchline(shot, hit_position - direction * EXPLOSION_BACKOFF)
		if explosive:
			break
		if targets_hit > shot.pierce_targets:
			end = hit_position
			break
	if is_beam and not extra:
		# Der Dauerstrahl hat sein eigenes Bild (_show_stream), keine Leuchtspur.
		return
	var trail: Vector3 = end - shot.muzzle
	Fx.tracer(fx_root, shot.muzzle + trail.normalized() * minf(TRACER_LEAD, trail.length() * TRACER_LEAD_SHARE), end, color)
	if shot.arc_jumps > 0:
		# Der Schuss des Kurzschlusses ist selbst ein Blitz (ab ARC_SHOT_LEAD vor der Mündung).
		var path: Vector3 = end - shot.muzzle
		var lead: float = minf(ARC_SHOT_LEAD, path.length() * 0.5)
		Fx.lightning(fx_root, PackedVector3Array([shot.muzzle + path.normalized() * lead, end]))


## Treffer-Info eines Kugeltreffers (auch Flammenstoß, Strahl und direkter Granatentreffer).
func _hit_info(shot: Shot, hit_position: Vector3, headshot: bool, extra: bool, crit: bool) -> Dictionary:
	return {
		"source": "bullet",
		"headshot": headshot,
		"weapon_id": shot.hand.id,
		"weapon": shot.hand.id,
		"weapon_uid": shot.hand.uid,
		"hand": shot.index,
		"hit_position": hit_position,
		"extra": extra,
		"crit": crit,
		"mode": shot.mode,
		"opener": shot.opener,
	}


## Ein Kugeltreffer: erst zombie.take_damage, danach Events.bullet_hit, danach der eingebaute
## Blitz der Waffe.
##
## Treffer-Punkte: Game gibt für jeden Schaden mit source "bullet" Balance.POINTS_BULLET_HIT.
## Flamme und Strahl treffen mit jedem Stoß alle Zombies im Kegel oder in der Linie: Zählte jeder
## davon, gäbe ein Stoß durch zehn Zombies zehnmal Punkte, 15 bis 20 Mal je Sekunde. Deshalb zählt
## bei ihnen (score_each = false) nur der erste Treffer je Schuss als "bullet". Jeder weitere
## nimmt denselben Schaden mit der Schussart als source ("flame" oder "beam"), also ohne
## Treffer-Punkte. So gibt es höchstens einen Punkte-Treffer je Stoß: 15 je Sekunde bei der
## Flamme, 20 beim Strahl, so viele wie bei einer Kugelwaffe mit derselben Schussfolge (die
## Applausmaschine hat 20). bullet_hit trägt für alle Treffer source "bullet", damit die
## Gegenstände auf der Waffe bei jedem Treffer wirken. In der Info steht "scored".
func _deal_hit(shot: Shot, zombie: Node3D, damage: float, info: Dictionary) -> void:
	var scored: bool = shot.score_each or not shot.scored
	shot.scored = true
	info["scored"] = scored
	var damage_info: Dictionary = info
	if not scored:
		damage_info = info.duplicate()
		damage_info["source"] = shot.mode
	# Die Körpermitte vor dem Schaden merken: Danach kann der Zombie schon weg sein.
	var origin: Vector3 = _center_of(zombie) if shot.arc_jumps > 0 else Vector3.ZERO
	zombie.call("take_damage", damage, damage_info)
	if is_instance_valid(zombie):
		# Nur fürs Bild: Die Trefferzahl dieses Treffers zeigt Kopftreffer und kritischen Treffer.
		Fx.hint_number(damage, bool(info["headshot"]), bool(info["crit"]))
		Events.bullet_hit.emit(zombie, damage, info)
		Fx.clear_number_hint()
	if shot.arc_jumps > 0:
		_cast_arc(shot, zombie, origin, damage, bool(info["extra"]), bool(info["crit"]))


## Eingebauter Blitz (Kurzschluss): springt vom getroffenen Zombie auf bis zu arc_jumps weitere,
## jeweils zum nächsten noch nicht getroffenen im Umkreis arc_radius um den vorigen. Jeder bekommt
## arc_factor des Treffer-Schadens mit source "lightning". Der getroffene Zombie selbst bekommt
## nichts dazu.
func _cast_arc(shot: Shot, origin_zombie: Node3D, origin: Vector3, hit_damage: float, extra: bool, crit: bool) -> void:
	var damage: float = hit_damage * shot.arc_factor
	if damage <= 0.0 or shot.arc_radius <= 0.0 or not is_inside_tree():
		return
	# Erst die ganze Kette festlegen, dann Schaden verteilen: So ändert ein Tod mitten in der Kette
	# nichts an ihrem Weg. Die Listen sind ohne Typ (siehe _explode).
	var candidates: Array = get_tree().get_nodes_in_group("zombies")
	candidates.erase(origin_zombie)
	var chain: Array = []
	var points: PackedVector3Array = PackedVector3Array([origin])
	var current: Vector3 = origin
	for _jump: int in shot.arc_jumps:
		var best: Node3D = null
		var best_distance: float = shot.arc_radius
		for entry: Variant in candidates:
			if not _is_alive(entry):
				continue
			var candidate: Node3D = entry
			var distance: float = current.distance_to(_center_of(candidate))
			if distance <= best_distance:
				best = candidate
				best_distance = distance
		if best == null:
			break
		candidates.erase(best)
		chain.append(best)
		current = _center_of(best)
		points.append(current)
	if chain.is_empty():
		return
	Fx.lightning(shot.fx_root, points)
	for i: int in chain.size():
		if not _is_alive(chain[i]):
			continue
		var target: Node3D = chain[i]
		Fx.damage_number(shot.fx_root, points[i + 1] + Vector3(0.0, ARC_NUMBER_HEIGHT, 0.0), damage, ARC_NUMBER_COLOR)
		target.call("take_damage", damage, {
			"source": "lightning",
			"weapon_id": shot.hand.id,
			"weapon": shot.hand.id,
			"weapon_uid": shot.hand.uid,
			"hand": shot.index,
			"hit_position": points[i + 1],
			"extra": extra,
			"crit": crit,
			"arc": true,
		})


## Ein Flammenstoß: trifft alle lebenden Zombies im Kegel vor dem Auge (Länge WeaponDefs.reach,
## halber Winkel WeaponDefs.cone_deg) mit freier Sicht, von nah nach fern, und setzt jeden in
## Brand. Ein Wurf für den kritischen Treffer gilt für den ganzen Stoß. Kopftreffer gibt es nicht.
func _fire_flame(shot: Shot, extra: bool, extra_factor: float) -> void:
	var hand: Hand = shot.hand
	var crit: bool = _roll_crit(shot.crit_chance)
	var bonus_factor: float = WeaponDefs.bonus_damage_factor(extra_factor if extra else 1.0, crit)
	var damage: float = WeaponDefs.bullet_damage(hand.id, false) * shot.multiplier * bonus_factor
	var burn_dps: float = WeaponDefs.burn_dps(hand.id)
	var burn_time: float = WeaponDefs.burn_time(hand.id)
	var first_hit: bool = true
	for entry: Dictionary in _zombies_in_cone(shot.from, shot.aim, WeaponDefs.reach(hand.id), WeaponDefs.cone_deg(hand.id)):
		# Ein früherer Treffer desselben Stoßes kann diesen Zombie schon getötet haben (Kettenreaktion).
		if not _is_alive(entry["zombie"]):
			continue
		var zombie: Node3D = entry["zombie"]
		var hit_position: Vector3 = entry["point"]
		_deal_hit(shot, zombie, damage, _hit_info(shot, hit_position, false, extra, crit))
		Fx.splatter(shot.fx_root, hit_position, shot.aim, false, crit, shot.fx_strength)
		if burn_dps > 0.0 and burn_time > 0.0 and _is_alive(zombie) and zombie.has_method("apply_burn"):
			zombie.call("apply_burn", burn_dps, burn_time)
		if first_hit:
			first_hit = false
			_try_punchline(shot, hit_position)
	# Ohne Treffer zündet die Schlusspointe am Ende der Flamme.
	_try_punchline(shot, _stream_end(shot.from, shot.aim, WeaponDefs.reach(hand.id)) - shot.aim * EXPLOSION_BACKOFF)


## Lebende Zombies im Kegel, von nah nach fern. Je Zombie { "zombie": Node3D, "point": Vector3,
## "along": float }: point ist der Punkt seiner Körperachse (Füße bis Kopf), der der Mittellinie
## des Kegels am nächsten liegt, along dessen Abstand entlang der Mittellinie. Ein Zombie zählt,
## wenn sein Körper (Achse plus Körperradius) in den Kegel ragt und vom Auge aus freie Sicht auf
## point besteht (nur die Welt verdeckt).
func _zombies_in_cone(from: Vector3, aim: Vector3, reach: float, half_angle_deg: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if reach <= 0.0 or half_angle_deg <= 0.0 or not is_inside_tree():
		return found
	var slope: float = tan(deg_to_rad(half_angle_deg))
	var tip: Vector3 = from + aim * reach
	var candidates: Array = get_tree().get_nodes_in_group("zombies")
	for candidate: Variant in candidates:
		if not _is_alive(candidate):
			continue
		var zombie: Node3D = candidate
		var feet: Vector3 = zombie.global_position
		var head: Vector3 = feet + Vector3(0.0, _body_height(zombie), 0.0)
		var closest: PackedVector3Array = Geometry3D.get_closest_points_between_segments(from, tip, feet, head)
		var point: Vector3 = closest[1]
		var along: float = (point - from).dot(aim)
		var radius: float = _body_radius(zombie)
		if along <= 0.0 or along > reach + radius:
			continue
		var beside: float = (point - (from + aim * along)).length()
		if beside - radius > along * slope:
			continue
		if not _has_line_of_sight(from, point):
			continue
		found.append({"zombie": zombie, "point": point, "along": along})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["along"]) < float(b["along"]))
	return found


## Startet eine Granate: Sie fliegt vom Auge in Blickrichtung (mit Streuung) im Bogen und meldet
## ihren Einschlag an _on_grenade_hit. Der Wurf für den kritischen Treffer fällt beim Abschuss.
func _launch_grenade(shot: Shot, extra: bool, extra_factor: float) -> void:
	if not is_instance_valid(shot.fx_root) or not shot.fx_root.is_inside_tree():
		return
	var hand: Hand = shot.hand
	var direction: Vector3 = _apply_spread(shot.aim, shot.spread_deg)
	if extra:
		direction = _apply_spread(direction, WeaponDefs.EXTRA_SHOT_SPREAD_DEG)
	var crit: bool = _roll_crit(shot.crit_chance)
	var bonus_factor: float = WeaponDefs.bonus_damage_factor(extra_factor if extra else 1.0, crit)
	var color: Color = TRACER_COLORS.get(hand.id, Color.YELLOW)
	if extra:
		color = color.lerp(Color.WHITE, EXTRA_TRACER_WHITEN)
	var exclude: Array[RID] = []
	if _player is CollisionObject3D:
		exclude.append((_player as CollisionObject3D).get_rid())
	var grenade: Node3D = Grenade.new()
	grenade.name = "Grenade"
	shot.fx_root.add_child(grenade)
	grenade.call("launch", shot.from, shot.muzzle, direction * WeaponDefs.projectile_speed(hand.id),
		WeaponDefs.projectile_gravity(hand.id), exclude,
		_on_grenade_hit.bind(shot, bonus_factor, extra, crit), color)


## Einschlag einer Granate (Aufruf aus grenade.gd). hit ist das Ergebnis des Strahls, leer wenn
## die Flugzeit abgelaufen ist. Gibt false zurück, wenn die Granate weiterfliegen soll (Leiche im
## Weg), sonst explodiert sie: Ein direkt getroffener Zombie bekommt den Kugelschaden, alle
## anderen im Radius den Explosionsschaden.
func _on_grenade_hit(hit: Dictionary, at: Vector3, direction: Vector3, shot: Shot, bonus_factor: float,
		extra: bool, crit: bool) -> bool:
	if not is_inside_tree():
		return true
	var center: Vector3 = at - direction * EXPLOSION_BACKOFF
	var direct_id: int = 0
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		var zombie: Node3D = _find_zombie(collider)
		if zombie == null and _is_zombie_body(collider):
			return false
		if zombie != null:
			direct_id = zombie.get_instance_id()
			var headshot: bool = zombie.has_method("is_headshot") and bool(zombie.call("is_headshot", at))
			var damage: float = WeaponDefs.bullet_damage(shot.hand.id, headshot, 0, shot.headshot_bonus) \
				* shot.multiplier * bonus_factor
			_deal_hit(shot, zombie, damage, _hit_info(shot, at, headshot, extra, crit))
			Fx.splatter(shot.fx_root, at, direction, headshot, crit, shot.fx_strength)
	_explode(shot, center, direct_id, bonus_factor, extra, crit)
	_try_punchline(shot, center)
	return true


## Schlusspointe: Der Schuss, der das Magazin geleert hat, explodiert an seinem ersten Einschlag.
## Einmal je Schuss, auch bei Schrot, Durchschlag und Zusatzkugeln. Trifft jeden Zombie im
## Radius, auch den direkt getroffenen.
func _try_punchline(shot: Shot, center: Vector3) -> void:
	if shot.punchline_damage <= 0.0 or shot.punchline_done:
		return
	shot.punchline_done = true
	_blast(shot, center, Balance.PUNCHLINE_RADIUS, shot.punchline_damage, 0, PUNCHLINE_COLOR, {
		"extra": false, "crit": false, "punchline": true,
	})


# --- Sichtbarer Strahl und sichtbare Flamme ---------------------------------------------------


## Zeigt Strahl oder Flamme dieser Hand (nach einem Stoß) und stellt die Restzeit neu.
func _show_stream(hand: Hand, index: int) -> void:
	if not is_instance_valid(hand.stream):
		var mode: String = WeaponDefs.mode(hand.id)
		if mode == WeaponDefs.MODE_BEAM:
			hand.stream = BeamFx.new()
		elif mode == WeaponDefs.MODE_FLAME:
			hand.stream = FlameFx.new()
			hand.stream.set("cone_deg", WeaponDefs.cone_deg(hand.id))
		else:
			return
		# Kind der Waffensteuerung (ein Knoten ohne Lage): Das Bild rechnet in Weltkoordinaten und
		# verschwindet mit dem Spieler.
		add_child(hand.stream)
	hand.stream_left = hand.state.fire_interval() * STREAM_LINGER_SHOTS
	_aim_stream(hand, index)


## Richtet Strahl oder Flamme neu aus: von der Mündung bis zum Ende in Blickrichtung.
func _aim_stream(hand: Hand, index: int) -> void:
	if not is_instance_valid(hand.stream) or not is_instance_valid(_player) or not _player.is_inside_tree():
		return
	var from: Vector3 = _aim_origin()
	hand.stream.call("aim", _muzzle_position(index, from), _stream_end(from, _aim_direction(), WeaponDefs.reach(hand.id)))


## Ende von Strahl oder Flamme: der erste Einschlag in der Welt in Blickrichtung, höchstens nach
## reach Metern. Zombies halten weder Strahl noch Flamme auf.
func _stream_end(from: Vector3, direction: Vector3, reach: float) -> Vector3:
	var to: Vector3 = from + direction * reach
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		return to
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, Balance.LAYER_WORLD)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit["position"]


## Lässt die Restzeit von Strahl und Flamme ablaufen: Solange sie läuft, folgt das Bild Mündung
## und Blick, danach geht es aus.
func _tick_streams(delta: float) -> void:
	for index: int in _hands.size():
		var hand: Hand = _hands[index]
		if hand.stream_left <= 0.0:
			continue
		hand.stream_left -= delta
		if hand.stream_left > 0.0:
			_aim_stream(hand, index)
		else:
			_stop_stream(hand)


func _stop_stream(hand: Hand) -> void:
	hand.stream_left = 0.0
	if is_instance_valid(hand.stream):
		hand.stream.call("stop")


func _free_stream(hand: Hand) -> void:
	hand.stream_left = 0.0
	if is_instance_valid(hand.stream):
		hand.stream.queue_free()
	hand.stream = null


## Würfelt, ob eine Kugel kritisch trifft (Zufall aus Game.rng). Ohne Chance wird nicht
## gewürfelt, damit ein Lauf ohne Glücksrad denselben Zufall hat wie vorher. Eine Chance von
## 1,0 trifft immer, auch dafür braucht es keinen Wurf.
func _roll_crit(chance: float) -> bool:
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	return Game.rng.randf() < chance


## Explosion eines Geschosses an center: Schaden (explosion_damage mal Waffen-Faktor mal
## bonus_factor) an allen lebenden Zombies im Radius mit freier Sichtlinie, außer dem direkt
## getroffenen (direct_id ist seine Instanz-Nummer, 0 = keiner). Der Spieler nimmt keinen Schaden.
## bonus_factor, extra und crit kommen von der Rakete: Anteil der Zusatzkugel, kritischer Treffer.
func _explode(shot: Shot, center: Vector3, direct_id: int, bonus_factor: float, extra: bool, crit: bool) -> void:
	var radius: float = float(shot.def.get("explosion_radius", 0.0))
	var damage: float = float(shot.def.get("explosion_damage", 0.0)) * shot.multiplier * bonus_factor
	_blast(shot, center, radius, damage, direct_id, EXPLOSION_COLOR, {"extra": extra, "crit": crit})


## Eine Explosion an center: Bild, Events.explosion und damage an allen lebenden Zombies im
## Radius mit freier Sichtlinie, außer dem mit der Instanz-Nummer direct_id (0 = keiner). Die
## Treffer-Info nennt source "explosion", die Waffe und dazu die Schlüssel aus marks.
func _blast(shot: Shot, center: Vector3, radius: float, damage: float, direct_id: int, color: Color,
		marks: Dictionary) -> void:
	var hand: Hand = shot.hand
	var fx_root: Node = shot.fx_root
	Fx.explosion(fx_root, center, radius, color)
	Events.explosion.emit(center, radius)
	if damage <= 0.0 or radius <= 0.0 or not is_inside_tree():
		return
	# Die Liste ist bewusst ohne Typ: Ein Zombie kann mitten in der Schleife sterben oder
	# verschwinden und darf dann nie in eine typisierte Variable wandern.
	var candidates: Array = get_tree().get_nodes_in_group("zombies")
	for candidate: Variant in candidates:
		if not _is_alive(candidate):
			continue
		var zombie: Node3D = candidate
		if zombie.get_instance_id() == direct_id:
			continue
		if center.distance_to(_closest_body_point(zombie, center)) > radius:
			continue
		var target: Vector3 = _center_of(zombie)
		if not _has_line_of_sight(center, target):
			continue
		var info: Dictionary = {
			"source": "explosion",
			"weapon_id": hand.id,
			"weapon": hand.id,
			"weapon_uid": hand.uid,
			"hand": shot.index,
			"hit_position": target,
		}
		info.merge(marks)
		zombie.call("take_damage", damage, info)


## Lebender Zombie zu einem getroffenen Collider: der Collider selbst oder ein Vorfahre in der
## Gruppe "zombies" mit take_damage. Sonst null.
func _find_zombie(collider: Object) -> Node3D:
	var node: Node = collider as Node
	while is_instance_valid(node):
		if node.is_in_group("zombies") and node.has_method("take_damage"):
			if bool(node.get("is_dead")):
				return null
			return node as Node3D
		node = node.get_parent()
	return null


## Liegt der Collider auf der Zombie-Lage? (auch tote Zombies, die die Gruppe schon verlassen haben)
func _is_zombie_body(collider: Object) -> bool:
	var body: CollisionObject3D = collider as CollisionObject3D
	if not is_instance_valid(body):
		return false
	return (body.collision_layer & Balance.LAYER_ZOMBIES) != 0


## Lebt dieser Zombie noch und hängt im Baum? Nimmt bewusst jeden Wert an, auch ein schon
## freigegebenes Objekt.
func _is_alive(candidate: Variant) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node3D:
		return false
	var zombie: Node3D = candidate
	return zombie.is_inside_tree() and not zombie.is_queued_for_deletion() \
		and not bool(zombie.get("is_dead")) and zombie.has_method("take_damage")


func _body_height(zombie: Node3D) -> float:
	var height: Variant = zombie.get("body_height")
	if height is float or height is int:
		return float(height)
	return Balance.ZOMBIE_HEIGHT


func _body_radius(zombie: Node3D) -> float:
	var radius: Variant = zombie.get("body_radius")
	if radius is float or radius is int:
		return float(radius)
	return Balance.ZOMBIE_RADIUS


## Körpermitte eines Zombies (Zielpunkt der Sichtlinie).
func _center_of(zombie: Node3D) -> Vector3:
	if zombie.has_method("get_center_position"):
		return zombie.call("get_center_position")
	return zombie.global_position + Vector3(0.0, _body_height(zombie) * 0.5, 0.0)


## Der Punkt auf der Körperachse des Zombies (Füße bis Kopf), der point am nächsten liegt.
func _closest_body_point(zombie: Node3D, point: Vector3) -> Vector3:
	var feet: Vector3 = zombie.global_position
	return Vector3(feet.x, clampf(point.y, feet.y, feet.y + _body_height(zombie)), feet.z)


## Freie Sicht zwischen zwei Punkten? Nur die Welt (Lage 1) verdeckt.
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		return true
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, Balance.LAYER_WORLD)
	return space.intersect_ray(query).is_empty()


## Lenkt die Richtung zufällig um höchstens spread_deg Grad ab, gleichmäßig über die Kreisfläche
## verteilt (Zufall aus Game.rng).
func _apply_spread(direction: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0:
		return direction
	var limit: float = tan(deg_to_rad(spread_deg))
	var side: Vector3 = direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up: Vector3 = side.cross(direction).normalized()
	var angle: float = Game.rng.randf() * TAU
	var radius: float = sqrt(Game.rng.randf()) * limit
	return (direction + side * (cos(angle) * radius) + up * (sin(angle) * radius)).normalized()


## Reine Optik: Ein Zombie, der stirbt (egal wodurch), platzt an seiner Körpermitte. Große
## Zombies platzen größer.
func _on_zombie_killed(zombie: Node3D, _info: Dictionary) -> void:
	if not is_instance_valid(zombie) or not zombie.is_inside_tree():
		return
	Fx.kill_burst(Fx.root_of(self), _center_of(zombie), _body_height(zombie) / Balance.ZOMBIE_HEIGHT)
