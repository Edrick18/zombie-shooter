extends CanvasLayer
## Modul: Oberfläche (scripts/ui).
## Rucksack-Bildschirm (Abschnitte 16 und 18): Raster, Hände, Ablage, Verkaufsfeld und Info-Tafel.
##
## Waffen liegen als Gegenstände im Raster: Was dort liegt, hält der Spieler in der Hand (höchstens
## zwei Hände, Anzeige über dem Raster). Gegenstände mit Sternen wirken nur auf die Waffen, die auf
## ihren Sternfeldern liegen: Jedes Sternfeld bekommt einen Stern in der Farbe seines Gegenstands,
## gefüllt mit Waffe darauf, sonst nur als Umriss (star_marks).
## Kameras (Abschnitt 22.1) liegen ebenfalls im Raster. Die Sterne der Kamera-Gegenstände
## leuchten nur auf Kameras, der Stern der Wiederholung auf Upgrade-Gegenständen und Kameras.
## Die Info-Tafel einer Kamera nennt ihre fertigen Werte aus Game.cameras.
##
## Der Bildschirm zeigt Game.backpack und ändert ihn nur über dessen Regeln (place, merge, store)
## und über Game.sell_item. Nach jeder gelungenen Änderung ruft er Game.sync_build(). Er öffnet
## sich bei Events.backpack_opened und schließt sich bei backpack_closed, run_started und game_over.
## process_mode ALWAYS, weil der Baum pausiert ist, solange der Rucksack offen ist.
##
## Bedienung: Gegenstand mit der linken Maustaste greifen, ziehen, loslassen. Über dem Raster wird
## er eingeräumt oder mit einem gleichen zusammengelegt, über der Ablage abgelegt, über dem
## Verkaufsfeld verkauft, überall sonst geht er zurück. R oder Rechtsklick dreht den gehaltenen
## Gegenstand. Doppelklick auf einen Gegenstand in der Ablage räumt ihn an die erste freie Stelle.
## Tab oder Esc schließen (nicht bei überfüllter Ablage).
##
## Das Halten ist reiner Anzeige-Zustand: Bis zum Loslassen bleibt der Rucksack unverändert. Ein
## misslungenes Ablegen muss deshalb nichts zurückstellen.
## Die Maus arbeitet nur über die öffentlichen Funktionen (pick_up, rotate_held, drop_on_cell,
## drop_on_storage, drop_on_sell, cancel_hold), Tests können dieselben Wege ohne Maus gehen.
## Alle Positionen (cell_at, cell_rect, storage_rect, set_pointer) sind lokale Koordinaten von board.

const UiStyle := preload("res://scripts/ui/hud.gd")
const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")

const LAYER: int = 15

## Ergebnis von drop_preview: passt, wird zusammengelegt, passt nicht.
const PREVIEW_FIT: int = 0
const PREVIEW_MERGE: int = 1
const PREVIEW_BAD: int = 2

# --- Optik-Zahlen ---
const STAGE_SIZE: Vector2 = Vector2(1200.0, 640.0)
## Kantenlänge eines Feldes im Raster.
const CELL: float = 68.0
const GRID_ORIGIN: Vector2 = Vector2(30.0, 104.0)
const SELL_RECT: Rect2 = Rect2(540.0, 104.0, 260.0, 120.0)
const STATS_RECT: Rect2 = Rect2(540.0, 236.0, 260.0, 130.0)
const DONE_RECT: Rect2 = Rect2(540.0, 378.0, 260.0, 66.0)
## Hände über dem Raster: Titel links, daneben ein Kasten je Hand.
const HANDS_TITLE_RECT: Rect2 = Rect2(30.0, 42.0, 136.0, 44.0)
const HAND_BOX_ORIGIN: Vector2 = Vector2(172.0, 42.0)
const HAND_BOX_SIZE: Vector2 = Vector2(128.0, 44.0)
const HAND_BOX_GAP: float = 6.0
const INFO_RECT: Rect2 = Rect2(826.0, 104.0, 344.0, 340.0)
const STORAGE_ORIGIN: Vector2 = Vector2(30.0, 492.0)
const STORAGE_SLOT: Vector2 = Vector2(96.0, 104.0)
const STORAGE_GAP: float = 8.0
## Breite der Ablage-Zeile. Liegt mehr darin, als in dieser Breite Platz hat, werden die Fächer schmaler.
const STORAGE_WIDTH: float = 1140.0
const HINT_TEXT: String = "Ziehen mit der Maus · Drehen: R oder Rechtsklick · Sterne zeigen, worauf ein Gegenstand wirkt · Zwei gleiche in gleicher Rarität: nächste Rarität · Tab: schließen"
const OVERFLOW_TEXT: String = "Ablage voll: etwas einräumen oder verkaufen"
## Warnungen, wenn eine Waffe mangels freier Hände nicht ins Raster passt.
const NO_HAND_TEXT: String = "Keine Hand frei: erst eine Waffe in die Ablage legen"
const NO_TWO_HANDS_TEXT: String = "Keine zwei Hände frei: erst die Waffe in die Ablage legen"
## So lange bleibt die Warnung nach einem abgelehnten Ablegen stehen (Sekunden).
const NOTICE_TIME: float = 4.0
const INFO_IDLE_TEXT: String = "Mit der Maus über einen Gegenstand fahren zeigt seine Wirkung.\nWaffen im Raster hältst du in der Hand: höchstens zwei Hände.\nEin Gegenstand mit Sternen wirkt nur auf Waffen, die auf seinen Sternen liegen.\nKameras schießen von selbst. Ihr Zubehör wirkt auf die Kamera auf seinen Sternen.\nRucksack-Teile an den Rand legen: Sie werden zu neuen Feldern."
## Abstand zwischen den Absätzen der Erklärung (jede Zeile von INFO_IDLE_TEXT ist ein Absatz).
const INFO_IDLE_PARAGRAPH_GAP: int = 9
## Schriftgröße des Wirkungstexts in der Info-Tafel und der (längeren) Erklärung ohne Gegenstand.
const INFO_TEXT_SIZE: int = 17
const INFO_IDLE_SIZE: int = 14
## Schriftgrößen der Info-Tafel für [Wirkungstext, Zusatzzeilen], von groß nach klein: Es gilt
## das erste Paar, mit dem alles in die Tafel passt.
const INFO_FIT_SIZES: Array[Array] = [[17, 15], [16, 14], [15, 14], [14, 13], [13, 12], [12, 11]]
## Abstand zwischen den Teilen der Info-Tafel und Zeilenabstand ihrer Labels.
const INFO_SEPARATION: float = 6.0
const INFO_LINE_SPACING: float = 3.0
## Sterne: Radius in der Ecke eines belegten Feldes und in der Mitte eines freien Feldes, Anteil
## des inneren Radius, Abstand mehrerer Sterne auf demselben Feld.
const STAR_RADIUS_CORNER: float = 9.5
const STAR_RADIUS_CENTER: float = 12.0
const STAR_INNER: float = 0.46
const STAR_STEP_CORNER: float = 15.0
const STAR_STEP_CENTER: float = 22.0
const CELL_FILL: Color = Color(0.22, 0.13, 0.42)
const CELL_EDGE: Color = Color(0.45, 0.33, 0.75)
const CELL_GHOST: Color = Color(1.0, 1.0, 1.0, 0.13)
const PIP_SIZE: Vector2 = Vector2(8.0, 6.0)
const PIP_GAP: float = 3.0
const NAME_FONT_SIZE: int = 14
const NAME_MIN_FONT_SIZE: int = 10
## So weit unter der Oberkante beginnt der Name einer Kamera (darüber sitzen die Sterne).
const CAMERA_NAME_TOP: float = 17.0
## Namen der Werte, die Verstärker erhöhen (ItemDefs.stat).
const STAT_NAMES: Dictionary = {"damage": "Waffenschaden", "reload": "Nachladetempo", "points": "Punkte"}

## Trennstellen der Namen, damit lange Namen in ein Feld passen: "|" trennt zusammengesetzte
## Wörter (bevorzugt), "'" trennt Silben (nur wenn es sonst nicht passt). Stimmt ein Eintrag nicht
## mehr mit dem Namen aus ItemDefs überein (oder fehlt er), wird nur noch an Bindestrich und
## Leerzeichen getrennt.
const NAME_HYPHENS: Dictionary = {
	"pistol": "Dienst|pis'to'le",
	"revolver": "Kan'di'da'ten|schreck",
	"smg": "Quo'ten|ham'mer",
	"sawed_off": "Blitz|run'de",
	"shotgun": "Pub'li'kums|jo'ker",
	"rifle": "Dau'er|bren'ner",
	"sniper": "Fern|be'die'nung",
	"minigun": "Ap'plaus|ma'schi'ne",
	"rocket_launcher": "Show|fi'na'le",
	"chain_lightning": "Stark|strom-Spon'sor",
	"pierce": "Spe'zial|mu'ni'tion",
	"burn": "Feuer|show",
	"lifesteal": "Blut|spen'de-Ak'tion",
	"max_hp": "Stunt|dou'ble",
	"corpse_explosion": "Kon'fet'ti-Ka'no'ne",
	"reload_shockwave": "Wer'be|pau'se",
	"drone": "Ka'me'ra|droh'ne",
	"speed": "Tur'bo-Turn|schu'he",
	"luck": "Pub'li'kums|lieb'ling",
	"spotlight": "Schein|wer'fer",
	"speed_loader": "La'de|hil'fe",
	"piggy_bank": "Spar|schwein",
	"extra_shot": "Zu'ga'be",
	"poison": "Kan'ti'nen|es'sen",
	"crit": "Glücks|rad",
	"big_mag": "Über|län'ge",
	"scope": "Te'le|promp'ter",
	"fire_rate": "Schnell|durch'lauf",
	"shield": "Si'cher'heits|glas",
	"kill_heal": "Trost|pflas'ter",
	"disco_ball": "Dis'co|ku'gel",
	"jammer": "Stör|sen'der",
	"dash": "Not|aus'gang",
	"replay": "Wie'der|ho'lung",
	"bag_tiny": "Bauch|ta'sche",
	"bag_small": "Ju'te|beu'tel",
	"bag_medium": "Sport|ta'sche",
	"bag_large": "Rei'se|kof'fer",
	# Abschnitt 22: neue Gegenstände, Kameras, Kamera-Gegenstände und Waffen.
	"frost": "Tro'cken|eis",
	"opener": "Er'öff'nungs|gag",
	"punchline": "Schluss|poin'te",
	"ricochet": "Quer|schlä'ger",
	"thorns": "Kak'tus-Re'qui'si'te",
	"revive": "Zwei'te Staf'fel",
	"snack": "Pau'sen|snack",
	"mine": "Re'qui'si'ten|bom'be",
	"cam_tele": "Te'le-Ka'me'ra",
	"cam_flash": "Blitz|licht-Ka'me'ra",
	"cam_slow": "Zeit|lu'pen-Ka'me'ra",
	"cam_director": "Re'gie-Ka'me'ra",
	"cam_lens": "Gro'ßes Ob'jek'tiv",
	"cam_zoom": "Zoom",
	"cam_battery": "Ak'ku|pack",
	"cam_second": "Zweit|ka'me'ra",
	"cam_uplink": "Sen'de|lei'tung",
	"burst_pistol": "Drei'er|pack",
	"nail_gun": "Büh'nen|bau",
	"machine_pistol": "Wer'be|block",
	"crossbow": "Ziel|ge'ra'de",
	"grenade_launcher": "Knall|ef'fekt",
	"flamethrower": "Hei'ße Pha'se",
	"beam": "Rot|licht",
	"tesla": "Kurz|schluss",
	"lmg": "Ma'ra'thon|sen'dung",
	"auto_shotgun": "Zu'schau'er|fra'ge",
}

## Gezeichnete Fläche für Raster, Ablage und Verkaufsfeld. Nimmt die Maus an.
var board: Control
## Liegt über allem und zeichnet nur den gehaltenen Gegenstand.
var overlay: Control
var headline_label: Label
var points_label: Label
var storage_label: Label
## Rote Warnung (nur sichtbar, wenn es etwas zu warnen gibt): überfüllte Ablage oder eine Waffe,
## für die keine Hand frei ist.
var warning_label: Label
var sell_title_label: Label
## Zeigt beim Halten die Punkte, die der Gegenstand beim Verkaufen gibt.
var sell_value_label: Label
## Freie Felder, Hände und Zusatzwerte aus Verstärkern.
var stats_label: Label
## Titel der Hände über dem Raster: "HÄNDE 1 / 2". Was jede Hand hält, steht in hand_slots().
var hands_label: Label
var info_name_label: Label
var info_subtitle_label: Label
var info_text_label: Label
var info_extra_label: Label
var info_sell_label: Label
var hint_label: Label
## Knopf "FERTIG" (schließt den Rucksack).
var done_button: Button

var _headline: PanelContainer
var _grid_box: StyleBoxFlat
var _slot_box: StyleBoxFlat
var _slot_over_box: StyleBoxFlat
var _sell_box: StyleBoxFlat
var _sell_hot_box: StyleBoxFlat
## Gerade gehaltener Gegenstand, -1 = keiner.
var _held_uid: int = -1
var _held_rot: int = 0
## Feld der gehaltenen Form, das unter dem Zeiger liegt.
var _grab: Vector2i = Vector2i.ZERO
## Zeiger in Koordinaten von board.
var _pointer: Vector2 = Vector2(-10000.0, -10000.0)
var _hover_uid: int = -1
## Neuer Gegenstand aus der Kiste (wird hervorgehoben), -1 = keiner.
var _new_uid: int = -1
var _pulse: float = 0.0
## Warnung nach einem abgelehnten Ablegen und wie lange sie noch steht (Sekunden).
var _notice: String = ""
var _notice_left: float = 0.0
## Gemerkte Zeilenumbrüche der Namen: Schlüssel -> { "size", "lines", "line_height" }.
var _name_cache: Dictionary = {}


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	Events.backpack_opened.connect(_on_backpack_opened)
	Events.backpack_closed.connect(_hide)
	Events.run_started.connect(_hide)
	Events.game_over.connect(_on_game_over)
	Events.build_changed.connect(_refresh)
	Events.points_changed.connect(_on_points_changed)


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse = fmod(_pulse + delta, 1000.0)
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_update_warning()
	board.queue_redraw()
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("backpack"):
		if Game.state == Game.State.PLAYING:
			get_viewport().set_input_as_handled()
			Game.open_backpack()
		elif Game.state == Game.State.PACKING:
			get_viewport().set_input_as_handled()
			request_close()
		return
	if Game.state != Game.State.PACKING or not visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		request_close()
	elif _held_uid != -1 and (event.is_action_pressed("reload") or _is_right_press(event)):
		get_viewport().set_input_as_handled()
		rotate_held()


# --- Öffentliche Schnittstelle ---------------------------------------------------------

## Ist der Rucksack-Bildschirm gerade offen?
func is_open() -> bool:
	return visible


## Schließt den Rucksack über Game.close_backpack(). Ein gehaltener Gegenstand geht vorher zurück.
## Gibt false zurück, wenn Game ablehnt (überfüllte Ablage: Die Warnung blinkt auf).
func request_close() -> bool:
	if Game.state != Game.State.PACKING:
		return false
	_notice_left = 0.0
	cancel_hold()
	if Game.close_backpack():
		return true
	_refresh()
	if warning_label.visible:
		UiStyle.pop(warning_label, 1.25, 0.25)
	return false


## uid des gehaltenen Gegenstands, -1 wenn nichts gehalten wird.
func held_uid() -> int:
	return _held_uid


## Drehung des gehaltenen Gegenstands (Vierteldrehungen im Uhrzeigersinn), 0 ohne Gegenstand.
func held_rotation() -> int:
	return _held_rot if _held_uid != -1 else 0


## Nimmt einen Gegenstand aus Raster oder Ablage in die Hand. Der Rucksack ändert sich dabei
## noch nicht. false, wenn der Bildschirm zu ist oder es den Gegenstand nicht gibt.
func pick_up(uid: int) -> bool:
	if not visible or not Game.backpack.has_item(uid):
		return false
	if _held_uid != -1:
		cancel_hold()
	var entry: Dictionary = Game.backpack.item(uid)
	_held_uid = uid
	_held_rot = int(entry["rot"])
	_grab = ItemDefs.cells(str(entry["id"]), _held_rot)[0]
	_refresh()
	return true


## Dreht den gehaltenen Gegenstand um 90 Grad im Uhrzeigersinn.
func rotate_held() -> void:
	if _held_uid == -1:
		return
	var entry: Dictionary = Game.backpack.item(_held_uid)
	if entry.is_empty():
		cancel_hold()
		return
	_grab = _rotated_grab(str(entry["id"]), _held_rot, _grab)
	_held_rot = posmod(_held_rot + 1, 4)
	_refresh()


## Legt den gehaltenen Gegenstand so ab, dass cell die linke obere Ecke seiner Form ist. Liegt auf
## einem der bedeckten Felder ein gleicher Gegenstand gleicher Rarität, wird zusammengelegt, sonst
## eingeräumt. Passt er nicht, geht er zurück an seinen alten Platz und es kommt false. Eine
## Waffe, für die keine Hand frei ist, passt nicht: Die Warnung sagt, warum.
func drop_on_cell(cell: Vector2i) -> bool:
	if _held_uid == -1:
		return false
	var pack: BackpackState = Game.backpack
	var uid: int = _held_uid
	var entry: Dictionary = pack.item(uid)
	if entry.is_empty():
		cancel_hold()
		return false
	var covered: Array[Vector2i] = BackpackState.shape_at(str(entry["id"]), cell, _held_rot)
	var target: int = _merge_target(uid, covered)
	var done: bool = target != -1 and pack.merge(uid, target)
	if not done:
		done = pack.place(uid, cell, _held_rot)
	if not done:
		if not pack.has_free_hands(uid):
			_show_notice(_no_hands_text(uid))
		cancel_hold()
		return false
	_release(uid, true)
	Game.sync_build()
	return true


## Legt den gehaltenen Gegenstand in die Ablage (ein eingeräumter wirkt danach nicht mehr).
func drop_on_storage() -> bool:
	if _held_uid == -1:
		return false
	var pack: BackpackState = Game.backpack
	var uid: int = _held_uid
	if not pack.has_item(uid):
		cancel_hold()
		return false
	var was_placed: bool = pack.is_placed(uid)
	if was_placed and not pack.store(uid):
		cancel_hold()
		return false
	pack.set_rotation(uid, _held_rot)
	_release(uid, was_placed)
	if was_placed:
		Game.sync_build()
	else:
		_refresh()
	return true


## Verkauft den gehaltenen Gegenstand (Game.sell_item). true, wenn er verkauft wurde.
func drop_on_sell() -> bool:
	if _held_uid == -1:
		return false
	var uid: int = _held_uid
	if not Game.backpack.has_item(uid):
		cancel_hold()
		return false
	_release(uid, true)
	var amount: int = Game.sell_item(uid)
	_refresh()
	return amount > 0


## Lässt den gehaltenen Gegenstand los: Er liegt wieder dort, wo er war.
func cancel_hold() -> void:
	if _held_uid == -1:
		return
	_held_uid = -1
	_refresh()


## Räumt einen Gegenstand aus der Ablage an die erste passende Stelle (Doppelklick).
func quick_place(uid: int) -> bool:
	var pack: BackpackState = Game.backpack
	if not visible or not pack.has_item(uid) or pack.is_placed(uid):
		return false
	if _held_uid != -1:
		cancel_hold()
	if not pack.auto_place(uid):
		if not pack.has_free_hands(uid):
			_show_notice(_no_hands_text(uid))
		return false
	_release(uid, true)
	Game.sync_build()
	return true


## Feld des Rasters unter einer Position (Koordinaten von board), Vector2i(-1, -1) außerhalb.
func cell_at(stage_pos: Vector2) -> Vector2i:
	if not grid_rect().has_point(stage_pos):
		return Vector2i(-1, -1)
	var local: Vector2 = (stage_pos - GRID_ORIGIN) / CELL
	return Vector2i(clampi(int(floor(local.x)), 0, BackpackState.COLS - 1), clampi(int(floor(local.y)), 0, BackpackState.ROWS - 1))


## Rechteck eines Feldes des Rasters (Koordinaten von board).
func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(cell) * CELL, Vector2(CELL, CELL))


## Rechteck des ganzen Rasters (alle COLS mal ROWS Felder).
func grid_rect() -> Rect2:
	return Rect2(GRID_ORIGIN, Vector2(float(BackpackState.COLS), float(BackpackState.ROWS)) * CELL)


## Rechteck des Fachs index in der Ablage. Fächer ab STORAGE_CAPACITY zeigen den Überlauf.
func storage_rect(index: int) -> Rect2:
	var count: int = maxi(Game.backpack.storage_items().size(), BackpackState.STORAGE_CAPACITY)
	var width: float = minf(STORAGE_SLOT.x, (STORAGE_WIDTH - STORAGE_GAP * float(count - 1)) / float(count))
	return Rect2(STORAGE_ORIGIN + Vector2(float(index) * (width + STORAGE_GAP), 0.0), Vector2(width, STORAGE_SLOT.y))


## Fläche, über der ein Loslassen "in die Ablage" bedeutet.
func storage_area() -> Rect2:
	return Rect2(STORAGE_ORIGIN, Vector2(STORAGE_WIDTH, STORAGE_SLOT.y)).grow(8.0)


## Fläche des Verkaufsfelds.
func sell_rect() -> Rect2:
	return SELL_RECT


## uid des Gegenstands unter einer Position (Raster oder Ablage), -1 wenn dort keiner liegt.
func item_at(board_pos: Vector2) -> int:
	var pack: BackpackState = Game.backpack
	var cell: Vector2i = cell_at(board_pos)
	if cell.x >= 0:
		return pack.occupant(cell)
	var storage: Array[Dictionary] = pack.storage_items()
	for i: int in storage.size():
		if storage_rect(i).has_point(board_pos):
			return int(storage[i]["uid"])
	return -1


## Setzt den Zeiger (Koordinaten von board). Der gehaltene Gegenstand folgt ihm.
func set_pointer(board_pos: Vector2) -> void:
	_pointer = board_pos
	if _held_uid == -1:
		var hovered: int = item_at(board_pos)
		if hovered != _hover_uid:
			_hover_uid = hovered
			_update_info()
	else:
		# Über einem gleichen Gegenstand (Zusammenlegen) braucht eine Waffe keine freie Hand.
		_update_warning()
	board.queue_redraw()
	overlay.queue_redraw()


## Lässt den gehaltenen Gegenstand an einer Position los: über dem Raster einräumen oder
## zusammenlegen, über der Ablage ablegen, über dem Verkaufsfeld verkaufen, sonst zurück.
func drop_at(board_pos: Vector2) -> bool:
	if _held_uid == -1:
		return false
	_pointer = board_pos
	var result: bool = false
	if grid_rect().has_point(board_pos):
		result = drop_on_cell(cell_at(board_pos) - _grab)
	elif storage_area().has_point(board_pos):
		result = drop_on_storage()
	elif SELL_RECT.has_point(board_pos):
		result = drop_on_sell()
	else:
		cancel_hold()
	_hover_uid = item_at(board_pos)
	_update_info()
	return result


## Was beim Loslassen über dem Raster passieren würde: leer, wenn nichts gehalten wird oder der
## Zeiger nicht über dem Raster steht. Sonst { "pos": Vector2i (linke obere Ecke),
## "cells": Array[Vector2i], "kind": PREVIEW_FIT / PREVIEW_MERGE / PREVIEW_BAD, "merge": uid oder -1 }.
func drop_preview() -> Dictionary:
	if _held_uid == -1 or not grid_rect().has_point(_pointer):
		return {}
	var pack: BackpackState = Game.backpack
	var entry: Dictionary = pack.item(_held_uid)
	if entry.is_empty():
		return {}
	var pos: Vector2i = cell_at(_pointer) - _grab
	var covered: Array[Vector2i] = BackpackState.shape_at(str(entry["id"]), pos, _held_rot)
	var target: int = _merge_target(_held_uid, covered)
	var kind: int = PREVIEW_BAD
	if target != -1:
		kind = PREVIEW_MERGE
	elif pack.can_place(_held_uid, pos, _held_rot):
		kind = PREVIEW_FIT
	return {"pos": pos, "cells": covered, "kind": kind, "merge": target}


## Texte der Info-Tafel für einen Gegenstand: { "name", "subtitle", "text", "extra", "sell" }.
## Leer, wenn es ihn nicht gibt.
func describe(uid: int) -> Dictionary:
	var pack: BackpackState = Game.backpack
	var entry: Dictionary = pack.item(uid)
	if entry.is_empty():
		return {}
	var id: String = str(entry["id"])
	var level: int = int(entry["level"])
	var placed: bool = bool(entry["placed"])
	var extra: PackedStringArray = PackedStringArray()
	if ItemDefs.is_bag(id):
		extra.append("Wird beim Einräumen verbraucht.")
	elif ItemDefs.is_weapon(id):
		if placed:
			var hand_note: String = _hand_note(uid)
			if not hand_note.is_empty():
				extra.append(hand_note)
			var mods: String = _names_of(pack.mods_of(uid))
			extra.append("Kein Gegenstand wirkt darauf." if mods.is_empty() else "Darauf wirken: %s" % mods)
		else:
			extra.append("Liegt in der Ablage: Du hältst sie nicht in der Hand.")
			if not pack.has_free_hands(uid):
				extra.append(_no_hands_text(uid) + ".")
	elif ItemDefs.is_camera(id):
		if placed:
			extra.append_array(_camera_notes(uid))
		else:
			extra.append("Liegt in der Ablage und filmt noch nicht.")
	else:
		if not placed:
			extra.append("Liegt in der Ablage und wirkt noch nicht.")
		else:
			var targets: Array[int] = pack.star_targets(uid)
			var active: bool = pack.is_active(uid)
			if ItemDefs.has_stars(id):
				if active:
					extra.append("Wirkt auf: %s" % _names_of(targets))
				elif ItemDefs.is_replay(id):
					extra.append("Wirkt gerade auf keinen Gegenstand: Stern auf einen Upgrade-Gegenstand oder eine Kamera legen.")
				elif ItemDefs.is_camera_mod(id):
					extra.append("Wirkt gerade auf keine Kamera: Stern auf eine Kamera legen.")
				else:
					extra.append("Wirkt gerade auf keine Waffe: Stern auf eine Waffe legen.")
			elif CameraDefs.is_mod(id):
				# Sendeleitung: wirkt ohne Sterne auf jede Kamera im Rucksack.
				var camera_count: int = Game.cameras.size()
				if camera_count <= 0:
					extra.append("Wirkt gerade auf keine Kamera: Es liegt keine im Rucksack.")
				else:
					extra.append("Wirkt auf %s." % ("eine Kamera" if camera_count == 1 else "%d Kameras" % camera_count))
			# Eine Wiederholung auf diesem Gegenstand: Er zählt mehrfach.
			var copies: int = pack.copy_levels(uid).size()
			if copies > 1:
				extra.append("Zählt %d-fach durch die Wiederholung." % copies)
			# Verstärker nennen ihren Beitrag nur, solange sie wirken.
			if active and not ItemDefs.stat(id).is_empty():
				var stat_name: String = str(STAT_NAMES.get(ItemDefs.stat(id), ItemDefs.stat(id)))
				extra.append("Bringt gerade +%s %% %s%s." % [UpgradeDefs.format_percent(pack.stat_contribution(uid)), stat_name,
						" je Waffe" if targets.size() > 1 else ""])
		if ItemDefs.is_upgrade(id):
			extra.append_array(_synergy_notes(id))
	return {
		"name": ItemDefs.display_name(id),
		"subtitle": ItemDefs.subtitle(id, level),
		"text": ItemDefs.description(id, level),
		"extra": "\n".join(extra),
		"sell": "Verkaufswert: %s Punkte" % UiStyle.format_int(ItemDefs.sell_value(id, level)),
	}


## Zeilen der Info-Tafel für eine eingeräumte Kamera: ihre fertigen Werte aus Game.cameras
## (Schaden, Abstand, Reichweite und je nach Typ Durchschlag, Verlangsamung, Mehr-Schaden,
## zweites Ziel), wie viele Exemplare durch Wiederholungen filmen und was auf sie wirkt.
func _camera_notes(uid: int) -> PackedStringArray:
	var notes: PackedStringArray = PackedStringArray()
	var pack: BackpackState = Game.backpack
	var entry: Dictionary = Game.camera_entry("%d:0" % uid)
	if not entry.is_empty():
		notes.append("Jetzt: %s" % camera_stats_text(entry))
	var copies: int = pack.copy_levels(uid).size()
	if copies > 1:
		notes.append("Zählt %d-fach durch die Wiederholung: %d Kameras filmen." % [copies, copies])
	var mods: String = _names_of(pack.mods_of(uid))
	var uplinks: int = Game.upgrades.copies(CameraDefs.MOD_UPLINK).size()
	if uplinks > 0:
		var uplink_name: String = ItemDefs.display_name(CameraDefs.MOD_UPLINK)
		var uplink_text: String = uplink_name if uplinks == 1 else "%d × %s" % [uplinks, uplink_name]
		mods = uplink_text if mods.is_empty() else "%s, %s" % [mods, uplink_text]
	notes.append("Kein Gegenstand wirkt darauf." if mods.is_empty() else "Darauf wirken: %s" % mods)
	return notes


## Die fertigen Werte einer Kamera als eine Zeile, aus einem Eintrag von Game.cameras:
## "Schaden 21 · alle 0,8 s · Reichweite 18 m", dazu je nach Kamera "Durchschlag 2",
## "Verlangsamung 30 %", "Markierte nehmen 20 % mehr Schaden" und "zweites Ziel 40 %".
static func camera_stats_text(entry: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var damage: float = float(entry.get("damage", 0.0))
	if damage > 0.0:
		parts.append("Schaden %s" % UpgradeDefs.format_number(snappedf(damage, 0.1)))
	parts.append("alle %s s" % UpgradeDefs.format_number(float(entry.get("interval", 0.0))))
	parts.append("Reichweite %s m" % UpgradeDefs.format_number(snappedf(float(entry.get("range", 0.0)), 0.1)))
	var pierce: int = int(entry.get("pierce", 0))
	if pierce > 0:
		parts.append("Durchschlag %d" % pierce)
	var slow: float = float(entry.get("slow", 0.0))
	if slow > 0.0:
		parts.append("Verlangsamung %s %%" % UpgradeDefs.format_percent(slow))
	var mark: float = float(entry.get("mark", 0.0))
	if mark > 0.0:
		parts.append("Markierte nehmen %s %% mehr Schaden" % UpgradeDefs.format_percent(mark))
	var second: float = float(entry.get("second", 0.0))
	if second > 0.0:
		parts.append("zweites Ziel %s %%" % UpgradeDefs.format_percent(second))
	return " · ".join(parts)


## Alle Sterne, die gerade gezeichnet werden: je Stern { "cell": Vector2i, "owner": int (uid des
## Gegenstands), "lit": bool (gefüllt: dort liegt etwas, worauf der Stern wirkt: eine Waffe, bei
## Kamera-Zubehör eine Kamera, bei der Wiederholung ein Gegenstand oder eine Kamera), "preview": bool (Stern des
## gehaltenen Gegenstands an der Stelle der Vorschau), "focus": bool (hervorgehoben) }.
## Sterne außerhalb des Rasters fehlen. Der gehaltene Gegenstand hat nur Sterne, solange er über
## dem Raster schwebt (und nicht zusammengelegt wird). Eine gehaltene Waffe, die an der Stelle der
## Vorschau passt, zählt dort und nicht mehr an ihrem alten Platz.
func star_marks() -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var pack: BackpackState = Game.backpack
	var held_id: String = str(pack.item(_held_uid).get("id", "")) if _held_uid != -1 else ""
	var preview: Dictionary = drop_preview()
	var preview_kind: int = int(preview.get("kind", PREVIEW_BAD))
	var weapon_cells: Array[Vector2i] = []
	# Ein gehaltener Gegenstand, der an der Stelle der Vorschau passt, zählt dort: Sterne anderer
	# Gegenstände leuchten, wenn sie auf ihn wirken würden (Waffen-Sterne auf eine Waffe, der Stern
	# der Wiederholung auf einen Upgrade-Gegenstand).
	var weapon_moves: bool = not preview.is_empty() and preview_kind == PREVIEW_FIT and ItemDefs.has(held_id) and not ItemDefs.is_bag(held_id)
	if weapon_moves:
		weapon_cells = preview["cells"]
	# Ohne gehaltenen Gegenstand: Sterne des Gegenstands unter dem Zeiger und Sterne auf der Waffe
	# unter dem Zeiger sind hervorgehoben.
	var hover_cells: Array[Vector2i] = []
	if _held_uid == -1 and _hover_uid != -1 and not pack.mods_of(_hover_uid).is_empty():
		hover_cells = pack.cells_of(_hover_uid)
	for entry: Dictionary in pack.placed_items():
		var uid: int = int(entry["uid"])
		if uid == _held_uid or not ItemDefs.has_stars(str(entry["id"])):
			continue
		for cell: Vector2i in pack.star_cells_of(uid):
			if not BackpackState.in_bounds(cell):
				continue
			var lit: bool = pack.is_star_lit(uid, cell)
			var would_hit: bool = weapon_cells.has(cell) and ItemDefs.star_hits(str(entry["id"]), held_id)
			if weapon_moves:
				lit = would_hit or (lit and pack.occupant(cell) != _held_uid)
			var focus: bool = would_hit
			if _held_uid == -1:
				focus = uid == _hover_uid or (lit and hover_cells.has(cell))
			marks.append({"cell": cell, "owner": uid, "lit": lit, "preview": false, "focus": focus})
	if not preview.is_empty() and preview_kind != PREVIEW_MERGE and ItemDefs.has_stars(held_id):
		for cell: Vector2i in BackpackState.stars_at(held_id, preview["pos"] as Vector2i, _held_rot):
			if not BackpackState.in_bounds(cell):
				continue
			var other: int = pack.occupant(cell)
			var hits: bool = other != -1 and other != _held_uid and ItemDefs.star_hits(held_id, str(pack.item(other)["id"]))
			marks.append({"cell": cell, "owner": _held_uid, "lit": hits, "preview": true, "focus": true})
	return marks


## Was jede Hand hält, von links nach rechts (aus Game.loadout). Je Kasten der Anzeige:
## { "caption": String, "name": String, "uid": int (Waffe, 0 = Dienstpistole als Notlösung,
## -1 = freie Hand), "id": String, "level": int, "span": int (1 oder 2 Hände breit),
## "stopgap": bool }. Zusammen sind die Kästen immer zwei Hände breit.
func hand_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var used: int = 0
	for weapon: Dictionary in Game.loadout:
		var uid: int = int(weapon.get("uid", -1))
		var id: String = str(weapon.get("id", ""))
		if uid <= 0:
			# Keine Waffe im Rucksack: Game gibt dem Spieler die Dienstpistole.
			slots.append({"caption": "Keine Waffe im Rucksack", "name": "%s (Notlösung)" % ItemDefs.display_name(id),
					"uid": 0, "id": id, "level": 1, "span": Balance.PLAYER_HANDS, "stopgap": true})
			return slots
		if used >= Balance.PLAYER_HANDS:
			break
		var span: int = clampi(int(weapon.get("hands", 1)), 1, Balance.PLAYER_HANDS - used)
		var caption: String = "Beide Hände" if span >= 2 else ("Linke Hand" if used == 0 else "Rechte Hand")
		slots.append({"caption": caption, "name": ItemDefs.display_name(id), "uid": uid, "id": id,
				"level": int(weapon.get("level", 1)), "span": span, "stopgap": false})
		used += span
	while used < Balance.PLAYER_HANDS:
		slots.append({"caption": "Linke Hand" if used == 0 else "Rechte Hand", "name": "frei", "uid": -1, "id": "",
				"level": 0, "span": 1, "stopgap": false})
		used += 1
	return slots


## Die Hände als eine Zeile Text: "HÄNDE 1 / 2 · Linke Hand: Dienstpistole · Rechte Hand: frei".
func hands_text() -> String:
	var parts: PackedStringArray = PackedStringArray([hands_label.text])
	for slot: Dictionary in hand_slots():
		parts.append("%s: %s" % [str(slot["caption"]), str(slot["name"])])
	return " · ".join(parts)


## Zeilenumbruch eines Namens für eine Fläche: { "size": int (Schriftgröße), "lines":
## PackedStringArray, "line_height": float }. Zuerst wird nur an Bindestrich und Leerzeichen
## getrennt, dann an den Wortfugen aus NAME_HYPHENS, zuletzt an den Silben. Für einen schöneren
## Umbruch darf die Schrift zwei bis drei Größen kleiner sein. Was auch in der kleinsten Schrift
## nicht passt, endet mit "…".
func name_layout(id: String, max_width: float, max_height: float, start_size: int = NAME_FONT_SIZE,
		min_size: int = NAME_MIN_FONT_SIZE) -> Dictionary:
	var key: String = "%s|%d|%d|%d|%d" % [id, roundi(max_width), roundi(max_height), start_size, min_size]
	if _name_cache.has(key):
		return _name_cache[key] as Dictionary
	var font: Font = UiStyle.show_font()
	var first_size: int = maxi(start_size, min_size)
	var result: Dictionary = {}
	for depth: int in 3:
		var pieces: Array[Dictionary] = _name_pieces(id, depth)
		var last_size: int = min_size if depth == 2 else maxi(min_size, first_size - 2 - depth)
		var font_size: int = first_size
		while font_size >= last_size and result.is_empty():
			var attempt: Dictionary = _layout_attempt(pieces, font, font_size, max_width, max_height, false)
			if depth == 2:
				# Ganze Wörter beisammen zu lassen ist schöner, solange es keine Zeile mehr kostet.
				var by_words: Dictionary = _layout_attempt(pieces, font, font_size, max_width, max_height, true)
				var fewer_lines: bool = (by_words["lines"] as PackedStringArray).size() <= (attempt["lines"] as PackedStringArray).size()
				if bool(by_words["fits"]) and (fewer_lines or not bool(attempt["fits"])):
					attempt = by_words
			if bool(attempt["fits"]):
				result = attempt
			font_size -= 1
		if not result.is_empty():
			break
	if result.is_empty():
		result = _layout_attempt(_name_pieces(id, 2), font, min_size, max_width, max_height, false)
		var max_lines: int = maxi(1, int(floor(max_height / float(result["line_height"]))))
		result["lines"] = _clip_lines(result["lines"] as PackedStringArray, max_lines, font, min_size, max_width)
	_name_cache[key] = result
	return result


# --- Aufbau ---------------------------------------------------------------------------

func _build() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim: ColorRect = UiStyle.make_dim(Color(UiStyle.COL_INK, 0.9))
	dim.name = "Dim"
	root.add_child(dim)
	var sunburst: UiStyle.Sunburst = UiStyle.Sunburst.new()
	sunburst.name = "Sunburst"
	sunburst.ray_color = Color(UiStyle.COL_PURPLE, 0.1)
	sunburst.speed = 0.05
	sunburst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sunburst)
	var stage: Control = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.anchor_box(stage, Vector2(0.5, 0.5), -STAGE_SIZE * 0.5, STAGE_SIZE)
	root.add_child(stage)

	_grid_box = UiStyle.make_box(UiStyle.COL_PANEL, UiStyle.COL_CYAN, 4, 0.0, 8)
	_slot_box = UiStyle.make_box(Color(0.0, 0.0, 0.0, 0.45), Color(UiStyle.COL_CYAN, 0.55), 3, 0.0, 6)
	_slot_box.shadow_size = 0
	_slot_over_box = UiStyle.make_box(Color(0.4, 0.02, 0.05, 0.6), UiStyle.COL_RED, 3, 0.0, 6)
	_slot_over_box.shadow_size = 0
	_sell_box = UiStyle.make_box(Color(0.3, 0.1, 0.05, 0.9), UiStyle.COL_ORANGE, 4, 0.0, 8)
	_sell_hot_box = UiStyle.make_box(Color(0.75, 0.3, 0.05), UiStyle.COL_YELLOW, 6, 0.0, 8)

	# Zeichenfläche zuerst: Tafeln und Texte liegen darüber, die Maus geht trotzdem an sie
	# (alle Texte ignorieren die Maus), nur der Knopf FERTIG fängt seine Klicks selbst.
	board = Control.new()
	board.name = "Board"
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(board)
	board.draw.connect(_draw_board)
	board.gui_input.connect(_on_board_input)
	board.mouse_exited.connect(_on_board_mouse_exited)

	_headline = UiStyle.make_headline("RUCKSACK", 44, UiStyle.COL_PURPLE, UiStyle.COL_YELLOW, UiStyle.COL_CYAN)
	_headline.name = "Headline"
	_headline.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_headline.pivot_offset_ratio = Vector2(0.5, 0.5)
	_headline.rotation_degrees = -2.0
	UiStyle.anchor_box(_headline, Vector2(0.5, 0.0), Vector2(0.0, 0.0), Vector2.ZERO)
	stage.add_child(_headline)
	headline_label = _headline.get_node("Label") as Label

	points_label = _add_label(stage, "Points", "", 26, UiStyle.COL_YELLOW, true,
			Rect2(INFO_RECT.position.x, 40.0, INFO_RECT.size.x, 40.0))
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	hands_label = _add_label(stage, "Hands", "", 22, UiStyle.COL_YELLOW, true, HANDS_TITLE_RECT)
	hands_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	sell_title_label = _add_label(stage, "SellTitle", "VERKAUFEN", 28, UiStyle.COL_YELLOW, true,
			Rect2(SELL_RECT.position + Vector2(0.0, 12.0), Vector2(SELL_RECT.size.x, 40.0)))
	sell_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_value_label = _add_label(stage, "SellValue", "", 17, UiStyle.COL_WHITE, false,
			Rect2(SELL_RECT.position + Vector2(10.0, 54.0), Vector2(SELL_RECT.size.x - 20.0, 56.0)))
	sell_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sell_value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var stats_plate: Panel = UiStyle.make_plate(UiStyle.COL_PANEL, Color(UiStyle.COL_CYAN, 0.6), 3, 0.0, 6)
	stats_plate.name = "StatsPlate"
	UiStyle.anchor_box(stats_plate, Vector2.ZERO, STATS_RECT.position, STATS_RECT.size)
	stage.add_child(stats_plate)
	stats_label = _add_label(stage, "Stats", "", 14, UiStyle.COL_WHITE, false, STATS_RECT.grow(-10.0))
	stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	done_button = UiStyle.make_button("FERTIG", UiStyle.COL_GREEN, 30)
	done_button.name = "Done"
	# Kein Tastatur-Fokus: Sonst verbraucht die Oberfläche die Tab-Taste für den Fokuswechsel.
	done_button.focus_mode = Control.FOCUS_NONE
	done_button.custom_minimum_size = DONE_RECT.size
	done_button.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(done_button, Vector2.ZERO, DONE_RECT.position, DONE_RECT.size)
	stage.add_child(done_button)
	done_button.pressed.connect(_on_done_pressed)

	_build_info(stage)

	storage_label = _add_label(stage, "StorageTitle", "ABLAGE", 22, UiStyle.COL_YELLOW, true,
			Rect2(STORAGE_ORIGIN.x, STORAGE_ORIGIN.y - 36.0, 190.0, 32.0))
	storage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning_label = _add_label(stage, "Warning", OVERFLOW_TEXT, 19, UiStyle.COL_RED, false,
			Rect2(STORAGE_ORIGIN.x + 200.0, STORAGE_ORIGIN.y - 36.0, 620.0, 32.0))
	warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning_label.pivot_offset_ratio = Vector2(0.0, 0.5)
	warning_label.visible = false
	hint_label = _add_label(stage, "Hint", HINT_TEXT, UiStyle.fit_font_size(HINT_TEXT, 15, STAGE_SIZE.x - 30.0, false, 11),
			UiStyle.COL_CYAN, false, Rect2(0.0, STORAGE_ORIGIN.y + STORAGE_SLOT.y + 12.0, STAGE_SIZE.x, 26.0))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(overlay)
	overlay.draw.connect(_draw_overlay)


func _build_info(stage: Control) -> void:
	var plate: Panel = UiStyle.make_plate(UiStyle.COL_PANEL, UiStyle.COL_CYAN, 4, 0.0, 8)
	plate.name = "InfoPlate"
	UiStyle.anchor_box(plate, Vector2.ZERO, INFO_RECT.position, INFO_RECT.size)
	stage.add_child(plate)
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Info"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.clip_contents = true
	column.add_theme_constant_override("separation", int(INFO_SEPARATION))
	var inner: Rect2 = INFO_RECT.grow_individual(-18.0, -12.0, -16.0, -12.0)
	UiStyle.anchor_box(column, Vector2.ZERO, inner.position, inner.size)
	stage.add_child(column)
	info_name_label = _add_info_label(column, "Name", 25, UiStyle.COL_YELLOW, true)
	info_subtitle_label = _add_info_label(column, "Subtitle", 15, UiStyle.COL_CYAN, false)
	info_text_label = _add_info_label(column, "Text", 17, UiStyle.COL_WHITE, false)
	info_extra_label = _add_info_label(column, "Extra", 15, UiStyle.COL_GREEN, false)
	info_sell_label = _add_info_label(column, "Sell", 15, UiStyle.COL_ORANGE, false)


func _add_label(parent: Control, node_name: String, text: String, font_size: int, color: Color, slanted: bool,
		rect: Rect2) -> Label:
	var label: Label = UiStyle.make_label(text, font_size, color, slanted)
	label.name = node_name
	UiStyle.anchor_box(label, Vector2.ZERO, rect.position, rect.size)
	parent.add_child(label)
	return label


func _add_info_label(column: VBoxContainer, node_name: String, font_size: int, color: Color, slanted: bool) -> Label:
	var label: Label = UiStyle.make_label("", font_size, color, slanted)
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(label)
	return label


# --- Signale und Anzeige --------------------------------------------------------------

func _on_backpack_opened(new_uid: int) -> void:
	_new_uid = new_uid if new_uid > 0 and Game.backpack.has_item(new_uid) else -1
	_held_uid = -1
	_hover_uid = -1
	_notice_left = 0.0
	_pointer = Vector2(-10000.0, -10000.0)
	visible = true
	if is_inside_tree():
		# Ein Knopf eines anderen Bildschirms mit Fokus würde die Tab-Taste verbrauchen.
		get_viewport().gui_release_focus()
	_refresh()
	_on_points_changed(Game.points)
	UiStyle.pop(_headline, 0.5, 0.25)


func _on_game_over(_stats: Dictionary) -> void:
	_hide()


func _hide() -> void:
	_held_uid = -1
	_hover_uid = -1
	_new_uid = -1
	_notice_left = 0.0
	visible = false


func _on_points_changed(total: int) -> void:
	points_label.text = "PUNKTE: %s" % UiStyle.format_int(total)


func _on_done_pressed() -> void:
	request_close()


## Bringt Texte und Zeichnung auf den Stand des Rucksacks.
func _refresh() -> void:
	if not visible:
		return
	var pack: BackpackState = Game.backpack
	if _held_uid != -1 and not pack.has_item(_held_uid):
		_held_uid = -1
	if _hover_uid != -1 and not pack.has_item(_hover_uid):
		_hover_uid = -1
	if _new_uid != -1 and not pack.has_item(_new_uid):
		_new_uid = -1
	var stored: int = pack.storage_items().size()
	storage_label.text = "ABLAGE  %d / %d" % [stored, BackpackState.STORAGE_CAPACITY]
	hands_label.text = "HÄNDE %d / %d" % [pack.hands_used(), Balance.PLAYER_HANDS]
	hands_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(hands_label.text, 22, HANDS_TITLE_RECT.size.x - 6.0, true, 14))
	_update_warning()
	_update_sell()
	_update_stats()
	_update_info()
	board.queue_redraw()
	overlay.queue_redraw()


## Rote Warnung: Eine gehaltene Waffe, für die keine Hand frei ist (außer sie wird gerade mit
## einer gleichen zusammengelegt), dann die Meldung nach einem abgelehnten Ablegen, dann die
## überfüllte Ablage.
func _update_warning() -> void:
	var pack: BackpackState = Game.backpack
	var text: String = ""
	if _held_uid != -1 and pack.has_item(_held_uid) and not pack.has_free_hands(_held_uid) \
			and int(drop_preview().get("kind", PREVIEW_BAD)) != PREVIEW_MERGE:
		text = _no_hands_text(_held_uid)
	elif _notice_left > 0.0:
		text = _notice
	elif pack.storage_overflow():
		text = OVERFLOW_TEXT
	if not text.is_empty():
		warning_label.text = text
	warning_label.visible = not text.is_empty()


## Zeigt eine Warnung für NOTICE_TIME Sekunden.
func _show_notice(text: String) -> void:
	_notice = text
	_notice_left = NOTICE_TIME
	_update_warning()
	UiStyle.pop(warning_label, 1.15, 0.2)


## Warum diese Waffe nicht ins Raster passt: Alle Hände sind voll, oder sie braucht beide und
## nur eine ist frei.
func _no_hands_text(uid: int) -> String:
	var pack: BackpackState = Game.backpack
	var id: String = str(pack.item(uid).get("id", ""))
	if ItemDefs.hands(id) >= 2 and pack.hands_used(uid) < Balance.PLAYER_HANDS:
		return NO_TWO_HANDS_TEXT
	return NO_HAND_TEXT


## In welcher Hand die eingeräumte Waffe liegt (aus Game.loadout), leer wenn sie dort fehlt.
func _hand_note(uid: int) -> String:
	for slot: Dictionary in hand_slots():
		if int(slot["uid"]) == uid and uid > 0:
			match str(slot["caption"]):
				"Beide Hände":
					return "Du hältst sie in beiden Händen."
				"Linke Hand":
					return "Du hältst sie in der linken Hand."
				_:
					return "Du hältst sie in der rechten Hand."
	return ""


## Namen der Gegenstände als Aufzählung, gleiche zusammengefasst: "2 × Spezialmunition, Scheinwerfer".
func _names_of(uids: Array[int]) -> String:
	var order: PackedStringArray = PackedStringArray()
	var counts: Dictionary = {}
	for uid: int in uids:
		var entry: Dictionary = Game.backpack.item(uid)
		if entry.is_empty():
			continue
		var item_name: String = ItemDefs.display_name(str(entry["id"]))
		if not counts.has(item_name):
			order.append(item_name)
		counts[item_name] = int(counts.get(item_name, 0)) + 1
	var parts: PackedStringArray = PackedStringArray()
	for item_name: String in order:
		var count: int = int(counts[item_name])
		parts.append(item_name if count == 1 else "%d × %s" % [count, item_name])
	return ", ".join(parts)


func _update_sell() -> void:
	var entry: Dictionary = Game.backpack.item(_held_uid) if _held_uid != -1 else {}
	if entry.is_empty():
		sell_value_label.text = "Gegenstand hierher ziehen"
		sell_value_label.add_theme_color_override("font_color", UiStyle.COL_WHITE)
		sell_value_label.add_theme_font_size_override("font_size", 16)
		return
	var amount: int = ItemDefs.sell_value(str(entry["id"]), int(entry["level"]))
	sell_value_label.text = "+%s Punkte" % UiStyle.format_int(amount)
	sell_value_label.add_theme_color_override("font_color", UiStyle.COL_GREEN)
	sell_value_label.add_theme_font_size_override("font_size", 26)


func _update_stats() -> void:
	var pack: BackpackState = Game.backpack
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Freie Felder: %d von %d" % [pack.free_cell_count(), pack.cell_count()])
	lines.append("Hände: %d von %d" % [pack.hands_used(), Balance.PLAYER_HANDS])
	var bonus: PackedStringArray = PackedStringArray()
	var points: float = float(pack.stats().get("points", 0.0))
	if points > 0.0001:
		bonus.append("Punkte +%s %%" % UpgradeDefs.format_percent(points))
	# Schaden und Nachladen aus Verstärkern gelten je Waffe in der Hand.
	var weapons: Array[Dictionary] = Game.loadout
	for i: int in weapons.size():
		var weapon: Dictionary = weapons[i]
		# Eine Waffe nennt ihren Namen, zwei nennen ihre Hand (die Namen stehen über dem Raster).
		var title: String = ItemDefs.display_name(str(weapon.get("id", "")))
		if weapons.size() > 1:
			title = "Links" if i == 0 else "Rechts"
		if float(weapon.get("damage", 0.0)) > 0.0001:
			bonus.append("%s: Schaden +%s %%" % [title, UpgradeDefs.format_percent(float(weapon["damage"]))])
		if float(weapon.get("reload", 0.0)) > 0.0001:
			bonus.append("%s: Nachladen +%s %%" % [title, UpgradeDefs.format_percent(float(weapon["reload"]))])
	if bonus.is_empty():
		lines.append("Noch kein Bonus durch Verstärker.")
	else:
		lines.append_array(bonus)
	stats_label.text = "\n".join(lines)
	# Viele Zeilen: kleinere Schrift, damit alles in den Kasten passt.
	for font_size: int in [14, 13, 12, 11]:
		stats_label.add_theme_font_size_override("font_size", font_size)
		if float(stats_label.get_line_count() * stats_label.get_line_height()) <= STATS_RECT.size.y - 16.0:
			break


## Info-Tafel: gehaltener Gegenstand, sonst der unter der Maus, sonst der neue aus der Kiste.
func _update_info() -> void:
	var uid: int = _held_uid
	if uid == -1:
		uid = _hover_uid
	if uid == -1:
		uid = _new_uid
	var info: Dictionary = describe(uid) if uid != -1 else {}
	info_text_label.add_theme_font_size_override("font_size", INFO_IDLE_SIZE if info.is_empty() else INFO_TEXT_SIZE)
	info_text_label.add_theme_constant_override("paragraph_spacing", INFO_IDLE_PARAGRAPH_GAP if info.is_empty() else 0)
	if info.is_empty():
		info_name_label.add_theme_font_size_override("font_size", 25)
		_set_info_line(info_name_label, "SO GEHT ES")
		_set_info_line(info_subtitle_label, "")
		_set_info_line(info_text_label, INFO_IDLE_TEXT)
		_set_info_line(info_extra_label, "")
		_set_info_line(info_sell_label, "")
		return
	var title: String = str(info["name"])
	if uid == _new_uid:
		title = "NEU: " + title
	info_name_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(title, 25, INFO_RECT.size.x - 40.0, true, 17))
	_set_info_line(info_name_label, title)
	_set_info_line(info_subtitle_label, str(info["subtitle"]))
	_set_info_line(info_text_label, str(info["text"]))
	_set_info_line(info_extra_label, str(info["extra"]))
	_set_info_line(info_sell_label, str(info["sell"]))
	_fit_info(info)


## Wählt die Schriftgrößen von Wirkungstext und Zusatzzeilen so, dass die ganze Tafel in ihren
## Rahmen passt (lange Texte wie bei der Regie-Kamera mit Wiederholung bekommen kleinere Schrift).
func _fit_info(info: Dictionary) -> void:
	var width: float = INFO_RECT.size.x - 34.0
	var available: float = INFO_RECT.size.y - 24.0
	var name_size: int = info_name_label.get_theme_font_size("font_size")
	var fixed: float = _wrapped_height(info_name_label.text, name_size, width, true) \
			+ _wrapped_height(str(info["subtitle"]), 15, width, false) + _wrapped_height(str(info["sell"]), 15, width, false)
	var parts: int = 3
	for key: String in ["text", "extra"]:
		if not str(info[key]).is_empty():
			parts += 1
	fixed += INFO_SEPARATION * float(parts - 1)
	var chosen: Array = INFO_FIT_SIZES[INFO_FIT_SIZES.size() - 1]
	for sizes: Array in INFO_FIT_SIZES:
		var needed: float = fixed + _wrapped_height(str(info["text"]), int(sizes[0]), width, false) \
				+ _wrapped_height(str(info["extra"]), int(sizes[1]), width, false)
		if needed <= available:
			chosen = sizes
			break
	info_text_label.add_theme_font_size_override("font_size", int(chosen[0]))
	info_extra_label.add_theme_font_size_override("font_size", int(chosen[1]))


## Höhe eines Texts, den ein Label in dieser Breite umbricht (mit dem Zeilenabstand des Labels).
## 0 für einen leeren Text.
func _wrapped_height(text: String, font_size: int, width: float, slanted: bool) -> float:
	if text.is_empty():
		return 0.0
	var font: Font = UiStyle.show_font(slanted)
	var line_height: float = maxf(font.get_height(font_size), 1.0)
	var lines: float = maxf(roundf(font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y / line_height), 1.0)
	return lines * line_height + (lines - 1.0) * INFO_LINE_SPACING


func _set_info_line(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()


## Hinweise zu Verbindungen (Synergien), an denen dieser Upgrade-Gegenstand beteiligt ist.
func _synergy_notes(id: String) -> PackedStringArray:
	var notes: PackedStringArray = PackedStringArray()
	var active: Array[String] = Game.backpack.active_synergies()
	for synergy_id: String in UpgradeDefs.synergy_ids():
		var requires: Dictionary = UpgradeDefs.synergy_requirements(synergy_id)
		if not requires.has(id):
			continue
		if active.has(synergy_id):
			notes.append("Verbindung %s ist aktiv." % UpgradeDefs.synergy_name(synergy_id))
			continue
		var parts: PackedStringArray = PackedStringArray()
		for other_id: String in requires:
			parts.append("%s (%s)" % [ItemDefs.display_name(other_id), ItemDefs.rarity_name(int(requires[other_id]))])
		notes.append("Verbindung %s: %s auf derselben Waffe." % [UpgradeDefs.synergy_name(synergy_id), " und ".join(parts)])
	return notes


# --- Maus ------------------------------------------------------------------------------

func _on_board_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		set_pointer((event as InputEventMouseMotion).position)
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		if button.pressed and _held_uid != -1:
			board.accept_event()
			rotate_held()
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	board.accept_event()
	if not button.pressed:
		if _held_uid != -1:
			drop_at(button.position)
		return
	if _held_uid != -1:
		# Die Maustaste wurde außerhalb des Fensters losgelassen: Der nächste Klick legt ab.
		drop_at(button.position)
		return
	set_pointer(button.position)
	var uid: int = item_at(button.position)
	if uid == -1:
		return
	var pack: BackpackState = Game.backpack
	if button.double_click and not pack.is_placed(uid):
		quick_place(uid)
		return
	if pick_up(uid) and pack.is_placed(uid):
		# Das angefasste Feld der Form bleibt unter dem Zeiger.
		var grabbed: Vector2i = cell_at(button.position) - (pack.item(uid)["pos"] as Vector2i)
		if ItemDefs.cells(str(pack.item(uid)["id"]), _held_rot).has(grabbed):
			_grab = grabbed


func _on_board_mouse_exited() -> void:
	if _held_uid == -1 and _hover_uid != -1:
		_hover_uid = -1
		_update_info()


func _is_right_press(event: InputEvent) -> bool:
	var button: InputEventMouseButton = event as InputEventMouseButton
	return button != null and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT


# --- Regeln hinter dem Halten ---------------------------------------------------------

## Erster eingeräumter Gegenstand auf den Feldern covered, mit dem sich uid zusammenlegen lässt.
func _merge_target(uid: int, covered: Array[Vector2i]) -> int:
	for cell: Vector2i in covered:
		var target: int = Game.backpack.merge_target(uid, cell)
		if target != -1:
			return target
	return -1


## Beendet das Halten nach einem gelungenen Ablegen. changed: Der Gegenstand liegt jetzt woanders
## (oder ist weg), die Markierung "NEU" entfällt. Eine Warnung vom letzten abgelehnten Ablegen
## ist damit erledigt.
func _release(uid: int, changed: bool) -> void:
	_held_uid = -1
	_notice_left = 0.0
	if changed and uid == _new_uid:
		_new_uid = -1
	if uid == _hover_uid:
		_hover_uid = -1


## Das Greif-Feld nach einer Vierteldrehung im Uhrzeigersinn (wie ItemDefs.cells dreht und schiebt).
func _rotated_grab(id: String, rot: int, grab: Vector2i) -> Vector2i:
	var origin: Vector2i = Vector2i(9999, 9999)
	for cell: Vector2i in ItemDefs.cells(id, rot):
		origin = Vector2i(mini(origin.x, -cell.y), mini(origin.y, cell.x))
	var turned: Vector2i = Vector2i(-grab.y, grab.x) - origin
	if ItemDefs.cells(id, rot + 1).has(turned):
		return turned
	return ItemDefs.cells(id, rot + 1)[0]


# --- Namen umbrechen ------------------------------------------------------------------

## Ein Versuch, den Namen in einer Schriftgröße zu setzen: { "size", "lines", "line_height", "fits" }.
func _layout_attempt(pieces: Array[Dictionary], font: Font, font_size: int, max_width: float, max_height: float,
		by_words: bool) -> Dictionary:
	var line_height: float = ceilf((font.get_ascent(font_size) + font.get_descent(font_size)) * 0.85)
	var lines: PackedStringArray = _wrap_words(pieces, font, font_size, max_width) if by_words else _wrap(pieces, font, font_size, max_width)
	var fits: bool = float(lines.size()) * line_height <= max_height or lines.size() <= 1
	for line: String in lines:
		if _text_width(font, line, font_size) > max_width:
			fits = false
	return {"size": font_size, "lines": lines, "line_height": line_height, "fits": fits}


## Zerlegt den Namen in Stücke: { "text": String, "end": String }. end sagt, was nach dem Stück
## kommt: "|" Wortfuge oder "'" Silbengrenze (Bindestrich nur beim Umbruch), "-" fester
## Bindestrich (steht schon im Text), " " Leerzeichen, "" Ende. depth 0: nur Bindestrich und
## Leerzeichen, 1: auch Wortfugen, 2: auch Silben.
func _name_pieces(id: String, depth: int) -> Array[Dictionary]:
	var display_name: String = ItemDefs.display_name(id)
	var hinted: String = str(NAME_HYPHENS.get(id, display_name))
	if hinted.replace("|", "").replace("'", "") != display_name:
		hinted = display_name
	var pieces: Array[Dictionary] = []
	var current: String = ""
	for i: int in hinted.length():
		var letter: String = hinted[i]
		if letter == "|" or letter == "'":
			if (depth >= 1 if letter == "|" else depth >= 2) and not current.is_empty():
				pieces.append({"text": current, "end": letter})
				current = ""
		elif letter == " ":
			if not current.is_empty():
				pieces.append({"text": current, "end": " "})
			current = ""
		elif letter == "-":
			pieces.append({"text": current + "-", "end": "-"})
			current = ""
		else:
			current += letter
	if not current.is_empty():
		pieces.append({"text": current, "end": ""})
	return pieces


## Füllt Zeilen der Breite max_width mit den Stücken (so viele je Zeile, wie passen).
func _wrap(pieces: Array[Dictionary], font: Font, font_size: int, max_width: float) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var line: String = ""
	var previous_end: String = ""
	for piece: Dictionary in pieces:
		var text: String = str(piece["text"])
		var end: String = str(piece["end"])
		var joined: String = line + (" " if previous_end == " " and not line.is_empty() else "") + text
		var shown: String = joined + ("-" if _is_soft(end) else "")
		if not line.is_empty() and _text_width(font, shown, font_size) > max_width:
			lines.append(line + ("-" if _is_soft(previous_end) else ""))
			line = text
		else:
			line = joined
		previous_end = end
	if not line.is_empty():
		lines.append(line)
	return lines


## Wie _wrap, aber ganze Wörter bleiben beisammen: Nur ein Wort, das allein zu breit für eine
## Zeile ist, wird an seinen Silben getrennt (es beginnt dann in einer neuen Zeile).
func _wrap_words(pieces: Array[Dictionary], font: Font, font_size: int, max_width: float) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var line: String = ""
	var previous_end: String = ""
	var word: Array[Dictionary] = []
	for piece: Dictionary in pieces:
		word.append(piece)
		var end: String = str(piece["end"])
		if end == "'":
			continue
		var text: String = ""
		for part: Dictionary in word:
			text += str(part["text"])
		var tail: String = "-" if _is_soft(end) else ""
		var joined: String = line + (" " if previous_end == " " and not line.is_empty() else "") + text
		var fits: bool = _text_width(font, joined + tail, font_size) <= max_width
		if not line.is_empty() and not fits:
			lines.append(line + ("-" if _is_soft(previous_end) else ""))
			line = ""
			joined = text
			fits = _text_width(font, text + tail, font_size) <= max_width
		if fits or word.size() == 1:
			line = joined
		else:
			var syllables: Array[Dictionary] = []
			for k: int in word.size():
				syllables.append({"text": str(word[k]["text"]), "end": "'" if k < word.size() - 1 else ""})
			var parts: PackedStringArray = _wrap(syllables, font, font_size, max_width)
			for k: int in parts.size() - 1:
				lines.append(parts[k])
			line = parts[parts.size() - 1]
		previous_end = end
		word.clear()
	if not line.is_empty():
		lines.append(line)
	return lines


## Trennstelle, an der beim Umbruch ein Bindestrich entsteht?
func _is_soft(end: String) -> bool:
	return end == "|" or end == "'"


## Kürzt auf max_lines Zeilen und jede Zeile auf max_width. Gekürztes endet mit "…".
func _clip_lines(lines: PackedStringArray, max_lines: int, font: Font, font_size: int, max_width: float) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for i: int in mini(lines.size(), max_lines):
		var line: String = lines[i]
		var cut: bool = i == max_lines - 1 and lines.size() > max_lines
		if cut:
			line = line.trim_suffix("-") + "…"
		while line.length() > 1 and _text_width(font, line, font_size) > max_width:
			line = line.trim_suffix("…")
			line = line.left(line.length() - 1) + "…"
		result.append(line)
	return result


func _text_width(font: Font, text: String, font_size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


# --- Zeichnen -------------------------------------------------------------------------

func _draw_board() -> void:
	var pack: BackpackState = Game.backpack
	var pulse: float = 0.5 + 0.5 * sin(_pulse * 6.0)
	board.draw_style_box(_grid_box, grid_rect().grow(12.0))
	for y: int in BackpackState.ROWS:
		for x: int in BackpackState.COLS:
			var rect: Rect2 = cell_rect(Vector2i(x, y))
			if pack.has_cell(Vector2i(x, y)):
				board.draw_rect(rect.grow(-2.0), CELL_FILL)
				board.draw_rect(rect.grow(-3.0), CELL_EDGE, false, 2.0)
			else:
				board.draw_rect(rect.grow(-6.0), CELL_GHOST, false, 1.5)
	var placed: Array[Dictionary] = pack.placed_items()
	for entry: Dictionary in placed:
		var uid: int = int(entry["uid"])
		var id: String = str(entry["id"])
		var rot: int = int(entry["rot"])
		var origin: Vector2 = cell_rect(entry["pos"] as Vector2i).position
		# Der gehaltene Gegenstand bleibt an seinem alten Platz als Schatten sichtbar.
		_draw_shape(board, id, rot, origin, CELL, uid == _held_uid)
	_draw_links(pack)
	var marks: Array[Dictionary] = star_marks()
	var related: Array[int] = _related_items(marks)
	for entry: Dictionary in placed:
		var uid: int = int(entry["uid"])
		if uid == _held_uid:
			continue
		var id: String = str(entry["id"])
		var rot: int = int(entry["rot"])
		var origin: Vector2 = cell_rect(entry["pos"] as Vector2i).position
		_draw_item_label(board, id, rot, origin, CELL, int(entry["level"]))
		if related.has(uid):
			# Gehört zum Gegenstand unter dem Zeiger (oder zum gehaltenen): Waffe, auf die er wirkt,
			# oder Gegenstand, der auf die Waffe wirkt.
			_draw_outline(board, ItemDefs.cells(id, rot), origin, CELL, Color(UiStyle.COL_YELLOW, 0.65 + 0.35 * pulse), 4.0)
		if uid == _hover_uid and _held_uid == -1:
			_draw_outline(board, ItemDefs.cells(id, rot), origin, CELL, UiStyle.COL_WHITE, 3.0)
	# Sterne über allen Gegenständen.
	_draw_star_marks(board, marks, false)
	_draw_hands()
	# Beim Zusammenlegen leuchtet das Ziel.
	var preview: Dictionary = drop_preview()
	if not preview.is_empty() and int(preview["merge"]) != -1:
		var target: Dictionary = pack.item(int(preview["merge"]))
		if not target.is_empty():
			_draw_outline(board, ItemDefs.cells(str(target["id"]), int(target["rot"])),
					cell_rect(target["pos"] as Vector2i).position, CELL, Color(UiStyle.COL_YELLOW, 0.6 + 0.4 * pulse), 5.0)
	_draw_storage(pack, pulse)
	var hot: bool = _held_uid != -1 and SELL_RECT.has_point(_pointer)
	board.draw_style_box(_sell_hot_box if hot else _sell_box, SELL_RECT)


## uids der eingeräumten Gegenstände, die zum Gegenstand unter dem Zeiger oder zum gehaltenen
## gehören und deshalb umrandet werden. Zeiger auf einem Stern-Gegenstand: die Waffen, auf die er
## wirkt. Zeiger auf einer Waffe: die Gegenstände, die auf sie wirken. Gehaltener Stern-Gegenstand:
## die Waffen unter seinen Sternen. Gehaltene Waffe: die Gegenstände, deren Sterne sie bedeckt.
func _related_items(marks: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	var pack: BackpackState = Game.backpack
	if _held_uid == -1:
		if _hover_uid == -1 or not pack.is_placed(_hover_uid):
			return result
		result.append_array(pack.star_targets(_hover_uid))
		result.append_array(pack.mods_of(_hover_uid))
		return result
	for mark: Dictionary in marks:
		if not bool(mark["focus"]) or not bool(mark["lit"]):
			continue
		var uid: int = pack.occupant(mark["cell"] as Vector2i) if bool(mark["preview"]) else int(mark["owner"])
		if uid != -1 and not result.has(uid):
			result.append(uid)
	return result


## Zeichnet die Sterne aus star_marks. Auf dem Brett alle Sterne eingeräumter Gegenstände, auf der
## Ebene des gehaltenen Gegenstands (on_overlay) seine eigenen und die, die er verdeckt.
## Auf einem belegten Feld sitzt der Stern klein in der rechten oberen Ecke (der Name bleibt
## lesbar), auf einem freien Feld groß in der Mitte. Mehrere Sterne auf einem Feld rücken
## nebeneinander.
func _draw_star_marks(canvas: Control, marks: Array[Dictionary], on_overlay: bool) -> void:
	if marks.is_empty():
		return
	var pack: BackpackState = Game.backpack
	var pulse: float = 0.5 + 0.5 * sin(_pulse * 6.0)
	var covered: Array[Vector2i] = []
	var preview: Dictionary = drop_preview()
	if not preview.is_empty():
		covered = preview["cells"]
	var per_cell: Dictionary = {}
	for mark: Dictionary in marks:
		per_cell[mark["cell"]] = int(per_cell.get(mark["cell"], 0)) + 1
	var seen: Dictionary = {}
	for mark: Dictionary in marks:
		var cell: Vector2i = mark["cell"]
		var index: int = int(seen.get(cell, 0))
		seen[cell] = index + 1
		var wanted: bool = (bool(mark["preview"]) or covered.has(cell)) if on_overlay else not bool(mark["preview"])
		var star_item: Dictionary = pack.item(int(mark["owner"]))
		if not wanted or star_item.is_empty():
			continue
		var rect: Rect2 = cell_rect(cell)
		var count: int = int(per_cell[cell])
		var radius: float = STAR_RADIUS_CENTER
		var center: Vector2 = rect.get_center()
		var focus: bool = bool(mark["focus"])
		var grow: float = 1.2 + 0.12 * pulse if focus else 1.0
		if pack.occupant(cell) != -1 or covered.has(cell):
			radius = STAR_RADIUS_CORNER
			var step: float = minf(STAR_STEP_CORNER, (CELL - 44.0) / float(maxi(count - 1, 1)))
			center = Vector2(rect.end.x - 14.0 - float(index) * step, rect.position.y + 14.0)
			if not bool(mark["lit"]):
				# Leere Sterne auf einem Gegenstand bleiben klein, damit sein Name frei bleibt.
				radius = STAR_RADIUS_CORNER - 2.0
				center += Vector2(3.0, -3.0)
				grow = 1.0 + 0.5 * (grow - 1.0)
		else:
			var step: float = minf(STAR_STEP_CENTER, (CELL - 30.0) / float(maxi(count - 1, 1)))
			center.x += (float(index) - float(count - 1) * 0.5) * step
		radius *= grow
		# Sterne auf Feldern, die noch nicht zum Rucksack gehören, sind blasser.
		var alpha: float = 1.0 if pack.has_cell(cell) else 0.55
		_draw_star(canvas, center, radius, ItemDefs.color(str(star_item["id"])), bool(mark["lit"]), focus, alpha)


## Ein Stern: gefüllt und hell (lit) oder nur als blasser Umriss. strong: mit weißem Rand.
func _draw_star(canvas: Control, center: Vector2, radius: float, color: Color, lit: bool, strong: bool, alpha: float) -> void:
	if lit:
		if strong:
			canvas.draw_colored_polygon(_star_points(center, radius + 5.5), Color(UiStyle.COL_WHITE, alpha))
		canvas.draw_colored_polygon(_star_points(center, radius + 3.0), Color(UiStyle.COL_INK, alpha))
		canvas.draw_colored_polygon(_star_points(center, radius), Color(color, alpha))
		return
	canvas.draw_colored_polygon(_star_points(center, radius + 2.0), Color(UiStyle.COL_INK, 0.7 * alpha))
	var outline: PackedVector2Array = _star_points(center, radius - 0.5)
	outline.append(outline[0])
	canvas.draw_polyline(outline, Color(color, 0.85 * alpha), 1.6, true)
	if strong:
		var ring: PackedVector2Array = _star_points(center, radius + 3.5)
		ring.append(ring[0])
		canvas.draw_polyline(ring, Color(UiStyle.COL_WHITE, alpha), 1.6, true)


## Eckpunkte eines fünfzackigen Sterns (Spitze nach oben).
func _star_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 10:
		var angle: float = -PI * 0.5 + float(i) * PI / 5.0
		var length: float = radius if i % 2 == 0 else radius * STAR_INNER
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	return points


## Die Hände über dem Raster: ein Kasten je Hand mit der Waffe darin, eine Zweihand-Waffe füllt
## beide. Ohne Waffe im Rucksack steht dort die Dienstpistole als Notlösung.
func _draw_hands() -> void:
	var font: Font = UiStyle.show_font()
	var left: float = HAND_BOX_ORIGIN.x
	for slot: Dictionary in hand_slots():
		var span: int = int(slot["span"])
		var width: float = HAND_BOX_SIZE.x * float(span) + HAND_BOX_GAP * float(span - 1)
		var rect: Rect2 = Rect2(left, HAND_BOX_ORIGIN.y, width, HAND_BOX_SIZE.y)
		left += width + HAND_BOX_GAP
		var uid: int = int(slot["uid"])
		var fill: Color = Color(0.0, 0.0, 0.0, 0.45)
		var edge: Color = Color(UiStyle.COL_CYAN, 0.45)
		var name_color: Color = Color(UiStyle.COL_WHITE, 0.55)
		if bool(slot["stopgap"]):
			fill = Color(0.3, 0.1, 0.05, 0.9)
			edge = UiStyle.COL_ORANGE
			name_color = UiStyle.COL_WHITE
		elif uid > 0:
			fill = ItemDefs.color(str(slot["id"])).darkened(0.68)
			edge = ItemDefs.rarity_color(int(slot["level"]))
			name_color = UiStyle.COL_WHITE
			if _held_uid == -1 and uid == _hover_uid:
				edge = UiStyle.COL_WHITE
		board.draw_rect(rect.grow(2.0), UiStyle.COL_INK)
		board.draw_rect(rect, fill)
		board.draw_rect(rect.grow(-1.5), edge, false, 3.0)
		board.draw_string(font, Vector2(rect.position.x + 9.0, rect.position.y + 16.0), str(slot["caption"]).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, width - 18.0, 10, UiStyle.COL_CYAN)
		var item_name: String = str(slot["name"])
		var font_size: int = UiStyle.fit_font_size(item_name, 15, width - 18.0, false, 9)
		board.draw_string(font, Vector2(rect.position.x + 9.0, rect.position.y + 35.0), item_name,
				HORIZONTAL_ALIGNMENT_LEFT, width - 18.0, font_size, name_color)


func _draw_storage(pack: BackpackState, pulse: float) -> void:
	var storage: Array[Dictionary] = pack.storage_items()
	var count: int = maxi(storage.size(), BackpackState.STORAGE_CAPACITY)
	var font: Font = UiStyle.show_font()
	for i: int in count:
		var rect: Rect2 = storage_rect(i)
		board.draw_style_box(_slot_over_box if i >= BackpackState.STORAGE_CAPACITY else _slot_box, rect)
		if i >= storage.size():
			continue
		var entry: Dictionary = storage[i]
		var uid: int = int(entry["uid"])
		var id: String = str(entry["id"])
		var rot: int = int(entry["rot"])
		var held: bool = uid == _held_uid
		var area: Rect2 = Rect2(rect.position + Vector2(6.0, 7.0), Vector2(rect.size.x - 12.0, 50.0))
		var extent: Vector2i = ItemDefs.size(id, rot)
		var mini_cell: float = minf(22.0, minf(area.size.x / float(extent.x), area.size.y / float(extent.y)))
		var origin: Vector2 = area.position + (area.size - Vector2(extent) * mini_cell) * 0.5
		_draw_shape(board, id, rot, origin, mini_cell, held)
		var text_color: Color = Color(UiStyle.COL_WHITE, 0.35 if held else 1.0)
		if ItemDefs.has_rarity(id) and not held:
			_draw_pips(board, Vector2(rect.get_center().x, rect.position.y + 65.0), int(entry["level"]), 1.0)
		if ItemDefs.is_weapon(id) and not held:
			# Waffen zeigen, wie viele Hände sie brauchen.
			_draw_badge(board, Vector2(rect.end.x - 16.0, rect.position.y + 12.0), _hands_badge(id), UiStyle.COL_INK, UiStyle.COL_WHITE, 11)
		var layout: Dictionary = name_layout(id, rect.size.x - 8.0, 28.0, 12, 9)
		var lines: PackedStringArray = layout["lines"]
		var font_size: int = int(layout["size"])
		var line_height: float = float(layout["line_height"])
		var top: float = rect.position.y + 72.0 + (28.0 - line_height * float(lines.size())) * 0.5
		for n: int in lines.size():
			board.draw_string(font, Vector2(rect.position.x + 4.0, top + line_height * float(n) + font.get_ascent(font_size) * 0.92),
					lines[n], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8.0, font_size, text_color)
		if uid == _hover_uid and _held_uid == -1:
			board.draw_rect(rect.grow(1.0), UiStyle.COL_WHITE, false, 3.0)
		if uid == _new_uid:
			board.draw_rect(rect.grow(2.0 + 2.0 * pulse), Color(UiStyle.COL_YELLOW, 0.55 + 0.45 * pulse), false, 4.0)
			_draw_badge(board, rect.position + Vector2(20.0, 2.0), "NEU", UiStyle.COL_PINK, UiStyle.COL_YELLOW)


## Leuchtende Naht zwischen Gegenständen einer Verbindung: gelb pulsierend, wenn sie aktiv ist,
## sonst blass (die Gegenstände liegen richtig, die Stufen reichen noch nicht).
func _draw_links(pack: BackpackState) -> void:
	var links: Array[Array] = pack.synergy_links()
	if links.is_empty():
		return
	var active: Array[String] = pack.active_synergies()
	# So breit wie die dunklen Ränder zweier Nachbarn zusammen (siehe _draw_shape).
	var half_width: float = maxf(1.0, CELL * 0.03) + maxf(2.0, CELL * 0.05)
	var half_length: float = CELL * 0.34
	for link: Array in links:
		var uid_a: int = int(link[0])
		var uid_b: int = int(link[1])
		if uid_a == _held_uid or uid_b == _held_uid:
			continue
		var is_active: bool = _link_active(str(pack.item(uid_a)["id"]), str(pack.item(uid_b)["id"]), active)
		var color: Color = Color(0.8, 0.8, 0.9, 0.7)
		if is_active:
			color = UiStyle.COL_YELLOW.lerp(UiStyle.COL_WHITE, 0.5 + 0.5 * sin(_pulse * 5.0))
		var cells_b: Array[Vector2i] = pack.cells_of(uid_b)
		for cell: Vector2i in pack.cells_of(uid_a):
			for step: Vector2i in BackpackState.NEIGHBOR_STEPS:
				if not cells_b.has(cell + step):
					continue
				var middle: Vector2 = cell_rect(cell).get_center() + Vector2(step) * CELL * 0.5
				var half: Vector2 = Vector2(half_width, half_length) if step.x != 0 else Vector2(half_length, half_width)
				board.draw_rect(Rect2(middle - half, half * 2.0), color)
				if is_active:
					board.draw_rect(Rect2(middle - half, half * 2.0).grow(2.0), Color(UiStyle.COL_YELLOW, 0.35))


func _link_active(id_a: String, id_b: String, active: Array[String]) -> bool:
	for synergy_id: String in active:
		var requires: Dictionary = UpgradeDefs.synergy_requirements(synergy_id)
		if requires.has(id_a) and requires.has(id_b):
			return true
	return false


func _draw_overlay() -> void:
	if _held_uid == -1:
		return
	var entry: Dictionary = Game.backpack.item(_held_uid)
	if entry.is_empty():
		return
	var id: String = str(entry["id"])
	var shape: Array[Vector2i] = ItemDefs.cells(id, _held_rot)
	var preview: Dictionary = drop_preview()
	var origin: Vector2 = _pointer - (Vector2(_grab) + Vector2(0.5, 0.5)) * CELL
	if preview.is_empty():
		for cell: Vector2i in shape:
			overlay.draw_rect(Rect2(origin + Vector2(cell) * CELL + Vector2(7.0, 9.0), Vector2(CELL, CELL)).grow(-2.0), Color(0.0, 0.0, 0.0, 0.35))
	else:
		# Über dem Raster rastet die Form in die Felder ein.
		origin = cell_rect(preview["pos"] as Vector2i).position
	_draw_shape(overlay, id, _held_rot, origin, CELL, false)
	_draw_item_label(overlay, id, _held_rot, origin, CELL, int(entry["level"]))
	if preview.is_empty():
		# Frei schwebend: Die Sterne hängen als Umriss an der Form.
		for star: Vector2i in ItemDefs.stars(id, _held_rot):
			_draw_star(overlay, origin + (Vector2(star) + Vector2(0.5, 0.5)) * CELL, STAR_RADIUS_CENTER, ItemDefs.color(id), false, false, 1.0)
		return
	var tint: Color = UiStyle.COL_RED
	if int(preview["kind"]) == PREVIEW_FIT:
		tint = UiStyle.COL_GREEN
	elif int(preview["kind"]) == PREVIEW_MERGE:
		tint = UiStyle.COL_YELLOW
	for cell: Vector2i in shape:
		overlay.draw_rect(Rect2(origin + Vector2(cell) * CELL, Vector2(CELL, CELL)), Color(tint, 0.32))
	_draw_outline(overlay, shape, origin, CELL, tint, 4.0)
	# Sterne des gehaltenen Gegenstands an der Stelle der Vorschau und Sterne, die er verdeckt.
	_draw_star_marks(overlay, star_marks(), true)


## Zeichnet die Form eines Gegenstands: dunkler Rand außen herum, Felder ohne Fuge verbunden.
## ghost: nur ein blasser Schatten (alter Platz des gehaltenen Gegenstands).
func _draw_shape(canvas: Control, id: String, rot: int, origin: Vector2, cell: float, ghost: bool) -> void:
	var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
	var fill: Color = ItemDefs.color(id)
	var gap: float = maxf(1.0, cell * 0.03)
	var edge: float = maxf(2.0, cell * 0.05)
	if ghost:
		for entry: Vector2i in shape:
			canvas.draw_rect(Rect2(origin + Vector2(entry) * cell, Vector2(cell, cell)).grow(-gap - edge), Color(fill, 0.22))
		_draw_outline(canvas, shape, origin, cell, Color(fill, 0.6), 2.0)
		return
	for entry: Vector2i in shape:
		canvas.draw_rect(_shape_rect(shape, entry, origin, cell, gap), UiStyle.COL_INK)
	var inset: float = gap + edge
	for entry: Vector2i in shape:
		var inner: Rect2 = _shape_rect(shape, entry, origin, cell, inset)
		canvas.draw_rect(inner, fill)
		if not shape.has(entry + Vector2i(0, -1)):
			canvas.draw_rect(Rect2(inner.position, Vector2(inner.size.x, cell * 0.14)), fill.lightened(0.4))
		if not shape.has(entry + Vector2i(0, 1)):
			canvas.draw_rect(Rect2(inner.position.x, inner.end.y - cell * 0.1, inner.size.x, cell * 0.1), fill.darkened(0.22))
		# Innenecken (L-Formen): Der dunkle Rand läuft um die Ecke.
		var base: Vector2 = origin + Vector2(entry) * cell
		for corner: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			if shape.has(entry + Vector2i(corner.x, 0)) and shape.has(entry + Vector2i(0, corner.y)) and not shape.has(entry + corner):
				var at: Vector2 = base + Vector2(cell - inset if corner.x > 0 else 0.0, cell - inset if corner.y > 0 else 0.0)
				canvas.draw_rect(Rect2(at, Vector2(inset, inset)), UiStyle.COL_INK)


## Rechteck eines Feldes der Form: an Außenkanten um inset eingerückt, an Nachbarn der Form bündig.
func _shape_rect(shape: Array[Vector2i], entry: Vector2i, origin: Vector2, cell: float, inset: float) -> Rect2:
	var base: Rect2 = Rect2(origin + Vector2(entry) * cell, Vector2(cell, cell))
	return base.grow_individual(
			0.0 if shape.has(entry + Vector2i(-1, 0)) else -inset,
			0.0 if shape.has(entry + Vector2i(0, -1)) else -inset,
			0.0 if shape.has(entry + Vector2i(1, 0)) else -inset,
			0.0 if shape.has(entry + Vector2i(0, 1)) else -inset)


## Linie um den Umriss einer Form (nur Kanten ohne Nachbarfeld der Form).
func _draw_outline(canvas: Control, shape: Array[Vector2i], origin: Vector2, cell: float, color: Color, width: float) -> void:
	var half: float = width * 0.5
	for entry: Vector2i in shape:
		var rect: Rect2 = Rect2(origin + Vector2(entry) * cell, Vector2(cell, cell))
		if not shape.has(entry + Vector2i(0, -1)):
			canvas.draw_rect(Rect2(rect.position.x - half, rect.position.y - half, cell + width, width), color)
		if not shape.has(entry + Vector2i(0, 1)):
			canvas.draw_rect(Rect2(rect.position.x - half, rect.end.y - half, cell + width, width), color)
		if not shape.has(entry + Vector2i(-1, 0)):
			canvas.draw_rect(Rect2(rect.position.x - half, rect.position.y - half, width, cell + width), color)
		if not shape.has(entry + Vector2i(1, 0)):
			canvas.draw_rect(Rect2(rect.end.x - half, rect.position.y - half, width, cell + width), color)


## Name und Rarität eines Gegenstands in seiner Form (im Raster und in der Hand). Waffen tragen
## dazu links oben ein Schild mit ihren Händen ("1H" oder "2H").
func _draw_item_label(canvas: Control, id: String, rot: int, origin: Vector2, cell: float, level: int) -> void:
	var box: Rect2 = _text_box(id, rot, origin, cell)
	var with_pips: bool = ItemDefs.has_rarity(id)
	var pips_height: float = 13.0 if with_pips else 0.0
	var area: Rect2 = Rect2(box.position + Vector2(6.0, 6.0), Vector2(box.size.x - 12.0, box.size.y - 12.0 - pips_height))
	if ItemDefs.is_weapon(id):
		# Oben in jedem Feld einer Waffe sitzen ihr Schild und die Sterne: Der Name rückt darunter.
		# Bei einer hochkant liegenden Waffe steht er deshalb ganz im ersten Feld.
		area = Rect2(box.position + Vector2(6.0, 16.0), Vector2(box.size.x - 12.0, box.size.y - 22.0 - pips_height))
		if box.size.x <= cell + 0.5:
			area = Rect2(box.position + Vector2(6.0, 25.0), Vector2(cell - 12.0, cell - 28.0))
	elif ItemDefs.is_camera(id):
		# Auf einer Kamera leuchten oben rechts die Sterne ihres Zubehörs: Der Name rückt darunter.
		area = Rect2(box.position + Vector2(6.0, CAMERA_NAME_TOP), Vector2(box.size.x - 12.0, box.size.y - CAMERA_NAME_TOP - 6.0 - pips_height))
	var layout: Dictionary = name_layout(id, area.size.x, area.size.y)
	var lines: PackedStringArray = layout["lines"]
	var font_size: int = int(layout["size"])
	var line_height: float = float(layout["line_height"])
	var font: Font = UiStyle.show_font()
	var top: float = area.position.y + (area.size.y - line_height * float(lines.size())) * 0.5
	for n: int in lines.size():
		canvas.draw_string(font, Vector2(area.position.x, top + line_height * float(n) + font.get_ascent(font_size) * 0.92),
				lines[n], HORIZONTAL_ALIGNMENT_CENTER, area.size.x, font_size, UiStyle.COL_INK)
	if with_pips:
		_draw_pips(canvas, Vector2(box.get_center().x, box.end.y - 12.0), level, 1.0)
	if ItemDefs.is_weapon(id):
		var first: Vector2i = ItemDefs.cells(id, rot)[0]
		_draw_badge(canvas, origin + Vector2(first) * cell + Vector2(19.0, 15.0), _hands_badge(id), UiStyle.COL_INK, UiStyle.COL_WHITE, 11)


## Text des Schilds einer Waffe: "1H" (eine Hand) oder "2H" (zwei Hände).
func _hands_badge(id: String) -> String:
	return "%dH" % ItemDefs.hands(id)


## Fläche für den Namen: die breiteste Zeile der Form, bei schmalen Formen die ganze Spalte.
func _text_box(id: String, rot: int, origin: Vector2, cell: float) -> Rect2:
	var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
	var extent: Vector2i = ItemDefs.size(id, rot)
	var best_row: int = 0
	var best_count: int = 0
	var best_left: int = 0
	for y: int in extent.y:
		var count: int = 0
		var left: int = extent.x
		for entry: Vector2i in shape:
			if entry.y == y:
				count += 1
				left = mini(left, entry.x)
		if count > best_count:
			best_count = count
			best_row = y
			best_left = left
	if best_count >= 2:
		return Rect2(origin + Vector2(float(best_left), float(best_row)) * cell, Vector2(float(best_count) * cell, cell))
	var first: Vector2i = shape[0]
	var run: int = 1
	while shape.has(first + Vector2i(0, run)):
		run += 1
	return Rect2(origin + Vector2(first) * cell, Vector2(cell, float(run) * cell))


## Fünf Kästchen für die Rarität: so viele wie die Rarität in ihrer Farbe mit dunklem Rand (damit
## sie sich von jeder Farbe des Gegenstands abheben), der Rest dunkel.
func _draw_pips(canvas: Control, center: Vector2, level: int, alpha: float) -> void:
	var count: int = Balance.UPGRADE_MAX_LEVEL
	var total: float = PIP_SIZE.x * float(count) + PIP_GAP * float(count - 1)
	for i: int in count:
		var rect: Rect2 = Rect2(center.x - total * 0.5 + float(i) * (PIP_SIZE.x + PIP_GAP), center.y - PIP_SIZE.y * 0.5, PIP_SIZE.x, PIP_SIZE.y)
		var color: Color = Color(0.0, 0.0, 0.0, 0.55)
		if i < level:
			color = ItemDefs.rarity_color(level)
		canvas.draw_rect(rect.grow(2.0), Color(UiStyle.COL_INK, alpha))
		canvas.draw_rect(rect, Color(color, color.a * alpha))


## Kleines Schild mit Text, mittig um center.
func _draw_badge(canvas: Control, center: Vector2, text: String, bg: Color, text_color: Color, font_size: int = 12) -> void:
	var font: Font = UiStyle.show_font()
	var width: float = _text_width(font, text, font_size) + 10.0
	var height: float = float(font_size) + 6.0
	var rect: Rect2 = Rect2(center - Vector2(width * 0.5, height * 0.5), Vector2(width, height))
	canvas.draw_rect(rect.grow(2.0), UiStyle.COL_INK)
	canvas.draw_rect(rect, bg)
	canvas.draw_string(font, Vector2(rect.position.x, rect.position.y + height * 0.75), text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, text_color)
