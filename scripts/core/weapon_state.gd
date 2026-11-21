extends RefCounted
## Zustand einer gehaltenen Waffe als reine Logik: Magazin, Nachladen, Schussfolge.
## Munition ist unendlich: Es gibt keinen Vorrat, nachgeladen wird, sobald das Magazin nicht voll ist.
## Kennt keine Nodes und keine Eingaben. Der WeaponController ruft jede Runde tick(delta).
## Die Gegenstände der Waffe wirken über drei Faktoren, die der WeaponController setzt:
## reload_factor (Ladehilfe), magazine_bonus (Überlänge) und fire_rate_factor (Schnelldurchlauf).
## Besitzer: Waffen. Einbinden mit: const WeaponState := preload("res://scripts/core/weapon_state.gd")

const Balance := preload("res://scripts/core/balance.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")

## Reste einer Wartezeit unter diesem Wert gelten als abgelaufen (Rundung vieler kleiner Schritte).
const TIME_EPSILON: float = 0.00001

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
## Zusatz auf die Magazingröße als Bruchteil (0,3 = 30 % größer, aufgerundet). Nur lesen: gesetzt
## wird er mit set_magazine_bonus, damit das Magazin nie voller ist als seine Größe.
var magazine_bonus: float = 0.0
## Faktor auf die Schussrate (1,0 = normal, 1,2 = 20 % schneller): Die Zeit zwischen zwei
## Schüssen wird durch ihn geteilt. Gilt ab dem nächsten Schuss.
var fire_rate_factor: float = 1.0
## Salve (Abschnitt 22.2, WeaponDefs.burst): Schüsse, die nach dem Abzug noch von selbst folgen,
## und Sekunden bis zum nächsten davon. Nur lesen: fire() beginnt die Salve, burst_shot_due() und
## fire_burst_shot() arbeiten sie ab.
var burst_left: int = 0
var burst_wait: float = 0.0

var _def: Dictionary = {}


## Legt den Zustand für eine Waffe an: volles Magazin.
func _init(id: String = WeaponDefs.START_WEAPON) -> void:
	weapon_id = id
	_def = WeaponDefs.get_def(id)
	refill()


## Daten der Waffe aus WeaponDefs.
func get_def() -> Dictionary:
	return _def


## Magazingröße der Waffe mit dem Zusatz magazine_bonus.
func magazine_size() -> int:
	return WeaponDefs.magazine_size(weapon_id, magazine_bonus)


## Setzt den Zusatz auf die Magazingröße. Die Kugeln im Magazin bleiben, aber nie mehr als die
## neue Größe: Ein größeres Magazin füllt sich nicht von selbst, ein kleineres verliert den Rest.
func set_magazine_bonus(bonus: float) -> void:
	magazine_bonus = maxf(bonus, 0.0)
	mag = mini(mag, magazine_size())


## Sekunden zwischen zwei Schüssen mit dem Faktor fire_rate_factor. 0, wenn die Waffe unbekannt ist.
func fire_interval() -> float:
	if _def.is_empty():
		return 0.0
	return 1.0 / (float(_def["fire_rate"]) * maxf(fire_rate_factor, 0.01))


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
	if burst_left > 0:
		burst_wait -= delta
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
## Bei einer Salvenwaffe ist das der erste Schuss der Salve: Die übrigen folgen über
## burst_shot_due() und fire_burst_shot(). Die Schussfolge zählt von Salve zu Salve.
func fire() -> bool:
	if not can_fire():
		return false
	mag -= 1
	var interval: float = fire_interval()
	var most_credit: float = interval * float(maxi(Balance.FIRE_MAX_SHOTS_PER_FRAME - 1, 0))
	cooldown_left = clampf(cooldown_left, -most_credit, 0.0) + interval
	burst_left = mini(burst_size() - 1, mag)
	burst_wait = burst_interval() if burst_left > 0 else 0.0
	return true


## Schüsse je Abzug (1 = keine Salve).
func burst_size() -> int:
	return maxi(1, int(_def.get("burst", 1)))


## Sekunden zwischen zwei Schüssen einer Salve. Der Schnelldurchlauf (fire_rate_factor) verkürzt
## auch diesen Abstand.
func burst_interval() -> float:
	return float(_def.get("burst_interval", 0.0)) / maxf(fire_rate_factor, 0.01)


## Läuft gerade eine Salve (es folgen noch Schüsse von selbst)?
func is_bursting() -> bool:
	return burst_left > 0


## Ist der nächste Schuss der laufenden Salve fällig? Der WeaponController fragt das nach tick()
## in einer Schleife ab und ruft je fälligem Schuss fire_burst_shot().
func burst_shot_due() -> bool:
	return burst_left > 0 and burst_wait <= TIME_EPSILON and mag > 0 and not is_reloading


## Gibt den nächsten Schuss der Salve ab: eine Kugel weniger, ohne die Schussfolge zu berühren.
## false (und nichts ändert sich), wenn keiner fällig ist. Ist das Magazin danach leer, endet
## die Salve.
func fire_burst_shot() -> bool:
	if not burst_shot_due():
		return false
	mag -= 1
	burst_left -= 1
	if mag <= 0:
		burst_left = 0
	# Der Rest des Zeitschritts wird angerechnet, damit die Salve bei jeder Bildrate gleich lang ist.
	burst_wait = burst_wait + burst_interval() if burst_left > 0 else 0.0
	return true


## Bricht eine laufende Salve ab (Waffe weggelegt, Nachladen).
func cancel_burst() -> void:
	burst_left = 0
	burst_wait = 0.0


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
	cancel_burst()
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
