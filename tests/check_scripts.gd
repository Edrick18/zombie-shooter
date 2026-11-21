extends SceneTree
## Lädt jedes Skript unter res://scripts (auch in Unterordnern) und meldet jede Datei, die
## nicht lädt (Parse-Fehler, fehlende Abhängigkeit). Endet mit Code 1, sobald eine Datei scheitert.
## Läuft in _initialize statt _init: Erst dann kennt Godot die Autoload-Namen Events und Game.
## Aufruf: Godot --headless --path <Projekt> -s res://tests/check_scripts.gd

const SCRIPT_ROOT: String = "res://scripts"


func _initialize() -> void:
	var paths: Array[String] = []
	_collect(SCRIPT_ROOT, paths)
	paths.sort()
	var failed: Array[String] = []
	for path: String in paths:
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			failed.append(path)
	if paths.is_empty():
		printerr("FEHLER: Keine Skripte unter %s gefunden." % SCRIPT_ROOT)
		quit(1)
		return
	if failed.is_empty():
		print("Alle %d Skripte laden." % paths.size())
		quit(0)
		return
	for path: String in failed:
		printerr("FEHLER: Skript lädt nicht: %s" % path)
	printerr("%d von %d Skripten laden nicht." % [failed.size(), paths.size()])
	quit(1)


func _collect(dir_path: String, into: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		printerr("FEHLER: Ordner nicht lesbar: %s" % dir_path)
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), into)
	for file: String in dir.get_files():
		if file.get_extension() == "gd":
			into.append(dir_path.path_join(file))
