extends Node
## Vorwärmen der Shader beim Spielstart (hinter einem Ladebild).
##
## Zeichnet jede bekannte Material-Art (ShaderKeep) einmal in allen vier Lichtlagen (kein
## Zusatzlicht, Punktlicht, Strahler, beides), dazu Partikel und 3D-Schrift. Godot übersetzt die
## Shader dabei jetzt und nicht erst mitten im Spiel, wenn die erste Kiste fällt.
##
## Der Aufbau steht weit unter dem Studio (kein Licht des Levels reicht dorthin) und wird von
## einer eigenen Kamera gefilmt. Danach ist wieder die Kamera des Spielers aktiv.
##
## main.gd ruft run() einmal vor Game.start_run. Headless (Tests) und nach einem Neustart des
## Laufs passiert nichts: Die Shader sind dann schon da.

const ShaderKeep := preload("res://scripts/game/fx/shader_keep.gd")
const UiStyle := preload("res://scripts/ui/hud.gd")
const Settings := preload("res://scripts/game/settings.gd")

const LAYER: int = 100
## Mitte des Aufbaus, weit weg vom Studio.
const RIG_ORIGIN: Vector3 = Vector3(0.0, -600.0, 0.0)
const GROUP_SPACING: float = 40.0
const CELL: float = 0.5
const CAMERA_DISTANCE: float = 90.0
## So viele Bilder lang bleibt der Aufbau stehen (Partikel brauchen ein Bild Anlauf).
const FRAMES: int = 8
const LABEL_SAMPLE: String = "0123456789?"

## true, sobald in diesem Programmlauf einmal vorgewärmt wurde.
static var done: bool = false
## Dauer des letzten Vorwärmens in Millisekunden (für Messungen).
static var last_duration_ms: int = 0


## Muss vorgewärmt werden? Nicht headless (dort wird nichts gezeichnet) und nur einmal.
static func is_needed() -> bool:
	return not done and DisplayServer.get_name() != "headless"


## Zeigt das Ladebild, zeichnet alle Material-Arten und räumt wieder auf.
func run() -> void:
	if not is_inside_tree():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var started: int = Time.get_ticks_msec()
	var overlay: CanvasLayer = _build_overlay()
	add_child(overlay)
	# Zwei Bilder warten: Das Ladebild soll stehen, bevor das lange Bild mit den Shadern kommt.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	ShaderKeep.load_lists()
	var previous_camera: Camera3D = get_viewport().get_camera_3d()
	var rig: Node3D = _build_rig()
	add_child(rig)
	(rig.get_node("Camera") as Camera3D).make_current()
	for _i: int in FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	if is_instance_valid(previous_camera) and previous_camera.is_inside_tree():
		previous_camera.make_current()
	rig.queue_free()
	# Ein Bild mit der Spielerkamera, solange das Ladebild noch deckt: Das Studio selbst ist
	# damit auch gezeichnet.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	overlay.queue_free()

	ShaderKeep.autosave = true
	ShaderKeep.save_if_changed()
	done = true
	last_duration_ms = Time.get_ticks_msec() - started
	print("Shader vorgewärmt: %d Arten in %d ms" % [ShaderKeep.known_count(), last_duration_ms])


## Text unter der Überschrift des Ladebilds. Mit dem Unterbau „Schnell“ (OpenGL-Treiber der
## Grafikkarte) übersetzt der Treiber die Shader bei jedem Start neu: Das Bild steht dann 10 bis
## 15 s still, und der Text sagt das, damit niemand an einen Absturz glaubt.
static func loading_text(driver: int) -> String:
	if driver == Settings.DRIVER_FAST:
		return "Das Studio wird aufgebaut.\nMit dem Grafik-Unterbau „Schnell“ dauert das bei jedem Start 10 bis 15 Sekunden."
	return "Das Studio wird aufgebaut.\nBeim allerersten Start dauert das etwas länger."


func _build_overlay() -> CanvasLayer:
	var overlay: CanvasLayer = CanvasLayer.new()
	overlay.name = "LoadingScreen"
	overlay.layer = LAYER
	var dim: ColorRect = UiStyle.make_dim(UiStyle.COL_INK)
	dim.name = "Dim"
	overlay.add_child(dim)
	var headline: PanelContainer = UiStyle.make_headline("GLEICH GEHT'S LOS", 56, UiStyle.COL_PURPLE, UiStyle.COL_YELLOW, UiStyle.COL_CYAN)
	headline.name = "Headline"
	headline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	headline.pivot_offset_ratio = Vector2(0.5, 0.5)
	headline.rotation_degrees = -3.0
	UiStyle.anchor_box(headline, Vector2(0.5, 0.5), Vector2(0.0, -110.0), Vector2.ZERO)
	overlay.add_child(headline)
	var subline: Label = UiStyle.make_label(loading_text(Settings.active_driver()), 24, UiStyle.COL_WHITE, true)
	subline.name = "Subline"
	subline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.anchor_box(subline, Vector2(0.5, 0.5), Vector2(-500.0, 30.0), Vector2(1000.0, 80.0))
	overlay.add_child(subline)
	return overlay


## Vier Gruppen nebeneinander, jede mit allen Material-Arten, je Gruppe eine andere Lichtlage.
func _build_rig() -> Node3D:
	var rig: Node3D = Node3D.new()
	rig.name = "WarmupRig"
	rig.position = RIG_ORIGIN
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, 0.0, CAMERA_DISTANCE)
	camera.far = 400.0
	rig.add_child(camera)

	var materials: Array[Dictionary] = ShaderKeep.material_entries()
	var labels: Array[Dictionary] = ShaderKeep.label_entries()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(CELL * 0.7, CELL * 0.7)
	var columns: int = maxi(1, int(ceil(sqrt(float(materials.size() * 2 + labels.size())))))
	for group_index: int in 4:
		var group: Node3D = Node3D.new()
		group.name = "Group%d" % group_index
		group.position = Vector3((float(group_index) - 1.5) * GROUP_SPACING, 0.0, 0.0)
		rig.add_child(group)
		if group_index == 1 or group_index == 3:
			var omni: OmniLight3D = OmniLight3D.new()
			omni.name = "Omni"
			omni.position = Vector3(0.0, 0.0, 3.0)
			omni.omni_range = 14.0
			omni.shadow_enabled = false
			group.add_child(omni)
		if group_index == 2 or group_index == 3:
			var spot: SpotLight3D = SpotLight3D.new()
			spot.name = "Spot"
			spot.position = Vector3(0.0, 0.0, 12.0)
			spot.spot_range = 22.0
			spot.spot_angle = 30.0
			spot.shadow_enabled = false
			group.add_child(spot)
		var slot: int = 0
		for entry: Dictionary in materials:
			var material: Material = entry["material"] as Material
			var usage: int = int(entry["usage"])
			if usage & ShaderKeep.USE_MESH != 0:
				var mesh: MeshInstance3D = MeshInstance3D.new()
				mesh.mesh = quad
				mesh.material_override = material
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh.position = _slot_position(slot, columns)
				group.add_child(mesh)
				slot += 1
			if usage & ShaderKeep.USE_PARTICLES != 0:
				var particles: CPUParticles3D = CPUParticles3D.new()
				particles.mesh = quad
				particles.material_override = material
				particles.amount = 2
				particles.lifetime = 30.0
				particles.explosiveness = 1.0
				particles.gravity = Vector3.ZERO
				particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				particles.position = _slot_position(slot, columns)
				group.add_child(particles)
				particles.emitting = true
				slot += 1
		for settings: Dictionary in labels:
			var label: Label3D = Label3D.new()
			label.text = LABEL_SAMPLE
			for property: String in settings:
				var current: Variant = label.get(property)
				if typeof(current) == TYPE_BOOL:
					label.set(property, int(settings[property]) != 0)
				else:
					label.set(property, int(settings[property]))
			label.pixel_size = 0.001
			label.position = _slot_position(slot, columns)
			group.add_child(label)
			slot += 1
	return rig


func _slot_position(slot: int, columns: int) -> Vector3:
	var column: int = slot % columns
	@warning_ignore("integer_division")
	var row: int = slot / columns
	return Vector3((float(column) - float(columns) * 0.5) * CELL, (float(row) - float(columns) * 0.5) * CELL, 0.0)
