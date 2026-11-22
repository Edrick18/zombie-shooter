extends RefCounted
## Modul: Oberfläche (scripts/ui).
## Bilder für alle Gegenstände, gezeichnet mit den Zeichenbefehlen eines CanvasItem
## (Abschnitt 26.2 im Bauplan). Alle Bildschirme benutzen nur diese Datei.
## Einbinden mit: const ItemIcons := preload("res://scripts/ui/item_icons.gd")
##
## Öffentlich:
##   has(id)                        gibt es ein Bild für diese ID?
##   draw(canvas, id, rect, tint)   zeichnet das Bild in das Rechteck (nur in _draw() des canvas)
##   commands(id, rect, tint)       dieselben Zeichenbefehle als Liste, ohne zu zeichnen (für Tests)
##   View                           fertiges Control, das ein Bild zeigt (item_id, tint, dazu auf
##                                  Wunsch eine Plakette dahinter: plate, plate_color, plate_fill)
##
## Aufbau: Jedes Bild ist eine Funktion icon_<id>() der Klasse Painter. Sie zeichnet in einem
## Einheitsquadrat (x nach rechts, y nach unten, 0 bis 1) mit den Helfern der Klasse Pen: Flächen
## mit dunklem Umriss, Linien, Glanz, Sterne, Herzen, Patronen. Pen rechnet in das Rechteck um
## (größtes Quadrat in der Mitte des Rechtecks) und multipliziert jede Farbe mit tint. Die Tabelle
## DRAWERS ordnet jeder ID ihre Funktion zu.
##
## Stil: flach, kräftige Farben, dunkler Umriss, kein Hintergrund (das Bild steht frei). Waffen in
## Seitenansicht mit der Mündung nach rechts: einhändige waagerecht, zweihändige schräg nach oben.

const ItemDefs := preload("res://scripts/core/item_defs.gd")

# --- Farben (reine Optik) ---
const INK: Color = Color(0.06, 0.03, 0.13)
const WHITE: Color = Color(1.0, 1.0, 1.0)
const YELLOW: Color = Color(1.0, 0.87, 0.1)
const PINK: Color = Color(1.0, 0.16, 0.52)
const CYAN: Color = Color(0.2, 0.92, 1.0)
const GREEN: Color = Color(0.35, 1.0, 0.3)
const ORANGE: Color = Color(1.0, 0.55, 0.08)
const RED: Color = Color(1.0, 0.18, 0.16)
const PURPLE: Color = Color(0.55, 0.3, 1.0)
const STEEL: Color = Color(0.66, 0.72, 0.84)
const STEEL_DARK: Color = Color(0.42, 0.47, 0.62)
const STEEL_LIGHT: Color = Color(0.88, 0.92, 1.0)
const GUN: Color = Color(0.29, 0.31, 0.45)
const WOOD: Color = Color(0.8, 0.5, 0.24)
const WOOD_DARK: Color = Color(0.55, 0.32, 0.15)
const BRASS: Color = Color(1.0, 0.76, 0.2)
const COPPER: Color = Color(0.93, 0.5, 0.25)
const GLASS: Color = Color(0.45, 0.85, 1.0)
const OLIVE: Color = Color(0.45, 0.6, 0.3)
const LEAF: Color = Color(0.2, 0.75, 0.3)
const SLIME: Color = Color(0.62, 0.95, 0.15)
const CAM: Color = Color(0.86, 0.84, 1.0)
const CAM_DARK: Color = Color(0.6, 0.56, 0.92)
const PIG: Color = Color(1.0, 0.62, 0.74)
const PIG_DARK: Color = Color(0.92, 0.42, 0.6)
const CLOTH: Color = Color(0.93, 0.83, 0.6)
const LEATHER: Color = Color(0.68, 0.42, 0.22)

# --- Maße ---
## Breite des Umrisses als Anteil der Kantenlänge (mindestens 1 Pixel).
const OUTLINE: float = 0.036
## Unter dieser Kantenlänge wird nichts gezeichnet.
const MIN_SIDE: float = 6.0
## Zweihändige Waffen liegen schräg: Winkel in Grad und Maßstab.
const LONG_TILT: float = -24.0
const LONG_ZOOM: float = 0.96

## ID -> Funktion der Klasse Painter.
const DRAWERS: Dictionary = {
	# Waffen
	"pistol": &"icon_pistol", "revolver": &"icon_revolver", "smg": &"icon_smg",
	"sawed_off": &"icon_sawed_off", "shotgun": &"icon_shotgun", "rifle": &"icon_rifle",
	"sniper": &"icon_sniper", "minigun": &"icon_minigun", "rocket_launcher": &"icon_rocket_launcher",
	"burst_pistol": &"icon_burst_pistol", "nail_gun": &"icon_nail_gun",
	"machine_pistol": &"icon_machine_pistol", "crossbow": &"icon_crossbow",
	"grenade_launcher": &"icon_grenade_launcher", "flamethrower": &"icon_flamethrower",
	"beam": &"icon_beam", "tesla": &"icon_tesla", "lmg": &"icon_lmg", "auto_shotgun": &"icon_auto_shotgun",
	# Upgrade-Gegenstände
	"chain_lightning": &"icon_chain_lightning", "pierce": &"icon_pierce", "burn": &"icon_burn",
	"lifesteal": &"icon_lifesteal", "max_hp": &"icon_max_hp", "corpse_explosion": &"icon_corpse_explosion",
	"reload_shockwave": &"icon_reload_shockwave", "speed": &"icon_speed", "luck": &"icon_luck",
	"extra_shot": &"icon_extra_shot", "poison": &"icon_poison", "crit": &"icon_crit",
	"big_mag": &"icon_big_mag", "scope": &"icon_scope", "fire_rate": &"icon_fire_rate",
	"shield": &"icon_shield", "kill_heal": &"icon_kill_heal", "disco_ball": &"icon_disco_ball",
	"jammer": &"icon_jammer", "dash": &"icon_dash", "frost": &"icon_frost", "opener": &"icon_opener",
	"punchline": &"icon_punchline", "ricochet": &"icon_ricochet", "thorns": &"icon_thorns",
	"revive": &"icon_revive", "snack": &"icon_snack", "mine": &"icon_mine",
	# Kameras
	"drone": &"icon_drone", "cam_tele": &"icon_cam_tele", "cam_flash": &"icon_cam_flash",
	"cam_slow": &"icon_cam_slow", "cam_director": &"icon_cam_director",
	# Kamera-Zubehör
	"cam_lens": &"icon_cam_lens", "cam_zoom": &"icon_cam_zoom", "cam_battery": &"icon_cam_battery",
	"cam_second": &"icon_cam_second", "cam_uplink": &"icon_cam_uplink",
	# Verstärker
	"spotlight": &"icon_spotlight", "speed_loader": &"icon_speed_loader",
	"piggy_bank": &"icon_piggy_bank", "replay": &"icon_replay",
	# Rucksack-Teile
	"bag_tiny": &"icon_bag_tiny", "bag_small": &"icon_bag_small",
	"bag_medium": &"icon_bag_medium", "bag_large": &"icon_bag_large",
}


## Gibt es ein Bild für diesen Gegenstand?
static func has(id: String) -> bool:
	return DRAWERS.has(id)


## Zeichnet das Bild des Gegenstands in das Rechteck (Koordinaten des canvas). Nur innerhalb
## von _draw() des canvas aufrufen. Das Bild füllt das größte Quadrat in der Mitte des Rechtecks.
## tint multipliziert alle Farben (z. B. grau für kaputt). Eine unbekannte ID zeichnet nichts.
static func draw(canvas: CanvasItem, id: String, rect: Rect2, tint: Color = Color.WHITE) -> void:
	if canvas == null or not DRAWERS.has(id):
		return
	var painter: Painter = Painter.new()
	painter.setup(canvas, rect, tint)
	painter.paint(id)


## Die Zeichenbefehle des Bilds als Liste, ohne zu zeichnen (läuft auch ohne Bildschirm).
## Je Befehl: { "op": "polygon" | "polyline" | "circle", "points": PackedVector2Array,
## "color": Color (schon mit tint), "extent": float }. extent ist der Abstand, um den der Befehl
## über seine Punkte hinausreicht (halbe Linienbreite oder Radius).
static func commands(id: String, rect: Rect2, tint: Color = Color.WHITE) -> Array[Dictionary]:
	var painter: Painter = Painter.new()
	painter.setup(null, rect, tint)
	painter.paint(id)
	return painter.recorded


# =====================================================================================
# Fertiges Control mit einem Bild
# =====================================================================================

## Zeigt das Bild eines Gegenstands in der Größe des Controls.
class View:
	extends Control

	## ID aus ItemDefs.
	var item_id: String = "":
		set(value):
			item_id = value
			queue_redraw()
	## Multipliziert alle Farben des Bilds.
	var tint: Color = Color.WHITE:
		set(value):
			tint = value
			queue_redraw()
	## Plakette hinter dem Bild (für Listen): Fläche in plate_fill mit Rand in plate_color.
	var plate: bool = false:
		set(value):
			plate = value
			queue_redraw()
	## Farbe des Rands der Plakette.
	var plate_color: Color = Color(1.0, 1.0, 1.0, 0.3):
		set(value):
			plate_color = value
			queue_redraw()
	## Farbe der Fläche der Plakette.
	var plate_fill: Color = Color(0.05, 0.03, 0.12, 0.92):
		set(value):
			plate_fill = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x < MIN_SIDE or size.y < MIN_SIDE:
			return
		var rect: Rect2 = Rect2(Vector2.ZERO, size)
		if plate:
			var border: float = maxf(1.0, roundf(minf(size.x, size.y) * 0.05))
			draw_rect(rect, plate_color)
			draw_rect(rect.grow(-border), plate_fill)
			rect = rect.grow(-border)
		var painter: Painter = Painter.new()
		painter.setup(self, rect, tint)
		painter.paint(item_id)


# =====================================================================================
# Stift: rechnet das Einheitsquadrat in das Rechteck um und zeichnet oder schreibt mit
# =====================================================================================

class Pen:
	extends RefCounted

	## Ziel der Zeichenbefehle. null: Die Befehle werden nur in recorded mitgeschrieben.
	var canvas: CanvasItem = null
	var recorded: Array[Dictionary] = []
	## Linke obere Ecke und Kantenlänge des Quadrats, in das gezeichnet wird.
	var origin: Vector2 = Vector2.ZERO
	var side: float = 1.0
	var tint: Color = Color.WHITE
	## Breite des Umrisses in Pixeln.
	var line: float = 1.0
	## Eigener Rahmen für gedrehte oder verkleinerte Teile (siehe frame).
	var xf: Transform2D = Transform2D.IDENTITY
	var zoom: float = 1.0

	func setup(target: CanvasItem, rect: Rect2, color: Color) -> void:
		canvas = target
		side = minf(rect.size.x, rect.size.y)
		origin = rect.position + (rect.size - Vector2(side, side)) * 0.5
		tint = color
		line = maxf(1.0, side * OUTLINE)
		unframe()

	## Ab jetzt gilt ein gedrehter und skalierter Rahmen: Der Punkt (0.5, 0.5) der folgenden
	## Befehle landet bei (cx, cy), gedreht um degrees (im Uhrzeigersinn) und mit Maßstab scale.
	func frame(cx: float, cy: float, degrees: float = 0.0, scale: float = 1.0) -> void:
		zoom = scale
		xf = Transform2D(deg_to_rad(degrees), Vector2(scale, scale), 0.0, Vector2(cx, cy)) \
				* Transform2D(0.0, Vector2(-0.5, -0.5))

	func unframe() -> void:
		zoom = 1.0
		xf = Transform2D.IDENTITY

	## Punkt des Einheitsquadrats in Koordinaten des canvas.
	func at(x: float, y: float) -> Vector2:
		return origin + (xf * Vector2(x, y)) * side

	## Länge im Einheitsquadrat in Pixeln.
	func px(length: float) -> float:
		return length * side * zoom

	## Punktliste aus x/y-Paaren.
	func path(flat: Array) -> PackedVector2Array:
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in range(0, flat.size() - 1, 2):
			points.append(at(float(flat[i]), float(flat[i + 1])))
		return points

	# --- Grundbefehle (zeichnen oder mitschreiben) ---

	func _polygon(points: PackedVector2Array, color: Color) -> void:
		if points.size() < 3:
			return
		var shown: Color = color * tint
		if canvas == null:
			recorded.append({"op": "polygon", "points": points, "color": shown, "extent": 0.0})
		else:
			canvas.draw_colored_polygon(points, shown)

	func _polyline(points: PackedVector2Array, color: Color, width: float) -> void:
		if points.size() < 2:
			return
		var shown: Color = color * tint
		if canvas == null:
			recorded.append({"op": "polyline", "points": points, "color": shown, "extent": width * 0.5})
		else:
			canvas.draw_polyline(points, shown, width, true)

	func _circle(center: Vector2, radius: float, color: Color) -> void:
		var shown: Color = color * tint
		if canvas == null:
			recorded.append({"op": "circle", "points": PackedVector2Array([center]), "color": shown, "extent": radius})
		else:
			canvas.draw_circle(center, radius, shown, true, -1.0, true)

	## Geschlossener Umriss um eine Punktliste. Beginnt in der Mitte der ersten Kante, damit
	## auch die erste Ecke sauber verbunden ist.
	func _closed(points: PackedVector2Array, color: Color, width: float) -> void:
		if points.size() < 3:
			return
		var loop: PackedVector2Array = PackedVector2Array()
		var start: Vector2 = (points[0] + points[1]) * 0.5
		loop.append(start)
		for i: int in range(1, points.size()):
			loop.append(points[i])
		loop.append(points[0])
		loop.append(start)
		_polyline(loop, color, width)

	# --- Flächen ---

	## Fläche ohne Umriss.
	func fill(flat: Array, color: Color) -> void:
		_polygon(path(flat), color)

	## Fläche mit dunklem Umriss.
	func shape(flat: Array, color: Color) -> void:
		var points: PackedVector2Array = path(flat)
		_polygon(points, color)
		_closed(points, INK, line)

	## Nur der dunkle Umriss.
	func rim(flat: Array) -> void:
		_closed(path(flat), INK, line)

	## Rechteck ohne Umriss.
	func bar(x: float, y: float, w: float, h: float, color: Color) -> void:
		fill([x, y, x + w, y, x + w, y + h, x, y + h], color)

	## Rechteck mit Umriss.
	func box(x: float, y: float, w: float, h: float, color: Color) -> void:
		shape([x, y, x + w, y, x + w, y + h, x, y + h], color)

	## Rechteck mit runden Ecken und Umriss.
	func rbox(x: float, y: float, w: float, h: float, r: float, color: Color) -> void:
		shape(round_rect(x, y, w, h, r), color)

	## Kreis mit Umriss.
	func disc(x: float, y: float, r: float, color: Color) -> void:
		shape(ellipse(x, y, r, r, 24), color)

	## Kreis ohne Umriss.
	func dot(x: float, y: float, r: float, color: Color) -> void:
		_circle(at(x, y), px(r), color)

	## Ellipse mit Umriss.
	func oval(x: float, y: float, rx: float, ry: float, color: Color) -> void:
		shape(ellipse(x, y, rx, ry, 24), color)

	## Ellipse ohne Umriss.
	func blob(x: float, y: float, rx: float, ry: float, color: Color) -> void:
		fill(ellipse(x, y, rx, ry, 20), color)

	## Heller Glanzstreifen (Rechteck).
	func shine(x: float, y: float, w: float, h: float, alpha: float = 0.38) -> void:
		bar(x, y, w, h, Color(1.0, 1.0, 1.0, alpha))

	## Heller Glanz als freie Fläche.
	func gloss(flat: Array, alpha: float = 0.3) -> void:
		fill(flat, Color(1.0, 1.0, 1.0, alpha))

	## Schatten am Boden unter einem stehenden Gegenstand.
	func ground(x: float, y: float, rx: float, ry: float) -> void:
		blob(x, y, rx, ry, Color(INK, 0.35))

	# --- Linien ---

	## Offene Linie der Breite w.
	func stroke(flat: Array, color: Color, w: float) -> void:
		_polyline(path(flat), color, maxf(px(w), 1.0))

	## Offene Linie mit dunklem Umriss.
	func cord(flat: Array, color: Color, w: float) -> void:
		var points: PackedVector2Array = path(flat)
		var width: float = maxf(px(w), 1.0)
		_polyline(points, INK, width + line * 2.0)
		_polyline(points, color, width)

	## Kreisbogen von from_deg bis to_deg (0 = rechts, im Uhrzeigersinn).
	func arc(x: float, y: float, r: float, from_deg: float, to_deg: float, color: Color, w: float) -> void:
		_polyline(path(arc_flat(x, y, r, from_deg, to_deg)), color, maxf(px(w), 1.0))

	## Kreisbogen mit dunklem Umriss.
	func oarc(x: float, y: float, r: float, from_deg: float, to_deg: float, color: Color, w: float) -> void:
		var points: PackedVector2Array = path(arc_flat(x, y, r, from_deg, to_deg))
		var width: float = maxf(px(w), 1.0)
		_polyline(points, INK, width + line * 2.0)
		_polyline(points, color, width)

	# --- Punktlisten für wiederkehrende Formen ---

	func round_rect(x: float, y: float, w: float, h: float, r: float) -> Array:
		var radius: float = minf(r, minf(w, h) * 0.5)
		var flat: Array = []
		_corner(flat, x + w - radius, y + radius, radius, -90.0)
		_corner(flat, x + w - radius, y + h - radius, radius, 0.0)
		_corner(flat, x + radius, y + h - radius, radius, 90.0)
		_corner(flat, x + radius, y + radius, radius, 180.0)
		return flat

	func _corner(flat: Array, cx: float, cy: float, radius: float, start_deg: float) -> void:
		for step: int in 4:
			var angle: float = deg_to_rad(start_deg + 30.0 * float(step))
			flat.append(cx + cos(angle) * radius)
			flat.append(cy + sin(angle) * radius)

	func ellipse(x: float, y: float, rx: float, ry: float, steps: int) -> Array:
		var flat: Array = []
		for i: int in steps:
			var angle: float = TAU * float(i) / float(steps)
			flat.append(x + cos(angle) * rx)
			flat.append(y + sin(angle) * ry)
		return flat

	func arc_flat(x: float, y: float, r: float, from_deg: float, to_deg: float) -> Array:
		var steps: int = maxi(3, ceili(absf(to_deg - from_deg) / 15.0))
		var flat: Array = []
		for i: int in steps + 1:
			var angle: float = deg_to_rad(lerpf(from_deg, to_deg, float(i) / float(steps)))
			flat.append(x + cos(angle) * r)
			flat.append(y + sin(angle) * r)
		return flat

	## Ringstück zwischen zwei Radien: außen von from_deg nach to_deg, innen zurück.
	func band_flat(x: float, y: float, inner: float, outer: float, from_deg: float, to_deg: float) -> Array:
		var flat: Array = arc_flat(x, y, outer, from_deg, to_deg)
		flat.append_array(arc_flat(x, y, inner, to_deg, from_deg))
		return flat

	## Stern mit count Zacken, erste Zacke bei rot_deg (-90 = oben).
	func star_flat(x: float, y: float, outer: float, inner: float, count: int, rot_deg: float = -90.0) -> Array:
		var flat: Array = []
		for i: int in count * 2:
			var radius: float = outer if i % 2 == 0 else inner
			var angle: float = deg_to_rad(rot_deg) + TAU * float(i) / float(count * 2)
			flat.append(x + cos(angle) * radius)
			flat.append(y + sin(angle) * radius)
		return flat

	## Herz um (x, y), s = halbe Breite.
	func heart_flat(x: float, y: float, s: float) -> Array:
		var unit: Array = [0.0, -0.45, 0.3, -0.85, 0.72, -0.85, 1.0, -0.52, 1.0, -0.1, 0.6, 0.45, 0.0, 1.0,
				-0.6, 0.45, -1.0, -0.1, -1.0, -0.52, -0.72, -0.85, -0.3, -0.85]
		var flat: Array = []
		for i: int in range(0, unit.size(), 2):
			flat.append(x + float(unit[i]) * s)
			flat.append(y + float(unit[i + 1]) * s)
		return flat

	# --- Wiederkehrende Bildteile ---

	## Stern mit Umriss.
	func star(x: float, y: float, outer: float, inner: float, count: int, color: Color, rot_deg: float = -90.0) -> void:
		shape(star_flat(x, y, outer, inner, count, rot_deg), color)

	## Kleines Funkeln (vier Zacken, ohne Umriss).
	func sparkle(x: float, y: float, s: float, color: Color = WHITE) -> void:
		fill(star_flat(x, y, s, s * 0.3, 4), color)

	## Herz mit Umriss.
	func heart(x: float, y: float, s: float, color: Color) -> void:
		shape(heart_flat(x, y, s), color)

	## Pluszeichen um (x, y), s = halbe Länge, w = Balkenbreite.
	func plus(x: float, y: float, s: float, w: float, color: Color) -> void:
		bar(x - s, y - w * 0.5, s * 2.0, w, color)
		bar(x - w * 0.5, y - s, w, s * 2.0, color)

	## Patrone nach rechts: Hülse aus Messing, Geschoss aus Kupfer. (x, y) = Mitte des Bodens.
	func bullet(x: float, y: float, length: float, thick: float, tip: Color = COPPER) -> void:
		var half: float = thick * 0.5
		shape([x + length * 0.55, y - half, x + length * 0.74, y - half, x + length * 0.9, y - half * 0.55, x + length, y,
				x + length * 0.9, y + half * 0.55, x + length * 0.74, y + half, x + length * 0.55, y + half], tip)
		box(x, y - half, length * 0.58, thick, BRASS)
		bar(x, y - half, length * 0.09, thick, WOOD_DARK)
		shine(x + length * 0.12, y - half * 0.6, length * 0.4, half * 0.4, 0.5)

	## Patrone nach oben. (x, y) = Mitte des Bodens.
	func bullet_up(x: float, y: float, length: float, thick: float, tip: Color = COPPER) -> void:
		var half: float = thick * 0.5
		shape([x - half, y - length * 0.55, x - half, y - length * 0.74, x - half * 0.55, y - length * 0.9, x, y - length,
				x + half * 0.55, y - length * 0.9, x + half, y - length * 0.74, x + half, y - length * 0.55], tip)
		box(x - half, y - length * 0.58, thick, length * 0.58, BRASS)
		bar(x - half, y - length * 0.09, thick, length * 0.09, WOOD_DARK)
		shine(x - half * 0.6, y - length * 0.5, half * 0.4, length * 0.38, 0.5)

	## Pfeilspitze an (x, y) in Richtung dir_deg.
	func arrow_head(x: float, y: float, dir_deg: float, length: float, half_width: float, color: Color) -> void:
		var dir: Vector2 = Vector2.from_angle(deg_to_rad(dir_deg))
		var normal: Vector2 = Vector2(-dir.y, dir.x)
		var tip: Vector2 = Vector2(x, y) + dir * length
		var left: Vector2 = Vector2(x, y) + normal * half_width
		var right: Vector2 = Vector2(x, y) - normal * half_width
		shape([tip.x, tip.y, left.x, left.y, right.x, right.y], color)

	## Kameragehäuse mit Sucher: Rechteck mit runden Ecken, Linse als dunkler Ring mit Glas.
	func camera_body(x: float, y: float, w: float, h: float, color: Color = CAM) -> void:
		rbox(x, y, w, h, minf(w, h) * 0.14, color)
		shine(x + w * 0.1, y + h * 0.1, w * 0.8, h * 0.12, 0.5)

	func lens(x: float, y: float, r: float, glass: Color = GLASS) -> void:
		disc(x, y, r, GUN)
		dot(x, y, r * 0.58, glass)
		dot(x - r * 0.2, y - r * 0.22, r * 0.18, WHITE)


# =====================================================================================
# Die Bilder
# =====================================================================================

class Painter:
	extends Pen

	## Zeichnet das Bild dieser ID. Unbekannte ID oder zu kleines Rechteck: nichts.
	func paint(id: String) -> void:
		if not DRAWERS.has(id) or side < MIN_SIDE:
			return
		unframe()
		call(DRAWERS[id] as StringName)
		unframe()

	# ---------------------------------------------------------------------------------
	# Waffen, einhändig (waagerecht)
	# ---------------------------------------------------------------------------------

	## Dienstpistole: schlichte Pistole mit Schlitten und Holzgriff.
	func icon_pistol() -> void:
		shape([0.2, 0.44, 0.7, 0.44, 0.7, 0.56, 0.48, 0.58, 0.41, 0.9, 0.14, 0.9, 0.2, 0.62], GUN)
		fill([0.23, 0.62, 0.39, 0.62, 0.35, 0.84, 0.19, 0.84], WOOD)
		stroke([0.48, 0.58, 0.51, 0.72, 0.63, 0.72, 0.66, 0.56], INK, 0.035)
		stroke([0.56, 0.58, 0.54, 0.66], INK, 0.03)
		rbox(0.1, 0.24, 0.8, 0.23, 0.04, STEEL)
		shine(0.14, 0.27, 0.72, 0.045)
		bar(0.52, 0.34, 0.17, 0.07, STEEL_DARK)
		for i: int in 3:
			bar(0.16 + 0.055 * float(i), 0.34, 0.024, 0.1, STEEL_DARK)
		bar(0.86, 0.32, 0.04, 0.09, INK)
		fill([0.82, 0.24, 0.86, 0.18, 0.89, 0.24], INK)

	## Kandidatenschreck: Revolver mit Trommel, langem Lauf und Holzgriff.
	func icon_revolver() -> void:
		shape([0.22, 0.44, 0.42, 0.54, 0.37, 0.7, 0.33, 0.93, 0.1, 0.89, 0.14, 0.66], WOOD)
		stroke([0.2, 0.7, 0.3, 0.73], WOOD_DARK, 0.03)
		stroke([0.18, 0.79, 0.29, 0.82], WOOD_DARK, 0.03)
		stroke([0.42, 0.56, 0.45, 0.7, 0.57, 0.68, 0.58, 0.54], INK, 0.035)
		box(0.54, 0.37, 0.24, 0.06, STEEL_DARK)
		box(0.52, 0.23, 0.42, 0.14, STEEL)
		shine(0.56, 0.25, 0.34, 0.035)
		fill([0.86, 0.23, 0.89, 0.15, 0.92, 0.23], INK)
		shape([0.2, 0.23, 0.56, 0.23, 0.56, 0.56, 0.4, 0.58, 0.22, 0.48], STEEL)
		shape([0.13, 0.19, 0.21, 0.12, 0.27, 0.23, 0.2, 0.3], STEEL_DARK)
		rbox(0.27, 0.26, 0.27, 0.25, 0.05, STEEL_LIGHT)
		bar(0.3, 0.32, 0.21, 0.03, STEEL_DARK)
		bar(0.3, 0.42, 0.21, 0.03, STEEL_DARK)

	## Quotenhammer: Maschinenpistole mit langem Magazin vor dem Griff und Drahtstütze.
	func icon_smg() -> void:
		cord([0.26, 0.34, 0.07, 0.34, 0.07, 0.6], STEEL_DARK, 0.035)
		shape([0.5, 0.46, 0.64, 0.46, 0.61, 0.94, 0.47, 0.94], STEEL)
		bar(0.5, 0.6, 0.12, 0.025, STEEL_DARK)
		bar(0.49, 0.72, 0.12, 0.025, STEEL_DARK)
		shape([0.27, 0.46, 0.4, 0.46, 0.36, 0.78, 0.22, 0.78], GUN)
		stroke([0.4, 0.5, 0.42, 0.62, 0.5, 0.62], INK, 0.03)
		box(0.72, 0.3, 0.2, 0.09, STEEL)
		box(0.86, 0.28, 0.08, 0.13, GUN)
		box(0.3, 0.16, 0.07, 0.08, GUN)
		box(0.62, 0.16, 0.05, 0.08, GUN)
		rbox(0.2, 0.23, 0.54, 0.25, 0.04, STEEL_DARK)
		bar(0.24, 0.34, 0.44, 0.055, YELLOW)
		shine(0.24, 0.26, 0.46, 0.035)

	## Blitzrunde: abgesägte Doppelflinte mit zwei kurzen Läufen und Pistolengriff aus Holz.
	func icon_sawed_off() -> void:
		shape([0.34, 0.3, 0.34, 0.62, 0.25, 0.92, 0.06, 0.86, 0.13, 0.58, 0.2, 0.36], WOOD)
		stroke([0.14, 0.7, 0.25, 0.74], WOOD_DARK, 0.03)
		stroke([0.36, 0.6, 0.4, 0.72, 0.5, 0.7, 0.5, 0.6], INK, 0.035)
		shape([0.48, 0.52, 0.78, 0.52, 0.75, 0.65, 0.48, 0.65], WOOD)
		box(0.42, 0.26, 0.52, 0.28, STEEL)
		stroke([0.42, 0.4, 0.94, 0.4], INK, 0.025)
		shine(0.45, 0.285, 0.42, 0.035)
		bar(0.88, 0.29, 0.04, 0.09, INK)
		bar(0.88, 0.43, 0.04, 0.09, INK)
		shape([0.3, 0.24, 0.46, 0.24, 0.46, 0.58, 0.3, 0.6], STEEL_DARK)
		shape([0.25, 0.17, 0.34, 0.15, 0.36, 0.25, 0.27, 0.26], GUN)

	## Dreierpack: dunkle Pistole mit langem Magazin, davor drei Schüsse in einer Reihe.
	func icon_burst_pistol() -> void:
		shape([0.19, 0.7, 0.36, 0.7, 0.33, 0.95, 0.16, 0.95], STEEL)
		shape([0.16, 0.44, 0.56, 0.44, 0.56, 0.54, 0.4, 0.56, 0.36, 0.8, 0.13, 0.8, 0.17, 0.6], STEEL_DARK)
		stroke([0.4, 0.56, 0.42, 0.68, 0.52, 0.68, 0.54, 0.54], INK, 0.035)
		box(0.58, 0.29, 0.07, 0.13, STEEL)
		rbox(0.05, 0.24, 0.56, 0.22, 0.04, GUN)
		bar(0.1, 0.32, 0.34, 0.05, CYAN)
		shine(0.09, 0.265, 0.48, 0.03)
		for i: int in 3:
			rbox(0.7 + 0.095 * float(i), 0.32, 0.065, 0.075, 0.02, YELLOW)

	## Bühnenbau: gelbes Nagelgerät mit schrägem Nagelstreifen und Nagel an der Nase.
	func icon_nail_gun() -> void:
		shape([0.36, 0.78, 0.72, 0.44, 0.85, 0.44, 0.85, 0.55, 0.48, 0.93, 0.36, 0.93], ORANGE)
		for i: int in 4:
			var t: float = float(i) / 3.0
			stroke([lerpf(0.46, 0.76, t), lerpf(0.76, 0.48, t), lerpf(0.5, 0.8, t), lerpf(0.82, 0.54, t)], INK, 0.022)
		shape([0.25, 0.46, 0.42, 0.46, 0.4, 0.86, 0.23, 0.86], GUN)
		shape([0.84, 0.3, 0.91, 0.3, 0.97, 0.345, 0.91, 0.39, 0.84, 0.39], STEEL_LIGHT)
		box(0.72, 0.24, 0.13, 0.22, STEEL_DARK)
		box(0.07, 0.2, 0.1, 0.24, GUN)
		rbox(0.15, 0.12, 0.6, 0.38, 0.09, YELLOW)
		fill([0.3, 0.14, 0.39, 0.14, 0.31, 0.48, 0.22, 0.48], INK)
		fill([0.47, 0.14, 0.56, 0.14, 0.48, 0.48, 0.39, 0.48], INK)
		shine(0.24, 0.155, 0.44, 0.04, 0.5)

	## Werbeblock: kantige Maschinenpistole, das Magazin steckt im Griff, rosa Streifen.
	func icon_machine_pistol() -> void:
		box(0.43, 0.66, 0.12, 0.28, STEEL)
		box(0.4, 0.44, 0.18, 0.27, STEEL_DARK)
		stroke([0.58, 0.5, 0.6, 0.6, 0.68, 0.6, 0.7, 0.46], INK, 0.035)
		box(0.78, 0.28, 0.15, 0.1, STEEL)
		box(0.06, 0.28, 0.12, 0.11, STEEL_DARK)
		box(0.42, 0.13, 0.1, 0.09, STEEL)
		box(0.7, 0.14, 0.05, 0.08, GUN)
		rbox(0.16, 0.2, 0.64, 0.27, 0.03, GUN)
		bar(0.2, 0.3, 0.52, 0.065, PINK)
		shine(0.2, 0.225, 0.56, 0.03)

	## Zielgerade: Armbrust von oben mit gespanntem Bogen und Bolzen.
	func icon_crossbow() -> void:
		cord([0.55, 0.09, 0.34, 0.5, 0.55, 0.91], WHITE, 0.016)
		shape([0.04, 0.4, 0.22, 0.44, 0.82, 0.455, 0.82, 0.545, 0.22, 0.56, 0.04, 0.6], WOOD)
		bar(0.08, 0.46, 0.12, 0.08, WOOD_DARK)
		cord([0.53, 0.07, 0.67, 0.2, 0.75, 0.36, 0.77, 0.5, 0.75, 0.64, 0.67, 0.8, 0.53, 0.93], STEEL, 0.06)
		cord([0.36, 0.5, 0.88, 0.5], YELLOW, 0.028)
		shape([0.85, 0.42, 0.97, 0.5, 0.85, 0.58], STEEL_LIGHT)
		shape([0.33, 0.5, 0.39, 0.43, 0.47, 0.43, 0.43, 0.5, 0.47, 0.57, 0.39, 0.57], RED)

	## Knalleffekt: Granatwerfer mit dicker Trommel und kurzem, weitem Lauf.
	func icon_grenade_launcher() -> void:
		shape([0.04, 0.3, 0.28, 0.34, 0.28, 0.48, 0.04, 0.54], GUN)
		shape([0.24, 0.56, 0.38, 0.6, 0.34, 0.9, 0.18, 0.88], GUN)
		box(0.64, 0.46, 0.11, 0.26, GUN)
		box(0.54, 0.22, 0.36, 0.25, OLIVE)
		bar(0.65, 0.23, 0.05, 0.23, YELLOW)
		shine(0.56, 0.245, 0.3, 0.035)
		box(0.86, 0.18, 0.09, 0.33, GUN)
		disc(0.42, 0.42, 0.2, STEEL)
		dot(0.42, 0.42, 0.04, GUN)
		for i: int in 5:
			var angle: float = TAU * float(i) / 5.0 - PI * 0.5
			dot(0.42 + cos(angle) * 0.12, 0.42 + sin(angle) * 0.12, 0.042, INK)

	# ---------------------------------------------------------------------------------
	# Waffen, zweihändig (schräg nach oben)
	# ---------------------------------------------------------------------------------

	## Publikumsjoker: lange Pumpflinte mit Holzschaft und Vorderschaft.
	func icon_shotgun() -> void:
		frame(0.5, 0.5, LONG_TILT, LONG_ZOOM)
		shape([0.0, 0.41, 0.26, 0.41, 0.28, 0.56, 0.2, 0.6, 0.0, 0.72], WOOD)
		stroke([0.3, 0.58, 0.33, 0.69, 0.42, 0.67, 0.43, 0.58], INK, 0.03)
		box(0.44, 0.5, 0.48, 0.065, STEEL_DARK)
		box(0.44, 0.41, 0.56, 0.08, STEEL)
		shine(0.46, 0.425, 0.5, 0.025)
		box(0.95, 0.365, 0.035, 0.045, GUN)
		box(0.24, 0.39, 0.22, 0.2, STEEL_DARK)
		# Patronenhalter am Kasten: drei rote Schrotpatronen.
		for i: int in 3:
			bar(0.275 + 0.055 * float(i), 0.43, 0.04, 0.1, RED)
			bar(0.275 + 0.055 * float(i), 0.43, 0.04, 0.03, BRASS)
		rbox(0.54, 0.465, 0.25, 0.14, 0.04, WOOD)
		for i: int in 3:
			bar(0.6 + 0.055 * float(i), 0.49, 0.022, 0.09, WOOD_DARK)

	## Dauerbrenner: Sturmgewehr mit gebogenem Magazin, Holzschaft und Korn.
	func icon_rifle() -> void:
		frame(0.5, 0.5, LONG_TILT, LONG_ZOOM)
		shape([0.0, 0.41, 0.22, 0.44, 0.22, 0.57, 0.0, 0.68], WOOD)
		shape([0.38, 0.56, 0.5, 0.56, 0.58, 0.74, 0.55, 0.9, 0.42, 0.88, 0.45, 0.73], STEEL)
		shape([0.24, 0.56, 0.34, 0.56, 0.31, 0.8, 0.2, 0.8], GUN)
		box(0.76, 0.455, 0.2, 0.05, STEEL)
		box(0.94, 0.43, 0.06, 0.1, GUN)
		box(0.86, 0.35, 0.035, 0.11, GUN)
		rbox(0.5, 0.405, 0.28, 0.15, 0.03, WOOD)
		bar(0.55, 0.45, 0.18, 0.025, WOOD_DARK)
		box(0.2, 0.39, 0.32, 0.18, STEEL_DARK)
		bar(0.3, 0.44, 0.13, 0.045, INK)
		shine(0.22, 0.405, 0.28, 0.025)
		box(0.26, 0.32, 0.06, 0.07, GUN)

	## Fernbedienung: Scharfschützengewehr mit großem Zielfernrohr, langem Lauf und Zweibein.
	func icon_sniper() -> void:
		frame(0.5, 0.5, LONG_TILT, LONG_ZOOM)
		cord([0.72, 0.5, 0.66, 0.74], STEEL_DARK, 0.028)
		cord([0.75, 0.5, 0.83, 0.72], STEEL_DARK, 0.028)
		shape([0.0, 0.44, 0.18, 0.42, 0.32, 0.44, 0.32, 0.58, 0.16, 0.6, 0.13, 0.74, 0.0, 0.74], OLIVE)
		shape([0.28, 0.58, 0.37, 0.58, 0.34, 0.76, 0.25, 0.76], GUN)
		box(0.43, 0.57, 0.09, 0.13, GUN)
		box(0.56, 0.47, 0.4, 0.05, STEEL_DARK)
		box(0.94, 0.445, 0.06, 0.1, GUN)
		box(0.3, 0.44, 0.28, 0.14, OLIVE)
		bar(0.34, 0.37, 0.03, 0.08, INK)
		bar(0.5, 0.37, 0.03, 0.08, INK)
		rbox(0.24, 0.26, 0.4, 0.12, 0.04, GUN)
		box(0.6, 0.23, 0.08, 0.18, GUN)
		bar(0.655, 0.25, 0.022, 0.14, CYAN)
		box(0.2, 0.24, 0.06, 0.16, GUN)
		shine(0.28, 0.28, 0.3, 0.025)

	## Applausmaschine: Minigun mit drei langen Läufen, Motorgehäuse, Tragegriff und Gurtkasten.
	func icon_minigun() -> void:
		frame(0.5, 0.52, -14.0, 0.9)
		box(0.2, 0.64, 0.22, 0.2, OLIVE)
		bar(0.22, 0.68, 0.18, 0.04, YELLOW)
		cord([0.38, 0.66, 0.44, 0.58], BRASS, 0.05)
		box(0.44, 0.32, 0.54, 0.06, STEEL)
		box(0.44, 0.42, 0.56, 0.06, STEEL_LIGHT)
		box(0.44, 0.52, 0.54, 0.06, STEEL)
		box(0.62, 0.29, 0.055, 0.32, STEEL_DARK)
		box(0.88, 0.29, 0.055, 0.32, STEEL_DARK)
		shape([0.0, 0.38, 0.14, 0.4, 0.14, 0.54, 0.0, 0.56], GUN)
		cord([0.2, 0.3, 0.22, 0.17, 0.4, 0.17, 0.42, 0.3], GUN, 0.04)
		rbox(0.12, 0.26, 0.34, 0.4, 0.06, STEEL_DARK)
		bar(0.15, 0.41, 0.28, 0.08, YELLOW)
		for i: int in 3:
			fill([0.18 + 0.09 * float(i), 0.41, 0.22 + 0.09 * float(i), 0.41,
					0.19 + 0.09 * float(i), 0.49, 0.15 + 0.09 * float(i), 0.49], INK)
		shine(0.16, 0.29, 0.26, 0.035)

	## Showfinale: grünes Raketenrohr, vorn schaut die rote Rakete heraus.
	func icon_rocket_launcher() -> void:
		frame(0.52, 0.5, LONG_TILT, 0.92)
		shape([0.76, 0.385, 0.88, 0.385, 1.0, 0.46, 0.88, 0.535, 0.76, 0.535], RED)
		bar(0.82, 0.395, 0.035, 0.13, WHITE)
		shape([0.4, 0.54, 0.5, 0.54, 0.47, 0.78, 0.37, 0.78], GUN)
		shape([0.58, 0.54, 0.66, 0.54, 0.64, 0.72, 0.56, 0.72], GUN)
		box(0.1, 0.36, 0.68, 0.2, OLIVE)
		bar(0.19, 0.37, 0.05, 0.18, YELLOW)
		bar(0.27, 0.37, 0.025, 0.18, YELLOW)
		shine(0.12, 0.385, 0.62, 0.035)
		shape([0.0, 0.3, 0.1, 0.35, 0.1, 0.57, 0.0, 0.62], STEEL_DARK)
		box(0.74, 0.33, 0.06, 0.26, STEEL_DARK)
		box(0.34, 0.24, 0.13, 0.12, GUN)
		bar(0.43, 0.26, 0.025, 0.08, CYAN)

	## Heiße Phase: Flammenwerfer mit rotem Tank unter dem Rohr und Flamme an der Düse.
	func icon_flamethrower() -> void:
		frame(0.5, 0.5, LONG_TILT, 0.94)
		shape([0.78, 0.35, 0.92, 0.23, 0.9, 0.36, 1.04, 0.44, 0.92, 0.52, 0.98, 0.65, 0.78, 0.56], ORANGE)
		fill([0.8, 0.4, 0.88, 0.37, 0.96, 0.445, 0.89, 0.52, 0.8, 0.51], YELLOW)
		cord([0.3, 0.62, 0.5, 0.67, 0.56, 0.52], GUN, 0.03)
		shape([0.5, 0.5, 0.59, 0.5, 0.57, 0.72, 0.48, 0.72], GUN)
		rbox(0.08, 0.56, 0.38, 0.21, 0.1, RED)
		shine(0.14, 0.59, 0.26, 0.035, 0.45)
		box(0.02, 0.62, 0.07, 0.09, STEEL)
		box(0.02, 0.39, 0.62, 0.12, STEEL_DARK)
		shine(0.04, 0.405, 0.54, 0.025)
		box(0.64, 0.42, 0.16, 0.065, STEEL)
		box(0.6, 0.36, 0.08, 0.18, GUN)

	## Rotlicht: helle Strahlenkanone mit roter Energiezelle, Ringen am Lauf und rotem Strahl.
	func icon_beam() -> void:
		frame(0.5, 0.5, LONG_TILT, LONG_ZOOM)
		fill([0.8, 0.43, 1.0, 0.43, 1.0, 0.55, 0.8, 0.55], Color(RED, 0.45))
		fill([0.8, 0.47, 1.0, 0.47, 1.0, 0.51, 0.8, 0.51], Color(1.0, 0.8, 0.8))
		shape([0.22, 0.58, 0.32, 0.58, 0.29, 0.8, 0.18, 0.8], GUN)
		shape([0.48, 0.58, 0.57, 0.58, 0.55, 0.74, 0.46, 0.74], GUN)
		box(0.6, 0.45, 0.2, 0.08, RED)
		box(0.64, 0.39, 0.05, 0.2, GUN)
		box(0.715, 0.41, 0.04, 0.16, GUN)
		box(0.78, 0.43, 0.03, 0.12, GUN)
		shape([0.02, 0.42, 0.14, 0.37, 0.5, 0.35, 0.62, 0.41, 0.62, 0.57, 0.5, 0.61, 0.02, 0.61], STEEL_LIGHT)
		rbox(0.2, 0.42, 0.26, 0.11, 0.04, RED)
		shine(0.24, 0.44, 0.18, 0.025, 0.55)
		bar(0.06, 0.52, 0.1, 0.04, STEEL_DARK)

	## Kurzschluss: blaue Blitzkanone mit Kupferspulen und leuchtender Kugel an der Spitze.
	func icon_tesla() -> void:
		frame(0.5, 0.5, LONG_TILT, LONG_ZOOM)
		shape([0.12, 0.6, 0.24, 0.6, 0.21, 0.84, 0.08, 0.84], GUN)
		box(0.36, 0.455, 0.46, 0.075, STEEL_DARK)
		for i: int in 4:
			rbox(0.42 + 0.1 * float(i), 0.36, 0.06, 0.26, 0.02, COPPER)
		rbox(0.02, 0.36, 0.36, 0.27, 0.06, Color(0.3, 0.45, 1.0))
		shine(0.06, 0.39, 0.28, 0.035)
		disc(0.2, 0.33, 0.08, YELLOW)
		disc(0.9, 0.49, 0.095, CYAN)
		dot(0.87, 0.46, 0.03, WHITE)
		stroke([0.76, 0.26, 0.85, 0.29, 0.8, 0.35, 0.89, 0.38], YELLOW, 0.03)

	## Marathonsendung: Maschinengewehr mit Gurtkasten, Tragegriff, Kühlmantel und Zweibein.
	func icon_lmg() -> void:
		frame(0.5, 0.5, LONG_TILT, LONG_ZOOM)
		cord([0.8, 0.5, 0.74, 0.74], STEEL_DARK, 0.03)
		cord([0.82, 0.5, 0.88, 0.72], STEEL_DARK, 0.03)
		shape([0.0, 0.42, 0.18, 0.42, 0.18, 0.58, 0.0, 0.66], GUN)
		shape([0.14, 0.58, 0.23, 0.58, 0.21, 0.78, 0.11, 0.78], GUN)
		shape([0.37, 0.5, 0.49, 0.5, 0.46, 0.64, 0.34, 0.64], BRASS)
		box(0.26, 0.6, 0.23, 0.22, OLIVE)
		bar(0.28, 0.64, 0.19, 0.04, YELLOW)
		box(0.48, 0.455, 0.5, 0.06, STEEL)
		box(0.94, 0.435, 0.055, 0.1, GUN)
		rbox(0.48, 0.425, 0.27, 0.12, 0.02, GUN)
		for i: int in 3:
			dot(0.54 + 0.075 * float(i), 0.485, 0.022, STEEL_LIGHT)
		box(0.18, 0.39, 0.32, 0.2, STEEL_DARK)
		shine(0.2, 0.405, 0.28, 0.025)
		cord([0.3, 0.39, 0.33, 0.3, 0.45, 0.3, 0.48, 0.39], GUN, 0.035)

	## Zuschauerfrage: automatische Flinte mit großem Trommelmagazin und dickem Lauf.
	func icon_auto_shotgun() -> void:
		frame(0.5, 0.5, LONG_TILT, LONG_ZOOM)
		shape([0.0, 0.42, 0.2, 0.42, 0.2, 0.58, 0.0, 0.67], GUN)
		shape([0.17, 0.58, 0.27, 0.58, 0.25, 0.78, 0.14, 0.78], GUN)
		box(0.78, 0.435, 0.2, 0.09, STEEL)
		box(0.95, 0.415, 0.05, 0.13, GUN)
		box(0.36, 0.56, 0.11, 0.08, STEEL_DARK)
		disc(0.42, 0.74, 0.165, STEEL)
		disc(0.42, 0.74, 0.075, RED)
		dot(0.42, 0.74, 0.025, INK)
		rbox(0.5, 0.4, 0.3, 0.16, 0.03, STEEL_DARK)
		for i: int in 3:
			bar(0.56 + 0.07 * float(i), 0.445, 0.03, 0.07, INK)
		box(0.2, 0.385, 0.32, 0.2, RED)
		bar(0.3, 0.44, 0.12, 0.045, INK)
		shine(0.22, 0.4, 0.28, 0.025)
		box(0.27, 0.31, 0.2, 0.06, GUN)

	# ---------------------------------------------------------------------------------
	# Upgrade-Gegenstände
	# ---------------------------------------------------------------------------------

	## Starkstrom-Sponsor: großer gelber Blitz mit kleinen Funken, die weiterspringen.
	func icon_chain_lightning() -> void:
		stroke([0.08, 0.26, 0.2, 0.33, 0.13, 0.41, 0.25, 0.5], CYAN, 0.035)
		stroke([0.76, 0.58, 0.88, 0.65, 0.81, 0.73, 0.93, 0.82], CYAN, 0.035)
		shape([0.62, 0.04, 0.22, 0.56, 0.45, 0.56, 0.34, 0.96, 0.8, 0.4, 0.56, 0.4], YELLOW)
		gloss([0.58, 0.14, 0.34, 0.48, 0.44, 0.48], 0.5)

	## Spezialmunition: ein Geschoss, das durch zwei Platten schlägt.
	func icon_pierce() -> void:
		shape([0.24, 0.1, 0.36, 0.1, 0.36, 0.9, 0.24, 0.9], STEEL_DARK)
		shape([0.5, 0.1, 0.62, 0.1, 0.62, 0.9, 0.5, 0.9], STEEL)
		shine(0.26, 0.12, 0.03, 0.76, 0.3)
		shine(0.52, 0.12, 0.03, 0.76, 0.4)
		cord([0.09, 0.5, 0.7, 0.5], YELLOW, 0.045)
		star(0.3, 0.5, 0.14, 0.055, 6, WHITE, -60.0)
		star(0.56, 0.5, 0.14, 0.055, 6, WHITE, -60.0)
		bullet(0.66, 0.5, 0.3, 0.18, STEEL_LIGHT)

	## Feuershow: Flamme in drei Schichten.
	func icon_burn() -> void:
		shape([0.5, 0.04, 0.62, 0.24, 0.61, 0.38, 0.72, 0.3, 0.86, 0.56, 0.8, 0.8, 0.62, 0.95,
				0.38, 0.95, 0.2, 0.8, 0.14, 0.58, 0.26, 0.36, 0.35, 0.5, 0.38, 0.26], RED)
		fill([0.5, 0.3, 0.6, 0.48, 0.7, 0.5, 0.74, 0.7, 0.62, 0.88, 0.38, 0.88, 0.26, 0.72, 0.3, 0.56,
				0.4, 0.62, 0.42, 0.44], ORANGE)
		fill([0.5, 0.56, 0.6, 0.7, 0.6, 0.82, 0.5, 0.88, 0.4, 0.82, 0.4, 0.7], YELLOW)

	## Blutspende-Aktion: roter Blutstropfen mit weißem Herz.
	func icon_lifesteal() -> void:
		shape([0.5, 0.04, 0.64, 0.3, 0.76, 0.5, 0.8, 0.66, 0.74, 0.84, 0.6, 0.95, 0.4, 0.95, 0.26, 0.84,
				0.2, 0.66, 0.24, 0.5, 0.36, 0.3], Color(0.9, 0.08, 0.2))
		gloss([0.46, 0.2, 0.36, 0.42, 0.3, 0.58, 0.36, 0.6, 0.42, 0.44], 0.4)
		fill(heart_flat(0.5, 0.68, 0.15), WHITE)

	## Stuntdouble: grünes Herz mit weißem Plus (mehr Leben).
	func icon_max_hp() -> void:
		heart(0.5, 0.48, 0.44, Color(0.2, 0.82, 0.35))
		gloss([0.14, 0.26, 0.24, 0.16, 0.38, 0.16, 0.2, 0.38], 0.4)
		plus(0.5, 0.45, 0.19, 0.11, WHITE)

	## Konfetti-Kanone: Tüte, aus der buntes Konfetti fliegt.
	func icon_corpse_explosion() -> void:
		stroke([0.5, 0.52, 0.58, 0.4, 0.5, 0.3, 0.58, 0.16], PINK, 0.035)
		stroke([0.62, 0.62, 0.76, 0.6, 0.8, 0.48, 0.93, 0.48], CYAN, 0.035)
		shape([0.07, 0.95, 0.27, 0.4, 0.62, 0.74], PURPLE)
		fill([0.2, 0.59, 0.3, 0.44, 0.4, 0.53, 0.27, 0.67], YELLOW)
		fill([0.13, 0.78, 0.36, 0.76, 0.5, 0.8, 0.44, 0.83, 0.1, 0.88], YELLOW)
		rim([0.07, 0.95, 0.27, 0.4, 0.62, 0.74])
		box(0.6, 0.14, 0.11, 0.11, YELLOW)
		box(0.82, 0.26, 0.1, 0.1, GREEN)
		box(0.36, 0.1, 0.09, 0.09, CYAN)
		disc(0.8, 0.1, 0.05, PINK)
		disc(0.7, 0.4, 0.045, WHITE)
		disc(0.9, 0.66, 0.04, YELLOW)

	## Werbepause: Pausenzeichen in der Mitte einer Druckwelle aus Ringen.
	func icon_reload_shockwave() -> void:
		for i: int in 4:
			var start: float = 20.0 + 90.0 * float(i)
			oarc(0.5, 0.5, 0.42, start, start + 50.0, CYAN, 0.045)
		oarc(0.5, 0.5, 0.29, 0.0, 360.0, YELLOW, 0.05)
		box(0.38, 0.37, 0.085, 0.26, WHITE)
		box(0.535, 0.37, 0.085, 0.26, WHITE)

	## Turbo-Turnschuhe: orangefarbener Turnschuh mit Fahrtstreifen.
	func icon_speed() -> void:
		bar(0.03, 0.4, 0.16, 0.04, WHITE)
		bar(0.07, 0.54, 0.12, 0.04, WHITE)
		bar(0.03, 0.68, 0.14, 0.04, WHITE)
		shape([0.26, 0.74, 0.26, 0.3, 0.44, 0.26, 0.52, 0.44, 0.7, 0.5, 0.9, 0.58, 0.96, 0.74], ORANGE)
		fill([0.28, 0.32, 0.43, 0.29, 0.47, 0.38, 0.29, 0.44], WOOD_DARK)
		fill([0.32, 0.68, 0.6, 0.56, 0.66, 0.6, 0.38, 0.74], YELLOW)
		for i: int in 3:
			stroke([0.5 + 0.07 * float(i), 0.5 + 0.025 * float(i), 0.56 + 0.07 * float(i), 0.42 + 0.025 * float(i)], WHITE, 0.03)
		shape([0.22, 0.72, 0.94, 0.72, 0.97, 0.79, 0.93, 0.86, 0.24, 0.86, 0.2, 0.79], WHITE)
		bar(0.26, 0.8, 0.66, 0.025, STEEL)

	## Publikumsliebling: lachender gelber Stern.
	func icon_luck() -> void:
		star(0.5, 0.54, 0.47, 0.22, 5, YELLOW)
		gloss([0.5, 0.16, 0.42, 0.38, 0.5, 0.38], 0.5)
		dot(0.42, 0.5, 0.04, INK)
		dot(0.58, 0.5, 0.04, INK)
		arc(0.5, 0.56, 0.11, 25.0, 155.0, INK, 0.035)
		sparkle(0.12, 0.16, 0.09)
		sparkle(0.88, 0.14, 0.07)

	## Zugabe: zwei Patronen nebeneinander und ein Plus.
	func icon_extra_shot() -> void:
		bar(0.06, 0.3, 0.2, 0.035, WHITE)
		bar(0.02, 0.64, 0.12, 0.035, WHITE)
		bullet(0.3, 0.32, 0.64, 0.22)
		bullet(0.18, 0.68, 0.64, 0.22)
		box(0.72, 0.6, 0.22, 0.07, GREEN)
		box(0.795, 0.525, 0.07, 0.22, GREEN)
		bar(0.73, 0.61, 0.2, 0.05, GREEN)

	## Kantinenessen: Teller mit grünlichem Brei und grünem Dampf.
	func icon_poison() -> void:
		cord([0.32, 0.46, 0.26, 0.38, 0.34, 0.3, 0.28, 0.2, 0.33, 0.12], SLIME, 0.04)
		cord([0.5, 0.42, 0.44, 0.33, 0.54, 0.24, 0.47, 0.15, 0.52, 0.08], SLIME, 0.04)
		cord([0.68, 0.46, 0.62, 0.38, 0.7, 0.3, 0.64, 0.2, 0.69, 0.12], SLIME, 0.04)
		oval(0.5, 0.78, 0.45, 0.15, WHITE)
		blob(0.5, 0.77, 0.32, 0.09, STEEL)
		shape([0.24, 0.76, 0.27, 0.62, 0.38, 0.52, 0.5, 0.56, 0.6, 0.5, 0.72, 0.6, 0.76, 0.76, 0.5, 0.82],
				Color(0.5, 0.62, 0.12))
		dot(0.4, 0.66, 0.045, SLIME)
		dot(0.6, 0.62, 0.035, SLIME)
		dot(0.52, 0.72, 0.03, SLIME)

	## Glücksrad: buntes Rad mit Feldern und rotem Zeiger oben.
	func icon_crit() -> void:
		var colors: Array[Color] = [PINK, YELLOW, CYAN, WHITE]
		for i: int in 8:
			var flat: Array = [0.5, 0.56]
			flat.append_array(arc_flat(0.5, 0.56, 0.4, 45.0 * float(i) - 22.5, 45.0 * float(i) + 22.5))
			fill(flat, colors[i % colors.size()])
		for i: int in 8:
			var dir: Vector2 = Vector2.from_angle(deg_to_rad(45.0 * float(i) - 22.5))
			stroke([0.5, 0.56, 0.5 + dir.x * 0.4, 0.56 + dir.y * 0.4], INK, 0.02)
		arc(0.5, 0.56, 0.4, 0.0, 360.0, INK, OUTLINE * 1.3)
		disc(0.5, 0.56, 0.08, STEEL_LIGHT)
		shape([0.4, 0.03, 0.6, 0.03, 0.5, 0.27], RED)

	## Überlänge: langes gebogenes Magazin mit gelber Verlängerung, oben liegt eine Patrone.
	func icon_big_mag() -> void:
		frame(0.42, 0.14, -12.0, 1.0)
		bullet(0.32, 0.5, 0.4, 0.11)
		unframe()
		var body: Array = [0.25, 0.21, 0.54, 0.15, 0.58, 0.38, 0.67, 0.6, 0.83, 0.82, 0.58, 0.95, 0.42, 0.7, 0.31, 0.45]
		fill(body, STEEL)
		fill([0.42, 0.7, 0.67, 0.6, 0.83, 0.82, 0.58, 0.95], YELLOW)
		stroke([0.42, 0.7, 0.67, 0.6], INK, 0.025)
		stroke([0.3, 0.33, 0.55, 0.27], STEEL_DARK, 0.035)
		stroke([0.35, 0.5, 0.6, 0.42], STEEL_DARK, 0.035)
		gloss([0.28, 0.24, 0.33, 0.23, 0.38, 0.45, 0.47, 0.67, 0.43, 0.68, 0.33, 0.46], 0.4)
		rim(body)

	## Teleprompter: Fadenkreuz mit rotem Punkt (genauer zielen, stärkere Kopfschüsse).
	func icon_scope() -> void:
		oarc(0.5, 0.5, 0.33, 0.0, 360.0, CYAN, 0.07)
		box(0.465, 0.04, 0.07, 0.3, WHITE)
		box(0.465, 0.66, 0.07, 0.3, WHITE)
		box(0.04, 0.465, 0.3, 0.07, WHITE)
		box(0.66, 0.465, 0.3, 0.07, WHITE)
		disc(0.5, 0.5, 0.07, RED)

	## Schnelldurchlauf: Vorspulen-Zeichen aus zwei Dreiecken.
	func icon_fire_rate() -> void:
		bar(0.02, 0.36, 0.1, 0.04, WHITE)
		bar(0.02, 0.6, 0.1, 0.04, WHITE)
		shape([0.14, 0.18, 0.54, 0.5, 0.14, 0.82], CYAN)
		shape([0.5, 0.18, 0.92, 0.5, 0.5, 0.82], CYAN)
		gloss([0.18, 0.27, 0.42, 0.46, 0.18, 0.46], 0.45)
		gloss([0.54, 0.27, 0.78, 0.46, 0.54, 0.46], 0.45)

	## Sicherheitsglas: gläserner Schild mit Rahmen und Spiegelung.
	func icon_shield() -> void:
		shape([0.5, 0.04, 0.9, 0.17, 0.88, 0.55, 0.74, 0.8, 0.5, 0.96, 0.26, 0.8, 0.12, 0.55, 0.1, 0.17], STEEL_LIGHT)
		shape([0.5, 0.15, 0.8, 0.25, 0.78, 0.53, 0.67, 0.73, 0.5, 0.84, 0.33, 0.73, 0.22, 0.53, 0.2, 0.25], GLASS)
		gloss([0.3, 0.3, 0.46, 0.25, 0.28, 0.56, 0.25, 0.48], 0.6)
		gloss([0.54, 0.24, 0.62, 0.26, 0.38, 0.7, 0.34, 0.66], 0.45)

	## Trostpflaster: schräges Pflaster mit Wundkissen und kleinem Herz.
	func icon_kill_heal() -> void:
		frame(0.5, 0.5, -35.0, 0.95)
		rbox(0.0, 0.34, 1.0, 0.32, 0.16, Color(1.0, 0.76, 0.56))
		box(0.34, 0.34, 0.32, 0.32, Color(1.0, 0.92, 0.8))
		for i: int in 2:
			for j: int in 2:
				dot(0.14 + 0.1 * float(i), 0.44 + 0.12 * float(j), 0.022, WOOD_DARK)
				dot(0.76 + 0.1 * float(i), 0.44 + 0.12 * float(j), 0.022, WOOD_DARK)
		unframe()
		fill(heart_flat(0.5, 0.5, 0.09), RED)

	## Discokugel: Spiegelkugel an einer Schnur mit bunten Facetten und Funkeln.
	func icon_disco_ball() -> void:
		stroke([0.5, 0.02, 0.5, 0.16], STEEL_LIGHT, 0.03)
		box(0.43, 0.12, 0.14, 0.07, STEEL_DARK)
		disc(0.5, 0.57, 0.38, STEEL_LIGHT)
		var tiles: Array = [0.3, 0.38, CYAN, 0.52, 0.38, PINK, 0.2, 0.56, YELLOW, 0.42, 0.56, WHITE,
				0.64, 0.56, CYAN, 0.3, 0.74, PINK, 0.54, 0.74, YELLOW]
		for i: int in range(0, tiles.size(), 3):
			bar(float(tiles[i]), float(tiles[i + 1]), 0.14, 0.12, tiles[i + 2] as Color)
		for dy: float in [-0.19, 0.0, 0.19]:
			var half: float = sqrt(0.38 * 0.38 - dy * dy)
			stroke([0.5 - half, 0.57 + dy, 0.5 + half, 0.57 + dy], INK, 0.018)
		for k: float in [-0.55, 0.0, 0.55]:
			var flat: Array = []
			for i: int in 9:
				var y: float = lerpf(-0.37, 0.37, float(i) / 8.0)
				flat.append(0.5 + k * sqrt(maxf(0.38 * 0.38 - y * y, 0.0)))
				flat.append(0.57 + y)
			stroke(flat, INK, 0.018)
		rim(ellipse(0.5, 0.57, 0.38, 0.38, 24))
		sparkle(0.14, 0.24, 0.1)
		sparkle(0.86, 0.3, 0.08)

	## Störsender: Kasten mit Antenne, von der Wellen nach beiden Seiten gehen.
	func icon_jammer() -> void:
		for r: float in [0.17, 0.3]:
			oarc(0.5, 0.3, r, -45.0, 45.0, RED, 0.035)
			oarc(0.5, 0.3, r, 135.0, 225.0, RED, 0.035)
		cord([0.5, 0.64, 0.5, 0.32], STEEL_LIGHT, 0.035)
		disc(0.5, 0.3, 0.06, YELLOW)
		rbox(0.24, 0.62, 0.52, 0.32, 0.05, STEEL_DARK)
		shine(0.28, 0.65, 0.44, 0.035)
		disc(0.38, 0.8, 0.07, GUN)
		dot(0.38, 0.8, 0.025, CYAN)
		bar(0.52, 0.74, 0.16, 0.035, GREEN)
		bar(0.52, 0.82, 0.16, 0.035, RED)

	## Notausgang: grünes Schild mit laufender Figur und Pfeil.
	func icon_dash() -> void:
		rbox(0.04, 0.18, 0.92, 0.64, 0.07, Color(0.1, 0.72, 0.32))
		var border: Array = round_rect(0.1, 0.24, 0.8, 0.52, 0.04)
		border.append_array([border[0], border[1]])
		stroke(border, Color(1.0, 1.0, 1.0, 0.6), 0.018)
		dot(0.37, 0.35, 0.06, WHITE)
		stroke([0.36, 0.42, 0.31, 0.56], WHITE, 0.065)
		stroke([0.22, 0.5, 0.34, 0.44, 0.44, 0.52], WHITE, 0.045)
		stroke([0.31, 0.56, 0.42, 0.62, 0.4, 0.72], WHITE, 0.05)
		stroke([0.31, 0.56, 0.24, 0.66, 0.14, 0.66], WHITE, 0.05)
		fill([0.54, 0.455, 0.7, 0.455, 0.7, 0.38, 0.86, 0.5, 0.7, 0.62, 0.7, 0.545, 0.54, 0.545], WHITE)

	## Trockeneis: Eiswürfel, von dem weißer Nebel aufsteigt und unten herausquillt.
	func icon_frost() -> void:
		for x: float in [0.34, 0.62]:
			var wisp: Array = []
			for i: int in 9:
				var t: float = float(i) / 8.0
				wisp.append(x + 0.035 * sin(t * TAU * 1.25))
				wisp.append(lerpf(0.23, 0.06, t))
			cord(wisp, WHITE, 0.03)
		shape([0.5, 0.2, 0.84, 0.33, 0.5, 0.48, 0.16, 0.33], Color(0.88, 0.98, 1.0))
		shape([0.16, 0.33, 0.5, 0.48, 0.5, 0.88, 0.16, 0.7], Color(0.55, 0.86, 1.0))
		shape([0.5, 0.48, 0.84, 0.33, 0.84, 0.7, 0.5, 0.88], Color(0.32, 0.68, 0.98))
		gloss([0.2, 0.41, 0.26, 0.44, 0.26, 0.66, 0.2, 0.63], 0.6)
		gloss([0.56, 0.52, 0.62, 0.49, 0.62, 0.76, 0.56, 0.79], 0.35)
		oval(0.14, 0.86, 0.11, 0.07, WHITE)
		oval(0.86, 0.86, 0.11, 0.07, WHITE)
		oval(0.32, 0.9, 0.12, 0.07, WHITE)
		oval(0.68, 0.9, 0.12, 0.07, WHITE)
		blob(0.5, 0.92, 0.12, 0.05, WHITE)

	## Eröffnungsgag: roter Bühnenvorhang geht auf, im Lichtkegel steht die erste Patrone.
	func icon_opener() -> void:
		bar(0.1, 0.2, 0.8, 0.72, Color(0.2, 0.13, 0.42))
		fill([0.5, 0.3, 0.72, 0.93, 0.28, 0.93], Color(1.0, 0.95, 0.6, 0.3))
		bullet_up(0.5, 0.93, 0.56, 0.2)
		sparkle(0.39, 0.42, 0.07)
		sparkle(0.62, 0.6, 0.05)
		shape([0.06, 0.2, 0.42, 0.2, 0.3, 0.5, 0.22, 0.94, 0.06, 0.94], RED)
		shape([0.94, 0.2, 0.58, 0.2, 0.7, 0.5, 0.78, 0.94, 0.94, 0.94], RED)
		stroke([0.15, 0.26, 0.13, 0.9], Color(0.6, 0.05, 0.1), 0.03)
		stroke([0.85, 0.26, 0.87, 0.9], Color(0.6, 0.05, 0.1), 0.03)
		box(0.22, 0.52, 0.1, 0.07, YELLOW)
		box(0.68, 0.52, 0.1, 0.07, YELLOW)
		shape([0.04, 0.06, 0.96, 0.06, 0.96, 0.2, 0.84, 0.27, 0.72, 0.2, 0.61, 0.27, 0.5, 0.2, 0.39, 0.27,
				0.28, 0.2, 0.16, 0.27, 0.04, 0.2], Color(0.78, 0.08, 0.14))
		bar(0.06, 0.08, 0.88, 0.035, YELLOW)

	## Schlusspointe: Knall mit Ausrufezeichen (die letzte Kugel explodiert).
	func icon_punchline() -> void:
		star(0.5, 0.5, 0.47, 0.3, 9, ORANGE, -80.0)
		fill(star_flat(0.5, 0.5, 0.33, 0.2, 9, -60.0), YELLOW)
		shape([0.43, 0.24, 0.57, 0.24, 0.54, 0.58, 0.46, 0.58], INK)
		disc(0.5, 0.7, 0.055, INK)

	## Querschläger: Geschoss prallt vom Boden ab und fliegt weiter.
	func icon_ricochet() -> void:
		box(0.04, 0.8, 0.92, 0.14, STEEL_DARK)
		for i: int in 4:
			fill([0.1 + 0.22 * float(i), 0.82, 0.18 + 0.22 * float(i), 0.82, 0.12 + 0.22 * float(i), 0.92,
					0.04 + 0.22 * float(i), 0.92], YELLOW)
		rim([0.04, 0.8, 0.96, 0.8, 0.96, 0.94, 0.04, 0.94])
		stroke([0.08, 0.2, 0.2, 0.4], WHITE, 0.03)
		cord([0.14, 0.14, 0.44, 0.74, 0.76, 0.3], YELLOW, 0.06)
		arrow_head(0.74, 0.33, -54.0, 0.22, 0.13, YELLOW)
		star(0.44, 0.76, 0.14, 0.06, 6, WHITE)

	## Kaktus-Requisite: Kaktus mit zwei Armen im Tontopf.
	func icon_thorns() -> void:
		var pot: Color = Color(0.9, 0.48, 0.26)
		rbox(0.14, 0.26, 0.12, 0.3, 0.06, LEAF)
		rbox(0.14, 0.44, 0.3, 0.12, 0.06, LEAF)
		bar(0.17, 0.3, 0.06, 0.2, LEAF)
		rbox(0.74, 0.34, 0.12, 0.3, 0.06, LEAF)
		rbox(0.56, 0.52, 0.3, 0.12, 0.06, LEAF)
		bar(0.77, 0.4, 0.06, 0.2, LEAF)
		rbox(0.38, 0.08, 0.24, 0.66, 0.12, LEAF)
		stroke([0.46, 0.16, 0.46, 0.66], Color(0.1, 0.5, 0.2), 0.025)
		stroke([0.54, 0.16, 0.54, 0.66], Color(0.1, 0.5, 0.2), 0.025)
		for i: int in 3:
			stroke([0.36, 0.2 + 0.16 * float(i), 0.3, 0.17 + 0.16 * float(i)], WHITE, 0.025)
			stroke([0.64, 0.24 + 0.14 * float(i), 0.7, 0.21 + 0.14 * float(i)], WHITE, 0.025)
		disc(0.5, 0.09, 0.06, PINK)
		shape([0.3, 0.74, 0.7, 0.74, 0.64, 0.95, 0.36, 0.95], pot)
		box(0.26, 0.67, 0.48, 0.09, Color(1.0, 0.6, 0.36))

	## Zweite Staffel: Filmklappe mit einer großen 2.
	func icon_revive() -> void:
		box(0.08, 0.4, 0.84, 0.54, PINK)
		box(0.08, 0.4, 0.84, 0.13, WHITE)
		for i: int in 4:
			fill([0.16 + 0.2 * float(i), 0.4, 0.26 + 0.2 * float(i), 0.4, 0.2 + 0.2 * float(i), 0.53,
					0.1 + 0.2 * float(i), 0.53], INK)
		shape([0.07, 0.26, 0.88, 0.06, 0.92, 0.2, 0.1, 0.4], WHITE)
		for i: int in 4:
			var t: float = 0.1 + 0.22 * float(i)
			fill([lerpf(0.07, 0.88, t), lerpf(0.26, 0.06, t), lerpf(0.07, 0.88, t + 0.1), lerpf(0.26, 0.06, t + 0.1),
					lerpf(0.1, 0.92, t + 0.14), lerpf(0.4, 0.2, t + 0.14), lerpf(0.1, 0.92, t + 0.04), lerpf(0.4, 0.2, t + 0.04)], INK)
		rim([0.07, 0.26, 0.88, 0.06, 0.92, 0.2, 0.1, 0.4])
		disc(0.12, 0.36, 0.045, STEEL)
		cord([0.38, 0.66, 0.42, 0.6, 0.5, 0.58, 0.58, 0.61, 0.6, 0.68, 0.4, 0.86, 0.63, 0.86], WHITE, 0.055)

	## Pausensnack: Donut mit rosa Zuckerguss und bunten Streuseln.
	func icon_snack() -> void:
		for half: int in 2:
			var from_deg: float = 180.0 * float(half)
			fill(band_flat(0.5, 0.52, 0.13, 0.42, from_deg, from_deg + 180.0), Color(0.93, 0.66, 0.36))
			# Zuckerguss mit welligem Rand.
			var icing: Array = []
			for i: int in 19:
				var angle: float = deg_to_rad(from_deg + 10.0 * float(i))
				var radius: float = 0.35 + 0.022 * sin(angle * 7.0)
				icing.append(0.5 + cos(angle) * radius)
				icing.append(0.5 + sin(angle) * radius)
			icing.append_array(arc_flat(0.5, 0.5, 0.18, from_deg + 180.0, from_deg))
			fill(icing, PINK)
		arc(0.5, 0.52, 0.42, 0.0, 360.0, INK, OUTLINE)
		arc(0.5, 0.52, 0.13, 0.0, 360.0, INK, OUTLINE)
		arc(0.5, 0.5, 0.3, 200.0, 250.0, Color(1.0, 0.62, 0.8), 0.035)
		var sprinkles: Array = [0.3, 0.36, 40.0, WHITE, 0.5, 0.24, -20.0, YELLOW, 0.7, 0.36, 60.0, CYAN,
				0.76, 0.56, 10.0, WHITE, 0.62, 0.74, -50.0, YELLOW, 0.36, 0.72, 30.0, CYAN, 0.24, 0.54, 80.0, YELLOW]
		for i: int in range(0, sprinkles.size(), 4):
			var dir: Vector2 = Vector2.from_angle(deg_to_rad(float(sprinkles[i + 2]))) * 0.04
			var x: float = float(sprinkles[i])
			var y: float = float(sprinkles[i + 1])
			stroke([x - dir.x, y - dir.y, x + dir.x, y + dir.y], sprinkles[i + 3] as Color, 0.035)

	## Requisitenbombe: flache Mine mit Warnstreifen und rotem Blinklicht.
	func icon_mine() -> void:
		for angle: float in [-90.0, -40.0, -140.0]:
			var dir: Vector2 = Vector2.from_angle(deg_to_rad(angle))
			stroke([0.5 + dir.x * 0.2, 0.4 + dir.y * 0.2, 0.5 + dir.x * 0.32, 0.4 + dir.y * 0.32], RED, 0.04)
		oval(0.5, 0.74, 0.45, 0.17, GUN)
		bar(0.05, 0.6, 0.9, 0.14, GUN)
		for i: int in 5:
			fill([0.1 + 0.18 * float(i), 0.62, 0.18 + 0.18 * float(i), 0.64, 0.14 + 0.18 * float(i), 0.78,
					0.06 + 0.18 * float(i), 0.76], YELLOW)
		stroke([0.05, 0.6, 0.05, 0.74], INK, OUTLINE)
		stroke([0.95, 0.6, 0.95, 0.74], INK, OUTLINE)
		oval(0.5, 0.6, 0.45, 0.17, OLIVE)
		oval(0.5, 0.58, 0.24, 0.085, STEEL_DARK)
		disc(0.5, 0.5, 0.1, RED)
		dot(0.47, 0.47, 0.03, WHITE)

	# ---------------------------------------------------------------------------------
	# Kameras
	# ---------------------------------------------------------------------------------

	## Kameradrohne: fliegende Kamera mit zwei Rotoren und Landekufen.
	func icon_drone() -> void:
		cord([0.14, 0.86, 0.28, 0.72, 0.34, 0.6], STEEL_DARK, 0.03)
		cord([0.86, 0.86, 0.72, 0.72, 0.66, 0.6], STEEL_DARK, 0.03)
		cord([0.16, 0.34, 0.84, 0.34], GUN, 0.05)
		box(0.14, 0.22, 0.06, 0.12, GUN)
		box(0.8, 0.22, 0.06, 0.12, GUN)
		oval(0.17, 0.19, 0.15, 0.04, CYAN)
		oval(0.83, 0.19, 0.15, 0.04, CYAN)
		camera_body(0.28, 0.28, 0.44, 0.34)
		lens(0.5, 0.58, 0.15)
		dot(0.64, 0.36, 0.03, RED)

	## Tele-Kamera: Kamera mit sehr langem, weitem Objektiv.
	func icon_cam_tele() -> void:
		box(0.1, 0.24, 0.16, 0.12, GUN)
		camera_body(0.04, 0.34, 0.36, 0.38)
		dot(0.12, 0.47, 0.03, RED)
		var barrel: Array = [0.4, 0.43, 0.76, 0.37, 0.76, 0.69, 0.4, 0.63]
		fill(barrel, GUN)
		fill([0.47, 0.418, 0.52, 0.41, 0.52, 0.65, 0.47, 0.642], STEEL)
		fill([0.63, 0.392, 0.68, 0.383, 0.68, 0.677, 0.63, 0.668], STEEL)
		gloss([0.42, 0.445, 0.74, 0.392, 0.74, 0.44, 0.42, 0.485], 0.25)
		rim(barrel)
		box(0.76, 0.28, 0.19, 0.5, STEEL_DARK)
		bar(0.885, 0.31, 0.045, 0.44, GLASS)

	## Blitzlicht-Kamera: Fotoapparat mit grellem Blitz obenauf.
	func icon_cam_flash() -> void:
		box(0.38, 0.3, 0.24, 0.16, STEEL_DARK)
		box(0.72, 0.38, 0.12, 0.07, RED)
		camera_body(0.1, 0.44, 0.8, 0.48)
		lens(0.5, 0.69, 0.18)
		star(0.5, 0.24, 0.2, 0.09, 8, YELLOW)
		dot(0.5, 0.24, 0.06, WHITE)

	## Zeitlupen-Kamera: Kamera, deren Linse eine Uhr ist.
	func icon_cam_slow() -> void:
		box(0.34, 0.1, 0.32, 0.12, GUN)
		camera_body(0.06, 0.2, 0.88, 0.68)
		dot(0.82, 0.31, 0.035, RED)
		disc(0.5, 0.56, 0.29, CYAN)
		disc(0.5, 0.56, 0.21, WHITE)
		for i: int in 4:
			var dir: Vector2 = Vector2.from_angle(TAU * float(i) / 4.0)
			stroke([0.5 + dir.x * 0.15, 0.56 + dir.y * 0.15, 0.5 + dir.x * 0.2, 0.56 + dir.y * 0.2], INK, 0.025)
		stroke([0.5, 0.56, 0.5, 0.41], INK, 0.04)
		stroke([0.5, 0.56, 0.6, 0.62], INK, 0.04)
		dot(0.5, 0.56, 0.03, INK)

	## Regie-Kamera: Filmkamera mit zwei Spulen, die ihr Ziel rot markiert.
	func icon_cam_director() -> void:
		disc(0.28, 0.24, 0.18, GUN)
		dot(0.28, 0.24, 0.06, STEEL_LIGHT)
		disc(0.6, 0.22, 0.15, GUN)
		dot(0.6, 0.22, 0.05, STEEL_LIGHT)
		shape([0.68, 0.52, 0.95, 0.4, 0.95, 0.84, 0.68, 0.72], GUN)
		bar(0.9, 0.45, 0.03, 0.34, GLASS)
		camera_body(0.1, 0.4, 0.6, 0.46)
		oarc(0.4, 0.64, 0.12, 0.0, 360.0, RED, 0.04)
		bar(0.385, 0.47, 0.03, 0.34, RED)
		bar(0.23, 0.625, 0.34, 0.03, RED)
		dot(0.4, 0.64, 0.045, RED)

	# ---------------------------------------------------------------------------------
	# Kamera-Zubehör
	# ---------------------------------------------------------------------------------

	## Großes Objektiv: Linse von vorn mit Ringen und Spiegelung.
	func icon_cam_lens() -> void:
		disc(0.5, 0.5, 0.45, GUN)
		for i: int in 12:
			var dir: Vector2 = Vector2.from_angle(TAU * float(i) / 12.0)
			stroke([0.5 + dir.x * 0.38, 0.5 + dir.y * 0.38, 0.5 + dir.x * 0.44, 0.5 + dir.y * 0.44], STEEL_LIGHT, 0.03)
		disc(0.5, 0.5, 0.35, STEEL)
		disc(0.5, 0.5, 0.27, Color(0.25, 0.45, 1.0))
		dot(0.5, 0.5, 0.17, Color(0.12, 0.16, 0.5))
		arc(0.5, 0.5, 0.21, 200.0, 280.0, Color(0.7, 0.9, 1.0), 0.04)
		dot(0.41, 0.41, 0.06, WHITE)
		dot(0.58, 0.6, 0.03, Color(1.0, 1.0, 1.0, 0.7))

	## Zoom: Lupe mit Pluszeichen.
	func icon_cam_zoom() -> void:
		cord([0.64, 0.64, 0.88, 0.88], WOOD, 0.1)
		disc(0.42, 0.42, 0.36, STEEL_LIGHT)
		disc(0.42, 0.42, 0.27, GLASS)
		gloss([0.24, 0.36, 0.3, 0.26, 0.4, 0.21, 0.32, 0.32, 0.28, 0.42], 0.6)
		plus(0.42, 0.42, 0.15, 0.07, INK)

	## Akkupack: Batterie mit drei grünen Ladebalken und Blitz.
	func icon_cam_battery() -> void:
		box(0.41, 0.05, 0.18, 0.09, STEEL)
		rbox(0.24, 0.13, 0.52, 0.82, 0.07, GUN)
		for i: int in 3:
			bar(0.31, 0.7 - 0.22 * float(i), 0.38, 0.17, GREEN)
		shine(0.29, 0.17, 0.05, 0.72, 0.3)
		shape([0.56, 0.24, 0.36, 0.56, 0.48, 0.56, 0.42, 0.84, 0.66, 0.48, 0.53, 0.48], YELLOW)

	## Zweitkamera: zwei Fotoapparate hintereinander.
	func icon_cam_second() -> void:
		box(0.16, 0.08, 0.16, 0.08, GUN)
		camera_body(0.05, 0.14, 0.58, 0.4, CAM_DARK)
		lens(0.34, 0.34, 0.13, CYAN)
		box(0.5, 0.4, 0.18, 0.09, GUN)
		camera_body(0.3, 0.47, 0.65, 0.46)
		lens(0.62, 0.7, 0.16)
		dot(0.86, 0.56, 0.03, RED)

	## Sendeleitung: Satellitenschüssel, die Funkwellen nach oben schickt.
	func icon_cam_uplink() -> void:
		oarc(0.6, 0.36, 0.15, -85.0, 5.0, YELLOW, 0.035)
		oarc(0.6, 0.36, 0.27, -85.0, 5.0, YELLOW, 0.035)
		shape([0.3, 0.95, 0.42, 0.62, 0.54, 0.62, 0.66, 0.95], STEEL_DARK)
		frame(0.44, 0.52, -40.0, 1.0)
		var bowl: Array = arc_flat(0.5, 0.5, 0.34, 0.0, 180.0)
		shape(bowl, STEEL_LIGHT)
		oval(0.5, 0.5, 0.34, 0.07, STEEL)
		cord([0.5, 0.5, 0.5, 0.3], STEEL_DARK, 0.03)
		disc(0.5, 0.28, 0.055, RED)
		unframe()

	# ---------------------------------------------------------------------------------
	# Verstärker
	# ---------------------------------------------------------------------------------

	## Scheinwerfer: Bühnenstrahler an einer Klemme, sein Lichtkegel fällt auf den Boden.
	func icon_spotlight() -> void:
		fill([0.41, 0.36, 0.67, 0.57, 0.6, 0.88, 0.04, 0.88], Color(YELLOW, 0.45))
		blob(0.32, 0.88, 0.28, 0.07, Color(1.0, 0.97, 0.7, 0.9))
		box(0.72, 0.05, 0.16, 0.08, STEEL_DARK)
		cord([0.8, 0.13, 0.7, 0.28], STEEL_DARK, 0.04)
		frame(0.64, 0.34, 40.0, 0.8)
		rbox(0.41, 0.19, 0.18, 0.1, 0.03, STEEL_DARK)
		shape([0.38, 0.26, 0.62, 0.26, 0.7, 0.62, 0.3, 0.62], GUN)
		bar(0.37, 0.36, 0.26, 0.035, STEEL_DARK)
		bar(0.35, 0.45, 0.3, 0.035, STEEL_DARK)
		gloss([0.4, 0.28, 0.45, 0.28, 0.39, 0.6, 0.33, 0.6], 0.35)
		box(0.27, 0.62, 0.46, 0.08, YELLOW)
		shine(0.3, 0.635, 0.18, 0.03, 0.7)
		unframe()

	## Ladehilfe: gerades Magazin mit Patrone obenauf, daneben zwei Pfeile nach oben.
	func icon_speed_loader() -> void:
		bullet(0.13, 0.15, 0.38, 0.12)
		shape([0.12, 0.22, 0.46, 0.22, 0.5, 0.94, 0.16, 0.94], STEEL_DARK)
		for i: int in 3:
			bar(0.18 + 0.008 * float(i), 0.4 + 0.16 * float(i), 0.27, 0.035, STEEL_LIGHT)
		shine(0.16, 0.26, 0.04, 0.62, 0.3)
		shape([0.56, 0.42, 0.75, 0.16, 0.94, 0.42, 0.94, 0.56, 0.75, 0.34, 0.56, 0.56], GREEN)
		shape([0.56, 0.74, 0.75, 0.48, 0.94, 0.74, 0.94, 0.88, 0.75, 0.66, 0.56, 0.88], GREEN)

	## Sparschwein: rosa Schwein, in dessen Schlitz eine Goldmünze fällt.
	func icon_piggy_bank() -> void:
		disc(0.44, 0.17, 0.12, YELLOW)
		arc(0.44, 0.17, 0.07, 0.0, 360.0, ORANGE, 0.025)
		cord([0.14, 0.6, 0.07, 0.54, 0.1, 0.46, 0.16, 0.5], PIG_DARK, 0.03)
		box(0.24, 0.78, 0.12, 0.16, PIG_DARK)
		box(0.56, 0.78, 0.12, 0.16, PIG_DARK)
		shape([0.58, 0.36, 0.66, 0.2, 0.76, 0.4], PIG_DARK)
		oval(0.48, 0.6, 0.36, 0.27, PIG)
		gloss(ellipse(0.38, 0.48, 0.16, 0.07, 14), 0.4)
		bar(0.34, 0.37, 0.2, 0.035, INK)
		rbox(0.76, 0.52, 0.18, 0.2, 0.06, PIG_DARK)
		dot(0.83, 0.62, 0.022, INK)
		dot(0.89, 0.62, 0.022, INK)
		dot(0.68, 0.52, 0.03, INK)

	## Wiederholung: Kreispfeil um ein Abspielen-Dreieck.
	func icon_replay() -> void:
		oarc(0.5, 0.53, 0.34, 40.0, 310.0, YELLOW, 0.1)
		var end: Vector2 = Vector2(0.5, 0.53) + Vector2.from_angle(deg_to_rad(310.0)) * 0.34
		arrow_head(end.x, end.y, 40.0, 0.2, 0.15, YELLOW)
		shape([0.42, 0.38, 0.68, 0.53, 0.42, 0.68], PINK)

	# ---------------------------------------------------------------------------------
	# Rucksack-Teile (vier Taschen, von klein nach groß)
	# ---------------------------------------------------------------------------------

	## Bauchtasche: kleine Tasche am Gurt mit Reißverschluss und Schnalle.
	func icon_bag_tiny() -> void:
		var teal: Color = Color(0.15, 0.78, 0.72)
		box(0.04, 0.4, 0.92, 0.1, GUN)
		box(0.84, 0.37, 0.09, 0.16, STEEL_LIGHT)
		shape([0.24, 0.36, 0.76, 0.36, 0.8, 0.56, 0.7, 0.7, 0.3, 0.7, 0.2, 0.56], teal)
		gloss([0.28, 0.39, 0.72, 0.39, 0.73, 0.43, 0.27, 0.43], 0.35)
		stroke([0.28, 0.5, 0.72, 0.5], INK, 0.025)
		box(0.64, 0.47, 0.05, 0.1, YELLOW)

	## Jutebeutel: heller Stoffbeutel mit zwei Henkeln und aufgedrucktem Stern.
	func icon_bag_small() -> void:
		cord([0.36, 0.38, 0.36, 0.2, 0.42, 0.13, 0.58, 0.13, 0.64, 0.2, 0.64, 0.38], Color(0.8, 0.68, 0.45), 0.045)
		shape([0.24, 0.34, 0.76, 0.34, 0.8, 0.9, 0.2, 0.9], CLOTH)
		stroke([0.26, 0.4, 0.74, 0.4], Color(0.8, 0.68, 0.45), 0.025)
		fill(star_flat(0.5, 0.65, 0.15, 0.065, 5), PINK)

	## Sporttasche: liegende blaue Tasche mit zwei Griffen und weißen Streifen.
	func icon_bag_medium() -> void:
		cord([0.32, 0.42, 0.36, 0.2, 0.64, 0.2, 0.68, 0.42], GUN, 0.045)
		rbox(0.04, 0.36, 0.92, 0.5, 0.16, Color(0.25, 0.5, 1.0))
		bar(0.22, 0.37, 0.07, 0.48, WHITE)
		bar(0.71, 0.37, 0.07, 0.48, WHITE)
		stroke([0.31, 0.46, 0.69, 0.46], INK, 0.025)
		box(0.47, 0.42, 0.06, 0.09, YELLOW)
		gloss([0.1, 0.42, 0.2, 0.39, 0.2, 0.44, 0.09, 0.5], 0.4)
		rim(round_rect(0.04, 0.36, 0.92, 0.5, 0.16))

	## Reisekoffer: großer Lederkoffer mit Griff, Riemen, Eckbeschlägen und Rollen.
	func icon_bag_large() -> void:
		cord([0.38, 0.14, 0.38, 0.07, 0.62, 0.07, 0.62, 0.14], STEEL_DARK, 0.045)
		disc(0.24, 0.93, 0.045, GUN)
		disc(0.76, 0.93, 0.045, GUN)
		rbox(0.06, 0.13, 0.88, 0.78, 0.07, LEATHER)
		bar(0.24, 0.14, 0.09, 0.76, WOOD_DARK)
		bar(0.67, 0.14, 0.09, 0.76, WOOD_DARK)
		box(0.235, 0.44, 0.1, 0.09, YELLOW)
		box(0.665, 0.44, 0.1, 0.09, YELLOW)
		fill([0.07, 0.14, 0.2, 0.14, 0.07, 0.27], BRASS)
		fill([0.93, 0.14, 0.8, 0.14, 0.93, 0.27], BRASS)
		fill([0.07, 0.9, 0.2, 0.9, 0.07, 0.77], BRASS)
		fill([0.93, 0.9, 0.8, 0.9, 0.93, 0.77], BRASS)
		disc(0.5, 0.36, 0.085, PINK)
		box(0.42, 0.62, 0.17, 0.11, CYAN)
		rim(round_rect(0.06, 0.13, 0.88, 0.78, 0.07))
