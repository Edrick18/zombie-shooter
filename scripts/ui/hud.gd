extends CanvasLayer
## Modul: Oberfläche (scripts/ui).
## HUD während des Spiels (Abschnitt 11): Lebensbalken, Schild, Ausweichsprünge und Ladungen der
## Zweiten Staffel (nur mit Sicherheitsglas, Notausgang bzw. Zweiter Staffel, Abschnitte 19.2 und
## 22.3), Punkte, darunter klein das Material des Laufs (Abschnitt 26) mit kurzem "+2" beim
## Zuwachs, Welle und verbleibende Zombies, Waffe und Munition, Fadenkreuz, Treffermarker,
## Interaktions-Hinweis, Buff-Anzeige (Boni, Verbindungen und die Kameras im Spiel mit ihrem Bild
## aus ItemIcons), Banner, roter Rand bei Schaden, Countdown zwischen den Wellen.
##
## Das HUD liest nur: Es hört auf Events und fragt Namen und Texte bei UpgradeDefs und WeaponDefs
## ab. Bei run_started stellt es alles auf Anfang und holt sich Leben und Waffe vom Spieler,
## falls es ihn gibt (ohne Spieler zeigt es die Startwerte).
##
## Diese Datei enthält außerdem den gemeinsamen Gameshow-Stil aller vier Bildschirme: Farben,
## statische Helfer (make_label, make_box, make_button, make_headline, draw_gear, draw_wrench
## ...) und kleine gezeichnete Bausteine (SlantBar, UpgradeIcon, ItemIcon,
## MaterialIcon, Pips, Sunburst). Kistenwahl, Pausemenü und Game Over binden sie ein mit:
## const UiStyle := preload("res://scripts/ui/hud.gd")

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UpgradeState := preload("res://scripts/core/upgrade_state.gd")

## Ebene des HUD. Kistenwahl 10, Pausemenü 20, Game Over 30 liegen darüber.
const LAYER: int = 1

# --- Gemeinsame Farben der Show (reine Optik) ---
const COL_INK: Color = Color(0.06, 0.03, 0.13)
const COL_PANEL: Color = Color(0.12, 0.06, 0.26, 0.86)
const COL_PANEL_SOLID: Color = Color(0.14, 0.07, 0.3)
const COL_WHITE: Color = Color(1.0, 1.0, 1.0)
const COL_YELLOW: Color = Color(1.0, 0.87, 0.1)
const COL_PINK: Color = Color(1.0, 0.16, 0.52)
const COL_CYAN: Color = Color(0.2, 0.92, 1.0)
const COL_GREEN: Color = Color(0.35, 1.0, 0.3)
const COL_ORANGE: Color = Color(1.0, 0.55, 0.08)
const COL_RED: Color = Color(1.0, 0.18, 0.16)
const COL_PURPLE: Color = Color(0.5, 0.2, 0.95)

## Hintergrundfarbe des Symbols je Upgrade (und der Sonder-Symbole).
const UPGRADE_COLORS: Dictionary = {
	"chain_lightning": Color(0.1, 0.3, 0.95),
	"pierce": Color(0.38, 0.45, 0.6),
	"burn": Color(0.85, 0.2, 0.05),
	"lifesteal": Color(0.7, 0.05, 0.2),
	"max_hp": Color(0.1, 0.65, 0.25),
	"corpse_explosion": Color(0.75, 0.15, 0.8),
	"reload_shockwave": Color(0.05, 0.6, 0.7),
	"drone": Color(0.3, 0.32, 0.42),
	"speed": Color(0.95, 0.5, 0.05),
	"luck": Color(0.85, 0.1, 0.45),
	"cam_tele": Color(0.3, 0.26, 0.7),
	"cam_flash": Color(0.5, 0.3, 0.8),
	"cam_slow": Color(0.2, 0.42, 0.75),
	"cam_director": Color(0.55, 0.2, 0.55),
	"synergy": Color(0.45, 0.1, 0.9),
	"points": Color(0.15, 0.45, 0.2),
	"heal": Color(0.92, 0.92, 0.96),
}

# --- Optik-Zahlen der Schrift ---
const FONT_EMBOLDEN: float = 0.9
const FONT_SLANT: float = 0.2
## Schräge der Plaketten (StyleBoxFlat.skew).
const PLATE_SKEW: float = 0.22

# --- Optik-Zahlen des HUD ---
const MARGIN: float = 22.0
## Magazin gilt als knapp, wenn höchstens dieser Anteil übrig ist (nur Anzeige).
const LOW_AMMO_RATIO: float = 0.3
## Leben gilt als kritisch unter diesem Anteil (pulsierender Rand, nur Anzeige).
const LOW_HP_RATIO: float = 0.3
## Deckkraft des roten Rands bei wenig Leben (Grundwert und Pulsieren).
const LOW_HP_VIGNETTE: float = 0.42
const LOW_HP_VIGNETTE_PULSE: float = 0.14
## Schild-Anzeige (Sicherheitsglas): Farbe von Zahl und Balken, klar anders als das Leben.
const SHIELD_COLOR: Color = COL_CYAN
## Anzeige der Ausweichsprünge (Notausgang): Größe eines Kästchens und Taste.
const DASH_PIP_SIZE: Vector2 = Vector2(26.0, 14.0)
const DASH_KEY_TEXT: String = "Q"
const BANNER_HOLD: float = 1.7
const BANNER_HOLD_BUSY: float = 0.9
const BANNER_MAX_QUEUE: int = 5
const BANNER_MAX_WIDTH: float = 700.0
const BANNER_FONT_SIZE: int = 38
const BANNER_MIN_FONT_SIZE: int = 20
## Gleiche Meldungen innerhalb dieser Zeit werden nur einmal gezeigt.
const BANNER_DEDUPE_MSEC: int = 3000
const FLOATER_MAX: int = 6
const FLOATER_FADE_TIME: float = 0.4
## Punktgewinne, die so kurz aufeinander folgen, zählt eine einzige Anzeige zusammen.
const GAIN_COMBO_WINDOW: float = 0.5
## Ein Nachladebalken ohne reload_finished verschwindet so lange nach Ablauf von selbst.
const RELOAD_GRACE: float = 0.3
const VIGNETTE_FADE_SPEED: float = 1.6
const UPGRADE_ROW_SIZE: Vector2 = Vector2(252.0, 44.0)
## Anzeige der Ladungen der Zweiten Staffel: Schriftzug und Farbe.
const REVIVE_TAG_TEXT: String = "2. STAFFEL"
const REVIVE_COLOR: Color = COL_PINK
## Zeile der Buff-Anzeige links (höchstens elf: vier Werte, Leben, Verbindung, fünf Kameratypen).
const BUFF_ROW_SIZE: Vector2 = Vector2(200.0, 28.0)
const BUFF_ROW_STEP: float = 32.0
const BUFF_MAX_ROWS: int = 11
## Farbe der Kamera-Zeilen in der Buff-Anzeige.
const CAMERA_ROW_COLOR: Color = Color(0.74, 0.7, 1.0)
const UPGRADE_ROW_STEP: float = 48.0
const RELOAD_KEY_TEXT: String = "R"
## Waffenanzeige unten rechts: höchstens so viele Hände, Maße der Kästen je Hand.
const HUD_HANDS: int = 2
const HAND_BOX_HEIGHT: float = 140.0
const HAND_BOX_WIDTH_ONE: float = 400.0
const HAND_BOX_WIDTH_TWO: float = 200.0
const HAND_BOX_GAP: float = 26.0
const HAND_SIDE_TEXTS: Array[String] = ["LINKS", "RECHTS"]
## Material (Abschnitt 26): Farbe der Anzeige, Maße der kleinen Zeile unter den Punkten und so
## lange steht das "+2" nach einem Zuwachs (Sekunden).
const MATERIAL_COLOR: Color = Color(0.55, 0.9, 1.0)
const MATERIAL_ROW_TOP: float = 104.0
const MATERIAL_ROW_SIZE: Vector2 = Vector2(260.0, 26.0)
const MATERIAL_ICON_SIZE: float = 22.0
const MATERIAL_FONT_SIZE: int = 18
const MATERIAL_GAIN_HOLD: float = 1.1
const MATERIAL_GAIN_FADE: float = 0.5

static var _font_cache: Dictionary = {}


# =====================================================================================
# Gemeinsamer Stil (statisch, von allen vier Bildschirmen benutzt)
# =====================================================================================

## Schrift der Show: fette Standardschrift, auf Wunsch schräg. Fehlende Zeichen (Pfeil)
## kommen aus einer Systemschrift.
static func show_font(slanted: bool = false) -> Font:
	var key: String = "slanted" if slanted else "upright"
	if _font_cache.has(key):
		return _font_cache[key] as Font
	var font: FontVariation = FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = FONT_EMBOLDEN
	if slanted:
		font.variation_transform = Transform2D(Vector2(1.0, FONT_SLANT), Vector2(0.0, 1.0), Vector2.ZERO)
	var system_font: SystemFont = SystemFont.new()
	system_font.font_names = PackedStringArray(["Segoe UI Symbol", "Arial", "DejaVu Sans", "sans-serif"])
	var fallbacks: Array[Font] = [system_font]
	font.fallbacks = fallbacks
	_font_cache[key] = font
	return font


## Gibt die gemerkten Schriften frei (vor dem Programmende aufrufen, sonst unnötig).
static func clear_font_cache() -> void:
	_font_cache.clear()


## Gibt es für diese ID ein gezeichnetes Bild (UpgradeIcon)?
static func has_icon(icon_id: String) -> bool:
	return ICON_IDS.has(icon_id)


## Zeichnet ein Zahnrad (Zeichen für Material) um center. hole_color füllt das Loch in der Mitte.
static func draw_gear(canvas: CanvasItem, center: Vector2, radius: float, color: Color, hole_color: Color = COL_INK) -> void:
	MaterialIcon.draw_gear_on(canvas, center, radius, color, hole_color)


## Zeichnet einen Schraubenschlüssel (Zeichen für Reparieren) schräg in ein Quadrat der Kantenlänge
## extent um center. notch_color füllt das Maul des Schlüssels (die Farbe des Hintergrunds).
static func draw_wrench(canvas: CanvasItem, center: Vector2, extent: float, color: Color, notch_color: Color = COL_INK) -> void:
	var head: Vector2 = center + Vector2(0.24, -0.24) * extent
	var foot: Vector2 = center + Vector2(-0.36, 0.36) * extent
	canvas.draw_line(foot, head, color, maxf(2.0, extent * 0.2))
	canvas.draw_circle(foot, maxf(1.0, extent * 0.1), color)
	canvas.draw_circle(head, extent * 0.26, color)
	canvas.draw_circle(head + Vector2(0.14, -0.14) * extent, extent * 0.14, notch_color)


## Setzt Schrift, Größe, Farbe, dunklen Rand und Schatten eines Labels.
static func style_label(label: Label, font_size: int, color: Color, slanted: bool = false) -> void:
	var outline: int = maxi(4, roundi(float(font_size) * 0.22))
	var shadow: int = maxi(2, roundi(float(font_size) * 0.07))
	label.add_theme_font_override("font", show_font(slanted))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COL_INK)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", shadow)
	label.add_theme_constant_override("shadow_offset_y", shadow)
	label.add_theme_constant_override("shadow_outline_size", outline)


## Neues Label im Show-Stil. Fängt keine Maus.
static func make_label(text: String, font_size: int, color: Color = COL_WHITE, slanted: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_label(label, font_size, color, slanted)
	return label


## Kasten-Stil: Füllfarbe, dicker Rand, Schlagschatten, auf Wunsch schräg (skew).
static func make_box(bg: Color, border: Color = COL_INK, border_width: int = 4, skew: float = 0.0,
		radius: int = 6) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.skew = Vector2(skew, 0.0)
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	box.shadow_size = 2
	box.shadow_offset = Vector2(4.0, 5.0)
	box.anti_aliasing = true
	return box


## Plakette (Panel) mit Kasten-Stil. Fängt keine Maus.
static func make_plate(bg: Color, border: Color = COL_INK, border_width: int = 4,
		skew: float = PLATE_SKEW, radius: int = 6) -> Panel:
	var plate: Panel = Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", make_box(bg, border, border_width, skew, radius))
	return plate


## Schräge Überschrift-Plakette, die sich an ihren Text anschmiegt. Das Label heißt "Label".
static func make_headline(text: String, font_size: int, bg: Color = COL_PINK,
		text_color: Color = COL_YELLOW, border: Color = COL_YELLOW) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBoxFlat = make_box(bg, border, 6, PLATE_SKEW, 8)
	box.content_margin_left = float(font_size) * 0.8
	box.content_margin_right = float(font_size) * 0.8
	box.content_margin_top = float(font_size) * 0.08
	box.content_margin_bottom = float(font_size) * 0.12
	box.shadow_offset = Vector2(7.0, 8.0)
	panel.add_theme_stylebox_override("panel", box)
	var label: Label = make_label(text, font_size, text_color, true)
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


## Dicker Gameshow-Knopf (schräg, kräftige Farbe, Hover und Tastatur-Fokus sichtbar).
static func make_button(text: String, accent: Color = COL_YELLOW, font_size: int = 28) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(300.0, 62.0)
	button.add_theme_font_override("font", show_font(true))
	button.add_theme_font_size_override("font_size", font_size)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(color_name, COL_INK)
	button.add_theme_color_override("font_disabled_color", Color(0.2, 0.2, 0.25))
	button.add_theme_stylebox_override("normal", make_box(accent, COL_INK, 5, PLATE_SKEW, 8))
	button.add_theme_stylebox_override("hover", make_box(accent.lightened(0.45), COL_WHITE, 5, PLATE_SKEW, 8))
	button.add_theme_stylebox_override("pressed", make_box(COL_PINK, COL_WHITE, 5, PLATE_SKEW, 8))
	button.add_theme_stylebox_override("disabled", make_box(Color(0.45, 0.45, 0.5), COL_INK, 5, PLATE_SKEW, 8))
	var focus: StyleBoxFlat = make_box(Color(0.0, 0.0, 0.0, 0.0), COL_CYAN, 5, PLATE_SKEW, 8)
	focus.draw_center = false
	focus.shadow_size = 0
	focus.set_expand_margin_all(5.0)
	button.add_theme_stylebox_override("focus", focus)
	return button


## Abdunklung über den ganzen Bildschirm. Fängt Mausklicks ab, damit nichts darunter reagiert.
static func make_dim(color: Color) -> ColorRect:
	var dim: ColorRect = ColorRect.new()
	dim.color = color
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return dim


## Legt ein Control als feste Kiste an einen Ankerpunkt des Elternknotens (0..1 je Achse).
## offset ist die linke obere Ecke relativ zum Ankerpunkt. Vor add_child aufrufen.
static func anchor_box(control: Control, anchor: Vector2, offset: Vector2, box_size: Vector2) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + box_size.x
	control.offset_bottom = offset.y + box_size.y


## Lässt ein Control kurz aufploppen (von from_scale zurück auf 1). Läuft nur im Baum.
static func pop(control: Control, from_scale: float = 1.3, duration: float = 0.2) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree():
		return
	kill_tween(control, "pop_tween")
	control.scale = Vector2.ONE * from_scale
	var tween: Tween = control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	control.set_meta("pop_tween", tween)


## Beendet einen Tween, der unter diesem Meta-Namen am Knoten gemerkt wurde.
static func kill_tween(node: Node, meta_name: String) -> void:
	if not is_instance_valid(node) or not node.has_meta(meta_name):
		return
	var old: Tween = node.get_meta(meta_name) as Tween
	if old != null and old.is_valid():
		old.kill()
	node.remove_meta(meta_name)


## Ganze Zahl mit Tausenderpunkt (12340 -> "12.340").
static func format_int(value: int) -> String:
	var digits: String = str(absi(value))
	var grouped: String = ""
	while digits.length() > 3:
		grouped = "." + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + grouped


## Farbe des Lebensbalkens: grün, bei halbem Leben gelb, darunter rot.
static func health_color(ratio: float) -> Color:
	var r: float = clampf(ratio, 0.0, 1.0)
	if r >= 0.5:
		return COL_YELLOW.lerp(COL_GREEN, clampf((r - 0.5) / 0.3, 0.0, 1.0))
	return COL_RED.lerp(COL_YELLOW, clampf((r - 0.2) / 0.3, 0.0, 1.0))


## Symbolfarbe eines Upgrades (oder Sonder-Symbols), grau bei unbekannter ID.
static func upgrade_color(icon_id: String) -> Color:
	return UPGRADE_COLORS.get(icon_id, Color(0.4, 0.4, 0.5)) as Color


## Größte Schriftgröße (höchstens font_size), mit der der Text in max_width passt.
static func fit_font_size(text: String, font_size: int, max_width: float, slanted: bool = true,
		min_size: int = 16) -> int:
	var font: Font = show_font(slanted)
	var fitted: int = font_size
	while fitted > min_size:
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fitted).x
		if width <= max_width:
			break
		fitted -= 2
	return fitted


## Ersetzt das Leerzeichen zwischen Zahl und Einheit ("15 m", "3 s", "15 %") durch ein
## geschütztes, damit der Zeilenumbruch die beiden nie trennt.
static func keep_units_together(text: String) -> String:
	var pattern: RegEx = RegEx.new()
	if pattern.compile("([0-9]) (m|s|%)(?![a-zäöüß])") != OK:
		return text
	return pattern.sub(text, "$1" + String.chr(0x00A0) + "$2", true)


## Name eines Upgrades, Gegenstands oder einer Kamera für Listen (Kameras stehen seit Abschnitt 22
## nicht mehr in UpgradeDefs).
static func entry_name(id: String) -> String:
	return ItemDefs.display_name(id) if ItemDefs.has(id) else UpgradeDefs.display_name(id)


## Eine Zeile "Symbol, Name, Rarität" für die Liste im Game Over (Upgrades und Kameras).
## Kinder: "Icon", "Name" (Label), "Rarity" (Label mit der Rarität in ihrer Farbe).
## Zeilen unter 42 Pixeln Höhe werden enger gesetzt (kleinere Schrift).
static func make_upgrade_row(upgrade_id: String, level: int, row_size: Vector2) -> Control:
	var row: Control = Control.new()
	row.name = "Row_%s" % upgrade_id
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = row_size
	row.size = row_size
	row.pivot_offset_ratio = Vector2(0.0, 0.5)
	var rarity_color: Color = ItemDefs.rarity_color(level)
	var plate: Panel = make_plate(COL_PANEL, rarity_color, 3, 0.12, 5)
	plate.name = "Plate"
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(plate)
	var icon_size: float = row_size.y - 10.0
	if has_icon(upgrade_id):
		var icon: UpgradeIcon = UpgradeIcon.new()
		icon.name = "Icon"
		icon.icon_id = upgrade_id
		anchor_box(icon, Vector2.ZERO, Vector2(7.0, 5.0), Vector2(icon_size, icon_size))
		row.add_child(icon)
	else:
		# Neuere Gegenstände haben kein gezeichnetes Bild: Sie zeigen ihre Form.
		var shape_icon: ItemShape = ItemShape.new()
		shape_icon.name = "Icon"
		shape_icon.item_id = upgrade_id
		shape_icon.max_cell = icon_size * 0.56
		anchor_box(shape_icon, Vector2.ZERO, Vector2(7.0, 5.0), Vector2(icon_size, icon_size))
		row.add_child(shape_icon)
	var compact: bool = row_size.y < 42.0
	var text_left: float = icon_size + 14.0
	var name_width: float = row_size.x - text_left - 8.0
	var display_name: String = entry_name(upgrade_id)
	var name_label: Label = make_label(display_name, fit_font_size(display_name, 13 if compact else 15, name_width - 6.0, false, 10 if compact else 11), COL_WHITE)
	name_label.name = "Name"
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	anchor_box(name_label, Vector2.ZERO, Vector2(text_left, 0.0 if compact else 1.0), Vector2(name_width, 20.0 if compact else 24.0))
	row.add_child(name_label)
	# Unter dem Namen steht die Rarität in ihrer Farbe (die Stufe, mit der das Upgrade wirkt).
	var rarity_label: Label = make_label(ItemDefs.rarity_name(level).to_upper(), 10 if compact else 12, rarity_color, true)
	rarity_label.name = "Rarity"
	rarity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if compact:
		rarity_label.add_theme_constant_override("outline_size", 3)
		rarity_label.add_theme_constant_override("shadow_outline_size", 3)
		name_label.add_theme_constant_override("outline_size", 3)
		name_label.add_theme_constant_override("shadow_outline_size", 3)
	anchor_box(rarity_label, Vector2.ZERO, Vector2(text_left, row_size.y - (18.0 if compact else 22.0)), Vector2(name_width, 16.0 if compact else 18.0))
	row.add_child(rarity_label)
	return row


## Zeile für eine aktive Synergie (belegt keinen Platz). Kinder: "Icon", "Name", "Tag".
static func make_synergy_row(synergy_id: String, row_size: Vector2) -> Control:
	var row: Control = Control.new()
	row.name = "Synergy_%s" % synergy_id
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = row_size
	row.size = row_size
	row.pivot_offset_ratio = Vector2(0.0, 0.5)
	var plate: Panel = make_plate(Color(0.3, 0.05, 0.45, 0.92), COL_YELLOW, 3, 0.12, 5)
	plate.name = "Plate"
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(plate)
	var icon_size: float = row_size.y - 10.0
	var icon: UpgradeIcon = UpgradeIcon.new()
	icon.name = "Icon"
	icon.icon_id = "synergy"
	anchor_box(icon, Vector2.ZERO, Vector2(7.0, 5.0), Vector2(icon_size, icon_size))
	row.add_child(icon)
	var text_left: float = icon_size + 14.0
	var name_label: Label = make_label(UpgradeDefs.synergy_name(synergy_id), 16, COL_YELLOW)
	name_label.name = "Name"
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	anchor_box(name_label, Vector2.ZERO, Vector2(text_left, 1.0), Vector2(row_size.x - text_left - 8.0, 24.0))
	row.add_child(name_label)
	var tag: Label = make_label("SYNERGIE AKTIV", 11, COL_CYAN)
	tag.name = "Tag"
	anchor_box(tag, Vector2.ZERO, Vector2(text_left, row_size.y - 21.0), Vector2(row_size.x - text_left - 8.0, 18.0))
	row.add_child(tag)
	return row


# =====================================================================================
# Gezeichnete Bausteine
# =====================================================================================

## Schräger Balken mit Füllung und nachlaufendem hellen Anteil (Lebensbalken, Nachladen).
class SlantBar:
	extends Control

	## Füllstand 0 bis 1.
	var ratio: float = 1.0:
		set(value):
			ratio = clampf(value, 0.0, 1.0)
			queue_redraw()
	## Heller Anteil hinter der Füllung (zeigt gerade verlorenes Leben), 0 bis 1.
	var ghost_ratio: float = 0.0:
		set(value):
			ghost_ratio = clampf(value, 0.0, 1.0)
			queue_redraw()
	var fill_color: Color = Color(0.35, 1.0, 0.3):
		set(value):
			fill_color = value
			queue_redraw()
	var ghost_color: Color = Color(1.0, 1.0, 1.0, 0.9)
	var back_color: Color = Color(0.06, 0.03, 0.13, 0.9)
	var border_color: Color = Color(0.06, 0.03, 0.13)
	## Versatz der Oberkante nach rechts in Pixeln.
	var slant: float = 10.0
	var border: float = 4.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var inner_width: float = size.x - slant - border * 2.0
		if inner_width < 2.0 or size.y < border * 2.0 + 2.0:
			return
		draw_colored_polygon(_quad(0.0, size.x - slant, 0.0, size.y), border_color)
		draw_colored_polygon(_quad(border, border + inner_width, border, size.y - border), back_color)
		if ghost_ratio > ratio and inner_width * ghost_ratio >= 1.0:
			draw_colored_polygon(_quad(border, border + inner_width * ghost_ratio, border, size.y - border), ghost_color)
		if inner_width * ratio >= 1.0:
			draw_colored_polygon(_quad(border, border + inner_width * ratio, border, size.y - border), fill_color)
			# Glanzstreifen auf der oberen Hälfte.
			draw_colored_polygon(_quad(border, border + inner_width * ratio, border,
					border + (size.y - border * 2.0) * 0.4), Color(1.0, 1.0, 1.0, 0.25))

	func _quad(x0: float, x1: float, y0: float, y1: float) -> PackedVector2Array:
		var top_shift: float = slant * (1.0 - y0 / size.y)
		var bottom_shift: float = slant * (1.0 - y1 / size.y)
		return PackedVector2Array([
			Vector2(x0 + top_shift, y0), Vector2(x1 + top_shift, y0),
			Vector2(x1 + bottom_shift, y1), Vector2(x0 + bottom_shift, y1),
		])


## Kleines gezeichnetes Symbol je Upgrade (Platzhalter-Grafik aus einfachen Formen).
## icon_id: Upgrade-ID, "synergy", "points" oder "heal".
class UpgradeIcon:
	extends Control

	var icon_id: String = "":
		set(value):
			icon_id = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x < 6.0 or size.y < 6.0:
			return
		var inset: float = maxf(2.0, size.x * 0.07)
		var inner: Rect2 = Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		draw_rect(Rect2(Vector2.ZERO, size), COL_INK)
		draw_rect(inner, UPGRADE_COLORS.get(icon_id, Color(0.4, 0.4, 0.5)) as Color)
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.38)), Color(1.0, 1.0, 1.0, 0.16))
		var line: float = maxf(2.0, size.x * 0.09)
		match icon_id:
			"chain_lightning":
				draw_colored_polygon(_bolt(), COL_YELLOW)
			"pierce":
				draw_rect(Rect2(_p(0.3, 0.2), _p(0.09, 0.6)), COL_INK)
				draw_rect(Rect2(_p(0.52, 0.2), _p(0.09, 0.6)), COL_INK)
				draw_line(_p(0.12, 0.5), _p(0.74, 0.5), COL_YELLOW, line)
				draw_colored_polygon(_poly([0.9, 0.5, 0.68, 0.34, 0.68, 0.66]), COL_YELLOW)
			"burn":
				draw_colored_polygon(_poly([0.5, 0.1, 0.72, 0.45, 0.76, 0.66, 0.64, 0.86, 0.5, 0.9,
						0.36, 0.86, 0.24, 0.66, 0.28, 0.45]), COL_YELLOW)
				draw_colored_polygon(_poly([0.5, 0.42, 0.62, 0.62, 0.6, 0.78, 0.5, 0.84, 0.4, 0.78,
						0.38, 0.62]), COL_RED)
			"lifesteal":
				draw_circle(_p(0.36, 0.4), size.x * 0.17, COL_WHITE)
				draw_circle(_p(0.64, 0.4), size.x * 0.17, COL_WHITE)
				draw_colored_polygon(_poly([0.2, 0.47, 0.8, 0.47, 0.5, 0.86]), COL_WHITE)
			"max_hp", "heal":
				var cross: Color = COL_RED if icon_id == "heal" else COL_WHITE
				draw_rect(Rect2(_p(0.4, 0.18), _p(0.2, 0.64)), cross)
				draw_rect(Rect2(_p(0.18, 0.4), _p(0.64, 0.2)), cross)
			"corpse_explosion":
				var burst: Array[Color] = [COL_YELLOW, COL_CYAN, COL_WHITE, COL_GREEN]
				for i: int in 8:
					var dir: Vector2 = Vector2.from_angle(TAU * float(i) / 8.0)
					draw_line(size * 0.5 + dir * size.x * 0.16, size * 0.5 + dir * size.x * 0.38,
							burst[i % burst.size()], line)
				draw_circle(size * 0.5, size.x * 0.09, COL_WHITE)
			"reload_shockwave":
				draw_arc(size * 0.5, size.x * 0.34, 0.0, TAU, 24, COL_WHITE, line * 0.8)
				draw_arc(size * 0.5, size.x * 0.2, 0.0, TAU, 20, COL_YELLOW, line * 0.8)
				draw_circle(size * 0.5, size.x * 0.07, COL_WHITE)
			"drone":
				draw_line(_p(0.16, 0.28), _p(0.84, 0.28), COL_CYAN, line)
				draw_line(_p(0.5, 0.28), _p(0.5, 0.44), COL_WHITE, line * 0.7)
				draw_rect(Rect2(_p(0.24, 0.42), _p(0.52, 0.34)), COL_WHITE)
				draw_circle(_p(0.5, 0.59), size.x * 0.11, COL_INK)
				draw_circle(_p(0.5, 0.59), size.x * 0.05, COL_RED)
			"speed":
				draw_polyline(_poly([0.2, 0.24, 0.46, 0.5, 0.2, 0.76]), COL_WHITE, line * 1.2)
				draw_polyline(_poly([0.5, 0.24, 0.76, 0.5, 0.5, 0.76]), COL_YELLOW, line * 1.2)
			"luck":
				draw_colored_polygon(_star(Vector2(0.5, 0.53), 0.38, 0.16), COL_YELLOW)
			"cam_tele":
				# Kamera mit langem Objektiv.
				draw_rect(Rect2(_p(0.12, 0.36), _p(0.3, 0.36)), COL_WHITE)
				draw_colored_polygon(_poly([0.42, 0.44, 0.84, 0.32, 0.84, 0.76, 0.42, 0.64]), COL_CYAN)
				draw_line(_p(0.84, 0.32), _p(0.84, 0.76), COL_INK, line * 0.7)
				draw_circle(_p(0.27, 0.54), size.x * 0.06, COL_RED)
			"cam_flash":
				# Kamera mit Blitz obenauf.
				draw_rect(Rect2(_p(0.18, 0.46), _p(0.64, 0.36)), COL_WHITE)
				draw_circle(_p(0.5, 0.64), size.x * 0.12, COL_INK)
				draw_circle(_p(0.5, 0.64), size.x * 0.05, COL_CYAN)
				draw_colored_polygon(_star(Vector2(0.5, 0.26), 0.22, 0.09), COL_YELLOW)
			"cam_slow":
				# Kamera mit Uhr als Linse.
				draw_rect(Rect2(_p(0.14, 0.3), _p(0.72, 0.48)), COL_WHITE)
				draw_circle(_p(0.5, 0.54), size.x * 0.18, COL_INK)
				draw_line(_p(0.5, 0.54), _p(0.5, 0.42), COL_CYAN, line * 0.7)
				draw_line(_p(0.5, 0.54), _p(0.6, 0.58), COL_CYAN, line * 0.7)
			"cam_director":
				# Filmklappe.
				draw_rect(Rect2(_p(0.16, 0.44), _p(0.68, 0.38)), COL_WHITE)
				draw_colored_polygon(_poly([0.16, 0.34, 0.8, 0.18, 0.84, 0.3, 0.2, 0.46]), COL_INK)
				for i: int in 3:
					var x: float = 0.26 + 0.2 * float(i)
					draw_line(_p(x, 0.32), _p(x + 0.08, 0.4 - 0.05), COL_YELLOW, line * 0.9)
				draw_circle(_p(0.5, 0.63), size.x * 0.08, COL_PINK)
			"synergy":
				draw_colored_polygon(_star(Vector2(0.5, 0.53), 0.42, 0.2), COL_YELLOW)
				draw_colored_polygon(_bolt(), COL_PINK)
			"points":
				draw_circle(size * 0.5, size.x * 0.34, COL_YELLOW)
				draw_arc(size * 0.5, size.x * 0.22, 0.0, TAU, 20, COL_ORANGE, line * 0.8)

	func _p(x: float, y: float) -> Vector2:
		return Vector2(x * size.x, y * size.y)

	## Punktliste aus x/y-Paaren in Einheitskoordinaten.
	func _poly(flat: Array) -> PackedVector2Array:
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in range(0, flat.size() - 1, 2):
			points.append(_p(float(flat[i]), float(flat[i + 1])))
		return points

	func _bolt() -> PackedVector2Array:
		return _poly([0.6, 0.1, 0.26, 0.56, 0.46, 0.56, 0.38, 0.9, 0.74, 0.42, 0.53, 0.42])

	func _star(center: Vector2, outer: float, inner: float) -> PackedVector2Array:
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in 10:
			var radius: float = outer if i % 2 == 0 else inner
			var angle: float = -PI * 0.5 + TAU * float(i) / 10.0
			points.append(_p(center.x + cos(angle) * radius, center.y + sin(angle) * radius))
		return points


## Form eines Gegenstands aus dem Rucksack als kleine Kästchen (Kistenkarten, Kandidatenwahl).
## Die Form wird in die Größe des Controls eingepasst und mittig gezeichnet.
class ItemShape:
	extends Control

	const ItemDefs := preload("res://scripts/core/item_defs.gd")

	## ID aus ItemDefs.
	var item_id: String = "":
		set(value):
			item_id = value
			queue_redraw()
	## Vierteldrehungen im Uhrzeigersinn.
	var rot: int = 0:
		set(value):
			rot = value
			queue_redraw()
	## Größte Kantenlänge eines Kästchens in Pixeln.
	var max_cell: float = 26.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var cells: Array[Vector2i] = ItemDefs.cells(item_id, rot)
		if cells.is_empty() or size.x < 4.0 or size.y < 4.0:
			return
		var extent: Vector2i = ItemDefs.size(item_id, rot)
		var cell: float = minf(max_cell, minf(size.x / float(extent.x), size.y / float(extent.y)))
		var origin: Vector2 = (size - Vector2(extent) * cell) * 0.5
		var fill: Color = ItemDefs.color(item_id)
		# Sehr kleine Kästchen (lange Waffen in einem kleinen Bild) bekommen dünnere Ränder,
		# sonst bliebe von der Farbe nichts übrig.
		var small: bool = cell < 13.0
		for entry: Vector2i in cells:
			var rect: Rect2 = Rect2(origin + Vector2(entry) * cell, Vector2(cell, cell)).grow(-0.5 if small else -1.5)
			draw_rect(rect, Color(0.05, 0.04, 0.12))
			draw_rect(rect.grow(-1.0 if small else -2.0), fill)
			if not small:
				draw_rect(Rect2(rect.position + Vector2(3.0, 3.0), Vector2(rect.size.x - 6.0, rect.size.y * 0.28)), fill.lightened(0.45))


## Bild eines Gegenstands aus ItemIcons (Abschnitt 26.2) auf einem dunklen Feld.
class ItemIcon:
	extends Control

	## ID aus ItemDefs.
	var item_id: String = "":
		set(value):
			item_id = value
			queue_redraw()
	## Färbt das ganze Bild (z. B. grau für kaputt).
	var tint: Color = Color.WHITE:
		set(value):
			tint = value
			queue_redraw()
	## Wie oft das Bild gezeichnet wurde (für Tests).
	var draw_count: int = 0

	## Pfad der Bilder-Datei. Erst beim Zeichnen geladen: So hängt hud.gd nicht an der
	## Bilder-Datei (und umgekehrt).
	const ICONS_PATH: String = "res://scripts/ui/item_icons.gd"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x < 4.0 or size.y < 4.0 or item_id.is_empty():
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.03, 0.13))
		draw_count += 1
		var icons: GDScript = load(ICONS_PATH) as GDScript
		if icons != null:
			icons.call("draw", self, item_id, Rect2(Vector2.ZERO, size), tint)


## Zahnrad als kleines Bild: das Zeichen für Material (HUD und Rucksack).
class MaterialIcon:
	extends Control

	## Zahl der Zähne.
	const TEETH: int = 8

	var color: Color = Color(0.55, 0.9, 1.0):
		set(value):
			color = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var radius: float = minf(size.x, size.y) * 0.5
		if radius < 3.0:
			return
		var ink: Color = Color(0.06, 0.03, 0.13)
		draw_gear_on(self, size * 0.5 + Vector2(0.0, 1.5), radius, ink, ink)
		draw_gear_on(self, size * 0.5, radius - 1.5, color, ink)

	## Zeichnet ein Zahnrad um center (siehe draw_gear außen).
	static func draw_gear_on(canvas: CanvasItem, center: Vector2, radius: float, gear_color: Color, hole_color: Color) -> void:
		var points: PackedVector2Array = PackedVector2Array()
		var steps: int = TEETH * 4
		for i: int in steps:
			# Je Zahn vier Punkte: zwei außen (Zahn), zwei innen (Lücke).
			var outer: bool = i % 4 < 2
			var angle: float = TAU * (float(i) - 0.5) / float(steps)
			points.append(center + Vector2.from_angle(angle) * radius * (1.0 if outer else 0.72))
		canvas.draw_colored_polygon(points, gear_color)
		canvas.draw_circle(center, radius * 0.32, hole_color)


## IDs, für die UpgradeIcon ein eigenes Bild zeichnet. Alle anderen Gegenstände zeigen ihre Form.
const ICON_IDS: Array[String] = [
	"chain_lightning", "pierce", "burn", "lifesteal", "max_hp",
	"corpse_explosion", "reload_shockwave", "drone", "speed", "luck",
	"cam_tele", "cam_flash", "cam_slow", "cam_director",
	"synergy", "points", "heal",
]


## Stufen-Punkte: max_level schräge Kästchen, level davon gefüllt. Kästchen ab gained_from
## (0-basiert, -1 = keine) zeigen die neu gewonnenen Stufen in new_color.
class Pips:
	extends Control

	var level: int = 0:
		set(value):
			level = value
			queue_redraw()
	var max_level: int = 5
	var gained_from: int = -1:
		set(value):
			gained_from = value
			queue_redraw()
	var fill_color: Color = Color(0.2, 0.92, 1.0)
	var new_color: Color = Color(1.0, 0.87, 0.1):
		set(value):
			new_color = value
			queue_redraw()
	var empty_color: Color = Color(0.0, 0.0, 0.0, 0.55)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if max_level <= 0:
			return
		var gap: float = maxf(2.0, size.y * 0.3)
		var slant: float = size.y * 0.45
		var width: float = (size.x - gap * float(max_level - 1)) / float(max_level)
		if width <= slant + 2.0 or size.y < 3.0:
			return
		for i: int in max_level:
			var x: float = float(i) * (width + gap)
			var color: Color = empty_color
			if i < level:
				color = new_color if gained_from >= 0 and i >= gained_from else fill_color
			var quad: PackedVector2Array = PackedVector2Array([
				Vector2(x + slant, 0.0), Vector2(x + width, 0.0),
				Vector2(x + width - slant, size.y), Vector2(x, size.y),
			])
			draw_colored_polygon(quad, color)
			quad.append(quad[0])
			draw_polyline(quad, COL_INK, 1.5, true)


## Drehender Strahlenkranz als Gameshow-Hintergrund (Kistenwahl, Game Over, Pause).
class Sunburst:
	extends Control

	var ray_color: Color = Color(1.0, 1.0, 1.0, 0.08):
		set(value):
			ray_color = value
			queue_redraw()
	var rays: int = 14
	## Drehung in Radiant je Sekunde.
	var speed: float = 0.12
	var _angle: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_angle = fmod(_angle + speed * delta, TAU)
		queue_redraw()

	func _draw() -> void:
		if size.x < 8.0 or size.y < 8.0 or rays <= 0:
			return
		var center: Vector2 = size * 0.5
		var radius: float = size.length()
		var step: float = TAU / float(rays)
		for i: int in rays:
			var start: float = _angle + step * float(i)
			draw_colored_polygon(PackedVector2Array([
				center,
				center + Vector2.from_angle(start) * radius,
				center + Vector2.from_angle(start + step * 0.5) * radius,
			]), ray_color)


## FPS-Anzeige: Bilder je Sekunde, sichtbar solange Settings.show_fps an ist. Läuft auch in der
## Pause weiter, damit sie beim Umschalten in den Einstellungen sofort erscheint.
class FpsLabel:
	extends Label

	const Settings := preload("res://scripts/game/settings.gd")
	const INTERVAL: float = 0.25
	var _left: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS
		visible = false

	func _process(delta: float) -> void:
		if visible != Settings.show_fps:
			visible = Settings.show_fps
			_left = 0.0
		if not visible:
			return
		_left -= delta
		if _left <= 0.0:
			_left = INTERVAL
			text = "%d FPS" % roundi(Engine.get_frames_per_second())


## Fadenkreuz: vier Striche und ein Punkt. Springt beim Schuss auf und zieht sich wieder zusammen.
class Crosshair:
	extends Control

	const TICK_LENGTH: float = 9.0
	const KICK_MAX: float = 16.0
	const KICK_RECOVER: float = 9.0

	## Abstand der Striche zur Mitte in Ruhe (wächst mit der Streuung der Waffe).
	var base_gap: float = 6.0:
		set(value):
			base_gap = value
			queue_redraw()
	## Aktueller Ausschlag durch Schüsse in Pixeln.
	var kick: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	## Ein Schuss: Die Striche springen nach außen.
	func bump(amount: float) -> void:
		kick = minf(kick + amount, KICK_MAX)
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		kick = lerpf(kick, 0.0, minf(1.0, KICK_RECOVER * delta))
		if kick < 0.1:
			kick = 0.0
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		var gap: float = base_gap + kick
		for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(dir * (gap - 1.5), dir * (gap + TICK_LENGTH + 1.5), COL_INK, 6.0)
		for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(dir * gap, dir * (gap + TICK_LENGTH), COL_WHITE, 3.0)
		draw_circle(Vector2.ZERO, 3.2, COL_INK)
		draw_circle(Vector2.ZERO, 1.7, COL_WHITE)


## Treffermarker: ein X um die Bildmitte. Art: HIT weiß, HEADSHOT gelb, KILL rot,
## HEADSHOT_KILL rot mit gelbem Ring. Ein stärkerer Marker wird nicht von einem schwächeren verdrängt.
class HitMarker:
	extends Control

	enum Kind { NONE = -1, HIT = 0, HEADSHOT = 1, KILL = 2, HEADSHOT_KILL = 3 }
	const DURATIONS: Array[float] = [0.14, 0.2, 0.34, 0.42]

	## Art des gerade gezeigten Markers (NONE, wenn keiner zu sehen ist).
	var kind: int = Kind.NONE
	var _left: float = 0.0
	var _duration: float = 0.1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	## Zeigt einen Marker dieser Art.
	func flash(new_kind: int) -> void:
		if new_kind < Kind.HIT or new_kind > Kind.HEADSHOT_KILL:
			return
		if is_active() and new_kind < kind:
			return
		kind = new_kind
		_duration = DURATIONS[new_kind]
		_left = _duration
		set_process(true)
		queue_redraw()

	## Ist gerade ein Marker zu sehen?
	func is_active() -> bool:
		return _left > 0.0 and kind != Kind.NONE

	## Blendet den Marker sofort aus.
	func clear() -> void:
		_left = 0.0
		kind = Kind.NONE
		set_process(false)
		queue_redraw()

	func _process(delta: float) -> void:
		_left -= delta
		if _left <= 0.0:
			clear()
			return
		queue_redraw()

	func _draw() -> void:
		if not is_active():
			return
		var t: float = clampf(_left / _duration, 0.0, 1.0)
		var grow: float = 1.0 + (1.0 - t) * 0.45
		var color: Color = COL_WHITE
		if kind == Kind.HEADSHOT:
			color = COL_YELLOW
		elif kind >= Kind.KILL:
			color = COL_RED
		color.a = minf(1.0, t * 1.6)
		var ink: Color = Color(COL_INK, color.a)
		var inner: float = (9.0 + float(kind) * 1.5) * grow
		var outer: float = (19.0 + float(kind) * 3.5) * grow
		var width: float = 3.0 + float(kind) * 0.8
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var unit: Vector2 = dir.normalized()
			draw_line(unit * (inner - 1.5), unit * (outer + 1.5), ink, width + 3.0)
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var unit: Vector2 = dir.normalized()
			draw_line(unit * inner, unit * outer, color, width)
		if kind == Kind.HEADSHOT_KILL:
			draw_arc(Vector2.ZERO, outer + 6.0, 0.0, TAU, 28, Color(COL_YELLOW, color.a), 3.0)


## Hält die Banner-Plakette. Läuft auch bei pausiertem Baum und blendet die Meldung aus, solange
## ein Menü offen ist (Kistenwahl, Pause, Game Over): Sie läge sonst hinter dessen Überschrift.
class BannerHolder:
	extends Control

	func _init() -> void:
		name = "BannerHolder"
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		var playing: bool = Game.state == Game.State.PLAYING
		if visible != playing:
			visible = playing


# =====================================================================================
# HUD
# =====================================================================================

## Wurzel aller HUD-Elemente (füllt den Bildschirm, fängt keine Maus).
var root: Control
## "WELLE 3" (vor der ersten Welle "SHOWSTART").
var wave_label: Label
## "NOCH 12 ZOMBIES", nach der Welle "GESCHAFFT!".
var zombies_label: Label
## Punktestand mit Tausenderpunkt.
var points_label: Label
## Behälter der schwebenden "+60"-Anzeigen (je Anzeige ein Label).
var floaters: Control
## Material des Laufs, klein unter den Punkten: "MATERIAL 3" mit Zahnrad davor.
var material_label: Label
var material_icon: MaterialIcon
## "+2" links neben dem Material, nur kurz nach einem Zuwachs zu sehen.
var material_gain_label: Label
## Aktuelles Leben als ganze Zahl.
var health_label: Label
## "/ 100".
var health_max_label: Label
var health_bar: SlantBar
## Schild-Anzeige (Sicherheitsglas) am Lebensbalken: Behälter mit "SCHILD", Zahl und Balken.
## Nur sichtbar, solange der Spieler ein Schild hat (max_shield > 0).
var shield_box: Control
## Aktuelles Schild als ganze Zahl (cyan).
var shield_label: Label
## "/ 40": Höchstwert des Schilds.
var shield_max_label: Label
## Schmaler cyanfarbener Balken direkt unter dem Lebensbalken.
var shield_bar: SlantBar
## Anzeige der Ausweichsprünge (Notausgang) rechts neben dem Lebensbalken: Taste und Kästchen.
## Nur sichtbar, solange der Spieler Sprünge hat (max_dash_charges > 0).
var dash_box: Control
## Je Sprung ein Kästchen (max_level = höchstens mögliche, level = verfügbare Sprünge).
var dash_pips: Pips
## Anzeige der Ladungen der Zweiten Staffel: Schriftzug "2. STAFFEL" und je Ladung ein Kästchen.
## Steht direkt über der Sprung-Anzeige (ohne Notausgang an deren Platz). Nur sichtbar, solange
## eine Zweite Staffel im Rucksack liegt (max_charges > 0).
var revive_box: Control
## Je Ladung ein Kästchen (max_level = Ladungen im Rucksack, level = bereite Ladungen).
var revive_pips: Pips
## Waffenanzeige unten rechts, je Hand ein Kasten (Index 0 = linke Hand). Bei einer Waffe ist nur
## Kasten 0 zu sehen, bei zwei Waffen steht die linke Hand links neben der rechten. Kinder je
## Kasten: "Side" (Label "LINKS" oder "RECHTS", nur bei zwei Waffen), "Name" (Label),
## "AmmoRow/Ammo" (Kugeln im Magazin) und "AmmoRow/Magazine" ("/ 10", Größe des Magazins).
var hand_boxes: Array[Control] = []
## Name der Waffe in der linken Hand (bei einer Waffe: dieser Waffe).
var weapon_label: Label
## Kugeln im Magazin der linken Hand.
var ammo_label: Label
## "/ 10": Größe des Magazins der linken Hand. Munition ist unendlich, einen Vorrat gibt es nicht.
var magazine_label: Label
## "WENIG MUNITION" über der Munitionsanzeige.
var low_ammo_label: Label
## "NACHLADEN [R]" unter dem Fadenkreuz bei leerem Magazin.
var reload_hint_label: Label
## Fortschritt des Nachladens unter dem Fadenkreuz, je Hand ein Balken: bei einer Waffe mittig,
## bei zwei Waffen der der linken Hand links und der der rechten rechts der Mitte.
var reload_bars: Array[SlantBar] = []
## Balken der linken Hand (bei einer Waffe: dieser Waffe).
var reload_bar: SlantBar
var reload_label: Label
var crosshair: Crosshair
var hit_marker: HitMarker
## "KOPFSCHUSS!" oder "ELITE ERLEDIGT!" über dem Fadenkreuz.
var kill_label: Label
## Plakette des Interaktions-Hinweises (unsichtbar bei leerem Text).
var prompt_panel: PanelContainer
var prompt_label: Label
## Kopfzeile der Buff-Anzeige links: "BUFFS · TAB: RUCKSACK".
var buff_header: Label
## Behälter der Buff-Zeilen: je aktivem Bonus ein Kind "Buff_<key>" (siehe buff_entries).
var buff_rows: Control
## Plakette der Banner-Meldung (unsichtbar, wenn keine läuft).
var banner_panel: PanelContainer
var banner_label: Label
## Behälter des Countdowns zwischen den Wellen.
var countdown_box: Control
var countdown_title: Label
var countdown_label: Label
## Roter Rand bei Schaden und bei wenig Leben.
var vignette: TextureRect
## FPS-Anzeige unten in der Mitte (nur sichtbar, wenn in den Einstellungen eingeschaltet).
var fps_label: FpsLabel

var _center: Control
var _time: float = 0.0
var _wave: int = 0
var _shown_points: int = 0
var _pending_gain: int = 0
var _gain_label: Label
var _gain_value: int = 0
var _gain_left: float = 0.0
var _gain_lane: int = 0
var _hp: float = Balance.PLAYER_MAX_HP
var _max_hp: float = Balance.PLAYER_MAX_HP
var _low_hp: bool = false
var _damage_flash: float = 0.0
## Stand von Schild und Ausweichsprüngen (0 = nicht vorhanden).
var _shield: float = 0.0
var _max_shield: float = 0.0
var _dash_charges: int = 0
var _max_dash_charges: int = 0
var _revive_charges: int = 0
var _max_revive_charges: int = 0
var _shield_tween: Tween
## Zahl der gezeigten Hände (1 oder 2) und ihr Stand, je Hand ein Eintrag.
var _hand_count: int = 1
var _hand_ids: Array[String] = [WeaponDefs.START_WEAPON, ""]
var _hand_mag: Array[int] = [0, 0]
var _hand_size: Array[int] = [1, 1]
var _hand_reloading: Array[bool] = [false, false]
var _hand_reload_left: Array[float] = [0.0, 0.0]
var _hand_reload_duration: Array[float] = [1.0, 1.0]
var _banner_queue: Array[String] = []
var _banner_active: bool = false
var _banner_tween: Tween
var _recent_banners: Array[Dictionary] = []
var _health_tween: Tween
var _kill_tween: Tween


func _ready() -> void:
	layer = LAYER
	_build()
	_connect_events()
	_reset()


func _process(delta: float) -> void:
	_time += delta
	_gain_left = maxf(_gain_left - delta, 0.0)
	_flush_point_gain()
	_tick_reload(delta)
	_tick_vignette(delta)
	if reload_hint_label.visible:
		reload_hint_label.modulate.a = 0.6 + 0.4 * sin(_time * 11.0)
	if _low_hp:
		health_label.modulate.a = 0.7 + 0.3 * sin(_time * 9.0)


## Stellt eine Banner-Meldung in die Warteschlange. Meldungen laufen nacheinander, nie
## übereinander. Eine gleiche Meldung kurz hintereinander wird nur einmal gezeigt.
## dedupe_key: Enthält eine andere Meldung der letzten Sekunden diesen Text, gilt sie als gleich
## (ein fremdes Modul meldet dasselbe Ereignis mit eigenen Worten). Zwei Meldungen mit demselben
## Schlüssel gelten nur bei gleichem Text als gleich: Bronze- und Gold-Kiste laufen beide.
func show_banner(text: String, dedupe_key: String = "") -> void:
	var clean: String = text.strip_edges()
	if clean.is_empty():
		return
	var lower: String = clean.to_lower()
	var key: String = dedupe_key.strip_edges().to_lower()
	if _is_duplicate_banner(lower, key):
		return
	_recent_banners.append({"text": lower, "key": key, "time": Time.get_ticks_msec()})
	_banner_queue.append(clean)
	while _banner_queue.size() > BANNER_MAX_QUEUE:
		_banner_queue.pop_front()
	if not _banner_active:
		_show_next_banner()


## Läuft gerade eine Banner-Meldung?
func is_banner_active() -> bool:
	return _banner_active


## Wie viele Banner-Meldungen warten noch (ohne die gerade gezeigte)?
func get_banner_queue_size() -> int:
	return _banner_queue.size()


# --- Aufbau ---------------------------------------------------------------------------

func _build() -> void:
	root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_vignette()
	_build_wave_box()
	_build_points()
	_build_health()
	_build_weapon()
	_build_center()
	_build_prompt()
	_build_buff_bar()
	_build_countdown()
	_build_banner()
	_build_fps()


func _build_vignette() -> void:
	var gradient: Gradient = Gradient.new()
	# Die Bildmitte bleibt frei: Das Rot beginnt erst im äußeren Drittel, damit man auch mit
	# wenig Leben noch sieht, worauf man schießt.
	gradient.offsets = PackedFloat32Array([0.0, 0.66, 0.85, 1.0])
	gradient.colors = PackedColorArray([Color(0.9, 0.0, 0.0, 0.0), Color(0.9, 0.0, 0.0, 0.0),
			Color(0.95, 0.0, 0.03, 0.4), Color(1.0, 0.0, 0.05, 0.95)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	vignette = TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = texture
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.visible = false
	root.add_child(vignette)


func _build_wave_box() -> void:
	var plate: Panel = make_plate(COL_PINK, COL_YELLOW, 4)
	plate.name = "WavePlate"
	anchor_box(plate, Vector2.ZERO, Vector2(MARGIN, 16.0), Vector2(236.0, 58.0))
	root.add_child(plate)
	wave_label = make_label("SHOWSTART", 34, COL_YELLOW, true)
	wave_label.name = "Wave"
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	anchor_box(wave_label, Vector2.ZERO, Vector2(MARGIN, 14.0), Vector2(236.0, 58.0))
	root.add_child(wave_label)
	var sub_plate: Panel = make_plate(COL_PANEL, COL_INK, 3)
	sub_plate.name = "ZombiesPlate"
	anchor_box(sub_plate, Vector2.ZERO, Vector2(MARGIN - 2.0, 82.0), Vector2(236.0, 34.0))
	root.add_child(sub_plate)
	zombies_label = make_label("", 18, COL_WHITE)
	zombies_label.name = "Zombies"
	zombies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zombies_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zombies_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	anchor_box(zombies_label, Vector2.ZERO, Vector2(MARGIN - 2.0, 81.0), Vector2(236.0, 34.0))
	root.add_child(zombies_label)


func _build_points() -> void:
	var tag_plate: Panel = make_plate(COL_CYAN, COL_INK, 3)
	tag_plate.name = "PointsTagPlate"
	anchor_box(tag_plate, Vector2(1.0, 0.0), Vector2(-MARGIN - 124.0, 14.0), Vector2(124.0, 28.0))
	root.add_child(tag_plate)
	var tag: Label = make_label("PUNKTE", 16, COL_WHITE, true)
	tag.name = "PointsTag"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	anchor_box(tag, Vector2(1.0, 0.0), Vector2(-MARGIN - 124.0, 13.0), Vector2(124.0, 28.0))
	root.add_child(tag)
	points_label = make_label("0", 54, COL_YELLOW, true)
	points_label.name = "Points"
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	points_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	points_label.pivot_offset_ratio = Vector2(1.0, 0.5)
	anchor_box(points_label, Vector2(1.0, 0.0), Vector2(-MARGIN - 400.0, 40.0), Vector2(400.0, 66.0))
	root.add_child(points_label)
	_build_material()
	floaters = Control.new()
	floaters.name = "Floaters"
	floaters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Die schwebenden Zahlen beginnen unter der Zeile mit dem Material.
	anchor_box(floaters, Vector2(1.0, 0.0), Vector2(-MARGIN - 400.0, MATERIAL_ROW_TOP + MATERIAL_ROW_SIZE.y + 2.0), Vector2(400.0, 90.0))
	root.add_child(floaters)


## Material klein unter den Punkten: von links "+2" (nur kurz), Zahnrad, "MATERIAL 3".
func _build_material() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "MaterialRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	anchor_box(row, Vector2(1.0, 0.0), Vector2(-MARGIN - MATERIAL_ROW_SIZE.x, MATERIAL_ROW_TOP), MATERIAL_ROW_SIZE)
	root.add_child(row)
	material_gain_label = make_label("", MATERIAL_FONT_SIZE, COL_GREEN, true)
	material_gain_label.name = "MaterialGain"
	material_gain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	material_gain_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	material_gain_label.modulate.a = 0.0
	row.add_child(material_gain_label)
	material_icon = MaterialIcon.new()
	material_icon.name = "MaterialIcon"
	material_icon.color = MATERIAL_COLOR
	material_icon.custom_minimum_size = Vector2(MATERIAL_ICON_SIZE, MATERIAL_ICON_SIZE)
	material_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(material_icon)
	material_label = make_label("MATERIAL 0", MATERIAL_FONT_SIZE, MATERIAL_COLOR, true)
	material_label.name = "Material"
	material_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	material_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	material_label.pivot_offset_ratio = Vector2(1.0, 0.5)
	row.add_child(material_label)


func _build_health() -> void:
	var tag: Label = make_label("LEBEN", 15, COL_WHITE, true)
	tag.name = "HealthTag"
	anchor_box(tag, Vector2(0.0, 1.0), Vector2(MARGIN + 6.0, -128.0), Vector2(120.0, 22.0))
	root.add_child(tag)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "HealthRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	anchor_box(row, Vector2(0.0, 1.0), Vector2(MARGIN + 4.0, -112.0), Vector2(300.0, 56.0))
	root.add_child(row)
	health_label = make_label("100", 46, COL_GREEN, true)
	health_label.name = "Health"
	health_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(health_label)
	health_max_label = make_label("/ 100", 22, COL_WHITE, true)
	health_max_label.name = "HealthMax"
	health_max_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(health_max_label)
	health_bar = SlantBar.new()
	health_bar.name = "HealthBar"
	health_bar.slant = 12.0
	anchor_box(health_bar, Vector2(0.0, 1.0), Vector2(MARGIN, -54.0), Vector2(340.0, 32.0))
	root.add_child(health_bar)
	_build_shield()
	_build_dash()
	_build_revive()


## Schild-Anzeige: Zahl rechts über dem Lebensbalken, schmaler Balken direkt darunter. Der
## Behälter deckt die Fläche der Lebensanzeige, seine Kinder liegen relativ zu ihm.
func _build_shield() -> void:
	shield_box = Control.new()
	shield_box.name = "Shield"
	shield_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_box(shield_box, Vector2(0.0, 1.0), Vector2(MARGIN, -128.0), Vector2(340.0, 122.0))
	shield_box.visible = false
	root.add_child(shield_box)
	var tag: Label = make_label("SCHILD", 15, SHIELD_COLOR, true)
	tag.name = "ShieldTag"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	anchor_box(tag, Vector2.ZERO, Vector2(196.0, 8.0), Vector2(136.0, 22.0))
	shield_box.add_child(tag)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ShieldRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	anchor_box(row, Vector2.ZERO, Vector2(176.0, 30.0), Vector2(156.0, 42.0))
	shield_box.add_child(row)
	shield_label = make_label("0", 28, SHIELD_COLOR, true)
	shield_label.name = "Shield"
	shield_label.size_flags_vertical = Control.SIZE_SHRINK_END
	shield_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	row.add_child(shield_label)
	shield_max_label = make_label("/ 0", 16, COL_WHITE, true)
	shield_max_label.name = "ShieldMax"
	shield_max_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(shield_max_label)
	# Der Balken setzt die schräge Kante des Lebensbalkens nach unten fort.
	shield_bar = SlantBar.new()
	shield_bar.name = "ShieldBar"
	shield_bar.slant = 5.0
	shield_bar.border = 3.0
	shield_bar.fill_color = SHIELD_COLOR
	anchor_box(shield_bar, Vector2.ZERO, Vector2(-5.0, 108.0), Vector2(333.0, 14.0))
	shield_box.add_child(shield_bar)


## Ausweichsprünge: Taste und je Sprung ein Kästchen, rechts neben dem Lebensbalken.
func _build_dash() -> void:
	dash_box = Control.new()
	dash_box.name = "Dash"
	dash_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_box(dash_box, Vector2(0.0, 1.0), Vector2(MARGIN + 352.0, -54.0), Vector2(200.0, 32.0))
	dash_box.visible = false
	root.add_child(dash_box)
	var key: Label = make_label(DASH_KEY_TEXT, 20, COL_YELLOW, true)
	key.name = "DashKey"
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	anchor_box(key, Vector2.ZERO, Vector2(0.0, 0.0), Vector2(24.0, 32.0))
	dash_box.add_child(key)
	dash_pips = Pips.new()
	dash_pips.name = "DashPips"
	dash_pips.max_level = 0
	dash_pips.fill_color = COL_YELLOW
	dash_pips.pivot_offset_ratio = Vector2(0.0, 0.5)
	anchor_box(dash_pips, Vector2.ZERO, Vector2(28.0, 9.0), DASH_PIP_SIZE)
	dash_box.add_child(dash_pips)


## Ladungen der Zweiten Staffel: Schriftzug und je Ladung ein Kästchen, über der Sprung-Anzeige.
func _build_revive() -> void:
	revive_box = Control.new()
	revive_box.name = "Revive"
	revive_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_box(revive_box, Vector2(0.0, 1.0), Vector2(MARGIN + 352.0, -90.0), Vector2(260.0, 32.0))
	revive_box.visible = false
	root.add_child(revive_box)
	var tag: Label = make_label(REVIVE_TAG_TEXT, 14, REVIVE_COLOR, true)
	tag.name = "ReviveTag"
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	anchor_box(tag, Vector2.ZERO, Vector2(0.0, 0.0), Vector2(88.0, 32.0))
	revive_box.add_child(tag)
	revive_pips = Pips.new()
	revive_pips.name = "RevivePips"
	revive_pips.max_level = 0
	revive_pips.fill_color = REVIVE_COLOR
	revive_pips.pivot_offset_ratio = Vector2(0.0, 0.5)
	anchor_box(revive_pips, Vector2.ZERO, Vector2(92.0, 9.0), DASH_PIP_SIZE)
	revive_box.add_child(revive_pips)


func _build_weapon() -> void:
	low_ammo_label = make_label("WENIG MUNITION", 18, COL_ORANGE, true)
	low_ammo_label.name = "LowAmmo"
	low_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	low_ammo_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	anchor_box(low_ammo_label, Vector2(1.0, 1.0), Vector2(-MARGIN - 440.0, -158.0), Vector2(440.0, 26.0))
	low_ammo_label.visible = false
	root.add_child(low_ammo_label)
	for index: int in HUD_HANDS:
		var box: Control = Control.new()
		box.name = "Hand%d" % index
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor_box(box, Vector2(1.0, 1.0), Vector2(-MARGIN - HAND_BOX_WIDTH_ONE, -HAND_BOX_HEIGHT - 20.0),
				Vector2(HAND_BOX_WIDTH_ONE, HAND_BOX_HEIGHT))
		root.add_child(box)
		hand_boxes.append(box)
		var side: Label = make_label(HAND_SIDE_TEXTS[index], 12, COL_WHITE, true)
		side.name = "Side"
		side.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		side.modulate.a = 0.75
		box.add_child(side)
		var name_label: Label = make_label("", 22, COL_CYAN, true)
		name_label.name = "Name"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_label.pivot_offset_ratio = Vector2(1.0, 0.5)
		box.add_child(name_label)
		var row: HBoxContainer = HBoxContainer.new()
		row.name = "AmmoRow"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var ammo: Label = make_label("0", 60, COL_WHITE, true)
		ammo.name = "Ammo"
		ammo.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(ammo)
		var magazine: Label = make_label("/ 0", 30, COL_WHITE, true)
		magazine.name = "Magazine"
		magazine.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(magazine)
	weapon_label = hand_boxes[0].get_node("Name") as Label
	ammo_label = hand_boxes[0].get_node("AmmoRow/Ammo") as Label
	magazine_label = hand_boxes[0].get_node("AmmoRow/Magazine") as Label


func _build_center() -> void:
	_center = Control.new()
	_center.name = "Center"
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_box(_center, Vector2(0.5, 0.5), Vector2.ZERO, Vector2.ZERO)
	root.add_child(_center)
	crosshair = Crosshair.new()
	crosshair.name = "Crosshair"
	_center.add_child(crosshair)
	hit_marker = HitMarker.new()
	hit_marker.name = "HitMarker"
	_center.add_child(hit_marker)
	kill_label = make_label("", 24, COL_YELLOW, true)
	kill_label.name = "KillText"
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kill_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	anchor_box(kill_label, Vector2.ZERO, Vector2(-200.0, -96.0), Vector2(400.0, 34.0))
	kill_label.visible = false
	_center.add_child(kill_label)
	for index: int in HUD_HANDS:
		var bar: SlantBar = SlantBar.new()
		bar.name = "ReloadBar" if index == 0 else "ReloadBar%d" % index
		bar.slant = 6.0
		bar.border = 3.0
		bar.fill_color = COL_CYAN
		anchor_box(bar, Vector2.ZERO, Vector2(-93.0, 44.0), Vector2(192.0, 16.0))
		bar.visible = false
		_center.add_child(bar)
		reload_bars.append(bar)
	reload_bar = reload_bars[0]
	reload_label = make_label("LÄDT NACH", 15, COL_CYAN, true)
	reload_label.name = "ReloadText"
	reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anchor_box(reload_label, Vector2.ZERO, Vector2(-150.0, 62.0), Vector2(300.0, 22.0))
	reload_label.visible = false
	_center.add_child(reload_label)
	reload_hint_label = make_label("NACHLADEN [%s]" % RELOAD_KEY_TEXT, 24, COL_YELLOW, true)
	reload_hint_label.name = "ReloadHint"
	reload_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anchor_box(reload_hint_label, Vector2.ZERO, Vector2(-220.0, 46.0), Vector2(440.0, 34.0))
	reload_hint_label.visible = false
	_center.add_child(reload_hint_label)


func _build_prompt() -> void:
	prompt_panel = PanelContainer.new()
	prompt_panel.name = "Prompt"
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBoxFlat = make_box(COL_PANEL, COL_CYAN, 4, PLATE_SKEW, 6)
	box.content_margin_left = 26.0
	box.content_margin_right = 26.0
	box.content_margin_top = 5.0
	box.content_margin_bottom = 7.0
	prompt_panel.add_theme_stylebox_override("panel", box)
	prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_panel.pivot_offset_ratio = Vector2(0.5, 0.5)
	anchor_box(prompt_panel, Vector2(0.5, 1.0), Vector2(0.0, -112.0), Vector2.ZERO)
	prompt_panel.visible = false
	root.add_child(prompt_panel)
	prompt_label = make_label("", 24, COL_WHITE)
	prompt_label.name = "Label"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)


func _build_buff_bar() -> void:
	var holder: Control = Control.new()
	holder.name = "BuffBar"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows_height: float = BUFF_ROW_STEP * float(BUFF_MAX_ROWS)
	anchor_box(holder, Vector2.ZERO, Vector2(MARGIN - 4.0, 132.0), Vector2(BUFF_ROW_SIZE.x, 24.0 + rows_height))
	root.add_child(holder)
	buff_header = make_label("BUFFS · TAB: RUCKSACK", 14, COL_CYAN, true)
	buff_header.name = "Header"
	anchor_box(buff_header, Vector2.ZERO, Vector2(8.0, 0.0), Vector2(230.0, 22.0))
	holder.add_child(buff_header)
	buff_rows = Control.new()
	buff_rows.name = "Rows"
	buff_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_box(buff_rows, Vector2.ZERO, Vector2(0.0, 24.0), Vector2(BUFF_ROW_SIZE.x, rows_height))
	holder.add_child(buff_rows)


func _build_countdown() -> void:
	countdown_box = Control.new()
	countdown_box.name = "Countdown"
	countdown_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_box(countdown_box, Vector2(0.5, 0.0), Vector2(-200.0, 8.0), Vector2(400.0, 100.0))
	countdown_box.visible = false
	root.add_child(countdown_box)
	countdown_title = make_label("NÄCHSTE WELLE IN", 18, COL_WHITE, true)
	countdown_title.name = "Title"
	countdown_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anchor_box(countdown_title, Vector2.ZERO, Vector2(0.0, 0.0), Vector2(400.0, 26.0))
	countdown_box.add_child(countdown_title)
	countdown_label = make_label("", 58, COL_YELLOW, true)
	countdown_label.name = "Seconds"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	anchor_box(countdown_label, Vector2.ZERO, Vector2(100.0, 20.0), Vector2(200.0, 76.0))
	countdown_box.add_child(countdown_label)


func _build_fps() -> void:
	fps_label = FpsLabel.new()
	fps_label.name = "Fps"
	style_label(fps_label, 16, COL_GREEN)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	anchor_box(fps_label, Vector2(0.5, 1.0), Vector2(-70.0, -32.0), Vector2(140.0, 24.0))
	root.add_child(fps_label)


func _build_banner() -> void:
	banner_panel = make_headline("", BANNER_FONT_SIZE, COL_PINK, COL_YELLOW, COL_YELLOW)
	banner_panel.name = "Banner"
	banner_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_panel.pivot_offset_ratio = Vector2(0.5, 0.5)
	banner_panel.rotation_degrees = -2.0
	anchor_box(banner_panel, Vector2(0.5, 0.0), Vector2(0.0, 118.0), Vector2.ZERO)
	banner_panel.visible = false
	var holder: BannerHolder = BannerHolder.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	holder.add_child(banner_panel)
	banner_label = banner_panel.get_node("Label") as Label
	banner_label.uppercase = true


func _connect_events() -> void:
	Events.run_started.connect(_on_run_started)
	Events.game_over.connect(_on_game_over)
	Events.points_changed.connect(_on_points_changed)
	Events.materials_changed.connect(_on_materials_changed)
	Events.banner.connect(_on_banner)
	Events.wave_started.connect(_on_wave_started)
	Events.wave_cleared.connect(_on_wave_cleared)
	Events.intermission_tick.connect(_on_intermission_tick)
	Events.zombies_left_changed.connect(_on_zombies_left_changed)
	Events.player_health_changed.connect(_on_player_health_changed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_shield_changed.connect(_on_player_shield_changed)
	Events.dash_charges_changed.connect(_on_dash_charges_changed)
	Events.revive_charges_changed.connect(_on_revive_charges_changed)
	Events.cameras_changed.connect(_on_cameras_changed)
	Events.loadout_changed.connect(_on_loadout_changed)
	Events.hand_ammo_changed.connect(_on_hand_ammo_changed)
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.hand_reload_started.connect(_on_hand_reload_started)
	Events.hand_reload_finished.connect(_on_hand_reload_finished)
	Events.bullet_hit.connect(_on_bullet_hit)
	Events.zombie_killed.connect(_on_zombie_killed)
	Events.upgrade_chosen.connect(_on_upgrade_chosen)
	Events.build_changed.connect(_on_build_changed)
	Events.synergy_unlocked.connect(_on_synergy_unlocked)
	Events.interact_prompt_changed.connect(_on_interact_prompt_changed)
	Events.chest_dropped.connect(_on_chest_dropped)


# --- Zustand auf Anfang ---------------------------------------------------------------

func _reset() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_queue.clear()
	_recent_banners.clear()
	_banner_active = false
	banner_panel.visible = false
	for floater: Node in floaters.get_children():
		floaters.remove_child(floater)
		floater.queue_free()
	_pending_gain = 0
	_gain_label = null
	_gain_value = 0
	_gain_left = 0.0
	_shown_points = Game.points
	points_label.text = format_int(_shown_points)
	_set_material(Game.materials, 0)
	_wave = 0
	wave_label.text = "SHOWSTART"
	_set_zombies_text("GLEICH GEHT'S LOS", COL_WHITE)
	countdown_box.visible = false
	prompt_panel.visible = false
	prompt_label.text = ""
	_damage_flash = 0.0
	vignette.visible = false
	_stop_reload()
	hit_marker.clear()
	kill_label.visible = false
	_center.visible = true
	_pull_player_state()
	_rebuild_buffs()


## Holt Leben, Schild, Ausweichsprünge und Waffen vom Spieler. Ohne Spieler gelten die
## Startwerte (kein Schild, keine Sprünge).
func _pull_player_state() -> void:
	var hp: float = Balance.PLAYER_MAX_HP
	var max_hp: float = Balance.PLAYER_MAX_HP
	var shield: float = 0.0
	var max_shield: float = 0.0
	var charges: int = 0
	var max_charges: int = 0
	var revives: int = 0
	var max_revives: int = 0
	if is_instance_valid(Game.player):
		var player: Node3D = Game.player
		var player_max: Variant = player.get("max_hp")
		var player_hp: Variant = player.get("hp")
		if (player_max is float or player_max is int) and float(player_max) > 0.0:
			max_hp = float(player_max)
			if player_hp is float or player_hp is int:
				hp = float(player_hp)
		var player_max_shield: Variant = player.get("max_shield")
		var player_shield: Variant = player.get("shield")
		if (player_max_shield is float or player_max_shield is int) and float(player_max_shield) > 0.0:
			max_shield = float(player_max_shield)
			if player_shield is float or player_shield is int:
				shield = float(player_shield)
		var player_max_charges: Variant = player.get("max_dash_charges")
		var player_charges: Variant = player.get("dash_charges")
		if (player_max_charges is int or player_max_charges is float) and int(player_max_charges) > 0:
			max_charges = int(player_max_charges)
			if player_charges is int or player_charges is float:
				charges = int(player_charges)
		# Zweite Staffel: Hat der Spieler die Ladungen als Eigenschaften, gelten sie sofort.
		# Sonst kommt der Stand mit Events.revive_charges_changed.
		var player_max_revives: Variant = player.get("max_revive_charges")
		var player_revives: Variant = player.get("revive_charges")
		if (player_max_revives is int or player_max_revives is float) and int(player_max_revives) > 0:
			max_revives = int(player_max_revives)
			if player_revives is int or player_revives is float:
				revives = int(player_revives)
	_set_health(hp, max_hp, false)
	_set_shield(shield, max_shield, false)
	_set_dash(charges, max_charges, false)
	_set_revive(revives, max_revives, false)
	_set_weapon(_read_hands(), false)


## Die gehaltenen Waffen, je Hand ein Eintrag wie in WeaponController.get_hands(). Ohne Spieler
## (oder ohne dessen Waffensteuerung) gilt Game.loadout mit vollen Magazinen.
func _read_hands() -> Array[Dictionary]:
	var hands: Array[Dictionary] = []
	if is_instance_valid(Game.player) and Game.player.has_method("get_weapon_controller"):
		var controller: Node = Game.player.call("get_weapon_controller") as Node
		if is_instance_valid(controller) and controller.has_method("get_hands"):
			for entry: Variant in controller.call("get_hands") as Array:
				if entry is Dictionary and WeaponDefs.has(str((entry as Dictionary).get("id", ""))):
					hands.append(entry as Dictionary)
	if hands.is_empty():
		for weapon: Dictionary in Game.loadout:
			var id: String = str(weapon.get("id", ""))
			if WeaponDefs.has(id):
				var magazine: int = int(WeaponDefs.get_def(id).get("magazine", 0))
				hands.append({"id": id, "mag": magazine, "magazine": magazine, "reloading": false})
	if hands.is_empty():
		var start_magazine: int = int(WeaponDefs.get_def(WeaponDefs.START_WEAPON).get("magazine", 0))
		hands.append({"id": WeaponDefs.START_WEAPON, "mag": start_magazine, "magazine": start_magazine, "reloading": false})
	return hands


# --- Punkte ---------------------------------------------------------------------------

func _on_points_changed(total: int) -> void:
	var delta: int = total - _shown_points
	_shown_points = total
	points_label.text = format_int(total)
	if delta > 0:
		_pending_gain += delta
	elif delta < 0:
		_spawn_spend_floater(-delta)
		pop(points_label, 0.82, 0.22)


## Zeigt die Gewinne als schwebende Zahl unter dem Punktestand. Alle Gewinne eines Bildes und
## alle, die kurz aufeinander folgen, zählt dieselbe Anzeige zusammen (Schrot: "+80", Dauerfeuer:
## eine wachsende Zahl statt eines Zahlensalats).
func _flush_point_gain() -> void:
	if _pending_gain <= 0:
		return
	var gain: int = _pending_gain
	_pending_gain = 0
	if is_instance_valid(_gain_label) and _gain_left > 0.0:
		_gain_value += gain
	else:
		_gain_value = gain
		_gain_lane = (_gain_lane + 1) % 2
		_gain_label = _make_floater(Vector2(-200.0 - 120.0 * float(_gain_lane), 2.0))
	_gain_left = GAIN_COMBO_WINDOW
	var big: bool = _gain_value >= Balance.POINTS_ELITE_KILL
	var color: Color = COL_GREEN
	if big:
		color = COL_YELLOW
	elif _gain_value <= Balance.POINTS_BULLET_HIT:
		color = COL_WHITE
	_gain_label.text = "+%s" % format_int(_gain_value)
	style_label(_gain_label, 34 if big else 26, color, true)
	_run_floater(_gain_label, GAIN_COMBO_WINDOW, -30.0)
	pop(points_label, 1.28 if gain >= Balance.POINTS_ELITE_KILL else 1.14, 0.2)


## Material hat sich geändert (Events.materials_changed): neuer Stand und Änderung.
func _on_materials_changed(total: int, delta: int) -> void:
	_set_material(total, delta)


## Zeigt den Stand des Materials. Bei einem Zuwachs steht kurz "+2" daneben und die Zahl ploppt,
## bei delta 0 (neuer Lauf) verschwindet ein altes "+2" sofort.
func _set_material(total: int, delta: int) -> void:
	material_label.text = "MATERIAL %s" % format_int(total)
	kill_tween(material_gain_label, "gain_tween")
	if delta <= 0:
		material_gain_label.modulate.a = 0.0
		if delta < 0:
			pop(material_label, 0.85, 0.2)
		return
	material_gain_label.text = "+%s" % format_int(delta)
	material_gain_label.modulate.a = 1.0
	pop(material_label, 1.3, 0.25)
	if not is_inside_tree():
		return
	var tween: Tween = material_gain_label.create_tween()
	tween.tween_interval(MATERIAL_GAIN_HOLD)
	tween.tween_property(material_gain_label, "modulate:a", 0.0, MATERIAL_GAIN_FADE)
	material_gain_label.set_meta("gain_tween", tween)


func _spawn_spend_floater(amount: int) -> void:
	var label: Label = _make_floater(Vector2(-200.0, 40.0))
	label.text = "−%s" % format_int(amount)
	style_label(label, 28, COL_RED, true)
	_run_floater(label, 0.45, 26.0)


func _make_floater(offset: Vector2) -> Label:
	while floaters.get_child_count() >= FLOATER_MAX:
		var oldest: Node = floaters.get_child(0)
		floaters.remove_child(oldest)
		oldest.queue_free()
	var label: Label = make_label("", 26, COL_WHITE, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.pivot_offset_ratio = Vector2(1.0, 0.5)
	anchor_box(label, Vector2(1.0, 0.0), offset, Vector2(200.0, 40.0))
	label.set_meta("rest_top", offset.y)
	floaters.add_child(label)
	return label


## Lässt eine schwebende Zahl aufploppen, kurz stehen und dann wegziehen und verblassen.
## Ein erneuter Aufruf (die Zahl ist gewachsen) beginnt von vorn.
func _run_floater(label: Label, hold: float, drift: float) -> void:
	kill_tween(label, "float_tween")
	var rest_top: float = float(label.get_meta("rest_top", 0.0))
	label.position.y = rest_top
	label.modulate.a = 1.0
	label.scale = Vector2(1.45, 1.45)
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(maxf(hold - 0.16, 0.0))
	tween.tween_property(label, "position:y", rest_top + drift, FLOATER_FADE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(label, "modulate:a", 0.0, FLOATER_FADE_TIME)
	tween.tween_callback(label.queue_free)
	label.set_meta("float_tween", tween)


# --- Welle ----------------------------------------------------------------------------

func _on_wave_started(wave: int, total_zombies: int) -> void:
	_wave = wave
	wave_label.text = "WELLE %d" % wave
	pop(wave_label, 1.5, 0.35)
	_set_zombies_left(total_zombies)
	countdown_box.visible = false


func _on_wave_cleared(_wave_number: int) -> void:
	_set_zombies_text("GESCHAFFT!", COL_GREEN)
	pop(zombies_label, 1.4, 0.3)


func _on_zombies_left_changed(left: int) -> void:
	_set_zombies_left(left)
	pop(zombies_label, 1.12, 0.14)


func _set_zombies_left(left: int) -> void:
	var count: int = maxi(left, 0)
	var text: String = "NOCH 1 ZOMBIE" if count == 1 else "NOCH %d ZOMBIES" % count
	_set_zombies_text(text, COL_YELLOW if count <= 3 else COL_WHITE)


func _set_zombies_text(text: String, color: Color) -> void:
	zombies_label.text = text
	zombies_label.add_theme_color_override("font_color", color)


func _on_intermission_tick(seconds_left: int) -> void:
	if seconds_left <= 0:
		countdown_box.visible = false
		return
	countdown_title.text = "DIE SHOW BEGINNT IN" if _wave <= 0 else "NÄCHSTE WELLE IN"
	countdown_label.text = str(seconds_left)
	countdown_label.add_theme_color_override("font_color", COL_RED if seconds_left <= 3 else COL_YELLOW)
	countdown_box.visible = true
	pop(countdown_label, 1.45 if seconds_left <= 3 else 1.2, 0.25)


# --- Leben ----------------------------------------------------------------------------

func _on_player_health_changed(hp: float, max_hp: float) -> void:
	_set_health(hp, max_hp, true)


func _on_player_damaged(amount: float) -> void:
	_damage_flash = clampf(_damage_flash + 0.45 + amount / 60.0, 0.0, 1.0)
	pop(health_label, 1.35, 0.25)


func _set_health(hp: float, max_hp: float, animate: bool) -> void:
	var old_ratio: float = health_bar.ratio
	_max_hp = maxf(max_hp, 1.0)
	_hp = clampf(hp, 0.0, _max_hp)
	var ratio: float = _hp / _max_hp
	var color: Color = health_color(ratio)
	health_label.text = str(ceili(_hp))
	health_label.add_theme_color_override("font_color", color)
	health_max_label.text = "/ %d" % roundi(_max_hp)
	_low_hp = _hp > 0.0 and ratio <= LOW_HP_RATIO
	if not _low_hp:
		health_label.modulate.a = 1.0
	health_bar.fill_color = color
	if _health_tween != null and _health_tween.is_valid():
		_health_tween.kill()
	if not animate or not is_inside_tree():
		health_bar.ratio = ratio
		health_bar.ghost_ratio = ratio
		return
	if ratio < old_ratio:
		# Verlust: Füllung springt, der helle Rest läuft nach.
		health_bar.ghost_ratio = maxf(health_bar.ghost_ratio, old_ratio)
		health_bar.ratio = ratio
		_health_tween = create_tween()
		_health_tween.tween_interval(0.25)
		_health_tween.tween_property(health_bar, "ghost_ratio", ratio, 0.4)
	else:
		health_bar.ghost_ratio = 0.0
		_health_tween = create_tween()
		_health_tween.tween_property(health_bar, "ratio", ratio, 0.25) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if ratio - old_ratio >= 0.04:
			pop(health_label, 1.2, 0.2)


# --- Schild und Ausweichsprünge -------------------------------------------------------

func _on_player_shield_changed(shield: float, max_shield: float) -> void:
	_set_shield(shield, max_shield, true)


func _on_dash_charges_changed(charges: int, max_charges: int) -> void:
	_set_dash(charges, max_charges, true)


## Zeigt das Schild: Zahl, Höchstwert und Balken. Ohne Schild (max_shield <= 0) ist die Anzeige aus.
func _set_shield(shield: float, max_shield: float, animate: bool) -> void:
	var old_ratio: float = shield_bar.ratio
	var was_visible: bool = shield_box.visible
	_max_shield = maxf(max_shield, 0.0)
	_shield = clampf(shield, 0.0, _max_shield)
	if _shield_tween != null and _shield_tween.is_valid():
		_shield_tween.kill()
	shield_box.visible = _max_shield > 0.0
	if not shield_box.visible:
		shield_bar.ratio = 0.0
		shield_bar.ghost_ratio = 0.0
		return
	var ratio: float = _shield / _max_shield
	# Angebrochene Punkte zählen erst voll, wenn sie geladen sind (beim Leben wird aufgerundet,
	# weil 0 dort den Tod bedeutet).
	shield_label.text = str(floori(_shield + 0.001))
	shield_max_label.text = "/ %d" % roundi(_max_shield)
	# Ein leeres Schild steht blass da.
	shield_label.modulate.a = 1.0 if _shield >= 1.0 else 0.55
	shield_bar.ratio = ratio
	if animate and was_visible and is_inside_tree() and ratio < old_ratio:
		# Verlust: Füllung springt, der helle Rest läuft nach (wie beim Leben).
		shield_bar.ghost_ratio = maxf(shield_bar.ghost_ratio, old_ratio)
		_shield_tween = create_tween()
		_shield_tween.tween_interval(0.25)
		_shield_tween.tween_property(shield_bar, "ghost_ratio", ratio, 0.4)
		pop(shield_label, 1.3, 0.2)
	else:
		shield_bar.ghost_ratio = 0.0


## Zeigt die Ausweichsprünge: je Sprung ein Kästchen, gefüllt wenn verfügbar. Ohne Notausgang
## (max_charges <= 0) ist die Anzeige aus.
func _set_dash(charges: int, max_charges: int, animate: bool) -> void:
	var old_charges: int = _dash_charges
	var was_visible: bool = dash_box.visible
	_max_dash_charges = maxi(max_charges, 0)
	_dash_charges = clampi(charges, 0, _max_dash_charges)
	dash_box.visible = _max_dash_charges > 0
	dash_pips.max_level = _max_dash_charges
	dash_pips.level = _dash_charges
	_layout_abilities()
	if not dash_box.visible:
		return
	var gap: float = maxf(2.0, DASH_PIP_SIZE.y * 0.3)
	var width: float = DASH_PIP_SIZE.x * float(_max_dash_charges) + gap * float(_max_dash_charges - 1)
	dash_pips.offset_right = dash_pips.offset_left + width
	dash_pips.queue_redraw()
	# Ein Sprung ist wieder da: kurz aufploppen.
	if animate and was_visible and _dash_charges > old_charges:
		pop(dash_pips, 1.25, 0.2)


func _on_revive_charges_changed(charges: int, max_charges: int) -> void:
	_set_revive(charges, max_charges, true)


## Zeigt die Ladungen der Zweiten Staffel: je Ladung ein Kästchen, gefüllt wenn sie bereit ist.
## Ohne Zweite Staffel (max_charges <= 0) ist die Anzeige aus.
func _set_revive(charges: int, max_charges: int, animate: bool) -> void:
	var old_charges: int = _revive_charges
	var was_visible: bool = revive_box.visible
	_max_revive_charges = maxi(max_charges, 0)
	_revive_charges = clampi(charges, 0, _max_revive_charges)
	revive_box.visible = _max_revive_charges > 0
	revive_pips.max_level = _max_revive_charges
	revive_pips.level = _revive_charges
	_layout_abilities()
	if not revive_box.visible:
		return
	var gap: float = maxf(2.0, DASH_PIP_SIZE.y * 0.3)
	var width: float = DASH_PIP_SIZE.x * float(_max_revive_charges) + gap * float(_max_revive_charges - 1)
	revive_pips.offset_right = revive_pips.offset_left + width
	revive_pips.queue_redraw()
	# Ohne bereite Ladung steht der Schriftzug blass da.
	(revive_box.get_node("ReviveTag") as Label).modulate.a = 1.0 if _revive_charges > 0 else 0.55
	# Eine Ladung ist wieder da: kurz aufploppen.
	if animate and was_visible and _revive_charges > old_charges:
		pop(revive_pips, 1.25, 0.2)


## Die Zweite Staffel steht über der Sprung-Anzeige. Ohne Notausgang rückt sie an deren Platz
## neben den Lebensbalken.
func _layout_abilities() -> void:
	var top: float = -90.0 if dash_box.visible else -54.0
	revive_box.offset_top = top
	revive_box.offset_bottom = top + 32.0


func _tick_vignette(delta: float) -> void:
	_damage_flash = move_toward(_damage_flash, 0.0, delta * VIGNETTE_FADE_SPEED)
	var alpha: float = _damage_flash
	if _low_hp:
		alpha = maxf(alpha, LOW_HP_VIGNETTE + LOW_HP_VIGNETTE_PULSE * sin(_time * 5.0))
	vignette.visible = alpha > 0.01
	vignette.modulate.a = clampf(alpha, 0.0, 1.0)


# --- Waffe und Munition ---------------------------------------------------------------

## Die Waffensteuerung hat die Hände neu eingerichtet: Anzeige neu aufbauen.
func _on_loadout_changed() -> void:
	_set_weapon(_read_hands(), true)


func _on_hand_ammo_changed(hand: int, mag: int, magazine_size: int) -> void:
	if hand < 0 or hand >= _hand_count:
		return
	var gained: bool = mag > _hand_mag[hand]
	_set_ammo(hand, mag, magazine_size)
	if gained:
		pop(_hand_label(hand, "AmmoRow/Ammo"), 1.25, 0.18)


func _on_weapon_fired(weapon_id: String) -> void:
	var def: Dictionary = WeaponDefs.get_def(weapon_id)
	var pellets: int = int(def.get("pellets", 1))
	crosshair.bump(11.0 if pellets > 1 else 5.0)


func _on_hand_reload_started(hand: int, duration: float) -> void:
	if hand < 0 or hand >= _hand_count:
		return
	_start_reload(hand, duration, duration)
	_update_ammo_hints()


func _on_hand_reload_finished(hand: int) -> void:
	if hand < 0 or hand >= HUD_HANDS:
		return
	_stop_hand_reload(hand)
	_update_ammo_hints()


## Zeigt den Nachladebalken einer Hand: duration ist die ganze Dauer, left der Rest davon.
func _start_reload(hand: int, duration: float, left: float) -> void:
	_hand_reloading[hand] = true
	_hand_reload_duration[hand] = maxf(duration, 0.05)
	_hand_reload_left[hand] = clampf(left, 0.0, _hand_reload_duration[hand])
	reload_bars[hand].ratio = 1.0 - _hand_reload_left[hand] / _hand_reload_duration[hand]
	reload_bars[hand].visible = true
	reload_label.visible = true


func _stop_hand_reload(hand: int) -> void:
	_hand_reloading[hand] = false
	_hand_reload_left[hand] = 0.0
	reload_bars[hand].visible = false
	reload_label.visible = _hand_reloading.has(true)


## Beendet die Nachlade-Anzeige aller Hände.
func _stop_reload() -> void:
	for hand: int in HUD_HANDS:
		_stop_hand_reload(hand)


func _tick_reload(delta: float) -> void:
	for hand: int in HUD_HANDS:
		if not _hand_reloading[hand]:
			continue
		_hand_reload_left[hand] -= delta
		reload_bars[hand].ratio = 1.0 - maxf(_hand_reload_left[hand], 0.0) / _hand_reload_duration[hand]
		if _hand_reload_left[hand] < -RELOAD_GRACE:
			# Kein hand_reload_finished gekommen (Waffe weg, Lauf vorbei): Balken nicht stehen lassen.
			_stop_hand_reload(hand)
			_update_ammo_hints()


## Zeigt die gehaltenen Waffen (je Hand ein Eintrag wie in WeaponController.get_hands()): Namen,
## Magazine und laufendes Nachladen. Bei zwei Waffen bekommt jede Hand ihren eigenen Kasten.
func _set_weapon(hands: Array[Dictionary], animate: bool) -> void:
	var count: int = clampi(hands.size(), 1, HUD_HANDS)
	var changed: bool = count != _hand_count
	_hand_count = count
	_stop_reload()
	var widest_spread: float = 0.0
	for hand: int in HUD_HANDS:
		var entry: Dictionary = hands[hand] if hand < hands.size() else {}
		var id: String = str(entry.get("id", "")) if hand < count else ""
		if id != _hand_ids[hand]:
			changed = true
		_hand_ids[hand] = id
		if id.is_empty():
			_hand_mag[hand] = 0
			_hand_size[hand] = 1
			continue
		var def: Dictionary = WeaponDefs.get_def(id)
		widest_spread = maxf(widest_spread, float(def.get("spread_deg", 0.5)))
		_hand_size[hand] = maxi(int(entry.get("magazine", def.get("magazine", 1))), 1)
		_hand_mag[hand] = int(entry.get("mag", _hand_size[hand]))
		if bool(entry.get("reloading", false)):
			var duration: float = float(entry.get("reload_duration", def.get("reload_time", 1.0)))
			_start_reload(hand, duration, float(entry.get("reload_left", duration)))
	# Das Fadenkreuz richtet sich nach der Waffe mit der größten Streuung.
	crosshair.base_gap = 5.0 + widest_spread * 2.4
	_layout_hands()
	for hand: int in _hand_count:
		_hand_label(hand, "AmmoRow/Ammo").text = str(maxi(_hand_mag[hand], 0))
		_hand_label(hand, "AmmoRow/Magazine").text = "/ %d" % _hand_size[hand]
	_update_ammo_hints()
	if animate and changed:
		for hand: int in _hand_count:
			pop(_hand_label(hand, "Name"), 1.3, 0.22)


func _set_ammo(hand: int, mag: int, magazine_size: int) -> void:
	_hand_mag[hand] = mag
	_hand_size[hand] = maxi(magazine_size, 1)
	_hand_label(hand, "AmmoRow/Ammo").text = str(maxi(mag, 0))
	_hand_label(hand, "AmmoRow/Magazine").text = "/ %d" % _hand_size[hand]
	_update_ammo_hints()


## Label im Kasten einer Hand ("Side", "Name", "AmmoRow/Ammo", "AmmoRow/Magazine").
func _hand_label(hand: int, path: String) -> Label:
	return hand_boxes[hand].get_node(path) as Label


## Ordnet die Kästen der Hände an: eine Waffe groß ganz rechts, zwei Waffen kleiner nebeneinander
## (linke Hand links, rechte Hand rechts). Dazu die Nachladebalken unter dem Fadenkreuz.
func _layout_hands() -> void:
	var two: bool = _hand_count > 1
	var width: float = HAND_BOX_WIDTH_TWO if two else HAND_BOX_WIDTH_ONE
	for hand: int in HUD_HANDS:
		var box: Control = hand_boxes[hand]
		box.visible = hand < _hand_count
		if not box.visible:
			continue
		# Spalte von rechts gezählt: Die letzte Hand steht ganz rechts.
		var column: int = _hand_count - 1 - hand
		var left: float = -MARGIN - width - float(column) * (width + HAND_BOX_GAP)
		box.offset_left = left
		box.offset_right = left + width
		box.offset_top = -HAND_BOX_HEIGHT - 20.0
		box.offset_bottom = -20.0
		var side: Label = _hand_label(hand, "Side")
		side.visible = two
		side.text = HAND_SIDE_TEXTS[hand]
		side.position = Vector2(0.0, 28.0)
		side.size = Vector2(width, 18.0)
		var display_name: String = WeaponDefs.display_name(_hand_ids[hand]).to_upper()
		var name_size: int = fit_font_size(display_name, 17, width - 4.0, true, 11) if two else 22
		var name_label: Label = _hand_label(hand, "Name")
		style_label(name_label, name_size, COL_CYAN, true)
		name_label.text = display_name
		name_label.position = Vector2(0.0, 44.0 if two else 30.0)
		name_label.size = Vector2(width, 26.0 if two else 30.0)
		var row: Control = box.get_node("AmmoRow") as Control
		row.position = Vector2(0.0, 60.0)
		row.size = Vector2(width, HAND_BOX_HEIGHT - 60.0)
		_hand_label(hand, "AmmoRow/Ammo").add_theme_font_size_override("font_size", 48 if two else 60)
		_hand_label(hand, "AmmoRow/Magazine").add_theme_font_size_override("font_size", 24 if two else 30)
	low_ammo_label.offset_top = -164.0 if two else -158.0
	low_ammo_label.offset_bottom = low_ammo_label.offset_top + 26.0
	for hand: int in HUD_HANDS:
		var bar: SlantBar = reload_bars[hand]
		if two:
			bar.offset_left = -171.0 if hand == 0 else 21.0
			bar.offset_right = bar.offset_left + 156.0
		else:
			bar.offset_left = -93.0
			bar.offset_right = 99.0


func _update_ammo_hints() -> void:
	var any_low: bool = false
	var any_empty: bool = false
	for hand: int in _hand_count:
		var mag: int = _hand_mag[hand]
		var empty: bool = mag <= 0
		var low: bool = not empty and float(mag) <= float(_hand_size[hand]) * LOW_AMMO_RATIO
		var color: Color = COL_WHITE
		if _hand_reloading[hand]:
			color = COL_CYAN
		elif empty:
			color = COL_RED
		elif low:
			color = COL_ORANGE
		_hand_label(hand, "AmmoRow/Ammo").add_theme_color_override("font_color", color)
		if not _hand_reloading[hand]:
			any_low = any_low or low
			any_empty = any_empty or empty
	low_ammo_label.visible = any_low
	reload_hint_label.visible = any_empty


# --- Treffer --------------------------------------------------------------------------

func _on_bullet_hit(_zombie: Node3D, _damage: float, info: Dictionary) -> void:
	var headshot: bool = bool(info.get("headshot", false))
	hit_marker.flash(HitMarker.Kind.HEADSHOT if headshot else HitMarker.Kind.HIT)


func _on_zombie_killed(zombie: Node3D, info: Dictionary) -> void:
	var by_bullet: bool = str(info.get("source", "")) == "bullet"
	var headshot: bool = bool(info.get("headshot", false))
	var is_elite: bool = is_instance_valid(zombie) and str(zombie.get("zombie_type")) == "elite"
	if by_bullet:
		hit_marker.flash(HitMarker.Kind.HEADSHOT_KILL if headshot else HitMarker.Kind.KILL)
	if is_elite:
		_show_kill_text("ELITE ERLEDIGT!", COL_YELLOW)
	elif by_bullet and headshot:
		_show_kill_text("KOPFSCHUSS!", COL_ORANGE)


func _show_kill_text(text: String, color: Color) -> void:
	kill_label.text = text
	kill_label.add_theme_color_override("font_color", color)
	kill_label.visible = true
	kill_label.modulate.a = 1.0
	if _kill_tween != null and _kill_tween.is_valid():
		_kill_tween.kill()
	if not is_inside_tree():
		return
	kill_label.scale = Vector2(1.7, 1.7)
	_kill_tween = create_tween()
	_kill_tween.tween_property(kill_label, "scale", Vector2.ONE, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_kill_tween.tween_interval(0.45)
	_kill_tween.tween_property(kill_label, "modulate:a", 0.0, 0.25)
	_kill_tween.tween_callback(kill_label.hide)


# --- Interaktion ----------------------------------------------------------------------

func _on_interact_prompt_changed(text: String) -> void:
	var clean: String = text.strip_edges()
	if clean.is_empty():
		prompt_panel.visible = false
		prompt_label.text = ""
		return
	var changed: bool = clean != prompt_label.text or not prompt_panel.visible
	prompt_label.text = clean
	prompt_label.add_theme_font_size_override("font_size", fit_font_size(clean, 24, 620.0, false))
	_hug(prompt_panel)
	prompt_panel.visible = true
	if changed:
		pop(prompt_panel, 1.15, 0.16)


## Zieht eine mittig verankerte Plakette auf die Größe ihres Textes zusammen.
func _hug(panel: Control) -> void:
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	if panel.grow_vertical == Control.GROW_DIRECTION_BEGIN:
		panel.offset_top = panel.offset_bottom
	else:
		panel.offset_bottom = panel.offset_top


# --- Upgrades -------------------------------------------------------------------------

func _on_upgrade_chosen(_upgrade_id: String, _new_level: int) -> void:
	_rebuild_buffs()


## Der Rucksack hat sich geändert: Buff-Anzeige neu aufbauen.
func _on_build_changed() -> void:
	_rebuild_buffs()


## Game.cameras wurde ersetzt: Die Kamera-Zeilen der Buff-Anzeige stimmen nicht mehr.
func _on_cameras_changed() -> void:
	_rebuild_buffs()


func _on_synergy_unlocked(synergy_id: String) -> void:
	_rebuild_buffs()
	var synergy_name: String = UpgradeDefs.synergy_name(synergy_id)
	show_banner("Synergie: %s!" % synergy_name, synergy_name)


## Aktive Boni des Builds als Zeilen für die Anzeige: Zusatzwerte aus Kandidat, Upgrades und
## Verstärkern sowie aktive Verbindungen. Je Zeile { "key": String, "text": String, "good": bool }.
## Nur was vom Grundwert abweicht, steht drin. Welche Gegenstände man hat, zeigt der Rucksack.
static func buff_entries(upgrades: UpgradeState) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if upgrades == null:
		return entries
	var percents: Array[Array] = [
		["damage", "Schaden", upgrades.damage_multiplier() - 1.0],
		["reload", "Nachladen", 1.0 - upgrades.reload_time_multiplier()],
		["speed", "Tempo", upgrades.speed_multiplier() - 1.0],
		["points", "Punkte", upgrades.points_multiplier() - 1.0],
	]
	for row: Array in percents:
		var value: int = roundi(float(row[2]) * 100.0)
		if value == 0:
			continue
		var sign_text: String = "+" if value > 0 else "−"
		entries.append({"key": str(row[0]), "text": "%s %s%d %%" % [str(row[1]), sign_text, absi(value)], "good": value > 0})
	var hp: int = roundi(upgrades.bonus_max_hp())
	if hp != 0:
		entries.append({"key": "max_hp", "text": "Leben %s%d" % ["+" if hp > 0 else "−", absi(hp)], "good": hp > 0})
	for synergy_id: String in upgrades.active_synergies():
		entries.append({"key": "synergy_" + synergy_id, "text": UpgradeDefs.synergy_name(synergy_id), "good": true})
	return entries


## Die Kameras im Spiel als Zeilen für die Anzeige, je Kameratyp eine, in der Reihenfolge des
## Erwerbs. cameras: Game.cameras (ein Eintrag je Exemplar). Je Zeile { "key": "camera_<id>",
## "id": String, "count": int, "level": int (beste Rarität), "text": "2 × Kameradrohne",
## "good": true }.
static func camera_entries(cameras: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for value: Variant in cameras:
		if not value is Dictionary:
			continue
		var camera: Dictionary = value
		var id: String = str(camera.get("id", ""))
		if id.is_empty():
			continue
		if not by_id.has(id):
			var fresh: Dictionary = {"key": "camera_" + id, "id": id, "count": 0, "level": 0, "text": "", "good": true}
			by_id[id] = fresh
			entries.append(fresh)
		var entry: Dictionary = by_id[id]
		entry["count"] = int(entry["count"]) + 1
		entry["level"] = maxi(int(entry["level"]), int(camera.get("level", 1)))
	for entry: Dictionary in entries:
		var display_name: String = entry_name(str(entry["id"]))
		entry["text"] = display_name if int(entry["count"]) == 1 else "%d × %s" % [int(entry["count"]), display_name]
	return entries


## Baut die Buff-Anzeige neu: Boni aus Game.upgrades, darunter die Kameras aus Game.cameras.
func _rebuild_buffs() -> void:
	for child: Node in buff_rows.get_children():
		buff_rows.remove_child(child)
		child.queue_free()
	var entries: Array[Dictionary] = buff_entries(Game.upgrades)
	entries.append_array(camera_entries(Game.cameras))
	buff_header.visible = true
	var index: int = 0
	for entry: Dictionary in entries:
		var key: String = str(entry["key"])
		var is_synergy: bool = key.begins_with("synergy_")
		var is_camera: bool = key.begins_with("camera_")
		var color: Color = COL_YELLOW if is_synergy else (COL_GREEN if bool(entry["good"]) else COL_ORANGE)
		if is_camera:
			color = CAMERA_ROW_COLOR
		var row: Control = Control.new()
		row.name = "Buff_%s" % key
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = BUFF_ROW_SIZE
		row.size = BUFF_ROW_SIZE
		row.position = Vector2(0.0, float(index) * BUFF_ROW_STEP)
		var plate: Panel = make_plate(COL_PANEL, color, 2, 0.12, 4)
		plate.name = "Plate"
		plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.add_child(plate)
		var text: String = str(entry["text"]).to_upper() if is_synergy else str(entry["text"])
		var text_left: float = 12.0
		if is_camera:
			# Kameras zeigen ihr Bild vor dem Namen: So heben sie sich von den Boni ab.
			var icon: Control = _make_camera_icon(str(entry["id"]))
			anchor_box(icon, Vector2.ZERO, Vector2(8.0, 4.0), Vector2(20.0, 20.0))
			row.add_child(icon)
			text_left = 34.0
		var text_width: float = BUFF_ROW_SIZE.x - text_left - 8.0
		var label: Label = make_label(text, fit_font_size(text, 15, text_width - 4.0, is_synergy, 11), color, is_synergy)
		label.name = "Text"
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		anchor_box(label, Vector2.ZERO, Vector2(text_left, 0.0), Vector2(text_width, BUFF_ROW_SIZE.y))
		row.add_child(label)
		buff_rows.add_child(row)
		index += 1


## Kleines Bild einer Kamera: ihr Bild aus ItemIcons, dasselbe wie im Rucksack.
func _make_camera_icon(camera_id: String) -> Control:
	var icon: ItemIcon = ItemIcon.new()
	icon.name = "Icon"
	icon.item_id = camera_id
	return icon


# --- Banner ---------------------------------------------------------------------------

func _on_banner(text: String) -> void:
	show_banner(text)


## Eine Kiste ist gefallen: Meldung, damit sie im Getümmel niemand übersieht. Jede Kiste wird
## gemeldet, nur dieselbe Meldung (gleiche Seltenheit) entfällt innerhalb von 3 s. Meldet ein
## anderes Modul die Kiste selbst per Banner, bleibt es bei einer Meldung (dedupe_key "kiste").
func _on_chest_dropped(chest: Node3D) -> void:
	var rarity: int = -1
	if is_instance_valid(chest):
		var rarity_value: Variant = chest.get("rarity")
		if rarity_value is int:
			rarity = clampi(int(rarity_value), 0, Balance.RARITY_NAMES.size() - 1)
	if rarity < 0:
		show_banner("Kiste gefallen!", "kiste")
	else:
		show_banner("%s-Kiste gefallen!" % Balance.RARITY_NAMES[rarity], "kiste")


func _is_duplicate_banner(lower: String, key: String) -> bool:
	var now: int = Time.get_ticks_msec()
	var kept: Array[Dictionary] = []
	var duplicate: bool = false
	for entry: Dictionary in _recent_banners:
		if now - int(entry["time"]) > BANNER_DEDUPE_MSEC:
			continue
		kept.append(entry)
		var other_text: String = String(entry["text"])
		var other_key: String = String(entry["key"])
		if other_text == lower:
			duplicate = true
		elif not key.is_empty() and other_key == key:
			# Zwei eigene Meldungen derselben Art mit verschiedenem Text (Bronze- und Gold-Kiste)
			# sind zwei Ereignisse: Beide laufen.
			pass
		elif not key.is_empty() and other_text.contains(key):
			duplicate = true
		elif not other_key.is_empty() and lower.contains(other_key):
			duplicate = true
	_recent_banners = kept
	return duplicate


## Kürzt einen Text wortweise mit "...", bis er in dieser Schriftgröße in max_width passt.
func _shorten(text: String, font_size: int, max_width: float) -> String:
	var font: Font = show_font(true)
	if font.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= max_width:
		return text
	var words: PackedStringArray = text.split(" ", false)
	while words.size() > 1:
		words.remove_at(words.size() - 1)
		var shorter: String = " ".join(words) + " ..."
		if font.get_string_size(shorter.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= max_width:
			return shorter
	return text.left(24) + " ..."


func _show_next_banner() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	if _banner_queue.is_empty():
		_banner_active = false
		banner_panel.visible = false
		return
	_banner_active = true
	var text: String = String(_banner_queue.pop_front())
	var font_size: int = fit_font_size(text.to_upper(), BANNER_FONT_SIZE, BANNER_MAX_WIDTH, true, BANNER_MIN_FONT_SIZE)
	banner_label.text = _shorten(text, font_size, BANNER_MAX_WIDTH)
	banner_label.add_theme_font_size_override("font_size", font_size)
	_hug(banner_panel)
	banner_panel.visible = true
	banner_panel.modulate.a = 1.0
	banner_panel.scale = Vector2.ONE
	if not is_inside_tree():
		return
	var hold: float = BANNER_HOLD if _banner_queue.is_empty() else BANNER_HOLD_BUSY
	banner_panel.scale = Vector2(0.15, 1.6)
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner_panel, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(banner_panel, "scale", Vector2(1.3, 0.0), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_banner_tween.parallel().tween_property(banner_panel, "modulate:a", 0.0, 0.16)
	_banner_tween.tween_callback(_show_next_banner)


# --- Lauf -----------------------------------------------------------------------------

func _on_run_started() -> void:
	_reset()


func _on_game_over(_stats: Dictionary) -> void:
	# Unter dem Game-Over-Bildschirm bleibt nur der ruhige Teil des HUD stehen.
	_center.visible = false
	prompt_panel.visible = false
	countdown_box.visible = false
