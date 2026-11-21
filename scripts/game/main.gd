extends Node3D
## Baut das ganze Spiel aus den Modul-Skripten zusammen und startet den Lauf.
## Besitzer: Fundament. Hängt als einziges Skript an scenes/main.tscn (Knoten "Main").
##
## Baum nach _ready (Namen sind fest, andere Module dürfen sich darauf verlassen):
##   Main (Gruppe "main")
##   ├─ Level           Node3D, von LevelBuilder gefüllt
##   ├─ Zombies         Node3D, Behälter für Zombies
##   ├─ Chests          Node3D, Behälter für Kisten
##   ├─ Fx              Node3D, Behälter für Effekte und die Drohne (Gruppe "fx_root")
##   ├─ Player          player.gd (Gruppe "player")
##   ├─ ZombieSpawner   zombie_spawner.gd
##   ├─ UpgradeEffects  upgrade_effects.gd
##   ├─ ChestDropper    chest_dropper.gd
##   ├─ WaveManager     wave_manager.gd
##   ├─ Hud             hud.gd (Ebene 1)
##   ├─ ChestChoice     chest_choice.gd (Ebene 10)
##   ├─ BackpackScreen  backpack_screen.gd (Ebene 15)
##   ├─ PauseMenu       pause_menu.gd (Ebene 20)
##   ├─ GameOver        game_over.gd (Ebene 30)
##   └─ CharacterSelect character_select.gd (Ebene 40)
## Vor dem ersten Lauf zeigt main.gd ein Ladebild und wärmt die Shader vor (warmup.gd, nicht
## headless), danach wählt der Spieler seinen Kandidaten (character_select.gd, nicht headless).
## Zum Schluss ruft main.gd Game.start_run(run_seed). Alle Module sind dann im Baum und haben
## ihr _ready hinter sich: Sie richten sich bei Events.run_started ein. main.gd selbst stellt
## bei jedem run_started den Spieler zurück auf den Startpunkt (Blick zur Bühne).

const LevelBuilder := preload("res://scripts/game/level/level_builder.gd")
const Player := preload("res://scripts/game/player/player.gd")
const ZombieSpawner := preload("res://scripts/game/zombies/zombie_spawner.gd")
const WaveManager := preload("res://scripts/game/zombies/wave_manager.gd")
const UpgradeEffects := preload("res://scripts/game/upgrades/upgrade_effects.gd")
const ChestDropper := preload("res://scripts/game/upgrades/chest_dropper.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const ChestChoice := preload("res://scripts/ui/chest_choice.gd")
const BackpackScreen := preload("res://scripts/ui/backpack_screen.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const GameOver := preload("res://scripts/ui/game_over.gd")
const CharacterSelect := preload("res://scripts/ui/character_select.gd")
const Balance := preload("res://scripts/core/balance.gd")
const Warmup := preload("res://scripts/game/warmup.gd")
const Settings := preload("res://scripts/game/settings.gd")

## Seed für Game.start_run. -1 = zufällig. Tests setzen ihn vor add_child.
var run_seed: int = -1
## false: main.gd ruft Game.start_run nicht selbst (Tests, die den Start selbst auslösen).
var start_on_ready: bool = true
## false: Die Shader werden vor dem ersten Lauf nicht vorgewärmt (Messungen, Bildschirmfotos).
## Headless (Tests) wird nie vorgewärmt, der Lauf startet dort wie bisher sofort in _ready.
var warmup_enabled: bool = true
## false: Der Lauf beginnt ohne Kandidatenwahl mit Game.character_id, wie er gerade ist (Messungen,
## Bildschirmfotos). Headless (Tests) gibt es nie eine Kandidatenwahl.
var character_select_enabled: bool = true

var level_root: Node3D
## Rückgabe von LevelBuilder.build: player_spawn, nav_region, door.
var level_info: Dictionary = {}
var zombies_root: Node3D
var chests_root: Node3D
var fx_root: Node3D
var player: Player
var spawner: ZombieSpawner
var upgrade_effects: UpgradeEffects
var chest_dropper: ChestDropper
var wave_manager: WaveManager
var hud: Hud
var chest_choice: ChestChoice
var backpack_screen: BackpackScreen
var pause_menu: PauseMenu
var game_over: GameOver
var character_select: CharacterSelect


func _ready() -> void:
	add_to_group("main")
	# Gespeicherte Einstellungen laden und Fenster, VSync, Auflösung und Kantenglättung setzen.
	Settings.ensure_loaded()
	Settings.apply_video(get_window())
	_build_world()
	_build_player()
	_build_systems()
	_build_ui()
	Events.run_started.connect(_on_run_started)
	if start_on_ready:
		if warmup_enabled and Warmup.is_needed():
			# Ladebild: alle Shader jetzt übersetzen, damit im Spiel nichts mehr ruckelt.
			var warmup: Warmup = Warmup.new()
			warmup.name = "Warmup"
			add_child(warmup)
			await warmup.run()
			warmup.queue_free()
		if character_select_enabled and DisplayServer.get_name() != "headless":
			# Kandidatenwahl: Der Lauf beginnt erst nach der Wahl. Nach einem Neustart (die Szene
			# wird neu geladen) steht sie wieder hier, mit dem letzten Kandidaten vorausgewählt.
			character_select.open()
			await character_select.character_chosen
			# Der Klick oder Tastendruck der Wahl soll im Lauf nichts auslösen (kein erster Schuss).
			await _wait_for_fire_release()
		Game.start_run(run_seed)


func _build_world() -> void:
	level_root = _add_container("Level")
	level_info = LevelBuilder.new().build(level_root)
	zombies_root = _add_container("Zombies")
	chests_root = _add_container("Chests")
	fx_root = _add_container("Fx")
	fx_root.add_to_group("fx_root")


func _build_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.position = level_info.get("player_spawn", Vector3.ZERO)
	add_child(player)


## Reihenfolge = Reihenfolge der Signal-Empfänger nach Game: erst Effekte, dann Kisten, dann Wellen.
func _build_systems() -> void:
	spawner = ZombieSpawner.new()
	spawner.name = "ZombieSpawner"
	spawner.zombie_parent = zombies_root
	add_child(spawner)
	upgrade_effects = UpgradeEffects.new()
	upgrade_effects.name = "UpgradeEffects"
	add_child(upgrade_effects)
	chest_dropper = ChestDropper.new()
	chest_dropper.name = "ChestDropper"
	chest_dropper.chest_parent = chests_root
	add_child(chest_dropper)
	wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	wave_manager.spawner = spawner
	add_child(wave_manager)


func _build_ui() -> void:
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	chest_choice = ChestChoice.new()
	chest_choice.name = "ChestChoice"
	add_child(chest_choice)
	backpack_screen = BackpackScreen.new()
	backpack_screen.name = "BackpackScreen"
	add_child(backpack_screen)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	game_over = GameOver.new()
	game_over.name = "GameOver"
	add_child(game_over)
	character_select = CharacterSelect.new()
	character_select.name = "CharacterSelect"
	add_child(character_select)


## Neuer Lauf (auch ein zweiter in derselben Szene): Der Spieler steht wieder am Startpunkt und
## schaut zur Bühne. Leben, Waffen, Zombies, Kisten und Tür stellen die Module selbst zurück.
func _on_run_started() -> void:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	var spawn: Vector3 = level_info.get("player_spawn", Vector3.ZERO)
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	player.look_at_point(spawn + Vector3(0.0, Balance.PLAYER_EYE_HEIGHT, -10.0))


## Wartet mindestens ein Bild und dann, bis die Schusstaste losgelassen ist (höchstens eine Sekunde).
func _wait_for_fire_release() -> void:
	await get_tree().process_frame
	var deadline: int = Time.get_ticks_msec() + 1000
	while Input.is_action_pressed("fire") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _add_container(node_name: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = node_name
	add_child(node)
	return node
