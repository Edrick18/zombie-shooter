extends "res://scripts/game/upgrades/camera_base.gd"
## Modul: Upgrades (scripts/game/upgrades).
## Regie-Kamera (Kamera "cam_director", Abschnitt 22.1): Sie macht keinen Schaden. In ihrem Takt
## markiert sie einen Zombie über zombie.apply_mark("mark", "mark_duration"): Markierte nehmen
## aus jeder Quelle mehr Schaden (das rechnet der Zombie selbst).
##
## Ziel: zuerst Elite, dann unmarkierte Zombies, jeweils der nächste zuerst, Sichtlinie wie bei
## der Drohne. Genauer, in dieser Reihenfolge:
##   1. Elite, die eine Markierung braucht
##   2. andere Zombies, die eine Markierung brauchen
##   3. Elite mit laufender Markierung
##   4. andere Zombies mit laufender Markierung
## Eine Markierung braucht, wer keine hat, und wer seine von dieser Kamera hat, wenn sie vor
## deren nächstem Auslösen abläuft. So bleibt eine Elite dauerhaft markiert, und die Kamera
## verschwendet keine Markierung auf einen Zombie, der noch lange markiert ist.
##
## Zweitkamera ("second" > 0): Ein zweiter Zombie wird markiert, mit diesem Anteil am
## Mehr-Schaden.
##
## Aussehen: schwarzes Gehäuse mit pinkem Sprechtrichter vorn, Regieklappe obenauf und zwei
## Rotoren übereinander. Zu sehen ist die Markierung als pinker Strahl zum Zombie (die pinke
## Pyramide über seinem Kopf zeigt der Zombie selbst).

const CAMERA_ID: String = "cam_director"

# --- Reine Optik-Zahlen ---
const BODY_COLOR: Color = Color(0.08, 0.08, 0.1)
const ACCENT_COLOR: Color = Color(1.0, 0.2, 0.75)
const BEAM_COLOR: Color = Color(1.0, 0.25, 0.75)
const BEAM_WIDTH: float = 0.07
const BEAM_TIME: float = 0.35
const ROTOR_SPEED: float = 34.0

## Eigene Markierungen: Instanz-ID des Zombies -> Sekunden, die sie noch läuft. Eine ID statt
## eines Knotens: Der Zombie kann jederzeit verschwinden.
var _own_marks: Dictionary = {}


func _init() -> void:
	camera_id = CAMERA_ID
	number_color = Color(1.0, 0.45, 0.85)


## Markiert sofort, ohne den Takt zu prüfen (auch für Tests). Gibt true zurück, wenn ein Zombie
## markiert wurde.
func try_fire() -> bool:
	var bonus: float = get_value("mark")
	var duration: float = get_value("mark_duration")
	if bonus <= 0.0 or duration <= 0.0:
		return false
	var share: float = get_second_share()
	var targets: Array[Node3D] = pick_visible(ranked_targets(), 2 if share > 0.0 else 1)
	if targets.is_empty():
		return false
	var from: Vector3 = get_muzzle_position()
	var fx_root: Node = Fx.root_of(self)
	for i: int in targets.size():
		var target: Node3D = targets[i]
		if not target.has_method("apply_mark"):
			continue
		target.call("apply_mark", bonus * (1.0 if i == 0 else share), duration)
		_own_marks[target.get_instance_id()] = duration
		var head: Vector3 = _head_of(target)
		UpgradeFx.beam(fx_root, from, head, BEAM_COLOR, BEAM_WIDTH, BEAM_TIME)
		UpgradeFx.burst(fx_root, head, BEAM_COLOR, 0.55)
	_after_shot(_center_of(targets[0]))
	return true


## Die Zombies in Reichweite in der Reihenfolge, in der die Kamera sie wählt (siehe Kopf der
## Datei), ohne Sichtprüfung.
func ranked_targets() -> Array[Node3D]:
	var groups: Array = [[], [], [], []]
	for zombie: Node3D in targets_in_range():
		var index: int = (0 if needs_mark(zombie) else 2) + (0 if _is_elite(zombie) else 1)
		(groups[index] as Array).append(zombie)
	var result: Array[Node3D] = []
	for group: Array in groups:
		for zombie: Node3D in group:
			result.append(zombie)
	return result


## Braucht dieser Zombie eine Markierung? Ja, wenn er keine hat, und wenn seine von dieser
## Kamera stammt und vor deren nächstem Auslösen abläuft.
func needs_mark(zombie: Node3D) -> bool:
	if not zombie.has_method("is_marked") or not bool(zombie.call("is_marked")):
		return true
	var id: int = zombie.get_instance_id()
	return _own_marks.has(id) and float(_own_marks[id]) < get_fire_interval()


func _tick_extra(delta: float, _active: bool) -> void:
	if _own_marks.is_empty():
		return
	for id: int in _own_marks.keys():
		var left: float = float(_own_marks[id]) - delta
		if left <= TIME_EPSILON:
			_own_marks.erase(id)
		else:
			_own_marks[id] = left


## Punkt knapp über dem Kopf eines Zombies (dort schwebt seine Markierung).
func _head_of(zombie: Node3D) -> Vector3:
	var height: Variant = zombie.get("body_height")
	return zombie.global_position + Vector3(0.0, (float(height) if height != null else Balance.ZOMBIE_HEIGHT) + 0.15, 0.0)


func _build_visual() -> void:
	var shell: StandardMaterial3D = _lit(BODY_COLOR, 0.6, 0.35)
	var accent: StandardMaterial3D = _glowing(ACCENT_COLOR)
	var dark: StandardMaterial3D = _lit(Color(0.03, 0.03, 0.04), 0.8, 0.2)
	var white: StandardMaterial3D = _lit(Color(0.92, 0.92, 0.95))
	# Schwarzer Kasten mit pinkem Streifen.
	_add_box("Body", Vector3(0.26, 0.22, 0.34), Vector3.ZERO, shell)
	_add_box("Stripe", Vector3(0.27, 0.04, 0.35), Vector3(0.0, -0.05, 0.0), accent)
	# Sprechtrichter nach vorn: schmal am Gehäuse, weit an der Öffnung.
	_add_cylinder("Horn", 0.17, 0.05, 0.3, Vector3(0.0, 0.0, -0.32), accent, true)
	_add_cylinder("HornMouth", 0.13, 0.13, 0.01, Vector3(0.0, 0.0, -0.466), dark, true)
	_muzzle.position = Vector3(0.0, 0.0, -0.5)
	# Regieklappe obenauf: weiße Tafel mit schräg gestellter, gestreifter Leiste.
	_add_box("Slate", Vector3(0.3, 0.16, 0.03), Vector3(0.0, 0.2, 0.1), white)
	var clap: MeshInstance3D = _add_box("Clap", Vector3(0.3, 0.045, 0.035), Vector3(0.0, 0.32, 0.1), dark)
	clap.rotation.z = 0.22
	for i: int in 3:
		_add_box("ClapStripe", Vector3(0.045, 0.047, 0.037), Vector3(-0.1 + 0.1 * float(i), 0.0, 0.0), accent, clap)
	# Zwei Rotoren übereinander, gegenläufig.
	_add_rotor(Vector3(0.0, 0.42, -0.06), 0.5, 0.3, accent, dark, ROTOR_SPEED)
	_add_rotor(Vector3(0.0, 0.5, -0.06), 0.36, 0.08, white, dark, -ROTOR_SPEED)
