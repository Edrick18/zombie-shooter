extends Node3D
## Modul: Upgrades (scripts/game/upgrades).
## Mine der Requisitenbombe (Gegenstand "mine", Abschnitt 22.3): eine kleine Bühnen-Bombe am
## Boden. Dieser Knoten ist nur das Bild und der Zustand einer Mine. UpgradeEffects legt sie,
## lässt ihre Zeit vergehen (tick), prüft, ob ein Zombie nah genug ist, und zündet sie
## (Schaden, Events.mine_triggered, Events.explosion). Sie hängt im Behälter aus Fx.root_of(...).
##
## Eine frisch gelegte Mine ist ARM_TIME Sekunden lang noch nicht scharf: Sonst ginge eine Mine,
## die dem Spieler mitten im Gedränge vor die Füße fällt, im selben Augenblick hoch.

## Gruppe aller liegenden Minen.
const GROUP: String = "mines"
## Sekunden, bis eine gelegte Mine scharf ist.
const ARM_TIME: float = 0.6

# --- Reine Optik-Zahlen ---
const BODY_COLOR: Color = Color(0.06, 0.06, 0.08)
const BASE_COLOR: Color = Color(1.0, 0.78, 0.1)
const LAMP_COLOR: Color = Color(1.0, 0.25, 0.1)
const LAMP_IDLE_COLOR: Color = Color(0.35, 0.3, 0.28)
const BLINK_TIME: float = 0.5
const BLINK_ON_SHARE: float = 0.45

# Netze und Materialien gibt es einmal für alle Minen.
static var _base_mesh: CylinderMesh = null
static var _body_mesh: SphereMesh = null
static var _fuse_mesh: CylinderMesh = null
static var _lamp_mesh: SphereMesh = null
static var _lamp_on: StandardMaterial3D = null
static var _lamp_off: StandardMaterial3D = null

## Schaden der Explosion ohne den Effekt-Faktor der Welle (der kommt beim Zünden dazu).
var damage: float = 0.0

var _arm_left: float = ARM_TIME
var _time: float = 0.0
var _lamp: MeshInstance3D = null


func _ready() -> void:
	add_to_group(GROUP)
	_build_visual()
	# Die Mine ploppt beim Legen auf.
	scale = Vector3.ONE * 0.05
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Lässt die Zeit bis zum Scharfwerden vergehen. Ruft UpgradeEffects je Schritt auf.
func tick(delta: float) -> void:
	_arm_left = maxf(0.0, _arm_left - delta)


## Ist die Mine scharf (löst sie bei einem Zombie in der Nähe aus)?
func is_armed() -> bool:
	return _arm_left <= 0.0


func _process(delta: float) -> void:
	if not is_instance_valid(_lamp):
		return
	_time += delta
	# Scharf: Das Lämpchen blinkt. Vorher glimmt es nur.
	var lit: bool = is_armed() and fmod(_time, BLINK_TIME) < BLINK_TIME * BLINK_ON_SHARE
	_lamp.material_override = _lamp_on if lit else _lamp_off


## Baut die Bühnen-Bombe aus einfachen Formen: gelber Sockel, schwarze Kugel, Zündschnur mit Lämpchen.
func _build_visual() -> void:
	_prepare_shared()
	_add("Base", _base_mesh, Vector3(0.0, 0.025, 0.0))
	_add("Body", _body_mesh, Vector3(0.0, 0.2, 0.0))
	var fuse: MeshInstance3D = _add("Fuse", _fuse_mesh, Vector3(0.05, 0.42, 0.0))
	fuse.rotation.z = -0.35
	_lamp = _add("Lamp", _lamp_mesh, Vector3(0.085, 0.5, 0.0))
	_lamp.material_override = _lamp_off


func _add(node_name: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## Legt Netze und Materialien einmal an. Die Arten gibt es im Spiel schon (leuchtend beleuchtet
## wie der Streifen der Drohne, unbeleuchtet wie ihre Linse, dunkel glänzend wie ihr Griff).
static func _prepare_shared() -> void:
	if _base_mesh != null:
		return
	var base: StandardMaterial3D = StandardMaterial3D.new()
	base.albedo_color = BASE_COLOR
	base.emission_enabled = true
	base.emission = BASE_COLOR
	base.emission_energy_multiplier = 0.5
	_base_mesh = CylinderMesh.new()
	_base_mesh.top_radius = 0.2
	_base_mesh.bottom_radius = 0.24
	_base_mesh.height = 0.05
	_base_mesh.radial_segments = 12
	_base_mesh.rings = 1
	_base_mesh.material = base
	var body: StandardMaterial3D = StandardMaterial3D.new()
	body.albedo_color = BODY_COLOR
	body.metallic = 0.7
	body.roughness = 0.3
	_body_mesh = SphereMesh.new()
	_body_mesh.radius = 0.19
	_body_mesh.height = 0.38
	_body_mesh.radial_segments = 12
	_body_mesh.rings = 6
	_body_mesh.material = body
	_fuse_mesh = CylinderMesh.new()
	_fuse_mesh.top_radius = 0.02
	_fuse_mesh.bottom_radius = 0.03
	_fuse_mesh.height = 0.14
	_fuse_mesh.radial_segments = 6
	_fuse_mesh.rings = 1
	_fuse_mesh.material = base
	_lamp_mesh = SphereMesh.new()
	_lamp_mesh.radius = 0.045
	_lamp_mesh.height = 0.09
	_lamp_mesh.radial_segments = 8
	_lamp_mesh.rings = 4
	_lamp_on = StandardMaterial3D.new()
	_lamp_on.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_on.albedo_color = LAMP_COLOR
	_lamp_off = StandardMaterial3D.new()
	_lamp_off.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_off.albedo_color = LAMP_IDLE_COLOR
