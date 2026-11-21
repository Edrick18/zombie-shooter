extends Node3D
## Modul: Spieler (scripts/game/player).
## Sichtbare Waffen vor der Kamera (Kind der Kamera, Name "ViewModel"). Zeigt, was der Spieler
## hält: eine Waffe (ein- oder zweihändig) rechts wie bisher, bei zwei Einhand-Waffen eine rechts
## und eine gespiegelt links. Hat keinen Einfluss auf Spielregeln.
##
## Der WeaponController ruft set_loadout (nach jedem Abgleich mit dem Rucksack) und play_fire
## (je Schuss einer Hand). Das Nachladen kommt über Events.hand_reload_started und
## hand_reload_finished. Jede Hand hat ihren eigenen Rückstoß und ihre eigene Nachlade-Bewegung.
##
## Aufbau:
##   ViewModel
##   └─ Rig (verkleinert, siehe VIEW_SCALE)
##       ├─ Hand0 (linke Hand: bei zwei Waffen gespiegelt links, sonst rechts)
##       │   └─ Holder (wird animiert)
##       │       └─ Gun_<id> (Modell der Waffe, entsteht beim ersten Zeigen)
##       └─ Hand1 (rechte Hand, nur bei zwei Waffen sichtbar)
##           └─ Holder
## Die neun Modelle:
##   pistol           Dienstpistole: gelb-schwarz, Schlitten fährt zurück
##   revolver         Kandidatenschreck: silber-rot mit goldener Trommel, die sich weiterdreht
##   smg              Quotenhammer: türkis-pink, Magazin fällt beim Nachladen
##   sawed_off        Blitzrunde: lila-grün, zwei kurze Läufe, die zum Nachladen abkippen
##   shotgun          Publikumsjoker: rot-gold, Vorderschaft wird durchgeladen
##   rifle            Dauerbrenner: blau-orange, gebogenes Magazin
##   sniper           Fernbedienung: weiß-lila, langer Lauf, großes Zielfernrohr, Kammerstängel
##   minigun          Applausmaschine: pink-gelb, sechs Läufe, die sich drehen
##   rocket_launcher  Showfinale: grünes Rohr mit goldenen Ringen, rote Rakete vorn
## Jede Waffe hat einen Knoten "Muzzle" (Mündung): dort entsteht das Mündungsfeuer (Fx.muzzle_flash)
## und dort beginnt die Leuchtspur.

const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

# --- Reine Optik ---
## Die Waffe ist in echter Größe gebaut und wird samt Abstand zur Kamera verkleinert. Im Bild
## sieht das gleich aus, sie ragt aber nie in eine Wand, vor der der Spieler steht.
const VIEW_SCALE: float = 0.3
const HAND_COUNT: int = 2
const REST_POSITION: Vector3 = Vector3(0.25, -0.235, -0.56)
const REST_YAW: float = 0.05
## Versatz bei zwei Waffen: etwas weiter außen und tiefer, damit die Bildmitte frei bleibt.
const AKIMBO_OFFSET: Vector3 = Vector3(0.035, -0.012, 0.0)
const WEAPON_OFFSETS: Dictionary = {
	"pistol": Vector3(-0.02, 0.01, 0.05),
	"revolver": Vector3(-0.02, 0.005, 0.05),
	"smg": Vector3(0.0, 0.0, 0.03),
	"sawed_off": Vector3(-0.01, 0.0, 0.06),
	"shotgun": Vector3(0.0, -0.02, 0.12),
	"rifle": Vector3(0.0, -0.02, 0.12),
	"sniper": Vector3(0.01, -0.045, 0.08),
	"minigun": Vector3(0.0, -0.05, -0.02),
	"rocket_launcher": Vector3(0.09, -0.03, 0.06),
}
## Rückstoß je Waffe: zurück (m), Mündung hoch (rad), Verdrehen (rad, zufällig), seitlich (m, zufällig).
const RECOIL: Dictionary = {
	"pistol": { "back": 0.06, "pitch": 0.2, "roll": 0.03, "side": 0.004 },
	"revolver": { "back": 0.09, "pitch": 0.36, "roll": 0.04, "side": 0.005 },
	"smg": { "back": 0.034, "pitch": 0.055, "roll": 0.045, "side": 0.007 },
	"sawed_off": { "back": 0.14, "pitch": 0.42, "roll": 0.06, "side": 0.008 },
	"shotgun": { "back": 0.16, "pitch": 0.34, "roll": 0.05, "side": 0.008 },
	"rifle": { "back": 0.04, "pitch": 0.05, "roll": 0.03, "side": 0.005 },
	"sniper": { "back": 0.2, "pitch": 0.3, "roll": 0.03, "side": 0.004 },
	"minigun": { "back": 0.016, "pitch": 0.012, "roll": 0.03, "side": 0.007 },
	"rocket_launcher": { "back": 0.2, "pitch": 0.22, "roll": 0.05, "side": 0.008 },
}
## Wie stark die Waffe beim Nachladen kippt (1 = wie die Pistole). Schwere Waffen kippen weniger.
const RELOAD_TILT: Dictionary = {
	"rifle": 0.45, "sniper": 0.4, "minigun": 0.3, "rocket_launcher": 0.4,
}
## Bei zwei Waffen kippen beide weniger, damit sie sich in der Bildmitte nicht kreuzen.
const AKIMBO_RELOAD_TILT: float = 0.55
const RECOIL_STIFFNESS: float = 240.0
const RECOIL_DAMPING: float = 20.0
const SWITCH_TIME: float = 0.28
const SWAY_GAIN: float = 0.011
const SWAY_MAX: float = 0.045
const BOB_FREQUENCY: float = 1.75
const BOB_AMOUNT: float = 0.011
const SLIDE_TRAVEL: float = 0.055
const SLIDE_TIME: float = 0.1
const PUMP_TRAVEL: float = 0.13
const BOLT_TRAVEL: float = 0.075
## Minigun: Drehung der Läufe je Schuss dazu (rad/s), Obergrenze und Abklingen (1/s).
const SPIN_PER_SHOT: float = 9.0
const SPIN_MAX: float = 34.0
const SPIN_DECAY: float = 2.4

const COLOR_STEEL: Color = Color(0.13, 0.13, 0.16)
const COLOR_YELLOW: Color = Color(1.0, 0.82, 0.1)
const COLOR_RED: Color = Color(0.85, 0.12, 0.14)
const COLOR_GOLD: Color = Color(1.0, 0.7, 0.2)
const COLOR_TEAL: Color = Color(0.1, 0.75, 0.8)
const COLOR_PINK: Color = Color(1.0, 0.2, 0.7)
const COLOR_SILVER: Color = Color(0.82, 0.84, 0.9)
const COLOR_WHITE: Color = Color(0.95, 0.95, 0.92)
const COLOR_PURPLE: Color = Color(0.55, 0.2, 0.9)
const COLOR_LIME: Color = Color(0.55, 0.95, 0.15)
const COLOR_BLUE: Color = Color(0.12, 0.35, 0.95)
const COLOR_ORANGE: Color = Color(1.0, 0.5, 0.08)
const COLOR_GREEN: Color = Color(0.1, 0.62, 0.25)
const COLOR_WOOD: Color = Color(0.55, 0.32, 0.14)
const COLOR_SKIN: Color = Color(0.93, 0.72, 0.58)
const COLOR_SLEEVE: Color = Color(0.45, 0.2, 0.85)


## Gedämpfte Feder für eine Zahl: schnappt nach einem Stoß zurück auf 0.
class Spring:
	extends RefCounted
	var value: float = 0.0
	var velocity: float = 0.0

	func step(stiffness: float, damping: float, delta: float) -> void:
		# In kleinen Teilschritten, damit die Feder bei niedriger Bildrate nicht aufschaukelt.
		var left: float = delta
		while left > 0.0:
			var dt: float = minf(left, 1.0 / 120.0)
			velocity += (-stiffness * value - damping * velocity) * dt
			value += velocity * dt
			left -= dt

	func reset() -> void:
		value = 0.0
		velocity = 0.0


## Eine Hand: ihr Platz vor der Kamera, ihre Modelle und der Stand ihrer Bewegungen.
class HandSlot:
	extends RefCounted
	## Spiegelt die linke Waffe (scale.x = -1), wenn zwei Waffen gehalten werden.
	var side: Node3D = null
	var holder: Node3D = null
	## Gezeigte Waffe, "" = diese Hand ist leer.
	var weapon_id: String = ""
	var mirrored: bool = false
	## weapon_id -> Node3D (Modell der Waffe).
	var models: Dictionary = {}
	## weapon_id -> Node3D (Mündung).
	var muzzles: Dictionary = {}
	## "weapon_id/teil" -> Node3D (bewegliches Teil).
	var parts: Dictionary = {}
	## "weapon_id/teil" -> Vector3 (Ruheposition des Teils).
	var part_rest: Dictionary = {}
	var kick_back: Spring = Spring.new()
	var kick_pitch: Spring = Spring.new()
	var kick_roll: float = 0.0
	var kick_side: float = 0.0
	var fire_age: float = 10.0
	var switch_progress: float = 1.0
	var is_reloading: bool = false
	var reload_time: float = 0.0
	var reload_duration: float = 1.0
	## Schüsse seit dem Zeigen (dreht die Trommel des Revolvers weiter).
	var shots: int = 0
	## Drehung der Minigun-Läufe (Winkel und Tempo).
	var spin: float = 0.0
	var spin_speed: float = 0.0
	## Steckt eine Rakete im Rohr?
	var rocket_loaded: bool = true

	func reset_motion() -> void:
		kick_back.reset()
		kick_pitch.reset()
		kick_roll = 0.0
		kick_side = 0.0
		fire_age = 10.0
		is_reloading = false
		reload_time = 0.0
		shots = 0
		spin_speed = 0.0
		rocket_loaded = true


## Waffe in der linken Hand (bei einer einzelnen Waffe: diese Waffe).
var weapon_id: String = WeaponDefs.START_WEAPON

var _rig: Node3D
var _slots: Array[HandSlot] = []
var _akimbo: bool = false
var _materials: Dictionary = {}

var _sway: Vector2 = Vector2.ZERO
var _last_basis: Basis = Basis.IDENTITY
var _has_last_basis: bool = false
var _bob_phase: float = 0.0
var _bob_weight: float = 0.0
var _fall_offset: float = 0.0
var _time: float = 0.0


func _init() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.scale = Vector3.ONE * VIEW_SCALE
	add_child(_rig)
	for index: int in HAND_COUNT:
		var slot: HandSlot = HandSlot.new()
		slot.side = Node3D.new()
		slot.side.name = "Hand%d" % index
		_rig.add_child(slot.side)
		slot.holder = Node3D.new()
		slot.holder.name = "Holder"
		slot.holder.position = REST_POSITION
		slot.side.add_child(slot.holder)
		_slots.append(slot)
	set_weapon(weapon_id)
	for slot: HandSlot in _slots:
		slot.switch_progress = 1.0
		_apply_pose(slot)


func _ready() -> void:
	Events.hand_reload_started.connect(_on_hand_reload_started)
	Events.hand_reload_finished.connect(_on_hand_reload_finished)
	Events.player_died.connect(_on_player_died)
	Events.run_started.connect(_on_run_started)


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	_time += dt
	_update_sway(dt)
	_update_bob(dt)
	var settle: float = 1.0 - exp(-14.0 * dt)
	for slot: HandSlot in _slots:
		if slot.weapon_id.is_empty():
			continue
		slot.fire_age += dt
		slot.kick_back.step(RECOIL_STIFFNESS, RECOIL_DAMPING, dt)
		slot.kick_pitch.step(RECOIL_STIFFNESS, RECOIL_DAMPING, dt)
		slot.kick_roll = lerpf(slot.kick_roll, 0.0, settle)
		slot.kick_side = lerpf(slot.kick_side, 0.0, settle)
		slot.switch_progress = minf(1.0, slot.switch_progress + dt / SWITCH_TIME)
		slot.spin_speed = lerpf(slot.spin_speed, 0.0, 1.0 - exp(-SPIN_DECAY * dt))
		slot.spin = fposmod(slot.spin + slot.spin_speed * dt, TAU)
		if slot.is_reloading:
			slot.reload_time += dt
			if slot.reload_time >= slot.reload_duration:
				slot.is_reloading = false
				slot.rocket_loaded = true
		_apply_pose(slot)


# --- Öffentliche Schnittstelle ---------------------------------------------------------------


## Zeigt die gehaltenen Waffen. hands: je Hand ein Eintrag aus WeaponController.get_hands()
## (gelesen werden "id", "reloading", "reload_left", "reload_duration") oder nur die Waffen-ID.
## Eine Waffe: rechts wie bisher. Zwei Waffen: Hand 0 gespiegelt links, Hand 1 rechts. Eine neu
## gezeigte Waffe kommt von unten hoch. Unbekannte IDs werden übergangen.
func set_loadout(hands: Array) -> void:
	var ids: Array[String] = []
	var entries: Array[Dictionary] = []
	for value: Variant in hands:
		var entry: Dictionary = value if value is Dictionary else {"id": str(value)}
		var id: String = str(entry.get("id", ""))
		if WeaponDefs.has(id) and ids.size() < HAND_COUNT:
			ids.append(id)
			entries.append(entry)
	if ids.is_empty():
		return
	_akimbo = ids.size() > 1
	weapon_id = ids[0]
	for index: int in HAND_COUNT:
		var slot: HandSlot = _slots[index]
		var id: String = ids[index] if index < ids.size() else ""
		var mirrored: bool = _akimbo and index == 0
		if id != slot.weapon_id or mirrored != slot.mirrored:
			_show_weapon(slot, id, mirrored)
		if id.is_empty():
			continue
		var entry: Dictionary = entries[index]
		if entry.has("reloading"):
			# Laufendes Nachladen übernehmen (die Waffe kann die Hand gewechselt haben).
			slot.is_reloading = bool(entry["reloading"])
			if slot.is_reloading:
				slot.reload_duration = maxf(float(entry.get("reload_duration", 1.0)), 0.05)
				slot.reload_time = clampf(slot.reload_duration - float(entry.get("reload_left", 0.0)), 0.0, slot.reload_duration)
		_apply_pose(slot)


## Zeigt genau eine Waffe (rechts). Unbekannte IDs zeigen nichts Neues.
func set_weapon(new_weapon_id: String) -> void:
	set_loadout([new_weapon_id])


## IDs der gezeigten Waffen in Reihenfolge der Hände.
func get_hand_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot: HandSlot in _slots:
		if not slot.weapon_id.is_empty():
			ids.append(slot.weapon_id)
	return ids


## Ein Schuss dieser Hand: Rückstoß und Mündungsfeuer.
func play_fire(hand: int = 0) -> void:
	var slot: HandSlot = _slot(hand)
	if slot == null:
		return
	var recoil: Dictionary = RECOIL.get(slot.weapon_id, {})
	if recoil.is_empty():
		return
	slot.fire_age = 0.0
	slot.shots += 1
	slot.kick_back.value = minf(slot.kick_back.value + float(recoil["back"]), float(recoil["back"]) * 1.6)
	slot.kick_pitch.value = minf(slot.kick_pitch.value + float(recoil["pitch"]), float(recoil["pitch"]) * 1.6)
	slot.kick_roll = randf_range(-1.0, 1.0) * float(recoil["roll"])
	slot.kick_side = randf_range(-1.0, 1.0) * float(recoil["side"])
	slot.spin_speed = minf(slot.spin_speed + SPIN_PER_SHOT, SPIN_MAX)
	if slot.weapon_id == "rocket_launcher":
		slot.rocket_loaded = false
	Fx.muzzle_flash(get_muzzle_node(hand))
	_apply_pose(slot)


## Weltposition der Mündung dieser Hand: Startpunkt der Leuchtspur und Ort des Mündungsfeuers.
func get_muzzle_position(hand: int = 0) -> Vector3:
	if not is_inside_tree():
		return position
	var muzzle: Node3D = get_muzzle_node(hand)
	if muzzle == null:
		return global_position
	return muzzle.global_position


## Knoten der Mündung der Waffe in dieser Hand, null wenn die Hand leer ist.
func get_muzzle_node(hand: int = 0) -> Node3D:
	var slot: HandSlot = _slot(hand)
	if slot == null:
		return null
	return slot.muzzles.get(slot.weapon_id, null) as Node3D


# --- Signale ---------------------------------------------------------------------------------


func _on_hand_reload_started(hand: int, duration: float) -> void:
	var slot: HandSlot = _slot(hand)
	if slot == null:
		return
	slot.is_reloading = true
	slot.reload_time = 0.0
	slot.reload_duration = maxf(duration, 0.05)


func _on_hand_reload_finished(hand: int) -> void:
	var slot: HandSlot = _slot(hand)
	if slot == null:
		return
	slot.is_reloading = false
	slot.rocket_loaded = true


func _on_player_died() -> void:
	_rig.visible = false


func _on_run_started() -> void:
	_rig.visible = true


## Die Hand mit diesem Index, null wenn es sie nicht gibt oder sie leer ist.
func _slot(hand: int) -> HandSlot:
	if hand < 0 or hand >= _slots.size() or _slots[hand].weapon_id.is_empty():
		return null
	return _slots[hand]


## Zeigt in dieser Hand das Modell der Waffe ("" = nichts) und beginnt die Wechsel-Bewegung.
func _show_weapon(slot: HandSlot, id: String, mirrored: bool) -> void:
	slot.weapon_id = id
	slot.mirrored = mirrored
	slot.side.scale = Vector3(-1.0 if mirrored else 1.0, 1.0, 1.0)
	slot.side.visible = not id.is_empty()
	if not id.is_empty() and not slot.models.has(id):
		_build_model(slot, id)
	for model_id: String in slot.models.keys():
		(slot.models[model_id] as Node3D).visible = model_id == id
	slot.reset_motion()
	slot.switch_progress = 0.0


# --- Bewegung --------------------------------------------------------------------------------


## Die Waffe hängt der Kameradrehung leicht nach.
func _update_sway(dt: float) -> void:
	if not is_inside_tree():
		return
	var now: Basis = global_transform.basis.orthonormalized()
	var target: Vector2 = Vector2.ZERO
	if _has_last_basis and dt > 0.0001:
		var forward: Vector3 = _last_basis.inverse() * (-now.z)
		target = Vector2(-forward.x, -forward.y) / dt * SWAY_GAIN
		target = target.limit_length(SWAY_MAX)
	_last_basis = now
	_has_last_basis = true
	_sway = _sway.lerp(target, 1.0 - exp(-12.0 * dt))


## Die Waffe wippt beim Laufen und sackt bei Sprung und Landung leicht nach.
func _update_bob(dt: float) -> void:
	var body: CharacterBody3D = null
	var camera: Node = get_parent()
	if camera != null:
		body = camera.get_parent() as CharacterBody3D
	var flat_speed: float = 0.0
	var fall_target: float = 0.0
	var target_weight: float = 0.0
	if body != null and body.is_inside_tree():
		flat_speed = Vector2(body.velocity.x, body.velocity.z).length()
		if body.is_on_floor():
			target_weight = clampf(flat_speed / 5.0, 0.0, 1.4)
		else:
			fall_target = clampf(-body.velocity.y * 0.007, -0.035, 0.035)
	_bob_weight = lerpf(_bob_weight, target_weight, 1.0 - exp(-10.0 * dt))
	_bob_phase = fposmod(_bob_phase + flat_speed * BOB_FREQUENCY * dt, TAU)
	_fall_offset = lerpf(_fall_offset, fall_target, 1.0 - exp(-9.0 * dt))


## Setzt die Haltung einer Hand aus Ruhelage, Wechsel, Nachladen, Rückstoß, Nachhängen und
## Wippen zusammen. Die gespiegelte Hand rechnet seitliche Bewegungen umgekehrt, damit beide
## Waffen im Bild in dieselbe Richtung schwingen.
func _apply_pose(slot: HandSlot) -> void:
	var id: String = slot.weapon_id
	if id.is_empty():
		return
	var facing: float = -1.0 if slot.mirrored else 1.0
	var offset: Vector3 = WEAPON_OFFSETS.get(id, Vector3.ZERO)
	var pos: Vector3 = REST_POSITION + offset
	if _akimbo:
		pos += AKIMBO_OFFSET
	var rot: Vector3 = Vector3(0.0, REST_YAW, 0.0)
	# Wechsel: die Waffe kommt von unten hoch.
	var lowered: float = 1.0 - _ease_out(slot.switch_progress)
	pos.y -= 0.34 * lowered
	rot.x -= 0.95 * lowered
	# Nachladen: Mündung hoch und zur Mitte, Unterseite (Magazin) dreht sich ins Bild.
	var reload_progress: float = 0.0
	if slot.is_reloading:
		reload_progress = clampf(slot.reload_time / slot.reload_duration, 0.0, 1.0)
		var tilt: float = smoothstep(0.0, 0.16, reload_progress) * (1.0 - smoothstep(0.84, 1.0, reload_progress))
		tilt *= float(RELOAD_TILT.get(id, 1.0))
		if _akimbo:
			tilt *= AKIMBO_RELOAD_TILT
		pos += Vector3(-0.06, -0.03, 0.03) * tilt
		rot += Vector3(0.38, 0.3, -0.7) * tilt
	# Rückstoß.
	pos.z += slot.kick_back.value
	pos.x += slot.kick_side
	rot.x += slot.kick_pitch.value
	rot.z += slot.kick_roll
	# Nachhängen und Wippen.
	pos.x += (_sway.x + cos(_bob_phase) * BOB_AMOUNT * _bob_weight) * facing
	pos.y += _sway.y + _fall_offset - absf(sin(_bob_phase)) * BOB_AMOUNT * _bob_weight
	pos.y += sin(_time * 1.6) * 0.0025
	rot.y -= _sway.x * 1.5 * facing
	rot.x += _sway.y * 1.5
	rot.z += -_sway.x * 2.0 * facing
	match id:
		"pistol":
			_pose_pistol(slot, reload_progress)
		"revolver":
			_pose_revolver(slot, reload_progress)
		"smg":
			pos.y += _pose_magazine(slot, "smg/mag", reload_progress, 0.42)
		"sawed_off":
			_pose_sawed_off(slot, reload_progress)
		"shotgun":
			pos.y += _pose_shotgun(slot, reload_progress)
		"rifle":
			pos.y += _pose_magazine(slot, "rifle/mag", reload_progress, 0.4)
		"sniper":
			pos.y += _pose_sniper(slot, reload_progress)
		"minigun":
			_pose_minigun(slot, reload_progress)
		"rocket_launcher":
			_pose_rocket_launcher(slot, reload_progress)
	slot.holder.position = pos
	slot.holder.rotation = rot


## Pistole: Schlitten schnellt beim Schuss zurück, Magazin fällt beim Nachladen heraus.
func _pose_pistol(slot: HandSlot, reload_progress: float) -> void:
	var slide: float = maxf(0.0, 1.0 - slot.fire_age / SLIDE_TIME)
	var mag_drop: float = 0.0
	if slot.is_reloading:
		mag_drop = _window(reload_progress, 0.16, 0.3, 0.5, 0.68)
		slide = maxf(slide, _window(reload_progress, 0.76, 0.84, 0.88, 0.95))
	_set_part(slot, "pistol/slide", Vector3(0.0, 0.0, SLIDE_TRAVEL * slide))
	_set_part(slot, "pistol/mag", Vector3(0.0, -0.24 * mag_drop, 0.05 * mag_drop))


## Revolver: Die Trommel dreht sich je Schuss ein Sechstel weiter. Beim Nachladen schwenkt sie
## seitlich heraus und dreht durch, der Hahn spannt nach jedem Schuss.
func _pose_revolver(slot: HandSlot, reload_progress: float) -> void:
	var step: float = clampf(slot.fire_age / 0.18, 0.0, 1.0)
	var angle: float = (float(slot.shots) - 1.0 + _ease_out(step)) * TAU / 6.0
	var swing: float = 0.0
	if slot.is_reloading:
		swing = _window(reload_progress, 0.14, 0.28, 0.7, 0.84)
		angle += reload_progress * TAU * 2.0
	_set_part(slot, "revolver/drum", Vector3(-0.075 * swing, -0.02 * swing, 0.0))
	var drum: Node3D = slot.parts.get("revolver/drum", null) as Node3D
	if drum != null:
		drum.rotation.z = angle
	var hammer: Node3D = slot.parts.get("revolver/hammer", null) as Node3D
	if hammer != null:
		hammer.rotation.x = 0.7 * _window(slot.fire_age, 0.0, 0.03, 0.1, 0.3)


## Waffen mit Stangenmagazin (MP, Sturmgewehr): Das Magazin fällt beim Nachladen und wird wieder
## eingeschlagen. Gibt einen Versatz der Waffe nach oben zurück.
func _pose_magazine(slot: HandSlot, key: String, reload_progress: float, drop_distance: float) -> float:
	var mag_drop: float = 0.0
	var bump: float = 0.0
	if slot.is_reloading:
		mag_drop = _window(reload_progress, 0.14, 0.3, 0.48, 0.66)
		bump = 0.025 * _window(reload_progress, 0.64, 0.69, 0.71, 0.8)
	_set_part(slot, key, Vector3(0.0, -drop_distance * mag_drop, 0.04 * mag_drop))
	return bump


## Abgesägte Schrotflinte: Die Läufe kippen zum Nachladen nach unten ab.
func _pose_sawed_off(slot: HandSlot, reload_progress: float) -> void:
	var open: float = 0.0
	if slot.is_reloading:
		open = _window(reload_progress, 0.12, 0.26, 0.7, 0.86)
	var barrels: Node3D = slot.parts.get("sawed_off/barrels", null) as Node3D
	if barrels != null:
		barrels.rotation.x = -0.75 * open


## Schrotflinte: Durchladen nach jedem Schuss, Patronen nachschieben beim Nachladen.
## Gibt einen Versatz der Waffe nach oben zurück.
func _pose_shotgun(slot: HandSlot, reload_progress: float) -> float:
	var pump: float = _window(slot.fire_age, 0.16, 0.3, 0.36, 0.52)
	var bump: float = -0.012 * pump
	if slot.is_reloading:
		pump = maxf(pump, _window(reload_progress, 0.8, 0.87, 0.9, 0.97))
		if reload_progress > 0.16 and reload_progress < 0.78:
			var shells: float = (reload_progress - 0.16) / 0.62 * 4.0
			bump += 0.02 * absf(sin(shells * PI))
	_set_part(slot, "shotgun/pump", Vector3(0.0, 0.0, PUMP_TRAVEL * pump))
	return bump


## Scharfschützengewehr: Der Kammerstängel fährt nach jedem Schuss zurück und wieder vor, beim
## Nachladen fällt das kurze Magazin. Gibt einen Versatz der Waffe nach oben zurück.
func _pose_sniper(slot: HandSlot, reload_progress: float) -> float:
	var bolt: float = _window(slot.fire_age, 0.25, 0.45, 0.6, 0.85)
	var mag_drop: float = 0.0
	if slot.is_reloading:
		mag_drop = _window(reload_progress, 0.14, 0.3, 0.5, 0.68)
		bolt = maxf(bolt, _window(reload_progress, 0.72, 0.8, 0.86, 0.95))
	_set_part(slot, "sniper/bolt", Vector3(0.0, 0.0, BOLT_TRAVEL * bolt))
	_set_part(slot, "sniper/mag", Vector3(0.0, -0.3 * mag_drop, 0.03 * mag_drop))
	return -0.008 * bolt


## Minigun: Die Läufe drehen sich, solange geschossen wird, und laufen aus. Beim Nachladen wird
## der Munitionskasten getauscht.
func _pose_minigun(slot: HandSlot, reload_progress: float) -> void:
	var barrels: Node3D = slot.parts.get("minigun/barrels", null) as Node3D
	if barrels != null:
		barrels.rotation.z = slot.spin
	var box_drop: float = 0.0
	if slot.is_reloading:
		box_drop = _window(reload_progress, 0.12, 0.3, 0.6, 0.8)
	_set_part(slot, "minigun/box", Vector3(0.0, -0.4 * box_drop, 0.03 * box_drop))


## Raketenwerfer: Nach dem Schuss ist das Rohr leer, beim Nachladen schiebt sich die neue Rakete
## von vorn hinein.
func _pose_rocket_launcher(slot: HandSlot, reload_progress: float) -> void:
	var rocket: Node3D = slot.parts.get("rocket_launcher/rocket", null) as Node3D
	if rocket == null:
		return
	if slot.is_reloading:
		var slide_in: float = smoothstep(0.5, 0.82, reload_progress)
		rocket.visible = reload_progress > 0.5
		_set_part(slot, "rocket_launcher/rocket", Vector3(0.0, 0.0, -0.35 * (1.0 - slide_in)))
		return
	rocket.visible = slot.rocket_loaded
	_set_part(slot, "rocket_launcher/rocket", Vector3.ZERO)


## Verschiebt ein bewegliches Teil um offset aus seiner Ruhelage.
func _set_part(slot: HandSlot, key: String, offset: Vector3) -> void:
	var part: Node3D = slot.parts.get(key, null) as Node3D
	if part == null:
		return
	var rest: Vector3 = slot.part_rest.get(key, Vector3.ZERO)
	part.position = rest + offset


## 0 → 1 zwischen rise_from und rise_to, bleibt 1, 1 → 0 zwischen fall_from und fall_to.
func _window(x: float, rise_from: float, rise_to: float, fall_from: float, fall_to: float) -> float:
	return smoothstep(rise_from, rise_to, x) * (1.0 - smoothstep(fall_from, fall_to, x))


func _ease_out(x: float) -> float:
	var inverse: float = 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - inverse * inverse * inverse


# --- Aufbau der Modelle aus einfachen Formen (Mündung zeigt nach -Z) -------------------------


func _build_model(slot: HandSlot, id: String) -> void:
	match id:
		"pistol":
			_build_pistol(slot)
		"revolver":
			_build_revolver(slot)
		"smg":
			_build_smg(slot)
		"sawed_off":
			_build_sawed_off(slot)
		"shotgun":
			_build_shotgun(slot)
		"rifle":
			_build_rifle(slot)
		"sniper":
			_build_sniper(slot)
		"minigun":
			_build_minigun(slot)
		"rocket_launcher":
			_build_rocket_launcher(slot)


func _build_pistol(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "pistol")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.0, 0.1)
	var glow: StandardMaterial3D = _material(COLOR_PINK, 1.6, 0.0)
	var slide: Node3D = _new_part(slot, gun, "pistol/slide", Vector3(0.0, 0.03, -0.1))
	_box(slide, Vector3(0.05, 0.055, 0.26), Vector3.ZERO, steel)
	_box(slide, Vector3(0.054, 0.014, 0.09), Vector3(0.0, 0.004, 0.06), yellow)
	_box(slide, Vector3(0.012, 0.016, 0.016), Vector3(0.0, 0.034, -0.115), glow)
	_box(slide, Vector3(0.03, 0.014, 0.014), Vector3(0.0, 0.033, 0.115), steel)
	_box(gun, Vector3(0.044, 0.03, 0.21), Vector3(0.0, -0.012, -0.09), yellow)
	_box(gun, Vector3(0.012, 0.04, 0.075), Vector3(0.0, -0.045, -0.075), steel)
	var grip: MeshInstance3D = _box(gun, Vector3(0.044, 0.15, 0.068), Vector3(0.0, -0.09, 0.012), yellow)
	grip.rotation.x = -0.24
	var grip_stripe: MeshInstance3D = _box(gun, Vector3(0.048, 0.05, 0.05), Vector3(0.0, -0.1, 0.014), steel)
	grip_stripe.rotation.x = -0.24
	var mag: Node3D = _new_part(slot, gun, "pistol/mag", Vector3(0.0, -0.09, 0.012))
	mag.rotation.x = -0.24
	_box(mag, Vector3(0.03, 0.13, 0.046), Vector3.ZERO, _material(COLOR_TEAL, 0.4, 0.3))
	_add_muzzle(slot, gun, "pistol", Vector3(0.0, 0.03, -0.245))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.02))


func _build_revolver(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "revolver")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var silver: StandardMaterial3D = _material(COLOR_SILVER, 0.0, 0.8)
	var red: StandardMaterial3D = _material(COLOR_RED, 0.0, 0.2)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	# Rahmen mit Aussparung für die Trommel: Steg oben, Steg unten, Block hinten.
	_box(gun, Vector3(0.04, 0.022, 0.2), Vector3(0.0, 0.085, -0.07), silver)
	_box(gun, Vector3(0.04, 0.022, 0.16), Vector3(0.0, -0.022, -0.06), silver)
	_box(gun, Vector3(0.044, 0.1, 0.05), Vector3(0.0, 0.025, 0.035), silver)
	_box(gun, Vector3(0.044, 0.1, 0.03), Vector3(0.0, 0.035, -0.165), silver)
	# Langer, dicker Lauf mit Schiene darunter.
	_cylinder(gun, 0.024, 0.3, Vector3(0.0, 0.055, -0.32), silver)
	_box(gun, Vector3(0.03, 0.03, 0.27), Vector3(0.0, 0.018, -0.31), steel)
	_box(gun, Vector3(0.012, 0.02, 0.02), Vector3(0.0, 0.088, -0.455), _material(COLOR_GOLD, 1.8, 0.0))
	var drum: Node3D = _new_part(slot, gun, "revolver/drum", Vector3(0.0, 0.032, -0.065))
	_cylinder(drum, 0.05, 0.1, Vector3.ZERO, gold)
	# Rillen, an denen man die Drehung sieht.
	for i: int in 3:
		var groove: MeshInstance3D = _box(drum, Vector3(0.104, 0.018, 0.07), Vector3.ZERO, steel)
		groove.rotation.z = PI / 3.0 * float(i)
	var hammer: Node3D = _new_part(slot, gun, "revolver/hammer", Vector3(0.0, 0.07, 0.05))
	_box(hammer, Vector3(0.014, 0.04, 0.018), Vector3(0.0, 0.016, 0.008), steel)
	var grip: MeshInstance3D = _box(gun, Vector3(0.046, 0.16, 0.07), Vector3(0.0, -0.085, 0.04), red)
	grip.rotation.x = -0.32
	_box(gun, Vector3(0.05, 0.03, 0.074), Vector3(0.0, -0.155, 0.062), gold).rotation.x = -0.32
	_box(gun, Vector3(0.012, 0.04, 0.07), Vector3(0.0, -0.05, -0.04), steel)
	_add_muzzle(slot, gun, "revolver", Vector3(0.0, 0.055, -0.48))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.045))


func _build_smg(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "smg")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var teal: StandardMaterial3D = _material(COLOR_TEAL, 0.0, 0.3)
	var pink: StandardMaterial3D = _material(COLOR_PINK, 1.6, 0.0)
	_box(gun, Vector3(0.065, 0.1, 0.38), Vector3(0.0, 0.02, -0.1), teal)
	_box(gun, Vector3(0.069, 0.03, 0.2), Vector3(0.0, 0.02, -0.12), steel)
	_box(gun, Vector3(0.028, 0.018, 0.3), Vector3(0.0, 0.079, -0.1), pink)
	_box(gun, Vector3(0.014, 0.03, 0.02), Vector3(0.0, 0.1, -0.24), pink)
	_cylinder(gun, 0.024, 0.15, Vector3(0.0, 0.03, -0.36), steel)
	_cylinder(gun, 0.03, 0.03, Vector3(0.0, 0.03, -0.43), pink)
	_box(gun, Vector3(0.03, 0.05, 0.12), Vector3(0.0, 0.025, 0.15), steel)
	_box(gun, Vector3(0.04, 0.09, 0.025), Vector3(0.0, 0.005, 0.215), steel)
	_box(gun, Vector3(0.044, 0.12, 0.06), Vector3(0.0, -0.085, 0.05), steel).rotation.x = -0.2
	var mag: Node3D = _new_part(slot, gun, "smg/mag", Vector3(0.0, -0.13, -0.15))
	mag.rotation.x = 0.12
	_box(mag, Vector3(0.036, 0.24, 0.062), Vector3.ZERO, _material(COLOR_YELLOW, 0.3, 0.2))
	_add_muzzle(slot, gun, "smg", Vector3(0.0, 0.03, -0.46))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.06))


func _build_sawed_off(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "sawed_off")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var purple: StandardMaterial3D = _material(COLOR_PURPLE, 0.0, 0.3)
	var lime: StandardMaterial3D = _material(COLOR_LIME, 0.5, 0.1)
	var wood: StandardMaterial3D = _material(COLOR_WOOD, 0.0, 0.0)
	# Breiter Kasten, daran zwei kurze, dicke Läufe nebeneinander.
	_box(gun, Vector3(0.11, 0.085, 0.15), Vector3(0.0, 0.025, -0.02), purple)
	_box(gun, Vector3(0.114, 0.02, 0.1), Vector3(0.0, 0.05, -0.02), lime)
	var barrels: Node3D = _new_part(slot, gun, "sawed_off/barrels", Vector3(0.0, 0.0, -0.095))
	for side: float in [-1.0, 1.0]:
		_cylinder(barrels, 0.03, 0.27, Vector3(0.028 * side, 0.035, -0.135), steel)
		_cylinder(barrels, 0.021, 0.012, Vector3(0.028 * side, 0.035, -0.272), lime)
	_box(barrels, Vector3(0.124, 0.074, 0.03), Vector3(0.0, 0.035, -0.04), lime)
	_box(barrels, Vector3(0.124, 0.074, 0.024), Vector3(0.0, 0.035, -0.2), purple)
	_box(barrels, Vector3(0.05, 0.03, 0.2), Vector3(0.0, -0.008, -0.12), wood)
	# Kurzer, gebogener Holzgriff statt eines Schafts.
	_box(gun, Vector3(0.052, 0.09, 0.13), Vector3(0.0, -0.015, 0.1), wood).rotation.x = -0.35
	_box(gun, Vector3(0.05, 0.13, 0.065), Vector3(0.0, -0.09, 0.14), wood).rotation.x = -0.5
	_box(gun, Vector3(0.012, 0.04, 0.07), Vector3(0.0, -0.04, 0.02), steel)
	_add_muzzle(slot, gun, "sawed_off", Vector3(0.0, 0.035, -0.385))
	_add_grip_hand(gun, Vector3(0.0, -0.095, 0.13))


func _build_shotgun(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "shotgun")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var red: StandardMaterial3D = _material(COLOR_RED, 0.0, 0.2)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	_box(gun, Vector3(0.062, 0.09, 0.3), Vector3.ZERO, red)
	_box(gun, Vector3(0.066, 0.02, 0.2), Vector3(0.0, 0.02, 0.0), gold)
	_cylinder(gun, 0.023, 0.62, Vector3(0.0, 0.026, -0.45), steel)
	_cylinder(gun, 0.02, 0.46, Vector3(0.0, -0.026, -0.38), gold)
	_box(gun, Vector3(0.014, 0.02, 0.014), Vector3(0.0, 0.055, -0.74), _material(COLOR_GOLD, 1.8, 0.0))
	var stock: MeshInstance3D = _box(gun, Vector3(0.05, 0.1, 0.32), Vector3(0.0, -0.04, 0.29), red)
	stock.rotation.x = -0.13
	_box(gun, Vector3(0.042, 0.11, 0.05), Vector3(0.0, -0.085, 0.1), steel).rotation.x = -0.3
	var pump: Node3D = _new_part(slot, gun, "shotgun/pump", Vector3(0.0, -0.03, -0.44))
	_box(pump, Vector3(0.072, 0.062, 0.18), Vector3.ZERO, _material(Color(1.0, 0.45, 0.1), 0.0, 0.1))
	for i: int in 3:
		_box(pump, Vector3(0.076, 0.066, 0.016), Vector3(0.0, 0.0, -0.05 + 0.05 * float(i)), steel)
	# Die linke Hand liegt am Vorderschaft und macht das Durchladen mit.
	_add_support_hand(pump, Vector3(-0.005, -0.03, 0.0))
	_add_muzzle(slot, gun, "shotgun", Vector3(0.0, 0.026, -0.77))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.11))


func _build_rifle(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "rifle")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var blue: StandardMaterial3D = _material(COLOR_BLUE, 0.0, 0.3)
	var orange: StandardMaterial3D = _material(COLOR_ORANGE, 0.0, 0.1)
	var glow: StandardMaterial3D = _material(COLOR_ORANGE, 1.6, 0.0)
	# Gehäuse, Handschutz, Lauf mit Mündungsbremse.
	_box(gun, Vector3(0.06, 0.1, 0.4), Vector3(0.0, 0.02, -0.06), blue)
	_box(gun, Vector3(0.064, 0.026, 0.3), Vector3(0.0, 0.035, -0.06), steel)
	_box(gun, Vector3(0.058, 0.074, 0.27), Vector3(0.0, 0.022, -0.39), orange)
	for i: int in 4:
		_box(gun, Vector3(0.062, 0.03, 0.022), Vector3(0.0, 0.03, -0.3 - 0.06 * float(i)), steel)
	_cylinder(gun, 0.016, 0.24, Vector3(0.0, 0.03, -0.63), steel)
	_cylinder(gun, 0.026, 0.06, Vector3(0.0, 0.03, -0.76), orange)
	# Tragegriff mit Visier, Korn vorn.
	_box(gun, Vector3(0.024, 0.016, 0.22), Vector3(0.0, 0.125, -0.04), steel)
	_box(gun, Vector3(0.024, 0.05, 0.022), Vector3(0.0, 0.095, 0.06), steel)
	_box(gun, Vector3(0.024, 0.05, 0.022), Vector3(0.0, 0.095, -0.14), steel)
	_box(gun, Vector3(0.014, 0.02, 0.014), Vector3(0.0, 0.14, 0.05), glow)
	_box(gun, Vector3(0.014, 0.07, 0.016), Vector3(0.0, 0.085, -0.5), steel)
	# Schaft und Griff.
	_box(gun, Vector3(0.05, 0.085, 0.28), Vector3(0.0, 0.0, 0.28), blue)
	_box(gun, Vector3(0.054, 0.12, 0.03), Vector3(0.0, -0.01, 0.43), steel)
	_box(gun, Vector3(0.042, 0.12, 0.055), Vector3(0.0, -0.085, 0.09), steel).rotation.x = -0.28
	var mag: Node3D = _new_part(slot, gun, "rifle/mag", Vector3(0.0, -0.12, -0.1))
	mag.rotation.x = 0.3
	_box(mag, Vector3(0.04, 0.2, 0.075), Vector3.ZERO, orange)
	_box(mag, Vector3(0.044, 0.03, 0.079), Vector3(0.0, -0.09, 0.0), steel)
	_add_support_hand(gun, Vector3(-0.005, -0.035, -0.4))
	_add_muzzle(slot, gun, "rifle", Vector3(0.0, 0.03, -0.8))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.1))


func _build_sniper(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "sniper")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var white: StandardMaterial3D = _material(COLOR_WHITE, 0.0, 0.1)
	var purple: StandardMaterial3D = _material(COLOR_PURPLE, 0.0, 0.3)
	var lens: StandardMaterial3D = _material(COLOR_TEAL, 2.0, 0.0)
	var eyepiece: StandardMaterial3D = _material(Color(0.04, 0.2, 0.26), 0.6, 0.0)
	# Schlankes Gehäuse, sehr langer dünner Lauf mit Mündungsbremse.
	_box(gun, Vector3(0.052, 0.08, 0.5), Vector3(0.0, 0.01, -0.08), white)
	_box(gun, Vector3(0.056, 0.02, 0.4), Vector3(0.0, -0.012, -0.1), purple)
	_cylinder(gun, 0.014, 0.62, Vector3(0.0, 0.03, -0.63), steel)
	_box(gun, Vector3(0.044, 0.04, 0.08), Vector3(0.0, 0.03, -0.96), purple)
	# Großes Zielfernrohr mit leuchtenden Linsen.
	_cylinder(gun, 0.03, 0.26, Vector3(0.0, 0.115, -0.08), purple)
	_tapered(gun, 0.048, 0.03, 0.09, Vector3(0.0, 0.115, -0.25), steel)
	_tapered(gun, 0.03, 0.036, 0.06, Vector3(0.0, 0.115, 0.08), steel)
	_cylinder(gun, 0.042, 0.008, Vector3(0.0, 0.115, -0.297), lens)
	_cylinder(gun, 0.026, 0.008, Vector3(0.0, 0.115, 0.112), eyepiece)
	_box(gun, Vector3(0.02, 0.05, 0.028), Vector3(0.0, 0.07, -0.16), steel)
	_box(gun, Vector3(0.02, 0.05, 0.028), Vector3(0.0, 0.07, 0.0), steel)
	_box(gun, Vector3(0.016, 0.03, 0.03), Vector3(0.0, 0.158, -0.08), purple)
	# Schaft mit Wangenauflage, Griff.
	_box(gun, Vector3(0.05, 0.1, 0.34), Vector3(0.0, -0.012, 0.33), white).rotation.x = -0.06
	_box(gun, Vector3(0.04, 0.03, 0.16), Vector3(0.0, 0.06, 0.3), purple)
	_box(gun, Vector3(0.054, 0.13, 0.03), Vector3(0.0, -0.02, 0.51), steel)
	_box(gun, Vector3(0.042, 0.12, 0.055), Vector3(0.0, -0.085, 0.12), steel).rotation.x = -0.3
	var bolt: Node3D = _new_part(slot, gun, "sniper/bolt", Vector3(0.03, 0.04, 0.1))
	_box(bolt, Vector3(0.06, 0.018, 0.018), Vector3(0.02, 0.0, 0.0), steel)
	_box(bolt, Vector3(0.03, 0.03, 0.03), Vector3(0.055, -0.012, 0.0), _material(COLOR_GOLD, 0.4, 0.7))
	var mag: Node3D = _new_part(slot, gun, "sniper/mag", Vector3(0.0, -0.06, -0.06))
	_box(mag, Vector3(0.04, 0.07, 0.1), Vector3.ZERO, purple)
	_add_support_hand(gun, Vector3(-0.005, -0.06, -0.3))
	_add_muzzle(slot, gun, "sniper", Vector3(0.0, 0.03, -1.01))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.13))


func _build_minigun(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "minigun")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var pink: StandardMaterial3D = _material(COLOR_PINK, 0.0, 0.3)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.3, 0.2)
	# Dicker Motorblock mit Warnstreifen.
	_box(gun, Vector3(0.15, 0.15, 0.3), Vector3(0.0, 0.0, 0.0), pink)
	for i: int in 3:
		_box(gun, Vector3(0.154, 0.154, 0.03), Vector3(0.0, 0.0, -0.1 + 0.1 * float(i)), yellow)
	_cylinder(gun, 0.078, 0.05, Vector3(0.0, 0.0, -0.17), steel)
	# Sechs Läufe im Kreis, zusammengehalten von drei Scheiben. Das Bündel dreht sich.
	var barrels: Node3D = _new_part(slot, gun, "minigun/barrels", Vector3(0.0, 0.0, -0.2))
	for i: int in 6:
		var angle: float = TAU / 6.0 * float(i)
		_cylinder(barrels, 0.018, 0.62, Vector3(cos(angle) * 0.05, sin(angle) * 0.05, -0.31), steel)
	_cylinder(barrels, 0.074, 0.03, Vector3(0.0, 0.0, -0.18), yellow)
	_cylinder(barrels, 0.074, 0.03, Vector3(0.0, 0.0, -0.4), yellow)
	_cylinder(barrels, 0.074, 0.03, Vector3(0.0, 0.0, -0.6), pink)
	_cylinder(barrels, 0.026, 0.6, Vector3(0.0, 0.0, -0.3), yellow)
	# Tragegriff oben, Griff hinten (rechte Hand), Seitengriff vorn links (linke Hand).
	_box(gun, Vector3(0.03, 0.03, 0.22), Vector3(0.0, 0.14, -0.02), steel)
	_box(gun, Vector3(0.03, 0.07, 0.03), Vector3(0.0, 0.105, -0.11), steel)
	_box(gun, Vector3(0.03, 0.07, 0.03), Vector3(0.0, 0.105, 0.07), steel)
	_box(gun, Vector3(0.05, 0.05, 0.14), Vector3(0.0, 0.0, 0.21), steel)
	_box(gun, Vector3(0.044, 0.13, 0.05), Vector3(0.0, -0.05, 0.27), steel).rotation.x = -0.15
	_box(gun, Vector3(0.09, 0.034, 0.034), Vector3(-0.11, -0.02, -0.1), steel)
	# Munitionskasten unter dem Block.
	var box: Node3D = _new_part(slot, gun, "minigun/box", Vector3(0.0, -0.15, 0.02))
	_box(box, Vector3(0.13, 0.15, 0.2), Vector3.ZERO, yellow)
	_box(box, Vector3(0.134, 0.03, 0.204), Vector3(0.0, 0.03, 0.0), steel)
	_add_support_hand(gun, Vector3(-0.16, -0.025, -0.1))
	_add_muzzle(slot, gun, "minigun", Vector3(0.0, 0.0, -0.84))
	_add_grip_hand(gun, Vector3(0.0, -0.07, 0.28))


func _build_rocket_launcher(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "rocket_launcher")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var green: StandardMaterial3D = _material(COLOR_GREEN, 0.0, 0.2)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	var red: StandardMaterial3D = _material(COLOR_RED, 0.6, 0.1)
	# Dickes Rohr auf der Schulter mit goldenen Ringen und Trichter hinten.
	_cylinder(gun, 0.07, 0.95, Vector3(0.0, 0.07, -0.05), green)
	_cylinder(gun, 0.082, 0.05, Vector3(0.0, 0.07, -0.5), gold)
	_cylinder(gun, 0.078, 0.04, Vector3(0.0, 0.07, -0.2), gold)
	_cylinder(gun, 0.078, 0.04, Vector3(0.0, 0.07, 0.2), gold)
	_tapered(gun, 0.07, 0.11, 0.14, Vector3(0.0, 0.07, 0.49), gold)
	# Visier an der Seite, zwei Griffe unten.
	_box(gun, Vector3(0.02, 0.09, 0.02), Vector3(-0.06, 0.15, -0.22), steel)
	_box(gun, Vector3(0.05, 0.04, 0.012), Vector3(-0.06, 0.2, -0.22), _material(COLOR_LIME, 1.6, 0.0))
	_box(gun, Vector3(0.05, 0.05, 0.3), Vector3(0.0, -0.01, -0.12), steel)
	_box(gun, Vector3(0.042, 0.13, 0.055), Vector3(0.0, -0.085, 0.0), steel).rotation.x = -0.2
	_box(gun, Vector3(0.042, 0.11, 0.05), Vector3(0.0, -0.08, -0.25), steel)
	# Die Rakete schaut vorn aus dem Rohr.
	# Der Gefechtskopf ist dicker als das Rohr: So sieht man die Rakete auch von hinten.
	var rocket: Node3D = _new_part(slot, gun, "rocket_launcher/rocket", Vector3(0.0, 0.07, -0.53))
	_cylinder(rocket, 0.055, 0.1, Vector3(0.0, 0.0, -0.03), _material(COLOR_WHITE, 0.0, 0.1))
	_tapered(rocket, 0.11, 0.06, 0.07, Vector3(0.0, 0.0, -0.105), red)
	_cylinder(rocket, 0.11, 0.05, Vector3(0.0, 0.0, -0.165), red)
	_cylinder(rocket, 0.114, 0.016, Vector3(0.0, 0.0, -0.165), gold)
	_tapered(rocket, 0.01, 0.11, 0.17, Vector3(0.0, 0.0, -0.275), red)
	_add_support_hand(gun, Vector3(-0.005, -0.095, -0.25))
	_add_muzzle(slot, gun, "rocket_launcher", Vector3(0.0, 0.07, -0.62))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.01))


func _new_gun(slot: HandSlot, id: String) -> Node3D:
	var gun: Node3D = Node3D.new()
	gun.name = "Gun_%s" % id
	slot.holder.add_child(gun)
	slot.models[id] = gun
	return gun


func _new_part(slot: HandSlot, gun: Node3D, key: String, rest: Vector3) -> Node3D:
	var part: Node3D = Node3D.new()
	part.name = key.get_file().capitalize()
	part.position = rest
	gun.add_child(part)
	slot.parts[key] = part
	slot.part_rest[key] = rest
	return part


func _add_muzzle(slot: HandSlot, gun: Node3D, id: String, at: Vector3) -> void:
	var muzzle: Node3D = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = at
	gun.add_child(muzzle)
	slot.muzzles[id] = muzzle


## Rechte Hand am Griff mit Unterarm im Glitzer-Sakko, der nach unten rechts aus dem Bild läuft.
## (Bei der gespiegelten linken Waffe wird daraus die linke Hand.)
func _add_grip_hand(gun: Node3D, at: Vector3) -> void:
	_box(gun, Vector3(0.078, 0.095, 0.09), at, _material(COLOR_SKIN, 0.0, 0.0))
	var arm: MeshInstance3D = _box(gun, Vector3(0.09, 0.09, 0.44), at + Vector3(0.04, -0.09, 0.22),
		_material(COLOR_SLEEVE, 0.0, 0.1))
	arm.rotation = Vector3(0.42, 0.16, 0.0)


## Linke Hand einer Zweihand-Waffe (Vorderschaft, Tragegriff) mit Unterarm nach unten links.
func _add_support_hand(parent: Node3D, at: Vector3) -> void:
	_box(parent, Vector3(0.085, 0.07, 0.1), at, _material(COLOR_SKIN, 0.0, 0.0))
	var arm: MeshInstance3D = _box(parent, Vector3(0.085, 0.085, 0.42), at + Vector3(-0.125, -0.1, 0.17),
		_material(COLOR_SLEEVE, 0.0, 0.1))
	arm.rotation = Vector3(0.5, -0.62, 0.0)


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return _mesh_instance(parent, mesh, at, material)


## Zylinder entlang der Z-Achse (Lauf).
func _cylinder(parent: Node3D, radius: float, length: float, at: Vector3, material: Material) -> MeshInstance3D:
	return _tapered(parent, radius, radius, length, at, material)


## Zylinder entlang der Z-Achse mit verschiedenen Radien vorn (-Z) und hinten (Kegel, Trichter).
func _tapered(parent: Node3D, front_radius: float, back_radius: float, length: float, at: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	# Nach der Drehung zeigt die Oberseite des Zylinders nach hinten (+Z).
	mesh.top_radius = back_radius
	mesh.bottom_radius = front_radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	var instance: MeshInstance3D = _mesh_instance(parent, mesh, at, material)
	instance.rotation.x = PI * 0.5
	return instance


func _mesh_instance(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## Material je Farbe, Leuchten und Metallglanz (gleiche Angaben teilen sich ein Material).
func _material(color: Color, glow: float, metallic: float) -> StandardMaterial3D:
	var key: Array = [color, glow, metallic]
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.45
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	_materials[key] = material
	return material
