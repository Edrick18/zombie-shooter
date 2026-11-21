extends RefCounted
## Modul: FX (scripts/game/fx).
## Kurzlebige Effekte aus einfachen Formen: Leuchtspur, Mündungsfeuer, Blitzbogen, Blitzstern,
## Explosion, Konfetti, Druckwelle, Trefferzahl, Aufblitzen.
##
## Regeln für jede Funktion:
## - nur statische Funktionen, Einbinden mit const Fx := preload("res://scripts/game/fx/fx.gd")
## - nie abstürzen: ein ungültiger oder nicht im Baum hängender parent bedeutet "nichts tun"
## - jeder Effekt räumt sich selbst weg (queue_free nach Ablauf) und läuft auch headless ohne Fehler
## - Effekte ändern nie den Spielzustand (kein Schaden, keine Signale)
## - Zufall der Effekte kommt aus dem globalen Generator (randf), nie aus Game.rng: Die Optik darf
##   einen Lauf mit Seed nicht verändern.
## - Animationen laufen über Tweens des Effekt-Knotens: Sie halten in der Pause an und enden mit
##   dem Knoten.
## Als parent dient der Knoten aus root_of(...): der Behälter "Fx" unter Main (Gruppe "fx_root").

const ShaderKeep := preload("res://scripts/game/fx/shader_keep.gd")

const GROUP_FX_ROOT: String = "fx_root"

# --- Reine Optik-Zahlen (keine Spielregeln) ---
const TRACER_WIDTH: float = 0.035
const TRACER_TIME: float = 0.1
const MUZZLE_SIZE: float = 0.14
const MUZZLE_TIME: float = 0.06
const LIGHTNING_TIME: float = 0.2
const LIGHTNING_WIDTH: float = 0.16
const LIGHTNING_CORE_WIDTH: float = 0.06
const LIGHTNING_JITTER: float = 0.35
const LIGHTNING_STEP: float = 0.7
const LIGHTNING_COLOR: Color = Color(0.25, 0.9, 1.0, 0.95)
const LIGHTNING_CORE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const EXPLOSION_TIME: float = 0.32
const SHOCKWAVE_TIME: float = 0.4
const SHOCKWAVE_COLOR: Color = Color(0.7, 0.92, 1.0, 0.6)
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
## Beträgen). Große Treffer werden über den Maßstab größer: von 56/96 bis 128/96.
const NUMBER_FONT_SIZE: int = 96
const NUMBER_OUTLINE_SIZE: int = 22
## Obergrenzen, damit auch 24 Zombies in einer Kettenreaktion billig bleiben.
const MAX_LIVE_NUMBERS: int = 40
const MAX_LIVE_LIGHTS: int = 6
const MAX_LIVE_CONFETTI: int = 10
const MATERIAL_CACHE_LIMIT: int = 64
const META_FLASH_TOKEN: StringName = &"fx_flash_token"
const META_FLASH_ACTIVE: StringName = &"fx_flash_active"
const META_FLASH_PREVIOUS: StringName = &"fx_flash_previous"

## Bunte Gameshow-Farben für das Konfetti.
const CONFETTI_COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.35), Color(1.0, 0.8, 0.1), Color(0.2, 0.85, 0.35),
	Color(0.2, 0.65, 1.0), Color(0.85, 0.3, 1.0), Color(1.0, 0.5, 0.1), Color(1.0, 1.0, 1.0),
]

static var _box_mesh: BoxMesh = null
static var _sphere_mesh: SphereMesh = null
static var _quad_mesh: QuadMesh = null
static var _ring_mesh: TorusMesh = null
static var _confetti_mesh: QuadMesh = null
static var _confetti_gradient: Gradient = null
static var _confetti_fade: Gradient = null
static var _lightning_material: StandardMaterial3D = null
static var _materials: Dictionary = {}
static var _live_numbers: int = 0
static var _live_lights: int = 0
static var _live_confetti: int = 0


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


## Leuchtspur einer Kugel von from nach to (Weltkoordinaten).
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color) -> void:
	if not _usable(parent):
		return
	var offset: Vector3 = to - from
	var length: float = offset.length()
	if length < 0.05:
		return
	var direction: Vector3 = offset / length
	var beam: MeshInstance3D = _mesh_node(_box(), _glow_material(color))
	beam.name = "Tracer"
	parent.add_child(beam)
	var axes: Basis = _basis_along(direction)
	beam.global_transform = Transform3D(
		Basis(axes.x * TRACER_WIDTH, axes.y * TRACER_WIDTH, axes.z * length), (from + to) * 0.5)
	# Die Spur wird dünner und zieht sich zum Ziel hin zusammen: Das liest sich als Flugrichtung.
	var end_length: float = length * 0.35
	var end_transform: Transform3D = Transform3D(
		Basis(axes.x * 0.002, axes.y * 0.002, axes.z * end_length), to - direction * end_length * 0.5)
	var tween: Tween = beam.create_tween()
	tween.tween_property(beam, "global_transform", end_transform, TRACER_TIME).set_ease(Tween.EASE_IN)
	tween.tween_callback(beam.queue_free)


## Mündungsfeuer: kurzer heller Blitz als Kind von parent (z. B. die Mündung im ViewModel).
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
## einem kurzen Licht an light_pos.
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
	parent.add_child(arc)
	arc.global_transform = Transform3D.IDENTITY
	_add_light(parent, light_pos, Color(0.4, 0.9, 1.0), 2.5, 6.0, LIGHTNING_TIME)
	# Flackern: an, kurz aus, wieder an, weg.
	var tween: Tween = arc.create_tween()
	tween.tween_interval(LIGHTNING_TIME * 0.4)
	tween.tween_callback(arc.hide)
	tween.tween_interval(LIGHTNING_TIME * 0.15)
	tween.tween_callback(arc.show)
	tween.tween_interval(LIGHTNING_TIME * 0.45)
	tween.tween_callback(arc.queue_free)


## Explosion an pos (Weltkoordinaten) mit sichtbarem Radius und Farbe.
static func explosion(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	if not _usable(parent):
		return
	var size: float = maxf(radius, 0.2)
	# Farbiger Feuerball, der bis zum Radius wächst und dabei verblasst.
	var ball_color: Color = Color(color.r, color.g, color.b, 0.4)
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
	# Weißer Kern: der eigentliche Blitz. Klein gehalten, damit eine Explosion in der Nähe (oder
	# mehrere in einer Kette) nicht das ganze Bild weiß überstrahlt.
	var core_material: StandardMaterial3D = _fading_material(Color(1.0, 1.0, 0.92, 0.75))
	core_material.cull_mode = BaseMaterial3D.CULL_BACK
	var core: MeshInstance3D = _mesh_node(_sphere(), core_material)
	core.name = "ExplosionCore"
	parent.add_child(core)
	core.global_position = pos
	core.scale = Vector3.ONE * minf(size * 0.4, 1.4)
	var core_tween: Tween = core.create_tween()
	core_tween.tween_property(core, "scale", Vector3.ONE * 0.02, EXPLOSION_TIME * 0.45) \
		.set_ease(Tween.EASE_IN)
	core_tween.tween_callback(core.queue_free)
	# Ring am Boden zeigt die Reichweite.
	_ring(parent, pos, size, Color(color.r, color.g, color.b, 0.9), EXPLOSION_TIME * 1.1, 0.0)
	_add_light(parent, pos, color.lerp(Color.WHITE, 0.4), 4.0, size * 3.0, EXPLOSION_TIME)


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


## Druckwelle: flacher Ring am Boden, der sich von pos bis radius ausbreitet.
static func shockwave(parent: Node, pos: Vector3, radius: float) -> void:
	if not _usable(parent):
		return
	var size: float = maxf(radius, 0.2)
	_ring(parent, pos, size, SHOCKWAVE_COLOR, SHOCKWAVE_TIME, 0.0)
	# Ein zweiter, schwächerer Ring läuft hinterher: Das wirkt wie eine echte Welle.
	_ring(parent, pos, size * 0.8, Color(SHOCKWAVE_COLOR, 0.3), SHOCKWAVE_TIME, 0.08)
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


## Aufsteigende Trefferzahl an pos (Weltkoordinaten).
static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color) -> void:
	if not _usable(parent) or _live_numbers >= MAX_LIVE_NUMBERS:
		return
	var label: Label3D = Label3D.new()
	label.name = "DamageNumber"
	label.text = str(maxi(1, roundi(amount)))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = 5
	label.outline_render_priority = 4
	label.pixel_size = 0.005
	label.font_size = NUMBER_FONT_SIZE
	label.outline_size = NUMBER_OUTLINE_SIZE
	label.modulate = Color(color, 1.0)
	label.outline_modulate = Color(0.05, 0.05, 0.08, 1.0)
	parent.add_child(label)
	var start: Vector3 = pos + Vector3(randf_range(-0.25, 0.25), randf_range(0.0, 0.2), randf_range(-0.25, 0.25))
	label.global_position = start
	# Große Treffer bekommen große Zahlen.
	var size: float = _distance_scale(parent, start) * clampf(56.0 + amount * 0.5, 56.0, 128.0) / float(NUMBER_FONT_SIZE)
	label.scale = Vector3.ONE * size * 0.3
	_live_numbers += 1
	label.tree_exited.connect(func() -> void: _live_numbers = maxi(0, _live_numbers - 1))
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


## Größenfaktor für Schrift an pos: wächst mit dem Abstand zur Kamera, damit die Schrift auf
## dem Bildschirm etwa gleich groß bleibt (zwischen den Grenzen MIN und MAX).
static func _distance_scale(parent: Node, pos: Vector3) -> float:
	var viewport: Viewport = parent.get_viewport()
	if viewport == null:
		return 1.0
	var camera: Camera3D = viewport.get_camera_3d()
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return 1.0
	var distance: float = camera.global_position.distance_to(pos)
	return clampf(distance / NUMBER_REFERENCE_DISTANCE, NUMBER_MIN_DISTANCE_SCALE, NUMBER_MAX_DISTANCE_SCALE)


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
