extends Control
## Modul: Oberfläche (scripts/ui).
## Einstellungen (Ansicht im Pausemenü): Lautstärke, Mausempfindlichkeit, Sichtfeld, Fenstermodus,
## VSync, Bildraten-Grenze, Auflösungs-Skalierung, Kantenglättung, FPS-Anzeige.
##
## Jede Zeile ist entweder ein Regler mit Wertanzeige oder ein Knopf, der beim Klick zum nächsten
## Wert weiterschaltet. Jede Änderung wirkt sofort (Settings.apply_video, Settings.apply_audio)
## und wird beim Loslassen des Reglers, beim Klick auf einen Knopf und beim Schließen gespeichert
## (Settings.save).
## Das Pausemenü baut diese Ansicht, zeigt sie über open() und hört auf closed.

const UiStyle := preload("res://scripts/ui/hud.gd")
const Settings := preload("res://scripts/game/settings.gd")

signal closed

# --- Optik-Zahlen (Koordinaten relativ zur Mitte der Bühne oben) ---
const ROW_START_Y: float = 140.0
const ROW_STEP: float = 46.0
const CAPTION_WIDTH: float = 330.0
const CONTROL_WIDTH: float = 250.0
const CONTROL_HEIGHT: float = 38.0
const FOOTER_BUTTON_SIZE: Vector2 = Vector2(250.0, 60.0)

## Zeilen in der Reihenfolge der Anzeige. kind "slider": min, max, step und scale (Anzeige =
## Wert * scale) und suffix. kind "cycle": values und names (gleich lang).
const ROWS: Array[Dictionary] = [
	{"id": "master_volume", "caption": "LAUTSTÄRKE", "kind": "slider",
		"min": 0.0, "max": 100.0, "step": 5.0, "scale": 100.0, "suffix": " %",
		"hint": "Lautstärke aller Geräusche. 0 % ist stumm, 80 % ist der Standard."},
	{"id": "mouse_sensitivity", "caption": "MAUS-EMPFINDLICHKEIT", "kind": "slider",
		"min": 10.0, "max": 300.0, "step": 5.0, "scale": 100.0, "suffix": " %",
		"hint": "Wie schnell sich der Blick mit der Maus dreht. 100 % ist der Standard."},
	{"id": "fov", "caption": "SICHTFELD", "kind": "slider",
		"min": 60.0, "max": 110.0, "step": 1.0, "scale": 1.0, "suffix": "°",
		"hint": "Wie viel man links und rechts sieht. 80° ist der Standard."},
	{"id": "window_mode", "caption": "FENSTER", "kind": "cycle",
		"values": [0, 1, 2], "names": ["Fenster", "Vollbild randlos", "Vollbild exklusiv"],
		"hint": "Randlos wechselt schnell zu anderen Programmen, exklusiv hat die kürzeste Verzögerung."},
	{"id": "vsync", "caption": "VSYNC", "kind": "cycle",
		"values": [true, false], "names": ["An", "Aus"],
		"hint": "An: kein Zerreißen des Bildes, Bildrate höchstens wie der Monitor. Aus: geringere Verzögerung."},
	{"id": "fps_limit", "caption": "BILDRATEN-GRENZE", "kind": "cycle",
		"values": [0, 30, 60, 120, 144, 165, 240],
		"names": ["Keine", "30 FPS", "60 FPS", "120 FPS", "144 FPS", "165 FPS", "240 FPS"],
		"hint": "Begrenzt die Bilder je Sekunde. Spart Strom und Lüfterlärm."},
	{"id": "render_scale", "caption": "AUFLÖSUNG 3D", "kind": "slider",
		"min": 50.0, "max": 100.0, "step": 5.0, "scale": 100.0, "suffix": " %",
		"hint": "Unter 100 % wird das Spielbild kleiner berechnet und hochskaliert: schneller, aber unschärfer."},
	{"id": "msaa", "caption": "KANTENGLÄTTUNG", "kind": "cycle",
		"values": [0, 1, 2, 3], "names": ["Aus", "2-fach", "4-fach", "8-fach"],
		"hint": "Glättet Treppenstufen an Kanten. Höhere Stufen kosten Leistung."},
	{"id": "show_fps", "caption": "FPS-ANZEIGE", "kind": "cycle",
		"values": [false, true], "names": ["Aus", "An"],
		"hint": "Zeigt die Bilder je Sekunde unten in der Mitte."},
]

## Regler je Einstellung (id -> HSlider).
var sliders: Dictionary = {}
## Wertanzeige je Regler (id -> Label).
var value_labels: Dictionary = {}
## Umschalt-Knopf je Einstellung (id -> Button).
var cyclers: Dictionary = {}
## Knopf "Zurück" (schließt die Ansicht).
var back_button: Button
## Knopf "Standard" (alle Werte zurücksetzen).
var reset_button: Button

var _headline: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Settings.ensure_loaded()
	_build()
	refresh()


## Zeigt die Ansicht mit den aktuellen Werten.
func open() -> void:
	refresh()
	visible = true
	if is_inside_tree():
		back_button.grab_focus()
		UiStyle.pop(_headline, 0.5, 0.22)


## Schließt die Ansicht, speichert und meldet closed.
func close() -> void:
	if not visible:
		return
	visible = false
	Settings.save()
	closed.emit()


## Gleicht alle Regler und Knöpfe mit den Einstellungen ab.
func refresh() -> void:
	for row: Dictionary in ROWS:
		var id: String = row["id"]
		if row["kind"] == "slider":
			var slider: HSlider = sliders[id] as HSlider
			slider.set_value_no_signal(roundf(float(Settings.get_value(id)) * float(row["scale"])))
			_update_value_label(row)
		else:
			_update_cycler(row)


## Setzt eine Einstellung über ihren Setter in Settings und wendet sie an.
func set_setting(id: String, value: Variant) -> void:
	Settings.set_value(id, value)
	Settings.apply_audio()
	if is_inside_tree():
		Settings.apply_video(get_window())


# --- Aufbau ---------------------------------------------------------------------------

func _build() -> void:
	_headline = UiStyle.make_headline("EINSTELLUNGEN", 50, UiStyle.COL_PURPLE, UiStyle.COL_YELLOW, UiStyle.COL_CYAN)
	_headline.name = "Headline"
	_headline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_headline.pivot_offset_ratio = Vector2(0.5, 0.5)
	_headline.rotation_degrees = -2.0
	UiStyle.anchor_box(_headline, Vector2(0.5, 0.0), Vector2(0.0, 24.0), Vector2.ZERO)
	add_child(_headline)
	for i: int in ROWS.size():
		_build_row(ROWS[i], ROW_START_Y + float(i) * ROW_STEP)
	var footer_y: float = ROW_START_Y + float(ROWS.size()) * ROW_STEP + 22.0
	back_button = UiStyle.make_button("ZURÜCK", UiStyle.COL_GREEN, 28)
	back_button.name = "Back"
	back_button.pivot_offset_ratio = Vector2(0.5, 0.5)
	back_button.custom_minimum_size = FOOTER_BUTTON_SIZE
	UiStyle.anchor_box(back_button, Vector2(0.5, 0.0), Vector2(-FOOTER_BUTTON_SIZE.x - 12.0, footer_y), FOOTER_BUTTON_SIZE)
	add_child(back_button)
	back_button.pressed.connect(close)
	reset_button = UiStyle.make_button("STANDARD", UiStyle.COL_ORANGE, 28)
	reset_button.name = "Reset"
	reset_button.pivot_offset_ratio = Vector2(0.5, 0.5)
	reset_button.custom_minimum_size = FOOTER_BUTTON_SIZE
	reset_button.tooltip_text = "Stellt alle Einstellungen auf den Standard zurück."
	UiStyle.anchor_box(reset_button, Vector2(0.5, 0.0), Vector2(12.0, footer_y), FOOTER_BUTTON_SIZE)
	add_child(reset_button)
	reset_button.pressed.connect(_on_reset_pressed)


func _build_row(row: Dictionary, y: float) -> void:
	var id: String = row["id"]
	var caption: Label = UiStyle.make_label(str(row["caption"]), 20, UiStyle.COL_YELLOW, true)
	caption.name = "Caption_" + id
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(caption, Vector2(0.5, 0.0), Vector2(-CAPTION_WIDTH - 24.0, y), Vector2(CAPTION_WIDTH, CONTROL_HEIGHT))
	add_child(caption)
	if row["kind"] == "slider":
		var slider: HSlider = HSlider.new()
		slider.name = "Slider_" + id
		slider.min_value = float(row["min"])
		slider.max_value = float(row["max"])
		slider.step = float(row["step"])
		slider.focus_mode = Control.FOCUS_CLICK
		slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slider.tooltip_text = str(row["hint"])
		var track: StyleBoxFlat = UiStyle.make_box(UiStyle.COL_INK, UiStyle.COL_CYAN, 3, 0.0, 6)
		track.content_margin_top = 7.0
		track.content_margin_bottom = 7.0
		var fill: StyleBoxFlat = UiStyle.make_box(UiStyle.COL_PINK, UiStyle.COL_CYAN, 3, 0.0, 6)
		slider.add_theme_stylebox_override("slider", track)
		slider.add_theme_stylebox_override("grabber_area", fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", fill)
		UiStyle.anchor_box(slider, Vector2(0.5, 0.0), Vector2(0.0, y), Vector2(CONTROL_WIDTH, CONTROL_HEIGHT))
		add_child(slider)
		sliders[id] = slider
		var value_label: Label = UiStyle.make_label("", 22, UiStyle.COL_WHITE, true)
		value_label.name = "Value_" + id
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiStyle.anchor_box(value_label, Vector2(0.5, 0.0), Vector2(CONTROL_WIDTH + 14.0, y), Vector2(110.0, CONTROL_HEIGHT))
		add_child(value_label)
		value_labels[id] = value_label
		slider.value_changed.connect(_on_slider_changed.bind(row))
		slider.drag_ended.connect(_on_slider_drag_ended)
	else:
		var button: Button = UiStyle.make_button("", UiStyle.COL_CYAN, 19)
		button.name = "Cycle_" + id
		button.custom_minimum_size = Vector2(CONTROL_WIDTH, CONTROL_HEIGHT)
		button.focus_mode = Control.FOCUS_CLICK
		button.tooltip_text = str(row["hint"])
		UiStyle.anchor_box(button, Vector2(0.5, 0.0), Vector2(0.0, y), Vector2(CONTROL_WIDTH, CONTROL_HEIGHT))
		add_child(button)
		cyclers[id] = button
		button.pressed.connect(_on_cycler_pressed.bind(row))


# --- Reaktionen -----------------------------------------------------------------------

func _on_slider_changed(shown_value: float, row: Dictionary) -> void:
	set_setting(str(row["id"]), shown_value / float(row["scale"]))
	_update_value_label(row)


func _on_slider_drag_ended(_value_changed: bool) -> void:
	Settings.save()


## Schaltet zum nächsten Wert der Zeile weiter (nach dem letzten wieder zum ersten).
func _on_cycler_pressed(row: Dictionary) -> void:
	var values: Array = row["values"]
	var index: int = _cycle_index(row)
	set_setting(str(row["id"]), values[(index + 1) % values.size()])
	_update_cycler(row)
	Settings.save()


func _on_reset_pressed() -> void:
	Settings.reset_to_defaults()
	Settings.apply_audio()
	if is_inside_tree():
		Settings.apply_video(get_window())
	Settings.save()
	refresh()


func _update_value_label(row: Dictionary) -> void:
	var id: String = row["id"]
	var shown: int = roundi(float(Settings.get_value(id)) * float(row["scale"]))
	(value_labels[id] as Label).text = "%d%s" % [shown, str(row["suffix"])]


func _update_cycler(row: Dictionary) -> void:
	var names: Array = row["names"]
	(cyclers[str(row["id"])] as Button).text = str(names[_cycle_index(row)])


## Stelle des aktuellen Werts in der Werteliste der Zeile (0, wenn er dort fehlt).
func _cycle_index(row: Dictionary) -> int:
	var values: Array = row["values"]
	var current: Variant = Settings.get_value(str(row["id"]))
	for i: int in values.size():
		if typeof(values[i]) == typeof(current) and values[i] == current:
			return i
	return 0
