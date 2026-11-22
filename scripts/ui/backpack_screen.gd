extends CanvasLayer
## Modul: Oberfläche (scripts/ui).
## Rucksack-Bildschirm (Abschnitte 16, 18, 25 und 26): Rucksack in der Mitte, Regal mit der Ablage
## links, Hände, Material und Punkte in der oberen Leiste, drei Felder rechts unten (Reparieren,
## Verschrotten, Verkaufen), Karte am Gegenstand.
##
## Aufteilung: Oben eine schmale Leiste (Titel, Hände, Material, Punkte, Knopf "?"). Links das
## Regal: Dort liegen die Gegenstände der Ablage untereinander in ihrer echten Form, die neuesten
## oben. Die Ablage hat keine Grenze, das Regal rollt (Mausrad, Rollbalken, von selbst beim Ziehen
## an den oberen oder unteren Rand). In der Mitte der Rucksack: Gezeichnet werden nur die Felder,
## die es gibt, als eine Fläche mit Umriss. Wo ein Rucksack-Teil hinpasst, zeigt sich erst, wenn
## man eines hält (ghost_cells). Unten eine Leiste mit den Tastenhinweisen, der Warnung und dem
## Knopf "FERTIG".
##
## Jeder Gegenstand zeigt sein Bild aus ItemIcons auf einer Fläche in der Farbe seiner Rarität.
## Der Name steht im Raster nur auf Wunsch als kleine Zeile am unteren Rand (Taste N), im Regal
## immer daneben oder darunter.
##
## Kaputte Gegenstände (Fundstücke aus Kisten) liegen grau und schraffiert im Regal und tragen ein
## Schild mit Schraubenschlüssel und den Kosten. Sie lassen sich nicht einräumen und nicht
## kombinieren: Die Vorschau zeigt "geht nicht", die Warnung sagt "Erst reparieren".
##
## Waffen liegen als Gegenstände im Raster: Was dort liegt, hält der Spieler in der Hand (höchstens
## zwei Hände, Anzeige in der oberen Leiste). Gegenstände mit Sternen wirken nur auf die Waffen, die
## auf ihren Sternfeldern liegen: Jedes Sternfeld bekommt einen Stern in der Farbe seines
## Gegenstands, gefüllt mit Waffe darauf, sonst nur als Umriss (star_marks).
## Kameras (Abschnitt 22.1) liegen ebenfalls im Raster. Die Sterne der Kamera-Gegenstände
## leuchten nur auf Kameras, der Stern der Wiederholung auf Upgrade-Gegenständen und Kameras.
##
## Karte: Liegt der Zeiger auf einem Gegenstand (Raster oder Regal) oder wird einer gehalten,
## steht neben ihm eine Karte mit Name, Rarität, dem Hinweis "Kaputt", Wertebalken (Waffen und
## Kameras), Wirkung, Hinweisen, Schlagworten, Verkaufswert und Ertrag beim Verschrotten. Die
## Texte kommen aus describe(uid). Ohne Gegenstand gibt es keine Karte. Die Erklärung "So geht es"
## ist eine Hilfe-Tafel (Knopf "?", F1 oder H).
##
## Der Bildschirm zeigt Game.backpack und ändert ihn nur über dessen Regeln (place, merge, store)
## und über Game.sell_item, Game.scrap_item und Game.repair_item. Nach jeder gelungenen Änderung
## am Rucksack ruft er Game.sync_build(). Er öffnet sich bei Events.backpack_opened und schließt
## sich bei backpack_closed, run_started und game_over.
## process_mode ALWAYS, weil der Baum pausiert ist, solange der Rucksack offen ist.
##
## Bedienung: Gegenstand mit der linken Maustaste greifen, ziehen, loslassen. Über dem Raster wird
## er eingeräumt oder mit einem gleichen zusammengelegt, über dem Regal abgelegt (auf einem
## gleichen Gegenstand dort: zusammengelegt), über "REPARIEREN" repariert (er bleibt im Regal),
## über "VERSCHROTTEN" zu Material, über "VERKAUFEN" zu Punkten, überall sonst geht er zurück.
## R oder Rechtsklick dreht den gehaltenen Gegenstand. Doppelklick auf einen Gegenstand im Regal
## räumt ihn an die erste freie Stelle. Tab oder Esc schließen.
## Tasten mit dem Zeiger auf einem Gegenstand (ohne etwas zu halten): F repariert, X verschrottet.
## Schutz gegen Versehen: Das erste X merkt den Gegenstand nur vor (roter Rahmen, Hinweis), erst
## ein zweites X auf demselben Gegenstand innerhalb von SCRAP_CONFIRM_TIME verschrottet ihn.
## N blendet die Namen im Raster ein und aus.
##
## Das Halten ist reiner Anzeige-Zustand: Bis zum Loslassen bleibt der Rucksack unverändert. Ein
## misslungenes Ablegen muss deshalb nichts zurückstellen.
## Die Maus arbeitet nur über die öffentlichen Funktionen (pick_up, rotate_held, drop_on_cell,
## drop_on_storage, drop_on_storage_item, drop_on_repair, drop_on_scrap, drop_on_sell,
## cancel_hold, scroll_shelf), die Tasten über press_repair, press_scrap und toggle_names. Tests
## können dieselben Wege ohne Maus und Tasten gehen.
## Alle Positionen (cell_at, cell_rect, storage_rect, card_rect, set_pointer) sind lokale
## Koordinaten von board.

const UiStyle := preload("res://scripts/ui/hud.gd")
const Balance := preload("res://scripts/core/balance.gd")
const ItemDefs := preload("res://scripts/core/item_defs.gd")
const UpgradeDefs := preload("res://scripts/core/upgrade_defs.gd")
const BackpackState := preload("res://scripts/core/backpack_state.gd")
const CameraDefs := preload("res://scripts/core/camera_defs.gd")
const WeaponDefs := preload("res://scripts/core/weapon_defs.gd")
const ItemIcons := preload("res://scripts/ui/item_icons.gd")

const LAYER: int = 15

## Ergebnis von drop_preview: passt, wird zusammengelegt, passt nicht.
const PREVIEW_FIT: int = 0
const PREVIEW_MERGE: int = 1
const PREVIEW_BAD: int = 2

## Die drei Felder rechts unten (action_at): keines, Reparieren, Verschrotten, Verkaufen.
const ACTION_NONE: int = 0
const ACTION_REPAIR: int = 1
const ACTION_SCRAP: int = 2
const ACTION_SELL: int = 3

# --- Maße (Koordinaten von board; die Bühne ist STAGE_SIZE groß und liegt mittig im Bild) ---
const STAGE_SIZE: Vector2 = Vector2(1240.0, 680.0)
## Kantenlänge eines Feldes im Rucksack: so groß, dass fünf Zeilen zwischen die Leisten passen.
const CELL: float = 96.0
## Obere Leiste (Titel, Hände, Material, Punkte, Hilfe) und untere Leiste (Hinweise, Warnung, FERTIG).
const TOP_BAR_RECT: Rect2 = Rect2(0.0, 0.0, 1240.0, 54.0)
const BOTTOM_BAR_RECT: Rect2 = Rect2(0.0, 612.0, 1240.0, 68.0)
const TITLE_POSITION: Vector2 = Vector2(10.0, 5.0)
const TITLE_FONT_SIZE: int = 26
## Hände in der oberen Leiste: Titel links, daneben ein Kasten je Hand.
const HANDS_TITLE_RECT: Rect2 = Rect2(300.0, 5.0, 130.0, 44.0)
const HAND_BOX_ORIGIN: Vector2 = Vector2(438.0, 5.0)
const HAND_BOX_SIZE: Vector2 = Vector2(152.0, 44.0)
const HAND_BOX_GAP: float = 6.0
## Material neben den Punkten: links das Zahnrad (MATERIAL_ICON_SIZE), rechts daneben "MATERIAL n".
const MATERIAL_RECT: Rect2 = Rect2(766.0, 7.0, 184.0, 40.0)
const MATERIAL_ICON_SIZE: float = 26.0
const MATERIAL_FONT_SIZE: int = 20
const MATERIAL_MIN_FONT_SIZE: int = 14
const POINTS_RECT: Rect2 = Rect2(956.0, 7.0, 222.0, 40.0)
const HELP_BUTTON_RECT: Rect2 = Rect2(1186.0, 6.0, 46.0, 42.0)
## Oberkante des Rasters. Waagerecht liegt die Mitte der vorhandenen Felder auf GRID_CENTER_X,
## solange sie dabei zwischen PACK_MIN_X und PACK_MAX_X bleiben (neben Regal und den drei Feldern
## rechts) und die freie Spalte links und rechts daneben (dort kann ein Rucksack-Teil anlegen)
## höchstens bis GHOST_MIN_X bzw. GHOST_MAX_X reicht.
const GRID_TOP: float = 76.0
const GRID_CENTER_X: float = 620.0
const PACK_MIN_X: float = 272.0
const PACK_MAX_X: float = 956.0
const GHOST_MIN_X: float = 230.0
const GHOST_MAX_X: float = 1004.0
## Rahmen um die Fläche des Rucksacks: Abstand zu den Feldern, Breite der Linie, Versatz des Schattens.
const PACK_PAD: float = 10.0
const PACK_BORDER: float = 4.0
const PACK_SHADOW: Vector2 = Vector2(5.0, 6.0)
## Zeile mit freien Feldern, Händen und Bonus unter dem Rucksack.
const STATS_RECT: Rect2 = Rect2(262.0, 573.0, 716.0, 26.0)

# --- Regal mit der Ablage am linken Rand ---
const SHELF_RECT: Rect2 = Rect2(0.0, 64.0, 250.0, 534.0)
## Höhe der Überschrift im Regal und Abstand des Inhalts zum Rahmen.
const SHELF_HEAD: float = 44.0
const SHELF_PAD: float = 10.0
## Kantenlänge eines Feldes im Regal: immer gleich, so dass auch die breiteste Form (fünf Felder)
## neben den Rollbalken passt. Nichts schrumpft, bei viel Inhalt rollt das Regal.
const SHELF_CELL: float = 42.0
## Abstand zwischen zwei Zeilen.
const SHELF_GAP: float = 14.0
## Rollbalken am rechten Rand des Regals: Breite, Abstand zum Inhalt, kleinste Länge des Griffs.
const SHELF_BAR_WIDTH: float = 8.0
const SHELF_BAR_GAP: float = 6.0
const SHELF_THUMB_MIN: float = 30.0
## So weit rollt ein Rastschritt des Mausrads (Pixel).
const SHELF_WHEEL_STEP: float = 70.0
## Rollen von selbst beim Halten: Höhe des Randstreifens oben und unten und höchstes Tempo (Pixel
## je Sekunde, ganz am Rand).
const SHELF_EDGE: float = 46.0
const SHELF_AUTO_SPEED: float = 640.0
## Maßstab der Kästchen für die Rarität im Regal (1 = Größe im Rucksack).
const SHELF_PIP_SCALE: float = 0.5
## Höhe der Namenszeile unter einer breiten Form.
const SHELF_CAPTION: float = 17.0
## Der Name steht rechts neben der Form, wenn dort mindestens SHELF_NAME_MIN Platz ist, sonst darunter.
const SHELF_NAME_GAP: float = 8.0
const SHELF_NAME_MIN: float = 80.0
const SHELF_NAME_FONT_SIZE: int = 13
const SHELF_NAME_MIN_FONT_SIZE: int = 9
const SHELF_EMPTY_TEXT: String = "Leer.\nWas hier liegt, wirkt nicht."
## Schild mit den Reparaturkosten rechts oben in der Zeile eines kaputten Gegenstands: Höhe und
## der Platz, den der Name dafür rechts frei lässt.
const SHELF_REPAIR_BADGE: float = 17.0
const SHELF_REPAIR_ROOM: float = 36.0

# --- Die drei Felder rechts unten: Reparieren, Verschrotten, Verkaufen (übereinander) ---
## Alle drei sind ACTION_SIZE groß und liegen mit 6 Pixeln Abstand untereinander.
const ACTION_SIZE: Vector2 = Vector2(240.0, 52.0)
const REPAIR_RECT: Rect2 = Rect2(1000.0, 430.0, 240.0, 52.0)
const SCRAP_RECT: Rect2 = Rect2(1000.0, 488.0, 240.0, 52.0)
const SELL_RECT: Rect2 = Rect2(1000.0, 546.0, 240.0, 52.0)
## Breite des Bildes links in einem Feld, Schriftgrößen von Titel und Zeile darunter.
const ACTION_ICON_WIDTH: float = 50.0
const ACTION_TITLE_FONT_SIZE: int = 18
const ACTION_VALUE_FONT_SIZE: int = 14
const ACTION_VALUE_HOT_FONT_SIZE: int = 17
const REPAIR_TITLE: String = "REPARIEREN"
const SCRAP_TITLE: String = "VERSCHROTTEN"
const SELL_TITLE: String = "VERKAUFEN"
const REPAIR_IDLE_TEXT: String = "Kostet Material"
const SCRAP_IDLE_TEXT: String = "Gibt Material"
const SELL_IDLE_TEXT: String = "Gibt Punkte"
const REPAIR_INTACT_TEXT: String = "Ist nicht kaputt"
## Farben der drei Felder (Rahmen und Titel).
const REPAIR_COLOR: Color = Color(0.35, 1.0, 0.3)
const SCRAP_COLOR: Color = Color(0.55, 0.9, 1.0)
const SELL_COLOR: Color = Color(1.0, 0.55, 0.08)

# --- Untere Leiste ---
const DONE_RECT: Rect2 = Rect2(1042.0, 618.0, 190.0, 56.0)
## Hinweise und Warnung teilen sich den Platz links von FERTIG: Solange eine Warnung steht, sind
## die Hinweise ausgeblendet.
const HINT_RECT: Rect2 = Rect2(14.0, 614.0, 1016.0, 64.0)
const WARNING_RECT: Rect2 = Rect2(14.0, 615.0, 1016.0, 62.0)
const HINT_TEXT: String = "Ziehen mit der Maus · Drehen: R oder Rechtsklick · Sterne zeigen, worauf ein Gegenstand wirkt · Zwei gleiche kombinieren: im Rucksack oder in der Ablage · Fundstücke sind kaputt: Reparieren kostet Material (Taste F) · Verschrotten gibt Material (zweimal X) · Verkaufen gibt Punkte · Material gibt es auch für jede geschaffte Welle · N: Namen · Tab: schließen · F1: Hilfe"
## Schriftgrößen der Hinweiszeile von groß nach klein: Es gilt die erste, mit der alles passt.
const HINT_FIT_SIZES: Array[int] = [13, 12, 11]
## Warnungen, wenn eine Waffe mangels freier Hände nicht ins Raster passt.
const NO_HAND_TEXT: String = "Keine Hand frei: erst eine Waffe in die Ablage legen"
const NO_TWO_HANDS_TEXT: String = "Keine zwei Hände frei: erst die Waffe in die Ablage legen"
## Hinweis, wenn ein kaputter Gegenstand eingeräumt oder kombiniert werden soll.
const BROKEN_HINT_TEXT: String = "Erst reparieren: Kaputtes lässt sich nicht einräumen oder kombinieren"
## Schild am gehaltenen Gegenstand in diesem Fall.
const BROKEN_BADGE_TEXT: String = "ERST REPARIEREN"
## Zeile auf der Karte eines kaputten Gegenstands (mit den Kosten).
const BROKEN_CARD_TEXT: String = "Kaputt: Reparieren kostet %d Material. Bis dahin lässt er sich nicht einräumen oder kombinieren."
## Meldungen beim Reparieren.
const NOT_BROKEN_TEXT: String = "Der Gegenstand ist heil: Hier gibt es nichts zu reparieren"
const NO_MATERIAL_TEXT: String = "Zu wenig Material: Reparieren kostet %d, du hast %d"
## Meldung nach dem ersten X (Name und Ertrag).
const SCRAP_CONFIRM_TEXT: String = "Noch einmal X: %s verschrotten (+%d Material)"
## So lange gilt das erste X: Ein zweites X in dieser Zeit verschrottet (Sekunden).
const SCRAP_CONFIRM_TIME: float = 1.5
## So lange bleibt die Warnung nach einem abgelehnten Ablegen stehen (Sekunden).
const NOTICE_TIME: float = 4.0
## So lange leuchtet ein Gegenstand nach dem Zusammenlegen oder Reparieren auf (Sekunden).
const FLASH_TIME: float = 0.5
## Über den drei Feldern ist der gehaltene Gegenstand kleiner (Kantenlänge eines Feldes) und
## steht mit diesem Abstand links neben ihnen: So bleibt ihr Text frei.
const HELD_DOCK_CELL: float = 48.0
const HELD_DOCK_GAP: float = 12.0

# --- Hilfe-Tafel "So geht es" ---
const HELP_RECT: Rect2 = Rect2(968.0, 62.0, 272.0, 360.0)
const HELP_TITLE: String = "SO GEHT ES"
const HELP_TEXT: String = "Fundstücke aus Kisten sind kaputt. Reparieren kostet Material, erst danach lassen sie sich einräumen und kombinieren.\nVerschrotten gibt Material, Verkaufen gibt Punkte. Material gibt es auch für jede geschaffte Welle.\nWaffen im Rucksack hältst du in der Hand: höchstens zwei Hände.\nSterne wirken auf die Waffe, die auf ihnen liegt. Kamera-Zubehör wirkt so auf Kameras.\nZwei gleiche in gleicher Rarität aufeinander werden zur nächsten Rarität, auch in der Ablage.\nRucksack-Teile an den Rand legen: neue Felder.\nTasten am Gegenstand: F repariert, zweimal X verschrottet. N zeigt die Namen."
const HELP_FOOT_TEXT: String = "F1, H oder ?: zu"
## Schriftgrößen der Hilfe von groß nach klein: Es gilt die erste, mit der alles in die Tafel passt.
const HELP_FIT_SIZES: Array[int] = [14, 13, 12, 11]
## Abstand zwischen den Absätzen der Hilfe (jede Zeile von HELP_TEXT ist ein Absatz).
const HELP_PARAGRAPH_GAP: int = 6

# --- Karte am Gegenstand ---
const CARD_WIDTH: float = 300.0
const CARD_PAD: float = 14.0
## Abstand der Karte zum Gegenstand und zum Rand der Bühne.
const CARD_GAP: float = 10.0
const CARD_MARGIN: float = 4.0
## Höher wird die Karte nicht: Vorher schrumpft die Schrift (CARD_FIT_SIZES).
const CARD_MAX_HEIGHT: float = 560.0
const CARD_NAME_SIZE: int = 22
const CARD_NAME_MIN_SIZE: int = 15
const CARD_LINE_SIZE: int = 14
const CARD_LINE_MIN_SIZE: int = 12
## Schriftgrößen der Karte für [Wirkungstext, Zusatzzeilen], von groß nach klein: Es gilt das
## erste Paar, mit dem die Karte nicht höher als CARD_MAX_HEIGHT wird.
const CARD_FIT_SIZES: Array[Array] = [[15, 14], [14, 13], [13, 12], [12, 11]]
## Abstand zwischen den Teilen der Karte.
const CARD_SEPARATION: float = 6.0
const CARD_FILL: Color = Color(0.085, 0.045, 0.19)
## Wertebalken: Höhe einer Zeile, Höhe des Balkens, Breite für Namen und Zahl, Schriftgröße.
const BAR_ROW: float = 21.0
const BAR_HEIGHT: float = 9.0
const BAR_LABEL_WIDTH: float = 98.0
const BAR_VALUE_WIDTH: float = 82.0
const BAR_FONT_SIZE: int = 13
## Kürzester sichtbarer Balken (Anteil), damit auch ein kleiner Wert zu sehen ist.
const BAR_MIN_RATIO: float = 0.03

## Sterne: Radius in der Ecke eines belegten Feldes und in der Mitte eines freien Feldes, Anteil
## des inneren Radius, Abstand mehrerer Sterne auf demselben Feld, Abstand zur Ecke des Feldes.
const STAR_RADIUS_CORNER: float = 12.5
const STAR_RADIUS_CENTER: float = 17.0
const STAR_INNER: float = 0.46
const STAR_STEP_CORNER: float = 20.0
const STAR_STEP_CENTER: float = 30.0
const STAR_CORNER_INSET: float = 18.0
const CELL_FILL: Color = Color(0.22, 0.13, 0.42)
const CELL_EDGE: Color = Color(0.45, 0.33, 0.75)
## Mögliche neue Felder, solange ein Rucksack-Teil gehalten wird.
const CELL_GHOST: Color = Color(1.0, 1.0, 1.0, 0.3)
## Kästchen für die Rarität bei einem Feld der Größe CELL (im Regal entsprechend kleiner).
const PIP_SIZE: Vector2 = Vector2(11.0, 8.0)
const PIP_GAP: float = 4.0
## Abstand der Kästchen vom unteren Rand der Form (Anteil der Feldgröße).
const PIP_BOTTOM: float = 0.15

# --- Bild und Name auf einem Gegenstand ---
## Das Bild füllt das größte Quadrat der Form bis auf diesen Rand (Anteil der Kante des Quadrats)
## und sitzt etwas über der Mitte: Unten bleibt Platz für die Kästchen der Rarität.
const ICON_INSET: float = 0.13
const ICON_LIFT: float = 0.045
## Mit eingeblendeten Namen ist das Bild kleiner und sitzt höher (Anteile wie oben).
const ICON_INSET_NAMED: float = 0.2
const ICON_LIFT_NAMED: float = 0.13
## Farbton eines kaputten Gegenstands: seine Fläche (gemischt mit etwas Rarität) und sein Bild (tint).
const BROKEN_FILL: Color = Color(0.3, 0.3, 0.37)
const BROKEN_RARITY_MIX: float = 0.2
const BROKEN_TINT: Color = Color(0.74, 0.74, 0.8)
## Grauer Schleier und Schraffur über einem kaputten Gegenstand, Abstand der Striche (Anteil der Feldgröße).
const BROKEN_VEIL: Color = Color(0.32, 0.32, 0.4, 0.42)
const BROKEN_HATCH: Color = Color(0.03, 0.02, 0.08, 0.38)
const BROKEN_HATCH_STEP: float = 0.3
## Schild mit Schraubenschlüssel und Kosten an einem kaputten Gegenstand.
const BROKEN_BADGE_COLOR: Color = Color(0.85, 0.12, 0.1)
## Namenszeile am unteren Rand eines Gegenstands im Raster (Taste N): Schriftgrößen, größte Höhe
## (zwei Zeilen), Abstand zum Rand.
const NAME_FONT_SIZE: int = 12
const NAME_MIN_FONT_SIZE: int = 9
const NAME_BAND_MAX: float = 25.0
const NAME_PAD: float = 9.0
const NAME_BAND_COLOR: Color = Color(0.03, 0.015, 0.09, 0.78)
## Schild einer Waffe ("1H", "2H") im Raster: Mitte ab der Ecke des ersten Feldes, Schriftgröße.
const BADGE_OFFSET: Vector2 = Vector2(23.0, 18.0)
const BADGE_FONT_SIZE: int = 13
## Dasselbe Schild im Regal (kleinere Felder).
const SHELF_BADGE_OFFSET: Vector2 = Vector2(14.0, 11.0)
const SHELF_BADGE_FONT_SIZE: int = 10
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

## Gezeichnete Fläche für Rucksack, Regal, Hände und die drei Felder. Nimmt die Maus an.
var board: Control
## Zeichnet die Zeilen des Regals und schneidet ab, was hinausgerollt ist.
var shelf_canvas: Control
## Bilder, Kästchen und Namen der eingeräumten Gegenstände: eigene Fläche über board. Sie wird nur
## neu gezeichnet, wenn sich daran etwas ändert (siehe _faces_state), nicht in jedem Bild: Die
## Bilder aus ItemIcons sind mit Abstand das Teuerste am ganzen Bildschirm.
var board_faces: Control
## Alles, was über den Gegenständen liegt: Rahmen, Sterne, Hände, Regalrahmen, die drei Felder,
## Aufleuchten. Billig zu zeichnen. Zeichnet sich neu, wenn sich etwas ändert, und in jedem Bild,
## solange darauf etwas pulsiert (siehe _process).
var board_top: Control
## Pulsierende Rahmen und Schilder über den Zeilen des Regals (Kind von shelf_canvas, damit es
## genauso abgeschnitten wird). Zeichnet sich neu wie board_top.
var shelf_top: Control
## Liegt über allem und zeichnet nur den gehaltenen Gegenstand.
var overlay: Control
var headline_label: Label
var points_label: Label
## Material neben den Punkten: "MATERIAL 3". Das Zahnrad davor zeichnet board.
var material_label: Label
## Überschrift des Regals: "ABLAGE 3".
var storage_label: Label
## Rote Warnung in der unteren Leiste (nur sichtbar, wenn es etwas zu sagen gibt): "Erst
## reparieren", eine Waffe ohne freie Hand, zu wenig Material, das vorgemerkte Verschrotten.
var warning_label: Label
## Die drei Felder rechts unten: Titel und die Zeile darunter. Beim Halten zeigt die Zeile, was
## das Loslassen dort bringt ("−2 Material", "+2 Material", "+200 Punkte").
var repair_title_label: Label
var repair_value_label: Label
var scrap_title_label: Label
var scrap_value_label: Label
var sell_title_label: Label
var sell_value_label: Label
## Eine Zeile unter dem Rucksack: freie Felder, Hände und Zusatzwerte aus Verstärkern.
var stats_label: Label
## Titel der Hände in der oberen Leiste: "HÄNDE 1 / 2". Was jede Hand hält, steht in hand_slots().
var hands_label: Label
## Karte am Gegenstand (nur sichtbar mit Gegenstand unter dem Zeiger oder in der Hand) und ihre
## Zeilen. Unsichtbare Zeilen haben einen leeren Text.
var card: Control
var card_name_label: Label
var card_subtitle_label: Label
## "Kaputt: Reparieren kostet N Material. ..." (leer bei einem heilen Gegenstand).
var card_broken_label: Label
var card_text_label: Label
var card_extra_label: Label
var card_tags_label: Label
var card_sell_label: Label
## "Verschrotten: +N Material".
var card_scrap_label: Label
## Zeichnet die Wertebalken der Karte (card_bars).
var card_bars_box: Control
## Hilfe-Tafel "So geht es" mit ihrem Text und der Knopf "?" in der oberen Leiste.
var help_panel: Control
var help_text_label: Label
var help_button: Button
var hint_label: Label
## Knopf "FERTIG" (schließt den Rucksack, nie gesperrt).
var done_button: Button

## Die Hilfe war in diesem Programmlauf schon einmal von selbst zu sehen.
static var _help_shown: bool = false
## Namen im Raster eingeblendet (Taste N)? Gilt bis zum Programmende.
static var _names_shown: bool = false
## Beste Werte aller Waffen für die Wertebalken (siehe _weapon_best).
static var _weapon_best_cache: Dictionary = {}
## Gemerkte Bildflächen je Form: "id|rot" -> Rect2 in Feldern (siehe icon_block).
static var _icon_block_cache: Dictionary = {}

var _headline: PanelContainer
var _bar_box: StyleBoxFlat
var _shelf_box: StyleBoxFlat
var _shelf_hot_box: StyleBoxFlat
## Rahmen der drei Felder: [ruhig, heiß] je Feld, dazu der rote Rahmen für "geht nicht".
var _action_boxes: Dictionary = {}
var _action_bad_box: StyleBoxFlat
var _card_box: StyleBoxFlat
var _card_plate: Panel
## Teile der Karte von oben nach unten.
var _card_parts: Array[Control] = []
## Gegenstand der Karte (-1 = keine Karte), seine Balken und die Farbe seiner Rarität.
var _card_uid: int = -1
var _card_bars: Array[Dictionary] = []
var _card_accent: Color = UiStyle.COL_CYAN
## Linke obere Ecke des Rasters und wofür sie gilt (Rucksack und Zahl seiner Felder).
var _origin: Vector2 = Vector2(PACK_MIN_X, GRID_TOP)
var _origin_pack: BackpackState
var _origin_count: int = -1
## Felder, auf die das gehaltene Rucksack-Teil passen würde (leer ohne Rucksack-Teil in der Hand).
var _bag_cells: Array[Vector2i] = []
## Gerade zusammengelegter oder reparierter Gegenstand (leuchtet kurz auf) und wie lange noch.
var _flash_uid: int = -1
var _flash_left: float = 0.0
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
## So weit ist das Regal nach unten gerollt (Pixel, 0 = ganz oben).
var _shelf_scroll: float = 0.0
## Die Maus zieht gerade am Griff des Rollbalkens.
var _bar_drag: bool = false
## Zum Verschrotten vorgemerkter Gegenstand (erstes X) und wie lange noch, -1 = keiner.
var _scrap_uid: int = -1
var _scrap_left: float = 0.0
## Welche Bilder beim letzten Zeichnen gezeichnet wurden, je Zeichenfläche ("board", "shelf",
## "overlay") eine Liste (siehe drawn_icons).
var _icon_draws: Dictionary = {"board": [], "shelf": [], "overlay": []}
## So oft (Sekunden) prüft _process ohne Anlass, ob sich die Gegenstände geändert haben.
const FACES_CHECK_INTERVAL: float = 0.2
## Stand, für den board_faces und shelf_canvas zuletzt gezeichnet wurden (siehe _faces_state und
## _shelf_state). Weicht der aktuelle Stand ab, wird die Fläche neu gezeichnet.
var _faces_drawn: Array = []
var _shelf_drawn: Array = []
## Stand der billigen Flächen beim letzten Bild (was gehalten, berührt, vorgemerkt, neu ist).
var _moving_drawn: Array = []
## Sekunden bis zur nächsten Prüfung von _faces_state ohne Anlass.
var _faces_check_left: float = 0.0
## Hat die Fläche beim letzten Zeichnen etwas gezeichnet, das von der Zeit abhängt (Pulsieren,
## Aufleuchten)? Nur dann zeichnet _process sie im nächsten Bild von selbst neu. _live sammelt
## das während des Zeichnens einer Fläche.
var _live: bool = false
var _board_live: bool = false
var _top_live: bool = false
var _shelf_live: bool = false
var _overlay_live: bool = false


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
	Events.materials_changed.connect(_on_materials_changed)
	Events.item_repaired.connect(_on_item_repaired)


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse = fmod(_pulse + delta, 1000.0)
	if _notice_left > 0.0:
		_notice_left -= delta
		if _notice_left <= 0.0:
			_update_warning()
	if _scrap_uid != -1:
		_scrap_left -= delta
		if _scrap_left <= 0.0:
			_disarm_scrap()
	if _flash_left > 0.0:
		_flash_left -= delta
	_auto_scroll(delta)
	# Schneller: Früher zeichneten sich hier alle Flächen in jedem Bild neu, auch die Bilder aller
	# Gegenstände (gemessen 33 ms je Bild bei vollem Rucksack und 30 Gegenständen im Regal). Jetzt
	# zeichnet sich eine Fläche nur neu, wenn sich ihr Stand ändert oder solange auf ihr etwas
	# pulsiert (das merkt sich jede Fläche beim Zeichnen selbst, siehe _live).
	var moving: Array = [_held_uid, _held_rot, _hover_uid, _scrap_uid, _new_uid, _flash_left > 0.0, _bar_drag]
	_faces_check_left -= delta
	if moving != _moving_drawn:
		_moving_drawn = moving
		_redraw_moving()
		_redraw_changed_faces()
	else:
		if _board_live:
			board.queue_redraw()
		if _top_live:
			board_top.queue_redraw()
		if _shelf_live:
			shelf_top.queue_redraw()
		if _overlay_live:
			overlay.queue_redraw()
		if _faces_check_left <= 0.0:
			# Sicherheitsnetz für Änderungen am Rucksack, die niemand gemeldet hat.
			_redraw_changed_faces()


## Zeichnet die vier billigen Flächen neu (alles außer den Bildern der Gegenstände).
func _redraw_moving() -> void:
	board.queue_redraw()
	board_top.queue_redraw()
	shelf_top.queue_redraw()
	overlay.queue_redraw()


## Zeichnet die Flächen mit den Bildern der Gegenstände neu, wenn sich ihr Stand geändert hat.
func _redraw_changed_faces() -> void:
	_faces_check_left = FACES_CHECK_INTERVAL
	var faces: Array = _faces_state()
	if faces != _faces_drawn:
		_faces_drawn = faces
		board_faces.queue_redraw()
	var shelf: Array = _shelf_state()
	if shelf != _shelf_drawn:
		_shelf_drawn = shelf
		shelf_canvas.queue_redraw()


## Alles, wovon das Bild auf board_faces abhängt: Lage des Rasters, Namen an oder aus, der
## gehaltene Gegenstand (er fehlt im Raster) und je eingeräumtem Gegenstand uid, ID, Rarität,
## Stelle und Drehung.
func _faces_state() -> Array:
	var state: Array = [grid_origin(), _names_shown, _held_uid]
	for entry: Dictionary in Game.backpack.placed_items():
		state.append(entry["uid"])
		state.append(entry["id"])
		state.append(entry["level"])
		state.append(entry["pos"])
		state.append(entry["rot"])
	return state


## Alles, wovon das Bild auf shelf_canvas abhängt: wie weit gerollt ist, der Gegenstand unter dem
## Zeiger und der gehaltene (Hinterlegung, Umriss, Schatten) und je Gegenstand im Regal uid, ID,
## Rarität, Drehung und ob er kaputt ist (auch die Reparaturkosten hängen nur daran).
func _shelf_state() -> Array:
	var state: Array = [shelf_scroll(), _hover_uid, _held_uid]
	for entry: Dictionary in Game.backpack.storage_items():
		state.append(entry["uid"])
		state.append(entry["id"])
		state.append(entry["level"])
		state.append(entry["rot"])
		state.append(entry.get("broken", false))
	return state


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("backpack"):
		if Game.state == Game.State.PLAYING:
			_handled()
			Game.open_backpack()
		elif Game.state == Game.State.PACKING:
			_handled()
			request_close()
		return
	if Game.state != Game.State.PACKING or not visible:
		return
	if event.is_action_pressed("pause"):
		_handled()
		request_close()
	elif _held_uid != -1 and (event.is_action_pressed("reload") or _is_right_press(event)):
		_handled()
		rotate_held()
	elif _is_key(event, KEY_F1) or _is_key(event, KEY_H):
		_handled()
		toggle_help()
	elif _is_key(event, KEY_N):
		_handled()
		toggle_names()
	elif _is_key(event, KEY_F):
		_handled()
		press_repair()
	elif _is_key(event, KEY_X):
		_handled()
		press_scrap()


## Meldet die Eingabe als verbraucht (ohne Baum, etwa im Test, gibt es nichts zu melden).
func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


## Wurde diese Taste gerade gedrückt (nach Beschriftung oder nach Lage auf der Tastatur)?
func _is_key(event: InputEvent, keycode: Key) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return key.keycode == keycode or key.physical_keycode == keycode


# --- Öffentliche Schnittstelle ---------------------------------------------------------

## Ist der Rucksack-Bildschirm gerade offen?
func is_open() -> bool:
	return visible


## Schließt den Rucksack über Game.close_backpack(). Ein gehaltener Gegenstand geht vorher zurück.
## Die Ablage hält den Rucksack nicht mehr offen: false kommt nur, wenn er gar nicht offen ist.
func request_close() -> bool:
	if Game.state != Game.State.PACKING:
		return false
	_notice_left = 0.0
	_disarm_scrap()
	cancel_hold()
	if Game.close_backpack():
		return true
	_refresh()
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
	_disarm_scrap()
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
## eingeräumt. Passt er nicht, geht er zurück an seinen alten Platz und es kommt false. Die
## Warnung sagt, warum: Er ist kaputt ("Erst reparieren") oder für die Waffe ist keine Hand frei.
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
		if pack.is_broken(uid):
			_show_notice(BROKEN_HINT_TEXT)
		elif not pack.has_free_hands(uid):
			_show_notice(_no_hands_text(uid))
		cancel_hold()
		return false
	_release(uid, true)
	if target != -1 and not pack.has_item(uid):
		_flash(target)
	Game.sync_build()
	return true


## Lässt den gehaltenen Gegenstand auf einem Gegenstand im Regal los. Ist das derselbe Gegenstand
## in derselben Rarität (BackpackState.can_merge), werden beide zusammengelegt: Das Ziel steigt um
## eine Rarität und bleibt im Regal, der gehaltene verschwindet. Sonst landet der gehaltene wie
## bei drop_on_storage einfach in der Ablage (ist einer der beiden kaputt, sagt die Warnung "Erst
## reparieren"). false nur, wenn nichts gehalten wird.
func drop_on_storage_item(target_uid: int) -> bool:
	if _held_uid == -1:
		return false
	var pack: BackpackState = Game.backpack
	var uid: int = _held_uid
	if not pack.has_item(uid):
		cancel_hold()
		return false
	if pack.is_placed(target_uid) or not pack.can_merge(uid, target_uid) or not pack.merge(uid, target_uid):
		var blocked: bool = _same_kind(uid, target_uid) and (pack.is_broken(uid) or pack.is_broken(target_uid))
		var stored: bool = drop_on_storage()
		if blocked:
			_show_notice(BROKEN_HINT_TEXT)
		return stored
	_release(uid, true)
	_flash(target_uid)
	Game.sync_build()
	return true


## Legt den gehaltenen Gegenstand in die Ablage (ein eingeräumter wirkt danach nicht mehr). Das
## Regal rollt so, dass er zu sehen ist.
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
		scroll_to_item(uid)
	else:
		_refresh()
	return true


## Repariert den gehaltenen Gegenstand (Game.repair_item). Er bleibt im Regal und blitzt kurz
## auf. false, wenn nichts gehalten wird, er heil ist oder das Material nicht reicht: Dann geht
## er unverändert zurück und die Warnung sagt, warum.
func drop_on_repair() -> bool:
	if _held_uid == -1:
		return false
	var uid: int = _held_uid
	if not Game.backpack.has_item(uid):
		cancel_hold()
		return false
	_held_uid = -1
	var done: bool = repair(uid)
	if done:
		scroll_to_item(uid)
	_refresh()
	return done


## Verschrottet den gehaltenen Gegenstand (Game.scrap_item): Er ist weg, dafür gibt es Material.
## true, wenn er verschrottet wurde.
func drop_on_scrap() -> bool:
	if _held_uid == -1:
		return false
	var uid: int = _held_uid
	if not Game.backpack.has_item(uid):
		cancel_hold()
		return false
	_release(uid, true)
	var amount: int = Game.scrap_item(uid)
	_refresh()
	return amount > 0


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


## Repariert einen Gegenstand (Game.repair_item): Er bleibt, wo er liegt, und blitzt kurz auf.
## false, wenn er heil ist oder das Material nicht reicht: Die Warnung sagt, warum.
func repair(uid: int) -> bool:
	var pack: BackpackState = Game.backpack
	if not visible or not pack.has_item(uid):
		return false
	_disarm_scrap()
	if not pack.is_broken(uid):
		_show_notice(NOT_BROKEN_TEXT)
		return false
	if not Game.can_repair(uid):
		_show_notice(NO_MATERIAL_TEXT % [Game.repair_cost(uid), Game.materials])
		UiStyle.pop(material_label, 1.25, 0.25)
		return false
	if not Game.repair_item(uid):
		return false
	_notice_left = 0.0
	_flash(uid)
	_refresh()
	return true


## Taste F: repariert den Gegenstand unter dem Zeiger (nur wenn nichts gehalten wird).
func press_repair() -> bool:
	if not visible or _held_uid != -1 or _hover_uid == -1:
		return false
	return repair(_hover_uid)


## Taste X: verschrottet den Gegenstand unter dem Zeiger (nur wenn nichts gehalten wird). Schutz
## gegen Versehen: Das erste X merkt ihn nur vor (scrap_armed_uid, roter Rahmen, Hinweis in der
## Warnzeile) und gibt 0 zurück. Erst ein zweites X auf demselben Gegenstand innerhalb von
## SCRAP_CONFIRM_TIME verschrottet ihn und gibt das Material zurück. Verlässt der Zeiger den
## Gegenstand oder läuft die Zeit ab, ist die Vormerkung weg.
func press_scrap() -> int:
	if not visible or _held_uid != -1 or _hover_uid == -1 or not Game.backpack.has_item(_hover_uid):
		return 0
	var uid: int = _hover_uid
	if _scrap_uid != uid or _scrap_left <= 0.0:
		_scrap_uid = uid
		_scrap_left = SCRAP_CONFIRM_TIME
		_notice_left = 0.0
		_update_warning()
		UiStyle.pop(warning_label, 1.12, 0.18)
		return 0
	_scrap_uid = -1
	_scrap_left = 0.0
	if uid == _new_uid:
		_new_uid = -1
	_hover_uid = -1
	var amount: int = Game.scrap_item(uid)
	# Der nächste Gegenstand rückt unter den Zeiger: Er bekommt die Karte, vorgemerkt ist er nicht.
	_hover_uid = item_at(_pointer)
	_refresh()
	return amount


## uid des Gegenstands, der nach dem ersten X zum Verschrotten vorgemerkt ist, -1 wenn keiner.
func scrap_armed_uid() -> int:
	return _scrap_uid if _scrap_left > 0.0 else -1


## Stehen die Namen als kleine Zeile auf den Gegenständen im Raster?
func names_shown() -> bool:
	return _names_shown


## Blendet die Namen im Raster ein oder aus. Die Wahl gilt bis zum Programmende.
func set_names_shown(shown: bool) -> void:
	_names_shown = shown
	if visible:
		board.queue_redraw()
		overlay.queue_redraw()
		_redraw_changed_faces()


## Taste N: schaltet die Namen im Raster um.
func toggle_names() -> void:
	set_names_shown(not _names_shown)


## Räumt einen Gegenstand aus der Ablage an die erste passende Stelle (Doppelklick).
func quick_place(uid: int) -> bool:
	var pack: BackpackState = Game.backpack
	if not visible or not pack.has_item(uid) or pack.is_placed(uid):
		return false
	if _held_uid != -1:
		cancel_hold()
	if not pack.auto_place(uid):
		if pack.is_broken(uid):
			_show_notice(BROKEN_HINT_TEXT)
		elif not pack.has_free_hands(uid):
			_show_notice(_no_hands_text(uid))
		return false
	_release(uid, true)
	Game.sync_build()
	return true


## Feld des Rasters unter einer Position (Koordinaten von board), Vector2i(-1, -1) außerhalb.
func cell_at(stage_pos: Vector2) -> Vector2i:
	if not _over_grid(stage_pos):
		return Vector2i(-1, -1)
	var local: Vector2 = (stage_pos - grid_origin()) / CELL
	return Vector2i(clampi(int(floor(local.x)), 0, BackpackState.COLS - 1), clampi(int(floor(local.y)), 0, BackpackState.ROWS - 1))


## Liegt die Position über dem Raster? Regal und die drei Felder gehen vor: Wo sie eine leere
## Spalte des Rasters überdecken, zählt die Position zu ihnen.
func _over_grid(board_pos: Vector2) -> bool:
	return grid_rect().has_point(board_pos) and not SHELF_RECT.has_point(board_pos) and action_at(board_pos) == ACTION_NONE


## Rechteck eines Feldes des Rasters (Koordinaten von board).
func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(grid_origin() + Vector2(cell) * CELL, Vector2(CELL, CELL))


## Rechteck des ganzen Rasters (alle COLS mal ROWS Felder, auch die, die es noch nicht gibt).
func grid_rect() -> Rect2:
	return Rect2(grid_origin(), Vector2(float(BackpackState.COLS), float(BackpackState.ROWS)) * CELL)


## Linke obere Ecke des Rasters. Die Mitte der vorhandenen Felder liegt waagerecht auf
## GRID_CENTER_X, solange sie dabei zwischen dem Regal und den drei Feldern rechts bleiben.
func grid_origin() -> Vector2:
	var pack: BackpackState = Game.backpack
	if pack != _origin_pack or pack.cell_count() != _origin_count:
		_update_origin()
	return _origin


## Die vorhandenen Felder als Rechteck in Feldern (linke obere Ecke und Größe), leer ohne Felder.
func pack_bounds() -> Rect2i:
	var cells: Array[Vector2i] = Game.backpack.cells()
	if cells.is_empty():
		return Rect2i()
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for cell: Vector2i in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	return Rect2i(low, high - low + Vector2i.ONE)


## Rechteck um alle vorhandenen Felder des Rucksacks (Koordinaten von board, ohne Rahmen).
func pack_rect() -> Rect2:
	var bounds: Rect2i = pack_bounds()
	return Rect2(grid_origin() + Vector2(bounds.position) * CELL, Vector2(bounds.size) * CELL)


## Felder, die als Rucksack gezeichnet werden: genau die, die es gibt.
func drawn_cells() -> Array[Vector2i]:
	return Game.backpack.cells()


## Felder, die blass als "hier passt das Rucksack-Teil hin" gezeichnet werden: alle Felder, die
## das gehaltene Rucksack-Teil in irgendeiner Lage und Drehung neu anlegen würde. Leer, solange
## kein Rucksack-Teil gehalten wird.
func ghost_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var pack: BackpackState = Game.backpack
	var entry: Dictionary = pack.item(_held_uid) if _held_uid != -1 else {}
	if entry.is_empty() or not ItemDefs.is_bag(str(entry["id"])):
		return result
	var id: String = str(entry["id"])
	var seen: Dictionary = {}
	for rot: int in 4:
		for y: int in BackpackState.ROWS:
			for x: int in BackpackState.COLS:
				if not pack.can_place(_held_uid, Vector2i(x, y), rot):
					continue
				for cell: Vector2i in BackpackState.shape_at(id, Vector2i(x, y), rot):
					if not seen.has(cell):
						seen[cell] = true
						result.append(cell)
	return result


## Die Zeilen des Regals von oben nach unten, eine je Gegenstand der Ablage, die neuesten zuerst
## (ein frisches Fundstück steht ganz oben):
## { "uid": int, "id": String, "rot": int, "level": int, "broken": bool, "rect": Rect2 (ganze
## Zeile), "origin": Vector2 (linke obere Ecke der Form), "cell": float (Kantenlänge eines Feldes,
## immer SHELF_CELL), "name_rect": Rect2 (Fläche für den Namen), "visible": bool (liegt wenigstens
## teilweise im sichtbaren Teil des Regals, shelf_view) }.
## Alle Rechtecke sind Koordinaten von board und schon um shelf_scroll() verschoben: Was
## hinausgerollt ist, liegt über oder unter shelf_view().
func shelf_layout() -> Array[Dictionary]:
	var rows: Array[Dictionary] = _shelf_rows()
	if rows.is_empty():
		return rows
	var view: Rect2 = shelf_view()
	var height: float = (rows[rows.size() - 1]["rect"] as Rect2).end.y
	var shift: Vector2 = Vector2(0.0, view.position.y - clampf(_shelf_scroll, 0.0, maxf(height - view.size.y, 0.0)))
	for row: Dictionary in rows:
		var rect: Rect2 = row["rect"]
		var name_rect: Rect2 = row["name_rect"]
		rect.position += shift
		name_rect.position += shift
		row["rect"] = rect
		row["name_rect"] = name_rect
		row["origin"] = (row["origin"] as Vector2) + shift
		row["visible"] = view.intersects(rect)
	return rows


## Sichtbare Fläche für die Zeilen des Regals: unter der Überschrift, links vom Rollbalken.
func shelf_view() -> Rect2:
	var inner: Rect2 = _shelf_inner()
	return Rect2(inner.position, Vector2(inner.size.x - SHELF_BAR_WIDTH - SHELF_BAR_GAP, inner.size.y))


## Höhe aller Zeilen des Regals zusammen (Pixel), 0 bei leerer Ablage.
func shelf_content_height() -> float:
	var rows: Array[Dictionary] = _shelf_rows()
	if rows.is_empty():
		return 0.0
	return (rows[rows.size() - 1]["rect"] as Rect2).end.y


## So weit ist das Regal nach unten gerollt (Pixel, 0 = ganz oben).
func shelf_scroll() -> float:
	return clampf(_shelf_scroll, 0.0, shelf_scroll_max())


## So weit lässt sich das Regal höchstens rollen: 0, solange alles hineinpasst.
func shelf_scroll_max() -> float:
	return maxf(shelf_content_height() - shelf_view().size.y, 0.0)


## Rollt das Regal an eine Stelle (Pixel von oben, wird auf den möglichen Bereich begrenzt).
func set_shelf_scroll(value: float) -> void:
	var before: float = _shelf_scroll
	_shelf_scroll = clampf(value, 0.0, shelf_scroll_max())
	if not is_equal_approx(before, _shelf_scroll):
		_after_scroll()


## Rollt das Regal um amount Pixel (positiv: nach unten). Das Mausrad rollt je Rastschritt um
## SHELF_WHEEL_STEP.
func scroll_shelf(amount: float) -> void:
	set_shelf_scroll(shelf_scroll() + amount)


## Rollt das Regal so, dass die Zeile dieses Gegenstands ganz zu sehen ist. false, wenn er nicht
## in der Ablage liegt.
func scroll_to_item(uid: int) -> bool:
	var view: Rect2 = shelf_view()
	for row: Dictionary in shelf_layout():
		if int(row["uid"]) != uid:
			continue
		var rect: Rect2 = row["rect"]
		if rect.position.y < view.position.y:
			set_shelf_scroll(shelf_scroll() - (view.position.y - rect.position.y))
		elif rect.end.y > view.end.y:
			set_shelf_scroll(shelf_scroll() + minf(rect.end.y - view.end.y, rect.position.y - view.position.y))
		return true
	return false


## Der Rollbalken des Regals: { "track": Rect2 (ganze Bahn), "thumb": Rect2 (Griff) }. Leer,
## solange alles ins Regal passt (dann gibt es nichts zu rollen und keinen Balken).
func shelf_bar() -> Dictionary:
	var limit: float = shelf_scroll_max()
	if limit <= 0.0:
		return {}
	var inner: Rect2 = _shelf_inner()
	var track: Rect2 = Rect2(inner.end.x - SHELF_BAR_WIDTH, inner.position.y, SHELF_BAR_WIDTH, inner.size.y)
	var length: float = maxf(SHELF_THUMB_MIN, track.size.y * track.size.y / (track.size.y + limit))
	var top: float = track.position.y + (track.size.y - length) * shelf_scroll() / limit
	return {"track": track, "thumb": Rect2(track.position.x, top, SHELF_BAR_WIDTH, length)}


## Rechteck der Zeile index im Regal (von oben gezählt, die neueste zuerst). Für einen index
## hinter der letzten Zeile: die nächste freie Zeile.
func storage_rect(index: int) -> Rect2:
	var layout: Array[Dictionary] = shelf_layout()
	if index >= 0 and index < layout.size():
		return layout[index]["rect"] as Rect2
	var view: Rect2 = shelf_view()
	var top: float = view.position.y if layout.is_empty() else (layout[layout.size() - 1]["rect"] as Rect2).end.y + SHELF_GAP
	return Rect2(view.position.x, top + float(maxi(index - layout.size(), 0)) * (SHELF_CELL + SHELF_GAP), view.size.x, SHELF_CELL)


## Fläche, über der ein Loslassen "in die Ablage" bedeutet: das ganze Regal.
func storage_area() -> Rect2:
	return SHELF_RECT


## Fläche des Felds "REPARIEREN".
func repair_rect() -> Rect2:
	return REPAIR_RECT


## Fläche des Felds "VERSCHROTTEN".
func scrap_rect() -> Rect2:
	return SCRAP_RECT


## Fläche des Felds "VERKAUFEN".
func sell_rect() -> Rect2:
	return SELL_RECT


## Welches der drei Felder unter einer Position liegt: ACTION_REPAIR, ACTION_SCRAP, ACTION_SELL
## oder ACTION_NONE.
func action_at(board_pos: Vector2) -> int:
	if REPAIR_RECT.has_point(board_pos):
		return ACTION_REPAIR
	if SCRAP_RECT.has_point(board_pos):
		return ACTION_SCRAP
	if SELL_RECT.has_point(board_pos):
		return ACTION_SELL
	return ACTION_NONE


## uid des Gegenstands unter einer Position (Raster oder sichtbarer Teil des Regals), -1 wenn
## dort keiner liegt.
func item_at(board_pos: Vector2) -> int:
	if action_at(board_pos) != ACTION_NONE:
		return -1
	var cell: Vector2i = cell_at(board_pos)
	if cell.x >= 0:
		return Game.backpack.occupant(cell)
	if not shelf_view().has_point(board_pos):
		return -1
	for row: Dictionary in shelf_layout():
		# Die halbe Lücke über und unter der Zeile gehört dazu: So gibt es keine toten Streifen.
		if (row["rect"] as Rect2).grow_individual(0.0, SHELF_GAP * 0.5, 0.0, SHELF_GAP * 0.5).has_point(board_pos):
			return int(row["uid"])
	return -1


## Rechteck, in dem ein Gegenstand gerade gezeichnet wird (Koordinaten von board): im Raster das
## Rechteck um seine Felder, im Regal seine Zeile (auch wenn sie hinausgerollt ist), in der Hand
## die Form am Zeiger (über dem Raster eingerastet, über den drei Feldern klein links daneben).
## Ohne Größe, wenn es ihn nicht gibt.
func item_rect(uid: int) -> Rect2:
	var entry: Dictionary = Game.backpack.item(uid)
	if entry.is_empty():
		return Rect2()
	var id: String = str(entry["id"])
	if uid == _held_uid:
		return Rect2(_held_origin(), Vector2(ItemDefs.size(id, _held_rot)) * _held_cell())
	if bool(entry["placed"]):
		return Rect2(cell_rect(entry["pos"] as Vector2i).position, Vector2(ItemDefs.size(id, int(entry["rot"]))) * CELL)
	for row: Dictionary in shelf_layout():
		if int(row["uid"]) == uid:
			return row["rect"] as Rect2
	return Rect2()


## Fläche, auf der das Bild eines Gegenstands gerade sitzt (Koordinaten von board, wie item_rect):
## ein Quadrat mitten auf dem größten Quadrat seiner Form. Ohne Größe, wenn es ihn nicht gibt.
func icon_rect(uid: int) -> Rect2:
	var entry: Dictionary = Game.backpack.item(uid)
	if entry.is_empty():
		return Rect2()
	var id: String = str(entry["id"])
	if uid == _held_uid:
		return _icon_rect(id, _held_rot, _held_origin(), _held_cell(), _names_shown)
	if bool(entry["placed"]):
		return _icon_rect(id, int(entry["rot"]), cell_rect(entry["pos"] as Vector2i).position, CELL, _names_shown)
	for row: Dictionary in shelf_layout():
		if int(row["uid"]) == uid:
			return _icon_rect(id, int(row["rot"]), row["origin"] as Vector2, float(row["cell"]), false)
	return Rect2()


## Das größte Quadrat aus ganzen Feldern, das in die Form passt, in Feldern ab der linken oberen
## Ecke der Form: Rect2(Lage, Kante). Gibt es mehrere, liegt es in ihrer Mitte (eine lange Form
## trägt ihr Bild also mittig), solange es dort ganz in der Form bleibt, sonst auf dem Quadrat,
## das der Mitte am nächsten ist.
static func icon_block(id: String, rot: int = 0) -> Rect2:
	var key: String = "%s|%d" % [id, posmod(rot, 4)]
	if _icon_block_cache.has(key):
		return _icon_block_cache[key] as Rect2
	var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
	var extent: Vector2i = ItemDefs.size(id, rot)
	var result: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
	if shape.is_empty():
		return result
	var edge: int = mini(extent.x, extent.y)
	var blocks: Array[Vector2i] = []
	while edge >= 1 and blocks.is_empty():
		for y: int in extent.y - edge + 1:
			for x: int in extent.x - edge + 1:
				if _block_in_shape(shape, Vector2(float(x), float(y)), edge):
					blocks.append(Vector2i(x, y))
		if blocks.is_empty():
			edge -= 1
	if blocks.is_empty():
		blocks.append(shape[0])
		edge = 1
	var middle: Vector2 = Vector2.ZERO
	for block: Vector2i in blocks:
		middle += Vector2(block)
	middle /= float(blocks.size())
	if _block_in_shape(shape, middle, edge):
		result = Rect2(middle, Vector2(float(edge), float(edge)))
	else:
		var best: Vector2i = blocks[0]
		for block: Vector2i in blocks:
			if Vector2(block).distance_squared_to(middle) < Vector2(best).distance_squared_to(middle) - 0.0001:
				best = block
		result = Rect2(Vector2(best), Vector2(float(edge), float(edge)))
	_icon_block_cache[key] = result
	return result


## Liegt ein Quadrat der Kante edge an der Stelle pos (in Feldern, auch zwischen zwei Feldern)
## ganz auf Feldern der Form?
static func _block_in_shape(shape: Array[Vector2i], pos: Vector2, edge: int) -> bool:
	var last: Vector2 = pos + Vector2(float(edge), float(edge)) - Vector2(0.001, 0.001)
	for y: int in range(int(floor(pos.y + 0.001)), int(floor(last.y)) + 1):
		for x: int in range(int(floor(pos.x + 0.001)), int(floor(last.x)) + 1):
			if not shape.has(Vector2i(x, y)):
				return false
	return true


## Die Bilder, die beim letzten Zeichnen wirklich gezeichnet wurden (je Aufruf von ItemIcons.draw
## ein Eintrag): { "uid": int (0 für die Notlösung in der Hand-Anzeige), "id": String, "rect":
## Rect2, "tint": Color, "where": "board" (Raster), "shelf" (Regal, Koordinaten von board) oder
## "overlay" (in der Hand) }. Im Regal fehlt, was hinausgerollt ist.
func drawn_icons() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for where: String in ["board", "shelf", "overlay"]:
		for entry: Variant in _icon_draws[where] as Array:
			result.append(entry as Dictionary)
	return result


## uid des Gegenstands im Regal unter dem Zeiger, mit dem der gehaltene beim Loslassen
## zusammengelegt würde. -1, wenn nichts gehalten wird oder dort kein passender liegt (auch wenn
## einer der beiden kaputt ist).
func storage_merge_target() -> int:
	if _held_uid == -1 or not SHELF_RECT.has_point(_pointer):
		return -1
	var uid: int = item_at(_pointer)
	if uid == -1 or not Game.backpack.can_merge(_held_uid, uid):
		return -1
	return uid


## Scheitert das, worauf der Zeiger mit dem gehaltenen Gegenstand gerade zielt, nur daran, dass
## etwas kaputt ist? true, wenn ein kaputter Gegenstand über dem Raster gehalten wird oder über
## einem gleichen Gegenstand gleicher Rarität im Regal (oder ein heiler über einem solchen
## kaputten). Dann steht "Erst reparieren" in der Warnung und am gehaltenen Gegenstand.
func needs_repair_hint() -> bool:
	if _held_uid == -1 or action_at(_pointer) != ACTION_NONE:
		return false
	var pack: BackpackState = Game.backpack
	if not pack.has_item(_held_uid):
		return false
	if _over_grid(_pointer):
		return pack.is_broken(_held_uid)
	if not SHELF_RECT.has_point(_pointer):
		return false
	var other: int = item_at(_pointer)
	return other != -1 and _same_kind(_held_uid, other) and (pack.is_broken(_held_uid) or pack.is_broken(other))


## Setzt den Zeiger (Koordinaten von board). Der gehaltene Gegenstand folgt ihm, die Karte auch.
func set_pointer(board_pos: Vector2) -> void:
	_pointer = board_pos
	if _held_uid == -1:
		var hovered: int = item_at(board_pos)
		if hovered != _hover_uid:
			_hover_uid = hovered
			# Das Vormerken zum Verschrotten gilt nur, solange der Zeiger auf dem Gegenstand bleibt.
			if _scrap_uid != -1 and _scrap_uid != hovered:
				_disarm_scrap()
			_update_card()
	else:
		# Über einem gleichen Gegenstand (Zusammenlegen) braucht eine Waffe keine freie Hand.
		_update_warning()
		_move_card()
	_redraw_moving()
	_redraw_changed_faces()


## Lässt den gehaltenen Gegenstand an einer Position los: über einem der drei Felder reparieren,
## verschrotten oder verkaufen, über dem Regal ablegen (auf einem gleichen Gegenstand dort:
## zusammenlegen), über dem Raster einräumen oder zusammenlegen, sonst zurück.
func drop_at(board_pos: Vector2) -> bool:
	if _held_uid == -1:
		return false
	_pointer = board_pos
	var result: bool = false
	match action_at(board_pos):
		ACTION_REPAIR:
			result = drop_on_repair()
		ACTION_SCRAP:
			result = drop_on_scrap()
		ACTION_SELL:
			result = drop_on_sell()
		_:
			if storage_area().has_point(board_pos):
				var target: int = storage_merge_target()
				if target == -1 and needs_repair_hint():
					# Gleicher Gegenstand, aber einer ist kaputt: ablegen und sagen, warum.
					target = item_at(board_pos)
				result = drop_on_storage_item(target) if target != -1 else drop_on_storage()
			elif _over_grid(board_pos):
				result = drop_on_cell(cell_at(board_pos) - _grab)
			else:
				cancel_hold()
	_hover_uid = item_at(board_pos)
	_update_card()
	return result


## Ist die Karte am Gegenstand zu sehen?
func is_card_open() -> bool:
	return card.visible and _card_uid != -1


## uid des Gegenstands, den die Karte beschreibt, -1 ohne Karte.
func card_uid() -> int:
	return _card_uid if card.visible else -1


## Rechteck der Karte (Koordinaten von board), ohne Größe wenn keine Karte zu sehen ist.
func card_rect() -> Rect2:
	if not is_card_open():
		return Rect2()
	return Rect2(card.position, card.size)


## Alles, was auf der Karte steht, Zeile für Zeile (Name, Rarität, "Kaputt", Balken, Wirkung,
## Hinweise, Schlagworte, Verkaufswert, Ertrag beim Verschrotten). Leer ohne Karte.
func card_text() -> String:
	if not is_card_open():
		return ""
	var lines: PackedStringArray = PackedStringArray([card_name_label.text, card_subtitle_label.text])
	if not card_broken_label.text.is_empty():
		lines.append(card_broken_label.text)
	for bar: Dictionary in _card_bars:
		lines.append("%s: %s" % [str(bar["label"]), str(bar["text"])])
	for label: Label in [card_text_label, card_extra_label, card_tags_label, card_sell_label, card_scrap_label]:
		if not label.text.is_empty():
			lines.append(label.text)
	return "\n".join(lines)


## Die Wertebalken der Karte (wie stat_bars), leer ohne Karte.
func card_bars() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if is_card_open():
		result.assign(_card_bars)
	return result


## Wertebalken eines Gegenstands: je Balken { "key": String, "label": String, "text": String (die
## Zahl), "ratio": float (Länge von 0 bis 1) }. Leer für alles außer Waffen und Kameras.
## Waffen: Schaden je Schuss ("damage", mit Rarität, alle Kugeln eines Schusses zusammen),
## Schüsse je Sekunde ("rate"), Magazin ("magazine") und Nachladezeit ("reload"), jeweils im
## Verhältnis zum besten Wert aller Waffen (bei der Nachladezeit ist die kürzeste die beste).
## Kameras: Schaden, Schussfolge ("rate") und Reichweite ("range") aus ihren fertigen Werten
## (Game.cameras, in der Ablage die Grundwerte), im Verhältnis zum besten Grundwert aller Kameras
## derselben Rarität.
func stat_bars(uid: int) -> Array[Dictionary]:
	var bars: Array[Dictionary] = []
	var entry: Dictionary = Game.backpack.item(uid)
	if entry.is_empty():
		return bars
	var id: String = str(entry["id"])
	var level: int = int(entry["level"])
	if ItemDefs.is_weapon(id):
		var def: Dictionary = WeaponDefs.get_def(id)
		if def.is_empty():
			return bars
		var best: Dictionary = _weapon_best()
		var pellets: int = maxi(int(def.get("pellets", 1)), 1)
		var damage: float = float(def.get("damage", 0.0))
		var damage_text: String = UpgradeDefs.format_number(snappedf(damage * ItemDefs.weapon_damage_factor(level), 0.1))
		if pellets > 1:
			damage_text = "%d × %s" % [pellets, damage_text]
		var rate: float = float(def.get("fire_rate", 0.0)) * float(WeaponDefs.burst(id))
		var magazine: float = float(int(def.get("magazine", 0)))
		var reload_time: float = float(def.get("reload_time", 0.0))
		bars.append(_bar("damage", "Schaden", damage_text, damage * float(pellets) / float(best["damage"])))
		bars.append(_bar("rate", "Schüsse je s", UpgradeDefs.format_number(rate), rate / float(best["rate"])))
		bars.append(_bar("magazine", "Magazin", str(int(magazine)), magazine / float(best["magazine"])))
		bars.append(_bar("reload", "Nachladen", "%s s" % UpgradeDefs.format_number(reload_time),
				float(best["reload"]) / maxf(reload_time, 0.01)))
	elif ItemDefs.is_camera(id):
		var stats: Dictionary = Game.camera_entry("%d:0" % uid) if bool(entry["placed"]) else {}
		if stats.is_empty():
			stats = CameraDefs.stats(id, level)
		if stats.is_empty():
			return bars
		var best_damage: float = 0.0
		var best_interval: float = 0.0
		var best_range: float = 0.0
		for camera_id: String in CameraDefs.all_ids():
			best_damage = maxf(best_damage, CameraDefs.base(camera_id, "damage", level))
			best_range = maxf(best_range, CameraDefs.base(camera_id, "range", level))
			var base_interval: float = CameraDefs.base(camera_id, "interval", level)
			if base_interval > 0.0 and (best_interval <= 0.0 or base_interval < best_interval):
				best_interval = base_interval
		var damage: float = float(stats.get("damage", 0.0))
		var interval: float = float(stats.get("interval", 0.0))
		var reach: float = float(stats.get("range", 0.0))
		bars.append(_bar("damage", "Schaden", UpgradeDefs.format_number(snappedf(damage, 0.1)) if damage > 0.0 else "keiner",
				damage / maxf(best_damage, 0.01)))
		bars.append(_bar("rate", "Schussfolge", "alle %s s" % UpgradeDefs.format_number(interval), best_interval / maxf(interval, 0.01)))
		bars.append(_bar("range", "Reichweite", "%s m" % UpgradeDefs.format_number(snappedf(reach, 0.1)), reach / maxf(best_range, 0.01)))
	return bars


## Ist die Hilfe-Tafel "So geht es" zu sehen?
func is_help_open() -> bool:
	return help_panel.visible


## Blendet die Hilfe-Tafel ein oder aus.
func set_help_open(open: bool) -> void:
	help_panel.visible = open
	if open:
		UiStyle.pop(help_panel, 1.06, 0.15)


## Schaltet die Hilfe-Tafel um (Knopf "?", F1 oder H).
func toggle_help() -> void:
	set_help_open(not help_panel.visible)


## Was beim Loslassen über dem Raster passieren würde: leer, wenn nichts gehalten wird oder der
## Zeiger nicht über dem Raster steht (oder über einem der drei Felder). Sonst { "pos": Vector2i
## (linke obere Ecke), "cells": Array[Vector2i], "kind": PREVIEW_FIT / PREVIEW_MERGE /
## PREVIEW_BAD, "merge": uid oder -1, "broken": bool (passt nicht, weil er kaputt ist) }.
func drop_preview() -> Dictionary:
	if _held_uid == -1 or not _over_grid(_pointer):
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
	return {"pos": pos, "cells": covered, "kind": kind, "merge": target, "broken": pack.is_broken(_held_uid)}


## Texte der Karte für einen Gegenstand: { "name", "subtitle", "text", "extra", "sell",
## "scrap" (Ertrag beim Verschrotten), "broken" (Hinweis mit den Reparaturkosten, leer bei einem
## heilen Gegenstand) }. Leer, wenn es ihn nicht gibt.
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
		"scrap": "Verschrotten: +%d Material" % Game.scrap_value(uid),
		"broken": BROKEN_CARD_TEXT % Game.repair_cost(uid) if pack.is_broken(uid) else "",
	}


## Zeilen der Karte für eine eingeräumte Kamera: ihre fertigen Werte aus Game.cameras
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


## Fläche für die Namenszeile eines Gegenstands, dessen Form mit Feldern der Größe cell bei
## origin liegt: ein Streifen am unteren Rand seiner untersten Zeile (höchstens NAME_BAND_MAX
## hoch, das reicht für zwei kleine Zeilen), ohne den Rand der Form.
func name_area(id: String, rot: int, origin: Vector2, cell: float) -> Rect2:
	var foot: Rect2 = _foot_box(id, rot, origin, cell)
	var inset: float = _shape_inset(cell)
	return Rect2(foot.position.x + NAME_PAD, foot.end.y - inset - NAME_BAND_MAX, foot.size.x - 2.0 * NAME_PAD, NAME_BAND_MAX)


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

	_bar_box = UiStyle.make_box(Color(0.03, 0.015, 0.08, 0.72), Color(UiStyle.COL_PURPLE, 0.75), 2, 0.0, 8)
	_bar_box.shadow_size = 0
	_shelf_box = UiStyle.make_box(Color(0.04, 0.02, 0.11, 0.88), UiStyle.COL_CYAN, 4, 0.0, 8)
	_shelf_hot_box = UiStyle.make_box(Color(0.09, 0.07, 0.2, 0.92), UiStyle.COL_YELLOW, 5, 0.0, 8)
	# Je Feld ein ruhiger und ein heißer Rahmen in seiner Farbe, dazu ein roter für "geht nicht".
	var action_colors: Dictionary = {ACTION_REPAIR: REPAIR_COLOR, ACTION_SCRAP: SCRAP_COLOR, ACTION_SELL: SELL_COLOR}
	for action: int in action_colors:
		var color: Color = action_colors[action]
		var calm: StyleBoxFlat = UiStyle.make_box(Color(color.darkened(0.8), 0.92), color, 3, 0.0, 8)
		calm.shadow_size = 0
		var hot: StyleBoxFlat = UiStyle.make_box(color.darkened(0.7), UiStyle.COL_YELLOW, 5, 0.0, 8)
		hot.shadow_size = 0
		_action_boxes[action] = [calm, hot]
	_action_bad_box = UiStyle.make_box(Color(0.26, 0.02, 0.04), UiStyle.COL_RED, 5, 0.0, 8)
	_action_bad_box.shadow_size = 0

	# Zeichenfläche zuerst: Texte liegen darüber, die Maus geht trotzdem an sie (alle Texte
	# ignorieren die Maus), nur die Knöpfe FERTIG und "?" fangen ihre Klicks selbst.
	board = Control.new()
	board.name = "Board"
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(board)
	board.draw.connect(_draw_board)
	board.gui_input.connect(_on_board_input)
	board.mouse_exited.connect(_on_board_mouse_exited)
	# Kinder von board liegen über seiner eigenen Zeichnung, in dieser Reihenfolge: erst die
	# Bilder der Gegenstände, dann alles, was darüber liegt.
	board_faces = _add_canvas(board, "Faces", _draw_board_faces)
	board_top = _add_canvas(board, "Top", _draw_board_top)

	# Die Zeilen des Regals auf einer eigenen Fläche, die abschneidet, was hinausgerollt ist.
	shelf_canvas = Control.new()
	shelf_canvas.name = "ShelfRows"
	shelf_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shelf_canvas.clip_contents = true
	var clip: Rect2 = _shelf_clip()
	UiStyle.anchor_box(shelf_canvas, Vector2.ZERO, clip.position, clip.size)
	stage.add_child(shelf_canvas)
	shelf_canvas.draw.connect(_draw_shelf_rows)
	shelf_top = _add_canvas(shelf_canvas, "Top", _draw_shelf_top)

	_build_top_bar(stage)

	storage_label = _add_label(stage, "StorageTitle", "ABLAGE", 20, UiStyle.COL_YELLOW, true,
			Rect2(SHELF_RECT.position + Vector2(SHELF_PAD + 2.0, 7.0), Vector2(SHELF_RECT.size.x - 2.0 * SHELF_PAD - 2.0, 30.0)))
	storage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	stats_label = _add_label(stage, "Stats", "", 15, UiStyle.COL_WHITE, false, STATS_RECT)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats_label.clip_text = true

	var repair_labels: Array[Label] = _build_action(stage, "Repair", REPAIR_RECT, REPAIR_TITLE, REPAIR_COLOR, REPAIR_IDLE_TEXT)
	repair_title_label = repair_labels[0]
	repair_value_label = repair_labels[1]
	var scrap_labels: Array[Label] = _build_action(stage, "Scrap", SCRAP_RECT, SCRAP_TITLE, SCRAP_COLOR, SCRAP_IDLE_TEXT)
	scrap_title_label = scrap_labels[0]
	scrap_value_label = scrap_labels[1]
	var sell_labels: Array[Label] = _build_action(stage, "Sell", SELL_RECT, SELL_TITLE, UiStyle.COL_YELLOW, SELL_IDLE_TEXT)
	sell_title_label = sell_labels[0]
	sell_value_label = sell_labels[1]

	_build_bottom_bar(stage)
	_build_help(stage)

	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(overlay)
	overlay.draw.connect(_draw_overlay)

	_build_card(stage)


## Legt eine Zeichenfläche über parent, so groß wie parent, die keine Maus fängt.
func _add_canvas(parent: Control, node_name: String, draw_func: Callable) -> Control:
	var canvas: Control = Control.new()
	canvas.name = node_name
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(canvas)
	canvas.draw.connect(draw_func)
	return canvas


## Texte eines der drei Felder rechts unten: Titel oben, darunter die Zeile mit dem Wert. Links
## bleibt ACTION_ICON_WIDTH frei für das Bild (zeichnet board). Gibt [Titel, Wert] zurück.
func _build_action(stage: Control, node_name: String, rect: Rect2, title: String, color: Color, idle: String) -> Array[Label]:
	var left: float = rect.position.x + ACTION_ICON_WIDTH
	var width: float = rect.size.x - ACTION_ICON_WIDTH - 8.0
	var title_label: Label = _add_label(stage, node_name + "Title", title, ACTION_TITLE_FONT_SIZE, color, true,
			Rect2(left, rect.position.y + 3.0, width, 26.0))
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(title, ACTION_TITLE_FONT_SIZE, width - 4.0, true, 13))
	var value_label: Label = _add_label(stage, node_name + "Value", idle, ACTION_VALUE_FONT_SIZE, UiStyle.COL_WHITE, false,
			Rect2(left, rect.position.y + 26.0, width, 22.0))
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.clip_text = true
	var result: Array[Label] = [title_label, value_label]
	return result


## Obere Leiste: Titel links, Hände in der Mitte (die Kästen zeichnet _draw_hands), Material,
## Punkte und der Knopf "?" rechts.
func _build_top_bar(stage: Control) -> void:
	_headline = UiStyle.make_headline("RUCKSACK", TITLE_FONT_SIZE, UiStyle.COL_PURPLE, UiStyle.COL_YELLOW, UiStyle.COL_CYAN)
	_headline.name = "Headline"
	_headline.pivot_offset_ratio = Vector2(0.5, 0.5)
	_headline.rotation_degrees = -2.0
	UiStyle.anchor_box(_headline, Vector2.ZERO, TITLE_POSITION, Vector2.ZERO)
	stage.add_child(_headline)
	headline_label = _headline.get_node("Label") as Label

	hands_label = _add_label(stage, "Hands", "", 20, UiStyle.COL_YELLOW, true, HANDS_TITLE_RECT)
	hands_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hands_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Das Zahnrad sitzt links im Feld (zeichnet board), der Text rechts daneben.
	var material_left: float = MATERIAL_ICON_SIZE + 8.0
	material_label = _add_label(stage, "Material", "", MATERIAL_FONT_SIZE, UiStyle.MATERIAL_COLOR, true,
			Rect2(MATERIAL_RECT.position.x + material_left, MATERIAL_RECT.position.y, MATERIAL_RECT.size.x - material_left, MATERIAL_RECT.size.y))
	material_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	material_label.pivot_offset_ratio = Vector2(0.0, 0.5)

	points_label = _add_label(stage, "Points", "", 24, UiStyle.COL_YELLOW, true, POINTS_RECT)
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	help_button = UiStyle.make_button("?", UiStyle.COL_CYAN, 24)
	help_button.name = "HelpButton"
	# Kein Tastatur-Fokus: Sonst verbraucht die Oberfläche die Tab-Taste für den Fokuswechsel.
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.custom_minimum_size = HELP_BUTTON_RECT.size
	help_button.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(help_button, Vector2.ZERO, HELP_BUTTON_RECT.position, HELP_BUTTON_RECT.size)
	stage.add_child(help_button)
	help_button.pressed.connect(toggle_help)


## Untere Leiste: Tastenhinweise links (an ihrer Stelle die Warnung, solange eine steht), Knopf
## FERTIG rechts.
func _build_bottom_bar(stage: Control) -> void:
	hint_label = _add_label(stage, "Hint", HINT_TEXT, HINT_FIT_SIZES[0], UiStyle.COL_CYAN, false, HINT_RECT)
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_constant_override("line_spacing", 0)
	# Die größte Schrift, mit der alle Hinweise in die Leiste passen.
	for font_size: int in HINT_FIT_SIZES:
		hint_label.add_theme_font_size_override("font_size", font_size)
		hint_label.size = HINT_RECT.size
		if hint_label.get_minimum_size().y <= HINT_RECT.size.y:
			break

	warning_label = _add_label(stage, "Warning", "", 20, UiStyle.COL_RED, false, WARNING_RECT)
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.pivot_offset_ratio = Vector2(0.5, 0.5)
	warning_label.visible = false

	done_button = UiStyle.make_button("FERTIG", UiStyle.COL_GREEN, 28)
	done_button.name = "Done"
	# Kein Tastatur-Fokus: Sonst verbraucht die Oberfläche die Tab-Taste für den Fokuswechsel.
	done_button.focus_mode = Control.FOCUS_NONE
	done_button.custom_minimum_size = DONE_RECT.size
	done_button.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(done_button, Vector2.ZERO, DONE_RECT.position, DONE_RECT.size)
	stage.add_child(done_button)
	done_button.pressed.connect(_on_done_pressed)


## Hilfe-Tafel "So geht es": rechts neben dem Rucksack über den drei Feldern, anfangs unsichtbar.
func _build_help(stage: Control) -> void:
	help_panel = Control.new()
	help_panel.name = "Help"
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.pivot_offset_ratio = Vector2(0.5, 0.5)
	UiStyle.anchor_box(help_panel, Vector2.ZERO, HELP_RECT.position, HELP_RECT.size)
	stage.add_child(help_panel)
	var plate: Panel = UiStyle.make_plate(Color(0.085, 0.045, 0.19, 0.96), UiStyle.COL_PINK, 4, 0.0, 8)
	plate.name = "Plate"
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help_panel.add_child(plate)
	var inner: Vector2 = HELP_RECT.size - Vector2(28.0, 0.0)
	var title: Label = _add_label(help_panel, "Title", HELP_TITLE, 20, UiStyle.COL_YELLOW, true, Rect2(14.0, 5.0, inner.x * 0.55, 28.0))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Wie die Hilfe wieder verschwindet, steht klein rechts neben dem Titel.
	var foot: Label = _add_label(help_panel, "Foot", HELP_FOOT_TEXT, 11, UiStyle.COL_CYAN, false,
			Rect2(14.0 + inner.x * 0.55, 5.0, inner.x * 0.45, 28.0))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var text_rect: Rect2 = Rect2(14.0, 36.0, inner.x, HELP_RECT.size.y - 36.0 - 8.0)
	help_text_label = _add_label(help_panel, "Text", HELP_TEXT, HELP_FIT_SIZES[0], UiStyle.COL_WHITE, false, text_rect)
	help_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_text_label.add_theme_constant_override("paragraph_spacing", HELP_PARAGRAPH_GAP)
	help_text_label.add_theme_constant_override("line_spacing", 0)
	# Die größte Schrift, mit der die ganze Erklärung in die Tafel passt.
	for font_size: int in HELP_FIT_SIZES:
		help_text_label.add_theme_font_size_override("font_size", font_size)
		if help_text_label.get_minimum_size().y <= text_rect.size.y:
			break
	help_panel.visible = false


## Karte am Gegenstand: Platte und Zeilen. Größe und Lage setzt _update_card.
func _build_card(stage: Control) -> void:
	card = Control.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(card)
	_card_box = UiStyle.make_box(CARD_FILL, UiStyle.COL_CYAN, 4, 0.0, 8)
	_card_plate = Panel.new()
	_card_plate.name = "Plate"
	_card_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_plate.add_theme_stylebox_override("panel", _card_box)
	card.add_child(_card_plate)
	card_name_label = _add_card_label("Name", CARD_NAME_SIZE, UiStyle.COL_YELLOW, true)
	card_subtitle_label = _add_card_label("Subtitle", CARD_LINE_SIZE, UiStyle.COL_CYAN, false)
	card_broken_label = _add_card_label("Broken", CARD_LINE_SIZE, UiStyle.COL_RED, false)
	card_bars_box = Control.new()
	card_bars_box.name = "Bars"
	card_bars_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(card_bars_box)
	card_bars_box.draw.connect(_draw_card_bars)
	card_text_label = _add_card_label("Text", int(CARD_FIT_SIZES[0][0]), UiStyle.COL_WHITE, false)
	card_extra_label = _add_card_label("Extra", int(CARD_FIT_SIZES[0][1]), UiStyle.COL_GREEN, false)
	card_tags_label = _add_card_label("Tags", CARD_LINE_SIZE - 1, UiStyle.COL_CYAN, false)
	card_sell_label = _add_card_label("Sell", CARD_LINE_SIZE, UiStyle.COL_ORANGE, false)
	card_scrap_label = _add_card_label("Scrap", CARD_LINE_SIZE, UiStyle.MATERIAL_COLOR, false)
	_card_parts = [card_name_label, card_subtitle_label, card_broken_label, card_bars_box, card_text_label,
			card_extra_label, card_tags_label, card_sell_label, card_scrap_label]
	card.visible = false


func _add_label(parent: Control, node_name: String, text: String, font_size: int, color: Color, slanted: bool,
		rect: Rect2) -> Label:
	var label: Label = UiStyle.make_label(text, font_size, color, slanted)
	label.name = node_name
	UiStyle.anchor_box(label, Vector2.ZERO, rect.position, rect.size)
	parent.add_child(label)
	return label


## Eine Zeile der Karte: bricht in der Breite der Karte um. Lage und Höhe setzt _layout_card.
func _add_card_label(node_name: String, font_size: int, color: Color, slanted: bool) -> Label:
	var label: Label = UiStyle.make_label("", font_size, color, slanted)
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(label)
	return label


# --- Signale und Anzeige --------------------------------------------------------------

func _on_backpack_opened(new_uid: int) -> void:
	_new_uid = new_uid if new_uid > 0 and Game.backpack.has_item(new_uid) else -1
	_held_uid = -1
	_hover_uid = -1
	_notice_left = 0.0
	_flash_left = 0.0
	_scrap_uid = -1
	_scrap_left = 0.0
	_bar_drag = false
	# Das Regal beginnt oben: Dort steht das neue Fundstück.
	_shelf_scroll = 0.0
	_pointer = Vector2(-10000.0, -10000.0)
	_faces_drawn = []
	_shelf_drawn = []
	_moving_drawn = []
	visible = true
	if is_inside_tree():
		# Ein Knopf eines anderen Bildschirms mit Fokus würde die Tab-Taste verbrauchen.
		get_viewport().gui_release_focus()
	# Die Erklärung steht beim ersten Öffnen in einem Programmlauf einmal von selbst da.
	help_panel.visible = not _help_shown
	_help_shown = true
	_refresh()
	_on_points_changed(Game.points)
	_show_materials(Game.materials)
	UiStyle.pop(_headline, 0.5, 0.25)


func _on_game_over(_stats: Dictionary) -> void:
	_hide()


func _hide() -> void:
	_held_uid = -1
	_hover_uid = -1
	_new_uid = -1
	_notice_left = 0.0
	_flash_left = 0.0
	_scrap_uid = -1
	_scrap_left = 0.0
	_bar_drag = false
	_card_uid = -1
	_card_bars.clear()
	card.visible = false
	_faces_drawn = []
	_shelf_drawn = []
	visible = false


func _on_points_changed(total: int) -> void:
	points_label.text = "PUNKTE: %s" % UiStyle.format_int(total)
	points_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(points_label.text, 24, POINTS_RECT.size.x, true, 16))


## Material hat sich geändert (Events.materials_changed): Zahl zeigen, bei einer echten Änderung
## ploppt sie kurz auf. Die drei Felder und die Karte rechnen mit dem neuen Stand.
func _on_materials_changed(total: int, delta: int) -> void:
	_show_materials(total)
	if not visible:
		return
	if delta != 0:
		UiStyle.pop(material_label, 1.3 if delta > 0 else 0.8, 0.25)
	_update_actions()
	board.queue_redraw()
	board_top.queue_redraw()
	shelf_canvas.queue_redraw()


func _show_materials(total: int) -> void:
	material_label.text = "MATERIAL %s" % UiStyle.format_int(total)
	material_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(material_label.text, MATERIAL_FONT_SIZE,
			MATERIAL_RECT.size.x - MATERIAL_ICON_SIZE - 12.0, true, MATERIAL_MIN_FONT_SIZE))


## Ein Gegenstand wurde repariert (Events.item_repaired): Er blitzt kurz auf.
func _on_item_repaired(uid: int) -> void:
	if not visible:
		return
	_flash(uid)
	_refresh()


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
	if _scrap_uid != -1 and not pack.has_item(_scrap_uid):
		_scrap_uid = -1
	_update_origin()
	_bag_cells = ghost_cells()
	# Nach jeder Änderung bleibt das Regal im möglichen Bereich (es kann kürzer geworden sein).
	_shelf_scroll = clampf(_shelf_scroll, 0.0, shelf_scroll_max())
	storage_label.text = "ABLAGE %d" % pack.storage_items().size()
	hands_label.text = "HÄNDE %d / %d" % [pack.hands_used(), Balance.PLAYER_HANDS]
	hands_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(hands_label.text, 20, HANDS_TITLE_RECT.size.x - 6.0, true, 14))
	_update_warning()
	_update_actions()
	_update_stats()
	_update_card()
	_redraw_moving()
	_redraw_changed_faces()


## Legt die linke obere Ecke des Rasters neu fest (siehe grid_origin).
func _update_origin() -> void:
	var pack: BackpackState = Game.backpack
	_origin_pack = pack
	_origin_count = pack.cell_count()
	var bounds: Rect2i = pack_bounds()
	var first: int = 0
	var end: int = BackpackState.COLS
	if bounds.size.x > 0:
		first = bounds.position.x
		end = bounds.end.x
	var low: float = PACK_MIN_X - float(first) * CELL
	var high: float = PACK_MAX_X - float(end) * CELL
	# Die freie Spalte direkt neben dem Rucksack bleibt (fast) ganz sichtbar.
	if first > 0:
		low = maxf(low, GHOST_MIN_X - float(first - 1) * CELL)
	if end < BackpackState.COLS:
		high = minf(high, GHOST_MAX_X - float(end + 1) * CELL)
	var middle: float = float(first + end) * 0.5
	_origin = Vector2(roundf(clampf(GRID_CENTER_X - middle * CELL, low, maxf(low, high))), GRID_TOP)


## Rote Warnung, das Wichtigste zuerst: "Erst reparieren" (ein kaputter Gegenstand wird gerade
## über das Raster oder einen gleichen gehalten), eine gehaltene Waffe, für die keine Hand frei
## ist (außer sie wird gerade mit einer gleichen zusammengelegt), das vorgemerkte Verschrotten,
## dann die Meldung nach einem abgelehnten Ablegen oder Reparieren.
func _update_warning() -> void:
	var pack: BackpackState = Game.backpack
	var text: String = ""
	var holding: bool = _held_uid != -1 and pack.has_item(_held_uid)
	if holding and needs_repair_hint():
		text = BROKEN_HINT_TEXT
	elif holding and not pack.is_broken(_held_uid) and not pack.has_free_hands(_held_uid) \
			and int(drop_preview().get("kind", PREVIEW_BAD)) != PREVIEW_MERGE and storage_merge_target() == -1:
		text = _no_hands_text(_held_uid)
	elif scrap_armed_uid() != -1 and pack.has_item(_scrap_uid):
		text = SCRAP_CONFIRM_TEXT % [ItemDefs.display_name(str(pack.item(_scrap_uid)["id"])), Game.scrap_value(_scrap_uid)]
	elif _notice_left > 0.0:
		text = _notice
	if not text.is_empty():
		warning_label.text = text
	warning_label.visible = not text.is_empty()
	# Die Warnung steht an der Stelle der Hinweise.
	hint_label.visible = text.is_empty()


## Zeigt eine Warnung für NOTICE_TIME Sekunden.
func _show_notice(text: String) -> void:
	_notice = text
	_notice_left = NOTICE_TIME
	_update_warning()
	UiStyle.pop(warning_label, 1.15, 0.2)


## Lässt einen Gegenstand nach dem Zusammenlegen oder Reparieren kurz aufleuchten.
func _flash(uid: int) -> void:
	_flash_uid = uid
	_flash_left = FLASH_TIME


## Nimmt die Vormerkung zum Verschrotten zurück (siehe press_scrap).
func _disarm_scrap() -> void:
	if _scrap_uid == -1:
		return
	_scrap_uid = -1
	_scrap_left = 0.0
	_update_warning()


## Derselbe Gegenstand in derselben Rarität (zwei, die sich zusammenlegen ließen, wenn beide heil
## wären)? Rucksack-Teile und Legendäre zählen nicht.
func _same_kind(uid: int, other_uid: int) -> bool:
	if uid == other_uid:
		return false
	var first: Dictionary = Game.backpack.item(uid)
	var second: Dictionary = Game.backpack.item(other_uid)
	if first.is_empty() or second.is_empty():
		return false
	var id: String = str(first["id"])
	return id == str(second["id"]) and int(first["level"]) == int(second["level"]) and ItemDefs.has_rarity(id) \
			and int(first["level"]) < ItemDefs.MAX_RARITY


## Nach dem Rollen des Regals: Unter dem Zeiger liegt jetzt vielleicht ein anderer Gegenstand.
func _after_scroll() -> void:
	if not visible:
		return
	if _held_uid == -1:
		var hovered: int = item_at(_pointer)
		if hovered != _hover_uid:
			_hover_uid = hovered
			if _scrap_uid != -1 and _scrap_uid != hovered:
				_disarm_scrap()
			_update_card()
		else:
			_move_card()
	else:
		_update_warning()
		_move_card()
	_redraw_moving()
	_redraw_changed_faces()


## Rollt das Regal von selbst, solange ein Gegenstand an seinen oberen oder unteren Rand gehalten
## wird: je näher am Rand, desto schneller.
func _auto_scroll(delta: float) -> void:
	if _held_uid == -1 or not SHELF_RECT.has_point(_pointer) or shelf_scroll_max() <= 0.0:
		return
	var view: Rect2 = shelf_view()
	var pull: float = 0.0
	if _pointer.y < view.position.y + SHELF_EDGE:
		pull = -clampf((view.position.y + SHELF_EDGE - _pointer.y) / SHELF_EDGE, 0.0, 1.0)
	elif _pointer.y > view.end.y - SHELF_EDGE:
		pull = clampf((_pointer.y - (view.end.y - SHELF_EDGE)) / SHELF_EDGE, 0.0, 1.0)
	if not is_zero_approx(pull):
		scroll_shelf(pull * SHELF_AUTO_SPEED * delta)


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


## Die Zeilen der drei Felder: ohne gehaltenen Gegenstand steht dort, was das Feld tut. Beim
## Halten steht dort, was das Loslassen bringt: "−2 Material" (rot mit "zu wenig", wenn das
## Material nicht reicht, rot "Ist nicht kaputt" bei einem heilen Gegenstand), "+2 Material",
## "+200 Punkte".
func _update_actions() -> void:
	var entry: Dictionary = Game.backpack.item(_held_uid) if _held_uid != -1 else {}
	if entry.is_empty():
		_set_action_value(repair_value_label, REPAIR_IDLE_TEXT, Color(UiStyle.COL_WHITE, 0.8), false)
		_set_action_value(scrap_value_label, SCRAP_IDLE_TEXT, Color(UiStyle.COL_WHITE, 0.8), false)
		_set_action_value(sell_value_label, SELL_IDLE_TEXT, Color(UiStyle.COL_WHITE, 0.8), false)
		return
	var cost: int = Game.repair_cost(_held_uid)
	if cost <= 0:
		_set_action_value(repair_value_label, REPAIR_INTACT_TEXT, UiStyle.COL_RED, true)
	elif Game.materials < cost:
		_set_action_value(repair_value_label, "−%d Material · zu wenig" % cost, UiStyle.COL_RED, true)
	else:
		_set_action_value(repair_value_label, "−%d Material" % cost, UiStyle.COL_GREEN, true)
	_set_action_value(scrap_value_label, "+%d Material" % Game.scrap_value(_held_uid), UiStyle.MATERIAL_COLOR, true)
	var amount: int = ItemDefs.sell_value(str(entry["id"]), int(entry["level"]))
	_set_action_value(sell_value_label, "+%s Punkte" % UiStyle.format_int(amount), UiStyle.COL_GREEN, true)


## Setzt Text, Farbe und Schriftgröße einer Zeile in einem der drei Felder (strong: größer).
func _set_action_value(label: Label, text: String, color: Color, strong: bool) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	var width: float = ACTION_SIZE.x - ACTION_ICON_WIDTH - 12.0
	label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(text,
			ACTION_VALUE_HOT_FONT_SIZE if strong else ACTION_VALUE_FONT_SIZE, width, false, 12))


## Würde "REPARIEREN" den gehaltenen Gegenstand ablehnen (er ist heil oder das Material reicht
## nicht)? false, wenn nichts gehalten wird.
func repair_refused() -> bool:
	return _held_uid != -1 and Game.backpack.has_item(_held_uid) and not Game.can_repair(_held_uid)


## Die Zeile unter dem Rucksack: freie Felder, Hände und Bonus durch Verstärker.
func _update_stats() -> void:
	var pack: BackpackState = Game.backpack
	var parts: PackedStringArray = PackedStringArray()
	parts.append("Freie Felder: %d von %d" % [pack.free_cell_count(), pack.cell_count()])
	parts.append("Hände: %d von %d" % [pack.hands_used(), Balance.PLAYER_HANDS])
	var bonus: PackedStringArray = PackedStringArray()
	var points: float = float(pack.stats().get("points", 0.0))
	if points > 0.0001:
		bonus.append("Punkte +%s %%" % UpgradeDefs.format_percent(points))
	# Schaden und Nachladen aus Verstärkern gelten je Waffe in der Hand.
	var weapons: Array[Dictionary] = Game.loadout
	for i: int in weapons.size():
		var weapon: Dictionary = weapons[i]
		# Eine Waffe nennt ihren Namen, zwei nennen ihre Hand (die Namen stehen in der oberen Leiste).
		var title: String = ItemDefs.display_name(str(weapon.get("id", "")))
		if weapons.size() > 1:
			title = "Links" if i == 0 else "Rechts"
		if float(weapon.get("damage", 0.0)) > 0.0001:
			bonus.append("%s: Schaden +%s %%" % [title, UpgradeDefs.format_percent(float(weapon["damage"]))])
		if float(weapon.get("reload", 0.0)) > 0.0001:
			bonus.append("%s: Nachladen +%s %%" % [title, UpgradeDefs.format_percent(float(weapon["reload"]))])
	if bonus.is_empty():
		parts.append("Noch kein Bonus durch Verstärker")
	else:
		parts.append_array(bonus)
	stats_label.text = " · ".join(parts)
	# Viele Angaben: kleinere Schrift, damit alles in die Zeile passt.
	stats_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(stats_label.text, 15, STATS_RECT.size.x - 8.0, false, 10))


## Karte am Gegenstand: für den gehaltenen Gegenstand, sonst für den unter dem Zeiger. Ohne
## Gegenstand gibt es keine Karte.
func _update_card() -> void:
	var uid: int = _held_uid if _held_uid != -1 else _hover_uid
	var info: Dictionary = describe(uid) if uid != -1 else {}
	if info.is_empty():
		_card_uid = -1
		_card_bars.clear()
		card.visible = false
		return
	var entry: Dictionary = Game.backpack.item(uid)
	var id: String = str(entry["id"])
	_card_uid = uid
	_card_accent = ItemDefs.rarity_color(int(entry["level"])) if ItemDefs.has_rarity(id) else UiStyle.COL_CYAN
	_card_box.border_color = _card_accent
	var width: float = CARD_WIDTH - 2.0 * CARD_PAD
	var title: String = str(info["name"])
	if uid == _new_uid:
		title = "NEU: " + title
	card_name_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(title, CARD_NAME_SIZE, width - 4.0, true, CARD_NAME_MIN_SIZE))
	card_name_label.text = title
	card_subtitle_label.text = str(info["subtitle"])
	card_subtitle_label.add_theme_font_size_override("font_size", UiStyle.fit_font_size(card_subtitle_label.text, CARD_LINE_SIZE, width - 2.0, false, CARD_LINE_MIN_SIZE))
	card_subtitle_label.add_theme_color_override("font_color", _card_accent)
	card_broken_label.text = str(info["broken"])
	# In der Hand ist die Karte kurz (Name, Rarität, "Kaputt"): So verdeckt sie beim Zielen wenig.
	# Die ganze Karte steht am Gegenstand, solange der Zeiger nur auf ihm liegt.
	var whole: bool = uid != _held_uid
	_card_bars.clear()
	if whole:
		_card_bars = stat_bars(uid)
	card_text_label.text = str(info["text"]) if whole else ""
	card_extra_label.text = str(info["extra"]) if whole else ""
	var tags: String = ItemDefs.tags_text(id)
	card_tags_label.text = "Schlagworte: %s" % tags if whole and not tags.is_empty() else ""
	card_tags_label.add_theme_color_override("font_color", ItemDefs.color(id))
	card_sell_label.text = str(info["sell"]) if whole else ""
	card_scrap_label.text = str(info["scrap"]) if whole else ""
	# Die größte Schrift, mit der die Karte nicht zu hoch wird.
	for sizes: Array in CARD_FIT_SIZES:
		card_text_label.add_theme_font_size_override("font_size", int(sizes[0]))
		card_extra_label.add_theme_font_size_override("font_size", int(sizes[1]))
		if _layout_card(width) <= CARD_MAX_HEIGHT:
			break
	card.visible = true
	card_bars_box.queue_redraw()
	_move_card()


## Setzt die Teile der Karte untereinander und gibt der Karte ihre Größe. Gibt die Höhe zurück.
func _layout_card(width: float) -> float:
	var top: float = CARD_PAD - 2.0
	for part: Control in _card_parts:
		var height: float = 0.0
		var label: Label = part as Label
		if label == null:
			height = float(_card_bars.size()) * BAR_ROW
		elif not label.text.is_empty():
			# Erst die Breite, dann die Höhe: Das Label bricht seinen Text in dieser Breite um.
			label.size = Vector2(width, 0.0)
			height = label.get_minimum_size().y
		part.visible = height > 0.0
		if height <= 0.0:
			continue
		part.position = Vector2(CARD_PAD, top)
		part.size = Vector2(width, height)
		top += height + CARD_SEPARATION
	var total: float = top - CARD_SEPARATION + CARD_PAD
	card.size = Vector2(CARD_WIDTH, total)
	_card_plate.position = Vector2.ZERO
	_card_plate.size = card.size
	return total


## Stellt die Karte neben ihren Gegenstand.
func _move_card() -> void:
	if _card_uid == -1 or not card.visible:
		return
	var holding: bool = _card_uid == _held_uid
	var anchors: Array[Rect2] = _card_anchors(_card_uid)
	var soft: Array[Rect2] = []
	var spare: Array[Vector2] = []
	if holding:
		# Die drei Felder bleiben frei, solange es geht: Rucksack und Regal gehen aber vor.
		var actions: Rect2 = _actions_rect()
		soft.append(actions)
		# Ist neben dem Gegenstand kein freier Platz, steht die Karte rechts neben dem Rucksack über
		# den drei Feldern (dort ist frei, solange der Rucksack klein ist).
		var top: float = minf(anchors[anchors.size() - 1].position.y, actions.position.y - CARD_GAP - card.size.y)
		spare.append(Vector2(pack_rect().end.x + PACK_PAD + CARD_GAP, maxf(top, TOP_BAR_RECT.end.y + CARD_GAP)))
	card.position = _card_position(anchors, card.size, _card_avoid(_card_uid), soft, spare, holding)


## Flächen, neben denen die Karte stehen soll, die liebste zuerst. Die letzte ist der Gegenstand
## selbst. Davor steht beim Halten die größere Fläche mit allem, worauf man gerade zielt: seine
## Sterne im Raster, der Gegenstand im Regal, mit dem er zusammengelegt würde, die drei Felder.
func _card_anchors(uid: int) -> Array[Rect2]:
	var plain: Rect2 = item_rect(uid)
	var anchors: Array[Rect2] = []
	if uid == _held_uid:
		var wide: Rect2 = plain
		var preview: Dictionary = drop_preview()
		if not preview.is_empty() and int(preview["kind"]) != PREVIEW_MERGE:
			var id: String = str(Game.backpack.item(uid).get("id", ""))
			for star: Vector2i in BackpackState.stars_at(id, preview["pos"] as Vector2i, _held_rot):
				if BackpackState.in_bounds(star):
					wide = wide.merge(cell_rect(star))
		var target: int = storage_merge_target()
		if target == -1 and needs_repair_hint() and SHELF_RECT.has_point(_pointer):
			target = item_at(_pointer)
		if target != -1:
			wide = wide.merge(_shelf_strip(item_rect(target)))
		if action_at(_pointer) != ACTION_NONE:
			wide = wide.merge(_actions_rect())
		if wide != plain:
			anchors.append(wide)
	elif not Game.backpack.is_placed(uid):
		# Im Regal: Die Karte steht neben dem Regal, nicht darauf.
		plain = _shelf_strip(plain)
	anchors.append(plain)
	return anchors


## Die Zeile eines Gegenstands im Regal, verbreitert auf das ganze Regal.
func _shelf_strip(row: Rect2) -> Rect2:
	var top: float = clampf(row.position.y, SHELF_RECT.position.y, SHELF_RECT.end.y)
	var bottom: float = clampf(row.end.y, SHELF_RECT.position.y, SHELF_RECT.end.y)
	return Rect2(SHELF_RECT.position.x, top, SHELF_RECT.size.x, maxf(bottom - top, 1.0))


## Die drei Felder rechts unten zusammen als eine Fläche.
func _actions_rect() -> Rect2:
	return REPAIR_RECT.merge(SCRAP_RECT).merge(SELL_RECT)


## Flächen, die die Karte nicht verdecken soll, solange es dafür eine Seite gibt. Beim Halten:
## Rucksack und Regal (die drei Felder kommen als weicher Wunsch dazu, siehe _move_card). Sonst
## das, womit der Gegenstand zusammenhängt: seine Sternfelder im Rucksack und die Gegenstände,
## die auf ihn wirken.
func _card_avoid(uid: int) -> Array[Rect2]:
	var avoid: Array[Rect2] = []
	var pack: BackpackState = Game.backpack
	if uid == _held_uid:
		avoid.append(pack_rect())
		avoid.append(SHELF_RECT)
		return avoid
	if not pack.is_placed(uid):
		return avoid
	for cell: Vector2i in pack.star_cells_of(uid):
		if pack.has_cell(cell):
			avoid.append(cell_rect(cell))
	for other: int in pack.mods_of(uid):
		avoid.append(item_rect(other))
	return avoid


## Lage der Karte: rechts neben der Fläche, bei Platzmangel links, immer ganz in der Bühne.
## Zuerst wird eine Seite gesucht, auf der die Karte nichts aus avoid und soft verdeckt (beim
## Halten, holding, darf sie dafür auch unter oder über dem Gegenstand stehen, danach kommen die
## Ausweichplätze aus spare), dann eine, auf der sie nur avoid frei lässt, dann eine beliebige.
## Passt sie nirgends daneben, kommt sie auf die Seite mit mehr Platz.
func _card_position(anchors: Array[Rect2], card_size: Vector2, avoid: Array[Rect2], soft: Array[Rect2], spare: Array[Vector2],
		holding: bool) -> Vector2:
	var bounds: Rect2 = Rect2(Vector2.ZERO, STAGE_SIZE).grow(-CARD_MARGIN)
	var low: float = maxf(bounds.position.y, bounds.end.y - card_size.y)
	var plain: Rect2 = anchors[anchors.size() - 1]
	var left: float = clampf(plain.position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - card_size.x))
	var all_blocked: Array[Rect2] = []
	all_blocked.append_array(avoid)
	all_blocked.append_array(soft)
	var levels: Array[Array] = [all_blocked, avoid, []]
	for level: int in levels.size():
		var careful: bool = level < levels.size() - 1
		var blocked_now: Array = levels[level]
		if careful and (blocked_now.is_empty() or (level == 1 and soft.is_empty())):
			continue
		var spots: Array[Vector2] = []
		for anchor: Rect2 in anchors:
			var top: float = clampf(anchor.position.y, bounds.position.y, low)
			spots.append(Vector2(anchor.end.x + CARD_GAP, top))
			spots.append(Vector2(anchor.position.x - CARD_GAP - card_size.x, top))
		if holding or not careful:
			spots.append(Vector2(left, plain.end.y + CARD_GAP))
			spots.append(Vector2(left, plain.position.y - CARD_GAP - card_size.y))
		if careful:
			spots.append_array(spare)
		for spot: Vector2 in spots:
			var area: Rect2 = Rect2(spot, card_size)
			if not bounds.encloses(area) or area.intersects(plain):
				continue
			var free: bool = true
			for blocked: Rect2 in blocked_now:
				if area.intersects(blocked):
					free = false
			if free:
				return spot
	var room_right: float = bounds.end.x - plain.end.x
	var room_left: float = plain.position.x - bounds.position.x
	var side: float = bounds.end.x - card_size.x if room_right >= room_left else bounds.position.x
	return Vector2(side, clampf(plain.position.y, bounds.position.y, low))


## Ein Wertebalken (siehe stat_bars). Die Länge liegt zwischen 0 und 1.
func _bar(key: String, label: String, text: String, ratio: float) -> Dictionary:
	return {"key": key, "label": label, "text": text, "ratio": clampf(ratio, 0.0, 1.0)}


## Beste Werte aller Waffen für die Wertebalken: { "damage": höchster Schaden je Schuss (alle
## Kugeln zusammen, ohne Rarität), "rate": meiste Schüsse je Sekunde, "magazine": größtes
## Magazin, "reload": kürzeste Nachladezeit }.
static func _weapon_best() -> Dictionary:
	if not _weapon_best_cache.is_empty():
		return _weapon_best_cache
	var best: Dictionary = {"damage": 0.01, "rate": 0.01, "magazine": 1.0, "reload": 0.0}
	for weapon_id: String in WeaponDefs.all_ids():
		var def: Dictionary = WeaponDefs.get_def(weapon_id)
		best["damage"] = maxf(float(best["damage"]), float(def.get("damage", 0.0)) * float(maxi(int(def.get("pellets", 1)), 1)))
		best["rate"] = maxf(float(best["rate"]), float(def.get("fire_rate", 0.0)) * float(WeaponDefs.burst(weapon_id)))
		best["magazine"] = maxf(float(best["magazine"]), float(int(def.get("magazine", 0))))
		var reload_time: float = float(def.get("reload_time", 0.0))
		if reload_time > 0.0 and (float(best["reload"]) <= 0.0 or reload_time < float(best["reload"])):
			best["reload"] = reload_time
	_weapon_best_cache = best
	return best


## Innenfläche des Regals unter seiner Überschrift (mit dem Rollbalken am rechten Rand).
func _shelf_inner() -> Rect2:
	return SHELF_RECT.grow_individual(-SHELF_PAD, -SHELF_HEAD, -SHELF_PAD, -SHELF_PAD)


## Fläche, auf der die Zeilen des Regals gezeichnet werden: der sichtbare Teil, links und rechts
## etwas breiter (für die Hinterlegung der Zeile unter dem Zeiger). Was darüber hinausragt, wird
## abgeschnitten.
func _shelf_clip() -> Rect2:
	return shelf_view().grow_individual(5.0, 5.0, 3.0, 5.0)


## Baut die Zeilen des Regals ohne Rollen: Die erste beginnt bei y = 0, x ist schon die Lage in
## board (siehe shelf_layout). Die neuesten Gegenstände (höchste uid) stehen oben. Jede Form hat
## Felder der Größe SHELF_CELL, der Name steht daneben oder (bei breiten Formen) darunter.
func _shelf_rows() -> Array[Dictionary]:
	var storage: Array[Dictionary] = Game.backpack.storage_items()
	storage.reverse()
	var view: Rect2 = shelf_view()
	var layout: Array[Dictionary] = []
	var top: float = 0.0
	for entry: Dictionary in storage:
		var id: String = str(entry["id"])
		var rot: int = int(entry["rot"])
		var shape_size: Vector2 = Vector2(ItemDefs.size(id, rot)) * SHELF_CELL
		var name_width: float = view.size.x - shape_size.x - SHELF_NAME_GAP
		if bool(entry.get("broken", false)):
			name_width -= SHELF_REPAIR_ROOM
		var beside: bool = name_width >= SHELF_NAME_MIN
		var height: float = shape_size.y + (0.0 if beside else SHELF_CAPTION)
		var name_rect: Rect2 = Rect2(view.position.x, top + shape_size.y, view.size.x, SHELF_CAPTION)
		if beside:
			name_rect = Rect2(view.position.x + shape_size.x + SHELF_NAME_GAP, top, name_width, shape_size.y)
		layout.append({
			"uid": int(entry["uid"]), "id": id, "rot": rot, "level": int(entry["level"]),
			"broken": bool(entry.get("broken", false)),
			"rect": Rect2(view.position.x, top, view.size.x, height),
			"origin": Vector2(view.position.x, top),
			"cell": SHELF_CELL, "name_rect": name_rect, "visible": true,
		})
		top += height + SHELF_GAP
	return layout


## Linke obere Ecke der gehaltenen Form: über dem Raster in die Felder eingerastet, über den drei
## Feldern rechts unten links neben ihnen auf der Höhe des Zeigers, sonst so, dass das angefasste
## Feld unter dem Zeiger liegt.
func _held_origin() -> Vector2:
	var preview: Dictionary = drop_preview()
	if not preview.is_empty():
		return cell_rect(preview["pos"] as Vector2i).position
	var entry: Dictionary = Game.backpack.item(_held_uid)
	if action_at(_pointer) != ACTION_NONE and not entry.is_empty():
		var extent: Vector2 = Vector2(ItemDefs.size(str(entry["id"]), _held_rot)) * HELD_DOCK_CELL
		var top: float = clampf(_pointer.y - extent.y * 0.5, TOP_BAR_RECT.end.y + 4.0, BOTTOM_BAR_RECT.position.y - extent.y - 4.0)
		return Vector2(REPAIR_RECT.position.x - extent.x - HELD_DOCK_GAP, top)
	return _pointer - (Vector2(_grab) + Vector2(0.5, 0.5)) * CELL


## Kantenlänge der Felder des gehaltenen Gegenstands: über den drei Feldern rechts unten ist er
## kleiner (siehe _held_origin), sonst so groß wie im Raster.
func _held_cell() -> float:
	return HELD_DOCK_CELL if _held_uid != -1 and action_at(_pointer) != ACTION_NONE else CELL


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
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _bar_drag:
			_drag_bar(motion.position.y)
		set_pointer(motion.position)
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		# Mausrad über dem Regal rollt es (auch mit einem Gegenstand in der Hand).
		if button.pressed and SHELF_RECT.has_point(button.position):
			board.accept_event()
			_pointer = button.position
			var steps: float = maxf(button.factor, 1.0)
			scroll_shelf(SHELF_WHEEL_STEP * steps * (-1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0))
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
		if _bar_drag:
			_bar_drag = false
		elif _held_uid != -1:
			drop_at(button.position)
		return
	if _held_uid != -1:
		# Die Maustaste wurde außerhalb des Fensters losgelassen: Der nächste Klick legt ab.
		drop_at(button.position)
		return
	if _on_shelf_bar(button.position):
		# Klick auf den Rollbalken: Der Griff springt zur Maus und folgt ihr.
		_bar_drag = true
		_drag_bar(button.position.y)
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


## Liegt die Position auf dem Rollbalken des Regals (mit etwas Rand zum leichteren Treffen)?
func _on_shelf_bar(board_pos: Vector2) -> bool:
	var bar: Dictionary = shelf_bar()
	return not bar.is_empty() and (bar["track"] as Rect2).grow_individual(SHELF_BAR_GAP - 1.0, 0.0, SHELF_PAD, 0.0).has_point(board_pos)


## Zieht den Griff des Rollbalkens so, dass seine Mitte auf der Höhe y liegt.
func _drag_bar(y: float) -> void:
	var bar: Dictionary = shelf_bar()
	if bar.is_empty():
		_bar_drag = false
		return
	var track: Rect2 = bar["track"]
	var length: float = (bar["thumb"] as Rect2).size.y
	var room: float = maxf(track.size.y - length, 1.0)
	set_shelf_scroll(clampf((y - track.position.y - length * 0.5) / room, 0.0, 1.0) * shelf_scroll_max())


func _on_board_mouse_exited() -> void:
	if _held_uid == -1 and _hover_uid != -1:
		_hover_uid = -1
		_disarm_scrap()
		_update_card()


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
	_live = false
	_update_origin()
	board.draw_style_box(_bar_box, TOP_BAR_RECT)
	board.draw_style_box(_bar_box, BOTTOM_BAR_RECT)
	_draw_pack(pack, pulse)
	for entry: Dictionary in pack.placed_items():
		var uid: int = int(entry["uid"])
		var id: String = str(entry["id"])
		var rot: int = int(entry["rot"])
		var origin: Vector2 = cell_rect(entry["pos"] as Vector2i).position
		# Der gehaltene Gegenstand bleibt an seinem alten Platz als Schatten sichtbar.
		_draw_shape(board, id, rot, origin, CELL, uid == _held_uid, int(entry["level"]), false)
	_draw_links(pack)
	_board_live = _live


## Bilder, Kästchen der Rarität, Schilder und Namen der eingeräumten Gegenstände (board_faces).
## Hängt nicht von der Zeit ab: wird nur neu gezeichnet, wenn sich _faces_state ändert.
func _draw_board_faces() -> void:
	(_icon_draws["board"] as Array).clear()
	if not visible:
		return
	_update_origin()
	for entry: Dictionary in Game.backpack.placed_items():
		var uid: int = int(entry["uid"])
		if uid == _held_uid:
			continue
		_draw_item_face(board_faces, "board", uid, str(entry["id"]), int(entry["rot"]),
				cell_rect(entry["pos"] as Vector2i).position, CELL, int(entry["level"]), false, _names_shown, true)


## Alles über den Gegenständen (board_top), in der Reihenfolge von früher: Rahmen um einzelne
## Gegenstände, Sterne, Hände, Zahnrad, Ziel beim Zusammenlegen, Regalrahmen, die drei Felder,
## Aufleuchten.
func _draw_board_top() -> void:
	_top_live = false
	if not visible:
		return
	var pack: BackpackState = Game.backpack
	var pulse: float = 0.5 + 0.5 * sin(_pulse * 6.0)
	_live = false
	var marks: Array[Dictionary] = star_marks()
	var related: Array[int] = _related_items(marks)
	var armed: int = scrap_armed_uid()
	for entry: Dictionary in pack.placed_items():
		var uid: int = int(entry["uid"])
		if uid == _held_uid:
			continue
		var id: String = str(entry["id"])
		var rot: int = int(entry["rot"])
		var origin: Vector2 = cell_rect(entry["pos"] as Vector2i).position
		if related.has(uid):
			# Gehört zum Gegenstand unter dem Zeiger (oder zum gehaltenen): Waffe, auf die er wirkt,
			# oder Gegenstand, der auf die Waffe wirkt.
			_live = true
			_draw_outline(board_top, ItemDefs.cells(id, rot), origin, CELL, Color(UiStyle.COL_YELLOW, 0.65 + 0.35 * pulse), 4.0)
		if uid == _hover_uid and _held_uid == -1:
			_draw_outline(board_top, ItemDefs.cells(id, rot), origin, CELL, UiStyle.COL_WHITE, 3.0)
		if uid == armed:
			_draw_scrap_mark(board_top, ItemDefs.cells(id, rot), origin, CELL, pulse)
	# Sterne über allen Gegenständen.
	_draw_star_marks(board_top, marks, false)
	_draw_hands()
	_draw_material_icon()
	# Beim Zusammenlegen leuchtet das Ziel.
	var preview: Dictionary = drop_preview()
	if not preview.is_empty() and int(preview["merge"]) != -1:
		var target: Dictionary = pack.item(int(preview["merge"]))
		if not target.is_empty():
			_live = true
			_draw_outline(board_top, ItemDefs.cells(str(target["id"]), int(target["rot"])),
					cell_rect(target["pos"] as Vector2i).position, CELL, Color(UiStyle.COL_YELLOW, 0.6 + 0.4 * pulse), 5.0)
	_draw_shelf_frame()
	_draw_actions(pulse)
	_draw_flash(board_top, true)
	_top_live = _live


## Der Rucksack: nur die Felder, die es gibt, als eine Fläche mit Umriss und Schatten. Solange
## ein Rucksack-Teil gehalten wird, dazu blass die Felder, die es neu anlegen könnte.
func _draw_pack(pack: BackpackState, pulse: float) -> void:
	var rects: Array[Rect2] = []
	for cell: Vector2i in pack.cells():
		rects.append(cell_rect(cell))
	# Jedes Feld wird etwas größer gemalt: Zusammen ergibt das eine Fläche mit gleich breitem Rand.
	for rect: Rect2 in rects:
		board.draw_rect(Rect2(rect.position + PACK_SHADOW, rect.size).grow(PACK_PAD), Color(0.01, 0.0, 0.03))
	for rect: Rect2 in rects:
		board.draw_rect(rect.grow(PACK_PAD), UiStyle.COL_CYAN)
	for rect: Rect2 in rects:
		board.draw_rect(rect.grow(PACK_PAD - PACK_BORDER), UiStyle.COL_PANEL_SOLID)
	for rect: Rect2 in rects:
		board.draw_rect(rect.grow(-2.0), CELL_FILL)
		board.draw_rect(rect.grow(-3.0), CELL_EDGE, false, 2.0)
	for cell: Vector2i in _bag_cells:
		if pack.has_cell(cell):
			continue
		var ghost: Rect2 = cell_rect(cell).grow(-6.0)
		_live = true
		board.draw_rect(ghost, Color(ItemDefs.BAG_COLOR, 0.07 + 0.05 * pulse))
		board.draw_rect(ghost, Color(CELL_GHOST, CELL_GHOST.a + 0.15 * pulse), false, 2.0)


## Zahnrad vor "MATERIAL n" in der oberen Leiste.
func _draw_material_icon() -> void:
	var center: Vector2 = MATERIAL_RECT.position + Vector2(MATERIAL_ICON_SIZE * 0.5 + 2.0, MATERIAL_RECT.size.y * 0.5)
	var radius: float = MATERIAL_ICON_SIZE * 0.5
	UiStyle.draw_gear(board_top, center + Vector2(0.0, 2.0), radius, UiStyle.COL_INK, UiStyle.COL_INK)
	UiStyle.draw_gear(board_top, center, radius - 1.5, UiStyle.MATERIAL_COLOR, UiStyle.COL_INK)


## Die drei Felder rechts unten mit ihrem Bild: Schraubenschlüssel, Zahnrad, Münze. Das Feld unter
## dem gehaltenen Gegenstand leuchtet, "REPARIEREN" wird rot, wenn es ihn ablehnen würde.
func _draw_actions(pulse: float) -> void:
	var holding: bool = _held_uid != -1
	var hot_action: int = action_at(_pointer) if holding else ACTION_NONE
	var refused: bool = repair_refused()
	for action: int in [ACTION_REPAIR, ACTION_SCRAP, ACTION_SELL]:
		var rect: Rect2 = REPAIR_RECT
		var color: Color = REPAIR_COLOR
		if action == ACTION_SCRAP:
			rect = SCRAP_RECT
			color = SCRAP_COLOR
		elif action == ACTION_SELL:
			rect = SELL_RECT
			color = SELL_COLOR
		var boxes: Array = _action_boxes[action]
		var box: StyleBoxFlat = boxes[0]
		var bad: bool = action == ACTION_REPAIR and refused
		if action == hot_action:
			box = _action_bad_box if bad else boxes[1] as StyleBoxFlat
		board_top.draw_style_box(box, rect)
		if holding and action != hot_action and not bad:
			# Beim Halten laden die Felder ein: Ihr Rahmen pulsiert leicht.
			_live = true
			board_top.draw_rect(rect.grow(-1.0), Color(color, 0.25 + 0.35 * pulse), false, 2.0)
		var center: Vector2 = rect.position + Vector2(ACTION_ICON_WIDTH * 0.5 + 2.0, rect.size.y * 0.5)
		var extent: float = rect.size.y - 20.0
		var back: Color = box.bg_color
		match action:
			ACTION_REPAIR:
				UiStyle.draw_wrench(board_top, center + Vector2(0.0, 2.0), extent + 3.0, UiStyle.COL_INK, UiStyle.COL_INK)
				UiStyle.draw_wrench(board_top, center, extent, UiStyle.COL_RED if bad else REPAIR_COLOR, back)
			ACTION_SCRAP:
				UiStyle.draw_gear(board_top, center + Vector2(0.0, 2.0), extent * 0.5 + 1.5, UiStyle.COL_INK, UiStyle.COL_INK)
				UiStyle.draw_gear(board_top, center, extent * 0.5, SCRAP_COLOR, back)
			_:
				board_top.draw_circle(center + Vector2(0.0, 2.0), extent * 0.5 + 1.5, UiStyle.COL_INK)
				board_top.draw_circle(center, extent * 0.5, UiStyle.COL_YELLOW)
				board_top.draw_arc(center, extent * 0.3, 0.0, TAU, 20, UiStyle.COL_ORANGE, 2.5)


## Lässt den gerade zusammengelegten oder reparierten Gegenstand kurz aufleuchten: ein heller
## Rahmen, der sich weitet und verblasst. in_grid: auf dem Brett (Gegenstand im Raster), sonst
## auf der Fläche des Regals.
func _draw_flash(canvas: Control, in_grid: bool) -> void:
	if _flash_left <= 0.0 or _flash_uid == _held_uid:
		return
	var entry: Dictionary = Game.backpack.item(_flash_uid)
	if entry.is_empty() or bool(entry["placed"]) != in_grid:
		return
	var id: String = str(entry["id"])
	var rot: int = int(entry["rot"])
	var origin: Vector2 = Vector2.ZERO
	var cell: float = CELL
	if in_grid:
		origin = cell_rect(entry["pos"] as Vector2i).position
	else:
		var found: bool = false
		for row: Dictionary in shelf_layout():
			if int(row["uid"]) == _flash_uid:
				origin = row["origin"] as Vector2
				cell = float(row["cell"])
				found = true
		if not found:
			return
	var left: float = clampf(_flash_left / FLASH_TIME, 0.0, 1.0)
	var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
	_live = true
	for entry_cell: Vector2i in shape:
		canvas.draw_rect(Rect2(origin + Vector2(entry_cell) * cell, Vector2(cell, cell)), Color(UiStyle.COL_WHITE, 0.55 * left))
	_draw_outline(canvas, shape, origin, cell, Color(UiStyle.COL_YELLOW, left), 4.0 + 10.0 * (1.0 - left))


## Roter pulsierender Rahmen um einen Gegenstand, der zum Verschrotten vorgemerkt ist (erstes X).
func _draw_scrap_mark(canvas: Control, shape: Array[Vector2i], origin: Vector2, cell: float, pulse: float) -> void:
	_live = true
	for entry: Vector2i in shape:
		canvas.draw_rect(Rect2(origin + Vector2(entry) * cell, Vector2(cell, cell)), Color(UiStyle.COL_RED, 0.18 + 0.14 * pulse))
	_draw_outline(canvas, shape, origin, cell, Color(UiStyle.COL_RED, 0.75 + 0.25 * pulse), 4.0)


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
		if focus:
			_live = true
		if pack.occupant(cell) != -1 or covered.has(cell):
			radius = STAR_RADIUS_CORNER
			var step: float = minf(STAR_STEP_CORNER, (CELL - 3.5 * STAR_CORNER_INSET) / float(maxi(count - 1, 1)))
			center = Vector2(rect.end.x - STAR_CORNER_INSET - float(index) * step, rect.position.y + STAR_CORNER_INSET)
			if not bool(mark["lit"]):
				# Leere Sterne auf einem Gegenstand bleiben klein, damit sein Name frei bleibt.
				radius = STAR_RADIUS_CORNER - 3.0
				center += Vector2(4.0, -4.0)
				grow = 1.0 + 0.5 * (grow - 1.0)
		else:
			var step: float = minf(STAR_STEP_CENTER, (CELL - 2.5 * STAR_RADIUS_CENTER) / float(maxi(count - 1, 1)))
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


## Die Hände in der oberen Leiste: ein Kasten je Hand mit der Waffe darin, eine Zweihand-Waffe
## füllt beide. Ohne Waffe im Rucksack steht dort die Dienstpistole als Notlösung.
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
		board_top.draw_rect(rect.grow(2.0), UiStyle.COL_INK)
		board_top.draw_rect(rect, fill)
		board_top.draw_rect(rect.grow(-1.5), edge, false, 3.0)
		board_top.draw_string(font, Vector2(rect.position.x + 9.0, rect.position.y + 16.0), str(slot["caption"]).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, width - 18.0, 10, UiStyle.COL_CYAN)
		var item_name: String = str(slot["name"])
		var font_size: int = UiStyle.fit_font_size(item_name, 15, width - 18.0, false, 9)
		board_top.draw_string(font, Vector2(rect.position.x + 9.0, rect.position.y + 35.0), item_name,
				HORIZONTAL_ALIGNMENT_LEFT, width - 18.0, font_size, name_color)


## Das Regal ohne seine Zeilen: Rahmen, Linie unter der Überschrift, der Text im leeren Regal und
## der Rollbalken (nur wenn es etwas zu rollen gibt). Die Zeilen zeichnet _draw_shelf_rows.
func _draw_shelf_frame() -> void:
	var holding: bool = _held_uid != -1
	board_top.draw_style_box(_shelf_hot_box if holding and SHELF_RECT.has_point(_pointer) else _shelf_box, SHELF_RECT)
	var inner: Rect2 = _shelf_inner()
	# Trennlinie unter der Überschrift.
	board_top.draw_rect(Rect2(SHELF_RECT.position.x + SHELF_PAD, inner.position.y - 7.0, inner.size.x, 2.0), Color(UiStyle.COL_CYAN, 0.55))
	if Game.backpack.storage_items().is_empty():
		board_top.draw_multiline_string(UiStyle.show_font(), Vector2(inner.position.x, inner.position.y + 26.0), SHELF_EMPTY_TEXT,
				HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 13, -1, Color(UiStyle.COL_WHITE, 0.45))
		return
	var bar: Dictionary = shelf_bar()
	if bar.is_empty():
		return
	var track: Rect2 = bar["track"]
	var thumb: Rect2 = bar["thumb"]
	board_top.draw_rect(track, Color(1.0, 1.0, 1.0, 0.1))
	board_top.draw_rect(thumb.grow(1.0), UiStyle.COL_INK)
	board_top.draw_rect(thumb, UiStyle.COL_YELLOW if _bar_drag else UiStyle.COL_CYAN)


## Die Zeilen des Regals (auf shelf_canvas, das abschneidet, was hinausgerollt ist): Die
## Gegenstände liegen untereinander in ihrer echten Form mit Bild, den Kästchen ihrer Rarität und
## ihrem Namen daneben oder darunter. Kaputte sind grau, schraffiert und tragen das Schild mit den
## Reparaturkosten. Unter jeder Zeile liegt ein Regalbrett.
func _draw_shelf_rows() -> void:
	(_icon_draws["shelf"] as Array).clear()
	if not visible:
		return
	var clip: Rect2 = _shelf_clip()
	# Ab hier gelten die Koordinaten von board.
	shelf_canvas.draw_set_transform(-clip.position)
	var holding: bool = _held_uid != -1
	var view: Rect2 = shelf_view()
	var font: Font = UiStyle.show_font()
	var layout: Array[Dictionary] = shelf_layout()
	for i: int in layout.size():
		var row: Dictionary = layout[i]
		if not bool(row["visible"]):
			continue
		var uid: int = int(row["uid"])
		var id: String = str(row["id"])
		var rot: int = int(row["rot"])
		var rect: Rect2 = row["rect"]
		var origin: Vector2 = row["origin"]
		var cell: float = float(row["cell"])
		var broken: bool = bool(row["broken"])
		var held: bool = uid == _held_uid
		var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
		var back: Rect2 = rect.grow_individual(4.0, 4.0, 2.0, 4.0)
		if uid == _hover_uid and not holding:
			shelf_canvas.draw_rect(back, Color(1.0, 1.0, 1.0, 0.1))
		# Regalbrett unter der Zeile.
		if i + 1 < layout.size():
			shelf_canvas.draw_rect(Rect2(view.position.x, rect.end.y + SHELF_GAP * 0.5 - 1.0, view.size.x, 2.0), Color(UiStyle.COL_CYAN, 0.22))
		_draw_shape(shelf_canvas, id, rot, origin, cell, held, int(row["level"]), broken)
		if not held:
			_draw_item_face(shelf_canvas, "shelf", uid, id, rot, origin, cell, int(row["level"]), broken, false, false)
			if broken:
				# Das Schild mit den Kosten steht in jeder Zeile an derselben Stelle: rechts oben.
				_draw_repair_badge(shelf_canvas, Vector2(rect.end.x, rect.position.y + 1.0), SHELF_REPAIR_BADGE, Game.repair_cost(uid))
		var name_rect: Rect2 = row["name_rect"]
		var layout_name: Dictionary = name_layout(id, name_rect.size.x, name_rect.size.y, SHELF_NAME_FONT_SIZE, SHELF_NAME_MIN_FONT_SIZE)
		var lines: PackedStringArray = layout_name["lines"]
		var font_size: int = int(layout_name["size"])
		var line_height: float = float(layout_name["line_height"])
		var top: float = name_rect.position.y + (name_rect.size.y - line_height * float(lines.size())) * 0.5
		# Der Name eines kaputten Gegenstands ist blasser: noch ein Zeichen neben Grau und Schild.
		var text_color: Color = Color(0.72, 0.72, 0.8) if broken else UiStyle.COL_WHITE
		text_color.a = 0.35 if held else 0.95
		for n: int in lines.size():
			var at: Vector2 = Vector2(name_rect.position.x, top + line_height * float(n) + font.get_ascent(font_size) * 0.92)
			shelf_canvas.draw_string_outline(font, at, lines[n], HORIZONTAL_ALIGNMENT_LEFT, name_rect.size.x, font_size, 4, Color(UiStyle.COL_INK, text_color.a))
			shelf_canvas.draw_string(font, at, lines[n], HORIZONTAL_ALIGNMENT_LEFT, name_rect.size.x, font_size, text_color)
		if uid == _hover_uid and not holding:
			_draw_outline(shelf_canvas, shape, origin, cell, UiStyle.COL_WHITE, 3.0)


## Was sich über den Zeilen des Regals mit der Zeit bewegt (shelf_top): Rahmen
## zum Verschrotten, Ziel beim Zusammenlegen, "geht nicht", der neue Gegenstand mit seinem Schild,
## das Aufleuchten und die dunklen Ränder oben und unten. Die Zeilen selbst zeichnet
## _draw_shelf_rows nur bei Änderungen.
func _draw_shelf_top() -> void:
	_shelf_live = false
	if not visible:
		return
	_live = false
	var clip: Rect2 = _shelf_clip()
	# Ab hier gelten die Koordinaten von board.
	shelf_top.draw_set_transform(-clip.position)
	var pulse: float = 0.5 + 0.5 * sin(_pulse * 6.0)
	var merge_uid: int = storage_merge_target()
	var blocked_uid: int = item_at(_pointer) if needs_repair_hint() and SHELF_RECT.has_point(_pointer) else -1
	var armed: int = scrap_armed_uid()
	if armed != -1 or merge_uid != -1 or blocked_uid != -1 or _new_uid != -1:
		for row: Dictionary in shelf_layout():
			if not bool(row["visible"]):
				continue
			var uid: int = int(row["uid"])
			if uid != armed and uid != merge_uid and uid != blocked_uid and uid != _new_uid:
				continue
			var rect: Rect2 = row["rect"]
			var origin: Vector2 = row["origin"]
			var cell: float = float(row["cell"])
			var shape: Array[Vector2i] = ItemDefs.cells(str(row["id"]), int(row["rot"]))
			var back: Rect2 = rect.grow_individual(4.0, 4.0, 2.0, 4.0)
			# Jede dieser Zeilen pulsiert.
			_live = true
			if uid == armed:
				_draw_scrap_mark(shelf_top, shape, origin, cell, pulse)
			if uid == merge_uid:
				# Der gehaltene Gegenstand würde mit diesem zusammengelegt: Das Ziel leuchtet wie im Raster.
				shelf_top.draw_rect(back, Color(UiStyle.COL_YELLOW, 0.14 + 0.1 * pulse))
				_draw_outline(shelf_top, shape, origin, cell, Color(UiStyle.COL_YELLOW, 0.6 + 0.4 * pulse), 5.0)
			elif uid == blocked_uid:
				# Gleicher Gegenstand, aber einer der beiden ist kaputt: geht nicht.
				shelf_top.draw_rect(back, Color(UiStyle.COL_RED, 0.14 + 0.08 * pulse))
				_draw_outline(shelf_top, shape, origin, cell, Color(UiStyle.COL_RED, 0.7 + 0.3 * pulse), 4.0)
			if uid == _new_uid and uid != _held_uid:
				shelf_top.draw_rect(back.grow(-1.0 - 1.0 * pulse), Color(UiStyle.COL_YELLOW, 0.55 + 0.45 * pulse), false, 3.0)
				_draw_badge(shelf_top, Vector2(rect.end.x - 15.0, rect.end.y - 9.0), "NEU", UiStyle.COL_PINK, UiStyle.COL_YELLOW, 11)
	_draw_flash(shelf_top, false)
	# Wo weiter oben oder unten noch etwas liegt, läuft der Rand des Regals dunkel aus.
	var fade: Color = Color(0.04, 0.02, 0.11)
	var limit: float = shelf_scroll_max()
	var scroll: float = shelf_scroll()
	for step: int in 4:
		var strip: float = 4.0
		var alpha: float = 0.8 - 0.2 * float(step)
		if scroll > 0.5:
			shelf_top.draw_rect(Rect2(clip.position.x, clip.position.y + strip * float(step), clip.size.x, strip), Color(fade, alpha))
		if scroll < limit - 0.5:
			shelf_top.draw_rect(Rect2(clip.position.x, clip.end.y - strip * float(step + 1), clip.size.x, strip), Color(fade, alpha))
	_shelf_live = _live


## Die Wertebalken der Karte: je Zeile Name, Balken in der Farbe der Rarität und die Zahl.
func _draw_card_bars() -> void:
	var font: Font = UiStyle.show_font()
	var width: float = card_bars_box.size.x
	var track_width: float = width - BAR_LABEL_WIDTH - BAR_VALUE_WIDTH
	for i: int in _card_bars.size():
		var bar: Dictionary = _card_bars[i]
		var top: float = float(i) * BAR_ROW
		var baseline: float = top + BAR_ROW * 0.5 + float(BAR_FONT_SIZE) * 0.36
		card_bars_box.draw_string(font, Vector2(0.0, baseline), str(bar["label"]), HORIZONTAL_ALIGNMENT_LEFT,
				BAR_LABEL_WIDTH - 4.0, BAR_FONT_SIZE, Color(UiStyle.COL_WHITE, 0.82))
		var track: Rect2 = Rect2(BAR_LABEL_WIDTH, top + (BAR_ROW - BAR_HEIGHT) * 0.5, track_width, BAR_HEIGHT)
		card_bars_box.draw_rect(track.grow(2.0), UiStyle.COL_INK)
		card_bars_box.draw_rect(track, Color(1.0, 1.0, 1.0, 0.13))
		var ratio: float = float(bar["ratio"])
		if ratio > 0.0:
			card_bars_box.draw_rect(Rect2(track.position, Vector2(track_width * maxf(ratio, BAR_MIN_RATIO), BAR_HEIGHT)), _card_accent)
		card_bars_box.draw_string(font, Vector2(width - BAR_VALUE_WIDTH + 6.0, baseline), str(bar["text"]), HORIZONTAL_ALIGNMENT_RIGHT,
				BAR_VALUE_WIDTH - 6.0, BAR_FONT_SIZE, UiStyle.COL_WHITE)


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
			_live = true
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
	(_icon_draws["overlay"] as Array).clear()
	_overlay_live = false
	if _held_uid == -1:
		return
	_live = false
	var entry: Dictionary = Game.backpack.item(_held_uid)
	if entry.is_empty():
		return
	var id: String = str(entry["id"])
	var level: int = int(entry["level"])
	var broken: bool = bool(entry.get("broken", false))
	var shape: Array[Vector2i] = ItemDefs.cells(id, _held_rot)
	var preview: Dictionary = drop_preview()
	# Über dem Raster rastet die Form in die Felder ein, sonst hängt sie am Zeiger.
	var origin: Vector2 = _held_origin()
	var size: float = _held_cell()
	var docked: bool = size < CELL
	if preview.is_empty():
		for part: Vector2i in shape:
			overlay.draw_rect(Rect2(origin + Vector2(part) * size + Vector2(7.0, 9.0) * size / CELL, Vector2(size, size)).grow(-2.0), Color(0.0, 0.0, 0.0, 0.35))
	_draw_shape(overlay, id, _held_rot, origin, size, false, level, broken)
	_draw_item_face(overlay, "overlay", _held_uid, id, _held_rot, origin, size, level, broken, _names_shown, true)
	var blocked: bool = needs_repair_hint()
	if preview.is_empty():
		if storage_merge_target() != -1:
			# Über einem gleichen Gegenstand im Regal: gelb wie beim Zusammenlegen im Raster.
			for part: Vector2i in shape:
				overlay.draw_rect(Rect2(origin + Vector2(part) * size, Vector2(size, size)), Color(UiStyle.COL_YELLOW, 0.32))
			_draw_outline(overlay, shape, origin, size, UiStyle.COL_YELLOW, 4.0)
			return
		if blocked:
			# Über einem gleichen Gegenstand im Regal, aber einer ist kaputt: geht nicht.
			for part: Vector2i in shape:
				overlay.draw_rect(Rect2(origin + Vector2(part) * size, Vector2(size, size)), Color(UiStyle.COL_RED, 0.32))
			_draw_outline(overlay, shape, origin, size, UiStyle.COL_RED, 4.0)
			_draw_repair_first(origin)
			return
		if docked:
			# Neben den drei Feldern: klein, ohne Sterne.
			_draw_outline(overlay, shape, origin, size, UiStyle.COL_WHITE, 2.0)
			return
		# Frei schwebend: Die Sterne hängen als Umriss an der Form.
		for star: Vector2i in ItemDefs.stars(id, _held_rot):
			_draw_star(overlay, origin + (Vector2(star) + Vector2(0.5, 0.5)) * size, STAR_RADIUS_CENTER, ItemDefs.color(id), false, false, 1.0)
		return
	var tint: Color = UiStyle.COL_RED
	if int(preview["kind"]) == PREVIEW_FIT:
		tint = UiStyle.COL_GREEN
	elif int(preview["kind"]) == PREVIEW_MERGE:
		tint = UiStyle.COL_YELLOW
	for part: Vector2i in shape:
		overlay.draw_rect(Rect2(origin + Vector2(part) * size, Vector2(size, size)), Color(tint, 0.32))
	_draw_outline(overlay, shape, origin, size, tint, 4.0)
	# Sterne des gehaltenen Gegenstands an der Stelle der Vorschau und Sterne, die er verdeckt.
	_draw_star_marks(overlay, star_marks(), true)
	_overlay_live = _live
	if blocked:
		_draw_repair_first(origin)


## Schild "ERST REPARIEREN" mitten auf dem gehaltenen Gegenstand.
func _draw_repair_first(origin: Vector2) -> void:
	var entry: Dictionary = Game.backpack.item(_held_uid)
	if entry.is_empty():
		return
	var extent: Vector2 = Vector2(ItemDefs.size(str(entry["id"]), _held_rot)) * _held_cell()
	var font_size: int = 13 if extent.x > CELL + 1.0 else 9
	var center: Vector2 = origin + extent * 0.5
	# Das Schild bleibt in der Bühne, auch wenn die Form am Rand hängt.
	center.x = clampf(center.x, 70.0, STAGE_SIZE.x - 70.0)
	_draw_badge(overlay, center, BROKEN_BADGE_TEXT, UiStyle.COL_RED, UiStyle.COL_WHITE, font_size)


## Farbe der Fläche eines Gegenstands: die Farbe seiner Rarität (Rucksack-Teile haben keine
## Rarität und behalten ihre eigene Farbe). Ein kaputter Gegenstand ist grau mit einem Hauch
## dieser Farbe.
func _surface_color(id: String, level: int, broken: bool) -> Color:
	var base: Color = ItemDefs.rarity_color(level) if ItemDefs.has_rarity(id) else ItemDefs.color(id)
	if broken:
		return BROKEN_FILL.lerp(base, BROKEN_RARITY_MIX)
	return base


## Breite des dunklen Rands um eine Form mit Feldern der Größe cell (Fuge und Rand zusammen).
func _shape_inset(cell: float) -> float:
	return maxf(1.0, cell * 0.03) + maxf(2.0, cell * 0.05)


## Zeichnet die Form eines Gegenstands in der Farbe seiner Rarität: dunkler Rand außen herum,
## Felder ohne Fuge verbunden. ghost: nur ein blasser Schatten (alter Platz des gehaltenen
## Gegenstands). broken: grau statt bunt.
func _draw_shape(canvas: Control, id: String, rot: int, origin: Vector2, cell: float, ghost: bool, level: int, broken: bool) -> void:
	var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
	var fill: Color = _surface_color(id, level, broken)
	var gap: float = maxf(1.0, cell * 0.03)
	var inset: float = _shape_inset(cell)
	if ghost:
		for entry: Vector2i in shape:
			canvas.draw_rect(Rect2(origin + Vector2(entry) * cell, Vector2(cell, cell)).grow(-inset), Color(fill, 0.22))
		_draw_outline(canvas, shape, origin, cell, Color(fill, 0.6), 2.0)
		return
	for entry: Vector2i in shape:
		canvas.draw_rect(_shape_rect(shape, entry, origin, cell, gap), UiStyle.COL_INK)
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


## Alles, was auf der Form eines Gegenstands liegt (Raster, Regal und Hand): sein Bild aus
## ItemIcons mitten auf dem größten Quadrat der Form, bei einem kaputten Gegenstand Schleier,
## Schraffur und Riss, die Kästchen der Rarität am unteren Rand, bei Waffen links oben das Schild
## mit ihren Händen ("1H" oder "2H"). names: dazu der Name als kleine Zeile ganz unten (das Bild
## ist dann kleiner und sitzt höher). cost_badge: Ein kaputter Gegenstand trägt das Schild mit
## den Reparaturkosten rechts oben auf seiner Form (im Regal steht es stattdessen in der Zeile).
## where: Zeichenfläche für drawn_icons ("board", "shelf" oder "overlay").
func _draw_item_face(canvas: Control, where: String, uid: int, id: String, rot: int, origin: Vector2, cell: float,
		level: int, broken: bool, names: bool, cost_badge: bool) -> void:
	var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
	var icon: Rect2 = _icon_rect(id, rot, origin, cell, names)
	_draw_icon(canvas, where, uid, id, icon, BROKEN_TINT if broken else Color.WHITE)
	if broken:
		_draw_broken_marks(canvas, shape, origin, cell, icon)
	var foot: Rect2 = _foot_box(id, rot, origin, cell)
	var small: bool = cell < CELL - 0.5
	var factor: float = SHELF_PIP_SCALE if small else 1.0
	var pips_y: float = foot.end.y - cell * PIP_BOTTOM
	if names:
		var area: Rect2 = name_area(id, rot, origin, cell)
		var layout: Dictionary = name_layout(id, area.size.x, area.size.y)
		var lines: PackedStringArray = layout["lines"]
		var font_size: int = int(layout["size"])
		var line_height: float = float(layout["line_height"])
		var font: Font = UiStyle.show_font()
		var inset: float = _shape_inset(cell)
		var band_height: float = minf(line_height * float(lines.size()) + 3.0, NAME_BAND_MAX)
		var band: Rect2 = Rect2(foot.position.x + inset, foot.end.y - inset - band_height, foot.size.x - 2.0 * inset, band_height)
		canvas.draw_rect(band, NAME_BAND_COLOR)
		for n: int in lines.size():
			canvas.draw_string(font, Vector2(area.position.x, band.position.y + 1.0 + line_height * float(n) + font.get_ascent(font_size) * 0.92),
					lines[n], HORIZONTAL_ALIGNMENT_CENTER, area.size.x, font_size, UiStyle.COL_WHITE)
		pips_y = band.position.y - PIP_SIZE.y * factor * 0.5 - 4.0
	if ItemDefs.has_rarity(id):
		_draw_pips(canvas, Vector2(foot.get_center().x, pips_y), level, 1.0, factor)
	# Trägt ein kaputter Gegenstand mit schmaler oberer Zeile dort das Schild mit den Kosten,
	# entfällt das Schild der Hände.
	var cost_on_shape: bool = broken and cost_badge
	if ItemDefs.is_weapon(id) and not (cost_on_shape and _top_run(shape) < 2):
		var first: Vector2 = origin + Vector2(shape[0]) * cell
		if small:
			_draw_badge(canvas, first + SHELF_BADGE_OFFSET, _hands_badge(id), UiStyle.COL_INK, UiStyle.COL_WHITE, SHELF_BADGE_FONT_SIZE)
		else:
			_draw_badge(canvas, first + BADGE_OFFSET, _hands_badge(id), UiStyle.COL_INK, UiStyle.COL_WHITE, BADGE_FONT_SIZE)
	if cost_on_shape:
		# Rechte obere Ecke der obersten Zeile der Form.
		var corner_cell: Vector2i = shape[0]
		for entry: Vector2i in shape:
			if entry.y < corner_cell.y or (entry.y == corner_cell.y and entry.x > corner_cell.x):
				corner_cell = entry
		var corner: Vector2 = origin + Vector2(float(corner_cell.x + 1), float(corner_cell.y)) * cell
		_draw_repair_badge(canvas, corner + Vector2(-1.0, 1.0), clampf(cell * 0.38, 16.0, 24.0), Game.repair_cost(uid))


## Zeichnet das Bild eines Gegenstands (ItemIcons.draw) und merkt den Aufruf für drawn_icons.
func _draw_icon(canvas: Control, where: String, uid: int, id: String, rect: Rect2, tint: Color) -> void:
	(_icon_draws[where] as Array).append({"uid": uid, "id": id, "rect": rect, "tint": tint, "where": where})
	ItemIcons.draw(canvas, id, rect, tint)


## Fläche des Bildes für eine Form mit Feldern der Größe cell bei origin: das größte Quadrat der
## Form (icon_block) ohne Rand, etwas nach oben gerückt. names: kleiner und höher, damit unten
## Platz für die Namenszeile bleibt.
func _icon_rect(id: String, rot: int, origin: Vector2, cell: float, names: bool) -> Rect2:
	var block: Rect2 = icon_block(id, rot)
	var edge: float = block.size.x * cell
	var inset: float = edge * (ICON_INSET_NAMED if names else ICON_INSET)
	var lift: float = cell * (ICON_LIFT_NAMED if names else ICON_LIFT)
	return Rect2(origin + block.position * cell + Vector2(inset, inset - lift), Vector2(edge - 2.0 * inset, edge - 2.0 * inset))


## Zeichen für "kaputt" über einem Gegenstand: grauer Schleier und schräge Schraffur über die
## ganze Form (die Striche laufen über die Felder durch), dazu ein gezackter Riss durch das Bild.
func _draw_broken_marks(canvas: Control, shape: Array[Vector2i], origin: Vector2, cell: float, icon: Rect2) -> void:
	var inset: float = _shape_inset(cell)
	var step: float = maxf(cell * BROKEN_HATCH_STEP, 6.0)
	var width: float = maxf(1.5, cell * 0.035)
	for entry: Vector2i in shape:
		var inner: Rect2 = _shape_rect(shape, entry, origin, cell, inset)
		canvas.draw_rect(inner, BROKEN_VEIL)
		# Striche auf den Geraden x + y = k * step (gemessen ab origin), auf das Feld begrenzt.
		var low: Vector2 = inner.position - origin
		var high: Vector2 = inner.end - origin
		var k: float = ceilf((low.x + low.y) / step + 0.001)
		while k * step < high.x + high.y - 0.5:
			var sum: float = k * step
			var from_x: float = clampf(sum - high.y, low.x, high.x)
			var to_x: float = clampf(sum - low.y, low.x, high.x)
			if to_x - from_x > 1.0:
				canvas.draw_line(origin + Vector2(from_x, sum - from_x), origin + Vector2(to_x, sum - to_x), BROKEN_HATCH, width)
			k += 1.0
	# Riss von oben nach unten durch die rechte Hälfte des Bildes (das Motiv in der Mitte bleibt zu
	# sehen), bei großen Bildern mit einem kurzen Ast.
	var crack: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in [Vector2(0.8, 0.02), Vector2(0.66, 0.3), Vector2(0.82, 0.5), Vector2(0.62, 0.74), Vector2(0.72, 0.98)]:
		crack.append(icon.position + point * icon.size)
	var crack_width: float = maxf(1.2, icon.size.x * 0.035)
	canvas.draw_polyline(crack, UiStyle.COL_INK, crack_width + 2.0)
	canvas.draw_polyline(crack, Color(0.94, 0.94, 1.0), crack_width)
	if icon.size.x >= 40.0:
		var branch_from: Vector2 = icon.position + Vector2(0.66, 0.3) * icon.size
		var branch_to: Vector2 = icon.position + Vector2(0.44, 0.42) * icon.size
		canvas.draw_line(branch_from, branch_to, UiStyle.COL_INK, crack_width + 1.5)
		canvas.draw_line(branch_from, branch_to, Color(0.94, 0.94, 1.0), crack_width * 0.8)


## Kleines rotes Schild für einen kaputten Gegenstand: Schraubenschlüssel und die Kosten der
## Reparatur in Material. corner ist seine rechte obere Ecke, height seine Höhe.
func _draw_repair_badge(canvas: Control, corner: Vector2, height: float, cost: int) -> void:
	var font: Font = UiStyle.show_font()
	var font_size: int = int(height) - 4
	var text: String = str(cost)
	var width: float = height + _text_width(font, text, font_size) + 6.0
	var rect: Rect2 = Rect2(corner.x - width, corner.y, width, height)
	canvas.draw_rect(rect.grow(2.0), UiStyle.COL_INK)
	canvas.draw_rect(rect, BROKEN_BADGE_COLOR)
	UiStyle.draw_wrench(canvas, rect.position + Vector2(height * 0.5, height * 0.5), height - 3.0, UiStyle.COL_WHITE, BROKEN_BADGE_COLOR)
	canvas.draw_string(font, Vector2(rect.position.x + height - 1.0, rect.position.y + height * 0.5 + float(font_size) * 0.36), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, UiStyle.COL_WHITE)


## Wie viele Felder der obersten Zeile der Form nebeneinander liegen.
func _top_run(shape: Array[Vector2i]) -> int:
	var top: int = 9999
	for entry: Vector2i in shape:
		top = mini(top, entry.y)
	var count: int = 0
	for entry: Vector2i in shape:
		if entry.y == top:
			count += 1
	return count


## Text des Schilds einer Waffe: "1H" (eine Hand) oder "2H" (zwei Hände).
func _hands_badge(id: String) -> String:
	return "%dH" % ItemDefs.hands(id)


## Unterste Zeile einer Form (ihr längstes Stück aus Feldern nebeneinander) als Rechteck: Dort
## sitzen die Kästchen der Rarität und die Namenszeile.
func _foot_box(id: String, rot: int, origin: Vector2, cell: float) -> Rect2:
	var shape: Array[Vector2i] = ItemDefs.cells(id, rot)
	var extent: Vector2i = ItemDefs.size(id, rot)
	var row: int = extent.y - 1
	var best_left: int = 0
	var best_run: int = 0
	var x: int = 0
	while x < extent.x:
		if not shape.has(Vector2i(x, row)):
			x += 1
			continue
		var run: int = 1
		while shape.has(Vector2i(x + run, row)):
			run += 1
		if run > best_run:
			best_run = run
			best_left = x
		x += run
	if best_run <= 0:
		return Rect2(origin, Vector2(cell, cell))
	return Rect2(origin + Vector2(float(best_left), float(row)) * cell, Vector2(float(best_run) * cell, cell))


## Fünf Kästchen für die Rarität: so viele wie die Rarität in ihrer Farbe mit dunklem Rand (damit
## sie sich von jeder Farbe des Gegenstands abheben), der Rest dunkel. factor verkleinert sie
## für die kleineren Felder im Regal (1 = Größe im Rucksack).
func _draw_pips(canvas: Control, center: Vector2, level: int, alpha: float, factor: float) -> void:
	var count: int = Balance.UPGRADE_MAX_LEVEL
	var pip: Vector2 = PIP_SIZE * factor
	var gap: float = maxf(PIP_GAP * factor, 1.0)
	var edge: float = 2.0 if factor >= 0.75 else 1.0
	var total: float = pip.x * float(count) + gap * float(count - 1)
	for i: int in count:
		var rect: Rect2 = Rect2(center.x - total * 0.5 + float(i) * (pip.x + gap), center.y - pip.y * 0.5, pip.x, pip.y)
		var color: Color = Color(0.0, 0.0, 0.0, 0.55)
		if i < level:
			color = ItemDefs.rarity_color(level)
		canvas.draw_rect(rect.grow(edge), Color(UiStyle.COL_INK, alpha))
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
