extends CanvasLayer
## Modul: Oberfläche (scripts/ui).
## Pausemenü (Abschnitt 11): Weiter, Einstellungen, Neustart, Beenden.
##
## Die Aktion "pause" (Esc) schaltet im Spiel zwischen PLAYING und PAUSED um. In der Kistenwahl
## und im Game Over wirkt sie nicht (Game.set_paused lehnt das ab). process_mode ALWAYS, weil
## das Menü bei pausiertem Baum bedient wird.
## Knöpfe: Weiter -> resume(), Einstellungen -> open_settings(), Neustart -> Game.restart_run(),
## Beenden -> Game.quit_game().
## Die Einstellungen (settings_menu.gd) sind eine zweite Ansicht im selben Menü. Esc führt von
## dort zurück zur Hauptansicht, ein zweites Esc setzt das Spiel fort.

const UiStyle := preload("res://scripts/ui/hud.gd")
const Settings := preload("res://scripts/game/settings.gd")
const SettingsMenu := preload("res://scripts/ui/settings_menu.gd")

const LAYER: int = 20

# --- Optik-Zahlen ---
const STAGE_SIZE: Vector2 = Vector2(760.0, 690.0)
const BUTTON_SIZE: Vector2 = Vector2(340.0, 66.0)
const BUTTON_STEP: float = 80.0
const BUTTON_START_Y: float = 204.0
const CONTROLS_TEXT: String = "WASD Laufen · Leertaste Springen · Umschalt Sprinten · Maus Zielen und Schießen\nR Nachladen · E Tür öffnen · Tab Rucksack · Q Ausweichen (mit Notausgang) · Esc Pause"

## Überschrift des Menüs.
var headline_label: Label
## Knopf "Weiter" (setzt das Spiel fort).
var resume_button: Button
## Knopf "Einstellungen" (öffnet die Ansicht settings_menu).
var settings_button: Button
## Knopf "Neustart" (Game.restart_run).
var restart_button: Button
## Knopf "Beenden" (Game.quit_game).
var quit_button: Button
## Ansicht mit allen Einstellungen (settings_menu.gd).
var settings_menu: SettingsMenu
## Regler für die Mausempfindlichkeit in den Einstellungen (Wert in Prozent, 100 = Standard).
var sensitivity_slider: HSlider
## Anzeige des Reglerwerts, z. B. "100 %".
var sensitivity_value_label: Label

var _headline: PanelContainer
var _main_view: Control
var _buttons: Array[Button] = []


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	Events.run_started.connect(_sync)
	Events.game_over.connect(_on_game_over)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if Game.state == Game.State.PLAYING:
		get_viewport().set_input_as_handled()
		open()
	elif Game.state == Game.State.PAUSED:
		get_viewport().set_input_as_handled()
		if is_settings_open():
			close_settings()
		else:
			resume()


## Pausiert das Spiel und zeigt das Menü. Wirkt nur im State PLAYING.
func open() -> void:
	Game.set_paused(true)
	_sync()


## Schließt das Menü und setzt das Spiel fort. Wirkt nur im State PAUSED.
func resume() -> void:
	Game.set_paused(false)
	_sync()


## Ist das Pausemenü gerade offen?
func is_open() -> bool:
	return visible


## Zeigt die Einstellungen anstelle der Hauptansicht. Wirkt nur bei offenem Menü.
func open_settings() -> void:
	if not visible:
		return
	_release_focus()
	_main_view.visible = false
	settings_menu.open()


## Zurück von den Einstellungen zur Hauptansicht (speichert die Einstellungen).
func close_settings() -> void:
	settings_menu.close()


## Sind gerade die Einstellungen zu sehen?
func is_settings_open() -> bool:
	return visible and settings_menu.visible


# --- Aufbau ---------------------------------------------------------------------------

func _build() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim: ColorRect = UiStyle.make_dim(Color(UiStyle.COL_INK, 0.88))
	dim.name = "Dim"
	root.add_child(dim)
	var sunburst: UiStyle.Sunburst = UiStyle.Sunburst.new()
	sunburst.name = "Sunburst"
	sunburst.ray_color = Color(UiStyle.COL_CYAN, 0.07)
	sunburst.speed = 0.06
	sunburst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sunburst)
	var stage: Control = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(stage, Vector2(0.5, 0.5), -STAGE_SIZE * 0.5, STAGE_SIZE)
	root.add_child(stage)
	_main_view = Control.new()
	_main_view.name = "MainView"
	_main_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_main_view)
	_headline = UiStyle.make_headline("SENDEPAUSE", 62, UiStyle.COL_PURPLE, UiStyle.COL_YELLOW, UiStyle.COL_CYAN)
	_headline.name = "Headline"
	_headline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_headline.pivot_offset_ratio = Vector2(0.5, 0.5)
	_headline.rotation_degrees = -3.0
	UiStyle.anchor_box(_headline, Vector2(0.5, 0.0), Vector2(0.0, 30.0), Vector2.ZERO)
	_main_view.add_child(_headline)
	headline_label = _headline.get_node("Label") as Label
	var subline: Label = UiStyle.make_label("Bleiben Sie dran: Gleich wird weitergestorben.", 22, UiStyle.COL_WHITE, true)
	subline.name = "Subline"
	subline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(subline, Vector2.ZERO, Vector2(0.0, 148.0), Vector2(STAGE_SIZE.x, 32.0))
	_main_view.add_child(subline)
	resume_button = _add_button("WEITER", UiStyle.COL_GREEN, 0)
	resume_button.name = "Resume"
	resume_button.pressed.connect(resume)
	settings_button = _add_button("EINSTELLUNGEN", UiStyle.COL_CYAN, 1)
	settings_button.name = "Settings"
	settings_button.pressed.connect(open_settings)
	restart_button = _add_button("NEUSTART", UiStyle.COL_YELLOW, 2)
	restart_button.name = "Restart"
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button = _add_button("BEENDEN", UiStyle.COL_ORANGE, 3)
	quit_button.name = "Quit"
	quit_button.pressed.connect(_on_quit_pressed)
	# Pfeiltasten wandern im Kreis durch die Knöpfe.
	for i: int in _buttons.size():
		var above: Button = _buttons[(i + _buttons.size() - 1) % _buttons.size()]
		var below: Button = _buttons[(i + 1) % _buttons.size()]
		_buttons[i].focus_neighbor_top = _buttons[i].get_path_to(above)
		_buttons[i].focus_neighbor_bottom = _buttons[i].get_path_to(below)
		_buttons[i].focus_previous = _buttons[i].get_path_to(above)
		_buttons[i].focus_next = _buttons[i].get_path_to(below)
	var controls: Label = UiStyle.make_label(CONTROLS_TEXT, 15, UiStyle.COL_CYAN)
	controls.name = "Controls"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(controls, Vector2(0.5, 0.0), Vector2(-500.0, 560.0), Vector2(1000.0, 56.0))
	_main_view.add_child(controls)
	settings_menu = SettingsMenu.new()
	settings_menu.name = "SettingsMenu"
	settings_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_menu.visible = false
	stage.add_child(settings_menu)
	settings_menu.closed.connect(_on_settings_closed)
	sensitivity_slider = settings_menu.sliders["mouse_sensitivity"] as HSlider
	sensitivity_value_label = settings_menu.value_labels["mouse_sensitivity"] as Label


func _add_button(text: String, accent: Color, index: int) -> Button:
	var button: Button = UiStyle.make_button(text, accent, 30)
	button.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(button, Vector2(0.5, 0.0),
			Vector2(-BUTTON_SIZE.x * 0.5, BUTTON_START_Y + float(index) * BUTTON_STEP), BUTTON_SIZE)
	_main_view.add_child(button)
	_buttons.append(button)
	return button


## Sichtbar genau dann, wenn das Spiel im State PAUSED ist. Das Menü öffnet immer in der
## Hauptansicht.
func _sync() -> void:
	var was_open: bool = visible
	visible = Game.state == Game.State.PAUSED
	if visible and not was_open:
		_show_main_view()
		settings_menu.refresh()
		_animate_open()
	elif not visible:
		if was_open:
			_show_main_view()
			Settings.save()
		_release_focus()


## Hauptansicht zeigen, Einstellungen verstecken (ohne Signal).
func _show_main_view() -> void:
	settings_menu.visible = false
	_main_view.visible = true


func _on_settings_closed() -> void:
	_main_view.visible = true
	if visible and is_inside_tree():
		settings_button.grab_focus()


func _animate_open() -> void:
	if not is_inside_tree():
		return
	resume_button.grab_focus()
	UiStyle.pop(_headline, 0.4, 0.28)
	for i: int in _buttons.size():
		UiStyle.pop(_buttons[i], 0.7, 0.18 + 0.05 * float(i))


## Nimmt den Tastatur-Fokus von allen Bedienelementen: Im laufenden Spiel darf die Leertaste
## (Springen) keinen unsichtbaren Knopf auslösen.
func _release_focus() -> void:
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()


func _on_restart_pressed() -> void:
	visible = false
	_show_main_view()
	_release_focus()
	Game.restart_run()


func _on_quit_pressed() -> void:
	Game.quit_game()


func _on_game_over(_stats: Dictionary) -> void:
	_sync()
