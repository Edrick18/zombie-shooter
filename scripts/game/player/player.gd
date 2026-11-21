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
## (volles Leben) und ruft bei Events.upgrade_chosen selbst refresh_stats().
##
## Eingaben wirken nur im State PLAYING und solange der Spieler lebt. Die Schüsse folgen immer
## der Kamera (Fadenkreuz = Bildmitte), auch während Rückstoß und Treffer-Wackeln.

const Balance := preload("res://scripts/core/balance.gd")
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
	_update_feedback(delta)
	_apply_camera_transform()


func _physics_process(delta: float) -> void:
	_prev_position = global_position
	_invulnerable_left = maxf(0.0, _invulnerable_left - delta)
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
	velocity.x = move_toward(velocity.x, direction.x * speed, step)
	velocity.z = move_toward(velocity.z, direction.z * speed, step)

	var wish: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var fall_speed: float = -velocity.y
	var height_before: float = global_position.y
	move_and_slide()
	var stepped: bool = false
	if was_on_floor and direction != Vector3.ZERO and is_on_wall():
		stepped = _try_step_up(wish, delta)
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


## Zieht Leben ab (Zombie-Schlag). Wirkt nicht während der Unverwundbarkeit nach einem Treffer
## und nicht nach dem Tod. Sendet player_damaged und player_health_changed, bei 0 Leben
## genau einmal player_died.
func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0 or _invulnerable_left > 0.0:
		return
	_invulnerable_left = Balance.PLAYER_HIT_INVULNERABILITY
	hp = maxf(0.0, hp - amount)
	_trauma = minf(1.0, _trauma + 0.4 + amount / 100.0)
	_roll_sign = -_roll_sign
	_roll_punch = HIT_ROLL_PUNCH * _roll_sign
	Events.player_damaged.emit(amount)
	Events.player_health_changed.emit(hp, max_hp)
	if hp <= 0.0 and not is_dead:
		_die()


## Heilt bis höchstens max_hp. Sendet player_health_changed. Wirkt nicht nach dem Tod.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	hp = minf(max_hp, hp + amount)
	Events.player_health_changed.emit(hp, max_hp)


## Liest Maximal-Leben und Tempo neu aus Game.upgrades. Steigt das Maximal-Leben, heilt der
## Zuwachs sofort. Sendet player_health_changed.
func refresh_stats() -> void:
	var new_max: float = Balance.PLAYER_MAX_HP + Game.upgrades.bonus_max_hp()
	if new_max > max_hp and not is_dead:
		hp += new_max - max_hp
	max_hp = new_max
	hp = minf(hp, max_hp)
	_speed_multiplier = Game.upgrades.speed_multiplier()
	Events.player_health_changed.emit(hp, max_hp)


## Weltposition der Augen (Start von Schuss- und Blick-Strahl).
func get_eye_position() -> Vector3:
	if not _camera.is_inside_tree():
		return position + _camera.position
	return _camera.global_position


## Blickrichtung der Kamera als Einheitsvektor in Weltkoordinaten.
func get_aim_direction() -> Vector3:
	if not _camera.is_inside_tree():
		return Vector3.FORWARD
	return -_camera.global_transform.basis.z.normalized()


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


func _on_upgrade_chosen(_upgrade_id: String, _new_level: int) -> void:
	refresh_stats()


func _on_weapon_fired(weapon_id: String) -> void:
	if is_dead:
		return
	_kick = minf(_kick + deg_to_rad(float(Balance.CAMERA_RECOIL_KICK_DEG.get(weapon_id, 0.0))), deg_to_rad(Balance.CAMERA_RECOIL_MAX_DEG))


## Darf der Spieler gerade steuern? (lebt und der Lauf ist im State PLAYING)
func _can_control() -> bool:
	return not is_dead and Game.state == Game.State.PLAYING


## Tod: genau einmal. Die Kamera kippt zu Boden, dann erst geht player_died raus (Game pausiert).
func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	_is_sprinting = false
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
	if _is_sprinting and flat_speed > Balance.PLAYER_WALK_SPEED * 0.9:
		fov_target += SPRINT_FOV_BOOST
	_camera.fov = lerpf(_camera.fov, fov_target, 1.0 - exp(-FOV_LERP_RATE * dt))


## Setzt die Kamera aus Blickwinkel und allen Feedback-Anteilen zusammen.
func _apply_camera_transform() -> void:
	if is_dead:
		return
	var eye: Vector3 = Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 0.0)
	eye.y += _dip + _step_offset + sin(_bob_phase * 2.0) * BOB_HEIGHT * _bob_weight
	eye.x += cos(_bob_phase) * BOB_WIDTH * _bob_weight
	eye += _interpolation_offset()
	_camera.position = eye
	var shake: float = _trauma * _trauma * SHAKE_MAX_ANGLE
	var shake_pitch: float = shake * sin(_shake_time * 61.0 + 1.3) * sin(_shake_time * 23.0)
	var shake_yaw: float = shake * sin(_shake_time * 53.0) * sin(_shake_time * 29.0 + 0.7)
	var shake_roll: float = shake * 0.8 * sin(_shake_time * 47.0 + 2.1)
	_camera.rotation = Vector3(
		clampf(_pitch + _kick + shake_pitch, -PITCH_LIMIT, PITCH_LIMIT),
		shake_yaw,
		_strafe_roll + _roll_punch + shake_roll
	)


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
