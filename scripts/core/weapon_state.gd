extends RefCounted
## Zustand einer gehaltenen Waffe als reine Logik: Magazin, Nachladen, Schussfolge.
## Munition ist unendlich: Es gibt keinen Vorrat, nachgeladen wird, sobald das Magazin nicht voll ist.
## Kennt keine Nodes und keine Eingaben. Der WeaponController ruft jede Runde tick(delta).
## Besitzer: Waffen. Einbinden mit: const WeaponState := preload("res://scripts/core/weapon_state.gd")

const Balance := preload("res://scripts/core/balance.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")

var weapon_id: String = ""
## Kugeln im Magazin.
var mag: int = 0
var is_reloading: bool = false
## Restzeit des laufenden Nachladens in Sekunden.
var reload_left: float = 0.0
## Faktor auf die Nachladezeit (1,0 = normal, kleiner = schneller). Der WeaponController setzt ihn
## vor jedem Nachladen aus Game.weapon_reload_multiplier.
var reload_factor: float = 1.0
## Restzeit bis zum nächsten möglichen Schuss in Sekunden (<= 0 = schussbereit).
var cooldown_left: float = 0.0

var _def: Dictionary = {}


## Legt den Zustand für eine Waffe an: volles Magazin.
func _init(id: String = WeaponDefs.START_WEAPON) -> void:
	weapon_id = id
	_def = WeaponDefs.get_def(id)
	refill()


## Daten der Waffe aus WeaponDefs.
func get_def() -> Dictionary:
	return _def


## Magazingröße der Waffe.
func magazine_size() -> int:
	return int(_def.get("magazine", 0))


## Lässt Zeit vergehen. Gibt true zurück, wenn in diesem Schritt ein Nachladen fertig wurde.
func tick(delta: float) -> bool:
	if delta <= 0.0:
		return false
	# Die Schussfolge darf um weniger als einen Schritt unter 0 fallen: fire() rechnet den Rest
	# an, damit Dauerfeuer bei jeder Bildrate genau die Schussrate trifft. Ist der Schritt länger
	# als die Schussfolge, reicht der Rest für mehrere Schüsse in diesem Schritt (siehe fire).
	# Wer in dem Schritt nicht schießt, verliert den Rest (kein angesparter Schnellschuss).
	if cooldown_left > 0.0:
		cooldown_left -= delta
	else:
		cooldown_left = 0.0
	if not is_reloading:
		return false
	reload_left -= delta
	if reload_left > 0.0:
		return false
	_finish_reload()
	return true


## Darf jetzt geschossen werden? (Kugel im Magazin, kein Nachladen, Schussfolge abgelaufen)
func can_fire() -> bool:
	return not _def.is_empty() and not is_reloading and mag > 0 and cooldown_left <= 0.0


## Gibt einen Schuss ab: eine Kugel weniger im Magazin (auch bei mehreren Schrotkugeln),
## Schussfolge beginnt. Gibt false zurück und ändert nichts, wenn nicht geschossen werden darf.
## Der Rest des letzten Zeitschritts wird angerechnet. War der Schritt länger als die
## Schussfolge, bleibt die Waffe schussbereit: Der Aufrufer darf im selben Schritt weiterschießen,
## insgesamt höchstens Balance.FIRE_MAX_SHOTS_PER_FRAME Schüsse (mehr Rest verfällt).
func fire() -> bool:
	if not can_fire():
		return false
	mag -= 1
	var interval: float = 1.0 / float(_def["fire_rate"])
	var most_credit: float = interval * float(maxi(Balance.FIRE_MAX_SHOTS_PER_FRAME - 1, 0))
	cooldown_left = clampf(cooldown_left, -most_credit, 0.0) + interval
	return true


## Kann nachgeladen werden? (nicht schon dabei, Magazin nicht voll)
func can_reload() -> bool:
	return not _def.is_empty() and not is_reloading and mag < magazine_size()


## Magazin leer und kein Nachladen läuft: Der Controller lädt dann von selbst nach.
func needs_reload() -> bool:
	return mag <= 0 and can_reload()


## Dauer eines Nachladens in Sekunden.
func reload_duration() -> float:
	return float(_def.get("reload_time", 0.0)) * reload_factor


## Beginnt das Nachladen. Gibt false zurück, wenn es nicht möglich ist.
func start_reload() -> bool:
	if not can_reload():
		return false
	is_reloading = true
	reload_left = reload_duration()
	return true


## Bricht ein laufendes Nachladen ohne Wirkung ab.
func cancel_reload() -> void:
	is_reloading = false
	reload_left = 0.0


## Füllt das Magazin sofort. Ein laufendes Nachladen ist damit erledigt.
func refill() -> void:
	is_reloading = false
	reload_left = 0.0
	mag = magazine_size()


func _finish_reload() -> void:
	is_reloading = false
	reload_left = 0.0
	mag = magazine_size()
