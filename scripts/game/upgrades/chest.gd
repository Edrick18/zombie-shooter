extends Area3D
## Modul: Upgrades (scripts/game/upgrades).
## Eine Kiste am Boden (Area3D, Lage 4, Maske 2, Gruppe "chests"). Sie bleibt liegen, bis der
## Spieler hineinläuft, dann öffnet sie über Game.open_chest(rarity) die Wahl und verschwindet.
##
## Aussehen: Truhe in der Farbe der Seltenheit (Bronze, Silber, Gold), die schwebt, sich dreht
## und leuchtet. Eine Lichtsäule bis unter die Decke macht sie quer durch den Raum sichtbar.

const Balance := preload("res://scripts/core/balance.gd")
const ChestRoller := preload("res://scripts/core/chest_roller.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

# --- Reine Optik-Zahlen ---
const BODY_SIZE: Vector3 = Vector3(0.8, 0.42, 0.55)
const LID_SIZE: Vector3 = Vector3(0.86, 0.2, 0.61)
## Höhe der Kastenmitte über dem Boden.
const HOVER_HEIGHT: float = 0.62
const BOB_AMPLITUDE: float = 0.12
const BOB_SPEED: float = 2.6
const SPIN_SPEED: float = 1.5
const BEAM_HEIGHT: float = 4.4
const BEAM_RADIUS: float = 0.16
const SPAWN_POP_TIME: float = 0.45
## Höhere Seltenheit leuchtet stärker und wirft eine dickere Lichtsäule.
const GLOW_BY_RARITY: Array[float] = [1.0, 1.5, 2.3]
const BEAM_WIDTH_BY_RARITY: Array[float] = [1.0, 1.3, 1.8]

## Seltenheit: 0 = Bronze, 1 = Silber, 2 = Gold.
var rarity: int = Balance.RARITY_BRONZE
## Nach dem Aufsammeln true. Eine Kiste öffnet sich nie zweimal.
var is_collected: bool = false

var _visual: Node3D = null
var _beam: MeshInstance3D = null
var _beam_material: StandardMaterial3D = null
var _light: OmniLight3D = null
var _time: float = 0.0
var _grace_left: float = 0.0


## Legt die Seltenheit fest. Vor add_child aufrufen.
func setup(chest_rarity: int) -> void:
	rarity = clampi(chest_rarity, Balance.RARITY_BRONZE, Balance.RARITY_GOLD)


func _ready() -> void:
	add_to_group("chests")
	collision_layer = Balance.LAYER_PICKUPS
	collision_mask = Balance.MASK_CHEST
	monitoring = true
	monitorable = false
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = Balance.CHEST_PICKUP_RADIUS
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = sphere
	shape.position = Vector3(0.0, Balance.CHEST_PICKUP_RADIUS * 0.5, 0.0)
	add_child(shape)
	_build_visual()
	# Phase je Kiste verschieben, damit mehrere Kisten nicht im Gleichtakt wippen.
	_time = fmod(absf(position.x * 1.7 + position.z * 2.3), TAU)
	_play_spawn_pop()
	Events.chest_opened.connect(_on_any_chest_opened)


func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_visual):
		_visual.position.y = HOVER_HEIGHT + sin(_time * BOB_SPEED) * BOB_AMPLITUDE
		_visual.rotation.y = _time * SPIN_SPEED
	var pulse: float = 0.5 + 0.5 * sin(_time * 4.0)
	if _beam_material != null:
		_beam_material.albedo_color.a = lerpf(0.3, 0.6, pulse)
	if is_instance_valid(_light):
		_light.light_energy = lerpf(1.2, 2.2, pulse) * _glow()


func _physics_process(delta: float) -> void:
	# Abfrage statt body_entered: So öffnet die Kiste auch, wenn der Spieler schon darin steht,
	# während gerade eine andere Wahl offen war.
	if is_collected or Game.state != Game.State.PLAYING:
		return
	if _grace_left > 0.0:
		_grace_left -= delta
		return
	for body: Node3D in get_overlapping_bodies():
		if is_instance_valid(body) and body.is_in_group("player"):
			collect()
			return


## Sammelt die Kiste auf: öffnet die Kistenwahl (Game.open_chest) und entfernt die Kiste.
## Wirkt nur einmal und nur im State PLAYING, sonst bleibt die Kiste liegen.
func collect() -> void:
	if is_collected or Game.state != Game.State.PLAYING:
		return
	is_collected = true
	remove_from_group("chests")
	# Der Jubel hängt im Effekt-Behälter und überlebt die Kiste. Er läuft weiter, sobald die
	# Wahl getroffen ist.
	if is_inside_tree():
		var fx_root: Node = Fx.root_of(self)
		var center: Vector3 = global_position + Vector3(0.0, HOVER_HEIGHT + 0.1, 0.0)
		Fx.confetti(fx_root, center)
		Fx.explosion(fx_root, center, 1.2, ChestRoller.rarity_color(rarity))
	Game.open_chest(rarity)
	queue_free()


## Eine andere Kiste wurde geöffnet: Diese hier wartet nach der Wahl einen Moment.
func _on_any_chest_opened(_chest_rarity: int, _offers: Array) -> void:
	if not is_collected:
		_grace_left = Balance.CHEST_REOPEN_GRACE


func _glow() -> float:
	return GLOW_BY_RARITY[clampi(rarity, 0, GLOW_BY_RARITY.size() - 1)]


func _build_visual() -> void:
	var color: Color = ChestRoller.rarity_color(rarity)
	var glow: float = _glow()
	var beam_width: float = BEAM_WIDTH_BY_RARITY[clampi(rarity, 0, BEAM_WIDTH_BY_RARITY.size() - 1)]

	var shell: StandardMaterial3D = StandardMaterial3D.new()
	shell.albedo_color = color
	shell.metallic = 0.6
	shell.roughness = 0.35
	shell.emission_enabled = true
	shell.emission = color
	shell.emission_energy_multiplier = 0.3 * glow
	var trim: StandardMaterial3D = StandardMaterial3D.new()
	trim.albedo_color = color.darkened(0.55)
	trim.metallic = 0.4
	trim.roughness = 0.5
	var shine: StandardMaterial3D = StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.albedo_color = color.lerp(Color.WHITE, 0.6)

	# Truhe: Der Kasten "Body" schwebt und dreht sich, alle Anbauten hängen an ihm.
	# Sein Ursprung ist die Mitte des Kastens.
	var half: float = BODY_SIZE.y * 0.5
	var body_mesh: BoxMesh = BoxMesh.new()
	body_mesh.size = BODY_SIZE
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = body_mesh
	body.material_override = shell
	body.position = Vector3(0.0, HOVER_HEIGHT, 0.0)
	add_child(body)
	_visual = body
	var lid: MeshInstance3D = _add_box(_visual, "Lid", LID_SIZE, Vector3(0.0, half + LID_SIZE.y * 0.5, 0.0), shell)
	# Der Deckel steht einen Spalt offen, aus dem es hell herausleuchtet.
	lid.position += Vector3(0.0, 0.04, -0.02)
	lid.rotation.x = deg_to_rad(-9.0)
	_add_box(_visual, "Gleam", Vector3(BODY_SIZE.x * 0.92, 0.05, BODY_SIZE.z * 0.9),
		Vector3(0.0, half + 0.02, 0.0), shine)
	# Beschläge: zwei Bänder und ein Schloss.
	for side: float in [-1.0, 1.0]:
		_add_box(_visual, "Band", Vector3(0.09, BODY_SIZE.y + 0.03, BODY_SIZE.z + 0.03),
			Vector3(side * BODY_SIZE.x * 0.3, 0.0, 0.0), trim)
	_add_box(_visual, "Lock", Vector3(0.14, 0.16, 0.06),
		Vector3(0.0, half * 0.56, BODY_SIZE.z * 0.5 + 0.02), shine)
	# Fragezeichen auf beiden Breitseiten: Hier wartet eine Überraschung.
	for side: float in [-1.0, 1.0]:
		var mark: Label3D = Label3D.new()
		mark.name = "Mark"
		mark.text = "?"
		mark.font_size = 96
		mark.pixel_size = 0.003
		mark.outline_size = 18
		mark.modulate = Color.WHITE
		mark.outline_modulate = color.darkened(0.7)
		mark.shaded = false
		mark.position = Vector3(0.0, -half * 0.28, side * (BODY_SIZE.z * 0.5 + 0.012))
		mark.rotation.y = 0.0 if side > 0.0 else PI
		_visual.add_child(mark, true)

	# Lichtsäule: ruht am Boden und dreht sich nicht mit.
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.albedo_color = Color(color.lerp(Color.WHITE, 0.25), 0.4)
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam_mesh: CylinderMesh = CylinderMesh.new()
	beam_mesh.top_radius = BEAM_RADIUS * beam_width * 0.45
	beam_mesh.bottom_radius = BEAM_RADIUS * beam_width
	beam_mesh.height = BEAM_HEIGHT
	beam_mesh.radial_segments = 12
	beam_mesh.rings = 1
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	_beam.mesh = beam_mesh
	_beam.material_override = _beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(0.0, BEAM_HEIGHT * 0.5 + 0.05, 0.0)
	add_child(_beam)

	# Leuchtender Ring am Boden markiert die Stelle zum Hineinlaufen.
	var ring_material: StandardMaterial3D = StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(color.lerp(Color.WHITE, 0.25), 0.8)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = Balance.CHEST_PICKUP_RADIUS * 0.82
	ring_mesh.outer_radius = Balance.CHEST_PICKUP_RADIUS * 0.92
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 6
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "GroundRing"
	ring.mesh = ring_mesh
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, 0.04, 0.0)
	ring.scale = Vector3(1.0, 0.25, 1.0)
	add_child(ring)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = color
	_light.light_energy = 1.6 * glow
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, HOVER_HEIGHT + 0.4, 0.0)
	add_child(_light)

	# Funken steigen in der Lichtsäule auf.
	var spark_material: StandardMaterial3D = StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = color.lerp(Color.WHITE, 0.5)
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_material.billboard_keep_scale = true
	var spark_mesh: QuadMesh = QuadMesh.new()
	spark_mesh.size = Vector2(0.06, 0.06)
	spark_mesh.material = spark_material
	var sparks: CPUParticles3D = CPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = 10 + 6 * rarity
	sparks.lifetime = 1.6
	sparks.mesh = spark_mesh
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.45
	sparks.direction = Vector3.UP
	sparks.spread = 12.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 0.8
	sparks.initial_velocity_max = 1.8
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.3
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.position = Vector3(0.0, HOVER_HEIGHT, 0.0)
	add_child(sparks)


func _add_box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = box
	node.material_override = material
	node.position = at
	parent.add_child(node, true)
	return node


## Die Kiste springt beim Erscheinen aus dem Boden hoch: Das zieht den Blick an.
func _play_spawn_pop() -> void:
	if not is_instance_valid(_visual):
		return
	_visual.scale = Vector3.ONE * 0.05
	var tween: Tween = create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE, SPAWN_POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_beam):
		_beam.scale = Vector3(1.0, 0.02, 1.0)
		_beam.position.y = 0.05
		tween.parallel().tween_property(_beam, "scale", Vector3.ONE, SPAWN_POP_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(_beam, "position:y", BEAM_HEIGHT * 0.5 + 0.05, SPAWN_POP_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
