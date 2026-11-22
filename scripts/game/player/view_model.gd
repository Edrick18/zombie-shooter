extends Node3D
## Modul: Spieler (scripts/game/player).
## Sichtbare Waffen vor der Kamera (Kind der Kamera, Name "ViewModel"). Zeigt, was der Spieler
## hält: eine Waffe (ein- oder zweihändig) rechts wie bisher, bei zwei Einhand-Waffen eine rechts
## und eine gespiegelt links. Hat keinen Einfluss auf Spielregeln.
##
## Der WeaponController ruft set_loadout (nach jedem Abgleich mit dem Rucksack) und play_fire
## (je Schuss einer Hand). Das Nachladen kommt über Events.hand_reload_started und
## hand_reload_finished. Jede Hand hat ihren eigenen Rückstoß und ihre eigene Nachlade-Bewegung.
##
## Aufbau:
##   ViewModel
##   └─ Rig (verkleinert, siehe VIEW_SCALE)
##       ├─ Hand0 (linke Hand: bei zwei Waffen gespiegelt links, sonst rechts)
##       │   └─ Holder (wird animiert)
##       │       └─ Gun_<id> (Modell der Waffe, entsteht beim ersten Zeigen)
##       └─ Hand1 (rechte Hand, nur bei zwei Waffen sichtbar)
##           └─ Holder
## Die 19 Modelle:
##   pistol           Dienstpistole: gelb-schwarz, Schlitten fährt zurück
##   revolver         Kandidatenschreck: silber-rot mit goldener Trommel, die sich weiterdreht
##   smg              Quotenhammer: türkis-pink, Magazin fällt beim Nachladen
##   sawed_off        Blitzrunde: lila-grün, zwei kurze Läufe, die zum Nachladen abkippen
##   shotgun          Publikumsjoker: rot-gold, Vorderschaft wird durchgeladen
##   rifle            Dauerbrenner: blau-orange, gebogenes Magazin
##   sniper           Fernbedienung: weiß-lila, langer Lauf, großes Zielfernrohr, Kammerstängel
##   minigun          Applausmaschine: pink-gelb, sechs Läufe, die sich drehen
##   rocket_launcher  Showfinale: grünes Rohr mit goldenen Ringen, rote Rakete vorn
##   burst_pistol     Dreierpack: pink-weiß, hoher Schlitten mit drei Mündungen übereinander
##   nail_gun         Bühnenbau: orange, stehender Druckzylinder, schräger Nagelstreifen
##   machine_pistol   Werbeblock: mintgrün, dicker Laufmantel, Stangenmagazin quer zur Seite
##   crossbow         Zielgerade: Holzschiene, türkise Wurfarme, Sehne, Bolzen mit Leuchtspitze
##   grenade_launcher Knalleffekt: dicke orange Trommel mit vier Kammern, kurzes dickes Rohr
##   flamethrower     Heiße Phase: lange Lanze mit Düse und Zündflamme, roter Tank darunter
##   beam             Rotlicht: weiß, roter Leuchtstab zwischen zwei Zinken, Ringe, Leuchtzelle
##   tesla            Kurzschluss: dunkelblau, Kupferspule mit leuchtender Kugel an der Spitze
##   lmg              Marathonsendung: oliv, Laufmantel, Zweibein, Munitionskasten mit Gurt
##   auto_shotgun     Zuschauerfrage: hellblau-weiß, dicker Lauf, große gelbe Trommel
## Jede Waffe hat einen Knoten "Muzzle" (Mündung): dort sitzt ihr Mündungsfeuer (Knoten "Flash",
## entsteht beim ersten Schuss und wird danach nur noch gezeigt und versteckt) und dort beginnt
## die Leuchtspur.
##
## Mündungsfeuer (FLASH_STYLES): je Waffenart ein eigenes Bild aus Kern, Stichflamme nach vorn,
## Stern quer zum Lauf und bei manchen Waffen seitlichen Flammen. Es steht nur wenige Bilder,
## dreht sich je Schuss zufällig und bleibt so klein, dass es die Bildmitte nie erreicht
## (FLASH_MAX_RADIUS). Ein einziges Licht (MuzzleLight) blitzt mit, es entsteht nie ein neues.
## Hülsen (SHELL_SCALES): Waffen mit Patronen werfen je Schuss eine kleine Hülse aus, höchstens
## SHELLS_PER_HAND je Hand zugleich, aus einem festen Vorrat von Knoten.

const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const Fx := preload("res://scripts/game/fx/fx.gd")

# --- Reine Optik ---
## Die Waffe ist in echter Größe gebaut und wird samt Abstand zur Kamera verkleinert. Im Bild
## sieht das gleich aus, sie ragt aber nie in eine Wand, vor der der Spieler steht.
const VIEW_SCALE: float = 0.3
const HAND_COUNT: int = 2
const REST_POSITION: Vector3 = Vector3(0.25, -0.235, -0.56)
const REST_YAW: float = 0.05
## Versatz bei zwei Waffen: etwas weiter außen und tiefer, damit die Bildmitte frei bleibt.
const AKIMBO_OFFSET: Vector3 = Vector3(0.035, -0.012, 0.0)
const WEAPON_OFFSETS: Dictionary = {
	"pistol": Vector3(-0.02, 0.01, 0.05),
	"revolver": Vector3(-0.02, 0.005, 0.05),
	"smg": Vector3(0.0, 0.0, 0.03),
	"sawed_off": Vector3(-0.01, 0.0, 0.06),
	"shotgun": Vector3(0.0, -0.02, 0.12),
	"rifle": Vector3(0.0, -0.02, 0.12),
	"sniper": Vector3(0.01, -0.045, 0.08),
	"minigun": Vector3(0.0, -0.05, -0.02),
	"rocket_launcher": Vector3(0.09, -0.03, 0.06),
	"burst_pistol": Vector3(-0.02, 0.005, 0.05),
	"nail_gun": Vector3(-0.015, 0.0, 0.05),
	"machine_pistol": Vector3(-0.01, 0.0, 0.04),
	"crossbow": Vector3(0.0, -0.005, 0.06),
	"grenade_launcher": Vector3(-0.005, -0.01, 0.06),
	"flamethrower": Vector3(0.0, -0.03, 0.1),
	"beam": Vector3(0.0, -0.03, 0.1),
	"tesla": Vector3(0.0, -0.03, 0.1),
	"lmg": Vector3(0.0, -0.03, 0.12),
	"auto_shotgun": Vector3(0.0, -0.02, 0.12),
}
## Rückstoß je Waffe: zurück (m), Mündung hoch (rad), Verdrehen (rad, zufällig), seitlich (m, zufällig).
const RECOIL: Dictionary = {
	"pistol": { "back": 0.06, "pitch": 0.2, "roll": 0.03, "side": 0.004 },
	"revolver": { "back": 0.09, "pitch": 0.36, "roll": 0.04, "side": 0.005 },
	"smg": { "back": 0.042, "pitch": 0.075, "roll": 0.05, "side": 0.008 },
	"sawed_off": { "back": 0.14, "pitch": 0.42, "roll": 0.06, "side": 0.008 },
	"shotgun": { "back": 0.16, "pitch": 0.34, "roll": 0.05, "side": 0.008 },
	"rifle": { "back": 0.05, "pitch": 0.075, "roll": 0.035, "side": 0.006 },
	"sniper": { "back": 0.2, "pitch": 0.3, "roll": 0.03, "side": 0.004 },
	"minigun": { "back": 0.024, "pitch": 0.022, "roll": 0.04, "side": 0.009 },
	"rocket_launcher": { "back": 0.2, "pitch": 0.22, "roll": 0.05, "side": 0.008 },
	"burst_pistol": { "back": 0.05, "pitch": 0.15, "roll": 0.035, "side": 0.005 },
	"nail_gun": { "back": 0.026, "pitch": 0.045, "roll": 0.035, "side": 0.006 },
	"machine_pistol": { "back": 0.036, "pitch": 0.065, "roll": 0.055, "side": 0.009 },
	"crossbow": { "back": 0.07, "pitch": 0.12, "roll": 0.03, "side": 0.004 },
	"grenade_launcher": { "back": 0.15, "pitch": 0.3, "roll": 0.05, "side": 0.008 },
	"flamethrower": { "back": 0.006, "pitch": 0.004, "roll": 0.02, "side": 0.004 },
	"beam": { "back": 0.004, "pitch": 0.003, "roll": 0.012, "side": 0.003 },
	"tesla": { "back": 0.08, "pitch": 0.12, "roll": 0.05, "side": 0.006 },
	"lmg": { "back": 0.046, "pitch": 0.06, "roll": 0.04, "side": 0.007 },
	"auto_shotgun": { "back": 0.12, "pitch": 0.22, "roll": 0.05, "side": 0.008 },
}
## Waffen ohne Mündungsfeuer: Flamme und Strahl haben ihr eigenes Bild, die Armbrust kein Pulver.
const NO_MUZZLE_FLASH: Array[String] = ["flamethrower", "beam", "crossbow"]
## Wie stark die Waffe beim Nachladen kippt (1 = wie die Pistole). Schwere Waffen kippen weniger.
const RELOAD_TILT: Dictionary = {
	"rifle": 0.45, "sniper": 0.4, "minigun": 0.3, "rocket_launcher": 0.4,
	"flamethrower": 0.4, "beam": 0.4, "tesla": 0.45, "lmg": 0.35, "auto_shotgun": 0.45,
}
## Bei zwei Waffen kippen beide weniger, damit sie sich in der Bildmitte nicht kreuzen.
const AKIMBO_RELOAD_TILT: float = 0.55
## Feder des Rückstoßes: straff, damit die Waffe hart zurückschlägt und schnell wieder steht.
const RECOIL_STIFFNESS: float = 300.0
const RECOIL_DAMPING: float = 23.0
## Mit dem Hochschlagen der Mündung hebt sich die Waffe um diesen Anteil (m je rad).
const RECOIL_HOP: float = 0.05
## Mündungsfeuer je Waffe. star: Durchmesser des Sterns quer zum Lauf, length: Länge der
## Stichflamme nach vorn, blades: gekreuzte Flächen des Sterns (2 = vier Strahlen), side: Länge
## der Flammen zur Seite (Mündungsbremse, 0 = keine), time: Dauer in Sekunden. Maße in Metern im
## Maß der Waffe. Waffen aus NO_MUZZLE_FLASH fehlen hier.
const FLASH_STYLES: Dictionary = {
	"pistol": { "star": 0.2, "length": 0.18, "blades": 2, "side": 0.0, "time": 0.05, "color": Color(1.0, 0.82, 0.3) },
	"revolver": { "star": 0.26, "length": 0.26, "blades": 3, "side": 0.08, "time": 0.065, "color": Color(1.0, 0.68, 0.25) },
	"smg": { "star": 0.19, "length": 0.22, "blades": 2, "side": 0.0, "time": 0.04, "color": Color(0.5, 0.95, 1.0) },
	"sawed_off": { "star": 0.28, "length": 0.2, "blades": 4, "side": 0.0, "time": 0.07, "color": Color(0.8, 1.0, 0.35) },
	"shotgun": { "star": 0.3, "length": 0.26, "blades": 4, "side": 0.0, "time": 0.07, "color": Color(1.0, 0.6, 0.2) },
	"rifle": { "star": 0.2, "length": 0.3, "blades": 3, "side": 0.0, "time": 0.045, "color": Color(0.6, 0.8, 1.0) },
	"sniper": { "star": 0.22, "length": 0.42, "blades": 2, "side": 0.1, "time": 0.075, "color": Color(0.95, 0.6, 1.0) },
	"minigun": { "star": 0.2, "length": 0.26, "blades": 3, "side": 0.0, "time": 0.035, "color": Color(1.0, 0.5, 0.8) },
	"rocket_launcher": { "star": 0.3, "length": 0.18, "blades": 4, "side": 0.0, "time": 0.09, "color": Color(1.0, 0.55, 0.15) },
	"burst_pistol": { "star": 0.19, "length": 0.18, "blades": 2, "side": 0.0, "time": 0.04, "color": Color(1.0, 0.65, 0.88) },
	"nail_gun": { "star": 0.13, "length": 0.1, "blades": 2, "side": 0.0, "time": 0.035, "color": Color(0.85, 0.92, 1.0) },
	"machine_pistol": { "star": 0.18, "length": 0.2, "blades": 2, "side": 0.0, "time": 0.035, "color": Color(0.65, 1.0, 0.6) },
	"grenade_launcher": { "star": 0.28, "length": 0.16, "blades": 4, "side": 0.0, "time": 0.08, "color": Color(1.0, 0.7, 0.2) },
	"tesla": { "star": 0.22, "length": 0.1, "blades": 4, "side": 0.0, "time": 0.07, "color": Color(0.4, 0.9, 1.0) },
	"lmg": { "star": 0.22, "length": 0.3, "blades": 3, "side": 0.08, "time": 0.045, "color": Color(1.0, 0.85, 0.5) },
	"auto_shotgun": { "star": 0.28, "length": 0.24, "blades": 4, "side": 0.0, "time": 0.06, "color": Color(0.4, 0.8, 1.0) },
}
## Das Mündungsfeuer beginnt mit FLASH_START mal seiner Größe, wächst bis FLASH_PEAK (nach dem
## Anteil FLASH_PEAK_AT seiner Dauer) und fällt dann zusammen. Kein Teil reicht weiter als
## FLASH_MAX_RADIUS von der Mündung zur Seite: So bleibt die Bildmitte (das Fadenkreuz) frei.
const FLASH_START: float = 0.6
const FLASH_PEAK: float = 1.1
const FLASH_PEAK_AT: float = 0.35
const FLASH_MAX_RADIUS: float = 0.16
## Deckkraft der Teile (alle leuchten addierend und liegen übereinander: zusammen hell, einzeln
## zurückhaltend, damit das Mündungsfeuer nicht zu einem weißen Fleck ausbrennt).
const FLASH_STAR_ALPHA: float = 0.62
const FLASH_CORE_ALPHA: float = 0.7
const FLASH_SPIKE_ALPHA: float = 0.45
const FLASH_LIGHT_ENERGY: float = 2.2
const FLASH_LIGHT_RANGE: float = 5.0
## Hülsen: Waffen, die welche auswerfen, mit ihrer Größe (1 = Pistolenhülse). Schrot wirft rote.
const SHELL_SCALES: Dictionary = {
	"pistol": 1.0, "smg": 1.0, "rifle": 1.25, "sniper": 1.6, "minigun": 1.1, "burst_pistol": 1.0,
	"machine_pistol": 1.0, "lmg": 1.25, "shotgun": 1.9, "auto_shotgun": 1.9,
}
const SHELL_RED: Array[String] = ["shotgun", "auto_shotgun"]
const SHELL_SIZE: Vector3 = Vector3(0.012, 0.012, 0.028)
## Vorrat je Hand: Die älteste Hülse wird wiederverwendet.
const SHELLS_PER_HAND: int = 6
const SHELL_LIFE: float = 0.42
const SHELL_GRAVITY: float = 9.0
const SHELL_SPIN: float = 22.0
## Der Auswurf sitzt rechts über dem Lauf, bei diesem Anteil des Wegs vom Griff zur Mündung.
const SHELL_PORT_SHARE: float = 0.2
const SHELL_PORT_OFFSET: Vector3 = Vector3(0.03, 0.012, 0.0)
const SWITCH_TIME: float = 0.28
const SWAY_GAIN: float = 0.011
const SWAY_MAX: float = 0.045
const BOB_FREQUENCY: float = 1.75
const BOB_AMOUNT: float = 0.011
const SLIDE_TRAVEL: float = 0.055
const SLIDE_TIME: float = 0.1
const PUMP_TRAVEL: float = 0.13
const BOLT_TRAVEL: float = 0.075
## Minigun: Drehung der Läufe je Schuss dazu (rad/s), Obergrenze und Abklingen (1/s).
const SPIN_PER_SHOT: float = 9.0
const SPIN_MAX: float = 34.0
const SPIN_DECAY: float = 2.4

const COLOR_STEEL: Color = Color(0.13, 0.13, 0.16)
const COLOR_YELLOW: Color = Color(1.0, 0.82, 0.1)
const COLOR_RED: Color = Color(0.85, 0.12, 0.14)
const COLOR_GOLD: Color = Color(1.0, 0.7, 0.2)
const COLOR_TEAL: Color = Color(0.1, 0.75, 0.8)
const COLOR_PINK: Color = Color(1.0, 0.2, 0.7)
const COLOR_SILVER: Color = Color(0.82, 0.84, 0.9)
const COLOR_WHITE: Color = Color(0.95, 0.95, 0.92)
const COLOR_PURPLE: Color = Color(0.55, 0.2, 0.9)
const COLOR_LIME: Color = Color(0.55, 0.95, 0.15)
const COLOR_BLUE: Color = Color(0.12, 0.35, 0.95)
const COLOR_ORANGE: Color = Color(1.0, 0.5, 0.08)
const COLOR_GREEN: Color = Color(0.1, 0.62, 0.25)
const COLOR_WOOD: Color = Color(0.55, 0.32, 0.14)
const COLOR_MINT: Color = Color(0.45, 0.95, 0.7)
const COLOR_NAVY: Color = Color(0.12, 0.16, 0.45)
const COLOR_COPPER: Color = Color(0.85, 0.45, 0.2)
const COLOR_CYAN: Color = Color(0.3, 0.9, 1.0)
const COLOR_OLIVE: Color = Color(0.42, 0.5, 0.16)
const COLOR_SKY: Color = Color(0.3, 0.72, 1.0)
const COLOR_SKIN: Color = Color(0.93, 0.72, 0.58)
const COLOR_SLEEVE: Color = Color(0.45, 0.2, 0.85)


## Gedämpfte Feder für eine Zahl: schnappt nach einem Stoß zurück auf 0.
class Spring:
	extends RefCounted
	var value: float = 0.0
	var velocity: float = 0.0

	func step(stiffness: float, damping: float, delta: float) -> void:
		# In kleinen Teilschritten, damit die Feder bei niedriger Bildrate nicht aufschaukelt.
		var left: float = delta
		while left > 0.0:
			var dt: float = minf(left, 1.0 / 120.0)
			velocity += (-stiffness * value - damping * velocity) * dt
			value += velocity * dt
			left -= dt

	func reset() -> void:
		value = 0.0
		velocity = 0.0


## Eine Hand: ihr Platz vor der Kamera, ihre Modelle und der Stand ihrer Bewegungen.
class HandSlot:
	extends RefCounted
	## Spiegelt die linke Waffe (scale.x = -1), wenn zwei Waffen gehalten werden.
	var side: Node3D = null
	var holder: Node3D = null
	## Gezeigte Waffe, "" = diese Hand ist leer.
	var weapon_id: String = ""
	var mirrored: bool = false
	## weapon_id -> Node3D (Modell der Waffe).
	var models: Dictionary = {}
	## weapon_id -> Node3D (Mündung).
	var muzzles: Dictionary = {}
	## "weapon_id/teil" -> Node3D (bewegliches Teil).
	var parts: Dictionary = {}
	## "weapon_id/teil" -> Vector3 (Ruheposition des Teils).
	var part_rest: Dictionary = {}
	var kick_back: Spring = Spring.new()
	var kick_pitch: Spring = Spring.new()
	var kick_roll: float = 0.0
	var kick_side: float = 0.0
	var fire_age: float = 10.0
	var switch_progress: float = 1.0
	var is_reloading: bool = false
	var reload_time: float = 0.0
	var reload_duration: float = 1.0
	## Schüsse seit dem Zeigen (dreht die Trommel des Revolvers weiter).
	var shots: int = 0
	## Drehung der Minigun-Läufe (Winkel und Tempo).
	var spin: float = 0.0
	var spin_speed: float = 0.0
	## Steckt eine Rakete im Rohr (Raketenwerfer) oder ein Bolzen auf der Schiene (Armbrust)?
	var rocket_loaded: bool = true
	## weapon_id -> Node3D (Mündungsfeuer an der Mündung, entsteht beim ersten Schuss).
	var flashes: Dictionary = {}
	## Restzeit und Dauer des laufenden Mündungsfeuers, seine Größe (Zufall je Schuss).
	var flash_left: float = 0.0
	var flash_time: float = 0.05
	var flash_size: float = 1.0
	## Vorrat der Hülsen dieser Hand (Knoten unter side) mit Ort, Tempo, Drehachse, Alter, Größe.
	## Ein Alter unter 0 heißt: Die Hülse ist nicht zu sehen.
	var shells: Array[MeshInstance3D] = []
	var shell_pos: PackedVector3Array = PackedVector3Array()
	var shell_vel: PackedVector3Array = PackedVector3Array()
	var shell_axis: PackedVector3Array = PackedVector3Array()
	var shell_age: PackedFloat32Array = PackedFloat32Array()
	var shell_scale: PackedFloat32Array = PackedFloat32Array()
	var shell_next: int = 0
	var shells_live: int = 0

	func reset_motion() -> void:
		kick_back.reset()
		kick_pitch.reset()
		kick_roll = 0.0
		kick_side = 0.0
		fire_age = 10.0
		is_reloading = false
		reload_time = 0.0
		shots = 0
		spin_speed = 0.0
		rocket_loaded = true
		flash_left = 0.0


## Waffe in der linken Hand (bei einer einzelnen Waffe: diese Waffe).
var weapon_id: String = WeaponDefs.START_WEAPON

var _rig: Node3D
var _slots: Array[HandSlot] = []
var _akimbo: bool = false
var _materials: Dictionary = {}

var _sway: Vector2 = Vector2.ZERO
var _last_basis: Basis = Basis.IDENTITY
var _has_last_basis: bool = false
var _bob_phase: float = 0.0
var _bob_weight: float = 0.0
var _fall_offset: float = 0.0
var _time: float = 0.0
## Das eine Licht des Mündungsfeuers (für beide Hände) mit Restzeit und Dauer.
var _muzzle_light: OmniLight3D
var _light_left: float = 0.0
var _light_time: float = 0.05
var _shell_mesh: BoxMesh = null


func _init() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	_rig.scale = Vector3.ONE * VIEW_SCALE
	add_child(_rig)
	for index: int in HAND_COUNT:
		var slot: HandSlot = HandSlot.new()
		slot.side = Node3D.new()
		slot.side.name = "Hand%d" % index
		_rig.add_child(slot.side)
		slot.holder = Node3D.new()
		slot.holder.name = "Holder"
		slot.holder.position = REST_POSITION
		slot.side.add_child(slot.holder)
		_slots.append(slot)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.name = "MuzzleLight"
	_muzzle_light.omni_range = FLASH_LIGHT_RANGE
	_muzzle_light.shadow_enabled = false
	_muzzle_light.visible = false
	add_child(_muzzle_light)
	set_weapon(weapon_id)
	for slot: HandSlot in _slots:
		slot.switch_progress = 1.0
		_apply_pose(slot)


func _ready() -> void:
	Events.hand_reload_started.connect(_on_hand_reload_started)
	Events.hand_reload_finished.connect(_on_hand_reload_finished)
	Events.player_died.connect(_on_player_died)
	Events.run_started.connect(_on_run_started)


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	_time += dt
	_update_sway(dt)
	_update_bob(dt)
	var settle: float = 1.0 - exp(-14.0 * dt)
	for slot: HandSlot in _slots:
		if slot.weapon_id.is_empty():
			continue
		slot.fire_age += dt
		slot.kick_back.step(RECOIL_STIFFNESS, RECOIL_DAMPING, dt)
		slot.kick_pitch.step(RECOIL_STIFFNESS, RECOIL_DAMPING, dt)
		slot.kick_roll = lerpf(slot.kick_roll, 0.0, settle)
		slot.kick_side = lerpf(slot.kick_side, 0.0, settle)
		slot.switch_progress = minf(1.0, slot.switch_progress + dt / SWITCH_TIME)
		slot.spin_speed = lerpf(slot.spin_speed, 0.0, 1.0 - exp(-SPIN_DECAY * dt))
		slot.spin = fposmod(slot.spin + slot.spin_speed * dt, TAU)
		if slot.is_reloading:
			slot.reload_time += dt
			if slot.reload_time >= slot.reload_duration:
				slot.is_reloading = false
				slot.rocket_loaded = true
		_apply_pose(slot)
		if slot.flash_left > 0.0:
			_update_flash(slot, dt)
	for slot: HandSlot in _slots:
		if slot.shells_live > 0:
			_update_shells(slot, dt)
	if _light_left > 0.0:
		_light_left -= dt
		if _light_left <= 0.0:
			_muzzle_light.visible = false
		else:
			_muzzle_light.light_energy = FLASH_LIGHT_ENERGY * _light_left / _light_time


# --- Öffentliche Schnittstelle ---------------------------------------------------------------


## Zeigt die gehaltenen Waffen. hands: je Hand ein Eintrag aus WeaponController.get_hands()
## (gelesen werden "id", "reloading", "reload_left", "reload_duration") oder nur die Waffen-ID.
## Eine Waffe: rechts wie bisher. Zwei Waffen: Hand 0 gespiegelt links, Hand 1 rechts. Eine neu
## gezeigte Waffe kommt von unten hoch. Unbekannte IDs werden übergangen.
func set_loadout(hands: Array) -> void:
	var ids: Array[String] = []
	var entries: Array[Dictionary] = []
	for value: Variant in hands:
		var entry: Dictionary = value if value is Dictionary else {"id": str(value)}
		var id: String = str(entry.get("id", ""))
		if WeaponDefs.has(id) and ids.size() < HAND_COUNT:
			ids.append(id)
			entries.append(entry)
	if ids.is_empty():
		return
	_akimbo = ids.size() > 1
	weapon_id = ids[0]
	for index: int in HAND_COUNT:
		var slot: HandSlot = _slots[index]
		var id: String = ids[index] if index < ids.size() else ""
		var mirrored: bool = _akimbo and index == 0
		if id != slot.weapon_id or mirrored != slot.mirrored:
			_show_weapon(slot, id, mirrored)
		if id.is_empty():
			continue
		var entry: Dictionary = entries[index]
		if entry.has("reloading"):
			# Laufendes Nachladen übernehmen (die Waffe kann die Hand gewechselt haben).
			slot.is_reloading = bool(entry["reloading"])
			if slot.is_reloading:
				slot.reload_duration = maxf(float(entry.get("reload_duration", 1.0)), 0.05)
				slot.reload_time = clampf(slot.reload_duration - float(entry.get("reload_left", 0.0)), 0.0, slot.reload_duration)
		_apply_pose(slot)


## Zeigt genau eine Waffe (rechts). Unbekannte IDs zeigen nichts Neues.
func set_weapon(new_weapon_id: String) -> void:
	set_loadout([new_weapon_id])


## IDs der gezeigten Waffen in Reihenfolge der Hände.
func get_hand_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot: HandSlot in _slots:
		if not slot.weapon_id.is_empty():
			ids.append(slot.weapon_id)
	return ids


## Ein Schuss dieser Hand: Rückstoß, Mündungsfeuer und Hülse.
func play_fire(hand: int = 0) -> void:
	var slot: HandSlot = _slot(hand)
	if slot == null:
		return
	var recoil: Dictionary = RECOIL.get(slot.weapon_id, {})
	if recoil.is_empty():
		return
	slot.fire_age = 0.0
	slot.shots += 1
	slot.kick_back.value = minf(slot.kick_back.value + float(recoil["back"]), float(recoil["back"]) * 1.6)
	slot.kick_pitch.value = minf(slot.kick_pitch.value + float(recoil["pitch"]), float(recoil["pitch"]) * 1.6)
	slot.kick_roll = randf_range(-1.0, 1.0) * float(recoil["roll"])
	slot.kick_side = randf_range(-1.0, 1.0) * float(recoil["side"])
	slot.spin_speed = minf(slot.spin_speed + SPIN_PER_SHOT, SPIN_MAX)
	if slot.weapon_id == "rocket_launcher" or slot.weapon_id == "crossbow":
		slot.rocket_loaded = false
	_apply_pose(slot)
	if FLASH_STYLES.has(slot.weapon_id) and not NO_MUZZLE_FLASH.has(slot.weapon_id):
		_start_flash(slot)
	if SHELL_SCALES.has(slot.weapon_id):
		_eject_shell(slot)


## Weltposition der Mündung dieser Hand: Startpunkt der Leuchtspur und Ort des Mündungsfeuers.
func get_muzzle_position(hand: int = 0) -> Vector3:
	if not is_inside_tree():
		return position
	var muzzle: Node3D = get_muzzle_node(hand)
	if muzzle == null:
		return global_position
	return muzzle.global_position


## Knoten der Mündung der Waffe in dieser Hand, null wenn die Hand leer ist.
func get_muzzle_node(hand: int = 0) -> Node3D:
	var slot: HandSlot = _slot(hand)
	if slot == null:
		return null
	return slot.muzzles.get(slot.weapon_id, null) as Node3D


## Knoten des Mündungsfeuers der Waffe in dieser Hand. null, solange sie noch nie geschossen hat
## oder kein Mündungsfeuer hat.
func get_flash_node(hand: int = 0) -> Node3D:
	var slot: HandSlot = _slot(hand)
	if slot == null:
		return null
	return slot.flashes.get(slot.weapon_id, null) as Node3D


## Ist an der Mündung dieser Hand gerade Mündungsfeuer zu sehen?
func is_flash_visible(hand: int = 0) -> bool:
	var flash: Node3D = get_flash_node(hand)
	return flash != null and flash.visible


## Größter Abstand, den ein Teil des Mündungsfeuers dieser Waffe quer zum Lauf von der Mündung
## hat (im Maß der Waffe, also vor VIEW_SCALE). 0 ohne Mündungsfeuer.
func flash_radius(id: String) -> float:
	if not FLASH_STYLES.has(id) or NO_MUZZLE_FLASH.has(id):
		return 0.0
	var style: Dictionary = FLASH_STYLES[id]
	return minf(FLASH_MAX_RADIUS, maxf(float(style["star"]) * 0.5, float(style["side"])) * FLASH_PEAK)


## Zahl der Hülsen dieser Hand, die gerade fliegen.
func live_shell_count(hand: int = 0) -> int:
	if hand < 0 or hand >= _slots.size():
		return 0
	return _slots[hand].shells_live


## Das Licht des Mündungsfeuers (eines für alle Schüsse).
func get_muzzle_light() -> OmniLight3D:
	return _muzzle_light


# --- Signale ---------------------------------------------------------------------------------


func _on_hand_reload_started(hand: int, duration: float) -> void:
	var slot: HandSlot = _slot(hand)
	if slot == null:
		return
	slot.is_reloading = true
	slot.reload_time = 0.0
	slot.reload_duration = maxf(duration, 0.05)


func _on_hand_reload_finished(hand: int) -> void:
	var slot: HandSlot = _slot(hand)
	if slot == null:
		return
	slot.is_reloading = false
	slot.rocket_loaded = true


func _on_player_died() -> void:
	_rig.visible = false


func _on_run_started() -> void:
	_rig.visible = true


## Die Hand mit diesem Index, null wenn es sie nicht gibt oder sie leer ist.
func _slot(hand: int) -> HandSlot:
	if hand < 0 or hand >= _slots.size() or _slots[hand].weapon_id.is_empty():
		return null
	return _slots[hand]


## Zeigt in dieser Hand das Modell der Waffe ("" = nichts) und beginnt die Wechsel-Bewegung.
func _show_weapon(slot: HandSlot, id: String, mirrored: bool) -> void:
	slot.weapon_id = id
	slot.mirrored = mirrored
	slot.side.scale = Vector3(-1.0 if mirrored else 1.0, 1.0, 1.0)
	slot.side.visible = not id.is_empty()
	if not id.is_empty() and not slot.models.has(id):
		_build_model(slot, id)
	for model_id: String in slot.models.keys():
		(slot.models[model_id] as Node3D).visible = model_id == id
	for flash: Node3D in slot.flashes.values():
		flash.visible = false
	_hide_shells(slot)
	slot.reset_motion()
	slot.switch_progress = 0.0


# --- Mündungsfeuer und Hülsen ----------------------------------------------------------------


## Zündet das Mündungsfeuer dieser Hand: Der Knoten an der Mündung entsteht beim ersten Schuss
## und wird danach nur gezeigt. Je Schuss zufällig gedreht und etwas anders groß.
func _start_flash(slot: HandSlot) -> void:
	var id: String = slot.weapon_id
	var muzzle: Node3D = slot.muzzles.get(id, null) as Node3D
	if muzzle == null:
		return
	var style: Dictionary = FLASH_STYLES[id]
	var flash: Node3D = slot.flashes.get(id, null) as Node3D
	if flash == null:
		flash = _build_flash(style)
		muzzle.add_child(flash)
		slot.flashes[id] = flash
	slot.flash_time = float(style["time"])
	slot.flash_left = slot.flash_time
	slot.flash_size = randf_range(0.85, 1.0)
	(flash.get_node("Star") as Node3D).rotation.z = randf() * TAU
	flash.scale = Vector3.ONE * slot.flash_size * FLASH_START
	flash.visible = true
	_light_time = slot.flash_time
	_light_left = _light_time
	_muzzle_light.light_color = (style["color"] as Color).lerp(Color.WHITE, 0.3)
	_muzzle_light.light_energy = FLASH_LIGHT_ENERGY
	_muzzle_light.visible = true
	if is_inside_tree():
		_muzzle_light.global_position = muzzle.global_position


func _update_flash(slot: HandSlot, dt: float) -> void:
	var flash: Node3D = slot.flashes.get(slot.weapon_id, null) as Node3D
	slot.flash_left -= dt
	if flash == null:
		slot.flash_left = 0.0
		return
	if slot.flash_left <= 0.0:
		flash.visible = false
		return
	var k: float = 1.0 - slot.flash_left / slot.flash_time
	var size: float = lerpf(FLASH_START, FLASH_PEAK, k / FLASH_PEAK_AT) if k < FLASH_PEAK_AT \
		else lerpf(FLASH_PEAK, 0.1, (k - FLASH_PEAK_AT) / (1.0 - FLASH_PEAK_AT))
	flash.scale = Vector3.ONE * slot.flash_size * size


## Baut das Mündungsfeuer einer Waffenart: Kern, Stichflamme nach vorn (-Z), Stern quer zum Lauf
## und, wenn die Art es will, Flammen nach links und rechts. Die Materialien sind die
## Leuchtmaterialien aus fx.gd (keine neue Art).
func _build_flash(style: Dictionary) -> Node3D:
	var star_size: float = minf(float(style["star"]), FLASH_MAX_RADIUS * 2.0 / FLASH_PEAK)
	var length: float = float(style["length"])
	var side: float = minf(float(style["side"]), FLASH_MAX_RADIUS / FLASH_PEAK)
	var color: Color = style["color"]
	var hot: StandardMaterial3D = Fx.glow_material(Color(color.r, color.g, color.b, FLASH_STAR_ALPHA))
	var white: StandardMaterial3D = Fx.glow_material(Color(1.0, 1.0, 0.92, FLASH_CORE_ALPHA))
	var pale: Color = color.lerp(Color.WHITE, 0.4)
	var tongue: StandardMaterial3D = Fx.glow_material(Color(pale.r, pale.g, pale.b, FLASH_SPIKE_ALPHA))
	var flash: Node3D = Node3D.new()
	flash.name = "Flash"
	flash.visible = false
	var core: MeshInstance3D = _ball(flash, 0.5, Vector3.ZERO, white)
	core.name = "Core"
	core.scale = Vector3.ONE * star_size * 0.34
	var spike: MeshInstance3D = _ball(flash, 0.5, Vector3(0.0, 0.0, -length * 0.42), tongue)
	spike.name = "Spike"
	spike.scale = Vector3(star_size * 0.24, star_size * 0.24, length)
	var star: Node3D = Node3D.new()
	star.name = "Star"
	flash.add_child(star)
	var blades: int = maxi(1, int(style["blades"]))
	for i: int in blades:
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(star_size, star_size * 0.26)
		var blade: MeshInstance3D = _mesh_instance(star, quad, Vector3.ZERO, hot)
		blade.rotation.z = PI * float(i) / float(blades)
	if side > 0.0:
		for direction: float in [-1.0, 1.0]:
			var jet: MeshInstance3D = _ball(flash, 0.5, Vector3(direction * side * 0.5, 0.0, 0.0), tongue)
			jet.name = "SideLeft" if direction < 0.0 else "SideRight"
			jet.scale = Vector3(side, star_size * 0.22, star_size * 0.22)
	return flash


## Wirft eine Hülse aus: nach rechts oben (bei der gespiegelten linken Waffe nach links oben),
## leicht nach hinten. Die Hülsen liegen im Raum der Hand, nicht der Waffe: Der Rückstoß nimmt
## sie nicht mit.
func _eject_shell(slot: HandSlot) -> void:
	var id: String = slot.weapon_id
	var muzzle: Node3D = slot.muzzles.get(id, null) as Node3D
	var gun: Node3D = slot.models.get(id, null) as Node3D
	if muzzle == null or gun == null:
		return
	if slot.shells.is_empty():
		_build_shells(slot)
	var index: int = slot.shell_next
	slot.shell_next = (index + 1) % SHELLS_PER_HAND
	var port: Vector3 = Vector3(SHELL_PORT_OFFSET.x, muzzle.position.y + SHELL_PORT_OFFSET.y, muzzle.position.z * SHELL_PORT_SHARE)
	var node: MeshInstance3D = slot.shells[index]
	if slot.shell_age[index] < 0.0:
		slot.shells_live += 1
	slot.shell_pos[index] = slot.holder.transform * (gun.transform * port)
	slot.shell_vel[index] = Vector3(randf_range(1.1, 1.8), randf_range(0.9, 1.6), randf_range(0.1, 0.6))
	slot.shell_axis[index] = Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)).normalized()
	slot.shell_age[index] = 0.0
	slot.shell_scale[index] = float(SHELL_SCALES[id])
	node.material_override = _material(COLOR_RED, 0.5, 0.2) if SHELL_RED.has(id) else _material(COLOR_GOLD, 0.6, 0.7)
	node.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * slot.shell_scale[index]), slot.shell_pos[index])
	node.visible = true


func _update_shells(slot: HandSlot, dt: float) -> void:
	for index: int in slot.shells.size():
		var age: float = slot.shell_age[index]
		if age < 0.0:
			continue
		age += dt
		var node: MeshInstance3D = slot.shells[index]
		if age >= SHELL_LIFE:
			node.visible = false
			slot.shell_age[index] = -1.0
			slot.shells_live -= 1
			continue
		slot.shell_age[index] = age
		var velocity: Vector3 = slot.shell_vel[index]
		velocity.y -= SHELL_GRAVITY * dt
		slot.shell_vel[index] = velocity
		var pos: Vector3 = slot.shell_pos[index] + velocity * dt
		slot.shell_pos[index] = pos
		node.transform = Transform3D(Basis(slot.shell_axis[index], age * SHELL_SPIN).scaled(Vector3.ONE * slot.shell_scale[index]), pos)


## Legt den Vorrat der Hülsen dieser Hand an (einmal, beim ersten Auswurf).
func _build_shells(slot: HandSlot) -> void:
	if _shell_mesh == null:
		_shell_mesh = BoxMesh.new()
		_shell_mesh.size = SHELL_SIZE
	slot.shell_pos.resize(SHELLS_PER_HAND)
	slot.shell_vel.resize(SHELLS_PER_HAND)
	slot.shell_axis.resize(SHELLS_PER_HAND)
	slot.shell_age.resize(SHELLS_PER_HAND)
	slot.shell_scale.resize(SHELLS_PER_HAND)
	for index: int in SHELLS_PER_HAND:
		var node: MeshInstance3D = _mesh_instance(slot.side, _shell_mesh, Vector3.ZERO, _material(COLOR_GOLD, 0.6, 0.7))
		node.name = "Shell%d" % index
		node.visible = false
		slot.shells.append(node)
		slot.shell_age[index] = -1.0


func _hide_shells(slot: HandSlot) -> void:
	for index: int in slot.shells.size():
		slot.shells[index].visible = false
		slot.shell_age[index] = -1.0
	slot.shells_live = 0


# --- Bewegung --------------------------------------------------------------------------------


## Die Waffe hängt der Kameradrehung leicht nach.
func _update_sway(dt: float) -> void:
	if not is_inside_tree():
		return
	var now: Basis = global_transform.basis.orthonormalized()
	var target: Vector2 = Vector2.ZERO
	if _has_last_basis and dt > 0.0001:
		var forward: Vector3 = _last_basis.inverse() * (-now.z)
		target = Vector2(-forward.x, -forward.y) / dt * SWAY_GAIN
		target = target.limit_length(SWAY_MAX)
	_last_basis = now
	_has_last_basis = true
	_sway = _sway.lerp(target, 1.0 - exp(-12.0 * dt))


## Die Waffe wippt beim Laufen und sackt bei Sprung und Landung leicht nach.
func _update_bob(dt: float) -> void:
	var body: CharacterBody3D = null
	var camera: Node = get_parent()
	if camera != null:
		body = camera.get_parent() as CharacterBody3D
	var flat_speed: float = 0.0
	var fall_target: float = 0.0
	var target_weight: float = 0.0
	if body != null and body.is_inside_tree():
		flat_speed = Vector2(body.velocity.x, body.velocity.z).length()
		if body.is_on_floor():
			target_weight = clampf(flat_speed / 5.0, 0.0, 1.4)
		else:
			fall_target = clampf(-body.velocity.y * 0.007, -0.035, 0.035)
	_bob_weight = lerpf(_bob_weight, target_weight, 1.0 - exp(-10.0 * dt))
	_bob_phase = fposmod(_bob_phase + flat_speed * BOB_FREQUENCY * dt, TAU)
	_fall_offset = lerpf(_fall_offset, fall_target, 1.0 - exp(-9.0 * dt))


## Setzt die Haltung einer Hand aus Ruhelage, Wechsel, Nachladen, Rückstoß, Nachhängen und
## Wippen zusammen. Die gespiegelte Hand rechnet seitliche Bewegungen umgekehrt, damit beide
## Waffen im Bild in dieselbe Richtung schwingen.
func _apply_pose(slot: HandSlot) -> void:
	var id: String = slot.weapon_id
	if id.is_empty():
		return
	var facing: float = -1.0 if slot.mirrored else 1.0
	var offset: Vector3 = WEAPON_OFFSETS.get(id, Vector3.ZERO)
	var pos: Vector3 = REST_POSITION + offset
	if _akimbo:
		pos += AKIMBO_OFFSET
	var rot: Vector3 = Vector3(0.0, REST_YAW, 0.0)
	# Wechsel: die Waffe kommt von unten hoch.
	var lowered: float = 1.0 - _ease_out(slot.switch_progress)
	pos.y -= 0.34 * lowered
	rot.x -= 0.95 * lowered
	# Nachladen: Mündung hoch und zur Mitte, Unterseite (Magazin) dreht sich ins Bild.
	var reload_progress: float = 0.0
	if slot.is_reloading:
		reload_progress = clampf(slot.reload_time / slot.reload_duration, 0.0, 1.0)
		var tilt: float = smoothstep(0.0, 0.16, reload_progress) * (1.0 - smoothstep(0.84, 1.0, reload_progress))
		tilt *= float(RELOAD_TILT.get(id, 1.0))
		if _akimbo:
			tilt *= AKIMBO_RELOAD_TILT
		pos += Vector3(-0.06, -0.03, 0.03) * tilt
		rot += Vector3(0.38, 0.3, -0.7) * tilt
	# Rückstoß.
	pos.z += slot.kick_back.value
	pos.x += slot.kick_side
	pos.y += slot.kick_pitch.value * RECOIL_HOP
	rot.x += slot.kick_pitch.value
	rot.z += slot.kick_roll
	# Nachhängen und Wippen.
	pos.x += (_sway.x + cos(_bob_phase) * BOB_AMOUNT * _bob_weight) * facing
	pos.y += _sway.y + _fall_offset - absf(sin(_bob_phase)) * BOB_AMOUNT * _bob_weight
	pos.y += sin(_time * 1.6) * 0.0025
	rot.y -= _sway.x * 1.5 * facing
	rot.x += _sway.y * 1.5
	rot.z += -_sway.x * 2.0 * facing
	match id:
		"pistol":
			_pose_pistol(slot, reload_progress)
		"revolver":
			_pose_revolver(slot, reload_progress)
		"smg":
			pos.y += _pose_magazine(slot, "smg/mag", reload_progress, 0.42)
		"sawed_off":
			_pose_sawed_off(slot, reload_progress)
		"shotgun":
			pos.y += _pose_shotgun(slot, reload_progress)
		"rifle":
			pos.y += _pose_magazine(slot, "rifle/mag", reload_progress, 0.4)
		"sniper":
			pos.y += _pose_sniper(slot, reload_progress)
		"minigun":
			_pose_minigun(slot, reload_progress)
		"rocket_launcher":
			_pose_rocket_launcher(slot, reload_progress)
		"burst_pistol":
			_pose_pistol(slot, reload_progress, "burst_pistol")
		"nail_gun":
			pos.y += _pose_magazine(slot, "nail_gun/mag", reload_progress, 0.3)
		"machine_pistol":
			pos.y += _pose_magazine(slot, "machine_pistol/mag", reload_progress, 0.42)
		"crossbow":
			_pose_crossbow(slot, reload_progress)
		"grenade_launcher":
			_pose_grenade_launcher(slot, reload_progress)
		"flamethrower":
			pos.y += _pose_magazine(slot, "flamethrower/tank", reload_progress, 0.36)
		"beam":
			_pose_cell(slot, "beam/cell", reload_progress, Vector3(0.0, 0.16, 0.06))
		"tesla":
			pos.y += _pose_magazine(slot, "tesla/cell", reload_progress, 0.3)
		"lmg":
			pos.y += _pose_magazine(slot, "lmg/box", reload_progress, 0.4)
		"auto_shotgun":
			pos.y += _pose_magazine(slot, "auto_shotgun/drum", reload_progress, 0.42)
	slot.holder.position = pos
	slot.holder.rotation = rot


## Pistole: Schlitten schnellt beim Schuss zurück, Magazin fällt beim Nachladen heraus.
## prefix nennt die Waffe, deren Teile "<prefix>/slide" und "<prefix>/mag" bewegt werden.
func _pose_pistol(slot: HandSlot, reload_progress: float, prefix: String = "pistol") -> void:
	var slide: float = maxf(0.0, 1.0 - slot.fire_age / SLIDE_TIME)
	var mag_drop: float = 0.0
	if slot.is_reloading:
		mag_drop = _window(reload_progress, 0.16, 0.3, 0.5, 0.68)
		slide = maxf(slide, _window(reload_progress, 0.76, 0.84, 0.88, 0.95))
	_set_part(slot, prefix + "/slide", Vector3(0.0, 0.0, SLIDE_TRAVEL * slide))
	_set_part(slot, prefix + "/mag", Vector3(0.0, -0.24 * mag_drop, 0.05 * mag_drop))


## Revolver: Die Trommel dreht sich je Schuss ein Sechstel weiter. Beim Nachladen schwenkt sie
## seitlich heraus und dreht durch, der Hahn spannt nach jedem Schuss.
func _pose_revolver(slot: HandSlot, reload_progress: float) -> void:
	var step: float = clampf(slot.fire_age / 0.18, 0.0, 1.0)
	var angle: float = (float(slot.shots) - 1.0 + _ease_out(step)) * TAU / 6.0
	var swing: float = 0.0
	if slot.is_reloading:
		swing = _window(reload_progress, 0.14, 0.28, 0.7, 0.84)
		angle += reload_progress * TAU * 2.0
	_set_part(slot, "revolver/drum", Vector3(-0.075 * swing, -0.02 * swing, 0.0))
	var drum: Node3D = slot.parts.get("revolver/drum", null) as Node3D
	if drum != null:
		drum.rotation.z = angle
	var hammer: Node3D = slot.parts.get("revolver/hammer", null) as Node3D
	if hammer != null:
		hammer.rotation.x = 0.7 * _window(slot.fire_age, 0.0, 0.03, 0.1, 0.3)


## Waffen mit Stangenmagazin (MP, Sturmgewehr): Das Magazin fällt beim Nachladen und wird wieder
## eingeschlagen. Gibt einen Versatz der Waffe nach oben zurück.
func _pose_magazine(slot: HandSlot, key: String, reload_progress: float, drop_distance: float) -> float:
	var mag_drop: float = 0.0
	var bump: float = 0.0
	if slot.is_reloading:
		mag_drop = _window(reload_progress, 0.14, 0.3, 0.48, 0.66)
		bump = 0.025 * _window(reload_progress, 0.64, 0.69, 0.71, 0.8)
	_set_part(slot, key, Vector3(0.0, -drop_distance * mag_drop, 0.04 * mag_drop))
	return bump


## Abgesägte Schrotflinte: Die Läufe kippen zum Nachladen nach unten ab.
func _pose_sawed_off(slot: HandSlot, reload_progress: float) -> void:
	var open: float = 0.0
	if slot.is_reloading:
		open = _window(reload_progress, 0.12, 0.26, 0.7, 0.86)
	var barrels: Node3D = slot.parts.get("sawed_off/barrels", null) as Node3D
	if barrels != null:
		barrels.rotation.x = -0.75 * open


## Schrotflinte: Durchladen nach jedem Schuss, Patronen nachschieben beim Nachladen.
## Gibt einen Versatz der Waffe nach oben zurück.
func _pose_shotgun(slot: HandSlot, reload_progress: float) -> float:
	var pump: float = _window(slot.fire_age, 0.16, 0.3, 0.36, 0.52)
	var bump: float = -0.012 * pump
	if slot.is_reloading:
		pump = maxf(pump, _window(reload_progress, 0.8, 0.87, 0.9, 0.97))
		if reload_progress > 0.16 and reload_progress < 0.78:
			var shells: float = (reload_progress - 0.16) / 0.62 * 4.0
			bump += 0.02 * absf(sin(shells * PI))
	_set_part(slot, "shotgun/pump", Vector3(0.0, 0.0, PUMP_TRAVEL * pump))
	return bump


## Scharfschützengewehr: Der Kammerstängel fährt nach jedem Schuss zurück und wieder vor, beim
## Nachladen fällt das kurze Magazin. Gibt einen Versatz der Waffe nach oben zurück.
func _pose_sniper(slot: HandSlot, reload_progress: float) -> float:
	var bolt: float = _window(slot.fire_age, 0.25, 0.45, 0.6, 0.85)
	var mag_drop: float = 0.0
	if slot.is_reloading:
		mag_drop = _window(reload_progress, 0.14, 0.3, 0.5, 0.68)
		bolt = maxf(bolt, _window(reload_progress, 0.72, 0.8, 0.86, 0.95))
	_set_part(slot, "sniper/bolt", Vector3(0.0, 0.0, BOLT_TRAVEL * bolt))
	_set_part(slot, "sniper/mag", Vector3(0.0, -0.3 * mag_drop, 0.03 * mag_drop))
	return -0.008 * bolt


## Minigun: Die Läufe drehen sich, solange geschossen wird, und laufen aus. Beim Nachladen wird
## der Munitionskasten getauscht.
func _pose_minigun(slot: HandSlot, reload_progress: float) -> void:
	var barrels: Node3D = slot.parts.get("minigun/barrels", null) as Node3D
	if barrels != null:
		barrels.rotation.z = slot.spin
	var box_drop: float = 0.0
	if slot.is_reloading:
		box_drop = _window(reload_progress, 0.12, 0.3, 0.6, 0.8)
	_set_part(slot, "minigun/box", Vector3(0.0, -0.4 * box_drop, 0.03 * box_drop))


## Raketenwerfer: Nach dem Schuss ist das Rohr leer, beim Nachladen schiebt sich die neue Rakete
## von vorn hinein.
func _pose_rocket_launcher(slot: HandSlot, reload_progress: float) -> void:
	var rocket: Node3D = slot.parts.get("rocket_launcher/rocket", null) as Node3D
	if rocket == null:
		return
	if slot.is_reloading:
		var slide_in: float = smoothstep(0.5, 0.82, reload_progress)
		rocket.visible = reload_progress > 0.5
		_set_part(slot, "rocket_launcher/rocket", Vector3(0.0, 0.0, -0.35 * (1.0 - slide_in)))
		return
	rocket.visible = slot.rocket_loaded
	_set_part(slot, "rocket_launcher/rocket", Vector3.ZERO)


## Armbrust: Nach dem Schuss ist die Schiene leer und die Sehne entspannt. Beim Nachladen wird
## die Sehne gespannt, dann schiebt sich der neue Bolzen von hinten auf die Schiene.
func _pose_crossbow(slot: HandSlot, reload_progress: float) -> void:
	var bolt: Node3D = slot.parts.get("crossbow/bolt", null) as Node3D
	var drawn: Node3D = slot.parts.get("crossbow/string", null) as Node3D
	var loose: Node3D = slot.parts.get("crossbow/string_loose", null) as Node3D
	if bolt == null or drawn == null or loose == null:
		return
	var cocked: bool = slot.rocket_loaded
	var bolt_shown: bool = slot.rocket_loaded
	var slide_in: float = 1.0
	if slot.is_reloading:
		cocked = reload_progress > 0.35
		bolt_shown = reload_progress > 0.5
		slide_in = smoothstep(0.5, 0.8, reload_progress)
	drawn.visible = cocked
	loose.visible = not cocked
	bolt.visible = bolt_shown
	_set_part(slot, "crossbow/bolt", Vector3(0.0, 0.03 * (1.0 - slide_in), 0.2 * (1.0 - slide_in)))


## Granatwerfer: Die Trommel dreht sich je Schuss eine Kammer weiter. Beim Nachladen schwenkt sie
## zur Seite heraus und dreht durch.
func _pose_grenade_launcher(slot: HandSlot, reload_progress: float) -> void:
	var step: float = clampf(slot.fire_age / 0.22, 0.0, 1.0)
	var angle: float = (float(slot.shots) - 1.0 + _ease_out(step)) * TAU / 4.0
	var swing: float = 0.0
	if slot.is_reloading:
		swing = _window(reload_progress, 0.12, 0.26, 0.72, 0.86)
		angle += reload_progress * TAU
	_set_part(slot, "grenade_launcher/drum", Vector3(-0.1 * swing, -0.03 * swing, 0.0))
	var drum: Node3D = slot.parts.get("grenade_launcher/drum", null) as Node3D
	if drum != null:
		drum.rotation.z = angle


## Waffen mit einer Zelle, die beim Nachladen um travel aus der Waffe fährt und wieder einrastet
## (Rotlicht: die Leuchtzelle oben).
func _pose_cell(slot: HandSlot, key: String, reload_progress: float, travel: Vector3) -> void:
	var out: float = 0.0
	if slot.is_reloading:
		out = _window(reload_progress, 0.14, 0.3, 0.5, 0.68)
	_set_part(slot, key, travel * out)


## Verschiebt ein bewegliches Teil um offset aus seiner Ruhelage.
func _set_part(slot: HandSlot, key: String, offset: Vector3) -> void:
	var part: Node3D = slot.parts.get(key, null) as Node3D
	if part == null:
		return
	var rest: Vector3 = slot.part_rest.get(key, Vector3.ZERO)
	part.position = rest + offset


## 0 → 1 zwischen rise_from und rise_to, bleibt 1, 1 → 0 zwischen fall_from und fall_to.
func _window(x: float, rise_from: float, rise_to: float, fall_from: float, fall_to: float) -> float:
	return smoothstep(rise_from, rise_to, x) * (1.0 - smoothstep(fall_from, fall_to, x))


func _ease_out(x: float) -> float:
	var inverse: float = 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - inverse * inverse * inverse


# --- Aufbau der Modelle aus einfachen Formen (Mündung zeigt nach -Z) -------------------------


func _build_model(slot: HandSlot, id: String) -> void:
	match id:
		"pistol":
			_build_pistol(slot)
		"revolver":
			_build_revolver(slot)
		"smg":
			_build_smg(slot)
		"sawed_off":
			_build_sawed_off(slot)
		"shotgun":
			_build_shotgun(slot)
		"rifle":
			_build_rifle(slot)
		"sniper":
			_build_sniper(slot)
		"minigun":
			_build_minigun(slot)
		"rocket_launcher":
			_build_rocket_launcher(slot)
		"burst_pistol":
			_build_burst_pistol(slot)
		"nail_gun":
			_build_nail_gun(slot)
		"machine_pistol":
			_build_machine_pistol(slot)
		"crossbow":
			_build_crossbow(slot)
		"grenade_launcher":
			_build_grenade_launcher(slot)
		"flamethrower":
			_build_flamethrower(slot)
		"beam":
			_build_beam(slot)
		"tesla":
			_build_tesla(slot)
		"lmg":
			_build_lmg(slot)
		"auto_shotgun":
			_build_auto_shotgun(slot)
		_:
			_build_placeholder(slot, id)


## Platzhalter für eine Waffe ohne eigenes Modell (alle 19 Waffen haben eines, das hier greift
## nur für eine künftige Waffe): schlichtes Gehäuse mit Lauf, Griff, Magazin und Mündung.
## Zweihand-Waffen sind länger. Ohne Eintrag in RECOIL gibt es dafür weder Rückstoß noch
## Mündungsfeuer.
func _build_placeholder(slot: HandSlot, id: String) -> void:
	var gun: Node3D = _new_gun(slot, id)
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.0, 0.1)
	var length: float = 0.46 if ItemDefs.hands(id) > 1 else 0.26
	_box(gun, Vector3(0.055, 0.07, length), Vector3(0.0, 0.02, 0.05 - length * 0.5), steel)
	_box(gun, Vector3(0.059, 0.016, length * 0.5), Vector3(0.0, 0.03, 0.02 - length * 0.5), yellow)
	_cylinder(gun, 0.016, 0.12, Vector3(0.0, 0.03, -length), steel)
	_box(gun, Vector3(0.012, 0.018, 0.018), Vector3(0.0, 0.064, 0.08 - length), _material(COLOR_PINK, 1.6, 0.0))
	_box(gun, Vector3(0.03, 0.016, 0.016), Vector3(0.0, 0.063, 0.03), steel)
	_box(gun, Vector3(0.012, 0.04, 0.07), Vector3(0.0, -0.035, -0.07), steel)
	var grip: MeshInstance3D = _box(gun, Vector3(0.044, 0.14, 0.066), Vector3(0.0, -0.085, 0.012), yellow)
	grip.rotation.x = -0.24
	_box(gun, Vector3(0.036, 0.1, 0.05), Vector3(0.0, -0.065, -0.15), _material(COLOR_TEAL, 0.4, 0.3))
	_add_muzzle(slot, gun, id, Vector3(0.0, 0.03, -length - 0.065))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.02))


func _build_pistol(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "pistol")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.0, 0.1)
	var glow: StandardMaterial3D = _material(COLOR_PINK, 1.6, 0.0)
	var slide: Node3D = _new_part(slot, gun, "pistol/slide", Vector3(0.0, 0.03, -0.1))
	_box(slide, Vector3(0.05, 0.055, 0.26), Vector3.ZERO, steel)
	_box(slide, Vector3(0.054, 0.014, 0.09), Vector3(0.0, 0.004, 0.06), yellow)
	_box(slide, Vector3(0.012, 0.016, 0.016), Vector3(0.0, 0.034, -0.115), glow)
	_box(slide, Vector3(0.03, 0.014, 0.014), Vector3(0.0, 0.033, 0.115), steel)
	_box(gun, Vector3(0.044, 0.03, 0.21), Vector3(0.0, -0.012, -0.09), yellow)
	_box(gun, Vector3(0.012, 0.04, 0.075), Vector3(0.0, -0.045, -0.075), steel)
	var grip: MeshInstance3D = _box(gun, Vector3(0.044, 0.15, 0.068), Vector3(0.0, -0.09, 0.012), yellow)
	grip.rotation.x = -0.24
	var grip_stripe: MeshInstance3D = _box(gun, Vector3(0.048, 0.05, 0.05), Vector3(0.0, -0.1, 0.014), steel)
	grip_stripe.rotation.x = -0.24
	var mag: Node3D = _new_part(slot, gun, "pistol/mag", Vector3(0.0, -0.09, 0.012))
	mag.rotation.x = -0.24
	_box(mag, Vector3(0.03, 0.13, 0.046), Vector3.ZERO, _material(COLOR_TEAL, 0.4, 0.3))
	_add_muzzle(slot, gun, "pistol", Vector3(0.0, 0.03, -0.245))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.02))


func _build_revolver(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "revolver")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var silver: StandardMaterial3D = _material(COLOR_SILVER, 0.0, 0.8)
	var red: StandardMaterial3D = _material(COLOR_RED, 0.0, 0.2)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	# Rahmen mit Aussparung für die Trommel: Steg oben, Steg unten, Block hinten.
	_box(gun, Vector3(0.04, 0.022, 0.2), Vector3(0.0, 0.085, -0.07), silver)
	_box(gun, Vector3(0.04, 0.022, 0.16), Vector3(0.0, -0.022, -0.06), silver)
	_box(gun, Vector3(0.044, 0.1, 0.05), Vector3(0.0, 0.025, 0.035), silver)
	_box(gun, Vector3(0.044, 0.1, 0.03), Vector3(0.0, 0.035, -0.165), silver)
	# Langer, dicker Lauf mit Schiene darunter.
	_cylinder(gun, 0.024, 0.3, Vector3(0.0, 0.055, -0.32), silver)
	_box(gun, Vector3(0.03, 0.03, 0.27), Vector3(0.0, 0.018, -0.31), steel)
	_box(gun, Vector3(0.012, 0.02, 0.02), Vector3(0.0, 0.088, -0.455), _material(COLOR_GOLD, 1.8, 0.0))
	var drum: Node3D = _new_part(slot, gun, "revolver/drum", Vector3(0.0, 0.032, -0.065))
	_cylinder(drum, 0.05, 0.1, Vector3.ZERO, gold)
	# Rillen, an denen man die Drehung sieht.
	for i: int in 3:
		var groove: MeshInstance3D = _box(drum, Vector3(0.104, 0.018, 0.07), Vector3.ZERO, steel)
		groove.rotation.z = PI / 3.0 * float(i)
	var hammer: Node3D = _new_part(slot, gun, "revolver/hammer", Vector3(0.0, 0.07, 0.05))
	_box(hammer, Vector3(0.014, 0.04, 0.018), Vector3(0.0, 0.016, 0.008), steel)
	var grip: MeshInstance3D = _box(gun, Vector3(0.046, 0.16, 0.07), Vector3(0.0, -0.085, 0.04), red)
	grip.rotation.x = -0.32
	_box(gun, Vector3(0.05, 0.03, 0.074), Vector3(0.0, -0.155, 0.062), gold).rotation.x = -0.32
	_box(gun, Vector3(0.012, 0.04, 0.07), Vector3(0.0, -0.05, -0.04), steel)
	_add_muzzle(slot, gun, "revolver", Vector3(0.0, 0.055, -0.48))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.045))


func _build_smg(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "smg")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var teal: StandardMaterial3D = _material(COLOR_TEAL, 0.0, 0.3)
	var pink: StandardMaterial3D = _material(COLOR_PINK, 1.6, 0.0)
	_box(gun, Vector3(0.065, 0.1, 0.38), Vector3(0.0, 0.02, -0.1), teal)
	_box(gun, Vector3(0.069, 0.03, 0.2), Vector3(0.0, 0.02, -0.12), steel)
	_box(gun, Vector3(0.028, 0.018, 0.3), Vector3(0.0, 0.079, -0.1), pink)
	_box(gun, Vector3(0.014, 0.03, 0.02), Vector3(0.0, 0.1, -0.24), pink)
	_cylinder(gun, 0.024, 0.15, Vector3(0.0, 0.03, -0.36), steel)
	_cylinder(gun, 0.03, 0.03, Vector3(0.0, 0.03, -0.43), pink)
	_box(gun, Vector3(0.03, 0.05, 0.12), Vector3(0.0, 0.025, 0.15), steel)
	_box(gun, Vector3(0.04, 0.09, 0.025), Vector3(0.0, 0.005, 0.215), steel)
	_box(gun, Vector3(0.044, 0.12, 0.06), Vector3(0.0, -0.085, 0.05), steel).rotation.x = -0.2
	var mag: Node3D = _new_part(slot, gun, "smg/mag", Vector3(0.0, -0.13, -0.15))
	mag.rotation.x = 0.12
	_box(mag, Vector3(0.036, 0.24, 0.062), Vector3.ZERO, _material(COLOR_YELLOW, 0.3, 0.2))
	_add_muzzle(slot, gun, "smg", Vector3(0.0, 0.03, -0.46))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.06))


func _build_sawed_off(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "sawed_off")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var purple: StandardMaterial3D = _material(COLOR_PURPLE, 0.0, 0.3)
	var lime: StandardMaterial3D = _material(COLOR_LIME, 0.5, 0.1)
	var wood: StandardMaterial3D = _material(COLOR_WOOD, 0.0, 0.0)
	# Breiter Kasten, daran zwei kurze, dicke Läufe nebeneinander.
	_box(gun, Vector3(0.11, 0.085, 0.15), Vector3(0.0, 0.025, -0.02), purple)
	_box(gun, Vector3(0.114, 0.02, 0.1), Vector3(0.0, 0.05, -0.02), lime)
	var barrels: Node3D = _new_part(slot, gun, "sawed_off/barrels", Vector3(0.0, 0.0, -0.095))
	for side: float in [-1.0, 1.0]:
		_cylinder(barrels, 0.03, 0.27, Vector3(0.028 * side, 0.035, -0.135), steel)
		_cylinder(barrels, 0.021, 0.012, Vector3(0.028 * side, 0.035, -0.272), lime)
	_box(barrels, Vector3(0.124, 0.074, 0.03), Vector3(0.0, 0.035, -0.04), lime)
	_box(barrels, Vector3(0.124, 0.074, 0.024), Vector3(0.0, 0.035, -0.2), purple)
	_box(barrels, Vector3(0.05, 0.03, 0.2), Vector3(0.0, -0.008, -0.12), wood)
	# Kurzer, gebogener Holzgriff statt eines Schafts.
	_box(gun, Vector3(0.052, 0.09, 0.13), Vector3(0.0, -0.015, 0.1), wood).rotation.x = -0.35
	_box(gun, Vector3(0.05, 0.13, 0.065), Vector3(0.0, -0.09, 0.14), wood).rotation.x = -0.5
	_box(gun, Vector3(0.012, 0.04, 0.07), Vector3(0.0, -0.04, 0.02), steel)
	_add_muzzle(slot, gun, "sawed_off", Vector3(0.0, 0.035, -0.385))
	_add_grip_hand(gun, Vector3(0.0, -0.095, 0.13))


func _build_shotgun(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "shotgun")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var red: StandardMaterial3D = _material(COLOR_RED, 0.0, 0.2)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	_box(gun, Vector3(0.062, 0.09, 0.3), Vector3.ZERO, red)
	_box(gun, Vector3(0.066, 0.02, 0.2), Vector3(0.0, 0.02, 0.0), gold)
	_cylinder(gun, 0.023, 0.62, Vector3(0.0, 0.026, -0.45), steel)
	_cylinder(gun, 0.02, 0.46, Vector3(0.0, -0.026, -0.38), gold)
	_box(gun, Vector3(0.014, 0.02, 0.014), Vector3(0.0, 0.055, -0.74), _material(COLOR_GOLD, 1.8, 0.0))
	var stock: MeshInstance3D = _box(gun, Vector3(0.05, 0.1, 0.32), Vector3(0.0, -0.04, 0.29), red)
	stock.rotation.x = -0.13
	_box(gun, Vector3(0.042, 0.11, 0.05), Vector3(0.0, -0.085, 0.1), steel).rotation.x = -0.3
	var pump: Node3D = _new_part(slot, gun, "shotgun/pump", Vector3(0.0, -0.03, -0.44))
	_box(pump, Vector3(0.072, 0.062, 0.18), Vector3.ZERO, _material(Color(1.0, 0.45, 0.1), 0.0, 0.1))
	for i: int in 3:
		_box(pump, Vector3(0.076, 0.066, 0.016), Vector3(0.0, 0.0, -0.05 + 0.05 * float(i)), steel)
	# Die linke Hand liegt am Vorderschaft und macht das Durchladen mit.
	_add_support_hand(pump, Vector3(-0.005, -0.03, 0.0))
	_add_muzzle(slot, gun, "shotgun", Vector3(0.0, 0.026, -0.77))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.11))


func _build_rifle(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "rifle")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var blue: StandardMaterial3D = _material(COLOR_BLUE, 0.0, 0.3)
	var orange: StandardMaterial3D = _material(COLOR_ORANGE, 0.0, 0.1)
	var glow: StandardMaterial3D = _material(COLOR_ORANGE, 1.6, 0.0)
	# Gehäuse, Handschutz, Lauf mit Mündungsbremse.
	_box(gun, Vector3(0.06, 0.1, 0.4), Vector3(0.0, 0.02, -0.06), blue)
	_box(gun, Vector3(0.064, 0.026, 0.3), Vector3(0.0, 0.035, -0.06), steel)
	_box(gun, Vector3(0.058, 0.074, 0.27), Vector3(0.0, 0.022, -0.39), orange)
	for i: int in 4:
		_box(gun, Vector3(0.062, 0.03, 0.022), Vector3(0.0, 0.03, -0.3 - 0.06 * float(i)), steel)
	_cylinder(gun, 0.016, 0.24, Vector3(0.0, 0.03, -0.63), steel)
	_cylinder(gun, 0.026, 0.06, Vector3(0.0, 0.03, -0.76), orange)
	# Tragegriff mit Visier, Korn vorn.
	_box(gun, Vector3(0.024, 0.016, 0.22), Vector3(0.0, 0.125, -0.04), steel)
	_box(gun, Vector3(0.024, 0.05, 0.022), Vector3(0.0, 0.095, 0.06), steel)
	_box(gun, Vector3(0.024, 0.05, 0.022), Vector3(0.0, 0.095, -0.14), steel)
	_box(gun, Vector3(0.014, 0.02, 0.014), Vector3(0.0, 0.14, 0.05), glow)
	_box(gun, Vector3(0.014, 0.07, 0.016), Vector3(0.0, 0.085, -0.5), steel)
	# Schaft und Griff.
	_box(gun, Vector3(0.05, 0.085, 0.28), Vector3(0.0, 0.0, 0.28), blue)
	_box(gun, Vector3(0.054, 0.12, 0.03), Vector3(0.0, -0.01, 0.43), steel)
	_box(gun, Vector3(0.042, 0.12, 0.055), Vector3(0.0, -0.085, 0.09), steel).rotation.x = -0.28
	var mag: Node3D = _new_part(slot, gun, "rifle/mag", Vector3(0.0, -0.12, -0.1))
	mag.rotation.x = 0.3
	_box(mag, Vector3(0.04, 0.2, 0.075), Vector3.ZERO, orange)
	_box(mag, Vector3(0.044, 0.03, 0.079), Vector3(0.0, -0.09, 0.0), steel)
	_add_support_hand(gun, Vector3(-0.005, -0.035, -0.4))
	_add_muzzle(slot, gun, "rifle", Vector3(0.0, 0.03, -0.8))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.1))


func _build_sniper(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "sniper")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var white: StandardMaterial3D = _material(COLOR_WHITE, 0.0, 0.1)
	var purple: StandardMaterial3D = _material(COLOR_PURPLE, 0.0, 0.3)
	var lens: StandardMaterial3D = _material(COLOR_TEAL, 2.0, 0.0)
	var eyepiece: StandardMaterial3D = _material(Color(0.04, 0.2, 0.26), 0.6, 0.0)
	# Schlankes Gehäuse, sehr langer dünner Lauf mit Mündungsbremse.
	_box(gun, Vector3(0.052, 0.08, 0.5), Vector3(0.0, 0.01, -0.08), white)
	_box(gun, Vector3(0.056, 0.02, 0.4), Vector3(0.0, -0.012, -0.1), purple)
	_cylinder(gun, 0.014, 0.62, Vector3(0.0, 0.03, -0.63), steel)
	_box(gun, Vector3(0.044, 0.04, 0.08), Vector3(0.0, 0.03, -0.96), purple)
	# Großes Zielfernrohr mit leuchtenden Linsen.
	_cylinder(gun, 0.03, 0.26, Vector3(0.0, 0.115, -0.08), purple)
	_tapered(gun, 0.048, 0.03, 0.09, Vector3(0.0, 0.115, -0.25), steel)
	_tapered(gun, 0.03, 0.036, 0.06, Vector3(0.0, 0.115, 0.08), steel)
	_cylinder(gun, 0.042, 0.008, Vector3(0.0, 0.115, -0.297), lens)
	_cylinder(gun, 0.026, 0.008, Vector3(0.0, 0.115, 0.112), eyepiece)
	_box(gun, Vector3(0.02, 0.05, 0.028), Vector3(0.0, 0.07, -0.16), steel)
	_box(gun, Vector3(0.02, 0.05, 0.028), Vector3(0.0, 0.07, 0.0), steel)
	_box(gun, Vector3(0.016, 0.03, 0.03), Vector3(0.0, 0.158, -0.08), purple)
	# Schaft mit Wangenauflage, Griff.
	_box(gun, Vector3(0.05, 0.1, 0.34), Vector3(0.0, -0.012, 0.33), white).rotation.x = -0.06
	_box(gun, Vector3(0.04, 0.03, 0.16), Vector3(0.0, 0.06, 0.3), purple)
	_box(gun, Vector3(0.054, 0.13, 0.03), Vector3(0.0, -0.02, 0.51), steel)
	_box(gun, Vector3(0.042, 0.12, 0.055), Vector3(0.0, -0.085, 0.12), steel).rotation.x = -0.3
	var bolt: Node3D = _new_part(slot, gun, "sniper/bolt", Vector3(0.03, 0.04, 0.1))
	_box(bolt, Vector3(0.06, 0.018, 0.018), Vector3(0.02, 0.0, 0.0), steel)
	_box(bolt, Vector3(0.03, 0.03, 0.03), Vector3(0.055, -0.012, 0.0), _material(COLOR_GOLD, 0.4, 0.7))
	var mag: Node3D = _new_part(slot, gun, "sniper/mag", Vector3(0.0, -0.06, -0.06))
	_box(mag, Vector3(0.04, 0.07, 0.1), Vector3.ZERO, purple)
	_add_support_hand(gun, Vector3(-0.005, -0.06, -0.3))
	_add_muzzle(slot, gun, "sniper", Vector3(0.0, 0.03, -1.01))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.13))


func _build_minigun(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "minigun")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var pink: StandardMaterial3D = _material(COLOR_PINK, 0.0, 0.3)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.3, 0.2)
	# Dicker Motorblock mit Warnstreifen.
	_box(gun, Vector3(0.15, 0.15, 0.3), Vector3(0.0, 0.0, 0.0), pink)
	for i: int in 3:
		_box(gun, Vector3(0.154, 0.154, 0.03), Vector3(0.0, 0.0, -0.1 + 0.1 * float(i)), yellow)
	_cylinder(gun, 0.078, 0.05, Vector3(0.0, 0.0, -0.17), steel)
	# Sechs Läufe im Kreis, zusammengehalten von drei Scheiben. Das Bündel dreht sich.
	var barrels: Node3D = _new_part(slot, gun, "minigun/barrels", Vector3(0.0, 0.0, -0.2))
	for i: int in 6:
		var angle: float = TAU / 6.0 * float(i)
		_cylinder(barrels, 0.018, 0.62, Vector3(cos(angle) * 0.05, sin(angle) * 0.05, -0.31), steel)
	_cylinder(barrels, 0.074, 0.03, Vector3(0.0, 0.0, -0.18), yellow)
	_cylinder(barrels, 0.074, 0.03, Vector3(0.0, 0.0, -0.4), yellow)
	_cylinder(barrels, 0.074, 0.03, Vector3(0.0, 0.0, -0.6), pink)
	_cylinder(barrels, 0.026, 0.6, Vector3(0.0, 0.0, -0.3), yellow)
	# Tragegriff oben, Griff hinten (rechte Hand), Seitengriff vorn links (linke Hand).
	_box(gun, Vector3(0.03, 0.03, 0.22), Vector3(0.0, 0.14, -0.02), steel)
	_box(gun, Vector3(0.03, 0.07, 0.03), Vector3(0.0, 0.105, -0.11), steel)
	_box(gun, Vector3(0.03, 0.07, 0.03), Vector3(0.0, 0.105, 0.07), steel)
	_box(gun, Vector3(0.05, 0.05, 0.14), Vector3(0.0, 0.0, 0.21), steel)
	_box(gun, Vector3(0.044, 0.13, 0.05), Vector3(0.0, -0.05, 0.27), steel).rotation.x = -0.15
	_box(gun, Vector3(0.09, 0.034, 0.034), Vector3(-0.11, -0.02, -0.1), steel)
	# Munitionskasten unter dem Block.
	var box: Node3D = _new_part(slot, gun, "minigun/box", Vector3(0.0, -0.15, 0.02))
	_box(box, Vector3(0.13, 0.15, 0.2), Vector3.ZERO, yellow)
	_box(box, Vector3(0.134, 0.03, 0.204), Vector3(0.0, 0.03, 0.0), steel)
	_add_support_hand(gun, Vector3(-0.16, -0.025, -0.1))
	_add_muzzle(slot, gun, "minigun", Vector3(0.0, 0.0, -0.84))
	_add_grip_hand(gun, Vector3(0.0, -0.07, 0.28))


func _build_rocket_launcher(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "rocket_launcher")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var green: StandardMaterial3D = _material(COLOR_GREEN, 0.0, 0.2)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	var red: StandardMaterial3D = _material(COLOR_RED, 0.6, 0.1)
	# Dickes Rohr auf der Schulter mit goldenen Ringen und Trichter hinten.
	_cylinder(gun, 0.07, 0.95, Vector3(0.0, 0.07, -0.05), green)
	_cylinder(gun, 0.082, 0.05, Vector3(0.0, 0.07, -0.5), gold)
	_cylinder(gun, 0.078, 0.04, Vector3(0.0, 0.07, -0.2), gold)
	_cylinder(gun, 0.078, 0.04, Vector3(0.0, 0.07, 0.2), gold)
	_tapered(gun, 0.07, 0.11, 0.14, Vector3(0.0, 0.07, 0.49), gold)
	# Visier an der Seite, zwei Griffe unten.
	_box(gun, Vector3(0.02, 0.09, 0.02), Vector3(-0.06, 0.15, -0.22), steel)
	_box(gun, Vector3(0.05, 0.04, 0.012), Vector3(-0.06, 0.2, -0.22), _material(COLOR_LIME, 1.6, 0.0))
	_box(gun, Vector3(0.05, 0.05, 0.3), Vector3(0.0, -0.01, -0.12), steel)
	_box(gun, Vector3(0.042, 0.13, 0.055), Vector3(0.0, -0.085, 0.0), steel).rotation.x = -0.2
	_box(gun, Vector3(0.042, 0.11, 0.05), Vector3(0.0, -0.08, -0.25), steel)
	# Die Rakete schaut vorn aus dem Rohr.
	# Der Gefechtskopf ist dicker als das Rohr: So sieht man die Rakete auch von hinten.
	var rocket: Node3D = _new_part(slot, gun, "rocket_launcher/rocket", Vector3(0.0, 0.07, -0.53))
	_cylinder(rocket, 0.055, 0.1, Vector3(0.0, 0.0, -0.03), _material(COLOR_WHITE, 0.0, 0.1))
	_tapered(rocket, 0.11, 0.06, 0.07, Vector3(0.0, 0.0, -0.105), red)
	_cylinder(rocket, 0.11, 0.05, Vector3(0.0, 0.0, -0.165), red)
	_cylinder(rocket, 0.114, 0.016, Vector3(0.0, 0.0, -0.165), gold)
	_tapered(rocket, 0.01, 0.11, 0.17, Vector3(0.0, 0.0, -0.275), red)
	_add_support_hand(gun, Vector3(-0.005, -0.095, -0.25))
	_add_muzzle(slot, gun, "rocket_launcher", Vector3(0.0, 0.07, -0.62))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.01))


# --- Die zehn Waffen aus Abschnitt 22.2 ---


func _build_burst_pistol(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "burst_pistol")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var pink: StandardMaterial3D = _material(COLOR_PINK, 0.0, 0.3)
	var white: StandardMaterial3D = _material(COLOR_WHITE, 0.0, 0.1)
	# Hoher Schlitten mit drei Mündungen übereinander.
	var slide: Node3D = _new_part(slot, gun, "burst_pistol/slide", Vector3(0.0, 0.04, -0.1))
	_box(slide, Vector3(0.052, 0.088, 0.27), Vector3.ZERO, pink)
	_box(slide, Vector3(0.056, 0.016, 0.12), Vector3(0.0, 0.022, 0.05), white)
	for i: int in 3:
		_cylinder(slide, 0.012, 0.03, Vector3(0.0, -0.027 + 0.027 * float(i), -0.145), steel)
	_box(slide, Vector3(0.012, 0.016, 0.016), Vector3(0.0, 0.052, -0.12), _material(COLOR_YELLOW, 1.6, 0.0))
	_box(slide, Vector3(0.03, 0.014, 0.014), Vector3(0.0, 0.051, 0.12), steel)
	_box(gun, Vector3(0.046, 0.03, 0.22), Vector3(0.0, -0.018, -0.09), white)
	_box(gun, Vector3(0.012, 0.04, 0.075), Vector3(0.0, -0.05, -0.075), steel)
	_box(gun, Vector3(0.046, 0.15, 0.07), Vector3(0.0, -0.095, 0.012), white).rotation.x = -0.24
	# Drei Streifen am Griff.
	for i: int in 3:
		_box(gun, Vector3(0.05, 0.014, 0.05), Vector3(0.0, -0.065 - 0.03 * float(i), 0.006 + 0.007 * float(i)), pink).rotation.x = -0.24
	# Langes Magazin, das unten aus dem Griff ragt.
	var mag: Node3D = _new_part(slot, gun, "burst_pistol/mag", Vector3(0.0, -0.115, 0.018))
	mag.rotation.x = -0.24
	_box(mag, Vector3(0.032, 0.2, 0.048), Vector3.ZERO, _material(COLOR_YELLOW, 0.3, 0.2))
	_add_muzzle(slot, gun, "burst_pistol", Vector3(0.0, 0.04, -0.265))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.02))


func _build_nail_gun(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "nail_gun")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var orange: StandardMaterial3D = _material(COLOR_ORANGE, 0.0, 0.1)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.0, 0.1)
	var silver: StandardMaterial3D = _material(COLOR_SILVER, 0.0, 0.8)
	# Gehäuse mit Warnstreifen, darauf ein stehender Druckzylinder.
	_box(gun, Vector3(0.07, 0.11, 0.2), Vector3(0.0, 0.03, -0.06), orange)
	_box(gun, Vector3(0.074, 0.02, 0.2), Vector3(0.0, 0.0, -0.06), yellow)
	var cap: MeshInstance3D = _cylinder(gun, 0.05, 0.09, Vector3(0.0, 0.125, -0.03), steel)
	cap.rotation.x = 0.0
	var lid: MeshInstance3D = _cylinder(gun, 0.038, 0.02, Vector3(0.0, 0.178, -0.03), orange)
	lid.rotation.x = 0.0
	# Nase mit Nagelstift und Aufsetzbügel.
	_box(gun, Vector3(0.042, 0.055, 0.1), Vector3(0.0, 0.02, -0.2), steel)
	_cylinder(gun, 0.008, 0.07, Vector3(0.0, 0.02, -0.28), silver)
	_box(gun, Vector3(0.05, 0.012, 0.012), Vector3(0.0, 0.02, -0.305), yellow)
	# Schräger Nagelstreifen von der Nase zum Griffende.
	var mag: Node3D = _new_part(slot, gun, "nail_gun/mag", Vector3(0.0, -0.085, -0.1))
	mag.rotation.x = -0.5
	_box(mag, Vector3(0.03, 0.05, 0.27), Vector3.ZERO, _material(COLOR_LIME, 0.5, 0.1))
	for i: int in 5:
		_box(mag, Vector3(0.034, 0.054, 0.008), Vector3(0.0, 0.0, -0.1 + 0.05 * float(i)), silver)
	_box(gun, Vector3(0.044, 0.14, 0.06), Vector3(0.0, -0.075, 0.035), orange).rotation.x = -0.2
	_box(gun, Vector3(0.048, 0.03, 0.064), Vector3(0.0, -0.15, 0.05), steel).rotation.x = -0.2
	_box(gun, Vector3(0.012, 0.035, 0.06), Vector3(0.0, -0.045, -0.03), steel)
	_add_muzzle(slot, gun, "nail_gun", Vector3(0.0, 0.02, -0.32))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.045))


func _build_machine_pistol(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "machine_pistol")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var mint: StandardMaterial3D = _material(COLOR_MINT, 0.0, 0.2)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.3, 0.2)
	# Kurzer Kasten mit Schiene, davor ein dicker Laufmantel mit gelben Ringen.
	_box(gun, Vector3(0.06, 0.085, 0.26), Vector3(0.0, 0.025, -0.06), mint)
	_box(gun, Vector3(0.03, 0.016, 0.22), Vector3(0.0, 0.075, -0.06), steel)
	_box(gun, Vector3(0.014, 0.022, 0.016), Vector3(0.0, 0.094, -0.15), _material(COLOR_PINK, 1.6, 0.0))
	_box(gun, Vector3(0.03, 0.02, 0.014), Vector3(0.0, 0.093, 0.03), steel)
	_cylinder(gun, 0.018, 0.08, Vector3(0.0, 0.03, -0.23), steel)
	_cylinder(gun, 0.03, 0.1, Vector3(0.0, 0.03, -0.31), steel)
	_cylinder(gun, 0.033, 0.014, Vector3(0.0, 0.03, -0.28), yellow)
	_cylinder(gun, 0.033, 0.014, Vector3(0.0, 0.03, -0.34), yellow)
	# Kurzer Stummel hinten statt eines Schafts.
	_box(gun, Vector3(0.04, 0.05, 0.05), Vector3(0.0, 0.03, 0.095), steel)
	# Das Stangenmagazin steckt quer in der Seite (aus Sicht des Schützen links).
	_box(gun, Vector3(0.03, 0.05, 0.064), Vector3(-0.04, 0.03, -0.1), steel)
	var mag: Node3D = _new_part(slot, gun, "machine_pistol/mag", Vector3(-0.135, 0.03, -0.1))
	_box(mag, Vector3(0.17, 0.032, 0.046), Vector3.ZERO, yellow)
	_box(mag, Vector3(0.02, 0.038, 0.052), Vector3(-0.08, 0.0, 0.0), steel)
	_box(gun, Vector3(0.046, 0.13, 0.066), Vector3(0.0, -0.08, 0.0), steel).rotation.x = -0.1
	_box(gun, Vector3(0.012, 0.035, 0.06), Vector3(0.0, -0.04, -0.065), steel)
	_add_muzzle(slot, gun, "machine_pistol", Vector3(0.0, 0.03, -0.375))
	_add_grip_hand(gun, Vector3(0.0, -0.095, 0.012))


func _build_crossbow(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "crossbow")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var wood: StandardMaterial3D = _material(COLOR_WOOD, 0.0, 0.0)
	var teal: StandardMaterial3D = _material(COLOR_TEAL, 0.0, 0.3)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	var cord: StandardMaterial3D = _material(COLOR_WHITE, 0.6, 0.0)
	# Schiene aus Holz mit türkiser Führung.
	_box(gun, Vector3(0.04, 0.045, 0.5), Vector3(0.0, 0.02, -0.15), wood)
	_box(gun, Vector3(0.016, 0.01, 0.46), Vector3(0.0, 0.046, -0.16), teal)
	# Zwei Wurfarme quer an der Spitze, nach hinten gepfeilt, mit goldenen Enden.
	for side: float in [-1.0, 1.0]:
		_box(gun, Vector3(0.2, 0.022, 0.03), Vector3(0.1 * side, 0.03, -0.345), teal).rotation.y = -0.35 * side
		_box(gun, Vector3(0.03, 0.04, 0.04), Vector3(0.19 * side, 0.03, -0.31), gold)
	_box(gun, Vector3(0.06, 0.05, 0.05), Vector3(0.0, 0.025, -0.38), steel)
	# Steigbügel vorn.
	_box(gun, Vector3(0.07, 0.012, 0.012), Vector3(0.0, 0.02, -0.45), steel)
	for side: float in [-1.0, 1.0]:
		_box(gun, Vector3(0.012, 0.012, 0.05), Vector3(0.03 * side, 0.02, -0.425), steel)
	# Sehne: gespannt als V bis zur Nuss, entspannt gerade zwischen den Armen.
	var drawn: Node3D = _new_part(slot, gun, "crossbow/string", Vector3(0.0, 0.052, 0.0))
	for side: float in [-1.0, 1.0]:
		_box(drawn, Vector3(0.006, 0.006, 0.32), Vector3(0.095 * side, 0.0, -0.18), cord).rotation.y = -0.635 * side
	var loose: Node3D = _new_part(slot, gun, "crossbow/string_loose", Vector3(0.0, 0.052, -0.31))
	_box(loose, Vector3(0.38, 0.006, 0.006), Vector3.ZERO, cord)
	loose.visible = false
	_box(gun, Vector3(0.03, 0.03, 0.04), Vector3(0.0, 0.055, -0.045), gold)
	# Bolzen mit leuchtender Spitze und Federn.
	var bolt: Node3D = _new_part(slot, gun, "crossbow/bolt", Vector3(0.0, 0.06, -0.21))
	_cylinder(bolt, 0.007, 0.34, Vector3.ZERO, steel)
	_tapered(bolt, 0.002, 0.018, 0.06, Vector3(0.0, 0.0, -0.2), _material(COLOR_LIME, 1.8, 0.0))
	_box(bolt, Vector3(0.03, 0.003, 0.05), Vector3(0.0, 0.0, 0.14), teal)
	_box(bolt, Vector3(0.003, 0.03, 0.05), Vector3(0.0, 0.0, 0.14), teal)
	# Visier, Griff, Abzugsbügel.
	_box(gun, Vector3(0.012, 0.03, 0.012), Vector3(0.0, 0.09, 0.02), _material(COLOR_GOLD, 1.8, 0.0))
	_box(gun, Vector3(0.03, 0.04, 0.03), Vector3(0.0, 0.06, 0.02), steel)
	_box(gun, Vector3(0.044, 0.14, 0.062), Vector3(0.0, -0.07, 0.05), wood).rotation.x = -0.3
	_box(gun, Vector3(0.012, 0.035, 0.07), Vector3(0.0, -0.025, -0.03), steel)
	_add_muzzle(slot, gun, "crossbow", Vector3(0.0, 0.06, -0.46))
	_add_grip_hand(gun, Vector3(0.0, -0.095, 0.06))


func _build_grenade_launcher(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "grenade_launcher")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var orange: StandardMaterial3D = _material(COLOR_ORANGE, 0.0, 0.2)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.3, 0.2)
	# Rahmen: Block hinten, Steg oben, Block vorn, dazwischen die Trommel.
	_box(gun, Vector3(0.06, 0.13, 0.06), Vector3(0.0, 0.01, 0.035), steel)
	_box(gun, Vector3(0.03, 0.02, 0.2), Vector3(0.0, 0.1, -0.065), steel)
	_box(gun, Vector3(0.06, 0.13, 0.03), Vector3(0.0, 0.01, -0.165), steel)
	# Dicke Trommel mit vier Kammern. Die obere liegt hinter dem Rohr.
	var drum: Node3D = _new_part(slot, gun, "grenade_launcher/drum", Vector3(0.0, 0.0, -0.065))
	_cylinder(drum, 0.075, 0.11, Vector3.ZERO, orange)
	for i: int in 4:
		var angle: float = PI * 0.5 * float(i + 1)
		_cylinder(drum, 0.024, 0.116, Vector3(cos(angle) * 0.043, sin(angle) * 0.043, 0.0), yellow)
	_cylinder(drum, 0.014, 0.12, Vector3.ZERO, steel)
	# Kurzes, dickes Rohr mit Warnring und Mündungsring.
	_cylinder(gun, 0.04, 0.2, Vector3(0.0, 0.043, -0.28), steel)
	_cylinder(gun, 0.044, 0.03, Vector3(0.0, 0.043, -0.25), yellow)
	_cylinder(gun, 0.05, 0.03, Vector3(0.0, 0.043, -0.375), orange)
	# Klappvisier, Griff, Abzugsbügel.
	_box(gun, Vector3(0.012, 0.06, 0.012), Vector3(0.0, 0.14, -0.15), _material(COLOR_LIME, 1.6, 0.0))
	_box(gun, Vector3(0.03, 0.02, 0.012), Vector3(0.0, 0.12, 0.02), steel)
	_box(gun, Vector3(0.046, 0.15, 0.066), Vector3(0.0, -0.11, 0.06), orange).rotation.x = -0.25
	_box(gun, Vector3(0.012, 0.035, 0.07), Vector3(0.0, -0.075, -0.01), steel)
	_add_muzzle(slot, gun, "grenade_launcher", Vector3(0.0, 0.043, -0.4))
	_add_grip_hand(gun, Vector3(0.0, -0.125, 0.07))


func _build_flamethrower(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "flamethrower")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var red: StandardMaterial3D = _material(COLOR_RED, 0.0, 0.2)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.0, 0.1)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	# Gehäuse, davor die lange dünne Lanze mit roten Kühlringen und einer Düse.
	_box(gun, Vector3(0.05, 0.065, 0.36), Vector3(0.0, 0.03, -0.05), steel)
	_box(gun, Vector3(0.054, 0.02, 0.3), Vector3(0.0, 0.05, -0.05), yellow)
	_cylinder(gun, 0.016, 0.42, Vector3(0.0, 0.04, -0.44), steel)
	for i: int in 4:
		_cylinder(gun, 0.027, 0.02, Vector3(0.0, 0.04, -0.3 - 0.08 * float(i)), red)
	_tapered(gun, 0.04, 0.018, 0.09, Vector3(0.0, 0.04, -0.69), yellow)
	# Zündflamme: dünnes Rohr unter der Lanze mit leuchtender Spitze.
	_cylinder(gun, 0.006, 0.3, Vector3(0.0, 0.004, -0.56), steel)
	_box(gun, Vector3(0.018, 0.018, 0.03), Vector3(0.0, 0.004, -0.72), _material(COLOR_ORANGE, 2.5, 0.0))
	# Roter Tank unter dem Gehäuse, mit goldenen Kappen und Warnstreifen.
	var tank: Node3D = _new_part(slot, gun, "flamethrower/tank", Vector3(0.0, -0.075, -0.1))
	_cylinder(tank, 0.062, 0.28, Vector3.ZERO, red)
	_cylinder(tank, 0.066, 0.03, Vector3(0.0, 0.0, -0.13), gold)
	_cylinder(tank, 0.066, 0.03, Vector3(0.0, 0.0, 0.13), gold)
	_cylinder(tank, 0.064, 0.04, Vector3.ZERO, yellow)
	_box(gun, Vector3(0.016, 0.05, 0.016), Vector3(0.0, -0.02, 0.06), steel)
	# Kurzer Schaft, Griff.
	_box(gun, Vector3(0.05, 0.075, 0.2), Vector3(0.0, 0.01, 0.23), red)
	_box(gun, Vector3(0.054, 0.1, 0.03), Vector3(0.0, 0.0, 0.34), steel)
	_box(gun, Vector3(0.042, 0.12, 0.055), Vector3(0.0, -0.075, 0.12), steel).rotation.x = -0.28
	_add_support_hand(gun, Vector3(-0.005, -0.01, -0.36))
	_add_muzzle(slot, gun, "flamethrower", Vector3(0.0, 0.04, -0.74))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.13))


func _build_beam(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "beam")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var white: StandardMaterial3D = _material(COLOR_WHITE, 0.0, 0.1)
	var glow: StandardMaterial3D = _material(COLOR_RED, 2.4, 0.0)
	# Weißes Gehäuse mit dunkler Unterseite und Kühlrippen.
	_box(gun, Vector3(0.07, 0.1, 0.34), Vector3(0.0, 0.02, -0.04), white)
	_box(gun, Vector3(0.074, 0.03, 0.26), Vector3(0.0, -0.02, -0.04), steel)
	for i: int in 3:
		_box(gun, Vector3(0.09, 0.05, 0.012), Vector3(0.0, 0.025, -0.13 + 0.05 * float(i)), steel)
	# Roter Leuchtstab zwischen zwei Zinken, darum drei Ringe, vorn die Linse.
	_cylinder(gun, 0.014, 0.42, Vector3(0.0, 0.03, -0.42), glow)
	for i: int in 3:
		_cylinder(gun, 0.046 - 0.007 * float(i), 0.03, Vector3(0.0, 0.03, -0.27 - 0.12 * float(i)), steel)
	_box(gun, Vector3(0.02, 0.014, 0.44), Vector3(0.0, 0.088, -0.43), white)
	_box(gun, Vector3(0.02, 0.014, 0.44), Vector3(0.0, -0.028, -0.43), white)
	_cylinder(gun, 0.03, 0.02, Vector3(0.0, 0.03, -0.64), glow)
	# Leuchtzelle oben, die beim Nachladen herausfährt.
	var cell: Node3D = _new_part(slot, gun, "beam/cell", Vector3(0.0, 0.085, 0.02))
	_box(cell, Vector3(0.05, 0.04, 0.14), Vector3.ZERO, _material(COLOR_RED, 1.2, 0.0))
	_box(cell, Vector3(0.054, 0.044, 0.02), Vector3(0.0, 0.0, 0.06), steel)
	# Schaft und Griff.
	_box(gun, Vector3(0.05, 0.085, 0.24), Vector3(0.0, 0.0, 0.25), white)
	_box(gun, Vector3(0.054, 0.12, 0.03), Vector3(0.0, -0.01, 0.38), steel)
	_box(gun, Vector3(0.042, 0.12, 0.055), Vector3(0.0, -0.085, 0.1), steel).rotation.x = -0.28
	_add_support_hand(gun, Vector3(-0.005, -0.07, -0.3))
	_add_muzzle(slot, gun, "beam", Vector3(0.0, 0.03, -0.66))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.11))


func _build_tesla(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "tesla")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var navy: StandardMaterial3D = _material(COLOR_NAVY, 0.0, 0.3)
	var copper: StandardMaterial3D = _material(COLOR_COPPER, 0.2, 0.8)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	var spark: StandardMaterial3D = _material(COLOR_CYAN, 2.5, 0.0)
	# Dunkelblaues Gehäuse mit goldener Leiste und zwei Kondensatoren an den Seiten.
	_box(gun, Vector3(0.07, 0.1, 0.3), Vector3(0.0, 0.02, -0.03), navy)
	_box(gun, Vector3(0.074, 0.02, 0.22), Vector3(0.0, 0.05, -0.03), gold)
	for side: float in [-1.0, 1.0]:
		_cylinder(gun, 0.022, 0.16, Vector3(0.05 * side, 0.03, -0.02), steel)
		_cylinder(gun, 0.024, 0.02, Vector3(0.05 * side, 0.03, -0.1), spark)
	# Kupferspule um einen Stab, an der Spitze die leuchtende Kugel zwischen zwei Zinken.
	_cylinder(gun, 0.012, 0.4, Vector3(0.0, 0.03, -0.38), steel)
	for i: int in 6:
		_cylinder(gun, 0.042, 0.024, Vector3(0.0, 0.03, -0.23 - 0.05 * float(i)), copper)
	_ball(gun, 0.045, Vector3(0.0, 0.03, -0.6), spark)
	for side: float in [-1.0, 1.0]:
		_box(gun, Vector3(0.012, 0.012, 0.14), Vector3(0.05 * side, 0.03, -0.58), gold).rotation.y = 0.25 * side
	# Zelle unter dem Gehäuse.
	var cell: Node3D = _new_part(slot, gun, "tesla/cell", Vector3(0.0, -0.065, -0.08))
	_box(cell, Vector3(0.05, 0.07, 0.12), Vector3.ZERO, _material(COLOR_CYAN, 0.8, 0.0))
	_box(cell, Vector3(0.054, 0.02, 0.124), Vector3(0.0, -0.03, 0.0), steel)
	# Schaft und Griff.
	_box(gun, Vector3(0.05, 0.085, 0.26), Vector3(0.0, 0.0, 0.25), navy)
	_box(gun, Vector3(0.054, 0.12, 0.03), Vector3(0.0, -0.01, 0.39), gold)
	_box(gun, Vector3(0.042, 0.12, 0.055), Vector3(0.0, -0.085, 0.09), steel).rotation.x = -0.28
	_add_support_hand(gun, Vector3(-0.005, -0.05, -0.28))
	_add_muzzle(slot, gun, "tesla", Vector3(0.0, 0.03, -0.66))
	_add_grip_hand(gun, Vector3(0.0, -0.1, 0.1))


func _build_lmg(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "lmg")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var olive: StandardMaterial3D = _material(COLOR_OLIVE, 0.0, 0.2)
	var gold: StandardMaterial3D = _material(COLOR_GOLD, 0.25, 0.7)
	# Langes Gehäuse mit Deckel, dicker Laufmantel mit Ringen, Lauf mit Mündungstrichter.
	_box(gun, Vector3(0.065, 0.11, 0.44), Vector3(0.0, 0.02, -0.06), olive)
	_box(gun, Vector3(0.069, 0.025, 0.2), Vector3(0.0, 0.085, 0.0), steel)
	_cylinder(gun, 0.03, 0.3, Vector3(0.0, 0.035, -0.43), steel)
	for i: int in 4:
		_cylinder(gun, 0.034, 0.02, Vector3(0.0, 0.035, -0.32 - 0.07 * float(i)), olive)
	_cylinder(gun, 0.016, 0.2, Vector3(0.0, 0.035, -0.68), steel)
	_tapered(gun, 0.03, 0.018, 0.06, Vector3(0.0, 0.035, -0.8), gold)
	# Tragegriff oben, Korn, eingeklapptes Zweibein unter dem Mantel.
	_box(gun, Vector3(0.024, 0.016, 0.2), Vector3(0.0, 0.15, -0.12), steel)
	_box(gun, Vector3(0.024, 0.05, 0.022), Vector3(0.0, 0.12, -0.04), steel)
	_box(gun, Vector3(0.024, 0.05, 0.022), Vector3(0.0, 0.12, -0.2), steel)
	_box(gun, Vector3(0.014, 0.05, 0.016), Vector3(0.0, 0.085, -0.56), _material(COLOR_ORANGE, 1.6, 0.0))
	for side: float in [-1.0, 1.0]:
		_box(gun, Vector3(0.012, 0.012, 0.28), Vector3(0.028 * side, -0.005, -0.44), steel)
	# Munitionskasten links unter dem Gehäuse, der Gurt läuft hoch in den Deckel.
	var box: Node3D = _new_part(slot, gun, "lmg/box", Vector3(-0.03, -0.11, -0.1))
	_box(box, Vector3(0.11, 0.12, 0.16), Vector3.ZERO, olive)
	_box(box, Vector3(0.114, 0.025, 0.164), Vector3(0.0, 0.05, 0.0), steel)
	for i: int in 4:
		_box(gun, Vector3(0.016, 0.03, 0.05), Vector3(-0.045, -0.035 + 0.03 * float(i), -0.05), gold)
	# Schaft und Griff.
	_box(gun, Vector3(0.05, 0.09, 0.3), Vector3(0.0, 0.0, 0.31), olive)
	_box(gun, Vector3(0.054, 0.13, 0.03), Vector3(0.0, -0.01, 0.47), steel)
	_box(gun, Vector3(0.042, 0.12, 0.055), Vector3(0.0, -0.09, 0.11), steel).rotation.x = -0.28
	_add_support_hand(gun, Vector3(-0.005, -0.04, -0.42))
	_add_muzzle(slot, gun, "lmg", Vector3(0.0, 0.035, -0.84))
	_add_grip_hand(gun, Vector3(0.0, -0.105, 0.12))


func _build_auto_shotgun(slot: HandSlot) -> void:
	var gun: Node3D = _new_gun(slot, "auto_shotgun")
	var steel: StandardMaterial3D = _material(COLOR_STEEL, 0.0, 0.6)
	var sky: StandardMaterial3D = _material(COLOR_SKY, 0.0, 0.3)
	var white: StandardMaterial3D = _material(COLOR_WHITE, 0.0, 0.1)
	var yellow: StandardMaterial3D = _material(COLOR_YELLOW, 0.3, 0.2)
	# Gehäuse, dicker Lauf mit Hitzeschild und Mündungsbremse, Gasrohr darunter.
	_box(gun, Vector3(0.066, 0.1, 0.36), Vector3(0.0, 0.015, -0.02), sky)
	_box(gun, Vector3(0.07, 0.024, 0.3), Vector3(0.0, 0.03, -0.02), white)
	_cylinder(gun, 0.028, 0.48, Vector3(0.0, 0.03, -0.44), steel)
	_box(gun, Vector3(0.05, 0.014, 0.36), Vector3(0.0, 0.066, -0.42), white)
	for i: int in 4:
		_box(gun, Vector3(0.054, 0.018, 0.03), Vector3(0.0, 0.066, -0.29 - 0.08 * float(i)), steel)
	_cylinder(gun, 0.016, 0.3, Vector3(0.0, -0.012, -0.36), sky)
	_cylinder(gun, 0.037, 0.06, Vector3(0.0, 0.03, -0.7), yellow)
	_box(gun, Vector3(0.014, 0.03, 0.014), Vector3(0.0, 0.09, -0.58), _material(COLOR_PINK, 1.6, 0.0))
	# Große Trommel quer unter dem Gehäuse.
	var drum: Node3D = _new_part(slot, gun, "auto_shotgun/drum", Vector3(0.0, -0.115, -0.08))
	_cylinder(drum, 0.088, 0.07, Vector3.ZERO, yellow).rotation = Vector3(0.0, 0.0, PI * 0.5)
	_cylinder(drum, 0.092, 0.016, Vector3.ZERO, steel).rotation = Vector3(0.0, 0.0, PI * 0.5)
	_cylinder(drum, 0.03, 0.084, Vector3.ZERO, steel).rotation = Vector3(0.0, 0.0, PI * 0.5)
	_box(drum, Vector3(0.04, 0.07, 0.06), Vector3(0.0, 0.075, 0.0), steel)
	# Schaft und Griff.
	_box(gun, Vector3(0.05, 0.095, 0.3), Vector3(0.0, -0.01, 0.3), sky).rotation.x = -0.08
	_box(gun, Vector3(0.054, 0.13, 0.03), Vector3(0.0, -0.025, 0.46), steel)
	_box(gun, Vector3(0.042, 0.12, 0.055), Vector3(0.0, -0.09, 0.12), steel).rotation.x = -0.28
	_add_support_hand(gun, Vector3(-0.005, -0.055, -0.36))
	_add_muzzle(slot, gun, "auto_shotgun", Vector3(0.0, 0.03, -0.74))
	_add_grip_hand(gun, Vector3(0.0, -0.105, 0.13))


func _new_gun(slot: HandSlot, id: String) -> Node3D:
	var gun: Node3D = Node3D.new()
	gun.name = "Gun_%s" % id
	slot.holder.add_child(gun)
	slot.models[id] = gun
	return gun


func _new_part(slot: HandSlot, gun: Node3D, key: String, rest: Vector3) -> Node3D:
	var part: Node3D = Node3D.new()
	part.name = key.get_file().capitalize()
	part.position = rest
	gun.add_child(part)
	slot.parts[key] = part
	slot.part_rest[key] = rest
	return part


func _add_muzzle(slot: HandSlot, gun: Node3D, id: String, at: Vector3) -> void:
	var muzzle: Node3D = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = at
	gun.add_child(muzzle)
	slot.muzzles[id] = muzzle


## Rechte Hand am Griff mit Unterarm im Glitzer-Sakko, der nach unten rechts aus dem Bild läuft.
## (Bei der gespiegelten linken Waffe wird daraus die linke Hand.)
func _add_grip_hand(gun: Node3D, at: Vector3) -> void:
	_box(gun, Vector3(0.078, 0.095, 0.09), at, _material(COLOR_SKIN, 0.0, 0.0))
	var arm: MeshInstance3D = _box(gun, Vector3(0.09, 0.09, 0.44), at + Vector3(0.04, -0.09, 0.22),
		_material(COLOR_SLEEVE, 0.0, 0.1))
	arm.rotation = Vector3(0.42, 0.16, 0.0)


## Linke Hand einer Zweihand-Waffe (Vorderschaft, Tragegriff) mit Unterarm nach unten links.
func _add_support_hand(parent: Node3D, at: Vector3) -> void:
	_box(parent, Vector3(0.085, 0.07, 0.1), at, _material(COLOR_SKIN, 0.0, 0.0))
	var arm: MeshInstance3D = _box(parent, Vector3(0.085, 0.085, 0.42), at + Vector3(-0.125, -0.1, 0.17),
		_material(COLOR_SLEEVE, 0.0, 0.1))
	arm.rotation = Vector3(0.5, -0.62, 0.0)


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return _mesh_instance(parent, mesh, at, material)


## Zylinder entlang der Z-Achse (Lauf).
func _cylinder(parent: Node3D, radius: float, length: float, at: Vector3, material: Material) -> MeshInstance3D:
	return _tapered(parent, radius, radius, length, at, material)


## Zylinder entlang der Z-Achse mit verschiedenen Radien vorn (-Z) und hinten (Kegel, Trichter).
func _tapered(parent: Node3D, front_radius: float, back_radius: float, length: float, at: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	# Nach der Drehung zeigt die Oberseite des Zylinders nach hinten (+Z).
	mesh.top_radius = back_radius
	mesh.bottom_radius = front_radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	var instance: MeshInstance3D = _mesh_instance(parent, mesh, at, material)
	instance.rotation.x = PI * 0.5
	return instance


## Kugel (Elektrode, Knauf).
func _ball(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _mesh_instance(parent, mesh, at, material)


func _mesh_instance(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## Material je Farbe, Leuchten und Metallglanz (gleiche Angaben teilen sich ein Material).
func _material(color: Color, glow: float, metallic: float) -> StandardMaterial3D:
	var key: Array = [color, glow, metallic]
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.45
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	_materials[key] = material
	return material
