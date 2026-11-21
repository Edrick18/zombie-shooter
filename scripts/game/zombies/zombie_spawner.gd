extends Node
## Modul: Zombies (scripts/game/zombies).
## Erzeugt Zombies an den Spawnpunkten des Levels (Marker3D in Gruppe "zombie_spawns" mit
## Meta "zone" (int) und Meta "active" (bool, fehlt = aktiv)). Die Punkte der Zone 2 schaltet
## die Tür beim Öffnen frei, vorher erscheint dort niemand.
##
## Wahl des Spawnpunkts:
## - nie derselbe Punkt zweimal hintereinander (solange es mehr als einen aktiven gibt)
## - möglichst kein Punkt direkt neben dem Spieler (näher als Balance.SPAWN_MIN_PLAYER_DISTANCE)
## - unter den übrigen zufällig über Game.rng, nähere Punkte etwas häufiger, damit die Welle
##   dort ankommt, wo der Spieler gerade ist

const Balance := preload("res://scripts/core/balance.gd")
const Zombie := preload("res://scripts/game/zombies/zombie.gd")

## Behälter für neue Zombies. main.gd setzt ihn vor add_child auf den Knoten "Zombies".
## Ohne Behälter landen Zombies beim Elternknoten des Spawners.
var zombie_parent: Node3D = null

var _last_marker: Marker3D = null


## Erzeugt einen Zombie des Typs für die Welle an einem aktiven Spawnpunkt, hängt ihn in den
## Behälter und sendet Events.zombie_spawned. Gibt den Zombie zurück (null, wenn der Spawner
## nicht im Baum hängt).
func spawn(type: String, wave: int) -> Node3D:
	var parent: Node = zombie_parent if is_instance_valid(zombie_parent) else get_parent()
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var zombie: Zombie = Zombie.new()
	zombie.setup(type, wave)
	var world_position: Vector3 = _pick_position()
	var parent_3d: Node3D = parent as Node3D
	if parent_3d != null:
		zombie.position = parent_3d.global_transform.affine_inverse() * world_position
	else:
		zombie.position = world_position
	# Gleich zum Spieler gedreht, damit er nicht erst im Stand herumschwenkt.
	if is_instance_valid(Game.player):
		var to_player: Vector3 = Game.player.global_position - world_position
		if Vector2(to_player.x, to_player.z).length_squared() > 0.01:
			zombie.rotation.y = atan2(-to_player.x, -to_player.z)
	parent.add_child(zombie)
	Events.zombie_spawned.emit(zombie)
	return zombie


## Alle aktiven Spawnpunkte (Zone 2 erst, wenn die Tür offen ist).
func get_active_spawns() -> Array[Marker3D]:
	var result: Array[Marker3D] = []
	if not is_inside_tree():
		return result
	for node: Node in get_tree().get_nodes_in_group("zombie_spawns"):
		var marker: Marker3D = node as Marker3D
		if marker == null or not marker.is_inside_tree() or marker.is_queued_for_deletion():
			continue
		if bool(marker.get_meta("active", true)):
			result.append(marker)
	return result


## Anzahl lebender Zombies (Knoten der Gruppe "zombies").
func alive_count() -> int:
	if not is_inside_tree():
		return 0
	return get_tree().get_nodes_in_group("zombies").size()


## Der Spawnpunkt des letzten Zombies (null vor dem ersten und ohne Spawnpunkte).
func get_last_spawn() -> Marker3D:
	return _last_marker if is_instance_valid(_last_marker) else null


## Wählt einen aktiven Spawnpunkt nach den Regeln oben und merkt ihn sich. null ohne Spawnpunkte.
func pick_spawn() -> Marker3D:
	var candidates: Array[Marker3D] = get_active_spawns()
	if candidates.is_empty():
		_last_marker = null
		return null
	if candidates.size() > 1 and is_instance_valid(_last_marker):
		candidates.erase(_last_marker)
	var picked: Marker3D = _pick_weighted(candidates)
	_last_marker = picked
	return picked


func _pick_weighted(candidates: Array[Marker3D]) -> Marker3D:
	if candidates.size() == 1:
		return candidates[0]
	var player: Node3D = Game.player
	if not is_instance_valid(player) or not player.is_inside_tree():
		return candidates[Game.rng.randi_range(0, candidates.size() - 1)]
	var player_position: Vector3 = player.global_position
	var far: Array[Marker3D] = []
	var farthest: Marker3D = candidates[0]
	var farthest_distance: float = -1.0
	for marker: Marker3D in candidates:
		var distance: float = marker.global_position.distance_to(player_position)
		if distance >= Balance.SPAWN_MIN_PLAYER_DISTANCE:
			far.append(marker)
		if distance > farthest_distance:
			farthest_distance = distance
			farthest = marker
	if far.is_empty():
		# Alle Punkte liegen direkt beim Spieler: der entfernteste.
		return farthest
	var weights: Array[float] = []
	var total: float = 0.0
	for marker: Marker3D in far:
		var weight: float = 1.0 / (Balance.SPAWN_WEIGHT_OFFSET + marker.global_position.distance_to(player_position))
		weights.append(weight)
		total += weight
	var roll: float = Game.rng.randf() * total
	for i: int in far.size():
		roll -= weights[i]
		if roll <= 0.0:
			return far[i]
	return far[far.size() - 1]


func _pick_position() -> Vector3:
	var marker: Marker3D = pick_spawn()
	if marker == null:
		# Kein Spawnpunkt (Test ohne Level): irgendwo auf einem Kreis um den Ursprung.
		var angle: float = Game.rng.randf() * TAU
		return Vector3(cos(angle), 0.0, sin(angle)) * Balance.SPAWN_FALLBACK_DISTANCE
	var jitter: Vector3 = Vector3(
		Game.rng.randf_range(-Balance.SPAWN_JITTER, Balance.SPAWN_JITTER), 0.0,
		Game.rng.randf_range(-Balance.SPAWN_JITTER, Balance.SPAWN_JITTER))
	return marker.global_position + jitter
