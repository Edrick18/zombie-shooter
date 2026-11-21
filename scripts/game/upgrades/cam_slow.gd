extends "res://scripts/game/upgrades/camera_base.gd"
## Modul: Upgrades (scripts/game/upgrades).
## Zeitlupen-Kamera (Kamera "cam_slow", Abschnitt 22.1): Ihr Schuss macht wenig Schaden (Quelle
## "cam_slow") und verlangsamt den getroffenen Zombie über zombie.apply_slow("slow",
## "slow_duration"). Den halben Wert für Elite rechnet der Zombie selbst.
##
## Ziel: zuerst ein Zombie, der gerade nicht verlangsamt ist, sonst der nächste. So bremst die
## Kamera eine Gruppe reihum, statt immer denselben Zombie neu zu treffen. Sichtlinie wie bei der
## Drohne.
##
## Zweitkamera ("second" > 0): Ein zweiter Zombie bekommt diesen Anteil vom Schaden und von der
## Verlangsamung.
##
## Aussehen: Filmkamera in Eisblau mit zwei langsam drehenden Filmspulen obenauf, der Rotor
## hängt darunter.

const CAMERA_ID: String = "cam_slow"

# --- Reine Optik-Zahlen ---
const BODY_COLOR: Color = Color(0.16, 0.42, 0.5)
const ACCENT_COLOR: Color = Color(0.45, 0.85, 1.0)
const BEAM_COLOR: Color = Color(0.4, 0.9, 1.0)
const BEAM_WIDTH: float = 0.06
const BEAM_TIME: float = 0.24
const REEL_SPEED: float = 1.6
const ROTOR_SPEED: float = 36.0


func _init() -> void:
	camera_id = CAMERA_ID
	number_color = Color(0.6, 0.9, 1.0)


## Schießt sofort, ohne den Takt zu prüfen (auch für Tests). Gibt true zurück, wenn ein Schuss fiel.
func try_fire() -> bool:
	var share: float = get_second_share()
	var targets: Array[Node3D] = pick_visible(ranked_targets(), 2 if share > 0.0 else 1)
	if targets.is_empty():
		return false
	var damage: float = get_shot_damage()
	var slow: float = get_value("slow")
	var duration: float = get_value("slow_duration")
	# Erst alle Ziele und Punkte festlegen, dann wirken.
	var points: PackedVector3Array = PackedVector3Array()
	for zombie: Node3D in targets:
		points.append(_center_of(zombie))
	var from: Vector3 = get_muzzle_position()
	var fx_root: Node = Fx.root_of(self)
	for i: int in targets.size():
		var part: float = 1.0 if i == 0 else share
		UpgradeFx.beam(fx_root, from, points[i], BEAM_COLOR, BEAM_WIDTH, BEAM_TIME)
		UpgradeFx.burst(fx_root, points[i], BEAM_COLOR, 0.5)
		_damage(targets[i], damage * part, points[i])
		# Wer den Schuss überlebt, läuft langsamer.
		if _is_alive(targets[i]) and targets[i].has_method("apply_slow"):
			targets[i].call("apply_slow", slow * part, duration)
	_after_shot(points[0])
	return true


## Die Zombies in Reichweite in der Reihenfolge, in der die Kamera sie wählt: erst die nicht
## verlangsamten, dann die verlangsamten, jeweils der nächste zuerst (ohne Sichtprüfung).
func ranked_targets() -> Array[Node3D]:
	var fresh: Array[Node3D] = []
	var slowed: Array[Node3D] = []
	for zombie: Node3D in targets_in_range():
		if zombie.has_method("is_slowed") and bool(zombie.call("is_slowed")):
			slowed.append(zombie)
		else:
			fresh.append(zombie)
	fresh.append_array(slowed)
	return fresh


func _build_visual() -> void:
	var shell: StandardMaterial3D = _lit(BODY_COLOR)
	var accent: StandardMaterial3D = _glowing(ACCENT_COLOR)
	var dark: StandardMaterial3D = _lit(Color(0.03, 0.03, 0.04), 0.8, 0.2)
	# Gedrungener Kasten mit eisblauem Streifen und kurzem Objektiv mit Blende.
	_add_box("Body", Vector3(0.24, 0.24, 0.36), Vector3.ZERO, shell)
	_add_box("Stripe", Vector3(0.25, 0.04, 0.37), Vector3(0.0, -0.05, 0.0), accent)
	_add_cylinder("Lens", 0.08, 0.08, 0.14, Vector3(0.0, 0.0, -0.25), dark, true)
	_add_cylinder("Hood", 0.12, 0.085, 0.07, Vector3(0.0, 0.0, -0.345), shell, true)
	_add_cylinder("Glass", 0.085, 0.085, 0.01, Vector3(0.0, 0.0, -0.385), _flat(Color(0.7, 0.95, 1.0)), true)
	_muzzle.position = Vector3(0.0, 0.0, -0.42)
	# Zwei Filmspulen obenauf (liegen quer, drehen sich langsam um ihre Achse).
	for depth: float in [-0.11, 0.13]:
		var reel: MeshInstance3D = _add_cylinder("Reel", 0.14, 0.14, 0.06, Vector3(0.0, 0.25, depth), accent, false)
		reel.rotation.z = PI * 0.5
		# Speichen, damit man die Drehung sieht.
		_add_box("Spoke", Vector3(0.24, 0.07, 0.035), Vector3.ZERO, dark, reel)
		_add_box("Spoke", Vector3(0.035, 0.07, 0.24), Vector3.ZERO, dark, reel)
		_spinners.append({"node": reel, "speed": REEL_SPEED})
	# Der Rotor hängt unter der Kamera.
	_add_rotor(Vector3(0.0, -0.3, 0.0), 0.56, -0.16, accent, dark, ROTOR_SPEED)
