extends Node3D
## Modul: Upgrades (scripts/game/upgrades).
## Kameradrohne (Upgrade "drone"): eine kleine fliegende TV-Kamera. Sie folgt dem Spieler mit
## weichem Nachziehen in Balance.DRONE_HOVER_HEIGHT und schießt im Takt der Stufe auf den
## nächsten Zombie mit freier Sichtlinie in Balance.DRONE_RANGE.
## Schaden über zombie.take_damage(schaden, {"source": "drone"}). Takt und Schaden kommen aus
## den Stufenwerten des Upgrades "drone" für die eigene Stufe (level), der Schaden mal
## Game.effect_factor(). UpgradeEffects erzeugt die Drohnen, hält ihre Stufen aktuell und hängt
## sie in den Behälter aus Fx.root_of(...).
##
## Mehrere Drohnen (Abschnitt 18: jede Kameradrohne im Rucksack ist eine eigene Drohne):
## Jede hat einen Platz (slot, 0 = erste Drohne). Der Platz bestimmt, wo sie um den Spieler
## schwebt, wie versetzt sie wippt und wann ihr erster Schuss fällt. Beim Schuss beansprucht sie
## ihr Ziel bis zum eigenen nächsten Schuss. Eine andere Drohne nimmt ein beanspruchtes Ziel nur,
## wenn sie kein anderes sieht: So verteilen sich die Drohnen auf verschiedene Zombies.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

## Gruppe aller Drohnen (für die Absprache der Ziele).
const GROUP: String = "drones"

# --- Reine Optik- und Flug-Zahlen (keine Spielregeln) ---
## Platz der ersten Drohne relativ zum Spieler: schräg rechts vorn. Bei geradem Blick steht sie
## damit rechts über der Bildmitte: weit genug vorn, dass sie klein bleibt, und links von der
## Punkte-Anzeige in der Ecke, die sie sonst verdecken würde.
const OFFSET_FORWARD: float = 2.6
const OFFSET_RIGHT: float = 2.0
## Weitere Drohnen: abwechselnd rechts und links, je Paar um diesen Winkel (Bogenmaß) weiter um
## den Spieler herum. Nach SLOTS_PER_SIDE Paaren beginnt ein weiterer, größerer Ring.
const SLOT_ANGLE_STEP: float = 0.66
const SLOTS_PER_SIDE: int = 4
const RING_RADIUS_STEP: float = 1.1
const SLOT_HEIGHT_STEP: float = 0.3
const RING_HEIGHT_STEP: float = 0.4
## Versatz des ersten Schusses und des Wippens je Platz (Anteil des Takts bzw. Sekunden).
const SLOT_FIRE_PHASE: float = 0.382
const SLOT_BOB_PHASE: float = 1.3
## So lange über den eigenen Takt hinaus gilt ein beanspruchtes Ziel noch (Sekunden).
const CLAIM_MARGIN: float = 0.15
const FOLLOW_SPEED: float = 4.0
const TURN_SPEED: float = 10.0
const BOB_AMPLITUDE: float = 0.1
const BOB_SPEED: float = 2.2
const SNAP_DISTANCE: float = 14.0
const WALL_MARGIN: float = 0.35
const ROTOR_SPEED: float = 38.0
const RECOIL_DISTANCE: float = 0.12
const TRACER_COLOR: Color = Color(1.0, 0.25, 0.3, 0.95)
const NUMBER_COLOR: Color = Color(1.0, 0.45, 0.5)
const BODY_COLOR: Color = Color(0.82, 0.85, 0.92)
const ACCENT_COLOR: Color = Color(1.0, 0.82, 0.1)

## Stufe des Upgrades (1 bis 5).
var level: int = 1
## Zeigt die Drohne eigene Trefferzahlen? UpgradeEffects schaltet das mit seinen Zahlen gleich.
var show_damage_numbers: bool = true
## Platz dieser Drohne unter allen Drohnen (0 = erste). Setzen mit set_slot.
var slot: int = 0

var _cooldown_left: float = 0.0
var _scan_left: float = 0.0
var _time: float = 0.0
## Beanspruchtes Ziel als Instanz-ID (0 = keines) und wie lange der Anspruch noch gilt. Eine ID
## statt eines Knotens: Der Zombie kann jederzeit verschwinden.
var _claim_id: int = 0
var _claim_left: float = 0.0
var _desired: Vector3 = Vector3.ZERO
var _has_desired: bool = false
var _aim_point: Vector3 = Vector3.ZERO
var _has_aim: bool = false
var _aim_hold_left: float = 0.0
var _pivot: Node3D = null
var _muzzle: Node3D = null
var _rec_light: MeshInstance3D = null
var _rotors: Array[Node3D] = []


func _ready() -> void:
	add_to_group(GROUP)
	_build_visual()
	# Drohnen auf verschiedenen Plätzen wippen und schießen versetzt, nicht im Gleichschritt.
	_time = float(slot) * SLOT_BOB_PHASE
	_cooldown_left = get_fire_interval() * fmod(float(slot) * SLOT_FIRE_PHASE, 1.0)
	var player: Node3D = _player()
	if player != null:
		_desired = _wanted_position(player)
		_has_desired = true
		global_position = _desired
	# Die Drohne ploppt beim Erscheinen auf.
	scale = Vector3.ONE * 0.05
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Setzt die Stufe (1 bis 5). Takt und Schaden richten sich danach.
func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, Balance.UPGRADE_MAX_LEVEL)
	# Ein schnellerer Takt gilt sofort, nicht erst nach dem alten Rest.
	_cooldown_left = minf(_cooldown_left, get_fire_interval())


## Setzt den Platz unter allen Drohnen (0 = erste). Die Drohne gleitet von selbst dorthin.
func set_slot(index: int) -> void:
	slot = maxi(0, index)


## Versatz eines Platzes zum Spieler: x = nach rechts, y = zusätzlich zur Flughöhe, z = nach vorn
## (jeweils in Metern, bezogen auf die Blickrichtung des Spielers). Platz 0 ist schräg rechts
## vorn, Platz 1 spiegelbildlich links, die nächsten Paare liegen weiter um den Spieler herum.
static func slot_offset(index: int) -> Vector3:
	var safe_index: int = maxi(0, index)
	var side: float = 1.0 if safe_index % 2 == 0 else -1.0
	@warning_ignore("integer_division")
	var pair: int = safe_index / 2
	@warning_ignore("integer_division")
	var ring: int = pair / SLOTS_PER_SIDE
	var in_ring: int = pair % SLOTS_PER_SIDE
	var base: Vector2 = Vector2(OFFSET_RIGHT, OFFSET_FORWARD)
	# Winkel zur Blickrichtung: 0 = genau vorn, positiv = nach rechts. Jeder weitere Ring ist um
	# einen halben Schritt verdreht, damit seine Drohnen in den Lücken des inneren stehen.
	var angle: float = side * (atan2(base.x, base.y) + (float(in_ring) + 0.5 * float(ring)) * SLOT_ANGLE_STEP)
	var radius: float = base.length() + float(ring) * RING_RADIUS_STEP
	var height: float = float(in_ring % 3) * SLOT_HEIGHT_STEP + float(ring) * RING_HEIGHT_STEP
	return Vector3(sin(angle) * radius, height, cos(angle) * radius)


## Sekunden zwischen zwei Schüssen auf dieser Stufe.
func get_fire_interval() -> float:
	return UpgradeDefs.value("drone", "interval", level)


## Schaden eines Schusses: Stufenwert mal Effekt-Faktor der aktuellen Welle.
func get_shot_damage() -> float:
	return UpgradeDefs.value("drone", "damage", level) * Game.effect_factor()


## Weltposition der Linse: Von hier gehen Schuss und Sichtlinie aus.
func get_muzzle_position() -> Vector3:
	if is_instance_valid(_muzzle) and _muzzle.is_inside_tree():
		return _muzzle.global_position
	return global_position


## Instanz-ID des Zombies, den diese Drohne gerade beansprucht, 0 wenn keiner (mehr).
func get_claim_id() -> int:
	return _claim_id if _claim_left > 0.0 else 0


## Der Zombie, den diese Drohne gerade beansprucht (ihr letztes Ziel bis zum nächsten eigenen
## Schuss), null wenn keiner oder wenn er tot oder weg ist.
func get_claimed_target() -> Node3D:
	var id: int = get_claim_id()
	if id == 0:
		return null
	var target: Node3D = instance_from_id(id) as Node3D
	return target if _is_alive(target) else null


## Gibt das beanspruchte Ziel frei.
func release_claim() -> void:
	_claim_id = 0
	_claim_left = 0.0


## Der nächste lebende Zombie in Reichweite mit freier Sichtlinie, sonst null. Ein Zombie, den
## eine andere Drohne gerade beansprucht, kommt nur dran, wenn es kein anderes sichtbares Ziel gibt.
func find_target() -> Node3D:
	if not is_inside_tree():
		return null
	var claimed: Dictionary = _claims_of_others()
	var origin: Vector3 = global_position
	var candidates: Array[Node3D] = []
	var distances: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		var zombie: Node3D = node as Node3D
		if not _is_alive(zombie):
			continue
		var distance: float = origin.distance_to(_center_of(zombie))
		if distance <= Balance.DRONE_RANGE:
			candidates.append(zombie)
			distances[zombie.get_instance_id()] = distance
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return float(distances[a.get_instance_id()]) < float(distances[b.get_instance_id()]))
	var shared: Node3D = null
	for zombie: Node3D in candidates:
		if not _has_line_of_sight(origin, _center_of(zombie)):
			continue
		if not claimed.has(zombie.get_instance_id()):
			return zombie
		if shared == null:
			shared = zombie
	return shared


## Ziele, die andere Drohnen gerade beanspruchen: Instanz-ID -> true.
func _claims_of_others() -> Dictionary:
	var claimed: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node == self or node.is_queued_for_deletion() or not node.has_method("get_claim_id"):
			continue
		var id: int = int(node.call("get_claim_id"))
		if id != 0:
			claimed[id] = true
	return claimed


## Schießt sofort auf das nächste sichtbare Ziel, ohne den Takt zu prüfen (auch für Tests).
## Gibt true zurück, wenn ein Schuss fiel.
func try_fire() -> bool:
	var target: Node3D = find_target()
	if target == null or not target.has_method("take_damage"):
		return false
	var hit_position: Vector3 = _center_of(target)
	var damage: float = get_shot_damage()
	if damage <= 0.0:
		return false
	_aim_point = hit_position
	_has_aim = true
	_aim_hold_left = 0.4
	# Das Ziel gehört bis zum nächsten eigenen Schuss dieser Drohne.
	_claim_id = target.get_instance_id()
	_claim_left = get_fire_interval() + CLAIM_MARGIN
	var from: Vector3 = get_muzzle_position()
	var fx_root: Node = Fx.root_of(self)
	Fx.tracer(fx_root, from, hit_position, TRACER_COLOR)
	if is_instance_valid(_muzzle):
		Fx.muzzle_flash(_muzzle)
	if show_damage_numbers:
		Fx.damage_number(fx_root, hit_position + Vector3(0.0, 0.5, 0.0), damage, NUMBER_COLOR)
	_play_recoil()
	target.call("take_damage", damage, {"source": "drone", "hit_position": hit_position})
	return true


func _process(delta: float) -> void:
	_time += delta
	# Weich zum Wunschplatz nachziehen, leicht auf und ab wippen.
	if _has_desired:
		var goal: Vector3 = _desired + Vector3(0.0, sin(_time * BOB_SPEED) * BOB_AMPLITUDE, 0.0)
		if global_position.distance_to(goal) > SNAP_DISTANCE:
			global_position = goal
		else:
			global_position = global_position.lerp(goal, 1.0 - exp(-FOLLOW_SPEED * delta))
	_update_aim(delta)
	for rotor: Node3D in _rotors:
		if is_instance_valid(rotor):
			rotor.rotation.y += ROTOR_SPEED * delta
	# Rotes Aufnahme-Licht blinkt im Sekundentakt.
	if is_instance_valid(_rec_light):
		_rec_light.visible = fmod(_time, 1.0) < 0.6


func _physics_process(delta: float) -> void:
	var player: Node3D = _player()
	if player != null:
		_desired = _clear_of_walls(player, _wanted_position(player))
		_has_desired = true
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_scan_left = maxf(0.0, _scan_left - delta)
	_aim_hold_left = maxf(0.0, _aim_hold_left - delta)
	_claim_left = maxf(0.0, _claim_left - delta)
	if _aim_hold_left <= 0.0:
		_has_aim = false
	if _cooldown_left > 0.0 or _scan_left > 0.0:
		return
	if Game.state != Game.State.PLAYING or player == null or bool(player.get("is_dead")):
		return
	if try_fire():
		_cooldown_left = get_fire_interval()
	else:
		_scan_left = Balance.DRONE_SCAN_INTERVAL


## Der Spieler, wenn er gültig ist und im Baum hängt, sonst null.
func _player() -> Node3D:
	var player: Node3D = Game.player
	if is_instance_valid(player) and player.is_inside_tree():
		return player
	return null


## Blickrichtung des Spielers in der Waagerechten (Einheitsvektor).
func _player_forward(player: Node3D) -> Vector3:
	var forward: Vector3 = -player.global_basis.z
	if player.has_method("get_aim_direction"):
		forward = player.call("get_aim_direction")
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -player.global_basis.z
		forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


## Wunschplatz: der Platz dieser Drohne (slot_offset) um den Spieler, in Flughöhe über seinen
## Füßen. Die erste Drohne steht schräg rechts vor ihm.
func _wanted_position(player: Node3D) -> Vector3:
	var forward: Vector3 = _player_forward(player)
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var offset: Vector3 = slot_offset(slot)
	return player.global_position + forward * offset.z + right * offset.x \
		+ Vector3(0.0, Balance.DRONE_HOVER_HEIGHT + offset.y, 0.0)


## Hält die Drohne vor Wänden und unter der Decke: Trifft der Weg vom Kopf des Spielers zum
## Wunschplatz auf die Welt, bleibt sie kurz davor.
func _clear_of_walls(player: Node3D, wanted: Vector3) -> Vector3:
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return wanted
	var from: Vector3 = player.global_position + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, 0.0)
	var offset: Vector3 = wanted - from
	var length: float = offset.length()
	if length < 0.01:
		return wanted
	var direction: Vector3 = offset / length
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, wanted + direction * WALL_MARGIN, Balance.MASK_LINE_OF_SIGHT)
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return wanted
	var free_length: float = maxf(0.0, from.distance_to(hit["position"] as Vector3) - WALL_MARGIN)
	return from + direction * free_length


func _is_alive(zombie: Node3D) -> bool:
	return is_instance_valid(zombie) and zombie.is_inside_tree() and not bool(zombie.get("is_dead"))


## Körpermitte eines Zombies (Zielpunkt).
func _center_of(zombie: Node3D) -> Vector3:
	if zombie.has_method("get_center_position"):
		return zombie.call("get_center_position")
	return zombie.global_position + Vector3(0.0, Balance.ZOMBIE_HEIGHT * 0.5, 0.0)


## Freie Sicht zwischen zwei Punkten? Nur die Welt (Lage 1) verdeckt.
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, to, Balance.MASK_LINE_OF_SIGHT)
	return world.direct_space_state.intersect_ray(query).is_empty()


## Dreht die Kamera weich zum letzten Ziel, sonst in die Blickrichtung des Spielers.
func _update_aim(delta: float) -> void:
	if not is_instance_valid(_pivot):
		return
	var look_direction: Vector3 = Vector3.ZERO
	if _has_aim:
		look_direction = _aim_point - global_position
	else:
		var player: Node3D = _player()
		if player != null:
			look_direction = _player_forward(player) + Vector3(0.0, -0.25, 0.0)
	if look_direction.length_squared() < 0.0001:
		return
	look_direction = look_direction.normalized()
	var up: Vector3 = Vector3.UP if absf(look_direction.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var target_basis: Basis = Basis.looking_at(look_direction, up)
	var weight: float = 1.0 - exp(-TURN_SPEED * delta)
	# Die Drohne selbst dreht sich nie, also ist die Ausrichtung des Schwenkteils im Raum der
	# Drohne dieselbe wie in der Welt.
	_pivot.basis = _pivot.basis.orthonormalized().slerp(target_basis, weight)


## Kurzer Rückstoß der Kamera beim Schuss.
func _play_recoil() -> void:
	if not is_instance_valid(_pivot) or not _pivot.is_inside_tree():
		return
	_pivot.position = Vector3.ZERO
	var kick: Vector3 = _pivot.basis.z.normalized() * RECOIL_DISTANCE
	var tween: Tween = _pivot.create_tween()
	tween.tween_property(_pivot, "position", kick, 0.03)
	tween.tween_property(_pivot, "position", Vector3.ZERO, 0.12)


## Baut die fliegende TV-Kamera aus einfachen Formen. Vorn ist -Z.
func _build_visual() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var shell: StandardMaterial3D = StandardMaterial3D.new()
	shell.albedo_color = BODY_COLOR
	shell.metallic = 0.5
	shell.roughness = 0.45
	var accent: StandardMaterial3D = StandardMaterial3D.new()
	accent.albedo_color = ACCENT_COLOR
	accent.emission_enabled = true
	accent.emission = ACCENT_COLOR
	accent.emission_energy_multiplier = 0.6
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.04)
	dark.metallic = 0.8
	dark.roughness = 0.2
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(0.45, 0.85, 1.0)
	var red: StandardMaterial3D = StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1.0, 0.1, 0.1)

	# Gehäuse mit gelbem Streifen, Sucher und Griff.
	_add_box("Body", Vector3(0.3, 0.24, 0.42), Vector3.ZERO, shell)
	_add_box("Stripe", Vector3(0.31, 0.05, 0.43), Vector3(0.0, -0.05, 0.0), accent)
	_add_box("Viewfinder", Vector3(0.1, 0.1, 0.2), Vector3(-0.1, 0.17, 0.08), shell)
	_add_box("Handle", Vector3(0.05, 0.05, 0.3), Vector3(0.08, 0.16, 0.0), dark)
	# Objektiv: Zylinder entlang -Z mit heller Linse.
	_add_cylinder("Lens", 0.1, 0.18, Vector3(0.0, 0.0, -0.29), dark, true)
	_add_cylinder("LensHood", 0.12, 0.05, Vector3(0.0, 0.0, -0.39), shell, true)
	_add_cylinder("Glass", 0.085, 0.01, Vector3(0.0, 0.0, -0.42), glass, true)
	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.0, 0.0, -0.46)
	_pivot.add_child(_muzzle)
	# Rotes Aufnahme-Licht.
	var rec_mesh: SphereMesh = SphereMesh.new()
	rec_mesh.radius = 0.035
	rec_mesh.height = 0.07
	_rec_light = MeshInstance3D.new()
	_rec_light.name = "RecLight"
	_rec_light.mesh = rec_mesh
	_rec_light.material_override = red
	_rec_light.position = Vector3(0.1, 0.14, -0.18)
	_pivot.add_child(_rec_light)
	# Schriftzug auf beiden Seiten.
	for side: float in [-1.0, 1.0]:
		var sign_label: Label3D = Label3D.new()
		sign_label.name = "LiveSign"
		sign_label.text = "LIVE"
		sign_label.font_size = 48
		sign_label.pixel_size = 0.002
		sign_label.outline_size = 8
		sign_label.modulate = Color(1.0, 0.2, 0.2)
		sign_label.outline_modulate = Color.WHITE
		sign_label.shaded = false
		sign_label.position = Vector3(side * 0.153, 0.04, 0.02)
		sign_label.rotation.y = side * PI * 0.5
		_pivot.add_child(sign_label, true)
	# Zwei Rotoren an Auslegern. Sie hängen am Rumpf, nicht an der schwenkenden Kamera.
	for side: float in [-1.0, 1.0]:
		_add_box("Arm", Vector3(0.26, 0.03, 0.05), Vector3(side * 0.26, 0.1, 0.0), dark, self)
		_add_cylinder("Mast", 0.02, 0.1, Vector3(side * 0.38, 0.16, 0.0), dark, false, self)
		var rotor: Node3D = Node3D.new()
		rotor.name = "Rotor"
		rotor.position = Vector3(side * 0.38, 0.22, 0.0)
		add_child(rotor, true)
		var blade_mesh: BoxMesh = BoxMesh.new()
		blade_mesh.size = Vector3(0.36, 0.01, 0.05)
		for turn: int in 2:
			var blade: MeshInstance3D = MeshInstance3D.new()
			blade.name = "Blade"
			blade.mesh = blade_mesh
			blade.material_override = accent
			blade.rotation.y = PI * 0.5 * float(turn)
			blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rotor.add_child(blade, true)
		_rotors.append(rotor)


## Quader, ohne parent am Schwenkteil.
func _add_box(node_name: String, size: Vector3, at: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = box
	node.material_override = material
	node.position = at
	(parent if parent != null else _pivot).add_child(node, true)
	return node


## Zylinder, ohne parent am Schwenkteil. along_z = true legt ihn entlang der Blickachse (Objektiv).
func _add_cylinder(node_name: String, radius: float, length: float, at: Vector3, material: Material, along_z: bool, parent: Node3D = null) -> MeshInstance3D:
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = length
	cylinder.radial_segments = 16
	cylinder.rings = 1
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = cylinder
	node.material_override = material
	node.position = at
	if along_z:
		node.rotation.x = PI * 0.5
	(parent if parent != null else _pivot).add_child(node, true)
	return node
