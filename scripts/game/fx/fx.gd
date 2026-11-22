extends RefCounted
## Modul: FX (scripts/game/fx).
## Kurzlebige Effekte aus einfachen Formen: Leuchtspur, Mündungsfeuer, Einschlag, Spritzer,
## Blitzbogen, Blitzstern, Explosion, Konfetti, Druckwelle, Trefferzahl, Aufblitzen.
##
## Regeln für jede Funktion:
## - nur statische Funktionen, Einbinden mit const Fx := preload("res://scripts/game/fx/fx.gd")
## - nie abstürzen: ein ungültiger oder nicht im Baum hängender parent bedeutet "nichts tun"
## - jeder Effekt räumt sich selbst weg (queue_free nach Ablauf) und läuft auch headless ohne Fehler
## - Effekte ändern nie den Spielzustand (kein Schaden, keine Signale) und haben keine Kollision
## - Zufall der Effekte kommt aus dem globalen Generator (randf), nie aus Game.rng: Die Optik darf
##   einen Lauf mit Seed nicht verändern.
## - Animationen laufen über Tweens des Effekt-Knotens oder im Vorrat (fx_pool.gd): Sie halten in
##   der Pause an und enden mit dem Knoten.
## Als parent dient der Knoten aus root_of(...): der Behälter "Fx" unter Main (Gruppe "fx_root").
##
## Viele kleine Teile (Leuchtspuren, Funken, Spritzer, Rauch, Einschussmale) liegen im Vorrat
## fx_pool.gd: ein Kind von parent mit festen Obergrenzen, das sich nach kurzer Ruhe selbst löscht.
## Große, seltene Bilder (Feuerball, Ringe, Blitz) sind eigene Knoten mit Tween wie bisher.
##
## Farben der Treffer: Zombies spritzen schleimgrün (einheitlich, passend zur Show, kein Blutrot).
## Kopftreffer spritzen stärker und heller, kritische Treffer dazu mit pinken Funken. Stirbt ein
## Zombie, platzt er grün mit ein paar bunten Tupfern in den Konfetti-Farben.

const ShaderKeep := preload("res://scripts/game/fx/shader_keep.gd")
const FxPool := preload("res://scripts/game/fx/fx_pool.gd")

const GROUP_FX_ROOT: String = "fx_root"

# --- Reine Optik-Zahlen (keine Spielregeln) ---
const TRACER_WIDTH: float = 0.032
const TRACER_TIME: float = 0.09
## Die Leuchtspur ist zu diesem Anteil zu Weiß hin aufgehellt und so deckend.
const TRACER_WHITEN: float = 0.3
const TRACER_ALPHA: float = 0.9
const MUZZLE_SIZE: float = 0.14
const MUZZLE_TIME: float = 0.06
const LIGHTNING_TIME: float = 0.14
## Nach dem Blitz glimmt sein Bogen so lange nach, anfangs mit dieser Deckkraft.
const LIGHTNING_AFTERGLOW_TIME: float = 0.28
const LIGHTNING_AFTERGLOW_ALPHA: float = 0.4
const LIGHTNING_WIDTH: float = 0.2
const LIGHTNING_CORE_WIDTH: float = 0.07
const LIGHTNING_JITTER: float = 0.35
const LIGHTNING_STEP: float = 0.7
const LIGHTNING_COLOR: Color = Color(0.25, 0.9, 1.0, 0.95)
const LIGHTNING_CORE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
## Funken, die am Einschlag eines Blitzes wegspringen.
const LIGHTNING_SPARKS: int = 3
const EXPLOSION_TIME: float = 0.32
## Fliegende Glut-Teile und Rauchbälle je Explosion, und wie lange der Rauch höchstens steht.
const EXPLOSION_DEBRIS: int = 10
const EXPLOSION_SMOKE: int = 6
const EXPLOSION_SMOKE_TIME: float = 0.85
const EXPLOSION_SMOKE_COLOR: Color = Color(0.4, 0.36, 0.5, 0.42)
## Rauch nah vor der Kamera wäre eine Wand: Unter diesem Abstand wird er durchsichtiger.
const SMOKE_NEAR_DISTANCE: float = 1.0
const SMOKE_FULL_DISTANCE: float = 4.5
## Der Ring einer Explosion legt sich auf den Boden, wenn der höchstens so tief unter ihr liegt.
const FLOOR_SEARCH_DEPTH: float = 3.0
const FLOOR_MASK: int = 1
const SHOCKWAVE_TIME: float = 0.4
const SHOCKWAVE_COLOR: Color = Color(0.7, 0.92, 1.0, 0.6)
## Die Druckwelle hat eine niedrige Wand, die mit dem Ring nach außen läuft (von vorn gut zu sehen).
const SHOCKWAVE_BAND_HEIGHT: float = 0.55
const CONFETTI_AMOUNT: int = 48
const CONFETTI_LIFETIME: float = 1.2
const NUMBER_TIME: float = 0.75
const NUMBER_RISE: float = 0.9
## Trefferzahlen sind auf dem Bildschirm etwa gleich groß: Sie wachsen mit dem Abstand zur Kamera
## (damit man sie quer durch den Raum liest) und schrumpfen in der Nähe (damit eine Zahl am
## Zombie direkt vor der Nase nicht das halbe Bild füllt).
const NUMBER_REFERENCE_DISTANCE: float = 4.0
const NUMBER_MIN_DISTANCE_SCALE: float = 0.3
const NUMBER_MAX_DISTANCE_SCALE: float = 2.2
## Alle Trefferzahlen nutzen eine Schriftgröße (eine Schrift-Textur, kein Ruckler bei neuen
## Beträgen). Große Treffer werden über den Maßstab größer: von NUMBER_MIN_SIZE bei kleinen
## Beträgen bis NUMBER_MAX_SIZE ab NUMBER_BIG_AMOUNT Schaden.
const NUMBER_FONT_SIZE: int = 96
const NUMBER_OUTLINE_SIZE: int = 22
const NUMBER_MIN_SIZE: float = 0.62
const NUMBER_MAX_SIZE: float = 1.35
const NUMBER_BIG_AMOUNT: float = 300.0
## Kopftreffer und kritische Treffer sind größer, der kritische hat eine eigene Farbe und ein
## Ausrufezeichen.
const NUMBER_HEADSHOT_SCALE: float = 1.15
const NUMBER_CRIT_SCALE: float = 1.22
## Eine Zahl entsteht neben dem Treffpunkt, nicht darauf (abwechselnd links und rechts, etwas
## darüber): Das Ziel am Fadenkreuz bleibt frei. Strecken in Metern bei NUMBER_REFERENCE_DISTANCE.
const NUMBER_SIDE_MIN: float = 0.3
const NUMBER_SIDE_MAX: float = 0.5
const NUMBER_LIFT_MIN: float = 0.1
const NUMBER_LIFT_MAX: float = 0.3
## Eine neue Zahl wächst von diesem Anteil ihrer Größe auf, eine kritische schlägt von oben ein,
## eine zusammengezählte ploppt nur leicht nach.
const NUMBER_POP_FROM: float = 0.3
const NUMBER_CRIT_POP_FROM: float = 1.25
const NUMBER_MERGE_POP_FROM: float = 0.8
const CRIT_NUMBER_COLOR: Color = Color(1.0, 0.22, 0.5)
## Treffer, die kurz nacheinander fast an derselben Stelle landen (Schrot, Dauerfeuer, Flamme),
## zählen in einer Zahl zusammen statt sich zu überdecken: innerhalb dieser Zeit und Strecke.
const NUMBER_MERGE_TIME: float = 0.22
const NUMBER_MERGE_RADIUS: float = 0.5
## Obergrenzen, damit auch 24 Zombies in einer Kettenreaktion billig bleiben.
const MAX_LIVE_NUMBERS: int = 40
const MAX_LIVE_LIGHTS: int = 6
const MAX_LIVE_CONFETTI: int = 10
const MATERIAL_CACHE_LIMIT: int = 64
const META_FLASH_TOKEN: StringName = &"fx_flash_token"
const META_FLASH_ACTIVE: StringName = &"fx_flash_active"
const META_FLASH_PREVIOUS: StringName = &"fx_flash_previous"

# Einschlag in Wand oder Boden.
const IMPACT_SPARKS: int = 5
const IMPACT_SPARK_WIDTH: float = 0.028
const IMPACT_SPARK_LENGTH: float = 0.2
const IMPACT_DECAL_SIZE: float = 0.09
const IMPACT_DUST_COLOR: Color = Color(0.82, 0.8, 0.92, 0.5)
const IMPACT_FLASH_COLOR: Color = Color(1.0, 0.97, 0.8, 0.95)
# Spritzer am Zombie.
const SPLAT_DROPS: int = 5
const SPLAT_MAX_DROPS: int = 14
## Grüner Tupfer am Treffpunkt (nur bei vollen Treffern, nicht bei Flamme und Strahl): Durchmesser
## am Anfang und am Ende, Dauer.
const SPLAT_POP_FROM: float = 0.1
const SPLAT_POP_TO: float = 0.28
const SPLAT_POP_TIME: float = 0.09
const SPLAT_POP_ALPHA: float = 0.5
const SPLAT_POP_MIN_STRENGTH: float = 0.4
const SPLAT_COLOR: Color = Color(0.5, 0.95, 0.15)
const SPLAT_DARK_COLOR: Color = Color(0.2, 0.6, 0.1)
const SPLAT_HEADSHOT_COLOR: Color = Color(0.85, 1.0, 0.35)
const SPLAT_CRIT_COLOR: Color = Color(1.0, 0.35, 0.7)
const SPLAT_GRAVITY: float = 9.0
const SPLAT_HEADSHOT_FACTOR: float = 1.8
const SPLAT_CRIT_FACTOR: float = 1.6
const SPLAT_CRIT_SPARKS: int = 6
# Platzen beim Tod.
const KILL_DROPS: int = 12
const KILL_DOTS: int = 7
## Sind Funken oder Spritzer im Vorrat über diesen Anteil belegt, kommt nur noch die Hälfte dazu.
const POOL_THROTTLE_SHARE: float = 0.6

## Bunte Gameshow-Farben für das Konfetti.
const CONFETTI_COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.35), Color(1.0, 0.8, 0.1), Color(0.2, 0.85, 0.35),
	Color(0.2, 0.65, 1.0), Color(0.85, 0.3, 1.0), Color(1.0, 0.5, 0.1), Color(1.0, 1.0, 1.0),
]


## Eine sichtbare Trefferzahl mit dem, was zum Zusammenzählen nötig ist.
class NumberEntry:
	extends RefCounted
	var label: Label3D = null
	var tween: Tween = null
	## Ort, an dem die Zahl entstand, und der Physik-Schritt dazu.
	var anchor: Vector3 = Vector3.ZERO
	var born: int = 0
	## Farbe und Art: Nur gleiche Zahlen zählen zusammen.
	var key: int = 0
	var amount: float = 0.0
	var headshot: bool = false
	var crit: bool = false


static var _box_mesh: BoxMesh = null
static var _sphere_mesh: SphereMesh = null
static var _quad_mesh: QuadMesh = null
static var _ring_mesh: TorusMesh = null
static var _band_mesh: CylinderMesh = null
static var _confetti_mesh: QuadMesh = null
static var _confetti_gradient: Gradient = null
static var _confetti_fade: Gradient = null
static var _lightning_material: StandardMaterial3D = null
static var _materials: Dictionary = {}
static var _numbers: Array[NumberEntry] = []
static var _live_lights: int = 0
static var _live_confetti: int = 0
static var _pool: FxPool = null
## Angekündigter Kugeltreffer (hint_number): Betrag, Kopftreffer, kritisch. Betrag < 0 = keiner.
static var _hint_amount: float = -1.0
## Seite der nächsten Trefferzahl (1 = rechts vom Treffpunkt, -1 = links).
static var _number_side: float = 1.0
static var _hint_headshot: bool = false
static var _hint_crit: bool = false


## Behälter für Effekte: erster Knoten der Gruppe "fx_root", sonst die Wurzel des Baums.
## Gibt null zurück, wenn from ungültig ist oder nicht im Baum hängt.
static func root_of(from: Node) -> Node:
	if not is_instance_valid(from) or not from.is_inside_tree():
		return null
	var tree: SceneTree = from.get_tree()
	var found: Node = tree.get_first_node_in_group(GROUP_FX_ROOT)
	if found != null:
		return found
	return tree.root


## Der Vorrat der kleinen Teile unter parent (entsteht bei Bedarf). null, wenn parent ungültig
## ist oder nicht im Baum hängt. Für Tests und für Effekte anderer Module.
static func pool_of(parent: Node) -> FxPool:
	if not _usable(parent):
		return null
	if is_instance_valid(_pool) and not _pool.is_queued_for_deletion() and _pool.get_parent() == parent:
		return _pool
	for child: Node in parent.get_children():
		if child is FxPool and not child.is_queued_for_deletion():
			_pool = child as FxPool
			return _pool
	_pool = FxPool.new()
	parent.add_child(_pool)
	return _pool


## Der Vorrat unter parent, wenn es gerade einen gibt (legt keinen an). Sonst null.
static func find_pool(parent: Node) -> FxPool:
	if not _usable(parent):
		return null
	for child: Node in parent.get_children():
		if child is FxPool and not child.is_queued_for_deletion():
			return child as FxPool
	return null


## Leuchtspur einer Kugel von from nach to (Weltkoordinaten): dünn, hell, zieht sich in
## TRACER_TIME zum Ziel hin zusammen. Am Anfang ist sie schmaler als am Ziel (TRACER_WIDTH gilt
## am Ziel). Höchstens FxPool.MAX_TRACERS zugleich.
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if not _usable(parent):
		return
	if from.distance_squared_to(to) < 0.0025:
		return
	var bright: Color = color.lerp(Color.WHITE, TRACER_WHITEN)
	bright.a = TRACER_ALPHA
	pool_of(parent).add_tracer(from, to, bright, TRACER_WIDTH, TRACER_TIME)


## Mündungsfeuer: kurzer heller Blitz als Kind von parent (z. B. die Mündung einer Drohne). Die
## Waffen des Spielers haben ihr eigenes Mündungsfeuer je Waffenart (view_model.gd).
static func muzzle_flash(parent: Node3D) -> void:
	if not _usable(parent):
		return
	var flash: Node3D = Node3D.new()
	flash.name = "MuzzleFlash"
	var hot: StandardMaterial3D = _glow_material(Color(1.0, 0.85, 0.35, 0.95))
	var core: MeshInstance3D = _mesh_node(_sphere(), _glow_material(Color(1.0, 1.0, 0.9, 1.0)))
	core.scale = Vector3.ONE * MUZZLE_SIZE * 0.55
	flash.add_child(core)
	# Zwei gekreuzte Flächen ergeben von vorn einen Stern, eine dritte zeigt zur Seite.
	for i: int in 3:
		var blade: MeshInstance3D = _mesh_node(_quad(), hot)
		blade.scale = Vector3(MUZZLE_SIZE * 2.2, MUZZLE_SIZE * 0.7, 1.0)
		if i < 2:
			blade.rotation = Vector3(0.0, 0.0, PI * 0.5 * float(i))
		else:
			blade.rotation = Vector3(0.0, PI * 0.5, 0.0)
		flash.add_child(blade)
	flash.rotation.z = randf() * TAU
	flash.scale = Vector3.ONE * randf_range(0.75, 1.0)
	parent.add_child(flash)
	_add_light(flash, Vector3.ZERO, Color(1.0, 0.8, 0.45), 2.2, 5.0, MUZZLE_TIME, true)
	var tween: Tween = flash.create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * 1.35, MUZZLE_TIME * 0.5)
	tween.tween_property(flash, "scale", Vector3.ONE * 0.05, MUZZLE_TIME * 0.5)
	tween.tween_callback(flash.queue_free)


## Einschlag einer Kugel in Wand oder Boden an pos (Weltkoordinaten) mit der Normalen normal:
## Funken in der Farbe color, die von der Fläche wegspringen, ein heller Tupfer, etwas Staub und
## ein Einschussmal, das ein paar Sekunden bleibt. strength 0 bis 1 dünnt aus (Schrot: viele
## Einschläge in einem Bild).
static func impact(parent: Node, pos: Vector3, normal: Vector3, color: Color, strength: float = 1.0) -> void:
	if not _usable(parent):
		return
	var pool: FxPool = pool_of(parent)
	var away: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var amount: float = clampf(strength, 0.2, 1.0)
	pool.add_decal(pos, away, IMPACT_DECAL_SIZE * randf_range(0.8, 1.25), FxPool.DECAL_SCORCH)
	var start: Vector3 = pos + away * 0.03
	var hot: Color = color.lerp(Color.WHITE, 0.45)
	hot.a = 1.0
	var sparks: int = _throttled(maxi(2, roundi(float(IMPACT_SPARKS) * amount)), pool.spark_count(), FxPool.MAX_SPARKS)
	for _i: int in sparks:
		var direction: Vector3 = (away * randf_range(0.5, 1.3) + _random_unit() * 0.85).normalized()
		pool.add_spark(start, direction * randf_range(2.5, 6.5), hot, IMPACT_SPARK_WIDTH,
			IMPACT_SPARK_LENGTH * randf_range(0.7, 1.3), randf_range(0.14, 0.28), 9.0)
	pool.add_blob(start, Vector3.ZERO, IMPACT_FLASH_COLOR, 0.26 * amount + 0.08, 0.04, 0.07, 0.0, 0.0)
	var puffs: int = _throttled(2 if amount > 0.6 else 1, pool.blob_count(), FxPool.MAX_BLOBS)
	for _i: int in puffs:
		pool.add_blob(start, away * randf_range(0.5, 1.2) + _random_unit() * 0.35, IMPACT_DUST_COLOR,
			0.09, randf_range(0.28, 0.42), randf_range(0.3, 0.45), -0.5, 3.0)


## Spritzer an einem getroffenen Zombie: schleimgrüne Tropfen ab pos (Weltkoordinaten) in
## Flugrichtung der Kugel (direction). Kopftreffer spritzen stärker und heller, kritische Treffer
## stärker und mit pinken Funken. strength 0 bis 1 dünnt aus (Flamme und Strahl treffen sehr oft).
static func splatter(parent: Node, pos: Vector3, direction: Vector3, headshot: bool = false, crit: bool = false,
		strength: float = 1.0) -> void:
	if not _usable(parent):
		return
	var pool: FxPool = pool_of(parent)
	var along: Vector3 = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	var power: float = 1.0
	if headshot:
		power *= SPLAT_HEADSHOT_FACTOR
	if crit:
		power *= SPLAT_CRIT_FACTOR
	var wanted: int = clampi(roundi(float(SPLAT_DROPS) * power * clampf(strength, 0.1, 1.0)), 1, SPLAT_MAX_DROPS)
	var drops: int = _throttled(wanted, pool.blob_count(), FxPool.MAX_BLOBS)
	var speed: float = 1.0 + 0.25 * (power - 1.0)
	var grow: float = 1.0 + 0.2 * (power - 1.0)
	# Die Tropfen beginnen knapp vor dem Treffpunkt (zum Schützen hin), nicht im Körper.
	var start: Vector3 = pos - along * 0.06
	for i: int in drops:
		# Die Tropfen fächern quer zur Kugel auf und treiben dabei mit ihr weiter: So sieht sie auch
		# der Schütze, der genau von hinten auf die Flugbahn schaut. Jeder dritte spritzt zurück.
		var back: bool = i % 3 == 2
		var random: Vector3 = _random_unit()
		var across: Vector3 = random - along * random.dot(along)
		if across.length_squared() < 0.0001:
			across = Vector3.UP
		var heading: Vector3 = along * (-0.5 if back else randf_range(0.15, 0.8)) + across.normalized() * randf_range(0.6, 1.2)
		heading.y += 0.35
		var color: Color = SPLAT_COLOR.lerp(SPLAT_DARK_COLOR, randf() * 0.6)
		if headshot and i % 2 == 0:
			color = SPLAT_HEADSHOT_COLOR
		pool.add_blob(start, heading.normalized() * randf_range(2.0, 4.8) * speed, color,
			randf_range(0.08, 0.14) * grow, 0.03, randf_range(0.3, 0.5), SPLAT_GRAVITY, 1.2)
	if strength >= SPLAT_POP_MIN_STRENGTH or headshot or crit:
		# Tupfer am Treffpunkt: Jeder volle Treffer ist sofort zu sehen. Kopftreffer und kritische
		# Treffer haben einen größeren in ihrer eigenen Farbe.
		var pop: Color = SPLAT_CRIT_COLOR if crit else (SPLAT_HEADSHOT_COLOR if headshot else SPLAT_COLOR)
		pool.add_blob(start, Vector3.ZERO, Color(pop, SPLAT_POP_ALPHA), SPLAT_POP_FROM * grow, SPLAT_POP_TO * grow * (1.3 if crit else 1.0),
			SPLAT_POP_TIME, 0.0, 0.0)
	if crit:
		var sparks: int = _throttled(SPLAT_CRIT_SPARKS, pool.spark_count(), FxPool.MAX_SPARKS)
		for _i: int in sparks:
			pool.add_spark(pos, _random_unit() * randf_range(3.0, 6.0), Color(SPLAT_CRIT_COLOR.lerp(Color.WHITE, 0.3), 1.0),
				0.035, 0.26, randf_range(0.16, 0.26), 4.0)


## Ein Zombie stirbt an pos (Weltkoordinaten, Körpermitte): Er platzt schleimgrün nach allen
## Seiten, dazu ein paar bunte Tupfer. size 1 = normaler Zombie, größer für große.
static func kill_burst(parent: Node, pos: Vector3, size: float = 1.0) -> void:
	if not _usable(parent):
		return
	var pool: FxPool = pool_of(parent)
	var scale: float = clampf(size, 0.6, 2.0)
	pool.add_blob(pos, Vector3.ZERO, Color(SPLAT_HEADSHOT_COLOR, 0.65), 0.35 * scale, 1.2 * scale, 0.16, 0.0, 0.0)
	var drops: int = _throttled(roundi(float(KILL_DROPS) * scale), pool.blob_count(), FxPool.MAX_BLOBS)
	for _i: int in drops:
		var heading: Vector3 = _random_unit()
		heading.y = absf(heading.y) * 0.8 + 0.25
		pool.add_blob(pos + heading * 0.15 * scale, heading.normalized() * randf_range(2.2, 5.5),
			SPLAT_COLOR.lerp(SPLAT_DARK_COLOR, randf() * 0.6), randf_range(0.14, 0.24) * scale, 0.04,
			randf_range(0.4, 0.65), SPLAT_GRAVITY, 1.0)
	var dots: int = _throttled(KILL_DOTS, pool.blob_count(), FxPool.MAX_BLOBS)
	for i: int in dots:
		var heading: Vector3 = _random_unit()
		heading.y = absf(heading.y) + 0.5
		pool.add_blob(pos, heading.normalized() * randf_range(2.5, 5.0), CONFETTI_COLORS[(i + randi()) % CONFETTI_COLORS.size()],
			randf_range(0.1, 0.15) * scale, 0.03, randf_range(0.45, 0.7), SPLAT_GRAVITY * 0.8, 0.8)


## Blitzbogen durch die Punkte (Weltkoordinaten, mindestens zwei).
static func lightning(parent: Node, points: PackedVector3Array) -> void:
	if not _usable(parent) or points.size() < 2:
		return
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _lightning_mat())
	var vertex_count: int = 0
	for i: int in points.size() - 1:
		vertex_count += _add_bolt(mesh, points[i], points[i + 1])
	_show_lightning(parent, mesh, vertex_count, points[points.size() - 1])
	_lightning_sparks(parent, points.slice(1))


## Blitze von origin zu jedem Ziel (Weltkoordinaten), alle in einem einzigen Netz: für einen
## Schlag, der viele Zombies zugleich trifft (Störsender). Ohne Ziel passiert nichts.
static func lightning_star(parent: Node, origin: Vector3, targets: PackedVector3Array) -> void:
	if not _usable(parent) or targets.is_empty():
		return
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _lightning_mat())
	var vertex_count: int = 0
	for target: Vector3 in targets:
		vertex_count += _add_bolt(mesh, origin, target)
	_show_lightning(parent, mesh, vertex_count, origin)
	_lightning_sparks(parent, targets)


## Ein zackiger Blitz von a nach b in eine offene Fläche von mesh: Bogen, kleiner Seitenast und
## Funkenstern am Einschlag. Gibt die Zahl der Ecken zurück.
static func _add_bolt(mesh: ImmediateMesh, a: Vector3, b: Vector3) -> int:
	var vertex_count: int = 0
	var path: PackedVector3Array = _jagged_path(a, b)
	for j: int in path.size() - 1:
		vertex_count += _add_ribbon(mesh, path[j], path[j + 1], LIGHTNING_WIDTH, LIGHTNING_COLOR)
		vertex_count += _add_ribbon(mesh, path[j], path[j + 1], LIGHTNING_CORE_WIDTH, LIGHTNING_CORE_COLOR)
	# Kleiner Seitenast in der Mitte des Bogens.
	if path.size() > 2:
		var mid: Vector3 = path[path.size() / 2]
		var fork_end: Vector3 = mid + _random_unit() * randf_range(0.35, 0.8)
		vertex_count += _add_ribbon(mesh, mid, fork_end, LIGHTNING_CORE_WIDTH * 1.5, LIGHTNING_COLOR)
	# Funkenstern am Einschlag.
	vertex_count += _add_spark(mesh, b, 0.32)
	return vertex_count


## Schließt die Fläche eines Blitz-Netzes ab, hängt es in parent und lässt es kurz flackern, mit
## einem kurzen Licht an light_pos. Danach glimmt der Bogen nach und verblasst.
static func _show_lightning(parent: Node, mesh: ImmediateMesh, vertex_count: int, light_pos: Vector3) -> void:
	if vertex_count == 0:
		# Alle Punkte lagen aufeinander: Eine leere Fläche darf nicht abgeschlossen werden.
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_end()
	var arc: MeshInstance3D = MeshInstance3D.new()
	arc.name = "Lightning"
	arc.mesh = mesh
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Eigenes Material derselben Art wie das geteilte: Seine Deckkraft läuft beim Nachglimmen aus.
	var material: StandardMaterial3D = _new_glow_material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	arc.material_override = material
	parent.add_child(arc)
	arc.global_transform = Transform3D.IDENTITY
	_add_light(parent, light_pos, Color(0.4, 0.9, 1.0), 2.5, 6.0, LIGHTNING_TIME + LIGHTNING_AFTERGLOW_TIME * 0.5)
	# Flackern: an, kurz aus, wieder an. Dann nachglimmen und weg.
	var tween: Tween = arc.create_tween()
	tween.tween_interval(LIGHTNING_TIME * 0.45)
	tween.tween_callback(arc.hide)
	tween.tween_interval(LIGHTNING_TIME * 0.15)
	tween.tween_callback(arc.show)
	tween.tween_interval(LIGHTNING_TIME * 0.4)
	tween.tween_callback(func() -> void: material.albedo_color.a = LIGHTNING_AFTERGLOW_ALPHA)
	tween.tween_property(material, "albedo_color:a", 0.0, LIGHTNING_AFTERGLOW_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_callback(arc.queue_free)


## Kleine Funken, die an jedem Einschlagpunkt eines Blitzes wegspringen.
static func _lightning_sparks(parent: Node, ends: PackedVector3Array) -> void:
	var pool: FxPool = pool_of(parent)
	for end: Vector3 in ends:
		var sparks: int = _throttled(LIGHTNING_SPARKS, pool.spark_count(), FxPool.MAX_SPARKS)
		for _i: int in sparks:
			pool.add_spark(end, _random_unit() * randf_range(1.5, 4.0), Color(0.75, 0.97, 1.0, 1.0),
				0.03, 0.2, randf_range(0.15, 0.3), 5.0)


## Explosion an pos (Weltkoordinaten) mit sichtbarem Radius und Farbe: heller Kern, Feuerball bis
## zum Radius, Ring am Boden, ein weißer Druckring, fliegende Glut und kurz etwas Rauch.
static func explosion(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	if not _usable(parent):
		return
	var size: float = maxf(radius, 0.2)
	# Farbiger Feuerball, der bis zum Radius wächst und dabei verblasst.
	var ball_color: Color = Color(color.r, color.g, color.b, 0.5)
	var ball_material: StandardMaterial3D = _fading_material(ball_color)
	# Nur die Außenseite zeichnen: Die Kugel leuchtet so nicht doppelt, und wer mitten in der
	# Explosion steht, sieht statt einer farbigen Wand das Spiel.
	ball_material.cull_mode = BaseMaterial3D.CULL_BACK
	var ball: MeshInstance3D = _mesh_node(_sphere(), ball_material)
	ball.name = "Explosion"
	parent.add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * size * 0.5
	var ball_tween: Tween = ball.create_tween()
	ball_tween.set_parallel(true)
	ball_tween.tween_property(ball, "scale", Vector3.ONE * size * 2.0, EXPLOSION_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ball_tween.tween_property(ball.material_override, "albedo_color:a", 0.0, EXPLOSION_TIME) \
		.set_ease(Tween.EASE_IN)
	ball_tween.chain().tween_callback(ball.queue_free)
	# Heißer innerer Ball: gelbweiß, halb so groß, schneller weg. Er gibt dem Feuerball eine Mitte.
	var hot_color: Color = color.lerp(Color(1.0, 0.95, 0.7), 0.7)
	var hot_material: StandardMaterial3D = _fading_material(Color(hot_color.r, hot_color.g, hot_color.b, 0.6))
	hot_material.cull_mode = BaseMaterial3D.CULL_BACK
	var hot: MeshInstance3D = _mesh_node(_sphere(), hot_material)
	hot.name = "ExplosionHot"
	parent.add_child(hot)
	hot.global_position = pos
	hot.scale = Vector3.ONE * size * 0.3
	var hot_tween: Tween = hot.create_tween()
	hot_tween.set_parallel(true)
	hot_tween.tween_property(hot, "scale", Vector3.ONE * size * 1.1, EXPLOSION_TIME * 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hot_tween.tween_property(hot_material, "albedo_color:a", 0.0, EXPLOSION_TIME * 0.8).set_ease(Tween.EASE_IN)
	hot_tween.chain().tween_callback(hot.queue_free)
	# Weißer Kern: der eigentliche Blitz. Klein gehalten, damit eine Explosion in der Nähe (oder
	# mehrere in einer Kette) nicht das ganze Bild weiß überstrahlt.
	var core_material: StandardMaterial3D = _fading_material(Color(1.0, 1.0, 0.92, 0.7))
	core_material.cull_mode = BaseMaterial3D.CULL_BACK
	var core: MeshInstance3D = _mesh_node(_sphere(), core_material)
	core.name = "ExplosionCore"
	parent.add_child(core)
	core.global_position = pos
	core.scale = Vector3.ONE * minf(size * 0.45, 1.2)
	var core_tween: Tween = core.create_tween()
	core_tween.tween_property(core, "scale", Vector3.ONE * 0.02, EXPLOSION_TIME * 0.45) \
		.set_ease(Tween.EASE_IN)
	core_tween.tween_callback(core.queue_free)
	# Ring am Boden zeigt die Reichweite, ein weißer Druckring läuft ihm voraus.
	var ground: Vector3 = _floor_below(parent, pos)
	_ring(parent, ground, size, Color(color.r, color.g, color.b, 0.9), EXPLOSION_TIME * 1.1, 0.0)
	_ring(parent, ground, size * 1.25, Color(1.0, 1.0, 1.0, 0.5), EXPLOSION_TIME * 0.7, 0.0)
	_add_light(parent, pos, color.lerp(Color.WHITE, 0.4), 4.0, size * 3.0, EXPLOSION_TIME)
	# Fliegende Glut und Rauch aus dem Vorrat.
	var pool: FxPool = pool_of(parent)
	var glow: Color = color.lerp(Color.WHITE, 0.45)
	glow.a = 1.0
	var debris: int = _throttled(EXPLOSION_DEBRIS, pool.spark_count(), FxPool.MAX_SPARKS)
	for _i: int in debris:
		var heading: Vector3 = _random_unit()
		heading.y = absf(heading.y) * 0.9 + 0.15
		pool.add_spark(pos, heading.normalized() * size * randf_range(2.2, 4.6), glow, 0.11,
			randf_range(0.4, 0.65), randf_range(0.35, 0.6), 9.0)
	var near: float = clampf(inverse_lerp(SMOKE_NEAR_DISTANCE, SMOKE_FULL_DISTANCE, _camera_distance(parent, pos)), 0.2, 1.0)
	var smoke_size: float = clampf(size * 0.42, 0.35, 1.3)
	var smoke: int = _throttled(EXPLOSION_SMOKE, pool.blob_count(), FxPool.MAX_BLOBS)
	for _i: int in smoke:
		var offset: Vector3 = _random_unit() * size * 0.22
		pool.add_blob(pos + offset, offset.normalized() * randf_range(0.4, 1.3) + Vector3(0.0, randf_range(0.5, 1.3), 0.0),
			Color(EXPLOSION_SMOKE_COLOR, EXPLOSION_SMOKE_COLOR.a * near), smoke_size * 0.45, smoke_size,
			randf_range(0.55, EXPLOSION_SMOKE_TIME), -0.6, 1.6)


## Konfetti-Regen an pos (Weltkoordinaten).
static func confetti(parent: Node, pos: Vector3) -> void:
	if not _usable(parent) or _live_confetti >= MAX_LIVE_CONFETTI:
		return
	var burst: CPUParticles3D = CPUParticles3D.new()
	burst.name = "Confetti"
	burst.emitting = false
	burst.one_shot = true
	burst.amount = CONFETTI_AMOUNT
	burst.lifetime = CONFETTI_LIFETIME
	burst.explosiveness = 0.95
	burst.randomness = 0.4
	burst.mesh = _confetti_quad()
	burst.direction = Vector3.UP
	burst.spread = 70.0
	burst.initial_velocity_min = 2.5
	burst.initial_velocity_max = 7.5
	burst.gravity = Vector3(0.0, -8.5, 0.0)
	burst.damping_min = 0.8
	burst.damping_max = 2.2
	burst.angle_min = 0.0
	burst.angle_max = 360.0
	burst.angular_velocity_min = -720.0
	burst.angular_velocity_max = 720.0
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.5
	burst.color_initial_ramp = _confetti_colors()
	burst.color_ramp = _confetti_fade_ramp()
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(burst)
	burst.global_position = pos
	burst.emitting = true
	_live_confetti += 1
	burst.tree_exited.connect(func() -> void: _live_confetti = maxi(0, _live_confetti - 1))
	var tween: Tween = burst.create_tween()
	tween.tween_interval(CONFETTI_LIFETIME + 0.25)
	tween.tween_callback(burst.queue_free)


## Druckwelle: heller Ring am Boden, der sich von pos bis radius ausbreitet, mit einer niedrigen
## durchscheinenden Wand, die mitläuft (so ist die Welle auch aus Augenhöhe gut zu sehen).
static func shockwave(parent: Node, pos: Vector3, radius: float) -> void:
	if not _usable(parent):
		return
	var size: float = maxf(radius, 0.2)
	_ring(parent, pos, size, Color(1.0, 1.0, 1.0, 0.85), SHOCKWAVE_TIME, 0.0)
	_ring(parent, pos, size * 0.96, SHOCKWAVE_COLOR, SHOCKWAVE_TIME, 0.03)
	# Ein dritter, schwächerer Ring läuft hinterher: Das wirkt wie eine echte Welle.
	_ring(parent, pos, size * 0.8, Color(SHOCKWAVE_COLOR, 0.3), SHOCKWAVE_TIME, 0.08)
	# Niedrige Wand, die mit dem Ring nach außen läuft und dabei flacher wird.
	var band_material: StandardMaterial3D = _fading_material(Color(SHOCKWAVE_COLOR, 0.3))
	var band: MeshInstance3D = _mesh_node(_band(), band_material)
	band.name = "ShockwaveBand"
	parent.add_child(band)
	band.global_position = pos + Vector3(0.0, SHOCKWAVE_BAND_HEIGHT * 0.5, 0.0)
	band.scale = Vector3(0.15, SHOCKWAVE_BAND_HEIGHT, 0.15)
	var band_tween: Tween = band.create_tween()
	band_tween.set_parallel(true)
	band_tween.tween_property(band, "scale", Vector3(size, SHOCKWAVE_BAND_HEIGHT * 0.3, size), SHOCKWAVE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	band_tween.tween_property(band_material, "albedo_color:a", 0.0, SHOCKWAVE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	band_tween.chain().tween_callback(band.queue_free)
	# Flache Kuppel als kurzer Lichtstoß.
	var dome: MeshInstance3D = _mesh_node(_sphere(), _fading_material(Color(SHOCKWAVE_COLOR, 0.22)))
	dome.name = "ShockwaveDome"
	parent.add_child(dome)
	dome.global_position = pos
	dome.scale = Vector3(0.3, 0.1, 0.3)
	var tween: Tween = dome.create_tween()
	tween.set_parallel(true)
	tween.tween_property(dome, "scale", Vector3(size * 2.0, size * 0.5, size * 2.0), SHOCKWAVE_TIME * 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(dome.material_override, "albedo_color:a", 0.0, SHOCKWAVE_TIME * 0.8)
	tween.chain().tween_callback(dome.queue_free)


## Kündigt die Trefferzahl eines Kugeltreffers an: Die nächste Zahl mit genau diesem Betrag wird
## als Kopftreffer (größer) oder kritischer Treffer (größer, eigene Farbe, Ausrufezeichen)
## gezeigt. Die Waffe ruft das direkt vor Events.bullet_hit und danach clear_number_hint: Wer die
## Zahl zeigt (UpgradeEffects), kennt nur Betrag und Farbe.
static func hint_number(amount: float, headshot: bool, crit: bool) -> void:
	_hint_amount = maxf(amount, 0.0)
	_hint_headshot = headshot
	_hint_crit = crit


static func clear_number_hint() -> void:
	_hint_amount = -1.0


## Aufsteigende Trefferzahl an pos (Weltkoordinaten). Größe nach Betrag, steigt kurz auf und
## verblasst. Treffer, die kurz nacheinander an fast derselben Stelle in derselben Farbe landen,
## zählen in einer Zahl zusammen. Höchstens MAX_LIVE_NUMBERS zugleich.
static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color) -> void:
	if not _usable(parent):
		return
	var headshot: bool = false
	var crit: bool = false
	if _hint_amount >= 0.0 and absf(amount - _hint_amount) < 0.001 + _hint_amount * 0.0001:
		headshot = _hint_headshot
		crit = _hint_crit
		_hint_amount = -1.0
	var shown: Color = Color(CRIT_NUMBER_COLOR if crit else color, 1.0)
	var key: int = shown.to_rgba32() * 4 + (2 if crit else 0) + (1 if headshot else 0)
	var now: int = Engine.get_physics_frames()
	var window: int = maxi(1, roundi(NUMBER_MERGE_TIME * float(Engine.physics_ticks_per_second)))
	for known: NumberEntry in _numbers:
		if known.key != key or now - known.born > window or known.anchor.distance_squared_to(pos) > NUMBER_MERGE_RADIUS * NUMBER_MERGE_RADIUS:
			continue
		if not is_instance_valid(known.label) or known.label.get_parent() != parent or known.label.is_queued_for_deletion():
			continue
		# Zusammenzählen: Die Zahl wächst, ploppt neu auf und steigt von ihrer Stelle weiter.
		known.amount += amount
		known.label.text = _number_text(known.amount, crit)
		_animate_number(parent, known, NUMBER_MERGE_POP_FROM)
		return
	if _numbers.size() >= MAX_LIVE_NUMBERS:
		return
	var label: Label3D = Label3D.new()
	label.name = "DamageNumber"
	label.text = _number_text(amount, crit)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = 5
	label.outline_render_priority = 4
	label.pixel_size = 0.005
	label.font_size = NUMBER_FONT_SIZE
	label.outline_size = NUMBER_OUTLINE_SIZE
	label.modulate = shown
	label.outline_modulate = Color(0.05, 0.05, 0.08, 1.0)
	parent.add_child(label)
	label.global_position = pos + _number_offset(parent, pos)
	var entry: NumberEntry = NumberEntry.new()
	entry.label = label
	entry.anchor = pos
	entry.born = now
	entry.key = key
	entry.amount = amount
	entry.headshot = headshot
	entry.crit = crit
	_numbers.append(entry)
	label.tree_exited.connect(func() -> void: _numbers.erase(entry))
	_animate_number(parent, entry, NUMBER_CRIT_POP_FROM if crit else NUMBER_POP_FROM)


## Versatz einer neuen Trefferzahl vom Treffpunkt: zur Seite (im Bild der Kamera, abwechselnd links
## und rechts) und etwas nach oben. Ohne Kamera ein kleiner zufälliger Versatz.
static func _number_offset(parent: Node, pos: Vector3) -> Vector3:
	var viewport: Viewport = parent.get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return Vector3(randf_range(-0.25, 0.25), randf_range(0.0, 0.2), randf_range(-0.25, 0.25))
	_number_side = -_number_side
	var reach: float = _distance_scale(parent, pos)
	return camera.global_transform.basis.x * (_number_side * randf_range(NUMBER_SIDE_MIN, NUMBER_SIDE_MAX) * reach) \
		+ Vector3(0.0, randf_range(NUMBER_LIFT_MIN, NUMBER_LIFT_MAX) * reach, 0.0)


## Zahl der gerade sichtbaren Trefferzahlen (für Tests).
static func live_number_count() -> int:
	return _numbers.size()


## Text einer Trefferzahl: ganzer Betrag, mindestens 1, kritisch mit Ausrufezeichen.
static func _number_text(amount: float, crit: bool) -> String:
	var text: String = str(maxi(1, roundi(amount)))
	return text + "!" if crit else text


## Größe einer Trefferzahl nach Betrag und Art (ohne den Abstand zur Kamera).
static func number_size(amount: float, headshot: bool = false, crit: bool = false) -> float:
	var size: float = lerpf(NUMBER_MIN_SIZE, NUMBER_MAX_SIZE, sqrt(clampf(amount / NUMBER_BIG_AMOUNT, 0.0, 1.0)))
	if crit:
		size *= NUMBER_CRIT_SCALE
	elif headshot:
		size *= NUMBER_HEADSHOT_SCALE
	return size


## Startet (oder erneuert) die Bewegung einer Trefferzahl: aufploppen von pop_from mal ihrer
## Größe (über 1 = sie schlägt ein, unter 1 = sie wächst auf), aufsteigen, verblassen, weg.
static func _animate_number(parent: Node, entry: NumberEntry, pop_from: float) -> void:
	if entry.tween != null and entry.tween.is_valid():
		entry.tween.kill()
	var label: Label3D = entry.label
	var start: Vector3 = label.global_position
	var size: float = _distance_scale(parent, start) * number_size(entry.amount, entry.headshot, entry.crit)
	label.scale = Vector3.ONE * size * pop_from
	label.modulate.a = 1.0
	label.outline_modulate.a = 1.0
	var drift: Vector3 = Vector3(randf_range(-0.2, 0.2), NUMBER_RISE, randf_range(-0.2, 0.2))
	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector3.ONE * size, NUMBER_TIME * 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "global_position", start + drift, NUMBER_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, NUMBER_TIME * 0.4).set_delay(NUMBER_TIME * 0.6)
	tween.tween_property(label, "outline_modulate:a", 0.0, NUMBER_TIME * 0.4).set_delay(NUMBER_TIME * 0.6)
	tween.chain().tween_callback(label.queue_free)
	entry.tween = tween


## Lässt ein Mesh kurz in color aufleuchten und stellt danach sein Material wieder her.
static func hit_flash(mesh: MeshInstance3D, color: Color, duration: float = 0.08) -> void:
	if not _usable(mesh):
		return
	# Mehrere Treffer kurz hintereinander: Das ursprüngliche Material wird nur einmal gemerkt,
	# und nur das letzte Aufblitzen stellt es wieder her.
	if not bool(mesh.get_meta(META_FLASH_ACTIVE, false)):
		mesh.set_meta(META_FLASH_ACTIVE, true)
		mesh.set_meta(META_FLASH_PREVIOUS, [mesh.material_override])
	var token: int = int(mesh.get_meta(META_FLASH_TOKEN, 0)) + 1
	mesh.set_meta(META_FLASH_TOKEN, token)
	mesh.material_override = _flash_material(color)
	var tween: Tween = mesh.create_tween()
	tween.tween_interval(maxf(duration, 0.01))
	tween.tween_callback(func() -> void:
		if not is_instance_valid(mesh) or int(mesh.get_meta(META_FLASH_TOKEN, 0)) != token:
			return
		var previous: Array = mesh.get_meta(META_FLASH_PREVIOUS, [null])
		mesh.material_override = previous[0] as Material
		mesh.set_meta(META_FLASH_ACTIVE, false)
		mesh.remove_meta(META_FLASH_PREVIOUS)
	)


## Leuchtendes, unbeleuchtetes, addierendes Material in dieser Farbe (je Farbe geteilt, also nie
## verändern). Für Effekte anderer Module, die dieselbe Material-Art nutzen sollen wie fx.gd.
static func glow_material(color: Color) -> StandardMaterial3D:
	return _glow_material(color)


## Größenfaktor für Schrift an pos: wächst mit dem Abstand zur Kamera, damit die Schrift auf
## dem Bildschirm etwa gleich groß bleibt (zwischen den Grenzen MIN und MAX).
static func _distance_scale(parent: Node, pos: Vector3) -> float:
	var distance: float = _camera_distance(parent, pos)
	if distance == INF:
		return 1.0
	return clampf(distance / NUMBER_REFERENCE_DISTANCE, NUMBER_MIN_DISTANCE_SCALE, NUMBER_MAX_DISTANCE_SCALE)


## Abstand von pos zur Kamera des Bildes, in dem parent hängt. INF ohne Kamera.
static func _camera_distance(parent: Node, pos: Vector3) -> float:
	var viewport: Viewport = parent.get_viewport()
	if viewport == null:
		return INF
	var camera: Camera3D = viewport.get_camera_3d()
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return INF
	return camera.global_position.distance_to(pos)


## Der Boden unter pos (höchstens FLOOR_SEARCH_DEPTH tiefer), sonst pos selbst. Nur ein Strahl
## auf die Welt, nichts wird verändert.
static func _floor_below(parent: Node, pos: Vector3) -> Vector3:
	var viewport: Viewport = parent.get_viewport()
	if viewport == null:
		return pos
	var world: World3D = viewport.find_world_3d()
	if world == null:
		return pos
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return pos
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		pos + Vector3(0.0, 0.05, 0.0), pos + Vector3(0.0, -FLOOR_SEARCH_DEPTH, 0.0), FLOOR_MASK)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return pos
	return hit["position"]


## Wie viele von wanted Teilen dürfen noch dazu? Ab POOL_THROTTLE_SHARE Belegung die Hälfte
## (mindestens eins), bei vollem Vorrat keins.
static func _throttled(wanted: int, used: int, capacity: int) -> int:
	if used >= capacity:
		return 0
	if float(used) >= float(capacity) * POOL_THROTTLE_SHARE:
		return maxi(1, wanted / 2)
	return mini(wanted, capacity - used)


## Darf an diesem Knoten ein Effekt entstehen?
static func _usable(parent: Node) -> bool:
	return is_instance_valid(parent) and parent.is_inside_tree()


## Flacher Ring auf Bodenhöhe, der bis radius wächst und verblasst.
static func _ring(parent: Node, pos: Vector3, radius: float, color: Color, time: float, delay: float) -> void:
	var ring: MeshInstance3D = _mesh_node(_ring_shape(), _fading_material(color))
	ring.name = "Ring"
	parent.add_child(ring)
	ring.global_position = pos + Vector3(0.0, 0.06, 0.0)
	ring.scale = Vector3(0.15, 0.6, 0.15)
	var tween: Tween = ring.create_tween()
	if delay > 0.0:
		ring.visible = false
		tween.tween_interval(delay)
		tween.tween_callback(ring.show)
	tween.tween_property(ring, "scale", Vector3(radius, 0.35, radius), time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(ring.material_override, "albedo_color:a", 0.0, time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(ring.queue_free)


## Kurzes Licht, das von energy auf 0 fällt. Es gibt nie mehr als MAX_LIVE_LIGHTS davon.
## pos ist eine Weltposition, mit local = true eine Position im Raum von parent.
static func _add_light(parent: Node, pos: Vector3, color: Color, energy: float, light_range: float, time: float, local: bool = false) -> void:
	if _live_lights >= MAX_LIVE_LIGHTS:
		return
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "FxLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = maxf(light_range, 0.5)
	light.shadow_enabled = false
	parent.add_child(light)
	if local:
		light.position = pos
	else:
		light.global_position = pos
	_live_lights += 1
	light.tree_exited.connect(func() -> void: _live_lights = maxi(0, _live_lights - 1))
	var tween: Tween = light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, maxf(time, 0.02))
	tween.tween_callback(light.queue_free)


## Zackiger Weg von a nach b: Zwischenpunkte mit zufälligem seitlichem Versatz.
static func _jagged_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var path: PackedVector3Array = PackedVector3Array()
	path.append(a)
	var offset: Vector3 = b - a
	var length: float = offset.length()
	if length < 0.01:
		return path
	var steps: int = clampi(int(ceil(length / LIGHTNING_STEP)), 2, 8)
	var axes: Basis = _basis_along(offset / length)
	var jitter: float = minf(LIGHTNING_JITTER, length * 0.2)
	for i: int in range(1, steps):
		var point: Vector3 = a + offset * (float(i) / float(steps))
		point += axes.x * randf_range(-jitter, jitter) + axes.y * randf_range(-jitter, jitter)
		path.append(point)
	path.append(b)
	return path


## Zwei gekreuzte Bänder von a nach b (von jeder Seite sichtbar). Gibt die Zahl der Ecken zurück.
static func _add_ribbon(mesh: ImmediateMesh, a: Vector3, b: Vector3, width: float, color: Color) -> int:
	var offset: Vector3 = b - a
	var length: float = offset.length()
	if length < 0.001:
		return 0
	var axes: Basis = _basis_along(offset / length)
	var half: float = width * 0.5
	_add_quad(mesh, a - axes.x * half, a + axes.x * half, b + axes.x * half, b - axes.x * half, color)
	_add_quad(mesh, a - axes.y * half, a + axes.y * half, b + axes.y * half, b - axes.y * half, color)
	return 12


## Kleiner Stern aus drei gekreuzten Flächen. Gibt die Zahl der Ecken zurück.
static func _add_spark(mesh: ImmediateMesh, center: Vector3, size: float) -> int:
	var half: float = size * 0.5
	var color: Color = LIGHTNING_CORE_COLOR
	_add_quad(mesh, center + Vector3(-half, -half, 0.0), center + Vector3(half, -half, 0.0),
		center + Vector3(half, half, 0.0), center + Vector3(-half, half, 0.0), color)
	_add_quad(mesh, center + Vector3(0.0, -half, -half), center + Vector3(0.0, -half, half),
		center + Vector3(0.0, half, half), center + Vector3(0.0, half, -half), color)
	_add_quad(mesh, center + Vector3(-half, 0.0, -half), center + Vector3(half, 0.0, -half),
		center + Vector3(half, 0.0, half), center + Vector3(-half, 0.0, half), color)
	return 18


static func _add_quad(mesh: ImmediateMesh, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, color: Color) -> void:
	for point: Vector3 in [p0, p1, p2, p0, p2, p3]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(point)


## Rechtwinklige Achsen, deren z-Achse entlang direction (Einheitsvektor) zeigt.
static func _basis_along(direction: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis: Vector3 = up.cross(direction).normalized()
	var y_axis: Vector3 = direction.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, direction)


static func _random_unit() -> Vector3:
	var v: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if v.length_squared() < 0.0001:
		return Vector3.UP
	return v.normalized()


static func _mesh_node(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Einheitswürfel (Kante 1).
static func _box() -> BoxMesh:
	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
		_box_mesh.size = Vector3.ONE
	return _box_mesh


## Kugel mit Radius 0,5 (Durchmesser 1): scale = gewünschter Durchmesser.
static func _sphere() -> SphereMesh:
	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radius = 0.5
		_sphere_mesh.height = 1.0
		_sphere_mesh.radial_segments = 16
		_sphere_mesh.rings = 8
	return _sphere_mesh


static func _quad() -> QuadMesh:
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2.ONE
	return _quad_mesh


## Flacher Ring mit Außenradius 1: scale.x/z = gewünschter Radius.
static func _ring_shape() -> TorusMesh:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.93
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 32
		_ring_mesh.ring_segments = 6
	return _ring_mesh


## Offener Zylindermantel mit Radius 1 und Höhe 1 (Wand der Druckwelle).
static func _band() -> CylinderMesh:
	if _band_mesh == null:
		_band_mesh = CylinderMesh.new()
		_band_mesh.top_radius = 1.0
		_band_mesh.bottom_radius = 1.0
		_band_mesh.height = 1.0
		_band_mesh.radial_segments = 32
		_band_mesh.rings = 1
		_band_mesh.cap_top = false
		_band_mesh.cap_bottom = false
	return _band_mesh


static func _confetti_quad() -> QuadMesh:
	if _confetti_mesh == null:
		_confetti_mesh = QuadMesh.new()
		_confetti_mesh.size = Vector2(0.2, 0.12)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.billboard_keep_scale = true
		_confetti_mesh.material = material
	return _confetti_mesh


static func _confetti_colors() -> Gradient:
	if _confetti_gradient == null:
		_confetti_gradient = Gradient.new()
		_confetti_gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		var offsets: PackedFloat32Array = PackedFloat32Array()
		var colors: PackedColorArray = PackedColorArray()
		for i: int in CONFETTI_COLORS.size():
			offsets.append(float(i) / float(CONFETTI_COLORS.size()))
			colors.append(CONFETTI_COLORS[i])
		_confetti_gradient.offsets = offsets
		_confetti_gradient.colors = colors
	return _confetti_gradient


static func _confetti_fade_ramp() -> Gradient:
	if _confetti_fade == null:
		_confetti_fade = Gradient.new()
		_confetti_fade.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
		_confetti_fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	return _confetti_fade


static func _lightning_mat() -> StandardMaterial3D:
	if _lightning_material == null:
		_lightning_material = _new_glow_material(Color.WHITE)
		_lightning_material.vertex_color_use_as_albedo = true
	return _lightning_material


## Leuchtendes, unbeleuchtetes Material in dieser Farbe. Wird je Farbe geteilt, also nie verändern.
static func _glow_material(color: Color) -> StandardMaterial3D:
	var key: int = color.to_rgba32()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	if _materials.size() >= MATERIAL_CACHE_LIMIT:
		_materials.clear()
	var material: StandardMaterial3D = _new_glow_material(color)
	_materials[key] = material
	return material


## Eigenes Material für einen einzelnen Effekt, dessen Deckkraft per Tween ausläuft.
static func _fading_material(color: Color) -> StandardMaterial3D:
	return _new_glow_material(color)


## Deckendes Leuchtmaterial für hit_flash (je Farbe geteilt).
static func _flash_material(color: Color) -> StandardMaterial3D:
	var key: int = -1 - color.to_rgba32()
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	if _materials.size() >= MATERIAL_CACHE_LIMIT:
		_materials.clear()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, 1.0)
	_materials[key] = material
	# Dieses Material kommt nie über einen neuen Knoten in den Baum, deshalb hier anmelden.
	ShaderKeep.hold(material)
	return material


static func _new_glow_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	return material
