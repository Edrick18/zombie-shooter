extends Node3D
## Modul: Upgrades (scripts/game/upgrades).
## Discokugel (Gegenstand "disco_ball", Abschnitt 19.2): eine kleine Spiegelkugel mit bunten
## Lichtflecken. Sie kreist im Abstand Balance.DISCO_ORBIT_RADIUS und etwa in Brusthöhe um den
## Spieler, mit Balance.DISCO_ORBIT_SPEED Radiant je Sekunde. Jeder Zombie im Umkreis
## Balance.DISCO_HIT_RADIUS um die Kugel nimmt Schaden: den Stufenwert "damage" der eigenen Stufe
## (level) mal Game.effect_factor(), über zombie.take_damage(schaden, {"source": "disco"}).
## Derselbe Zombie höchstens alle Balance.DISCO_HIT_INTERVAL Sekunden je Kugel.
##
## UpgradeEffects erzeugt je wirkendem Exemplar eine Kugel, hält Stufe und Platz aktuell, hängt
## sie in den Behälter aus Fx.root_of(...) und treibt sie an: Es ruft je Physik-Schritt
## tick(delta, grundwinkel) auf, solange das Spiel läuft, sonst hold(). Der Grundwinkel ist für
## alle Kugeln derselbe, jede steht um ihren Platz versetzt (slot von count): So bleiben mehrere
## Kugeln gleichmäßig über den Kreis verteilt, egal wann sie entstanden sind.
##
## Zwei Positionen: get_orbit_position() ist die Stelle, an der die Kugel für das Spiel steht
## (Stand des letzten Physik-Schritts, danach wird getroffen). Die sichtbare Stelle des Knotens
## gleitet in _process zwischen dem vorigen und diesem Stand, wie die Kamera des Spielers: Sonst
## würde die Kugel bei hoher Bildrate ruckeln. In der Pause stehen _process und der Antrieb still.
##
## Reichweite: Es zählt der waagerechte Abstand der Kugel zur Achse des Zombies (seine Füße). In
## der Höhe muss die Kugel auf den Körper des Zombies treffen, mit DISCO_HIT_RADIUS Spielraum
## nach oben und unten.

const Balance := preload("res://scripts/core/balance.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

## Gruppe aller Discokugeln.
const GROUP: String = "disco_balls"
## Höhe der Kugelmitte über den Füßen des Spielers (etwa Brusthöhe).
const ORBIT_HEIGHT: float = 1.15

# --- Reine Optik-Zahlen (keine Spielregeln) ---
const BALL_RADIUS: float = 0.2
const SPIN_SPEED: float = 2.2
const LIGHT_SPIN_SPEED: float = -3.4
const LIGHT_DISTANCE: float = 0.4
const SPECK_COUNT: int = 9
const LIGHT_COUNT: int = 4
const MIRROR_COLOR: Color = Color(0.8, 0.85, 0.95)
const NUMBER_COLOR: Color = Color(0.9, 0.6, 1.0)
const SPECK_COLORS: Array[Color] = [
	Color(1.0, 0.25, 0.6), Color(0.3, 0.9, 1.0), Color(1.0, 0.85, 0.2), Color(0.55, 1.0, 0.4),
]
## Reste einer Wartezeit unter diesem Wert gelten als abgelaufen (Rundung vieler kleiner Schritte).
const TIME_EPSILON: float = 0.0001

# Netze und Materialien gibt es einmal für alle Kugeln: keine neue Material-Art je Kugel.
static var _mirror_mesh: SphereMesh = null
static var _speck_mesh: SphereMesh = null
static var _cap_mesh: CylinderMesh = null
static var _speck_materials: Array[StandardMaterial3D] = []

## Stufe (Rarität) des Exemplars, 1 bis 5. Setzen mit set_level.
var level: int = 1
## Platz dieser Kugel unter allen Kugeln (0 = erste) und Zahl aller Kugeln. Setzen mit set_slot.
var slot: int = 0
var count: int = 1
## Zeigt die Kugel eigene Trefferzahlen? UpgradeEffects schaltet das mit seinen Zahlen gleich.
var show_damage_numbers: bool = true

## Winkel dieser Kugel auf dem Kreis (Grundwinkel plus Versatz des Platzes), in Radiant.
var _angle: float = 0.0
var _center: Vector3 = Vector3.ZERO
var _previous_center: Vector3 = Vector3.ZERO
var _has_center: bool = false
## Wartezeit je Zombie: Instanz-ID -> Sekunden bis zum nächsten Treffer dieser Kugel. Eine ID
## statt eines Knotens: Der Zombie kann jederzeit verschwinden.
var _hit_wait: Dictionary = {}
var _spin: Node3D = null
var _lights: Node3D = null


func _ready() -> void:
	add_to_group(GROUP)
	_build_visual()
	place(_angle - _slot_angle())
	# Die Kugel ploppt beim Erscheinen auf.
	scale = Vector3.ONE * 0.05
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Setzt die Stufe (1 bis 5). Der Schaden richtet sich danach.
func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, Balance.UPGRADE_MAX_LEVEL)


## Setzt den Platz (0 = erste Kugel) und die Zahl aller Kugeln: Die Kugel steht um
## TAU * index / total versetzt zum Grundwinkel. Danach place oder tick aufrufen.
func set_slot(index: int, total: int) -> void:
	count = maxi(1, total)
	slot = clampi(index, 0, count - 1)


## Schaden eines Treffers: Stufenwert mal Effekt-Faktor der aktuellen Welle.
func get_hit_damage() -> float:
	return UpgradeDefs.value("disco_ball", "damage", level) * Game.effect_factor() * UpgradeDefs.companion_factor(_companion_count())


## Zahl der Discokugeln, die gerade kreisen (mindestens 1): Mehrere teilen ihre Kraft.
func _companion_count() -> int:
	if not is_inside_tree():
		return 1
	var total: int = 0
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if not node.is_queued_for_deletion():
			total += 1
	return maxi(total, 1)


## Winkel dieser Kugel auf dem Kreis in Radiant (0 bis TAU).
func get_orbit_angle() -> float:
	return _angle


## Stelle der Kugel für das Spiel (Weltkoordinaten, Stand des letzten Schritts).
func get_orbit_position() -> Vector3:
	return _center if _has_center else global_position


## Versatz zur Position des Spielers (Füße) für einen Winkel auf dem Kreis.
static func orbit_offset(angle: float) -> Vector3:
	return Vector3(cos(angle) * Balance.DISCO_ORBIT_RADIUS, ORBIT_HEIGHT, sin(angle) * Balance.DISCO_ORBIT_RADIUS)


## Stellt die Kugel ohne Zeitschritt an ihre Stelle für diesen Grundwinkel (neu erzeugt, anderer
## Platz). Ohne Spieler bleibt sie, wo sie ist.
func place(base_angle: float) -> void:
	_angle = fposmod(base_angle + _slot_angle(), TAU)
	var player: Node3D = _player()
	if player == null or not is_inside_tree():
		return
	_center = player.global_position + orbit_offset(_angle)
	_previous_center = _center
	_has_center = true
	global_position = _center


## Ein Schritt: rückt auf den Platz für diesen Grundwinkel, lässt die Wartezeiten ablaufen und
## trifft jeden Zombie in Reichweite, der nicht mehr wartet. Ruft UpgradeEffects je
## Physik-Schritt auf, solange das Spiel läuft.
func tick(delta: float, base_angle: float) -> void:
	var player: Node3D = _player()
	if player == null or not is_inside_tree():
		return
	if not _has_center:
		place(base_angle)
	_angle = fposmod(base_angle + _slot_angle(), TAU)
	_previous_center = _center
	_center = player.global_position + orbit_offset(_angle)
	global_position = _center
	_tick_waits(delta)
	if bool(player.get("is_dead")):
		return
	_hit_zombies()


## Das Spiel läuft gerade nicht: Die Kugel bleibt stehen (auch die sichtbare Stelle).
func hold() -> void:
	_previous_center = _center


## Wie viele Zombies gerade auf ihren nächsten Treffer dieser Kugel warten.
func get_waiting_count() -> int:
	return _hit_wait.size()


func _process(delta: float) -> void:
	if is_instance_valid(_spin):
		_spin.rotation.y = fposmod(_spin.rotation.y + SPIN_SPEED * delta, TAU)
	if is_instance_valid(_lights):
		_lights.rotation.y = fposmod(_lights.rotation.y + LIGHT_SPIN_SPEED * delta, TAU)
	# Zwischen dem vorigen und dem aktuellen Stand gleiten (siehe Kopf der Datei).
	if _has_center and is_inside_tree():
		var fraction: float = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
		global_position = _previous_center.lerp(_center, fraction)


## Versatz dieses Platzes zum Grundwinkel.
func _slot_angle() -> float:
	return TAU * float(slot) / float(maxi(1, count))


func _tick_waits(delta: float) -> void:
	if _hit_wait.is_empty():
		return
	for id: int in _hit_wait.keys():
		var left: float = float(_hit_wait[id]) - delta
		if left <= TIME_EPSILON:
			_hit_wait.erase(id)
		else:
			_hit_wait[id] = left


## Schaden an allen lebenden Zombies in Reichweite, die nicht mehr warten.
func _hit_zombies() -> void:
	var damage: float = get_hit_damage()
	if damage <= 0.0:
		return
	var fx_root: Node = Fx.root_of(self)
	# Momentaufnahme: Ein Treffer kann Zombies töten oder (über andere Effekte) verschwinden lassen.
	# Die Schleife läuft ohne Typ: Ein freigegebenes Objekt darf nie in eine typisierte Variable.
	var candidates: Array = get_tree().get_nodes_in_group("zombies")
	for entry: Variant in candidates:
		if not _is_alive(entry):
			continue
		var zombie: Node3D = entry
		var id: int = zombie.get_instance_id()
		if _hit_wait.has(id) or not _in_reach(zombie):
			continue
		_hit_wait[id] = Balance.DISCO_HIT_INTERVAL
		var hit_position: Vector3 = _center_of(zombie)
		if show_damage_numbers:
			Fx.damage_number(fx_root, hit_position + Vector3(0.0, 0.6, 0.0), damage, NUMBER_COLOR)
		zombie.call("take_damage", damage, {"source": "disco", "hit_position": hit_position})


## Berührt die Kugel diesen Zombie? Waagerecht höchstens DISCO_HIT_RADIUS von seiner Achse, in
## der Höhe auf seinem Körper (mit demselben Spielraum).
func _in_reach(zombie: Node3D) -> bool:
	var feet: Vector3 = zombie.global_position
	var flat: Vector2 = Vector2(feet.x - _center.x, feet.z - _center.z)
	if flat.length() > Balance.DISCO_HIT_RADIUS:
		return false
	var height: float = Balance.ZOMBIE_HEIGHT
	if zombie.get("body_height") != null:
		height = float(zombie.get("body_height"))
	return _center.y >= feet.y - Balance.DISCO_HIT_RADIUS and _center.y <= feet.y + height + Balance.DISCO_HIT_RADIUS


## Der Spieler, wenn er gültig ist und im Baum hängt, sonst null.
func _player() -> Node3D:
	var player: Node3D = Game.player
	if is_instance_valid(player) and player.is_inside_tree():
		return player
	return null


func _is_alive(candidate: Variant) -> bool:
	if not is_instance_valid(candidate) or not candidate is Node3D:
		return false
	var zombie: Node3D = candidate
	return zombie.is_inside_tree() and not zombie.is_queued_for_deletion() \
		and not bool(zombie.get("is_dead")) and zombie.has_method("take_damage")


## Körpermitte eines Zombies (Trefferpunkt).
func _center_of(zombie: Node3D) -> Vector3:
	if zombie.has_method("get_center_position"):
		return zombie.call("get_center_position")
	return zombie.global_position + Vector3(0.0, Balance.ZOMBIE_HEIGHT * 0.5, 0.0)


## Baut die Spiegelkugel aus einfachen Formen: glänzende Kugel mit Aufhängung, bunte Plättchen
## auf der Oberfläche (drehen sich mit) und ein paar Lichtpunkte, die gegenläufig um sie kreisen.
func _build_visual() -> void:
	_prepare_shared()
	_spin = Node3D.new()
	_spin.name = "Spin"
	# Leicht gekippt, damit die Drehung zu sehen ist.
	_spin.rotation.z = 0.18
	add_child(_spin)
	var mirror: MeshInstance3D = MeshInstance3D.new()
	mirror.name = "Mirror"
	mirror.mesh = _mirror_mesh
	mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(mirror)
	var cap: MeshInstance3D = MeshInstance3D.new()
	cap.name = "Cap"
	cap.mesh = _cap_mesh
	cap.position = Vector3(0.0, BALL_RADIUS + 0.02, 0.0)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(cap)
	# Plättchen gleichmäßig über die Kugel verteilt (Spirale von oben nach unten).
	for i: int in SPECK_COUNT:
		var height: float = 1.0 - 2.0 * (float(i) + 0.5) / float(SPECK_COUNT)
		var ring: float = sqrt(maxf(0.0, 1.0 - height * height))
		var around: float = float(i) * 2.4
		var speck: MeshInstance3D = _speck(i)
		speck.name = "Speck%d" % i
		speck.position = Vector3(cos(around) * ring, height, sin(around) * ring) * BALL_RADIUS * 0.97
		speck.scale = Vector3.ONE * 0.075
		_spin.add_child(speck)
	_lights = Node3D.new()
	_lights.name = "Lights"
	add_child(_lights)
	for i: int in LIGHT_COUNT:
		var around: float = TAU * float(i) / float(LIGHT_COUNT)
		var light: MeshInstance3D = _speck(i)
		light.name = "Light%d" % i
		light.position = Vector3(cos(around) * LIGHT_DISTANCE, 0.12 * (1.0 if i % 2 == 0 else -1.0), sin(around) * LIGHT_DISTANCE)
		light.scale = Vector3.ONE * 0.06
		_lights.add_child(light)


## Ein bunter Punkt in der Farbe mit diesem Index (Netz und Material geteilt).
func _speck(index: int) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = _speck_mesh
	node.material_override = _speck_materials[index % _speck_materials.size()]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Legt Netze und Materialien einmal an. Die Arten gibt es im Spiel schon (leuchtend beleuchtet
## wie der Streifen der Drohne, unbeleuchtet wie ihre Linse, matt dunkel wie ihr Griff).
static func _prepare_shared() -> void:
	if _mirror_mesh != null:
		return
	var mirror: StandardMaterial3D = StandardMaterial3D.new()
	mirror.albedo_color = MIRROR_COLOR
	mirror.metallic = 0.9
	mirror.roughness = 0.18
	mirror.emission_enabled = true
	mirror.emission = MIRROR_COLOR
	mirror.emission_energy_multiplier = 0.35
	_mirror_mesh = SphereMesh.new()
	_mirror_mesh.radius = BALL_RADIUS
	_mirror_mesh.height = BALL_RADIUS * 2.0
	_mirror_mesh.radial_segments = 12
	_mirror_mesh.rings = 6
	_mirror_mesh.material = mirror
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.07)
	dark.metallic = 0.8
	dark.roughness = 0.3
	_cap_mesh = CylinderMesh.new()
	_cap_mesh.top_radius = 0.035
	_cap_mesh.bottom_radius = 0.06
	_cap_mesh.height = 0.07
	_cap_mesh.radial_segments = 8
	_cap_mesh.rings = 1
	_cap_mesh.material = dark
	_speck_mesh = SphereMesh.new()
	_speck_mesh.radius = 0.5
	_speck_mesh.height = 1.0
	_speck_mesh.radial_segments = 6
	_speck_mesh.rings = 3
	for color: Color in SPECK_COLORS:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		_speck_materials.append(material)
