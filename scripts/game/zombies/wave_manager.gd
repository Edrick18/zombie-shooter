extends Node
## Modul: Zombies (scripts/game/zombies).
## Steuert die Wellen nach WavePlan: Countdown, Spawn-Folge, Mitzählen, Wellenende mit Heilung.
## Sendet wave_started, zombies_left_changed, wave_cleared, intermission_tick und Banner im Showton.
##
## Ablauf: Events.run_started -> Countdown Balance.FIRST_WAVE_DELAY -> start_wave(1) -> alle
## Zombies der Welle tot -> wave_cleared, Heilung -> Countdown Balance.INTERMISSION_SECONDS ->
## nächste Welle. Gezählt werden nur Zombies, die dieser Manager erzeugt hat (Meta "wave_spawn").
##
## Sicherung gegen eine Welle, die nie endet (einmal je Sekunde geprüft):
## - Ein Zombie, der aus der Welt gefallen ist, kommt sofort an einen Spawnpunkt zurück.
## - Ein Zombie, der Balance.ZOMBIE_STUCK_SECONDS lang weder vorankommt noch beim Spieler steht noch Schaden
##   nimmt, wird an einen anderen Spawnpunkt gesetzt. Nach Balance.ZOMBIE_STUCK_MAX_RESCUES Versuchen
##   verschwindet er ohne Belohnung und zählt als erledigt.
## - Stimmt die Zahl nicht mehr (ein Zombie wurde ohne zombie_killed entfernt), wird sie
##   berichtigt.

const Balance := preload("res://scripts/core/balance.gd")
const WavePlan := preload("res://scripts/core/wave_plan.gd")

const WATCH_INTERVAL: float = 1.0
## So viele Prüfungen hintereinander muss die Zahl falsch sein, bevor sie berichtigt wird.
const MISMATCH_CHECKS: int = 2

## Banner zum Wellenbeginn. Feste Wellen haben einen eigenen Spruch, die übrigen wechseln durch.
const WAVE_BANNERS_SPECIAL: Dictionary = {
	1: "Welle 1 – Vorhang auf, Kamera läuft!",
	2: "Welle 2 – Ein Stargast betritt das Studio!",
	3: "Welle 3 – Jetzt wird gerannt!",
	6: "Welle 6 – Zwei Stargäste auf einmal!",
	10: "Welle 10 – Das große Staffelfinale!",
}
const WAVE_BANNERS: Array[String] = [
	"Welle %d – Bleiben Sie dran!",
	"Welle %d – Die Quote steigt!",
	"Welle %d – Das Publikum will mehr!",
	"Welle %d – Nachschub aus der Maske!",
	"Welle %d – Applaus für die Untoten!",
	"Welle %d – Jetzt geht es um alles!",
]
const BANNER_WAVE_CLEARED: String = "Welle %d überstanden! +%d Leben"
const BANNER_ELITE: String = "Stargast im Anmarsch – mit Geschenk!"

## false: Der Countdown läuft nicht, also beginnt keine Welle von selbst (für Tests).
## Eine mit start_wave begonnene Welle läuft trotzdem ganz normal bis wave_cleared.
var auto_start: bool = true
## Der ZombieSpawner. main.gd setzt ihn vor add_child.
var spawner: Node = null
## Laufende oder zuletzt gelaufene Welle, 0 vor der ersten.
var current_wave: int = 0
## Noch nicht getötete Zombies der laufenden Welle (auch noch nicht erschienene).
var zombies_left: int = 0
var is_wave_active: bool = false

var _queue: Array[String] = []
var _spawn_timer: float = 0.0
## Restzeit bis zur nächsten Welle, < 0 = kein Countdown.
var _countdown: float = -1.0
var _last_tick: int = -1
## Lebende Zombies der laufenden Welle mit den Daten der Festhänge-Prüfung. Je Eintrag:
## { "zombie": Node3D, "anchor": Vector3, "still": float, "rescues": int, "hp": float }.
var _tracked: Array[Dictionary] = []
var _watch_left: float = WATCH_INTERVAL
var _mismatch_count: int = 0


func _ready() -> void:
	Events.run_started.connect(_on_run_started)
	Events.zombie_killed.connect(_on_zombie_killed)
	Events.game_over.connect(_on_game_over)


func _process(delta: float) -> void:
	if Game.state != Game.State.PLAYING:
		return
	if auto_start and _countdown >= 0.0:
		_countdown -= delta
		var seconds_left: int = ceili(maxf(_countdown, 0.0))
		if seconds_left != _last_tick:
			_last_tick = seconds_left
			Events.intermission_tick.emit(seconds_left)
		if _countdown <= 0.0:
			start_wave(current_wave + 1)
			return
	if not is_wave_active:
		return
	if not _queue.is_empty():
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			if _alive_count() < WavePlan.max_alive(current_wave):
				_spawn_next()
			else:
				# Obergrenze erreicht: Sobald Platz ist, kommt genau einer nach, kein Schwall.
				_spawn_timer = 0.0
	_watch_left -= delta
	if _watch_left <= 0.0:
		_watch_left = WATCH_INTERVAL
		_watch_wave(WATCH_INTERVAL)


## Beginnt sofort Welle n (ab 1): bricht einen Countdown ab, füllt die Spawn-Folge und sendet
## wave_started(n, Gesamtzahl), zombies_left_changed und das Banner der Welle ("Welle n – ...").
## Läuft noch eine Welle, wird sie abgebrochen: Ihre Zombies bleiben, zählen aber nicht mehr.
func start_wave(n: int) -> void:
	_release_tracked()
	var plan: Dictionary = WavePlan.plan(n)
	current_wave = int(plan["wave"])
	_queue.assign(plan["spawns"])
	zombies_left = int(plan["total"])
	is_wave_active = true
	_countdown = -1.0
	_last_tick = -1
	_spawn_timer = 0.0
	_watch_left = WATCH_INTERVAL
	_mismatch_count = 0
	Events.wave_started.emit(current_wave, zombies_left)
	Events.zombies_left_changed.emit(zombies_left)
	Events.banner.emit(get_wave_banner(current_wave))


## Sekunden bis zur nächsten Welle, -1.0 ohne Countdown.
func get_countdown() -> float:
	return _countdown


## Der Spruch zum Beginn der Welle. Beginnt immer mit "Welle n".
func get_wave_banner(wave: int) -> String:
	if WAVE_BANNERS_SPECIAL.has(wave):
		return String(WAVE_BANNERS_SPECIAL[wave])
	return WAVE_BANNERS[posmod(wave, WAVE_BANNERS.size())] % wave


## Zombies der laufenden Welle, die noch nicht erschienen sind.
func get_queued_count() -> int:
	return _queue.size()


## Lebende Zombies der laufenden Welle (nur die, die dieser Manager erzeugt hat).
func get_wave_alive_count() -> int:
	var count: int = 0
	for entry: Dictionary in _tracked:
		if _is_alive(entry["zombie"]):
			count += 1
	return count


func _on_run_started() -> void:
	# Neuer Lauf in derselben Szene: alte Zombies weg, alles auf Anfang.
	_tracked.clear()
	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group("zombies"):
			_remove_zombie(node)
	current_wave = 0
	zombies_left = 0
	is_wave_active = false
	_queue.clear()
	_mismatch_count = 0
	_begin_countdown(Balance.FIRST_WAVE_DELAY)


func _on_game_over(_stats: Dictionary) -> void:
	# Der Lauf ist vorbei: keine Spawns, kein Countdown, keine Zählung mehr.
	is_wave_active = false
	_queue.clear()
	_countdown = -1.0
	_last_tick = -1


func _on_zombie_killed(zombie: Node3D, _info: Dictionary) -> void:
	if not is_wave_active or not is_instance_valid(zombie):
		return
	if not bool(zombie.get_meta("wave_spawn", false)):
		return
	_untrack(zombie)
	_count_down_one()


## Ein Zombie der Welle ist erledigt: Zahl senken, melden, bei 0 die Welle beenden.
func _count_down_one() -> void:
	zombies_left = maxi(0, zombies_left - 1)
	Events.zombies_left_changed.emit(zombies_left)
	if zombies_left <= 0 and _queue.is_empty():
		_finish_wave()


func _finish_wave() -> void:
	if not is_wave_active:
		return
	is_wave_active = false
	_tracked.clear()
	Events.wave_cleared.emit(current_wave)
	if is_instance_valid(Game.player) and Game.player.has_method("heal"):
		Game.player.call("heal", Balance.WAVE_END_HEAL)
	Events.banner.emit(BANNER_WAVE_CLEARED % [current_wave, roundi(Balance.WAVE_END_HEAL)])
	_begin_countdown(Balance.INTERMISSION_SECONDS)


func _begin_countdown(seconds: float) -> void:
	_countdown = seconds
	_last_tick = -1


func _spawn_next() -> void:
	_spawn_timer = WavePlan.spawn_interval(current_wave)
	if not is_instance_valid(spawner) or not spawner.has_method("spawn"):
		return
	var type: String = _queue.pop_front()
	var spawned: Variant = spawner.call("spawn", type, current_wave)
	var zombie: Node3D = spawned as Node3D
	if not is_instance_valid(zombie):
		# Der Spawner konnte nichts erzeugen. Die Zahl berichtigt _watch_wave.
		return
	zombie.set_meta("wave_spawn", true)
	_tracked.append({
		"zombie": zombie,
		"anchor": zombie.global_position,
		"still": 0.0,
		"rescues": 0,
		"hp": float(zombie.get("hp")),
	})
	if type == WavePlan.TYPE_ELITE:
		Events.banner.emit(BANNER_ELITE)


func _alive_count() -> int:
	if is_instance_valid(spawner) and spawner.has_method("alive_count"):
		return int(spawner.call("alive_count"))
	return get_tree().get_nodes_in_group("zombies").size()


# --- Sicherung gegen festhängende Wellen -----------------------------------------------------

## Prüft alle lebenden Zombies der Welle und gleicht danach die Zahl ab. step = Sekunden seit
## der letzten Prüfung.
func _watch_wave(step: float) -> void:
	var player: Node3D = Game.player if is_instance_valid(Game.player) else null
	# Rückwärts, weil eine Rettung den eigenen Eintrag entfernen kann.
	for i: int in range(_tracked.size() - 1, -1, -1):
		if not is_wave_active:
			return
		if i >= _tracked.size():
			continue
		var entry: Dictionary = _tracked[i]
		if not _is_alive(entry["zombie"]):
			_tracked.remove_at(i)
			continue
		var zombie: Node3D = entry["zombie"]
		var position: Vector3 = zombie.global_position
		if position.y < Balance.ZOMBIE_OUT_OF_WORLD_Y:
			_rescue(i)
			continue
		var anchor: Vector3 = entry["anchor"]
		var moved: bool = Vector2(position.x - anchor.x, position.z - anchor.z).length() >= Balance.ZOMBIE_STUCK_MOVE_DISTANCE
		var engaged: bool = false
		if player != null:
			var to_player: Vector3 = player.global_position - position
			engaged = Vector2(to_player.x, to_player.z).length() <= Balance.ZOMBIE_STUCK_ENGAGED_DISTANCE
		var current_hp: float = float(zombie.get("hp"))
		var damaged: bool = current_hp < float(entry["hp"])
		if moved or engaged or damaged:
			entry["anchor"] = position
			entry["still"] = 0.0
			entry["hp"] = current_hp
			continue
		entry["still"] = float(entry["still"]) + step
		if float(entry["still"]) >= Balance.ZOMBIE_STUCK_SECONDS:
			_rescue(i)
	if is_wave_active:
		_reconcile_count()


## Setzt den festhängenden oder gefallenen Zombie des Eintrags an einen Spawnpunkt. Hilft das
## mehrfach nicht (oder gibt es keinen Platz), verschwindet er ohne Belohnung und zählt als
## erledigt.
func _rescue(index: int) -> void:
	var entry: Dictionary = _tracked[index]
	var zombie: Node3D = entry["zombie"]
	entry["rescues"] = int(entry["rescues"]) + 1
	var target: Variant = _rescue_position(zombie.global_position)
	if int(entry["rescues"]) > Balance.ZOMBIE_STUCK_MAX_RESCUES or target == null or not zombie.has_method("teleport_to"):
		_tracked.remove_at(index)
		zombie.set_meta("wave_spawn", false)
		_remove_zombie(zombie)
		_count_down_one()
		return
	var world_position: Vector3 = target
	zombie.call("teleport_to", world_position)
	entry["anchor"] = world_position
	entry["still"] = 0.0
	entry["hp"] = float(zombie.get("hp"))


## Ein aktiver Spawnpunkt für die Rettung, möglichst nicht der, an dem der Zombie festhängt.
## Ohne Spawnpunkte eine Stelle in der Nähe des Spielers, ohne Spieler null.
func _rescue_position(from: Vector3) -> Variant:
	var spawns: Array = []
	if is_instance_valid(spawner) and spawner.has_method("get_active_spawns"):
		spawns = spawner.call("get_active_spawns")
	var candidates: Array[Vector3] = []
	var nearest_index: int = -1
	var nearest_distance: float = INF
	for node: Variant in spawns:
		var marker: Node3D = node as Node3D
		if not is_instance_valid(marker):
			continue
		var distance: float = marker.global_position.distance_to(from)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = candidates.size()
		candidates.append(marker.global_position)
	if candidates.size() > 1:
		candidates.remove_at(nearest_index)
	if not candidates.is_empty():
		return candidates[Game.rng.randi_range(0, candidates.size() - 1)]
	if not is_instance_valid(Game.player):
		return null
	var angle: float = Game.rng.randf() * TAU
	return Game.player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * Balance.ZOMBIE_RESCUE_FALLBACK_DISTANCE


## Erwartet wird: noch nicht erschienene plus lebende Zombies der Welle. Liegt zombies_left
## mehrere Prüfungen lang darüber, ist ein Zombie ohne zombie_killed verschwunden.
func _reconcile_count() -> void:
	var expected: int = _queue.size() + get_wave_alive_count()
	if expected >= zombies_left:
		_mismatch_count = 0
		return
	_mismatch_count += 1
	if _mismatch_count < MISMATCH_CHECKS:
		return
	_mismatch_count = 0
	zombies_left = expected
	Events.zombies_left_changed.emit(zombies_left)
	if zombies_left <= 0 and _queue.is_empty():
		_finish_wave()


## Zombies einer abgebrochenen Welle zählen nicht mehr mit.
func _release_tracked() -> void:
	for entry: Dictionary in _tracked:
		if is_instance_valid(entry["zombie"]):
			var zombie: Node3D = entry["zombie"]
			zombie.set_meta("wave_spawn", false)
	_tracked.clear()


func _untrack(zombie: Node3D) -> void:
	for i: int in range(_tracked.size() - 1, -1, -1):
		var tracked: Variant = _tracked[i]["zombie"]
		if not is_instance_valid(tracked) or tracked == zombie:
			_tracked.remove_at(i)


## Entfernt einen Zombie ohne Belohnung (kein zombie_killed).
func _remove_zombie(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.has_method("despawn"):
		node.call("despawn")
	else:
		node.remove_from_group("zombies")
		node.queue_free()


func _is_alive(node: Variant) -> bool:
	if not is_instance_valid(node):
		return false
	var zombie: Node = node as Node
	if zombie == null or zombie.is_queued_for_deletion() or not zombie.is_inside_tree():
		return false
	return not bool(zombie.get("is_dead"))
