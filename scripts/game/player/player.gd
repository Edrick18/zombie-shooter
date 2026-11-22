extends CharacterBody3D
## Modul: Spieler (scripts/game/player).
## Der Kandidat: Körper, Kamera, Bewegung, Leben, Blick-Strahl für Interaktion, Kamera-Feedback.
## Gruppe "player". Der Ursprung des Knotens sind die Füße (auf Bodenhöhe).
##
## Aufbau (entsteht in _init, ist also schon vor add_child vorhanden):
##   Player (CharacterBody3D)
##   ├─ Shape (CollisionShape3D, Kapsel)
##   ├─ Camera (Camera3D, auf Augenhöhe)
##   │   └─ ViewModel (view_model.gd)
##   └─ WeaponController (weapon_controller.gd)
##
## Der Spieler setzt Game.player in _ready, stellt sich bei Events.run_started auf Anfang
## (volles Leben, volles Schild, alle Ausweichsprünge) und ruft bei Events.upgrade_chosen und
## Events.build_changed selbst refresh_stats().
##
## Eingaben wirken nur im State PLAYING und solange der Spieler lebt. Die Schüsse folgen immer
## der Kamera (Fadenkreuz = Bildmitte), auch während Rückstoß und Treffer-Wackeln.
##
## Kamera-Wackeln der Effekte (add_camera_shake): eigene starke Schüsse (SHOT_SHAKE), Explosionen
## in der Nähe (Stärke nach Abstand) und eigene Treffer (HIT_SHAKE_*) lassen das Bild kurz
## zittern. Das ist reines Bild: Es klingt in Bruchteilen einer Sekunde ab, und
## get_aim_direction() rechnet es heraus, die Kugeln fliegen also, als gäbe es das Zittern nicht.
## Die Stärke allen Wackelns (auch des alten bei Schlägen der Zombies) hängt an der einen
## Konstante CAMERA_SHAKE_STRENGTH.
##
## Sicherheitsglas (Gegenstand "shield", Architektur 19.2): shield / max_shield. Schaden trifft
## zuerst das Schild, nur der Rest das Leben. Nach Balance.SHIELD_RECHARGE_DELAY Sekunden ohne
## Schaden lädt es mit SHIELD_RECHARGE_RATE je Sekunde. Signal player_shield_changed.
##
## Notausgang (Gegenstand "dash"): Taste Q oder try_dash(). Ein Ausweichsprung kostet eine Ladung
## (dash_charges / max_dash_charges), bewegt den Spieler Balance.DASH_TIME Sekunden lang mit
## DASH_SPEED und macht ihn so lange unverwundbar. Die Ladungen kommen nacheinander zurück.
## Signale player_dashed und dash_charges_changed.
##
## Zweite Staffel (Gegenstand "revive", Architektur 22.3): Jedes Exemplar ist eine Ladung
## (revive_charges / max_revive_charges). Ein tödlicher Treffer verbraucht eine bereite Ladung und
## tötet nicht: Der Spieler steht mit Balance.REVIVE_HP_SHARE seines Maximal-Lebens wieder,
## ist REVIVE_INVULNERABILITY Sekunden unverwundbar und stößt alle Zombies im Umkreis
## REVIVE_SHOCKWAVE_RADIUS weg (kein Schaden). Die Ladung kommt zurück, wenn so viele Wellen
## geschafft sind, wie ihre Rarität verlangt (Stufenwert "waves", gezählt über wave_cleared).
## Signale player_revived und revive_charges_changed.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")
const WeaponController := preload("res://scripts/game/player/weapon_controller.gd")
const ViewModel := preload("res://scripts/game/player/view_model.gd")
const Settings := preload("res://scripts/game/settings.gd")

# --- Reine Optik ---
## Blick nach oben und unten begrenzt (Radiant, knapp 88 Grad).
const PITCH_LIMIT: float = 1.535
const STEP_PROBE_EXTRA: float = 0.05
const STEP_MIN_RISE: float = 0.02
const STEP_MIN_ADVANCE: float = 0.1
const STEP_SMOOTH_RATE: float = 16.0
const STEP_SMOOTH_MIN: float = 0.05
const SPRINT_FOV_BOOST: float = 6.0
const FOV_LERP_RATE: float = 8.0
## Ausweichsprung: Das Sichtfeld weitet sich kurz um so viele Grad (schneller als beim Sprinten).
const DASH_FOV_BOOST: float = 9.0
const DASH_FOV_LERP_RATE: float = 22.0
const BOB_FREQUENCY: float = 1.75
const BOB_HEIGHT: float = 0.022
const BOB_WIDTH: float = 0.014
const STRAFE_ROLL: float = 0.022
const LAND_DIP_PER_SPEED: float = 0.32
const LAND_DIP_MAX: float = 2.4
const LAND_MIN_FALL_SPEED: float = 2.0
const DIP_STIFFNESS: float = 130.0
const DIP_DAMPING: float = 15.0
const TRAUMA_DECAY: float = 1.7
const SHAKE_MAX_ANGLE: float = 0.05
## Stärke des gesamten Kamera-Wackelns: 1 = wie gebaut, 0 = kein Wackeln. Die eine Stelle zum
## Abschwächen (gilt für Schläge der Zombies, eigene Schüsse, Explosionen und eigene Treffer).
const CAMERA_SHAKE_STRENGTH: float = 1.0
## Wackeln der Effekte: größter Winkel in Radiant bei voller Stärke (gut ein Grad) und wie viel
## Stärke je Sekunde abklingt (volle Stärke ist nach einer Drittelsekunde weg).
const FX_SHAKE_MAX_ANGLE: float = 0.02
const FX_SHAKE_DECAY: float = 3.2
## Eigene Schüsse: Stärke je Waffe (0 bis 1). Waffen, die hier fehlen, wackeln nicht.
const SHOT_SHAKE: Dictionary = {
	"revolver": 0.3, "sawed_off": 0.5, "shotgun": 0.5, "sniper": 0.6, "rocket_launcher": 0.65,
	"grenade_launcher": 0.45, "auto_shotgun": 0.4, "tesla": 0.3, "crossbow": 0.2,
	"lmg": 0.12, "minigun": 0.1,
}
## Explosion: volle Stärke in ihrer Mitte, null ab dem EXPLOSION_SHAKE_REACH-fachen ihres Radius
## (mindestens EXPLOSION_SHAKE_MIN_REACH Meter).
const EXPLOSION_SHAKE: float = 1.0
const EXPLOSION_SHAKE_REACH: float = 3.0
const EXPLOSION_SHAKE_MIN_REACH: float = 4.0
## Eigene Kugeltreffer: normal, Kopftreffer oder kritisch, tödlich.
const HIT_SHAKE: float = 0.06
const HIT_SHAKE_STRONG: float = 0.12
const KILL_SHAKE: float = 0.16
const HIT_ROLL_PUNCH: float = 0.07
const HIT_ROLL_RECOVERY: float = 7.0
## Ein Sprung der Position über diese Strecke in einem Physikschritt gilt als Versetzen (kein Gleiten).
const TELEPORT_DISTANCE: float = 1.5
const DEATH_EYE_HEIGHT: float = 0.4
const DEATH_ROLL: float = 1.0

var hp: float = Balance.PLAYER_MAX_HP
var max_hp: float = Balance.PLAYER_MAX_HP
## Nach dem Tod true. Dann keine Bewegung, kein Schaden, keine Schüsse mehr.
var is_dead: bool = false
## Schild aus dem Sicherheitsglas: aktuelle und höchste Punkte. max_shield 0 = kein Schild.
var shield: float = 0.0
var max_shield: float = 0.0
## Ausweichsprünge aus dem Notausgang: verfügbare und höchstens mögliche. 0 = kein Notausgang.
var dash_charges: int = 0
var max_dash_charges: int = 0
## Zweite Staffel: bereite Ladungen und Ladungen insgesamt (eine je Exemplar). 0 / 0 = kein Exemplar.
var revive_charges: int = 0
var max_revive_charges: int = 0

## Sekunden, bis das Schild wieder lädt (jeder Schaden stellt sie neu).
var _shield_delay_left: float = 0.0
## Rest des laufenden Ausweichsprungs in Sekunden (0 = keiner) und seine Richtung (waagerecht).
var _dash_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
## Sekunden, die eine Ladung zum Nachladen braucht, und Rest für die gerade ladende.
var _dash_cooldown: float = 0.0
var _dash_recharge_left: float = 0.0
## Zweite Staffel, je Exemplar in der Reihenfolge von Game.upgrades.copies("revive"):
## { "level": int (Rarität), "waves_left": int (geschaffte Wellen bis zur Rückkehr, 0 = bereit) }.
var _revive_slots: Array[Dictionary] = []

var _camera: Camera3D
var _view_model: Node3D
var _weapon_controller: Node
var _pitch: float = 0.0
var _speed_multiplier: float = 1.0
var _invulnerable_left: float = 0.0
var _focus: Node = null
var _prompt: String = ""

var _jump_buffer_left: float = 0.0
var _coyote_left: float = 0.0
var _interact_queued: bool = false
var _is_sprinting: bool = false

# Kamera-Feedback
var _prev_position: Vector3 = Vector3.ZERO
var _cur_position: Vector3 = Vector3.ZERO
var _has_physics_sample: bool = false
var _step_offset: float = 0.0
var _dip: float = 0.0
var _dip_velocity: float = 0.0
var _kick: float = 0.0
var _trauma: float = 0.0
var _shake_time: float = 0.0
## Wackeln der Effekte (0 bis 1) und die Drehung der Kamera ohne dieses Wackeln (für die
## Blickrichtung der Schüsse).
var _fx_shake: float = 0.0
var _aim_basis: Basis = Basis.IDENTITY
var _roll_punch: float = 0.0
var _roll_sign: float = 1.0
var _strafe_roll: float = 0.0
var _bob_phase: float = 0.0
var _bob_weight: float = 0.0


func _init() -> void:
	name = "Player"
	collision_layer = Balance.LAYER_PLAYER
	collision_mask = Balance.MASK_PLAYER
	floor_snap_length = 0.25
	# Gleiches Tempo auf Rampen und Treppen wie auf ebenem Boden.
	floor_constant_speed = true
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = Balance.PLAYER_RADIUS
	capsule.height = Balance.PLAYER_HEIGHT
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = capsule
	shape.position = Vector3(0.0, Balance.PLAYER_HEIGHT * 0.5, 0.0)
	add_child(shape)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 0.0)
	_camera.fov = Settings.fov
	_camera.current = true
	add_child(_camera)
	_view_model = ViewModel.new()
	_view_model.name = "ViewModel"
	_camera.add_child(_view_model)
	_weapon_controller = WeaponController.new()
	_weapon_controller.name = "WeaponController"
	add_child(_weapon_controller)


func _ready() -> void:
	add_to_group("player")
	Game.player = self
	Settings.ensure_loaded()
	Events.run_started.connect(_on_run_started)
	Events.upgrade_chosen.connect(_on_upgrade_chosen)
	Events.build_changed.connect(refresh_stats)
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.wave_cleared.connect(_on_wave_cleared)
	Events.explosion.connect(_on_explosion)
	Events.bullet_hit.connect(_on_bullet_hit)
	Events.zombie_killed.connect(_on_zombie_killed)
	_prev_position = global_position
	_cur_position = global_position
	refresh_stats()


func _input(event: InputEvent) -> void:
	# Mausblick in _input (nicht _unhandled_input), damit kein HUD-Element die Bewegung schluckt.
	if not _can_control():
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null:
		return
	# screen_relative ist unabhängig von der Fenstergröße (Stretch), relative wäre es nicht.
	# Der Faktor aus den Einstellungen (Pausemenü) wirkt sofort, auch mitten im Lauf.
	var turn: Vector2 = motion.screen_relative * Balance.MOUSE_SENSITIVITY * Settings.mouse_sensitivity
	rotate_y(-turn.x)
	_pitch = clampf(_pitch - turn.y, -PITCH_LIMIT, PITCH_LIMIT)
	_apply_camera_transform()


func _process(delta: float) -> void:
	if is_dead:
		return
	if _can_control():
		# just_pressed ist nur in _process verlässlich genau ein Bild lang wahr.
		if Input.is_action_just_pressed("jump"):
			_jump_buffer_left = Balance.PLAYER_JUMP_BUFFER_TIME
		if Input.is_action_just_pressed("interact"):
			_interact_queued = true
		if Input.is_action_just_pressed("dash"):
			try_dash()
	_update_feedback(delta)
	_apply_camera_transform()


func _physics_process(delta: float) -> void:
	_prev_position = global_position
	_invulnerable_left = maxf(0.0, _invulnerable_left - delta)
	_tick_shield(delta)
	_tick_dash_recharge(delta)
	var controllable: bool = _can_control()
	var was_on_floor: bool = is_on_floor()
	if was_on_floor:
		_coyote_left = Balance.PLAYER_COYOTE_TIME
	else:
		_coyote_left = maxf(0.0, _coyote_left - delta)
		velocity.y -= Balance.GRAVITY * delta
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if controllable and _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		velocity.y = Balance.PLAYER_JUMP_VELOCITY
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		was_on_floor = false

	var input: Vector2 = Vector2.ZERO
	if controllable:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = global_transform.basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO
	_is_sprinting = controllable and direction != Vector3.ZERO and Input.is_action_pressed("sprint")
	var speed: float = Balance.PLAYER_SPRINT_SPEED if _is_sprinting else Balance.PLAYER_WALK_SPEED
	speed *= _speed_multiplier
	var step: float = Balance.PLAYER_ACCELERATION * delta
	if not was_on_floor:
		step *= Balance.PLAYER_AIR_CONTROL
	var dashing: bool = _dash_left > 0.0
	if dashing:
		# Ausweichsprung: festes Tempo in die gemerkte Richtung, Schwerkraft und Kollision wie sonst.
		# Endet der Sprung mitten im Schritt, zählt der Rest des Schritts mit dem normalen Tempo.
		var portion: float = clampf(_dash_left / delta, 0.0, 1.0)
		_dash_left -= delta
		if _dash_left < 0.0001:
			_dash_left = 0.0
		var dash_speed: float = lerpf(minf(speed, Balance.DASH_SPEED), Balance.DASH_SPEED, portion)
		direction = _dash_direction
		velocity.x = direction.x * dash_speed
		velocity.z = direction.z * dash_speed
	else:
		velocity.x = move_toward(velocity.x, direction.x * speed, step)
		velocity.z = move_toward(velocity.z, direction.z * speed, step)

	var wish: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var fall_speed: float = -velocity.y
	var height_before: float = global_position.y
	move_and_slide()
	var stepped: bool = false
	if was_on_floor and direction != Vector3.ZERO and is_on_wall():
		stepped = _try_step_up(wish, delta)
	if dashing and _dash_left <= 0.0:
		# Ende des Sprungs: Der Schwung fällt auf das normale Tempo, sonst rutscht der Spieler weit nach.
		var flat: Vector2 = Vector2(velocity.x, velocity.z).limit_length(speed)
		velocity.x = flat.x
		velocity.z = flat.y
	if stepped or (was_on_floor and is_on_floor()):
		# Stufen (hoch wie runter) versetzen den Körper ruckartig: die Kamera gleitet hinterher.
		var rise: float = global_position.y - height_before
		if absf(rise) >= STEP_SMOOTH_MIN:
			_step_offset = clampf(_step_offset - rise, -Balance.PLAYER_STEP_HEIGHT * 1.5, Balance.PLAYER_STEP_HEIGHT * 1.5)
	elif not was_on_floor and is_on_floor() and fall_speed > LAND_MIN_FALL_SPEED:
		_dip_velocity -= minf(fall_speed * LAND_DIP_PER_SPEED, LAND_DIP_MAX)
	_cur_position = global_position
	_has_physics_sample = true
	_update_interaction()


## Zieht Leben ab (Zombie-Schlag). Wirkt nicht während der Unverwundbarkeit nach einem Treffer,
## nicht während eines Ausweichsprungs und nicht nach dem Tod. Mit Sicherheitsglas trifft der
## Schaden zuerst das Schild, nur der Rest das Leben. Jeder Schaden (auch ein ganz abgefangener)
## stellt die Wartezeit des Schilds neu. Sendet player_damaged mit dem vollen Schaden, bei
## geändertem Schild player_shield_changed, dann player_health_changed, bei 0 Leben genau einmal
## player_died. Ist bei 0 Leben eine Ladung der Zweiten Staffel bereit, stirbt der Spieler nicht:
## player_health_changed meldet dann schon das neue Leben, danach kommen revive_charges_changed
## und player_revived.
func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0 or _invulnerable_left > 0.0 or is_dashing():
		return
	_invulnerable_left = Balance.PLAYER_HIT_INVULNERABILITY
	var absorbed: float = minf(shield, amount)
	_shield_delay_left = Balance.SHIELD_RECHARGE_DELAY
	hp = maxf(0.0, hp - (amount - absorbed))
	_trauma = minf(1.0, _trauma + 0.4 + amount / 100.0)
	_roll_sign = -_roll_sign
	_roll_punch = HIT_ROLL_PUNCH * _roll_sign
	Events.player_damaged.emit(amount)
	if absorbed > 0.0:
		_set_shield(shield - absorbed, max_shield)
	var revived: bool = hp <= 0.0 and _use_revive_charge()
	Events.player_health_changed.emit(hp, max_hp)
	if revived:
		_publish_revive()
		Events.player_revived.emit()
		_revive_shockwave()
	elif hp <= 0.0 and not is_dead:
		_die()


## Heilt bis höchstens max_hp. Sendet player_health_changed. Wirkt nicht nach dem Tod.
## Das Schild füllt sich dadurch nie.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	hp = minf(max_hp, hp + amount)
	Events.player_health_changed.emit(hp, max_hp)


## Liest Maximal-Leben, Tempo, Schild, Ausweichsprünge und die Ladungen der Zweiten Staffel neu
## aus Game.upgrades. Steigt das Maximal-Leben, heilt der Zuwachs sofort. Ein größeres Schild,
## zusätzliche Sprünge und neue Ladungen der Zweiten Staffel kommen dagegen leer dazu und laden
## erst nach, kleinere Höchstwerte kappen den Stand. Sendet player_health_changed, bei Änderung
## auch player_shield_changed, dash_charges_changed und revive_charges_changed.
func refresh_stats() -> void:
	var new_max: float = Balance.PLAYER_MAX_HP + Game.upgrades.bonus_max_hp()
	if new_max > max_hp and not is_dead:
		hp += new_max - max_hp
	max_hp = new_max
	hp = minf(hp, max_hp)
	_speed_multiplier = Game.upgrades.speed_multiplier()
	Events.player_health_changed.emit(hp, max_hp)
	var new_max_shield: float = _read_max_shield()
	_set_shield(minf(shield, new_max_shield), new_max_shield)
	var new_max_charges: int = _read_max_dash_charges()
	_dash_cooldown = Game.upgrades.value("dash", "cooldown")
	# Eine kürzere Abklingzeit gilt auch für die Ladung, die gerade lädt.
	_dash_recharge_left = minf(_dash_recharge_left, _dash_cooldown)
	_set_dash_charges(mini(dash_charges, new_max_charges), new_max_charges)
	_sync_revive(false)


## Macht einen Ausweichsprung (wie die Taste Q): in die Richtung der Bewegungstasten, ohne
## Eingabe geradeaus in Blickrichtung. Kostet eine Ladung. Gibt false zurück (und tut nichts)
## ohne Notausgang, ohne Ladung, während eines Sprungs, außerhalb des States PLAYING oder nach
## dem Tod. Sendet player_dashed und dash_charges_changed.
func try_dash() -> bool:
	if not _can_control() or max_dash_charges <= 0 or dash_charges <= 0 or is_dashing():
		return false
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = global_transform.basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = -global_transform.basis.z
		direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return false
	_dash_direction = direction.normalized()
	_dash_left = Balance.DASH_TIME
	_set_dash_charges(dash_charges - 1, max_dash_charges)
	Events.player_dashed.emit()
	return true


## Läuft gerade ein Ausweichsprung? (So lange nimmt der Spieler keinen Schaden.)
func is_dashing() -> bool:
	return _dash_left > 0.0


## Zweite Staffel: je Ladung die Zahl der Wellen, die noch geschafft werden müssen, bis sie
## wieder bereit ist (0 = bereit), in der Reihenfolge der Exemplare. Leer ohne Exemplar.
func get_revive_waves_left() -> Array[int]:
	var result: Array[int] = []
	for slot: Dictionary in _revive_slots:
		result.append(int(slot["waves_left"]))
	return result


## Weltposition der Augen (Start von Schuss- und Blick-Strahl).
func get_eye_position() -> Vector3:
	if not _camera.is_inside_tree():
		return position + _camera.position
	return _camera.global_position


## Blickrichtung der Kamera als Einheitsvektor in Weltkoordinaten. Das Wackeln der Effekte
## (add_camera_shake) zählt nicht mit: Es ist nur Bild und lenkt keinen Schuss ab.
func get_aim_direction() -> Vector3:
	if not _camera.is_inside_tree():
		return Vector3.FORWARD
	if _fx_shake <= 0.0:
		return -_camera.global_transform.basis.z.normalized()
	return -(global_transform.basis * _aim_basis).z.normalized()


## Lässt die Kamera kurz zittern (reine Optik). amount 0 bis 1: Die Stärke steigt auf diesen
## Wert, wenn sie darunter liegt, und klingt mit FX_SHAKE_DECAY je Sekunde ab. Mehrere Auslöser
## addieren sich nicht, das Zittern bleibt also immer klein.
func add_camera_shake(amount: float) -> void:
	if is_dead:
		return
	_fx_shake = clampf(maxf(_fx_shake, amount), 0.0, 1.0)


## Aktuelle Stärke des Wackelns der Effekte (0 = ruhig).
func get_camera_shake() -> float:
	return _fx_shake


## Die Kamera des Spielers.
func get_camera() -> Camera3D:
	return _camera


## Der WeaponController des Spielers.
func get_weapon_controller() -> Node:
	return _weapon_controller


## Richtet den Blick sofort auf einen Punkt in Weltkoordinaten (für Tests und Skripte, ohne Maus).
## Rückstoß und Wackeln werden dabei zurückgesetzt, der Schuss danach geht genau dorthin.
func look_at_point(target: Vector3) -> void:
	var eye: Vector3 = global_position + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 0.0)
	var to_target: Vector3 = target - eye
	if to_target.length_squared() < 0.000001:
		return
	var flat: float = Vector2(to_target.x, to_target.z).length()
	if flat > 0.00001:
		rotation.y = atan2(-to_target.x, -to_target.z)
	_pitch = clampf(atan2(to_target.y, flat), -PITCH_LIMIT, PITCH_LIMIT)
	_reset_feedback()
	_apply_camera_transform()


## Blick nach oben (+) oder unten (-) in Radiant, ohne Rückstoß und Wackeln.
func get_look_pitch() -> float:
	return _pitch


## Sprintet der Spieler gerade?
func is_sprinting() -> bool:
	return _is_sprinting


## Ist der Spieler gerade gegen Zombie-Schläge unverwundbar (kurz nach einem Treffer)?
func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func _on_run_started() -> void:
	is_dead = false
	_invulnerable_left = 0.0
	_jump_buffer_left = 0.0
	_interact_queued = false
	velocity = Vector3.ZERO
	max_hp = Balance.PLAYER_MAX_HP + Game.upgrades.bonus_max_hp()
	hp = max_hp
	_speed_multiplier = Game.upgrades.speed_multiplier()
	_reset_feedback()
	_camera.fov = Settings.fov
	_apply_camera_transform()
	_prompt = ""
	_focus = null
	Events.interact_prompt_changed.emit("")
	Events.player_health_changed.emit(hp, max_hp)
	# Neuer Lauf: volles Schild und alle Ausweichsprünge.
	_shield_delay_left = 0.0
	_dash_left = 0.0
	_dash_recharge_left = 0.0
	_dash_cooldown = Game.upgrades.value("dash", "cooldown")
	var full_shield: float = _read_max_shield()
	_set_shield(full_shield, full_shield)
	var full_charges: int = _read_max_dash_charges()
	_set_dash_charges(full_charges, full_charges)
	# Und mit allen Ladungen der Zweiten Staffel.
	_sync_revive(true)


func _on_upgrade_chosen(_upgrade_id: String, _new_level: int) -> void:
	refresh_stats()


## Höchstwert des Schilds aus allen Exemplaren des Sicherheitsglases (0 ohne).
func _read_max_shield() -> float:
	return maxf(0.0, Game.upgrades.value("shield", "amount"))


## Zahl der Ausweichsprünge: einer je Exemplar des Notausgangs (0 ohne).
func _read_max_dash_charges() -> int:
	if Game.upgrades.get_level("dash") <= 0:
		return 0
	return maxi(0, int(Game.upgrades.value("dash", "charges")))


## Setzt Schild und Höchstwert und sendet player_shield_changed, wenn sich einer der Werte ändert.
func _set_shield(new_shield: float, new_max: float) -> void:
	new_max = maxf(0.0, new_max)
	new_shield = clampf(new_shield, 0.0, new_max)
	if new_shield == shield and new_max == max_shield:
		return
	shield = new_shield
	max_shield = new_max
	Events.player_shield_changed.emit(shield, max_shield)


## Setzt Ladungen und Höchstzahl der Ausweichsprünge, hält die Nachladezeit passend und sendet
## dash_charges_changed, wenn sich einer der Werte ändert.
func _set_dash_charges(new_charges: int, new_max: int) -> void:
	new_max = maxi(0, new_max)
	new_charges = clampi(new_charges, 0, new_max)
	var changed: bool = new_charges != dash_charges or new_max != max_dash_charges
	dash_charges = new_charges
	max_dash_charges = new_max
	if dash_charges >= max_dash_charges:
		_dash_recharge_left = 0.0
	elif _dash_recharge_left <= 0.0:
		_dash_recharge_left = _dash_cooldown
	if changed:
		Events.dash_charges_changed.emit(dash_charges, max_dash_charges)


## Schild: Die Wartezeit nach einem Schaden läuft ab, danach lädt es bis zum Höchstwert.
func _tick_shield(delta: float) -> void:
	if _shield_delay_left > 0.0:
		_shield_delay_left = maxf(0.0, _shield_delay_left - delta)
		return
	if is_dead or shield >= max_shield:
		return
	var charged: float = shield + Balance.SHIELD_RECHARGE_RATE * delta
	# Knapp unter dem Höchstwert gilt als voll (Rundungsreste), das letzte Signal meldet genau ihn.
	if charged >= max_shield - 0.0001:
		charged = max_shield
	_set_shield(charged, max_shield)


## Ausweichsprünge laden nacheinander nach: immer nur eine Ladung zur selben Zeit.
func _tick_dash_recharge(delta: float) -> void:
	if is_dead or dash_charges >= max_dash_charges:
		return
	_dash_recharge_left -= delta
	if _dash_recharge_left > 0.0:
		return
	_dash_recharge_left = 0.0
	_set_dash_charges(dash_charges + 1, max_dash_charges)


# --- Zweite Staffel ---

## Wellen, nach denen eine Ladung dieser Rarität wiederkommt (mindestens 1).
func _revive_waves(level: int) -> int:
	return maxi(1, roundi(UpgradeDefs.value("revive", "waves", level)))


## Gleicht die Ladungen mit den Exemplaren der Zweiten Staffel ab (eine je Exemplar, mit dessen
## Rarität). full = true (neuer Lauf): alle Ladungen sind bereit. Sonst behält jede Ladung ihren
## Stand: erst die mit gleicher Rarität, dann wandern übrige Ladungen auf geänderte Raritäten
## (kombinierte Gegenstände, ihre Wartezeit höchstens die neue). Was dann noch fehlt, ist neu und
## kommt leer: Es wartet seine volle Zahl an Wellen (sonst wäre Ein- und Ausräumen im Rucksack
## eine Gratis-Ladung).
func _sync_revive(full: bool) -> void:
	var wanted: Array[int] = []
	for entry: Variant in Game.upgrades.copies("revive"):
		if int(entry) > 0:
			wanted.append(clampi(int(entry), 1, Balance.UPGRADE_MAX_LEVEL))
	var slots: Array[Dictionary] = []
	if full:
		for level: int in wanted:
			slots.append({"level": level, "waves_left": 0})
	else:
		var old: Array[Dictionary] = _revive_slots.duplicate()
		# Erst die Ladungen mit gleicher Rarität zuordnen (null = noch offen).
		var matched: Array = []
		for level: int in wanted:
			var found: Variant = null
			for i: int in old.size():
				if int(old[i]["level"]) == level:
					found = old[i]
					old.remove_at(i)
					break
			matched.append(found)
		for i: int in wanted.size():
			var waves: int = _revive_waves(wanted[i])
			if matched[i] != null:
				slots.append(matched[i] as Dictionary)
			elif not old.is_empty():
				var moved: Dictionary = old.pop_front()
				slots.append({"level": wanted[i], "waves_left": mini(int(moved["waves_left"]), waves)})
			else:
				slots.append({"level": wanted[i], "waves_left": waves})
	_revive_slots = slots
	_publish_revive()


## Zählt die bereiten Ladungen und sendet revive_charges_changed, wenn sich etwas geändert hat.
func _publish_revive() -> void:
	var available: int = 0
	for slot: Dictionary in _revive_slots:
		if int(slot["waves_left"]) <= 0:
			available += 1
	var total: int = _revive_slots.size()
	if available == revive_charges and total == max_revive_charges:
		return
	revive_charges = available
	max_revive_charges = total
	Events.revive_charges_changed.emit(revive_charges, max_revive_charges)


## Verbraucht bei einem tödlichen Treffer eine bereite Ladung: Leben auf den Anteil
## Balance.REVIVE_HP_SHARE, unverwundbar für REVIVE_INVULNERABILITY Sekunden. Von mehreren
## bereiten geht die Ladung, die am schnellsten wiederkommt. Gibt false zurück (und tut nichts),
## wenn keine Ladung bereit ist. Die Signale sendet take_damage.
func _use_revive_charge() -> bool:
	var best: int = -1
	var best_waves: int = 0
	for i: int in _revive_slots.size():
		if int(_revive_slots[i]["waves_left"]) > 0:
			continue
		var waves: int = _revive_waves(int(_revive_slots[i]["level"]))
		if best < 0 or waves < best_waves:
			best = i
			best_waves = waves
	if best < 0:
		return false
	_revive_slots[best]["waves_left"] = best_waves
	hp = maxf(1.0, max_hp * Balance.REVIVE_HP_SHARE)
	_invulnerable_left = Balance.REVIVE_INVULNERABILITY
	return true


## Druckwelle der Zweiten Staffel: stößt alle lebenden Zombies im Umkreis
## Balance.REVIVE_SHOCKWAVE_RADIUS (Füße zu Füßen) vom Spieler weg. Schaden macht sie nur, wenn
## Balance.REVIVE_SHOCKWAVE_DAMAGE über 0 liegt (source "shockwave").
func _revive_shockwave() -> void:
	if not is_inside_tree():
		return
	var center: Vector3 = global_position
	Fx.shockwave(Fx.root_of(self), center, Balance.REVIVE_SHOCKWAVE_RADIUS)
	# Die Schleife läuft ohne Typ: Ein Zombie kann mittendrin verschwinden.
	for entry: Variant in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(entry) or not entry is Node3D:
			continue
		var zombie: Node3D = entry
		if bool(zombie.get("is_dead")) or zombie.is_queued_for_deletion():
			continue
		var offset: Vector3 = zombie.global_position - center
		if offset.length() > Balance.REVIVE_SHOCKWAVE_RADIUS:
			continue
		var push: Vector3 = Vector3(offset.x, 0.0, offset.z)
		if push.length_squared() < 0.0001:
			push = -global_basis.z
			push.y = 0.0
		if push.length_squared() < 0.0001:
			push = Vector3.FORWARD
		if Balance.REVIVE_SHOCKWAVE_DAMAGE > 0.0 and zombie.has_method("take_damage"):
			zombie.call("take_damage", Balance.REVIVE_SHOCKWAVE_DAMAGE, {"source": "shockwave", "hit_position": zombie.global_position})
		if zombie.has_method("apply_knockback"):
			zombie.call("apply_knockback", push.normalized() * Balance.REVIVE_SHOCKWAVE_KNOCKBACK)


## Eine Welle ist geschafft: Verbrauchte Ladungen der Zweiten Staffel rücken eine Welle näher.
func _on_wave_cleared(_wave: int) -> void:
	if is_dead:
		return
	for slot: Dictionary in _revive_slots:
		if int(slot["waves_left"]) > 0:
			slot["waves_left"] = int(slot["waves_left"]) - 1
	_publish_revive()


func _on_weapon_fired(weapon_id: String) -> void:
	if is_dead:
		return
	_kick = minf(_kick + deg_to_rad(float(Balance.CAMERA_RECOIL_KICK_DEG.get(weapon_id, 0.0))), deg_to_rad(Balance.CAMERA_RECOIL_MAX_DEG))
	add_camera_shake(float(SHOT_SHAKE.get(weapon_id, 0.0)))


## Explosion in der Nähe: Die Kamera zittert, je näher desto stärker.
func _on_explosion(at: Vector3, radius: float) -> void:
	if is_dead or not is_inside_tree():
		return
	var reach: float = maxf(radius * EXPLOSION_SHAKE_REACH, EXPLOSION_SHAKE_MIN_REACH)
	add_camera_shake(EXPLOSION_SHAKE * clampf(1.0 - get_eye_position().distance_to(at) / reach, 0.0, 1.0))


## Eigener Kugeltreffer: ein winziger Ruck, bei Kopftreffer und kritischem Treffer etwas mehr.
func _on_bullet_hit(_zombie: Node3D, _damage: float, info: Dictionary) -> void:
	var strong: bool = bool(info.get("headshot", false)) or bool(info.get("crit", false))
	add_camera_shake(HIT_SHAKE_STRONG if strong else HIT_SHAKE)


## Eigene Kugel tötet: etwas mehr Ruck als ein Treffer.
func _on_zombie_killed(_zombie: Node3D, info: Dictionary) -> void:
	if String(info.get("source", "")) == "bullet":
		add_camera_shake(KILL_SHAKE)


## Darf der Spieler gerade steuern? (lebt und der Lauf ist im State PLAYING)
func _can_control() -> bool:
	return not is_dead and Game.state == Game.State.PLAYING


## Tod: genau einmal. Die Kamera kippt zu Boden, dann erst geht player_died raus (Game pausiert).
func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	_is_sprinting = false
	_dash_left = 0.0
	if _prompt != "":
		_prompt = ""
		Events.interact_prompt_changed.emit("")
	_focus = null
	_camera.position = Vector3(0.0, DEATH_EYE_HEIGHT, 0.0)
	_camera.rotation = Vector3(_pitch * 0.3, 0.0, DEATH_ROLL * _roll_sign)
	Events.player_died.emit()


## Läuft eine niedrige Stufe hoch, an der move_and_slide hängen blieb. Gibt true zurück, wenn
## der Körper versetzt wurde. wish ist die gewünschte waagerechte Geschwindigkeit.
func _try_step_up(wish: Vector3, delta: float) -> bool:
	if wish.length_squared() < 0.01:
		return false
	var direction: Vector3 = wish.normalized()
	var up: Vector3 = Vector3.UP * Balance.PLAYER_STEP_HEIGHT
	var base: Transform3D = global_transform
	if test_move(base, up):
		return false
	var lifted: Transform3D = base.translated(up)
	# Erst prüfen, ob dahinter wirklich eine flache Stufe liegt (keine Wand, keine steile Schräge).
	var probe: Vector3 = direction * (Balance.PLAYER_RADIUS + STEP_PROBE_EXTRA)
	if test_move(lifted, probe):
		return false
	var top: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(lifted.translated(probe), -up, top):
		return false
	if top.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false
	# Dann nur so weit vorrücken wie nötig und dort absetzen.
	var advance: Vector3 = direction * maxf(wish.length() * delta, STEP_MIN_ADVANCE)
	if test_move(lifted, advance):
		return false
	var target: Transform3D = lifted.translated(advance)
	var landing: KinematicCollision3D = KinematicCollision3D.new()
	if not test_move(target, -up, landing):
		return false
	var travel: Vector3 = landing.get_travel()
	if Balance.PLAYER_STEP_HEIGHT - travel.length() < STEP_MIN_RISE:
		return false
	global_position = target.origin + travel
	velocity.x = wish.x
	velocity.z = wish.z
	velocity.y = 0.0
	return true


## Federn, Wackeln und Schrittbewegung der Kamera weiterrechnen.
func _update_feedback(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	# Landung: gedämpfte Feder.
	_dip_velocity += (-DIP_STIFFNESS * _dip - DIP_DAMPING * _dip_velocity) * dt
	_dip += _dip_velocity * dt
	_dip = clampf(_dip, -0.35, 0.15)
	# Stufen ausgleichen, Rückstoß und Schlag abklingen lassen.
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-STEP_SMOOTH_RATE * dt))
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-Balance.CAMERA_RECOIL_RECOVERY * dt))
	_roll_punch = lerpf(_roll_punch, 0.0, 1.0 - exp(-HIT_ROLL_RECOVERY * dt))
	_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * dt)
	_fx_shake = maxf(0.0, _fx_shake - FX_SHAKE_DECAY * dt)
	_shake_time += dt
	# Schritte und Seitenneigung aus der Bewegung.
	var local_velocity: Vector3 = global_transform.basis.inverse() * velocity
	var flat_speed: float = Vector2(velocity.x, velocity.z).length()
	var grounded: bool = is_on_floor()
	var bob_target: float = 0.0
	if grounded and flat_speed > 0.5:
		bob_target = clampf(flat_speed / Balance.PLAYER_WALK_SPEED, 0.0, 1.4)
	_bob_weight = lerpf(_bob_weight, bob_target, 1.0 - exp(-10.0 * dt))
	_bob_phase = fposmod(_bob_phase + flat_speed * BOB_FREQUENCY * dt, TAU)
	var roll_target: float = -clampf(local_velocity.x / Balance.PLAYER_SPRINT_SPEED, -1.0, 1.0) * STRAFE_ROLL
	_strafe_roll = lerpf(_strafe_roll, roll_target, 1.0 - exp(-8.0 * dt))
	# Sichtfeld weitet sich beim Sprinten.
	# Das Grund-Sichtfeld kommt aus den Einstellungen (Standard Balance.PLAYER_FOV).
	var fov_target: float = Settings.fov
	var fov_rate: float = FOV_LERP_RATE
	if _is_sprinting and flat_speed > Balance.PLAYER_WALK_SPEED * 0.9:
		fov_target += SPRINT_FOV_BOOST
	if is_dashing():
		# Ausweichsprung: kurzer, schneller Ruck nach außen. Danach kehrt es im normalen Tempo zurück.
		fov_target += DASH_FOV_BOOST
		fov_rate = DASH_FOV_LERP_RATE
	_camera.fov = lerpf(_camera.fov, fov_target, 1.0 - exp(-fov_rate * dt))


## Setzt die Kamera aus Blickwinkel und allen Feedback-Anteilen zusammen.
func _apply_camera_transform() -> void:
	if is_dead:
		return
	var eye: Vector3 = Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 0.0)
	eye.y += _dip + _step_offset + sin(_bob_phase * 2.0) * BOB_HEIGHT * _bob_weight
	eye.x += cos(_bob_phase) * BOB_WIDTH * _bob_weight
	eye += _interpolation_offset()
	_camera.position = eye
	var shake: float = _trauma * _trauma * SHAKE_MAX_ANGLE * CAMERA_SHAKE_STRENGTH
	var shake_pitch: float = shake * sin(_shake_time * 61.0 + 1.3) * sin(_shake_time * 23.0)
	var shake_yaw: float = shake * sin(_shake_time * 53.0) * sin(_shake_time * 29.0 + 0.7)
	var shake_roll: float = shake * 0.8 * sin(_shake_time * 47.0 + 2.1)
	var turn: Vector3 = Vector3(
		clampf(_pitch + _kick + shake_pitch, -PITCH_LIMIT, PITCH_LIMIT),
		shake_yaw,
		_strafe_roll + _roll_punch + shake_roll
	)
	# Bis hierher zählt alles für die Blickrichtung der Schüsse (wie immer). Das Wackeln der
	# Effekte kommt nur ins Bild.
	_aim_basis = Basis.from_euler(turn)
	var fx: float = _fx_shake * FX_SHAKE_MAX_ANGLE * CAMERA_SHAKE_STRENGTH
	if fx > 0.0:
		turn.x = clampf(turn.x + fx * sin(_shake_time * 67.0 + 0.9) * cos(_shake_time * 31.0), -PITCH_LIMIT, PITCH_LIMIT)
		turn.y += fx * sin(_shake_time * 59.0 + 2.3) * cos(_shake_time * 37.0 + 1.1)
		turn.z += fx * 0.5 * sin(_shake_time * 43.0 + 0.3)
	_camera.rotation = turn


## Die Physik läuft mit festen Schritten, das Bild meist öfter: Die Kamera gleitet zwischen der
## vorigen und der aktuellen Körperposition, damit die Bewegung bei jeder Bildrate flüssig ist.
## Ergebnis im lokalen Raum des Spielers.
func _interpolation_offset() -> Vector3:
	if not _has_physics_sample or not is_inside_tree():
		return Vector3.ZERO
	var back: Vector3 = _prev_position - _cur_position
	if back.length_squared() > TELEPORT_DISTANCE * TELEPORT_DISTANCE:
		return Vector3.ZERO
	# Wurde der Körper außerhalb der Physik versetzt, stimmt die Aufzeichnung nicht mehr.
	if global_position.distance_squared_to(_cur_position) > 0.000001:
		return Vector3.ZERO
	var fraction: float = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	return global_transform.basis.inverse() * (back * (1.0 - fraction))


func _reset_feedback() -> void:
	_step_offset = 0.0
	_dip = 0.0
	_dip_velocity = 0.0
	_kick = 0.0
	_trauma = 0.0
	_fx_shake = 0.0
	_roll_punch = 0.0
	_strafe_roll = 0.0
	_bob_weight = 0.0
	_prev_position = global_position if is_inside_tree() else position
	_cur_position = _prev_position


## Blick-Strahl: sucht ein Interaktionsobjekt, meldet dessen Hinweis und löst bei Taste E aus.
func _update_interaction() -> void:
	var focus: Node = null
	var text: String = ""
	if _can_control():
		focus = _find_focus()
		if focus != null:
			text = String(focus.call("get_prompt"))
	_focus = focus
	if text != _prompt:
		_prompt = text
		Events.interact_prompt_changed.emit(_prompt)
	var wants_interact: bool = _interact_queued
	_interact_queued = false
	if wants_interact and is_instance_valid(focus):
		focus.call("interact", self)


## Knoten der Gruppe "interactables" im Blick: der getroffene Collider oder einer seiner Vorfahren.
func _find_focus() -> Node:
	var from: Vector3 = get_eye_position()
	var to: Vector3 = from + get_aim_direction() * Balance.INTERACT_RANGE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, Balance.MASK_INTERACT)
	query.collide_with_areas = true
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node: Node = hit["collider"] as Node
	while is_instance_valid(node):
		if node.is_in_group("interactables") and node.has_method("get_prompt") and node.has_method("interact"):
			return node
		node = node.get_parent()
	return null
