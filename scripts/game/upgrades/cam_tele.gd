extends "res://scripts/game/upgrades/camera_base.gd"
## Modul: Upgrades (scripts/game/upgrades).
## Tele-Kamera (Kamera "cam_tele", Abschnitt 22.1): seltener, starker Schuss auf den nächsten
## Zombie mit freier Sichtlinie. Der Schuss geht durch weitere Zombies in der Linie ("pierce" aus
## dem Eintrag), jeder bekommt den vollen Schaden. Quelle "cam_tele".
##
## Die Linie: In der Waagerechten von der Kamera durch das Ziel, bis zur Reichweite. Die Kamera
## schwebt über den Köpfen, ein schräger Strahl im Raum träfe hinter dem ersten Zombie nur noch
## den Boden. Getroffen wird, wessen Körper die Linie berührt (Körperradius plus LINE_TOLERANCE),
## der Reihe nach vom Ziel weg. Der erste Zombie ohne freie Sicht beendet den Schuss (Wand).
##
## Zweitkamera ("second" > 0): ein zweiter Schuss mit diesem Anteil am Schaden auf den nächsten
## Zombie, den der erste Schuss nicht getroffen hat, wieder mit Durchschlag (ohne die schon
## Getroffenen).
##
## Aussehen: schlanker dunkelblauer Rumpf mit sehr langem Objektiv und einem großen Rotor obenauf.

const CAMERA_ID: String = "cam_tele"
## So nah darf die Linie am Körper eines Zombies vorbeigehen und trifft ihn trotzdem (Meter).
const LINE_TOLERANCE: float = 0.2

# --- Reine Optik-Zahlen ---
const BODY_COLOR: Color = Color(0.13, 0.19, 0.4)
const ACCENT_COLOR: Color = Color(0.25, 0.6, 1.0)
const BEAM_COLOR: Color = Color(0.25, 0.55, 1.0)
const BEAM_WIDTH: float = 0.11
const BEAM_TIME: float = 0.22
const ROTOR_SPEED: float = 30.0


func _init() -> void:
	camera_id = CAMERA_ID
	number_color = Color(0.45, 0.75, 1.0)


## Schießt sofort auf das nächste sichtbare Ziel, ohne den Takt zu prüfen (auch für Tests).
## Gibt true zurück, wenn ein Schuss fiel.
func try_fire() -> bool:
	var damage: float = get_shot_damage()
	if damage <= 0.0:
		return false
	var in_range: Array[Node3D] = targets_in_range()
	var first: Array[Node3D] = pick_visible(in_range, 1)
	if first.is_empty():
		return false
	# Erst alle Linien festlegen, dann Schaden verteilen: Ein Tod ändert nichts an der Auswahl.
	var lines: Array = []
	var taken: Dictionary = {}
	var hits: Array[Node3D] = line_hits(first[0], in_range, taken)
	lines.append({"hits": hits, "share": 1.0})
	var share: float = get_second_share()
	if share > 0.0:
		for zombie: Node3D in hits:
			taken[zombie.get_instance_id()] = true
		var second: Array[Node3D] = pick_visible(in_range, 1, taken)
		if not second.is_empty():
			lines.append({"hits": line_hits(second[0], in_range, taken), "share": share})
	var from: Vector3 = get_muzzle_position()
	var fx_root: Node = Fx.root_of(self)
	var aim_point: Vector3 = _center_of(first[0])
	UpgradeFx.burst(fx_root, from, BEAM_COLOR, 0.35)
	for line: Dictionary in lines:
		var targets: Array[Node3D] = line["hits"]
		var points: PackedVector3Array = PackedVector3Array()
		for zombie: Node3D in targets:
			points.append(_center_of(zombie))
		UpgradeFx.beam(fx_root, from, points[points.size() - 1], BEAM_COLOR,
			BEAM_WIDTH * clampf(float(line["share"]), 0.4, 1.0), BEAM_TIME)
		for i: int in targets.size():
			_damage(targets[i], damage * float(line["share"]), points[i])
	_after_shot(aim_point)
	return true


## Die Zombies, die ein Schuss auf target trifft: target selbst und dahinter bis zu "pierce"
## weitere in der Linie, der Reihe nach. in_range: die Zombies in Reichweite (targets_in_range),
## skip: Instanz-ID -> true für Zombies, die dieser Schuss auslässt.
func line_hits(target: Node3D, in_range: Array[Node3D], skip: Dictionary = {}) -> Array[Node3D]:
	var hits: Array[Node3D] = [target]
	var pierce: int = int(get_value("pierce"))
	if pierce <= 0:
		return hits
	var origin: Vector3 = global_position
	var to_target: Vector3 = _center_of(target) - origin
	var flat: Vector2 = Vector2(to_target.x, to_target.z)
	var target_along: float = flat.length()
	if target_along < 0.05:
		return hits
	var direction: Vector2 = flat / target_along
	var behind: Array = []
	for zombie: Node3D in in_range:
		if zombie == target or skip.has(zombie.get_instance_id()):
			continue
		var offset: Vector3 = _center_of(zombie) - origin
		var rel: Vector2 = Vector2(offset.x, offset.z)
		var along: float = rel.dot(direction)
		if along <= target_along:
			continue
		if (rel - direction * along).length() > _radius_of(zombie) + LINE_TOLERANCE:
			continue
		behind.append([along, zombie])
	behind.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for pair: Array in behind:
		if hits.size() > pierce:
			break
		var zombie: Node3D = pair[1] as Node3D
		# Eine Wand dazwischen hält den Schuss auf.
		if not sees(zombie):
			break
		hits.append(zombie)
	return hits


func _build_visual() -> void:
	var shell: StandardMaterial3D = _lit(BODY_COLOR)
	var accent: StandardMaterial3D = _glowing(ACCENT_COLOR)
	var dark: StandardMaterial3D = _lit(Color(0.03, 0.03, 0.04), 0.8, 0.2)
	var pale: StandardMaterial3D = _lit(Color(0.85, 0.88, 0.95))
	# Schlanker Rumpf mit blauem Streifen und Sucher.
	_add_box("Body", Vector3(0.22, 0.2, 0.46), Vector3.ZERO, shell)
	_add_box("Stripe", Vector3(0.23, 0.04, 0.47), Vector3(0.0, -0.04, 0.0), accent)
	_add_box("Sight", Vector3(0.05, 0.06, 0.26), Vector3(0.0, 0.13, 0.02), dark)
	# Sehr langes Objektiv: helles Rohr, blauer Ring, breite dunkle Blende.
	_add_cylinder("Barrel", 0.075, 0.075, 0.5, Vector3(0.0, 0.0, -0.48), pale, true)
	_add_cylinder("Ring", 0.085, 0.085, 0.05, Vector3(0.0, 0.0, -0.5), accent, true)
	_add_cylinder("Hood", 0.125, 0.085, 0.16, Vector3(0.0, 0.0, -0.8), dark, true)
	_add_cylinder("Glass", 0.105, 0.105, 0.01, Vector3(0.0, 0.0, -0.885), _flat(Color(0.5, 0.85, 1.0)), true)
	_muzzle.position = Vector3(0.0, 0.0, -0.92)
	# Ein großer Rotor obenauf.
	_add_rotor(Vector3(0.0, 0.3, 0.0), 0.7, 0.2, accent, dark, ROTOR_SPEED)
