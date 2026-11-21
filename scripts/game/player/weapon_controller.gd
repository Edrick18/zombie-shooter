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
## Signale bei einem Schuss einer Hand: alle bullet_hit, dann weapon_fired, dann hand_ammo_changed,
## bei leerem Magazin zum Schluss hand_reload_started. Die alten Signale ammo_changed,
## reload_started, reload_finished und weapon_changed kommen weiter für die linke Hand,
## weapon_fired für jeden Schuss jeder Hand.

const Balance := preload("res://scripts/core/balance.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const WeaponState := preload("res://scripts/core/weapon_state.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

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
}
const EXPLOSION_COLOR: Color = Color(1.0, 0.5, 0.12)
const IMPACT_SIZE: float = 0.09
const IMPACT_TIME: float = 0.14
## Obergrenze der Strahl-Abschnitte je Kugel (Durchschlag plus Leichen im Weg).
const MAX_RAY_STEPS: int = 16
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


## Die Hände in Reihenfolge (Index 0 = linke Hand).
var _hands: Array[Hand] = []
var _player: Node3D = null

## Nach Pause oder Kistenwahl muss der Abzug erst losgelassen werden (der Klick galt dem Menü).
var _fire_blocked_until_release: bool = false
var _last_process_frame: int = -1
var _was_inactive: bool = true
var _impact_mesh: BoxMesh = null
var _impact_materials: Dictionary = {}


func _ready() -> void:
	_player = get_parent() as Node3D
	_last_process_frame = Engine.get_process_frames()
	Events.run_started.connect(_on_run_started)
	Events.build_changed.connect(_on_build_changed)
	_sync_loadout(true)


func _process(delta: float) -> void:
	var frame: int = Engine.get_process_frames()
	# Lücke in den Bildern = der Baum war pausiert (Kistenwahl, Pausemenü, Rucksack).
	var resumed: bool = frame - _last_process_frame > 1 or _was_inactive
	_last_process_frame = frame
	_tick_states(delta)
	if not _can_act():
		_was_inactive = true
		_clear_fire_buffers()
		return
	_was_inactive = false
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
## (neuer Lauf). Sonst behalten Waffen, deren uid bleibt, ihren Zustand.
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
		hand.level = int(entry.get("level", 1))
		hand.hands = int(entry.get("hands", 1))
		hand.fire_buffer_left = 0.0
		hands.append(hand)
	if hands.is_empty():
		var fallback: Hand = Hand.new()
		fallback.id = WeaponDefs.START_WEAPON
		fallback.state = WeaponState.new(fallback.id)
		hands.append(fallback)
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


## uid einer gewöhnlichen Waffe mit dieser ID in der Ablage, -1 wenn dort keine liegt.
func _stored_common_weapon(backpack: BackpackState, weapon_id: String) -> int:
	for entry: Dictionary in backpack.storage_items():
		if String(entry["id"]) == weapon_id and int(entry["level"]) == 1:
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
## Magazin beginnt dann nachzuladen).
func _fire_hand(hand: Hand) -> bool:
	var index: int = _hands.find(hand)
	if index < 0:
		return false
	var state: WeaponState = hand.state
	if not state.can_fire():
		if state.needs_reload():
			_start_reload_hand(hand)
		return false
	state.fire()
	var def: Dictionary = state.get_def()
	var from: Vector3 = _aim_origin()
	var aim: Vector3 = _aim_direction()
	var muzzle: Vector3 = _muzzle_position(index, from)
	var pierce_targets: int = maxi(0, int(Game.bullet_value(hand.uid, "pierce", "targets")))
	var fx_root: Node = Fx.root_of(self)
	for _pellet: int in int(def["pellets"]):
		_fire_pellet(index, hand, def, from, aim, muzzle, pierce_targets, fx_root)
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
	return true


## Beginnt das Nachladen dieser Hand, wenn es möglich ist. Verstärker verkürzen es.
func _start_reload_hand(hand: Hand) -> void:
	var index: int = _hands.find(hand)
	if index < 0 or not _can_act():
		return
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
func _fire_pellet(index: int, hand: Hand, def: Dictionary, from: Vector3, aim: Vector3, muzzle: Vector3,
		pierce_targets: int, fx_root: Node) -> void:
	var direction: Vector3 = _apply_spread(aim, float(def["spread_deg"]))
	var to: Vector3 = from + direction * Balance.WEAPON_RANGE
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if _player is CollisionObject3D:
		exclude.append((_player as CollisionObject3D).get_rid())
	var color: Color = TRACER_COLORS.get(hand.id, Color.YELLOW)
	var explosive: bool = float(def.get("explosion_radius", 0.0)) > 0.0
	var multiplier: float = Game.weapon_damage_multiplier(hand.uid)
	var end: Vector3 = to
	var targets_hit: int = 0
	for _step: int in MAX_RAY_STEPS:
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
				_explode(index, hand, def, hit_position - direction * EXPLOSION_BACKOFF, 0, multiplier, fx_root)
			else:
				_spawn_impact(fx_root, hit_position, color)
			break
		exclude.append(hit["rid"])
		# Die Nummer merken: Nach take_damage kann der Zombie schon weg sein.
		var zombie_id: int = zombie.get_instance_id()
		var headshot: bool = zombie.has_method("is_headshot") and bool(zombie.call("is_headshot", hit_position))
		var damage: float = WeaponDefs.bullet_damage(hand.id, headshot, targets_hit) * multiplier
		var info: Dictionary = {
			"source": "bullet",
			"headshot": headshot,
			"weapon_id": hand.id,
			"weapon": hand.id,
			"weapon_uid": hand.uid,
			"hand": index,
			"hit_position": hit_position,
		}
		zombie.call("take_damage", damage, info)
		if is_instance_valid(zombie):
			Events.bullet_hit.emit(zombie, damage, info)
		targets_hit += 1
		if explosive:
			end = hit_position
			_explode(index, hand, def, hit_position - direction * EXPLOSION_BACKOFF, zombie_id, multiplier, fx_root)
			break
		if targets_hit > pierce_targets:
			end = hit_position
			break
	Fx.tracer(fx_root, muzzle, end, color)


## Explosion eines Geschosses an center: Schaden (explosion_damage mal Waffen-Faktor) an allen
## lebenden Zombies im Radius mit freier Sichtlinie, außer dem direkt getroffenen (direct_id ist
## seine Instanz-Nummer, 0 = keiner). Der Spieler nimmt keinen Schaden.
func _explode(index: int, hand: Hand, def: Dictionary, center: Vector3, direct_id: int, multiplier: float,
		fx_root: Node) -> void:
	var radius: float = float(def.get("explosion_radius", 0.0))
	var damage: float = float(def.get("explosion_damage", 0.0)) * multiplier
	Fx.explosion(fx_root, center, radius, EXPLOSION_COLOR)
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
		zombie.call("take_damage", damage, {
			"source": "explosion",
			"weapon_id": hand.id,
			"weapon": hand.id,
			"weapon_uid": hand.uid,
			"hand": index,
			"hit_position": target,
		})


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


## Kleiner Einschlag-Funke an Wand oder Boden, räumt sich selbst weg.
func _spawn_impact(fx_root: Node, at: Vector3, color: Color) -> void:
	if not is_instance_valid(fx_root) or not fx_root.is_inside_tree():
		return
	if _impact_mesh == null:
		_impact_mesh = BoxMesh.new()
		_impact_mesh.size = Vector3.ONE * IMPACT_SIZE
	var material: StandardMaterial3D = _impact_materials.get(color, null) as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color.lerp(Color.WHITE, 0.5)
		_impact_materials[color] = material
	var spark: MeshInstance3D = MeshInstance3D.new()
	spark.mesh = _impact_mesh
	spark.material_override = material
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spark.rotation = Vector3(at.x * 7.0, at.y * 5.0, at.z * 3.0)
	fx_root.add_child(spark)
	spark.global_position = at
	var tween: Tween = spark.create_tween()
	tween.tween_property(spark, "scale", Vector3.ONE * 0.05, IMPACT_TIME).from(Vector3.ONE * 1.6)
	tween.tween_callback(spark.queue_free)
