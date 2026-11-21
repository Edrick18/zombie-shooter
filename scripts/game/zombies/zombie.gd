extends CharacterBody3D
## Modul: Zombies (scripts/game/zombies).
## Ein Zombie: Leben, Schadensweg (Abschnitt 7), Brand, Rückstoß, Angriff mit Ausholen, Wegfindung.
## Gruppe "zombies" (nur solange er lebt). Der Ursprung des Knotens sind die Füße.
##
## Aufbau (entsteht in _ready):
##   Zombie (CharacterBody3D, Lage 3, Maske 1 + 2 + 3)
##   ├─ Shape      CollisionShape3D, Kapsel über die ganze Körperhöhe
##   ├─ Body       MeshInstance3D, Rumpf. Trägt alle sichtbaren Teile und wird als Ganzes animiert.
##   │   ├─ Head   MeshInstance3D, Kugel. Liegt genau im Kopftreffer-Bereich (über HEADSHOT_HEIGHT_RATIO).
##   │   ├─ ArmL / ArmR   Node3D an der Schulter mit je einem Arm nach vorn
##   │   └─ Flames Node3D, nur bei Brand sichtbar
##   ├─ NavAgent   NavigationAgent3D
##   ├─ Glow       OmniLight3D (nur Elite)
##   └─ HealthBar  Node3D (nur Elite), dreht sich zur Kamera
##
## Bewegung: Ziel ist Game.player. Der Pfad wird alle Balance.ZOMBIE_REPATH_INTERVAL s neu
## berechnet. Gibt es kein Navigationsnetz oder keinen Pfad (headless-Test, Spieler abseits des
## Netzes), läuft der Zombie geradeaus auf den Spieler zu. Niedrige Kanten überspringt er.

const Balance := preload("res://scripts/core/balance.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")

# --- Reine Optik und Technik ---
const HOP_MARGIN: float = 0.12
const SEPARATION_INTERVAL: float = 0.1
## Waagerechter Abstand (m), ab dem ein Pfadpunkt als erreicht gilt.
const WAYPOINT_REACHED: float = 0.2
const TURN_SPEED: float = 10.0
const FACE_PLAYER_DISTANCE: float = 3.0
const BURN_EPSILON: float = 0.0001
const FLASH_TIME: float = 0.09
const FLASH_STRENGTH: float = 0.75
const PUNCH_TIME: float = 0.14
const SPAWN_GROW_TIME: float = 0.35
const STRIKE_TIME: float = 0.3
const WOBBLE_RAD_PER_METER: float = 3.9
const ARM_RAISED: float = 1.75
const ARM_SLAM: float = -0.75
## Neigung des Körpers (Radiant um die Füße). Klein gehalten, damit der sichtbare Kopf über der
## Kollisionskapsel bleibt und Kopfschüsse dort treffen, wo man den Kopf sieht.
const WINDUP_LEAN: float = 0.12
const STRIKE_LEAN: float = -0.32
const STRIKE_LUNGE: float = 0.14
const BODY_SHARE: float = 0.8
const HEAD_RADIUS_SHARE: float = 0.112
const SHOULDER_SHARE: float = 0.66
const ARM_LENGTH_SHARE: float = 0.36
const ARM_THICKNESS_SHARE: float = 0.085
const BURN_COLOR: Color = Color(1.0, 0.45, 0.08)
const FLAME_COLOR: Color = Color(1.0, 0.62, 0.1)
const DEATH_COLOR: Color = Color(0.12, 0.1, 0.1)
const BAR_WIDTH: float = 0.9
const BAR_HEIGHT: float = 0.09

## "walker", "sprinter" oder "elite".
var zombie_type: String = WavePlan.TYPE_WALKER
var max_hp: float = 1.0
var hp: float = 1.0
## Ab dem tödlichen Treffer true. Tote Zombies nehmen keinen Schaden und sterben nie zweimal.
var is_dead: bool = false
## Welle, für die der Zombie erzeugt wurde.
var wave: int = 1
var move_speed: float = 0.0
var attack_damage: float = 0.0
## Körperhöhe in Metern (Elite: 1,3-fach). Grundlage für Kopftreffer.
var body_height: float = Balance.ZOMBIE_HEIGHT
var body_radius: float = Balance.ZOMBIE_RADIUS

var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _head: MeshInstance3D
var _arm_left: Node3D
var _arm_right: Node3D
var _flames: Node3D
var _glow: OmniLight3D
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _agent: NavigationAgent3D
var _skin: StandardMaterial3D
var _base_color: Color = Color.WHITE
var _base_emission: Color = Color.BLACK
var _body_rest: Vector3 = Vector3.ZERO
var _head_rest: Vector3 = Vector3.ZERO
var _lean_rest: float = 0.0
var _sway_amount: float = 0.1
var _glow_energy: float = 0.0

var _knockback: Vector3 = Vector3.ZERO
var _lift: float = 0.0
var _separation: Vector3 = Vector3.ZERO
var _separation_left: float = 0.0
var _repath_left: float = 0.0
var _path_valid: bool = false
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _hop_cooldown_left: float = 0.0
var _walk_speed_now: float = 0.0
var _burn_dps: float = 0.0
var _burn_left: float = 0.0
var _burn_accum: float = 0.0
var _windup_left: float = -1.0
var _attack_cooldown_left: float = 0.0
var _death_left: float = 0.0

var _anim_time: float = 0.0
var _walk_phase: float = 0.0
var _flash_left: float = 0.0
var _punch: float = 0.0
var _spawn_grow: float = 0.0
var _strike_left: float = 0.0
var _death_side: float = 1.0
var _material_dirty: bool = true


## Legt Typ und Welle fest und berechnet daraus Leben, Tempo, Schaden und Größe.
## Vor add_child aufrufen. Unbekannte Typen werden zu "walker".
func setup(type: String, wave_number: int) -> void:
	zombie_type = type if Balance.ZOMBIE_TYPES.has(type) else WavePlan.TYPE_WALKER
	wave = maxi(wave_number, 1)
	var def: Dictionary = Balance.ZOMBIE_TYPES[zombie_type]
	max_hp = WavePlan.zombie_hp(zombie_type, wave)
	hp = max_hp
	move_speed = WavePlan.zombie_speed(zombie_type, wave)
	attack_damage = WavePlan.zombie_damage(zombie_type)
	body_height = Balance.ZOMBIE_HEIGHT * float(def["scale"])
	body_radius = Balance.ZOMBIE_RADIUS * float(def["scale"])


func _ready() -> void:
	if hp <= 0.0 or move_speed <= 0.0:
		setup(zombie_type, wave)
	add_to_group("zombies")
	collision_layer = Balance.LAYER_ZOMBIES
	collision_mask = Balance.MASK_ZOMBIE
	floor_snap_length = 0.25
	_build_body()
	_build_agent()
	# Zeitversatz, damit nicht alle Zombies im selben Bild rechnen und im Gleichschritt wackeln.
	_repath_left = randf() * Balance.ZOMBIE_REPATH_INTERVAL
	_separation_left = randf() * SEPARATION_INTERVAL
	_walk_phase = randf() * TAU
	_death_side = -1.0 if randf() < 0.5 else 1.0
	_animate(0.0)


func _process(delta: float) -> void:
	_animate(delta)


func _physics_process(delta: float) -> void:
	if is_dead:
		_death_left -= delta
		if _death_left <= 0.0 and not is_queued_for_deletion():
			queue_free()
		return
	_tick_burn(delta)
	if is_dead:
		return
	var target: Node3D = _find_target()
	var direct: Vector3 = Vector3.ZERO
	var distance: float = INF
	var height_diff: float = 0.0
	if target != null:
		var to_target: Vector3 = target.global_position - global_position
		height_diff = to_target.y
		to_target.y = 0.0
		distance = to_target.length()
		if distance > 0.001:
			direct = to_target / distance
	# Freie Bahn zum Spieler wird nur in Schlagweite gebraucht (ein Strahl kostet, 24 Zombies leben).
	var reach_clear: bool = false
	if target != null and distance <= get_attack_range() + Balance.ZOMBIE_ATTACK_HIT_RANGE_BONUS:
		reach_clear = _has_clear_reach(target)
	# Stehen bleibt er nur, wenn er den Spieler auch erreichen kann. Steht eine Wand dazwischen,
	# folgt er weiter dem Pfad um sie herum, statt dahinter zu parken.
	var stops: bool = reach_clear and distance <= get_attack_range() * Balance.ZOMBIE_ATTACK_STOP_RANGE_FACTOR
	var walk: Vector3 = Vector3.ZERO
	if target != null and not stops:
		if _windup_left >= 0.0:
			walk = direct * move_speed * Balance.ZOMBIE_ATTACK_WINDUP_SPEED_FACTOR
		else:
			walk = _steer(delta, target.global_position, direct) * move_speed
	_move(delta, walk)
	_face(delta, walk, direct, distance)
	_tick_attack(delta, target, distance, height_diff, reach_clear)


## Der Schadensweg: zieht Leben ab und sendet Events.zombie_damaged (amount unverändert, auch
## beim tödlichen Treffer). Fällt das Leben auf 0: is_dead, Events.zombie_killed, kurze
## Todesanimation, dann queue_free. info siehe Abschnitt 7 ("source" ist Pflicht).
## Tote Zombies und Beträge <= 0 werden ignoriert.
func take_damage(amount: float, info: Dictionary) -> void:
	if is_dead or amount <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	if String(info.get("source", "")) != "burn":
		# Brand färbt ohnehin orange, nur echte Treffer blitzen weiß und lassen den Körper zucken.
		_flash_left = FLASH_TIME
		_punch = 1.0
	_material_dirty = true
	Events.zombie_damaged.emit(self, amount, info)
	if hp <= 0.0 and not is_dead:
		_die(info)


## Setzt den Zombie in Brand: dps ist Schaden je Sekunde in Lebenspunkten (schon fertig
## gerechnet, auch der Elite-Faktor, siehe get_burn_dps). Ein neuer Aufruf erneuert die Dauer,
## der höhere dps gewinnt. Der Brand-Schaden tickt alle Balance.BURN_TICK_INTERVAL s über
## take_damage mit source "burn". Über die ganze Dauer fällt genau dps * duration Schaden an.
func apply_burn(dps: float, duration: float) -> void:
	if is_dead or dps <= 0.0 or duration <= 0.0:
		return
	if _burn_left > 0.0:
		_burn_dps = maxf(_burn_dps, dps)
		_burn_left = maxf(_burn_left, duration)
	else:
		_burn_dps = dps
		_burn_left = duration
		_burn_accum = 0.0
	_material_dirty = true


## Rechnet den Brand-Schaden je Sekunde für diesen Zombie aus dem Anteil am Maximal-Leben
## (Upgrade "burn", Schlüssel dps_percent). Elite brennt nur mit Balance.BURN_ELITE_FACTOR.
## Das Ergebnis ist der Wert für apply_burn.
func get_burn_dps(dps_percent: float) -> float:
	var dps: float = maxf(dps_percent, 0.0) * max_hp
	if zombie_type == WavePlan.TYPE_ELITE:
		dps *= Balance.BURN_ELITE_FACTOR
	return dps


## Stößt den Zombie weg: impulse ist eine Geschwindigkeit in m/s, die schnell abklingt.
## Solange der Stoß stark ist, kann der Zombie nicht laufen.
func apply_knockback(impulse: Vector3) -> void:
	if is_dead:
		return
	var planar: Vector3 = Vector3(impulse.x, 0.0, impulse.z)
	_knockback += planar
	var lift: float = impulse.y
	if lift <= 0.0:
		lift = minf(planar.length() * Balance.ZOMBIE_KNOCKBACK_LIFT_SHARE, Balance.ZOMBIE_KNOCKBACK_LIFT_MAX)
	_lift = maxf(_lift, lift)
	_punch = 1.0


## Brennt der Zombie gerade?
func is_burning() -> bool:
	return _burn_left > 0.0


## Liegt der Trefferpunkt (Weltkoordinaten) im Kopfbereich? Höher als
## Balance.HEADSHOT_HEIGHT_RATIO der Körperhöhe über den Füßen.
func is_headshot(hit_position: Vector3) -> bool:
	return hit_position.y - global_position.y > body_height * Balance.HEADSHOT_HEIGHT_RATIO


## Weltposition der Körpermitte (Zielpunkt für Drohne, Blitz und Sichtlinien).
func get_center_position() -> Vector3:
	return global_position + Vector3(0.0, body_height * 0.5, 0.0)


## Weltposition der Kopfmitte (liegt sicher im Kopftreffer-Bereich).
func get_head_position() -> Vector3:
	return global_position + Vector3(0.0, body_height * (1.0 - HEAD_RADIUS_SHARE), 0.0)


## Entfernung (Füße zu Füßen, waagerecht), ab der dieser Zombie zum Schlag ausholt.
## Größere Zombies reichen um ihren zusätzlichen Körperradius weiter.
func get_attack_range() -> float:
	return Balance.ZOMBIE_ATTACK_RANGE + (body_radius - Balance.ZOMBIE_RADIUS)


## Holt der Zombie gerade zum Schlag aus?
func is_winding_up() -> bool:
	return _windup_left >= 0.0


## Setzt den Zombie an eine neue Stelle (Weltkoordinaten der Füße) und hält ihn an.
## Für die Rettung festhängender oder aus der Welt gefallener Zombies durch den WaveManager.
func teleport_to(world_position: Vector3) -> void:
	if is_dead:
		return
	global_position = world_position
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_lift = 0.0
	_windup_left = -1.0
	_repath_left = 0.0
	_path_valid = false
	_path = PackedVector3Array()
	_path_index = 0
	_spawn_grow = 0.0


## Entfernt den Zombie sofort und ohne Belohnung: kein zombie_killed, keine Punkte, keine Kiste.
## Für das Aufräumen bei einem neuen Lauf und als letzte Rettung gegen einen festhängenden Zombie.
func despawn() -> void:
	if is_dead:
		return
	is_dead = true
	_burn_left = 0.0
	remove_from_group("zombies")
	collision_layer = 0
	collision_mask = 0
	queue_free()


func _die(info: Dictionary) -> void:
	is_dead = true
	_death_left = Balance.ZOMBIE_DEATH_TIME
	_burn_left = 0.0
	_burn_accum = 0.0
	_windup_left = -1.0
	_knockback = Vector3.ZERO
	remove_from_group("zombies")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if is_instance_valid(_shape):
		_shape.set_deferred("disabled", true)
	if is_instance_valid(_bar):
		_bar.visible = false
	if is_instance_valid(_flames):
		_flames.visible = false
	_flash_left = FLASH_TIME
	_material_dirty = true
	Events.zombie_killed.emit(self, info)


## Brand: sammelt die Zeit und zieht je vollem Tick-Abstand Schaden ab. Läuft der Brand
## zwischen zwei Ticks aus, kommt der Rest anteilig, damit die Summe stimmt.
func _tick_burn(delta: float) -> void:
	if _burn_left <= 0.0:
		return
	var step: float = minf(delta, _burn_left)
	_burn_left -= step
	_burn_accum += step
	var dps: float = _burn_dps
	var ends: bool = _burn_left <= BURN_EPSILON
	var interval: float = Balance.BURN_TICK_INTERVAL
	while _burn_accum >= interval - BURN_EPSILON and not is_dead:
		_burn_accum -= interval
		take_damage(dps * interval, {"source": "burn"})
	if is_dead:
		return
	if ends:
		_burn_left = 0.0
		_burn_dps = 0.0
		var rest: float = _burn_accum
		_burn_accum = 0.0
		_material_dirty = true
		if rest > BURN_EPSILON:
			take_damage(dps * rest, {"source": "burn"})


## Der lebende Spieler oder null.
func _find_target() -> Node3D:
	var target: Node3D = Game.player
	if not is_instance_valid(target) or not target.is_inside_tree():
		return null
	if bool(target.get("is_dead")):
		return null
	return target


## Laufrichtung (waagerechter Einheitsvektor): entlang des Pfads, sonst geradeaus zum Spieler.
## Der NavigationAgent3D berechnet den Pfad, abgelaufen wird er hier Punkt für Punkt. Ein Punkt
## gilt erst als erreicht, wenn der Zombie wirklich dort steht (WAYPOINT_REACHED). So schneidet
## er an Türöffnungen und Kulissen keine Ecke und bleibt nicht an der Wand hängen.
func _steer(delta: float, target_position: Vector3, direct: Vector3) -> Vector3:
	_repath_left -= delta
	if _repath_left <= 0.0:
		_repath_left = Balance.ZOMBIE_REPATH_INTERVAL
		_path = PackedVector3Array()
		_path_index = 0
		if _nav_usable():
			_agent.target_position = target_position
			_agent.get_next_path_position()
			_path = _agent.get_current_navigation_path()
		_path_valid = _path.size() >= 2
	if _path_valid:
		while _path_index < _path.size():
			var waypoint: Vector3 = _path[_path_index]
			var to_waypoint: Vector3 = Vector3(waypoint.x - global_position.x, 0.0, waypoint.z - global_position.z)
			if to_waypoint.length_squared() > WAYPOINT_REACHED * WAYPOINT_REACHED:
				return to_waypoint.normalized()
			_path_index += 1
	# Pfad zu Ende (oder keiner da): das letzte Stück geradeaus.
	return direct


## Gibt es ein Navigationsnetz, das schon einmal abgeglichen wurde? Vorher wäre eine Abfrage
## ein Fehler, ohne Netz (headless-Test) bleibt der Pfad leer.
func _nav_usable() -> bool:
	if not is_instance_valid(_agent) or not _agent.is_inside_tree():
		return false
	var map: RID = _agent.get_navigation_map()
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0


func _move(delta: float, walk: Vector3) -> void:
	_update_separation(delta)
	var knock_speed: float = _knockback.length()
	var control: float = clampf(1.0 - knock_speed / Balance.ZOMBIE_STAGGER_KNOCKBACK_SPEED, 0.0, 1.0)
	var planar: Vector3 = (walk + _separation) * control
	_walk_speed_now = walk.length() * control
	velocity.x = planar.x + _knockback.x
	velocity.z = planar.z + _knockback.z
	if is_on_floor():
		velocity.y = _lift
	else:
		velocity.y -= Balance.GRAVITY * delta
	_lift = 0.0
	_knockback = _knockback.move_toward(Vector3.ZERO, Balance.ZOMBIE_KNOCKBACK_DAMPING * delta)
	move_and_slide()
	_hop_cooldown_left = maxf(0.0, _hop_cooldown_left - delta)
	if _hop_cooldown_left <= 0.0 and control > 0.5 and walk.length_squared() > 0.01:
		if is_on_floor() and is_on_wall():
			_try_hop(walk.normalized())


## Abstoßung: schiebt den Zombie von nahen Artgenossen weg, damit sie sich um den Spieler
## verteilen und nicht in einem Punkt stehen. Wird nur alle SEPARATION_INTERVAL s neu berechnet.
func _update_separation(delta: float) -> void:
	_separation_left -= delta
	if _separation_left > 0.0:
		return
	_separation_left = SEPARATION_INTERVAL
	var radius: float = Balance.ZOMBIE_SEPARATION_RADIUS * (body_radius / Balance.ZOMBIE_RADIUS)
	var push: Vector3 = Vector3.ZERO
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		if node == self:
			continue
		var other: Node3D = node as Node3D
		if other == null:
			continue
		var offset: Vector3 = global_position - other.global_position
		if absf(offset.y) > body_height:
			continue
		offset.y = 0.0
		var gap: float = offset.length()
		if gap >= radius:
			continue
		if gap < 0.01:
			# Genau übereinander: Beide rechnen aus ihren IDs dieselbe Achse aus und gehen in
			# entgegengesetzte Richtungen auseinander.
			var own_id: int = get_instance_id()
			var other_id: int = other.get_instance_id()
			var angle: float = float(mini(own_id, other_id) % 360) * TAU / 360.0
			var side: float = 1.0 if own_id < other_id else -1.0
			push += Vector3(cos(angle), 0.0, sin(angle)) * side
		else:
			push += offset / gap * (1.0 - gap / radius)
	_separation = push.limit_length(1.0) * Balance.ZOMBIE_SEPARATION_STRENGTH


## Steht der Zombie vor einer niedrigen Kante (Bühne, Stufe), springt er hinauf. Geprüft wird,
## ob der Weg in einer der Probehöhen frei ist. Wände und andere Zombies sind dafür zu hoch.
func _try_hop(direction: Vector3) -> void:
	var normal: Vector3 = get_wall_normal()
	if direction.dot(Vector3(normal.x, 0.0, normal.z)) > -0.25:
		return
	var probe: Vector3 = direction * maxf(body_radius * 0.5, 0.15)
	if not test_move(global_transform, probe):
		# Nur gestreift (Wandecke, Nachbar): Der Weg ist auf Bodenhöhe frei.
		return
	for height: float in Balance.ZOMBIE_HOP_PROBE_HEIGHTS:
		var from: Transform3D = global_transform
		if test_move(from, Vector3(0.0, height, 0.0)):
			return
		from.origin.y += height
		if not test_move(from, probe):
			_lift = sqrt(2.0 * Balance.GRAVITY * (height + HOP_MARGIN))
			_hop_cooldown_left = Balance.ZOMBIE_HOP_COOLDOWN
			return


## Dreht den Zombie weich: in der Nähe und beim Ausholen zum Spieler, sonst in Laufrichtung.
func _face(delta: float, walk: Vector3, direct: Vector3, distance: float) -> void:
	var look: Vector3 = direct
	if distance > FACE_PLAYER_DISTANCE and _windup_left < 0.0 and walk.length_squared() > 0.01:
		look = walk.normalized()
	if look.length_squared() < 0.0001:
		return
	var yaw: float = atan2(-look.x, -look.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))


## Angriff: in Reichweite ausholen (sichtbar: Arme gehen hoch), nach dem Ausholen trifft der
## Schlag, wenn der Spieler noch nah genug ist, danach Pause. reach_clear sagt, ob zwischen
## Zombie und Spieler keine Wand steht (siehe _has_clear_reach): Ohne freie Bahn holt er nicht
## aus, und ein schon begonnener Schlag geht ins Leere.
func _tick_attack(delta: float, target: Node3D, distance: float, height_diff: float, reach_clear: bool) -> void:
	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	if target == null:
		_windup_left = -1.0
		return
	var in_height: bool = absf(height_diff) <= body_height
	if _windup_left >= 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0:
			_windup_left = -1.0
			_attack_cooldown_left = Balance.ZOMBIE_ATTACK_COOLDOWN
			_strike_left = STRIKE_TIME
			var reach: float = get_attack_range() + Balance.ZOMBIE_ATTACK_HIT_RANGE_BONUS
			if distance <= reach and in_height and reach_clear and target.has_method("take_damage"):
				target.call("take_damage", attack_damage)
	elif _attack_cooldown_left <= 0.0 and distance <= get_attack_range() and in_height and reach_clear:
		_windup_left = Balance.ZOMBIE_ATTACK_WINDUP


## Kann der Zombie den Spieler erreichen, ohne durch die Welt zu schlagen? Zwei Strahlen nur
## gegen die Welt (Balance.MASK_LINE_OF_SIGHT): Körpermitte zu Körpermitte und Kopf zu Augen.
## Ist einer frei, gilt die Bahn als frei. So schützt eine Wand, eine hüfthohe Deckung aber
## nicht (darüber reicht er hinweg). Andere Zombies und die Sperren der Lage 6 zählen nicht.
func _has_clear_reach(target: Node3D) -> bool:
	if not is_inside_tree() or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	var world: World3D = get_world_3d()
	if world == null:
		return false
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return false
	var feet: Vector3 = target.global_position
	var center_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		get_center_position(), feet + Vector3(0.0, Balance.PLAYER_HEIGHT * 0.5, 0.0), Balance.MASK_LINE_OF_SIGHT)
	if space.intersect_ray(center_ray).is_empty():
		return true
	var head_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		get_head_position(), feet + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 0.0), Balance.MASK_LINE_OF_SIGHT)
	return space.intersect_ray(head_ray).is_empty()


# --- Aussehen -------------------------------------------------------------------------------

func _build_body() -> void:
	var def: Dictionary = Balance.ZOMBIE_TYPES[zombie_type]
	var is_elite: bool = zombie_type == WavePlan.TYPE_ELITE
	var is_sprinter: bool = zombie_type == WavePlan.TYPE_SPRINTER
	_base_color = def["color"]
	_base_emission = _base_color * 0.55 if bool(def["glow"]) else Color.BLACK
	_lean_rest = -0.16 if is_sprinter else -0.06
	_sway_amount = 0.06 if is_sprinter else 0.09

	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = body_radius
	capsule.height = body_height
	_shape = CollisionShape3D.new()
	_shape.name = "Shape"
	_shape.shape = capsule
	_shape.position = Vector3(0.0, body_height * 0.5, 0.0)
	add_child(_shape)

	_skin = StandardMaterial3D.new()
	_skin.albedo_color = _base_color
	_skin.roughness = 0.85
	# Leuchten bleibt immer an (schwarz = aus), damit Aufblitzen und Brand kein neues Material brauchen.
	_skin.emission_enabled = true
	_skin.emission = _base_emission

	# Rumpf: von den Füßen bis knapp über die Kopftreffer-Grenze, der Kopf sitzt darauf.
	var torso_height: float = body_height * BODY_SHARE
	var torso_radius: float = body_radius * (0.72 if is_sprinter else 0.86)
	var torso: CapsuleMesh = CapsuleMesh.new()
	torso.radius = torso_radius
	torso.height = torso_height
	torso.radial_segments = 12
	torso.rings = 4
	torso.material = _skin
	_body_rest = Vector3(0.0, torso_height * 0.5, 0.0)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"
	_mesh.mesh = torso
	_mesh.position = _body_rest
	add_child(_mesh)

	# Kopf: Kugel von HEADSHOT_HEIGHT_RATIO bis zum Scheitel.
	var head_radius: float = body_height * HEAD_RADIUS_SHARE
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = head_radius
	head_mesh.height = head_radius * 2.0
	head_mesh.radial_segments = 12
	head_mesh.rings = 6
	head_mesh.material = _skin
	_head_rest = Vector3(0.0, body_height - head_radius, 0.0) - _body_rest
	_head = MeshInstance3D.new()
	_head.name = "Head"
	_head.mesh = head_mesh
	_head.position = _head_rest
	_mesh.add_child(_head)
	_build_eyes(head_radius, is_elite, is_sprinter)
	if is_elite:
		_build_crown(head_radius)

	var shoulder_y: float = body_height * SHOULDER_SHARE - _body_rest.y
	var shoulder_x: float = torso_radius + body_height * ARM_THICKNESS_SHARE * 0.4
	_arm_left = _build_arm("ArmL", Vector3(-shoulder_x, shoulder_y, 0.0))
	_arm_right = _build_arm("ArmR", Vector3(shoulder_x, shoulder_y, 0.0))
	_build_flames(torso_radius)
	if is_elite:
		_build_glow()
		_build_health_bar()


func _build_eyes(head_radius: float, is_elite: bool, is_sprinter: bool) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if is_elite:
		material.albedo_color = Color(1.0, 0.12, 0.08)
	elif is_sprinter:
		material.albedo_color = Color(1.0, 1.0, 0.85)
	else:
		material.albedo_color = Color(1.0, 0.86, 0.25)
	var eye_mesh: SphereMesh = SphereMesh.new()
	eye_mesh.radius = head_radius * 0.22
	eye_mesh.height = head_radius * 0.44
	eye_mesh.radial_segments = 8
	eye_mesh.rings = 4
	eye_mesh.material = material
	for side: float in [-1.0, 1.0]:
		var eye: MeshInstance3D = MeshInstance3D.new()
		eye.name = "EyeL" if side < 0.0 else "EyeR"
		eye.mesh = eye_mesh
		# Vorn ist -Z.
		eye.position = Vector3(side * head_radius * 0.4, head_radius * 0.18, -head_radius * 0.86)
		_head.add_child(eye)


## Die Elite ist der Stargast der Show: Sie trägt eine Krone.
func _build_crown(head_radius: float) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.35)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.75, 0.1)
	material.metallic = 0.6
	material.roughness = 0.3
	var crown_mesh: CylinderMesh = CylinderMesh.new()
	crown_mesh.top_radius = head_radius * 0.85
	crown_mesh.bottom_radius = head_radius * 0.62
	crown_mesh.height = head_radius * 0.6
	crown_mesh.radial_segments = 6
	crown_mesh.rings = 1
	crown_mesh.material = material
	var crown: MeshInstance3D = MeshInstance3D.new()
	crown.name = "Crown"
	crown.mesh = crown_mesh
	crown.position = Vector3(0.0, head_radius * 0.95, 0.0)
	_head.add_child(crown)


## Arm: Drehpunkt an der Schulter, der Quader zeigt nach vorn (-Z). rotation.x > 0 hebt den Arm.
func _build_arm(arm_name: String, shoulder: Vector3) -> Node3D:
	var length: float = body_height * ARM_LENGTH_SHARE
	var thickness: float = body_height * ARM_THICKNESS_SHARE
	var arm_mesh: BoxMesh = BoxMesh.new()
	arm_mesh.size = Vector3(thickness, thickness, length)
	arm_mesh.material = _skin
	var pivot: Node3D = Node3D.new()
	pivot.name = arm_name
	pivot.position = shoulder
	var arm: MeshInstance3D = MeshInstance3D.new()
	arm.name = "Mesh"
	arm.mesh = arm_mesh
	arm.position = Vector3(0.0, 0.0, -length * 0.5)
	pivot.add_child(arm)
	_mesh.add_child(pivot)
	return pivot


func _build_flames(torso_radius: float) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = FLAME_COLOR
	var flame_mesh: SphereMesh = SphereMesh.new()
	flame_mesh.radius = body_height * 0.06
	flame_mesh.height = body_height * 0.24
	flame_mesh.radial_segments = 6
	flame_mesh.rings = 3
	flame_mesh.material = material
	_flames = Node3D.new()
	_flames.name = "Flames"
	_flames.visible = false
	for i: int in 4:
		var flame: MeshInstance3D = MeshInstance3D.new()
		flame.name = "Flame%d" % i
		flame.mesh = flame_mesh
		var angle: float = TAU * float(i) / 4.0 + 0.6
		flame.position = Vector3(cos(angle) * torso_radius, body_height * (0.05 * float(i) - 0.05), sin(angle) * torso_radius)
		_flames.add_child(flame)
	_mesh.add_child(_flames)


func _build_glow() -> void:
	_glow_energy = 1.6
	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.light_color = _base_color
	_glow.light_energy = _glow_energy
	_glow.omni_range = body_height * 2.4
	_glow.shadow_enabled = false
	_glow.position = Vector3(0.0, body_height * 0.6, 0.0)
	add_child(_glow)


## Lebensbalken über der Elite: zwei Flächen, die sich in _animate zur Kamera drehen.
func _build_health_bar() -> void:
	_bar = Node3D.new()
	_bar.name = "HealthBar"
	_bar.position = Vector3(0.0, body_height + 0.45, 0.0)
	var back: MeshInstance3D = MeshInstance3D.new()
	back.name = "Back"
	back.mesh = _make_bar_quad(Vector2(BAR_WIDTH + 0.06, BAR_HEIGHT + 0.06), Color(0.05, 0.04, 0.08))
	_bar.add_child(back)
	_bar_fill = MeshInstance3D.new()
	_bar_fill.name = "Fill"
	_bar_fill.mesh = _make_bar_quad(Vector2(BAR_WIDTH, BAR_HEIGHT), Color(1.0, 0.2, 0.25))
	_bar_fill.position = Vector3(0.0, 0.0, 0.01)
	_bar.add_child(_bar_fill)
	add_child(_bar)


func _make_bar_quad(size: Vector2, color: Color) -> QuadMesh:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	quad.material = material
	return quad


func _build_agent() -> void:
	_agent = NavigationAgent3D.new()
	_agent.name = "NavAgent"
	_agent.radius = body_radius
	_agent.height = body_height
	_agent.max_speed = maxf(move_speed, 0.1)
	_agent.avoidance_enabled = false
	add_child(_agent)


# --- Animation (nur Optik, ändert nie den Spielzustand) ---------------------------------------

func _animate(delta: float) -> void:
	if not is_instance_valid(_mesh):
		return
	_anim_time += delta
	_flash_left = maxf(0.0, _flash_left - delta)
	_punch = move_toward(_punch, 0.0, delta / PUNCH_TIME)
	_spawn_grow = move_toward(_spawn_grow, 1.0, delta / SPAWN_GROW_TIME)
	_strike_left = maxf(0.0, _strike_left - delta)
	if is_dead:
		_animate_death()
	else:
		_animate_alive(delta)
	_update_material()


func _animate_alive(delta: float) -> void:
	var size_factor: float = body_height / Balance.ZOMBIE_HEIGHT
	# Der Gang wackelt mit der gelaufenen Strecke, im Stand nur ganz leicht.
	_walk_phase += (_walk_speed_now * WOBBLE_RAD_PER_METER / size_factor + 0.9) * delta
	var stride: float = clampf(_walk_speed_now / 1.4, 0.2, 1.0)
	var swing: float = sin(_walk_phase)
	var sway: float = swing * _sway_amount * stride
	var bob: float = absf(swing) * 0.035 * body_height * stride
	var lean: float = _lean_rest
	# Die Arme bleiben waagerecht, auch wenn der Körper sich vorbeugt.
	var arm_rest: float = -_lean_rest + 0.05
	var arm_left: float = arm_rest + swing * 0.2 * stride
	var arm_right: float = arm_rest - swing * 0.2 * stride
	var forward: float = 0.0
	if _windup_left >= 0.0:
		# Ausholen: Arme hoch über den Kopf, Körper lehnt sich zurück. Das ist die Warnung.
		var raise: float = 1.0 - clampf(_windup_left / Balance.ZOMBIE_ATTACK_WINDUP, 0.0, 1.0)
		raise = 1.0 - (1.0 - raise) * (1.0 - raise)
		arm_left = lerpf(arm_left, ARM_RAISED, raise)
		arm_right = lerpf(arm_right, ARM_RAISED, raise)
		lean = lerpf(lean, WINDUP_LEAN, raise)
		forward = 0.04 * body_height * raise
	elif _strike_left > 0.0:
		# Schlag: Arme sausen herunter, der Körper stößt vor und richtet sich dann wieder auf.
		var progress: float = 1.0 - _strike_left / STRIKE_TIME
		if progress < 0.3:
			var slam: float = progress / 0.3
			arm_left = lerpf(ARM_RAISED, ARM_SLAM, slam)
			arm_right = arm_left
			lean = lerpf(WINDUP_LEAN, STRIKE_LEAN, slam)
			forward = lerpf(0.04, -STRIKE_LUNGE, slam) * body_height
		else:
			var recover: float = (progress - 0.3) / 0.7
			arm_left = lerpf(ARM_SLAM, arm_left, recover)
			arm_right = lerpf(ARM_SLAM, arm_right, recover)
			lean = lerpf(STRIKE_LEAN, lean, recover)
			forward = -STRIKE_LUNGE * body_height * (1.0 - recover)
	# Treffer: kurzes Zucken nach hinten und Stauchen.
	lean += 0.1 * _punch
	var grow: float = _ease_out_back(_spawn_grow)
	var squash: Vector3 = Vector3(
		(1.0 + 0.16 * _punch) * lerpf(0.7, 1.0, grow),
		(1.0 - 0.1 * _punch) * maxf(grow, 0.05),
		(1.0 + 0.16 * _punch) * lerpf(0.7, 1.0, grow))
	_pose_body(lean, sway, Vector3(0.0, bob, forward), squash)
	_head.position = _head_rest
	_head.rotation = Vector3(-lean * 0.5, 0.0, sin(_walk_phase * 0.5 + 1.3) * 0.2)
	_arm_left.rotation = Vector3(arm_left, 0.0, 0.0)
	_arm_right.rotation = Vector3(arm_right, 0.0, 0.0)
	_animate_flames()
	if is_instance_valid(_glow):
		_glow.light_energy = _glow_energy * (1.0 + 0.25 * sin(_anim_time * 5.0))
	if is_instance_valid(_bar):
		_update_health_bar()
	if delta > 0.0 and _burn_left > 0.0:
		_material_dirty = true


## Tod: Der Körper kippt nach hinten, der Kopf fliegt davon, die Arme klappen weg, am Ende
## schrumpft alles in den Boden. Dauert Balance.ZOMBIE_DEATH_TIME.
func _animate_death() -> void:
	var progress: float = 1.0 - clampf(_death_left / Balance.ZOMBIE_DEATH_TIME, 0.0, 1.0)
	var fall: float = progress * progress
	var shrink: float = 1.0
	if progress > 0.65:
		shrink = maxf(0.02, 1.0 - (progress - 0.65) / 0.35)
	var pop: float = 1.0 + 0.25 * sin(minf(progress * 4.0, 1.0) * PI)
	_pose_body(lerpf(_lean_rest, 1.35, fall), _death_side * 0.3 * fall,
			Vector3(0.0, -0.08 * body_height * fall, 0.1 * body_height * fall),
			Vector3(pop, 1.0, pop) * shrink)
	_head.position = _head_rest + Vector3(
			_death_side * 0.35 * body_height * progress,
			0.45 * body_height * sin(progress * PI * 0.85),
			0.2 * body_height * progress)
	_head.rotation = Vector3(progress * 7.0, 0.0, _death_side * progress * 4.0)
	_arm_left.rotation = Vector3(lerpf(0.0, 1.2, progress), 0.0, 1.5 * progress)
	_arm_right.rotation = Vector3(lerpf(0.0, 1.2, progress), 0.0, -1.5 * progress)
	if is_instance_valid(_glow):
		_glow.light_energy = _glow_energy * (1.0 - progress) * (1.0 + 2.0 * sin(progress * PI))
	_material_dirty = true


## Setzt den Rumpf (und damit alle Körperteile): Drehung und Stauchung wirken um die Füße.
func _pose_body(lean: float, sway: float, offset: Vector3, squash: Vector3) -> void:
	var turned: Basis = Basis.from_euler(Vector3(lean, 0.0, sway))
	var basis_scaled: Basis = Basis(turned.x * squash.x, turned.y * squash.y, turned.z * squash.z)
	_mesh.transform = Transform3D(basis_scaled, basis_scaled * _body_rest + offset)


func _animate_flames() -> void:
	var burning: bool = _burn_left > 0.0
	if _flames.visible != burning:
		_flames.visible = burning
	if not burning:
		return
	var index: int = 0
	for child: Node in _flames.get_children():
		var flame: Node3D = child as Node3D
		if flame != null:
			var flicker: float = 0.75 + 0.45 * sin(_anim_time * 19.0 + float(index) * 1.9)
			flame.scale = Vector3(1.0, flicker * 1.6, 1.0)
		index += 1
	_flames.rotation.y = _anim_time * 2.5


func _update_health_bar() -> void:
	var ratio: float = clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	_bar_fill.scale = Vector3(maxf(ratio, 0.001), 1.0, 1.0)
	_bar_fill.position = Vector3(-(1.0 - ratio) * BAR_WIDTH * 0.5, 0.0, 0.01)
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		# Gleiche Ausrichtung wie die Kamera: Die Flächen stehen immer parallel zum Bild.
		_bar.global_transform = Transform3D(camera.global_transform.basis.orthonormalized(), _bar.global_position)


## Farbe des Körpers aus Grundfarbe, Brand (orange, flackernd), Treffer (weiß) und Tod (dunkel).
func _update_material() -> void:
	var burning: bool = _burn_left > 0.0 and not is_dead
	var active: bool = burning or _flash_left > 0.0 or is_dead
	if not active and not _material_dirty:
		return
	_material_dirty = active
	var albedo: Color = _base_color
	var emission: Color = _base_emission
	if burning:
		var flicker: float = 0.5 + 0.5 * sin(_anim_time * 23.0 + _walk_phase)
		albedo = albedo.lerp(BURN_COLOR, 0.6)
		emission = emission.lerp(BURN_COLOR, 0.45 + 0.3 * flicker)
	if is_dead:
		var progress: float = 1.0 - clampf(_death_left / Balance.ZOMBIE_DEATH_TIME, 0.0, 1.0)
		albedo = albedo.lerp(DEATH_COLOR, progress * 0.8)
		emission = emission.lerp(Color.BLACK, progress)
	if _flash_left > 0.0:
		# Nicht bis ganz weiß: Unter Dauerfeuer bliebe sonst nur ein weißer Fleck ohne Form.
		var flash: float = clampf(_flash_left / FLASH_TIME, 0.0, 1.0) * FLASH_STRENGTH
		albedo = albedo.lerp(Color.WHITE, flash)
		emission = emission.lerp(Color.WHITE, flash * 0.3)
	_skin.albedo_color = albedo
	_skin.emission = emission


## Weiches Überschwingen (0 -> 1), für das Aufrichten beim Erscheinen.
func _ease_out_back(value: float) -> float:
	var shifted: float = clampf(value, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * shifted * shifted * shifted + 1.70158 * shifted * shifted
