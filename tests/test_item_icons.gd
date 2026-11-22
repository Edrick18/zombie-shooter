extends SceneTree
## Tests für die Bilder der Gegenstände (scripts/ui/item_icons.gd, Abschnitt 26.2):
## Jede ID aus ItemDefs.ORDER hat ein Bild. Das Zeichnen in drei Größen bleibt im Rechteck,
## liefert nur gültige Flächen und wirft keinen Fehler. Je zwei Gegenstände zeichnen nicht
## dieselbe Befehlsfolge. tint färbt alle Farben. Das fertige Control View zeichnet wirklich.
##
## Geprüft wird über ItemIcons.commands(): dieselben Zeichenbefehle als Liste, ohne Bildschirm.
## Dazu zeichnet ein echtes Control alle Bilder in seinem _draw() (läuft auch headless).

const ItemDefs := preload("res://scripts/core/item_defs.gd")
const ItemIcons := preload("res://scripts/ui/item_icons.gd")

## Kantenlängen, in denen jedes Bild geprüft wird (kleinste und größte laut Bauplan, dazu eine mittlere).
const SIZES: Array[float] = [24.0, 64.0, 160.0]
## So weit darf ein Befehl über das Rechteck hinausreichen (Rundung, Kantenglättung).
const EDGE_TOLERANCE: float = 0.5
const OPS: Array[String] = ["polygon", "polyline", "circle"]


## Zeichnet in seinem _draw() alle Bilder in allen Größen und zählt mit.
class DrawProbe:
	extends Control

	const Icons := preload("res://scripts/ui/item_icons.gd")

	var ids: Array[String] = []
	var sizes: Array[float] = []
	var tint: Color = Color.WHITE
	var draws: int = 0
	var drawn_icons: int = 0

	func _draw() -> void:
		draws += 1
		var y: float = 0.0
		for edge: float in sizes:
			var x: float = 0.0
			for id: String in ids:
				Icons.draw(self, id, Rect2(x, y, edge, edge), tint)
				drawn_icons += 1
				x += edge + 2.0
			y += edge + 2.0
		# Unbekannte ID und winziges Rechteck zeichnen nichts und werfen keinen Fehler.
		Icons.draw(self, "gibt_es_nicht", Rect2(0.0, 0.0, 64.0, 64.0))
		Icons.draw(self, "pistol", Rect2(0.0, 0.0, 2.0, 2.0))


var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_test_table()
	_test_bounds_and_shapes()
	_test_no_duplicates()
	_test_scaling_and_rect()
	_test_tint()
	_test_bags_grow()
	await _test_real_drawing()
	await _test_view()
	await process_frame
	if _failures == 0:
		print("Alle %d Prüfungen für die Bilder der Gegenstände bestanden." % _checks)
	else:
		printerr("%d von %d Prüfungen für die Bilder der Gegenstände fehlgeschlagen." % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


# --- Helfer ---------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + message)


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures += 1
		printerr("FEHLER: %s (erwartet %s, bekommen %s)" % [message, str(expected), str(actual)])


## Rechteck, das alle Befehle samt Linienbreite und Radius umschließt.
func _bounds(commands: Array[Dictionary]) -> Rect2:
	var first: bool = true
	var bounds: Rect2 = Rect2()
	for command: Dictionary in commands:
		var extent: float = float(command["extent"])
		for point: Vector2 in command["points"] as PackedVector2Array:
			var part: Rect2 = Rect2(point - Vector2(extent, extent), Vector2(extent, extent) * 2.0)
			bounds = part if first else bounds.merge(part)
			first = false
	return bounds


## Die Befehlsfolge als Text (Punkte auf Zehntel gerundet), zum Vergleichen zweier Bilder.
func _signature(commands: Array[Dictionary]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for command: Dictionary in commands:
		var text: String = "%s %s %.1f" % [str(command["op"]), (command["color"] as Color).to_html(), float(command["extent"])]
		for point: Vector2 in command["points"] as PackedVector2Array:
			text += " %.1f,%.1f" % [point.x, point.y]
		parts.append(text)
	return "\n".join(parts)


# --- Tests ----------------------------------------------------------------------------

## Jede ID hat ein Bild, die Tabelle kennt nichts anderes, jede Funktion gibt es.
func _test_table() -> void:
	var ids: Array[String] = ItemDefs.all_ids()
	_equal(ids.size(), 65, "Aufbau: Es gibt 65 Gegenstände.")
	var drawers: Dictionary = ItemIcons.DRAWERS
	_equal(drawers.size(), ids.size(), "Die Tabelle hat genau so viele Bilder wie es Gegenstände gibt.")
	var painter: RefCounted = ItemIcons.Painter.new()
	var methods: Dictionary = {}
	for id: String in ids:
		_check(ItemIcons.has(id), "%s hat ein Bild." % id)
		var method: StringName = drawers.get(id, &"") as StringName
		_check(painter.has_method(method), "Die Funktion %s für %s gibt es." % [method, id])
		_check(not methods.has(method), "%s hat eine eigene Funktion (%s gehört schon %s)." % [id, method, str(methods.get(method, ""))])
		methods[method] = id
	for key: Variant in drawers.keys():
		_check(ItemDefs.has(str(key)), "Die Tabelle kennt nur Gegenstände aus ItemDefs (%s)." % str(key))
	var kinds: Dictionary = {}
	for id: String in ids:
		kinds[ItemDefs.kind(id)] = int(kinds.get(ItemDefs.kind(id), 0)) + 1
	_equal(int(kinds.get("weapon", 0)), 19, "Aufbau: 19 Waffen.")
	_equal(int(kinds.get("camera", 0)), 5, "Aufbau: 5 Kameras.")
	_equal(int(kinds.get("booster", 0)), 4, "Aufbau: 4 Verstärker.")
	_equal(int(kinds.get("bag", 0)), 4, "Aufbau: 4 Rucksack-Teile.")
	_check(not ItemIcons.has("gibt_es_nicht") and not ItemIcons.has(""), "Unbekannte IDs haben kein Bild.")
	_check(not ItemIcons.has("points") and not ItemIcons.has("synergy"), "Trostpreise und Synergien sind keine Gegenstände.")
	_check(ItemIcons.commands("gibt_es_nicht", Rect2(0.0, 0.0, 64.0, 64.0)).is_empty(), "Eine unbekannte ID zeichnet nichts.")
	_check(ItemIcons.commands("pistol", Rect2(0.0, 0.0, 2.0, 2.0)).is_empty(), "Ein winziges Rechteck zeichnet nichts.")
	_check(ItemIcons.commands("pistol", Rect2(0.0, 0.0, 0.0, 0.0)).is_empty(), "Ein leeres Rechteck zeichnet nichts.")


## In drei Größen: Befehle vorhanden, alle Punkte endlich und im Rechteck, Flächen lassen sich
## in Dreiecke zerlegen (sonst meldet draw_colored_polygon einen Fehler), Farben gültig.
func _test_bounds_and_shapes() -> void:
	for edge: float in SIZES:
		var rect: Rect2 = Rect2(37.0, 11.0, edge, edge)
		var allowed: Rect2 = rect.grow(EDGE_TOLERANCE)
		for id: String in ItemDefs.all_ids():
			var commands: Array[Dictionary] = ItemIcons.commands(id, rect)
			_check(commands.size() >= 4, "%s besteht bei %d px aus mehreren Formen (%d Befehle)." % [id, int(edge), commands.size()])
			var finite: bool = true
			var valid_ops: bool = true
			var valid_colors: bool = true
			var triangulated: bool = true
			var filled: int = 0
			for command: Dictionary in commands:
				var points: PackedVector2Array = command["points"]
				var op: String = str(command["op"])
				valid_ops = valid_ops and OPS.has(op) and not points.is_empty()
				for point: Vector2 in points:
					finite = finite and is_finite(point.x) and is_finite(point.y)
				var color: Color = command["color"]
				valid_colors = valid_colors and color.a > 0.0 and color.a <= 1.0 and float(command["extent"]) >= 0.0
				if op == "polygon":
					filled += 1
					triangulated = triangulated and points.size() >= 3 and not Geometry2D.triangulate_polygon(points).is_empty()
				elif op == "polyline":
					valid_ops = valid_ops and points.size() >= 2 and float(command["extent"]) >= 0.5
				elif op == "circle":
					filled += 1
					valid_ops = valid_ops and float(command["extent"]) > 0.0
			_check(valid_ops, "%s benutzt bei %d px nur gültige Befehle." % [id, int(edge)])
			_check(finite, "%s hat bei %d px nur endliche Punkte." % [id, int(edge)])
			_check(valid_colors, "%s hat bei %d px nur sichtbare, gültige Farben." % [id, int(edge)])
			_check(triangulated, "Jede Fläche von %s lässt sich bei %d px zeichnen (zerlegbar in Dreiecke)." % [id, int(edge)])
			_check(filled >= 2, "%s hat bei %d px gefüllte Flächen (%d)." % [id, int(edge), filled])
			var bounds: Rect2 = _bounds(commands)
			_check(allowed.encloses(bounds), "%s bleibt bei %d px im Rechteck (links %.2f, oben %.2f, rechts %.2f, unten %.2f über dem Rand)." % [
				id, int(edge), maxf(rect.position.x - bounds.position.x, 0.0), maxf(rect.position.y - bounds.position.y, 0.0),
				maxf(bounds.end.x - rect.end.x, 0.0), maxf(bounds.end.y - rect.end.y, 0.0)])
			# Das Bild nutzt sein Rechteck: Es ist nicht winzig und sitzt nicht in einer Ecke.
			_check(maxf(bounds.size.x, bounds.size.y) >= edge * 0.8, "%s füllt bei %d px sein Rechteck (%.0f x %.0f)." % [id, int(edge), bounds.size.x, bounds.size.y])
			_check(minf(bounds.size.x, bounds.size.y) >= edge * 0.3, "%s ist bei %d px kein dünner Strich (%.0f x %.0f)." % [id, int(edge), bounds.size.x, bounds.size.y])
			_check((bounds.get_center() - rect.get_center()).length() <= edge * 0.12, "%s sitzt bei %d px in der Mitte." % [id, int(edge)])


## Keine zwei Gegenstände zeichnen dieselbe Befehlsfolge, auch nicht dieselben Formen in anderer Farbe.
func _test_no_duplicates() -> void:
	var rect: Rect2 = Rect2(0.0, 0.0, 96.0, 96.0)
	var seen: Dictionary = {}
	var seen_shapes: Dictionary = {}
	for id: String in ItemDefs.all_ids():
		var commands: Array[Dictionary] = ItemIcons.commands(id, rect)
		var signature: String = _signature(commands)
		_check(not seen.has(signature), "%s zeichnet nicht dieselbe Befehlsfolge wie %s." % [id, str(seen.get(signature, ""))])
		seen[signature] = id
		# Nur die Formen (ohne Farbe): Zwei Bilder dürfen sich nicht bloß in der Farbe unterscheiden.
		var shapes: PackedStringArray = PackedStringArray()
		for command: Dictionary in commands:
			var text: String = str(command["op"])
			for point: Vector2 in command["points"] as PackedVector2Array:
				text += " %.0f,%.0f" % [point.x, point.y]
			shapes.append(text)
		var shape_signature: String = "\n".join(shapes)
		_check(not seen_shapes.has(shape_signature), "%s hat andere Formen als %s." % [id, str(seen_shapes.get(shape_signature, ""))])
		seen_shapes[shape_signature] = id
		# Die größte gefüllte Fläche gehört nur diesem Bild: grobe Probe gegen Verwechslung.
	_equal(seen.size(), 65, "65 verschiedene Bilder.")
	# Zweimal dasselbe Bild zeichnet dieselben Befehle (kein Zufall im Bild).
	for id: String in ["pistol", "disco_ball", "snack", "bag_large"]:
		_equal(_signature(ItemIcons.commands(id, rect)), _signature(ItemIcons.commands(id, rect)), "%s zeichnet jedes Mal dasselbe." % id)


## Das Bild skaliert mit dem Rechteck und sitzt im größten Quadrat in der Mitte.
func _test_scaling_and_rect() -> void:
	for id: String in ItemDefs.all_ids():
		var small: Array[Dictionary] = ItemIcons.commands(id, Rect2(0.0, 0.0, 60.0, 60.0))
		var big: Array[Dictionary] = ItemIcons.commands(id, Rect2(0.0, 0.0, 120.0, 120.0))
		var same: bool = small.size() == big.size()
		if same:
			for i: int in small.size():
				var small_points: PackedVector2Array = small[i]["points"]
				var big_points: PackedVector2Array = big[i]["points"]
				same = same and small_points.size() == big_points.size() and str(small[i]["op"]) == str(big[i]["op"])
				if not same:
					break
				for n: int in small_points.size():
					same = same and (small_points[n] * 2.0).distance_to(big_points[n]) < 0.01
		_check(same, "%s ist bei doppelter Größe dasselbe Bild, nur doppelt so groß." % id)
		# Verschoben: alle Punkte verschieben sich mit.
		var moved: Array[Dictionary] = ItemIcons.commands(id, Rect2(300.0, 200.0, 60.0, 60.0))
		var shifted: bool = moved.size() == small.size()
		if shifted:
			for i: int in small.size():
				var a: PackedVector2Array = small[i]["points"]
				var b: PackedVector2Array = moved[i]["points"]
				for n: int in mini(a.size(), b.size()):
					shifted = shifted and (a[n] + Vector2(300.0, 200.0)).distance_to(b[n]) < 0.01
		_check(shifted, "%s folgt der Position des Rechtecks." % id)
		# Breites und hohes Rechteck: Das Bild bleibt im mittleren Quadrat.
		var wide: Rect2 = Rect2(10.0, 10.0, 200.0, 50.0)
		_check(Rect2(85.0, 10.0, 50.0, 50.0).grow(EDGE_TOLERANCE).encloses(_bounds(ItemIcons.commands(id, wide))),
				"%s bleibt in einem breiten Rechteck im mittleren Quadrat." % id)
		var tall: Rect2 = Rect2(10.0, 10.0, 40.0, 130.0)
		_check(Rect2(10.0, 55.0, 40.0, 40.0).grow(EDGE_TOLERANCE).encloses(_bounds(ItemIcons.commands(id, tall))),
				"%s bleibt in einem hohen Rechteck im mittleren Quadrat." % id)


## tint multipliziert jede Farbe, ändert aber keine Form.
func _test_tint() -> void:
	var rect: Rect2 = Rect2(0.0, 0.0, 96.0, 96.0)
	var grey: Color = Color(0.5, 0.5, 0.55)
	for id: String in ItemDefs.all_ids():
		var plain: Array[Dictionary] = ItemIcons.commands(id, rect)
		var tinted: Array[Dictionary] = ItemIcons.commands(id, rect, grey)
		var faded: Array[Dictionary] = ItemIcons.commands(id, rect, Color(1.0, 1.0, 1.0, 0.5))
		var ok: bool = plain.size() == tinted.size() and plain.size() == faded.size()
		if ok:
			for i: int in plain.size():
				var base: Color = plain[i]["color"]
				ok = ok and (tinted[i]["color"] as Color).is_equal_approx(base * grey)
				ok = ok and (faded[i]["color"] as Color).is_equal_approx(Color(base.r, base.g, base.b, base.a * 0.5))
				ok = ok and plain[i]["points"] == tinted[i]["points"]
		_check(ok, "tint färbt jede Farbe von %s und lässt die Formen gleich." % id)
	_equal(_signature(ItemIcons.commands("pistol", rect)), _signature(ItemIcons.commands("pistol", rect, Color.WHITE)), "Ohne tint gilt Weiß.")


## Die vier Taschen werden von der Bauchtasche zum Reisekoffer größer.
func _test_bags_grow() -> void:
	var rect: Rect2 = Rect2(0.0, 0.0, 100.0, 100.0)
	var last_area: float = 0.0
	for id: String in ["bag_tiny", "bag_small", "bag_medium", "bag_large"]:
		var bounds: Rect2 = _bounds(ItemIcons.commands(id, rect))
		var area: float = bounds.get_area()
		_check(area > last_area * 1.1, "%s ist sichtbar größer als die Tasche davor (%.0f nach %.0f)." % [id, area, last_area])
		last_area = area


## Ein echtes Control zeichnet alle Bilder in seinem _draw() (auch ohne Bildschirm).
func _test_real_drawing() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	root.add_child(layer)
	var probe: DrawProbe = DrawProbe.new()
	probe.ids = ItemDefs.all_ids()
	probe.sizes = SIZES
	probe.size = Vector2(1280.0, 720.0)
	layer.add_child(probe)
	for i: int in 4:
		await process_frame
	_check(probe.draws >= 1, "Das Control wurde gezeichnet.")
	_equal(probe.drawn_icons, probe.draws * 65 * SIZES.size(), "Alle 65 Bilder liefen in drei Größen ohne Abbruch durch.")
	# Getönt noch einmal.
	var before: int = probe.draws
	probe.tint = Color(0.5, 0.5, 0.55)
	probe.queue_redraw()
	for i: int in 4:
		await process_frame
	_check(probe.draws > before, "Das Control zeichnet nach queue_redraw erneut.")
	_equal(probe.drawn_icons, probe.draws * 65 * SIZES.size(), "Auch getönt laufen alle Bilder durch.")
	layer.queue_free()
	await process_frame


## Das fertige Control View: Eigenschaften, Neuzeichnen, keine Maus.
func _test_view() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	root.add_child(layer)
	var counts: Dictionary = {}
	var views: Array[Control] = []
	for id: String in ItemDefs.all_ids():
		var view: ItemIcons.View = ItemIcons.View.new()
		view.item_id = id
		view.size = Vector2(48.0, 48.0)
		view.position = Vector2(float(views.size() % 20) * 50.0, float(views.size() / 20) * 50.0)
		view.plate = views.size() % 2 == 0
		view.draw.connect(func() -> void: counts[id] = int(counts.get(id, 0)) + 1)
		layer.add_child(view)
		views.append(view)
	for i: int in 4:
		await process_frame
	_equal(counts.size(), 65, "Jedes View wurde gezeichnet.")
	var first: ItemIcons.View = views[0] as ItemIcons.View
	_equal(first.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Ein View fängt keine Maus.")
	_equal(first.item_id, "pistol", "Das View kennt seine ID.")
	_check(first.tint == Color.WHITE, "Ohne Angabe ist das View nicht getönt.")
	var before: int = int(counts.get("pistol", 0))
	first.tint = Color(0.5, 0.5, 0.5)
	for i: int in 3:
		await process_frame
	_check(int(counts.get("pistol", 0)) > before, "Eine neue Tönung zeichnet das View neu.")
	before = int(counts.get("pistol", 0))
	first.item_id = "revolver"
	for i: int in 3:
		await process_frame
	_check(int(counts.get("pistol", 0)) > before, "Eine neue ID zeichnet das View neu.")
	# Unbekannte ID und winzige Größe: kein Fehler.
	first.item_id = "gibt_es_nicht"
	first.size = Vector2(2.0, 2.0)
	for i: int in 3:
		await process_frame
	layer.queue_free()
	await process_frame
