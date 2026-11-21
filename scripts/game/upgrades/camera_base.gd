extends Node3D
## Modul: Upgrades (scripts/game/upgrades).
## Gemeinsame Basis der vier Kameras aus Abschnitt 22.1: Tele-Kamera (cam_tele.gd), Blitzlicht-
## Kamera (cam_flash.gd), Zeitlupen-Kamera (cam_slow.gd) und Regie-Kamera (cam_director.gd). Die
## Kameradrohne hat ihr eigenes Skript (drone.gd).
##
## Eine Kamera schwebt wie die Drohne um den Spieler: Sie hat einen Platz (slot), den sie sich mit
## den Drohnen teilt (Drone.slot_offset), folgt ihm mit weichem Nachziehen und löst in ihrem Takt
## aus (try_fire der abgeleiteten Skripte). Solange kein Ziel da ist, sucht sie nur alle
## Balance.DRONE_SCAN_INTERVAL Sekunden neu.
##
## Feste Werte: Schaden, Takt, Reichweite und alles Weitere stehen fertig gerechnet im Eintrag
## der Kamera aus Game.cameras (stats, gesetzt mit set_stats). Kein Game.effect_factor(), kein
## Abschlag für mehrere Kameras. Ohne Eintrag gelten die Grundwerte der Rarität (level) aus
## CameraDefs.stats. UpgradeEffects erzeugt die Kameras, hält Einträge und Plätze aktuell und
## hängt sie in den Behälter aus Fx.root_of(...).
##
## Sichtlinie wie bei der Drohne: Nur die Welt (Lage 1) verdeckt, gemessen vom Knoten der Kamera
## zur Körpermitte des Zombies. Die Reichweite zählt ebenfalls von dort.
## Bei jedem Auslösen (Schuss, Blitz, Markierung) kommt Events.camera_fired(camera_id, position).
##
## Abgeleitete Skripte setzen camera_id in _init, bauen ihr Aussehen in _build_visual und
## schreiben try_fire (dort am Ende _after_shot rufen).

const Balance := preload("res://scripts/core/balance.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")
const UpgradeFx := preload("res://scripts/game/upgrades/upgrade_fx.gd")
const Drone := preload("res://scripts/game/upgrades/drone.gd")

## Gruppe aller Kameras dieser Basis (die Drohnen stehen in ihrer eigenen Gruppe "drones").
const GROUP: String = "cameras"

# --- Reine Optik- und Flug-Zahlen (keine Spielregeln) ---
const FOLLOW_SPEED: float = 4.0
const TURN_SPEED: float = 10.0
const BOB_AMPLITUDE: float = 0.1
const BOB_SPEED: float = 2.2
const SNAP_DISTANCE: float = 14.0
const WALL_MARGIN: float = 0.35
const RECOIL_DISTANCE: float = 0.1
## Versatz des ersten Schusses, des Wippens und der Zielsuche je Platz (Anteil des Takts bzw.
## Sekunden): Kameras auf verschiedenen Plätzen arbeiten nicht im Gleichschritt.
const SLOT_FIRE_PHASE: float = 0.382
const SLOT_BOB_PHASE: float = 1.3
const SLOT_SCAN_PHASE: float = 0.037
## So lange blickt die Kamera nach dem Auslösen noch auf ihr Ziel (Sekunden).
const AIM_HOLD: float = 0.5
## Reste einer Wartezeit unter diesem Wert gelten als abgelaufen (Rundung vieler kleiner Schritte).
const TIME_EPSILON: float = 0.0001

# Netze und Materialien gibt es einmal für alle Kameras (Schlüssel -> Ressource).
static var _shared_meshes: Dictionary = {}
static var _shared_materials: Dictionary = {}

## Kameratyp aus CameraDefs. Setzt das abgeleitete Skript in _init.
var camera_id: String = ""
## Rarität der Kamera (1 bis 5).
var level: int = 1
## Eintrag dieser Kamera aus Game.cameras (fertige Werte). Leer: Es gelten die Grundwerte der
## Rarität. Setzen mit set_stats.
var stats: Dictionary = {}
## Zeigt die Kamera eigene Trefferzahlen? UpgradeEffects schaltet das mit seinen Zahlen gleich.
var show_damage_numbers: bool = true
## Platz dieser Kamera unter allen Kameras und Drohnen (0 = erster). Setzen mit set_slot.
var slot: int = 0
## Wie oft diese Kamera schon ausgelöst hat (Schüsse, Blitze, Markierungen).
var shots_fired: int = 0
## Farbe der Trefferzahlen (setzt das abgeleitete Skript).
var number_color: Color = Color(1.0, 1.0, 1.0)

var _cooldown_left: float = 0.0
var _scan_left: float = 0.0
var _time: float = 0.0
var _desired: Vector3 = Vector3.ZERO
var _has_desired: bool = false
var _aim_point: Vector3 = Vector3.ZERO
var _has_aim: bool = false
var _aim_hold_left: float = 0.0
## Grundwerte der Rarität, solange kein Eintrag gesetzt ist (CameraDefs.stats, einmal gerechnet).
var _fallback: Dictionary = {}
var _pivot: Node3D = null
var _muzzle: Node3D = null
## Drehende Teile (Rotoren, Filmspulen): { "node": Node3D, "speed": float (Radiant je Sekunde) }.
## Jedes dreht sich um seine eigene Y-Achse.
var _spinners: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(GROUP)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	_pivot.add_child(_muzzle)
	_build_visual()
	_time = float(slot) * SLOT_BOB_PHASE
	_cooldown_left = get_fire_interval() * fmod(float(slot) * SLOT_FIRE_PHASE, 1.0)
	_scan_left = fmod(float(slot) * SLOT_SCAN_PHASE, Balance.DRONE_SCAN_INTERVAL)
	var player: Node3D = _player()
	if player != null:
		_desired = _wanted_position(player)
		_has_desired = true
		global_position = _desired
	# Die Kamera ploppt beim Erscheinen auf.
	scale = Vector3.ONE * 0.05
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Setzt die Rarität (1 bis 5). Die Werte richten sich danach, bis set_stats die fertigen liefert.
func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, Balance.UPGRADE_MAX_LEVEL)
	if int(stats.get("level", level)) != level:
		stats = {}
	_fallback = {}
	# Ein schnellerer Takt gilt sofort, nicht erst nach dem alten Rest.
	_cooldown_left = minf(_cooldown_left, get_fire_interval())


## Setzt die fertigen Werte dieser Kamera: ein Eintrag aus Game.cameras. Die Rarität wird daraus
## übernommen.
func set_stats(entry: Dictionary) -> void:
	stats = entry
	level = clampi(int(entry.get("level", level)), 1, Balance.UPGRADE_MAX_LEVEL)
	_fallback = {}
	_cooldown_left = minf(_cooldown_left, get_fire_interval())


## Setzt den Platz unter allen Kameras und Drohnen (0 = erster). Die Kamera gleitet von selbst dorthin.
func set_slot(index: int) -> void:
	slot = maxi(0, index)


## Ein fertiger Wert dieser Kamera (Schlüssel wie in Game.cameras: "damage", "interval", "range",
## "pierce", "slow", "slow_duration", "mark", "mark_duration", "second", "cone_deg").
func get_value(key: String) -> float:
	if stats.has(key):
		return float(stats[key])
	if _fallback.is_empty():
		_fallback = CameraDefs.stats(camera_id, level)
	return float(_fallback.get(key, 0.0))


## Sekunden zwischen zwei Schüssen.
func get_fire_interval() -> float:
	return maxf(get_value("interval"), CameraDefs.MIN_INTERVAL)


## Schaden eines Schusses: der feste Wert der Kamera.
func get_shot_damage() -> float:
	return get_value("damage")


## Reichweite in Metern.
func get_range() -> float:
	return get_value("range")


## Anteil der Wirkung für das zweite Ziel (Zweitkamera), 0 = keines.
func get_second_share() -> float:
	return maxf(0.0, get_value("second"))


## Sekunden bis zum nächsten Auslösen (0 = bereit, wartet auf ein Ziel).
func get_cooldown_left() -> float:
	return _cooldown_left


## Weltposition der Linse: Von hier gehen die sichtbaren Strahlen aus.
func get_muzzle_position() -> Vector3:
	if is_instance_valid(_muzzle) and _muzzle.is_inside_tree():
		return _muzzle.global_position
	return global_position


## Lebende Zombies in Reichweite, der nächste zuerst (ohne Prüfung der Sichtlinie).
func targets_in_range() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not is_inside_tree():
		return result
	var origin: Vector3 = global_position
	var reach: float = get_range()
	var pairs: Array = []
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		if not _is_alive(node):
			continue
		var zombie: Node3D = node as Node3D
		var distance: float = origin.distance_to(_center_of(zombie))
		if distance <= reach:
			pairs.append([distance, zombie])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for pair: Array in pairs:
		result.append(pair[1] as Node3D)
	return result


## Die ersten count Zombies aus candidates, die die Kamera sieht. skip: Instanz-ID -> true für
## Zombies, die nicht in Frage kommen.
func pick_visible(candidates: Array[Node3D], count: int, skip: Dictionary = {}) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if count <= 0:
		return result
	for zombie: Node3D in candidates:
		if skip.has(zombie.get_instance_id()) or not sees(zombie):
			continue
		result.append(zombie)
		if result.size() >= count:
			break
	return result


## Der nächste lebende Zombie in Reichweite mit freier Sichtlinie, sonst null.
func find_target() -> Node3D:
	var found: Array[Node3D] = pick_visible(targets_in_range(), 1)
	return found[0] if not found.is_empty() else null


## Hat die Kamera freie Sicht auf die Körpermitte dieses Zombies?
func sees(zombie: Node3D) -> bool:
	return _has_line_of_sight(global_position, _center_of(zombie))


## Löst sofort aus, ohne den Takt zu prüfen (auch für Tests). Gibt true zurück, wenn die Kamera
## geschossen, geblitzt oder markiert hat. Schreibt das abgeleitete Skript.
func try_fire() -> bool:
	return false


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
	for entry: Dictionary in _spinners:
		var node: Node3D = entry["node"] as Node3D
		if is_instance_valid(node):
			node.rotate_object_local(Vector3.UP, float(entry["speed"]) * delta)
	_animate(delta)


func _physics_process(delta: float) -> void:
	# Eine entfernte Kamera (neuer Lauf, aus dem Rucksack genommen) hängt bis zum Ende des Bilds
	# noch im Baum: Sie löst nicht mehr aus.
	if is_queued_for_deletion():
		return
	var player: Node3D = _player()
	if player != null:
		_desired = _clear_of_walls(player, _wanted_position(player))
		_has_desired = true
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_scan_left = maxf(0.0, _scan_left - delta)
	_aim_hold_left = maxf(0.0, _aim_hold_left - delta)
	if _aim_hold_left <= 0.0:
		_has_aim = false
	var active: bool = Game.state == Game.State.PLAYING and player != null and not bool(player.get("is_dead"))
	_tick_extra(delta, active)
	if _cooldown_left > 0.0 or _scan_left > 0.0 or not active:
		return
	if try_fire():
		_cooldown_left = get_fire_interval()
	else:
		_scan_left = Balance.DRONE_SCAN_INTERVAL


## Baut das Aussehen der Kamera (Teile an _pivot schwenken mit, Teile an self nicht). Vorn ist -Z.
## Schreibt das abgeleitete Skript.
func _build_visual() -> void:
	pass


## Zusätzliche Zeit-Arbeit je Physik-Schritt (zweiter Blitz, eigene Merker). active: Das Spiel
## läuft und der Spieler lebt.
func _tick_extra(_delta: float, _active: bool) -> void:
	pass


## Zusätzliche Bewegung je Bild (Blinken und Ähnliches).
func _animate(_delta: float) -> void:
	pass


## Nach jedem Auslösen: Die Kamera blickt auf aim_point, zählt mit, zuckt kurz zurück und meldet
## sich über Events.camera_fired.
func _after_shot(aim_point: Vector3) -> void:
	_aim_point = aim_point
	_has_aim = true
	_aim_hold_left = AIM_HOLD
	shots_fired += 1
	_play_recoil()
	Events.camera_fired.emit(camera_id, global_position)


## Schaden an einem Zombie mit der Quelle dieser Kamera, dazu die Trefferzahl. candidate ist
## bewusst ohne Typ: Ein früherer Treffer desselben Schusses kann das Ziel schon entfernt haben.
func _damage(candidate: Variant, amount: float, hit_position: Vector3) -> void:
	if amount <= 0.0 or not _is_alive(candidate):
		return
	var zombie: Node3D = candidate
	if show_damage_numbers:
		Fx.damage_number(Fx.root_of(self), hit_position + Vector3(0.0, 0.5, 0.0), amount, number_color)
	zombie.call("take_damage", amount, {"source": camera_id, "hit_position": hit_position})


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


## Wunschplatz: der Platz dieser Kamera (Drone.slot_offset) um den Spieler, in Flughöhe über
## seinen Füßen.
func _wanted_position(player: Node3D) -> Vector3:
	var forward: Vector3 = _player_forward(player)
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var offset: Vector3 = Drone.slot_offset(slot)
	return player.global_position + forward * offset.z + right * offset.x \
		+ Vector3(0.0, Balance.DRONE_HOVER_HEIGHT + offset.y, 0.0)


## Hält die Kamera vor Wänden und unter der Decke: Trifft der Weg vom Kopf des Spielers zum
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


## Lebt dieser Zombie noch und hängt im Baum? Nimmt bewusst jeden Wert an, auch ein schon
## freigegebenes Objekt.
func _is_alive(candidate: Variant) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node3D:
		return false
	var zombie: Node3D = candidate
	return zombie.is_inside_tree() and not zombie.is_queued_for_deletion() \
		and not bool(zombie.get("is_dead")) and zombie.has_method("take_damage")


## Körpermitte eines Zombies (Zielpunkt).
func _center_of(zombie: Node3D) -> Vector3:
	if zombie.has_method("get_center_position"):
		return zombie.call("get_center_position")
	return zombie.global_position + Vector3(0.0, Balance.ZOMBIE_HEIGHT * 0.5, 0.0)


## Körperradius eines Zombies.
func _radius_of(zombie: Node3D) -> float:
	var radius: Variant = zombie.get("body_radius")
	return float(radius) if radius != null else Balance.ZOMBIE_RADIUS


## Ist das ein Elite-Zombie?
func _is_elite(zombie: Node3D) -> bool:
	return String(zombie.get("zombie_type")) == "elite"


## Freie Sicht zwischen zwei Punkten? Nur die Welt (Lage 1) verdeckt. Ohne Physik-Welt: ja.
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
	# Die Kamera selbst dreht sich nie, also ist die Ausrichtung des Schwenkteils im Raum der
	# Kamera dieselbe wie in der Welt.
	_pivot.basis = _pivot.basis.orthonormalized().slerp(target_basis, weight)


## Kurzer Rückstoß beim Auslösen.
func _play_recoil() -> void:
	if not is_instance_valid(_pivot) or not _pivot.is_inside_tree():
		return
	_pivot.position = Vector3.ZERO
	var kick: Vector3 = _pivot.basis.z.normalized() * RECOIL_DISTANCE
	var tween: Tween = _pivot.create_tween()
	tween.tween_property(_pivot, "position", kick, 0.03)
	tween.tween_property(_pivot, "position", Vector3.ZERO, 0.12)


# --- Bausteine für das Aussehen ---

## Beleuchtetes Material (Gehäuse), je Schlüssel geteilt.
static func _lit(color: Color, metallic: float = 0.5, roughness: float = 0.45) -> StandardMaterial3D:
	var key: String = "lit:%s:%.2f:%.2f" % [color.to_html(), metallic, roughness]
	if not _shared_materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metallic
		material.roughness = roughness
		_shared_materials[key] = material
	return _shared_materials[key] as StandardMaterial3D


## Beleuchtetes, selbst leuchtendes Material (Streifen, Rotorblätter), je Schlüssel geteilt.
static func _glowing(color: Color, energy: float = 0.7) -> StandardMaterial3D:
	var key: String = "glow:%s:%.2f" % [color.to_html(), energy]
	if not _shared_materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		_shared_materials[key] = material
	return _shared_materials[key] as StandardMaterial3D


## Unbeleuchtetes Material (Linsen, Lämpchen), je Farbe geteilt.
static func _flat(color: Color) -> StandardMaterial3D:
	var key: String = "flat:%s" % color.to_html()
	if not _shared_materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		_shared_materials[key] = material
	return _shared_materials[key] as StandardMaterial3D


## Quader, ohne parent am Schwenkteil.
func _add_box(node_name: String, size: Vector3, at: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var key: String = "box:%s" % size
	if not _shared_meshes.has(key):
		var box: BoxMesh = BoxMesh.new()
		box.size = size
		_shared_meshes[key] = box
	return _add_mesh(node_name, _shared_meshes[key] as Mesh, at, material, parent)


## Zylinder oder Kegelstumpf, ohne parent am Schwenkteil. along_z = true legt ihn entlang der
## Blickachse: front_radius zeigt dann nach vorn (-Z), back_radius nach hinten. Sonst steht er
## aufrecht (front_radius unten, back_radius oben).
func _add_cylinder(node_name: String, front_radius: float, back_radius: float, length: float, at: Vector3, material: Material, along_z: bool, parent: Node3D = null) -> MeshInstance3D:
	var key: String = "cyl:%.3f:%.3f:%.3f" % [front_radius, back_radius, length]
	if not _shared_meshes.has(key):
		var cylinder: CylinderMesh = CylinderMesh.new()
		cylinder.bottom_radius = front_radius
		cylinder.top_radius = back_radius
		cylinder.height = length
		cylinder.radial_segments = 14
		cylinder.rings = 1
		_shared_meshes[key] = cylinder
	var node: MeshInstance3D = _add_mesh(node_name, _shared_meshes[key] as Mesh, at, material, parent)
	if along_z:
		node.rotation.x = PI * 0.5
	return node


func _add_mesh(node_name: String, mesh: Mesh, at: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.position = at
	(parent if parent != null else _pivot).add_child(node, true)
	return node


## Rotor aus zwei gekreuzten Blättern an einem kurzen Mast, am Rumpf (schwenkt nicht mit). at ist
## die Stelle der Blätter, mast_length die Länge des Masts darunter (negativ: Mast darüber, der
## Rotor hängt unter der Kamera). Er dreht sich mit speed Radiant je Sekunde.
func _add_rotor(at: Vector3, blade_length: float, mast_length: float, blade_material: Material, mast_material: Material, speed: float) -> Node3D:
	if absf(mast_length) > 0.001:
		_add_cylinder("Mast", 0.018, 0.018, absf(mast_length), at - Vector3(0.0, mast_length * 0.5, 0.0), mast_material, false, self)
	var rotor: Node3D = Node3D.new()
	rotor.name = "Rotor"
	rotor.position = at
	add_child(rotor, true)
	for turn: int in 2:
		var blade: MeshInstance3D = _add_box("Blade", Vector3(blade_length, 0.01, 0.05), Vector3.ZERO, blade_material, rotor)
		blade.rotation.y = PI * 0.5 * float(turn)
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spinners.append({"node": rotor, "speed": speed})
	return rotor
