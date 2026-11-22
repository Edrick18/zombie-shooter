extends SceneTree
## Tests für die Einstellungen (scripts/game/settings.gd, auch die Lautstärke), den Shader-Halter
## (scripts/game/fx/shader_keep.gd) und den Regler im Pausemenü.
## Die Datei des Nutzers (user://settings.cfg) wird dabei weder gelesen noch geschrieben.

const TEMP_SETTINGS: String = "user://test_settings_tmp.cfg"
const TEMP_START: String = "user://test_start_tmp.cfg"
const TEMP_LIST: String = "user://test_shader_list_tmp.json"

var _failures: int = 0
var _settings: GDScript
var _keep: GDScript


func _initialize() -> void:
	_run()


func _run() -> void:
	# Ein Bild warten: Erst dann hängen die Autoloads im Baum.
	await process_frame
	_settings = load("res://scripts/game/settings.gd") as GDScript
	_keep = load("res://scripts/game/fx/shader_keep.gd") as GDScript
	_test_settings_values()
	_test_settings_file()
	_test_video_settings()
	_test_volume_setting()
	_test_material_keys()
	_test_tracking()
	_test_list_file()
	await _test_pause_slider()
	await _test_settings_menu()
	await _test_fps_label()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_LIST))
	if _failures == 0:
		print("Alle Tests für Einstellungen und Shader-Halter bestanden.")
	else:
		printerr("%d Test(s) fehlgeschlagen." % _failures)
	quit(1 if _failures > 0 else 0)


func _sensitivity() -> float:
	return float(_settings.get("mouse_sensitivity"))


func _test_settings_values() -> void:
	_settings.call("ensure_loaded")
	_near(_sensitivity(), 1.0, "Headless bleibt die Empfindlichkeit beim Standard 1,0.")
	_settings.call("set_mouse_sensitivity", 0.0)
	_near(_sensitivity(), 0.1, "Zu kleine Werte landen auf dem Minimum 0,1.")
	_settings.call("set_mouse_sensitivity", 99.0)
	_near(_sensitivity(), 3.0, "Zu große Werte landen auf dem Maximum 3,0.")
	_settings.call("set_mouse_sensitivity", 0.523)
	_near(_sensitivity(), 0.5, "Werte rasten im Raster von 0,05 ein.")
	_settings.call("set_mouse_sensitivity", 1.0)


func _test_settings_file() -> void:
	_settings.call("set_mouse_sensitivity", 1.65)
	_check(bool(_settings.call("save_to", TEMP_SETTINGS)), "save_to schreibt die Datei.")
	_settings.call("set_mouse_sensitivity", 1.0)
	_check(bool(_settings.call("load_from", TEMP_SETTINGS)), "load_from liest die Datei.")
	_near(_sensitivity(), 1.65, "Der gespeicherte Wert kommt zurück.")
	_check(not bool(_settings.call("load_from", "user://gibt_es_nicht.cfg")), "Fehlende Datei: load_from meldet false.")
	_near(_sensitivity(), 1.65, "Fehlende Datei ändert den Wert nicht.")
	# Ein unsinniger Wert in der Datei wird auf den erlaubten Bereich begrenzt.
	var config: ConfigFile = ConfigFile.new()
	config.set_value("eingabe", "mausempfindlichkeit", 500.0)
	config.save(TEMP_SETTINGS)
	_settings.call("load_from", TEMP_SETTINGS)
	_near(_sensitivity(), 3.0, "Ein zu großer Wert aus der Datei wird begrenzt.")
	_settings.call("set_mouse_sensitivity", 1.0)


## Grafik-Unterbau: Wahl, Begrenzung und die Startdatei, die Godot beim Programmstart selbst liest.
## Die Startdatei des Nutzers (user://start.cfg) wird dabei weder gelesen noch geschrieben.
func _test_graphics_driver() -> void:
	var ids: Array = _settings.get_script_constant_map().get("DRIVER_IDS", [])
	_check(ids.size() == 2 and str(ids[0]) == "opengl3_angle" and str(ids[1]) == "opengl3", "Zwei Unterbauten: ANGLE (sicher) und OpenGL (schnell).")
	_check(str(ProjectSettings.get_setting("application/config/project_settings_override", "")) == str(_settings.get_script_constant_map().get("START_PATH", "?")),
		"project.godot nennt die Startdatei aus den Einstellungen.")
	_settings.call("reset_to_defaults")
	_check(int(_settings.get("graphics_driver")) == 0, "Standard: Unterbau Sicher.")
	_settings.call("set_graphics_driver", 9)
	_check(int(_settings.get("graphics_driver")) == 1, "Der Unterbau wird auf den letzten Eintrag begrenzt.")
	_settings.call("set_value", "graphics_driver", 0)
	_check(int(_settings.call("get_value", "graphics_driver")) == 0, "Der Unterbau lässt sich über seinen Namen setzen und lesen.")
	var active: int = int(_settings.call("active_driver"))
	_settings.call("set_graphics_driver", active)
	_check(not bool(_settings.call("restart_needed")), "Läuft der gewählte Unterbau schon, ist kein Neustart nötig.")
	_settings.call("set_graphics_driver", 1 - active)
	_check(bool(_settings.call("restart_needed")), "Ein anderer Unterbau als der laufende braucht einen Neustart.")
	# Die Startdatei: Abschnitt und Schlüssel so, wie Godot sie als Projekteinstellung liest.
	_settings.call("set_graphics_driver", 1)
	_check(bool(_settings.call("save_start_to", TEMP_START)), "save_start_to schreibt die Startdatei.")
	var config: ConfigFile = ConfigFile.new()
	_check(config.load(TEMP_START) == OK and str(config.get_value("rendering", "gl_compatibility/driver.windows", "")) == "opengl3",
		"In der Startdatei steht der Treiber als Projekteinstellung.")
	_settings.call("set_graphics_driver", 0)
	_check(bool(_settings.call("load_start_from", TEMP_START)) and int(_settings.get("graphics_driver")) == 1, "load_start_from liest die Wahl zurück.")
	_check(not bool(_settings.call("load_start_from", "user://gibt_es_nicht.cfg")) and int(_settings.get("graphics_driver")) == 1,
		"Fehlende Startdatei ändert die Wahl nicht.")
	config.set_value("rendering", "gl_compatibility/driver.windows", "vulkan")
	config.save(TEMP_START)
	_settings.call("load_start_from", TEMP_START)
	_check(int(_settings.get("graphics_driver")) == 1, "Ein fremder Treibername in der Startdatei ändert die Wahl nicht.")
	# Die Wahl steht nur in der Startdatei, nicht in settings.cfg.
	_settings.call("save_to", TEMP_SETTINGS)
	_settings.call("set_graphics_driver", 0)
	_settings.call("load_from", TEMP_SETTINGS)
	_check(int(_settings.get("graphics_driver")) == 0, "settings.cfg enthält den Unterbau nicht.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_START))
	_settings.call("reset_to_defaults")


func _test_video_settings() -> void:
	_settings.call("reset_to_defaults")
	_near(float(_settings.get("fov")), 80.0, "Standard-Sichtfeld 80 Grad.")
	_check(int(_settings.get("window_mode")) == 0, "Standard: Fenster.")
	_check(bool(_settings.get("vsync")), "Standard: VSync an.")
	_check(int(_settings.get("fps_limit")) == 0, "Standard: keine Bildraten-Grenze.")
	_near(float(_settings.get("render_scale")), 1.0, "Standard: volle Auflösung.")
	_check(int(_settings.get("msaa")) == 0, "Standard: Kantenglättung aus.")
	_check(not bool(_settings.get("show_fps")), "Standard: FPS-Anzeige aus.")
	_settings.call("set_fov", 500.0)
	_near(float(_settings.get("fov")), 110.0, "Sichtfeld höchstens 110 Grad.")
	_settings.call("set_fov", 1.0)
	_near(float(_settings.get("fov")), 60.0, "Sichtfeld mindestens 60 Grad.")
	_settings.call("set_window_mode", 99)
	_check(int(_settings.get("window_mode")) == 2, "Fenstermodus wird auf den letzten Eintrag begrenzt.")
	_settings.call("set_fps_limit", 150)
	_check(int(_settings.get("fps_limit")) == 144, "Bildraten-Grenze rastet auf den nächsten erlaubten Wert (144).")
	_settings.call("set_fps_limit", -5)
	_check(int(_settings.get("fps_limit")) == 0, "Negative Bildraten-Grenze heißt keine Grenze.")
	_settings.call("set_render_scale", 0.1)
	_near(float(_settings.get("render_scale")), 0.5, "Auflösung mindestens 50 Prozent.")
	_settings.call("set_msaa", 7)
	_check(int(_settings.get("msaa")) == 3, "Kantenglättung höchstens 8-fach.")
	_test_graphics_driver()
	# Alle Werte einmal durch die Datei.
	_settings.call("set_fov", 95.0)
	_settings.call("set_window_mode", 1)
	_settings.call("set_vsync", false)
	_settings.call("set_fps_limit", 120)
	_settings.call("set_render_scale", 0.75)
	_settings.call("set_msaa", 2)
	_settings.call("set_show_fps", true)
	_check(bool(_settings.call("save_to", TEMP_SETTINGS)), "save_to schreibt die Grafikwerte.")
	_settings.call("reset_to_defaults")
	_check(bool(_settings.call("load_from", TEMP_SETTINGS)), "load_from liest die Grafikwerte.")
	_near(float(_settings.get("fov")), 95.0, "Sichtfeld kommt aus der Datei zurück.")
	_check(int(_settings.get("window_mode")) == 1, "Fenstermodus kommt aus der Datei zurück.")
	_check(not bool(_settings.get("vsync")), "VSync kommt aus der Datei zurück.")
	_check(int(_settings.get("fps_limit")) == 120, "Bildraten-Grenze kommt aus der Datei zurück.")
	_near(float(_settings.get("render_scale")), 0.75, "Auflösung kommt aus der Datei zurück.")
	_check(int(_settings.get("msaa")) == 2, "Kantenglättung kommt aus der Datei zurück.")
	_check(bool(_settings.get("show_fps")), "FPS-Anzeige kommt aus der Datei zurück.")
	# Unsinn in der Datei: falscher Typ wird übergangen, zu große Zahl begrenzt.
	var config: ConfigFile = ConfigFile.new()
	config.set_value("grafik", "sichtfeld", "breit")
	config.set_value("grafik", "kantenglaettung", 40)
	config.set_value("grafik", "vsync", "ja")
	config.save(TEMP_SETTINGS)
	_settings.call("reset_to_defaults")
	_settings.call("load_from", TEMP_SETTINGS)
	_near(float(_settings.get("fov")), 80.0, "Text statt Zahl ändert das Sichtfeld nicht.")
	_check(int(_settings.get("msaa")) == 3, "Zu große Kantenglättung aus der Datei wird begrenzt.")
	_check(bool(_settings.get("vsync")), "Text statt Wahrheitswert ändert VSync nicht.")
	# Headless verändert apply_video nichts und stürzt nicht ab.
	var max_fps_before: int = Engine.max_fps
	_settings.call("set_fps_limit", 60)
	_settings.call("apply_video", root)
	_check(Engine.max_fps == max_fps_before, "Headless lässt apply_video die Engine in Ruhe.")
	_settings.call("reset_to_defaults")


## Lautstärke: Standard, Begrenzung, Datei (Abschnitt ton) und Wirkung auf den Master-Bus.
## Ausführlicher in tests/test_audio.gd.
func _test_volume_setting() -> void:
	_settings.call("reset_to_defaults")
	_near(float(_settings.get("master_volume")), 0.8, "Standard-Lautstärke 0,8.")
	_settings.call("set_master_volume", 3.0)
	_near(float(_settings.get("master_volume")), 1.0, "Lautstärke höchstens 1,0.")
	_settings.call("set_master_volume", -0.4)
	_near(float(_settings.get("master_volume")), 0.0, "Lautstärke mindestens 0,0.")
	_settings.call("set_value", "master_volume", 0.62)
	_near(float(_settings.call("get_value", "master_volume")), 0.6, "Lautstärke über den Namen, im Raster von 0,05.")
	_check(bool(_settings.call("save_to", TEMP_SETTINGS)), "save_to schreibt die Lautstärke.")
	var written: ConfigFile = ConfigFile.new()
	written.load(TEMP_SETTINGS)
	_near(float(written.get_value("ton", "lautstaerke", -1.0)), 0.6, "Die Lautstärke steht im Abschnitt ton.")
	_settings.call("reset_to_defaults")
	_settings.call("load_from", TEMP_SETTINGS)
	_near(float(_settings.get("master_volume")), 0.6, "Lautstärke kommt aus der Datei zurück.")
	# apply_audio wirkt (anders als apply_video) auch headless.
	_settings.call("apply_audio")
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.6)) < 0.01, "apply_audio setzt den Master-Bus.")
	_settings.call("set_master_volume", 0.0)
	_settings.call("apply_audio")
	_check(AudioServer.is_bus_mute(0), "Lautstärke 0 schaltet den Master-Bus stumm.")
	_settings.call("reset_to_defaults")
	_settings.call("apply_audio")
	_check(not AudioServer.is_bus_mute(0), "Mit dem Standard ist der Master-Bus wieder zu hören.")
	# Musik und Geräusche: eigene Werte (Standard 0,7 und 1,0), eigene Busse, Abschnitt ton.
	_near(float(_settings.get("music_volume")), 0.7, "Standard-Lautstärke der Musik 0,7.")
	_near(float(_settings.get("sfx_volume")), 1.0, "Standard-Lautstärke der Geräusche 1,0.")
	_settings.call("set_music_volume", 2.0)
	_near(float(_settings.get("music_volume")), 1.0, "Musik höchstens 1,0.")
	_settings.call("set_sfx_volume", -1.0)
	_near(float(_settings.get("sfx_volume")), 0.0, "Geräusche mindestens 0,0.")
	_settings.call("set_value", "music_volume", 0.42)
	_settings.call("set_value", "sfx_volume", 0.88)
	_near(float(_settings.call("get_value", "music_volume")), 0.4, "Musik über den Namen, im Raster von 0,05.")
	_near(float(_settings.call("get_value", "sfx_volume")), 0.9, "Geräusche über den Namen, im Raster von 0,05.")
	_check(bool(_settings.call("save_to", TEMP_SETTINGS)), "save_to schreibt Musik und Geräusche.")
	var audio_file: ConfigFile = ConfigFile.new()
	audio_file.load(TEMP_SETTINGS)
	_near(float(audio_file.get_value("ton", "musik", -1.0)), 0.4, "Die Musik steht im Abschnitt ton unter musik.")
	_near(float(audio_file.get_value("ton", "geraeusche", -1.0)), 0.9, "Die Geräusche stehen im Abschnitt ton unter geraeusche.")
	_settings.call("reset_to_defaults")
	_settings.call("load_from", TEMP_SETTINGS)
	_near(float(_settings.get("music_volume")), 0.4, "Musik kommt aus der Datei zurück.")
	_near(float(_settings.get("sfx_volume")), 0.9, "Geräusche kommen aus der Datei zurück.")
	_settings.call("apply_audio")
	var music_bus: int = AudioServer.get_bus_index("Music")
	var sfx_bus: int = AudioServer.get_bus_index("Sfx")
	_check(music_bus != -1 and sfx_bus != -1, "apply_audio legt die Busse Music und Sfx an.")
	if music_bus != -1 and sfx_bus != -1:
		_check(absf(AudioServer.get_bus_volume_db(music_bus) - linear_to_db(0.4)) < 0.01, "apply_audio setzt den Bus Music.")
		_check(absf(AudioServer.get_bus_volume_db(sfx_bus) - linear_to_db(0.9)) < 0.01, "apply_audio setzt den Bus Sfx.")
		_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.8)) < 0.01, "Der Master-Bus behält die Gesamtlautstärke.")
		_settings.call("set_music_volume", 0.0)
		_settings.call("apply_audio")
		_check(AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(sfx_bus) and not AudioServer.is_bus_mute(0), "Musik 0 schaltet nur den Bus Music stumm.")
	# Text statt Zahl in der Datei ändert nichts.
	var broken: ConfigFile = ConfigFile.new()
	broken.set_value("ton", "musik", "laut")
	broken.set_value("ton", "geraeusche", true)
	broken.save(TEMP_SETTINGS)
	_settings.call("set_music_volume", 0.55)
	_settings.call("set_sfx_volume", 0.65)
	_settings.call("load_from", TEMP_SETTINGS)
	_near(float(_settings.get("music_volume")), 0.55, "Text statt Zahl ändert die Musik nicht.")
	_near(float(_settings.get("sfx_volume")), 0.65, "Ein Wahrheitswert statt Zahl ändert die Geräusche nicht.")
	_settings.call("reset_to_defaults")
	_settings.call("apply_audio")
	_near(float(_settings.get("music_volume")), 0.7, "reset_to_defaults stellt die Musik zurück.")
	_near(float(_settings.get("sfx_volume")), 1.0, "reset_to_defaults stellt die Geräusche zurück.")
	if music_bus != -1:
		_check(not AudioServer.is_bus_mute(music_bus), "Mit dem Standard ist die Musik wieder zu hören.")


func _test_material_keys() -> void:
	var plain: StandardMaterial3D = StandardMaterial3D.new()
	_check(str(_keep.call("material_key", plain)) == "", "Das Standardmaterial hat den leeren Schlüssel.")
	var red: StandardMaterial3D = StandardMaterial3D.new()
	red.albedo_color = Color.RED
	red.metallic = 0.7
	_check(str(_keep.call("material_key", red)) == "", "Farbe und Zahlenwerte gehören nicht zum Schlüssel.")
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var glow_key: String = str(_keep.call("material_key", glow))
	_check(glow_key.contains("shading_mode=0") and glow_key.contains("blend_mode=1") and glow_key.contains("transparency=1"),
		"Schalter stehen im Schlüssel, war: " + glow_key)
	var rebuilt: StandardMaterial3D = _keep.call("material_from_key", glow_key) as StandardMaterial3D
	_check(str(_keep.call("material_key", rebuilt)) == glow_key, "Aus dem Schlüssel entsteht wieder dieselbe Art.")
	var textured: StandardMaterial3D = StandardMaterial3D.new()
	textured.albedo_texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	var textured_key: String = str(_keep.call("material_key", textured))
	_check(textured_key.contains("T:albedo_texture"), "Eine gesetzte Textur steht im Schlüssel.")
	var textured_again: StandardMaterial3D = _keep.call("material_from_key", textured_key) as StandardMaterial3D
	_check(textured_again.albedo_texture != null, "Aus dem Schlüssel entsteht ein Material mit Textur.")


func _test_tracking() -> void:
	_keep.call("reset")
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = material
	# Game verbindet node_added mit track_node: Ein neuer Knoten im Baum reicht.
	root.add_child(mesh)
	var entries: Array = _keep.call("material_entries")
	_check(entries.size() == 1, "Ein neues Material im Baum wird gemerkt, waren %d." % entries.size())
	var twin: MeshInstance3D = MeshInstance3D.new()
	twin.mesh = BoxMesh.new()
	var twin_material: StandardMaterial3D = StandardMaterial3D.new()
	twin_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	twin_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	twin_material.albedo_color = Color.GREEN
	twin.material_override = twin_material
	root.add_child(twin)
	_check((_keep.call("material_entries") as Array).size() == 1, "Dieselbe Art in anderer Farbe zählt nicht doppelt.")
	if entries.size() == 1:
		var held: Material = (entries[0] as Dictionary)["material"] as Material
		_check(held != material and held != null, "Gehalten wird eine Kopie, nicht das Material des Besitzers.")
		_check(int((entries[0] as Dictionary)["usage"]) == 1, "Ein Mesh zählt als Verwendung 1.")
	# Partikel mit derselben Art: dieselbe Art, zusätzliche Verwendung.
	var particles: CPUParticles3D = CPUParticles3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.material = twin_material
	particles.mesh = quad
	root.add_child(particles)
	entries = _keep.call("material_entries")
	_check(entries.size() == 1 and int((entries[0] as Dictionary)["usage"]) == 3, "Partikel ergänzen die Verwendung (1 + 2 = 3).")
	# Material am Mesh statt am Knoten.
	var lit: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.material = StandardMaterial3D.new()
	lit.mesh = box
	root.add_child(lit)
	_check((_keep.call("material_entries") as Array).size() == 2, "Auch das Material eines Meshs wird gemerkt.")
	var label: Label3D = Label3D.new()
	label.font_size = 96
	root.add_child(label)
	var second_label: Label3D = Label3D.new()
	second_label.font_size = 96
	root.add_child(second_label)
	_check((_keep.call("label_entries") as Array).size() == 1, "Gleiche 3D-Schrift zählt einmal.")
	# Die Kopie überlebt ihren Besitzer.
	mesh.free()
	twin.free()
	particles.free()
	lit.free()
	label.free()
	second_label.free()
	_check((_keep.call("material_entries") as Array).size() == 2, "Die Arten bleiben nach dem Löschen der Knoten bekannt.")
	_check(int(_keep.call("known_count")) == 3, "Zwei Material-Arten und eine Schrift sind bekannt.")


func _test_list_file() -> void:
	_check(bool(_keep.call("save_list", TEMP_LIST)), "save_list schreibt die Liste.")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMP_LIST))
	_check(typeof(parsed) == TYPE_DICTIONARY, "Die Liste ist gültiges JSON.")
	if typeof(parsed) == TYPE_DICTIONARY:
		_check(((parsed as Dictionary).get("materials", []) as Array).size() == 2, "Zwei Material-Arten stehen in der Liste.")
		_check(((parsed as Dictionary).get("labels", []) as Array).size() == 1, "Eine Schrift steht in der Liste.")
	_keep.call("reset")
	_check(int(_keep.call("known_count")) == 0, "reset vergisst alles.")
	_keep.call("_load_list", TEMP_LIST)
	_check(int(_keep.call("known_count")) == 3, "Die geladene Liste stellt alle Arten wieder her.")
	_keep.call("_load_list", TEMP_LIST)
	_check(int(_keep.call("known_count")) == 3, "Doppeltes Laden verdoppelt nichts.")
	_keep.call("reset")
	# Die mitgelieferte Liste muss lesbar sein und die Arten des Spiels enthalten.
	_check(FileAccess.file_exists("res://data/shader_warmup.json"), "Die mitgelieferte Liste res://data/shader_warmup.json fehlt.")
	_keep.call("_load_list", "res://data/shader_warmup.json")
	_check(int(_keep.call("known_count")) >= 10, "Die mitgelieferte Liste enthält mindestens 10 Arten, waren %d." % int(_keep.call("known_count")))
	_keep.call("reset")


func _test_pause_slider() -> void:
	var game: Node = root.get_node("Game")
	var menu: CanvasLayer = (load("res://scripts/ui/pause_menu.gd") as GDScript).new() as CanvasLayer
	root.add_child(menu)
	await process_frame
	var slider: HSlider = menu.get("sensitivity_slider") as HSlider
	var value_label: Label = menu.get("sensitivity_value_label") as Label
	_check(slider != null and value_label != null, "Das Pausemenü hat Regler und Wertanzeige.")
	if slider != null and value_label != null:
		_near(float(slider.value), 100.0, "Der Regler steht anfangs auf 100.")
		_check(value_label.text == "100 %", "Die Anzeige zeigt anfangs 100 Prozent, war: " + value_label.text)
		_near(float(slider.min_value), 10.0, "Kleinster Wert 10 Prozent.")
		_near(float(slider.max_value), 300.0, "Größter Wert 300 Prozent.")
		slider.value = 150.0
		_near(_sensitivity(), 1.5, "Der Regler ändert die Empfindlichkeit sofort.")
		_check(value_label.text == "150 %", "Die Anzeige folgt dem Regler, war: " + value_label.text)
		slider.value = 1000.0
		_near(_sensitivity(), 3.0, "Der Regler geht nicht über 300 Prozent.")
		# Beim Öffnen übernimmt der Regler den aktuellen Wert.
		_settings.call("set_mouse_sensitivity", 0.75)
		game.call("start_run", 1)
		menu.call("open")
		_near(float(slider.value), 75.0, "Beim Öffnen zeigt der Regler den aktuellen Wert.")
		_check(value_label.text == "75 %", "Beim Öffnen zeigt die Anzeige den aktuellen Wert, war: " + value_label.text)
		menu.call("resume")
		_check(not bool(menu.call("is_open")), "Das Menü schließt sich wieder.")
	_settings.call("set_mouse_sensitivity", 1.0)
	paused = false
	menu.queue_free()
	await process_frame


func _test_settings_menu() -> void:
	_settings.call("reset_to_defaults")
	var game: Node = root.get_node("Game")
	var menu: CanvasLayer = (load("res://scripts/ui/pause_menu.gd") as GDScript).new() as CanvasLayer
	root.add_child(menu)
	await process_frame
	var settings_menu: Control = menu.get("settings_menu") as Control
	_check(settings_menu != null and menu.get("settings_button") != null, "Das Pausemenü hat Knopf und Ansicht für die Einstellungen.")
	if settings_menu == null:
		menu.queue_free()
		return
	game.call("start_run", 1)
	menu.call("open")
	_check(not bool(menu.call("is_settings_open")), "Das Menü öffnet in der Hauptansicht.")
	(menu.get("settings_button") as Button).pressed.emit()
	_check(bool(menu.call("is_settings_open")), "Der Knopf Einstellungen zeigt die Einstellungen.")
	var sliders: Dictionary = settings_menu.get("sliders")
	var cyclers: Dictionary = settings_menu.get("cyclers")
	var labels: Dictionary = settings_menu.get("value_labels")
	_check(sliders.has("master_volume") and sliders.has("mouse_sensitivity") and sliders.has("fov") and sliders.has("render_scale"),
		"Vier Regler: Lautstärke, Maus, Sichtfeld, Auflösung.")
	_check(sliders.has("music_volume") and sliders.has("sfx_volume") and sliders.size() == 6, "Dazu zwei Regler für Musik und Geräusche, zusammen sechs.")
	if sliders.has("music_volume") and sliders.has("sfx_volume") and labels.has("music_volume") and labels.has("sfx_volume"):
		var music_slider: HSlider = sliders["music_volume"] as HSlider
		var sfx_slider: HSlider = sliders["sfx_volume"] as HSlider
		_near(float(music_slider.value), 70.0, "Der Regler Musik steht anfangs auf 70.")
		_near(float(sfx_slider.value), 100.0, "Der Regler Geräusche steht anfangs auf 100.")
		music_slider.value = 20.0
		sfx_slider.value = 60.0
		_near(float(_settings.get("music_volume")), 0.2, "Der Regler Musik ändert die Einstellung.")
		_near(float(_settings.get("sfx_volume")), 0.6, "Der Regler Geräusche ändert die Einstellung.")
		_check((labels["music_volume"] as Label).text == "20 %" and (labels["sfx_volume"] as Label).text == "60 %", "Die Anzeigen zeigen Musik und Geräusche.")
		_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.2)) < 0.01, "Der Regler Musik wirkt sofort auf den Bus Music.")
		_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Sfx")) - linear_to_db(0.6)) < 0.01, "Der Regler Geräusche wirkt sofort auf den Bus Sfx.")
	if sliders.has("master_volume") and labels.has("master_volume"):
		var volume_slider: HSlider = sliders["master_volume"] as HSlider
		_near(float(volume_slider.value), 80.0, "Der Regler Lautstärke steht anfangs auf 80.")
		volume_slider.value = 35.0
		_near(float(_settings.get("master_volume")), 0.35, "Der Regler Lautstärke ändert die Einstellung.")
		_check((labels["master_volume"] as Label).text == "35 %", "Die Anzeige zeigt die Lautstärke, war: " + (labels["master_volume"] as Label).text)
		_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.35)) < 0.01, "Der Regler Lautstärke wirkt sofort auf den Master-Bus.")
	_check(cyclers.has("window_mode") and cyclers.has("vsync") and cyclers.has("fps_limit") and cyclers.has("msaa") and cyclers.has("show_fps"),
		"Fünf Umschalter: Fenster, VSync, Grenze, Kantenglättung, FPS-Anzeige.")
	_check(cyclers.has("graphics_driver"), "Dazu der Umschalter Grafik-Unterbau.")
	if cyclers.has("graphics_driver"):
		var driver_button: Button = cyclers["graphics_driver"] as Button
		var names: Array = ["Sicher", "Schnell"]
		var active_driver: int = int(_settings.call("active_driver"))
		settings_menu.call("set_setting", "graphics_driver", active_driver)
		settings_menu.call("refresh")
		_check(driver_button.text == str(names[active_driver]), "Der Knopf nennt den laufenden Unterbau ohne Zusatz, war: " + driver_button.text)
		driver_button.pressed.emit()
		_check(int(_settings.get("graphics_driver")) == 1 - active_driver, "Ein Klick wählt den anderen Unterbau.")
		_check(driver_button.text == str(names[1 - active_driver]) + " (Neustart)", "Der Knopf sagt, dass die Wahl erst nach einem Neustart gilt, war: " + driver_button.text)
		driver_button.pressed.emit()
		_check(driver_button.text == str(names[active_driver]), "Zurück auf den laufenden Unterbau: kein Zusatz mehr.")
		var back_button: Button = settings_menu.get("back_button") as Button
		var footer_end: float = back_button.offset_top + back_button.custom_minimum_size.y
		_check(footer_end > 0.0 and footer_end <= 690.0, "Zwölf Zeilen und die Fußzeile passen in die 690 Punkte hohe Ansicht, Ende bei: %.0f" % footer_end)
	if sliders.has("fov") and cyclers.has("fps_limit") and cyclers.has("show_fps") and cyclers.has("vsync"):
		(sliders["fov"] as HSlider).value = 100.0
		_near(float(_settings.get("fov")), 100.0, "Der Regler Sichtfeld ändert die Einstellung.")
		_check((labels["fov"] as Label).text == "100°", "Die Anzeige zeigt das Sichtfeld, war: " + (labels["fov"] as Label).text)
		(sliders["render_scale"] as HSlider).value = 70.0
		_near(float(_settings.get("render_scale")), 0.7, "Der Regler Auflösung rechnet Prozent in den Faktor um.")
		var limit_button: Button = cyclers["fps_limit"] as Button
		_check(limit_button.text == "Keine", "Die Bildraten-Grenze zeigt anfangs Keine, war: " + limit_button.text)
		limit_button.pressed.emit()
		_check(int(_settings.get("fps_limit")) == 30 and limit_button.text == "30 FPS", "Ein Klick schaltet zur nächsten Grenze.")
		for _i: int in 6:
			limit_button.pressed.emit()
		_check(int(_settings.get("fps_limit")) == 0 and limit_button.text == "Keine", "Nach dem letzten Wert kommt wieder der erste.")
		var fps_button: Button = cyclers["show_fps"] as Button
		fps_button.pressed.emit()
		_check(bool(_settings.get("show_fps")) and fps_button.text == "An", "Die FPS-Anzeige lässt sich einschalten.")
		var vsync_button: Button = cyclers["vsync"] as Button
		vsync_button.pressed.emit()
		_check(not bool(_settings.get("vsync")) and vsync_button.text == "Aus", "VSync lässt sich ausschalten.")
		(settings_menu.get("reset_button") as Button).pressed.emit()
		_near(float(_settings.get("fov")), 80.0, "Standard setzt das Sichtfeld zurück.")
		_check(bool(_settings.get("vsync")) and not bool(_settings.get("show_fps")), "Standard setzt die Umschalter zurück.")
		_near(float((sliders["fov"] as HSlider).value), 80.0, "Standard stellt auch die Regler zurück.")
		_near(float(_settings.get("master_volume")), 0.8, "Standard setzt die Lautstärke zurück.")
		_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.8)) < 0.01, "Standard wirkt auch auf den Master-Bus.")
		_near(float(_settings.get("music_volume")), 0.7, "Standard setzt die Musik zurück.")
		_near(float(_settings.get("sfx_volume")), 1.0, "Standard setzt die Geräusche zurück.")
		if sliders.has("music_volume") and sliders.has("sfx_volume"):
			_near(float((sliders["music_volume"] as HSlider).value), 70.0, "Standard stellt den Regler Musik zurück.")
			_near(float((sliders["sfx_volume"] as HSlider).value), 100.0, "Standard stellt den Regler Geräusche zurück.")
			_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.7)) < 0.01, "Standard wirkt auch auf den Bus Music.")
		_check(vsync_button.text == "An" and fps_button.text == "Aus", "Standard stellt auch die Knopftexte zurück.")
	# Esc führt aus den Einstellungen zurück, erst das zweite Esc setzt das Spiel fort.
	var escape: InputEventAction = InputEventAction.new()
	escape.action = "pause"
	escape.pressed = true
	menu.call("_unhandled_input", escape)
	_check(bool(menu.call("is_open")) and not bool(menu.call("is_settings_open")), "Esc führt aus den Einstellungen zur Hauptansicht.")
	_check(paused, "Nach dem ersten Esc ist das Spiel noch pausiert.")
	menu.call("_unhandled_input", escape)
	_check(not bool(menu.call("is_open")) and not paused, "Das zweite Esc setzt das Spiel fort.")
	# Nach Weiter öffnet das Menü wieder in der Hauptansicht.
	menu.call("open")
	menu.call("open_settings")
	menu.call("resume")
	menu.call("open")
	_check(not bool(menu.call("is_settings_open")), "Das Menü öffnet nach dem Schließen wieder in der Hauptansicht.")
	menu.call("resume")
	_settings.call("reset_to_defaults")
	paused = false
	menu.queue_free()
	await process_frame


func _test_fps_label() -> void:
	_settings.call("reset_to_defaults")
	var hud: CanvasLayer = (load("res://scripts/ui/hud.gd") as GDScript).new() as CanvasLayer
	root.add_child(hud)
	await process_frame
	await process_frame
	var label: Label = hud.get("fps_label") as Label
	_check(label != null, "Das HUD hat eine FPS-Anzeige.")
	if label != null:
		_check(not label.visible, "Die FPS-Anzeige ist anfangs aus.")
		_settings.call("set_show_fps", true)
		await process_frame
		await process_frame
		_check(label.visible, "Mit der Einstellung erscheint die FPS-Anzeige.")
		_check(label.text.ends_with(" FPS"), "Die Anzeige zeigt eine Zahl mit FPS, war: " + label.text)
		# Auch bei pausiertem Baum reagiert sie (Umschalten im Pausemenü).
		paused = true
		_settings.call("set_show_fps", false)
		await process_frame
		await process_frame
		_check(not label.visible, "Die FPS-Anzeige verschwindet auch in der Pause sofort.")
		paused = false
	_settings.call("reset_to_defaults")
	hud.queue_free()
	await process_frame


func _near(value: float, expected: float, message: String) -> void:
	_check(absf(value - expected) < 0.0001, "%s (erwartet %s, war %s)" % [message, expected, value])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)
