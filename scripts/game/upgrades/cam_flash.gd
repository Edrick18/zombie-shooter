extends "res://scripts/game/upgrades/camera_base.gd"
## Modul: Upgrades (scripts/game/upgrades).
## Blitzlicht-Kamera (Kamera "cam_flash", Abschnitt 22.1): Sie dreht sich zum nächsten Zombie mit
## freier Sichtlinie und blitzt. Der Blitz trifft alle Zombies im Kegel davor: voller
## Öffnungswinkel "cone_deg", Länge "range", jeder bekommt den festen Schaden. Quelle "cam_flash".
##
## Der Kegel: Der Winkel zählt in der Waagerechten (ein Fächer um die Blickrichtung zum Ziel), die
## Länge von der Kamera zur Körpermitte des Zombies. Die Kamera schwebt über den Köpfen: So
## trifft der Blitz, was man von oben im Fächer stehen sieht. Jeder Getroffene braucht freie Sicht.
##
## Zweitkamera ("second" > 0): CameraDefs.SECOND_FLASH_DELAY Sekunden später kommt ein zweiter
## Blitz mit diesem Anteil am Schaden. Er richtet sich neu auf den dann nächsten Zombie, ohne Ziel
## blitzt er in die alte Richtung. Auch er meldet sich über Events.camera_fired.
##
## Aussehen: breites helles Gehäuse mit großem Blitzkopf obenauf und vier kleinen Rotoren.
## Zu sehen ist der Blitz als heller Fächer am Boden und als Aufleuchten am Blitzkopf.

const CAMERA_ID: String = "cam_flash"
## Näher als so an der Achse der Kamera gilt ein Zombie immer als im Kegel (direkt darunter).
const CONE_INNER_RADIUS: float = 0.3
## Spielraum am Rand des Kegels in Radiant (Rundung).
const CONE_EPSILON: float = 0.0001

# --- Reine Optik-Zahlen ---
const BODY_COLOR: Color = Color(0.93, 0.88, 0.76)
const ACCENT_COLOR: Color = Color(1.0, 0.45, 0.08)
const FLASH_COLOR: Color = Color(1.0, 0.95, 0.7)
const PANEL_IDLE_COLOR: Color = Color(0.8, 0.74, 0.45)
const PANEL_GLOW_TIME: float = 0.18
const ROTOR_SPEED: float = 44.0

## Richtung des letzten Blitzes in der Waagerechten (Einheitsvektor).
var _flash_direction: Vector3 = Vector3.FORWARD
## Wartender zweiter Blitz: Sekunden bis dahin (0 = keiner) und sein Anteil am Schaden.
var _second_left: float = 0.0
var _second_share: float = 0.0
var _panel: MeshInstance3D = null
var _panel_glow_left: float = 0.0


func _init() -> void:
	camera_id = CAMERA_ID
	number_color = Color(1.0, 0.9, 0.45)


## Dreht sich zum nächsten sichtbaren Zombie und blitzt sofort, ohne den Takt zu prüfen (auch für
## Tests). Gibt true zurück, wenn sie geblitzt hat. Mit Zweitkamera merkt sie den zweiten Blitz vor.
func try_fire() -> bool:
	if get_shot_damage() <= 0.0:
		return false
	var target: Node3D = find_target()
	if target == null:
		return false
	_face(target)
	flash(1.0)
	var share: float = get_second_share()
	if share > 0.0:
		_second_left = CameraDefs.SECOND_FLASH_DELAY
		_second_share = share
	return true


## Ein Blitz in die aktuelle Richtung mit diesem Anteil am Schaden. Gibt die Zahl der getroffenen
## Zombies zurück. Meldet sich über Events.camera_fired, auch wenn er niemanden trifft.
func flash(share: float) -> int:
	var damage: float = get_shot_damage() * share
	# Erst alle Ziele festlegen, dann Schaden verteilen: Ein Tod ändert nichts an der Auswahl.
	var targets: Array[Node3D] = targets_in_cone()
	var points: PackedVector3Array = PackedVector3Array()
	for zombie: Node3D in targets:
		points.append(_center_of(zombie))
	var fx_root: Node = Fx.root_of(self)
	var strength: float = clampf(share, 0.35, 1.0)
	UpgradeFx.burst(fx_root, get_muzzle_position(), FLASH_COLOR, 0.9 * strength)
	UpgradeFx.flash_wedge(fx_root, Vector3(global_position.x, _floor_height(), global_position.z),
		_flash_direction, get_range(), get_value("cone_deg"), FLASH_COLOR, strength)
	_panel_glow_left = PANEL_GLOW_TIME
	for i: int in targets.size():
		_damage(targets[i], damage, points[i])
	_after_shot(global_position + _flash_direction * 3.0 + Vector3(0.0, -1.2, 0.0))
	return targets.size()


## Die Zombies, die ein Blitz in die aktuelle Richtung trifft: in Reichweite, im Fächer und mit
## freier Sicht, der nächste zuerst.
func targets_in_cone() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var half: float = deg_to_rad(get_value("cone_deg")) * 0.5
	var direction: Vector2 = Vector2(_flash_direction.x, _flash_direction.z)
	for zombie: Node3D in targets_in_range():
		var offset: Vector3 = _center_of(zombie) - global_position
		var flat: Vector2 = Vector2(offset.x, offset.z)
		if flat.length() > CONE_INNER_RADIUS and absf(direction.angle_to(flat)) > half + CONE_EPSILON:
			continue
		if sees(zombie):
			result.append(zombie)
	return result


## Richtung des Blitzes in der Waagerechten (Einheitsvektor).
func get_flash_direction() -> Vector3:
	return _flash_direction


## Sekunden bis zum vorgemerkten zweiten Blitz, 0 wenn keiner wartet.
func get_second_flash_left() -> float:
	return _second_left


func _tick_extra(delta: float, active: bool) -> void:
	if _second_left <= 0.0:
		return
	_second_left -= delta
	if _second_left > TIME_EPSILON:
		return
	_second_left = 0.0
	# Ist das Spiel inzwischen vorbei, verfällt der zweite Blitz.
	if not active:
		return
	var target: Node3D = find_target()
	if target != null:
		_face(target)
	flash(_second_share)


func _animate(delta: float) -> void:
	if _panel_glow_left <= 0.0 or not is_instance_valid(_panel):
		return
	_panel_glow_left -= delta
	_panel.material_override = _flat(FLASH_COLOR) if _panel_glow_left > 0.0 else _flat(PANEL_IDLE_COLOR)


## Richtet den Blitz in der Waagerechten auf diesen Zombie.
func _face(zombie: Node3D) -> void:
	var offset: Vector3 = _center_of(zombie) - global_position
	var flat: Vector3 = Vector3(offset.x, 0.0, offset.z)
	if flat.length_squared() > 0.0001:
		_flash_direction = flat.normalized()


## Bodenhöhe für den Fächer: die Füße des Spielers, sonst die Flughöhe unter der Kamera.
func _floor_height() -> float:
	var player: Node3D = _player()
	if player != null:
		return player.global_position.y
	return global_position.y - Balance.DRONE_HOVER_HEIGHT


func _build_visual() -> void:
	var shell: StandardMaterial3D = _lit(BODY_COLOR)
	var accent: StandardMaterial3D = _glowing(ACCENT_COLOR)
	var dark: StandardMaterial3D = _lit(Color(0.03, 0.03, 0.04), 0.8, 0.2)
	# Breites, flaches Gehäuse mit orangem Streifen und kurzem Objektiv.
	_add_box("Body", Vector3(0.42, 0.24, 0.2), Vector3.ZERO, shell)
	_add_box("Stripe", Vector3(0.43, 0.05, 0.21), Vector3(0.0, -0.06, 0.0), accent)
	_add_cylinder("Lens", 0.085, 0.085, 0.1, Vector3(0.0, 0.0, -0.15), dark, true)
	_add_cylinder("Glass", 0.07, 0.07, 0.01, Vector3(0.0, 0.0, -0.205), _flat(Color(0.45, 0.85, 1.0)), true)
	# Großer Blitzkopf obenauf: silberner Kasten mit heller Scheibe nach vorn.
	_add_box("FlashNeck", Vector3(0.08, 0.08, 0.08), Vector3(0.0, 0.16, 0.0), dark)
	_add_box("FlashHead", Vector3(0.34, 0.16, 0.14), Vector3(0.0, 0.27, 0.0), _lit(Color(0.72, 0.74, 0.8), 0.7, 0.3))
	_panel = _add_box("FlashPanel", Vector3(0.3, 0.12, 0.012), Vector3(0.0, 0.27, -0.075), _flat(PANEL_IDLE_COLOR))
	_muzzle.position = Vector3(0.0, 0.27, -0.12)
	# Vier kleine Rotoren an den Ecken.
	for side: float in [-1.0, 1.0]:
		for depth: float in [-1.0, 1.0]:
			_add_box("Arm", Vector3(0.14, 0.025, 0.04), Vector3(side * 0.27, 0.02, depth * 0.14), dark, self)
			_add_rotor(Vector3(side * 0.34, 0.1, depth * 0.14), 0.24, 0.08, accent, dark, ROTOR_SPEED * side)
