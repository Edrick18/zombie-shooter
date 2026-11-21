extends Node
## Modul: Upgrades (scripts/game/upgrades).
## Entscheidet bei jedem Events.zombie_killed, ob eine Kiste fällt (ChestRoller), und legt sie
## an die Stelle des Toten:
## - Elite: immer, Seltenheit nach der Elite-Verteilung
## - normale Zombies: Chance aus ChestRoller.drop_chance (3 % plus Glück)
## - Welle Balance.GUARANTEED_CHEST_WAVE: Der letzte Zombie der Welle lässt sicher eine fallen.
##   Dafür zählt der ChestDropper selbst mit (wave_started liefert die Gesamtzahl, gezählt werden
##   wie beim WaveManager nur Zombies mit Meta "wave_spawn"). Als Netz darunter: Ist die Welle
##   vorbei (wave_cleared) und die sichere Kiste fehlt noch, fällt sie am Ort des letzten Kills.
##
## Eine fallende Kiste landet auf dem Boden, auf dem Navigationsnetz (also dort, wo man laufen
## kann) und nicht genau auf einer anderen Kiste. Dazu gibt es eine kleine Explosion und Konfetti.
## Die Meldung zur Kiste zeigt das HUD (es hört auf Events.chest_dropped).

const Balance := preload("res://scripts/core/balance.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")
const Chest := preload("res://scripts/game/upgrades/chest.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

# --- Reine Platzierungs- und Optik-Zahlen ---
## So weit über und unter dem Ort wird der Boden gesucht.
const FLOOR_PROBE_UP: float = 1.0
const FLOOR_PROBE_DOWN: float = 6.0

## Behälter für Kisten. main.gd setzt ihn vor add_child auf den Knoten "Chests".
## Ohne Behälter landen Kisten beim Elternknoten des ChestDroppers.
var chest_parent: Node3D = null

var _wave: int = 0
var _wave_total: int = 0
var _wave_kills: int = 0
## Die sichere Kiste der Welle Balance.GUARANTEED_CHEST_WAVE gibt es je Lauf genau einmal.
var _sure_chest_given: bool = false
var _has_last_kill: bool = false
var _last_kill_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	Events.run_started.connect(_on_run_started)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_cleared.connect(_on_wave_cleared)
	Events.zombie_killed.connect(_on_zombie_killed)


## Legt eine Kiste dieser Seltenheit an position (Weltkoordinaten, Bodenhöhe) in den Behälter,
## sendet Events.chest_dropped und gibt die Kiste zurück. Liegt position in der Luft oder
## neben der begehbaren Fläche, rückt die Kiste auf den Boden bzw. auf das Navigationsnetz.
func spawn_chest(position: Vector3, rarity: int) -> Node3D:
	var parent: Node = chest_parent if is_instance_valid(chest_parent) else get_parent()
	if not is_instance_valid(parent):
		return null
	var chest: Area3D = Chest.new()
	chest.call("setup", rarity)
	chest.position = position
	parent.add_child(chest)
	if chest.is_inside_tree():
		chest.global_position = _snap_to_floor(_snap_to_navigation(position))
	Events.chest_dropped.emit(chest)
	return chest


## Sucht für eine fallende Kiste einen guten Platz nahe position: begehbar, auf dem Boden und
## mit Abstand zu anderen Kisten.
func find_drop_spot(position: Vector3) -> Vector3:
	var spot: Vector3 = _snap_to_navigation(position)
	if _is_crowded(spot):
		# Im Kreis um den Ort suchen, zwei Ringe weit.
		var found: bool = false
		for ring: int in range(1, 3):
			for step: int in 8:
				var angle: float = TAU * float(step) / 8.0
				var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * Balance.CHEST_SPACING * float(ring)
				var candidate: Vector3 = _snap_to_navigation(position + offset)
				if not _is_crowded(candidate) and _has_clear_way(position, candidate):
					spot = candidate
					found = true
					break
			if found:
				break
	return _snap_to_floor(spot)


func _on_run_started() -> void:
	# Neuer Lauf in derselben Szene: liegen gebliebene Kisten weg.
	for node: Node in get_tree().get_nodes_in_group("chests"):
		if is_instance_valid(node):
			node.remove_from_group("chests")
			node.queue_free()
	_wave = 0
	_wave_total = 0
	_wave_kills = 0
	_sure_chest_given = false
	_has_last_kill = false
	_last_kill_position = Vector3.ZERO


func _on_wave_started(wave: int, total_zombies: int) -> void:
	_wave = wave
	_wave_total = total_zombies
	_wave_kills = 0
	_has_last_kill = false


func _on_wave_cleared(wave: int) -> void:
	# Netz unter der Zählung: Die sichere Kiste fällt spätestens jetzt.
	if wave != Balance.GUARANTEED_CHEST_WAVE or _sure_chest_given:
		return
	_sure_chest_given = true
	var position: Vector3 = _last_kill_position
	if not _has_last_kill:
		if not is_instance_valid(Game.player) or not Game.player.is_inside_tree():
			return
		position = Game.player.global_position
	_drop(position, false)


func _on_zombie_killed(zombie: Node3D, _info: Dictionary) -> void:
	if not is_instance_valid(zombie) or not zombie.is_inside_tree():
		return
	var position: Vector3 = zombie.global_position
	var counts: bool = bool(zombie.get_meta("wave_spawn", false))
	if counts:
		_wave_kills += 1
		_has_last_kill = true
		_last_kill_position = position
	var is_elite: bool = String(zombie.get("zombie_type")) == "elite"
	var is_last_of_sure_wave: bool = counts and not _sure_chest_given \
		and _wave == Balance.GUARANTEED_CHEST_WAVE and _wave_total > 0 and _wave_kills >= _wave_total
	if is_elite or is_last_of_sure_wave or ChestRoller.should_drop(Game.rng, false, Game.upgrades):
		if is_last_of_sure_wave:
			_sure_chest_given = true
		_drop(position, is_elite)


## Würfelt die Seltenheit und lässt die Kiste mit etwas Tamtam fallen.
func _drop(position: Vector3, is_elite: bool) -> void:
	var rarity: int = ChestRoller.roll_rarity(Game.rng, is_elite, Game.upgrades.luck_level())
	var chest: Node3D = spawn_chest(find_drop_spot(position), rarity)
	if not is_instance_valid(chest) or not chest.is_inside_tree():
		return
	var fx_root: Node = Fx.root_of(self)
	Fx.explosion(fx_root, chest.global_position + Vector3(0.0, 0.5, 0.0), 1.4, ChestRoller.rarity_color(rarity))
	Fx.confetti(fx_root, chest.global_position + Vector3(0.0, 0.8, 0.0))


## Die 3D-Welt, in der die Kisten liegen. null, solange nichts im Baum hängt.
func _world() -> World3D:
	if is_instance_valid(chest_parent) and chest_parent.is_inside_tree():
		return chest_parent.get_world_3d()
	if is_inside_tree():
		return get_viewport().find_world_3d()
	return null


## Rückt einen Ort neben der begehbaren Fläche waagerecht auf das Navigationsnetz.
## Ohne gebackenes Netz (headless-Tests ohne Level) bleibt der Ort, wie er ist.
func _snap_to_navigation(position: Vector3) -> Vector3:
	var world: World3D = _world()
	if world == null:
		return position
	var map: RID = world.navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return position
	if NavigationServer3D.map_get_regions(map).is_empty():
		return position
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, position)
	var flat_offset: Vector2 = Vector2(closest.x - position.x, closest.z - position.z)
	if flat_offset.length() <= Balance.CHEST_NAV_SNAP_TOLERANCE:
		return position
	return Vector3(closest.x, position.y, closest.z)


## Setzt einen Ort senkrecht auf den Boden darunter (Lage "world"). Ohne Boden bleibt die Höhe.
func _snap_to_floor(position: Vector3) -> Vector3:
	var world: World3D = _world()
	if world == null:
		return position
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		position + Vector3(0.0, FLOOR_PROBE_UP, 0.0),
		position - Vector3(0.0, FLOOR_PROBE_DOWN, 0.0),
		Balance.LAYER_WORLD)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return position
	return Vector3(position.x, (hit["position"] as Vector3).y, position.z)


## Liegt schon eine Kiste zu nah an diesem Ort?
func _is_crowded(position: Vector3) -> bool:
	if not is_inside_tree():
		return false
	for node: Node in get_tree().get_nodes_in_group("chests"):
		var chest: Node3D = node as Node3D
		if not is_instance_valid(chest) or not chest.is_inside_tree():
			continue
		var offset: Vector3 = chest.global_position - position
		offset.y = 0.0
		if offset.length() < Balance.CHEST_SPACING:
			return true
	return false


## Steht zwischen zwei Orten keine Wand? (Strahl in Kniehöhe gegen die Lage "world".)
func _has_clear_way(from: Vector3, to: Vector3) -> bool:
	var world: World3D = _world()
	if world == null:
		return true
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return true
	var lift: Vector3 = Vector3(0.0, 0.5, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from + lift, to + lift, Balance.MASK_LINE_OF_SIGHT)
	return space.intersect_ray(query).is_empty()
