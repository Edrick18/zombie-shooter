extends RefCounted
## Alle Spielzahlen an einem Ort (Abschnitt 8 der Architektur).
## Besitzer: Fundament. Kein anderes Skript legt Spielzahlen fest im Code ab.
## Ausnahmen laut Vertrag: die Waffentabelle (weapon_defs.gd) und die Stufenwerte der Upgrades
## (upgrade_defs.gd). Einbinden mit: const Balance := preload("res://scripts/core/balance.gd")

# --- Kollisionslagen (Bitwerte) und Masken, siehe Abschnitt 4 ---
const LAYER_WORLD: int = 1
const LAYER_PLAYER: int = 2
const LAYER_ZOMBIES: int = 4
const LAYER_PICKUPS: int = 8
const LAYER_INTERACTABLES: int = 16
## Lage 6: Sperre, mit der nur der Spieler kollidiert (Zombie-Gänge, Publikum). Zombies und
## Schüsse gehen hindurch.
const LAYER_PLAYER_BLOCK: int = 32
## Spieler: Lage 2, Maske Welt + Zombies + Spieler-Sperre.
const MASK_PLAYER: int = 37
## Zombie: Lage 3, Maske Welt + Spieler + Zombies.
const MASK_ZOMBIE: int = 7
## Schuss-Strahl: Welt + Zombies.
const MASK_SHOT: int = 5
## Blick-Strahl für Interaktion: Welt + Interaktionsobjekte.
const MASK_INTERACT: int = 17
## Kiste (Area3D): Lage 4, Maske Spieler.
const MASK_CHEST: int = 2
## Sichtlinie (Drohne, Explosion): nur Welt.
const MASK_LINE_OF_SIGHT: int = 1

# --- Spieler ---
const PLAYER_MAX_HP: float = 100.0
## Heilung am Wellenende. Sonst gibt es keine automatische Heilung.
const WAVE_END_HEAL: float = 25.0
const PLAYER_WALK_SPEED: float = 5.0
const PLAYER_SPRINT_SPEED: float = 7.0
const PLAYER_JUMP_VELOCITY: float = 4.5
const GRAVITY: float = 12.0
const PLAYER_EYE_HEIGHT: float = 1.6
const PLAYER_FOV: float = 80.0
## Sekunden Unverwundbarkeit gegen weitere Zombie-Schläge nach einem Treffer.
const PLAYER_HIT_INVULNERABILITY: float = 0.5
const INTERACT_RANGE: float = 2.5
## Vom Vertrag offen gelassen: Körpermaße und Maus-Empfindlichkeit (Radiant je Pixel).
const PLAYER_HEIGHT: float = 1.8
const PLAYER_RADIUS: float = 0.35
const MOUSE_SENSITIVITY: float = 0.0025
## Bodenbeschleunigung des Spielers in m/s² (Anlaufen und Abbremsen).
const PLAYER_ACCELERATION: float = 40.0
## Anteil der Bodenbeschleunigung in der Luft.
const PLAYER_AIR_CONTROL: float = 0.35
## So lange merkt sich der Spieler einen zu früh gedrückten Sprung (Sekunden).
const PLAYER_JUMP_BUFFER_TIME: float = 0.12
## So lange darf nach dem Verlassen einer Kante noch gesprungen werden (Sekunden).
const PLAYER_COYOTE_TIME: float = 0.1
## Höchste Stufe, die der Spieler ohne Sprung hochläuft (Showtreppe), in Metern.
## Die Bühnenkante (STAGE_HEIGHT) ist höher: Dort braucht es Sprung, Treppe oder Rampe.
const PLAYER_STEP_HEIGHT: float = 0.3
## Kamera-Rückstoß je Schuss in Grad nach oben (je Waffe). Klingt von selbst wieder ab.
## Der Schuss folgt der Kamera, der Rückstoß verzieht also wirklich.
const CAMERA_RECOIL_KICK_DEG: Dictionary = {
	"pistol": 0.6,
	"shotgun": 2.2,
	"smg": 0.32,
	"revolver": 1.6,
	"sawed_off": 2.6,
	"rifle": 0.4,
	"sniper": 3.0,
	"minigun": 0.18,
	"rocket_launcher": 3.4,
	"burst_pistol": 0.5,
	"nail_gun": 0.22,
	"machine_pistol": 0.3,
	"crossbow": 1.8,
	"grenade_launcher": 2.4,
	"flamethrower": 0.05,
	"beam": 0.04,
	"tesla": 1.2,
	"lmg": 0.45,
	"auto_shotgun": 1.6,
}
## Abklingen des Kamera-Rückstoßes (1/s) und höchster aufgestauter Rückstoß in Grad.
const CAMERA_RECOIL_RECOVERY: float = 10.0
const CAMERA_RECOIL_MAX_DEG: float = 5.0

# --- Punkte ---
const POINTS_START: int = 0
const POINTS_BULLET_HIT: int = 10
const POINTS_KILL: int = 60
const POINTS_HEADSHOT_KILL_BONUS: int = 30
const POINTS_ELITE_KILL: int = 150
const DOOR_COST: int = 750
## Preise der vier kaufbaren Räume in der Reihenfolge ihrer Zonen 2 bis 5: Backstage, Kantine,
## Garderobe, Regieraum. Der erste Eintrag ist DOOR_COST.
const DOOR_COSTS: Array[int] = [DOOR_COST, 1250, 2000, 3000]

# --- Waffen allgemein (Tabelle in weapon_defs.gd) ---
const WEAPON_RANGE: float = 60.0
const HEADSHOT_MULTIPLIER: float = 2.0
## Kopftreffer: Trefferpunkt höher als dieser Anteil der Zombiehöhe über den Füßen.
const HEADSHOT_HEIGHT_RATIO: float = 0.78
## So lange merkt sich eine halbautomatische Waffe einen zu früh gedrückten Abzug (Sekunden).
const FIRE_BUFFER_TIME: float = 0.12
## Höchstens so viele Schüsse gibt eine Waffe in einem einzigen Bild ab. Ist ein Bild länger als
## die Schussfolge (MP unter 12 Bildern je Sekunde), holt Dauerfeuer damit die Schussrate auf.
## Ein langer Ruckler wird trotzdem kein Feuerstoß.
const FIRE_MAX_SHOTS_PER_FRAME: int = 4

# --- Zombies ---
## Grundwerte je Typ. "speed" des Schlurfers ist der Startwert, siehe WALKER_SPEED_*.
const ZOMBIE_TYPES: Dictionary = {
	"walker": {
		"name": "Schlurfer", "hp": 60.0, "speed": 1.6, "damage": 20.0, "from_wave": 1,
		"scale": 1.0, "color": Color(0.45, 0.56, 0.4), "glow": false,
	},
	"sprinter": {
		"name": "Sprinter", "hp": 35.0, "speed": 5.0, "damage": 15.0, "from_wave": 3,
		"scale": 1.0, "color": Color(0.86, 0.14, 0.12), "glow": false,
	},
	"elite": {
		"name": "Elite", "hp": 400.0, "speed": 2.6, "damage": 35.0, "from_wave": 2,
		"scale": 1.3, "color": Color(1.0, 0.8, 0.15), "glow": true,
	},
}
## Körpermaße bei Größe 1,0 (Elite: mal "scale"). Ursprung des Zombies sind die Füße.
const ZOMBIE_HEIGHT: float = 1.8
const ZOMBIE_RADIUS: float = 0.35
## Lebens-Faktor: 1 + 0.12 * (Welle - 1) bis Welle 10, danach je weiterer Welle mal 1,1.
const HP_FACTOR_PER_WAVE: float = 0.12
const HP_FACTOR_LINEAR_UNTIL_WAVE: int = 10
const HP_FACTOR_LATE_MULTIPLIER: float = 1.1
const WALKER_SPEED_START: float = 1.6
const WALKER_SPEED_PER_WAVE: float = 0.1
const WALKER_SPEED_MAX: float = 3.0
const ZOMBIE_ATTACK_RANGE: float = 1.4
const ZOMBIE_ATTACK_WINDUP: float = 0.4
const ZOMBIE_ATTACK_COOLDOWN: float = 1.0
## Sekunden zwischen zwei Pfadberechnungen.
const ZOMBIE_REPATH_INTERVAL: float = 0.25
## Vom Vertrag offen gelassen: Dauer der Todesanimation, Abstoßung, Abklingen des Rückstoßes.
const ZOMBIE_DEATH_TIME: float = 0.35
const ZOMBIE_SEPARATION_RADIUS: float = 0.9
const ZOMBIE_SEPARATION_STRENGTH: float = 1.5
const ZOMBIE_KNOCKBACK_DAMPING: float = 6.0
## Angriff im Einzelnen: Während des Ausholens rückt der Zombie mit diesem Anteil seines Tempos
## nach, der Schlag reicht so viel weiter als die Auslöse-Reichweite, und stehen bleibt er bei
## diesem Anteil der Angriffsreichweite.
const ZOMBIE_ATTACK_WINDUP_SPEED_FACTOR: float = 0.3
const ZOMBIE_ATTACK_HIT_RANGE_BONUS: float = 0.3
const ZOMBIE_ATTACK_STOP_RANGE_FACTOR: float = 0.8
## Ab diesem Rückstoß-Tempo (m/s) hat der Zombie keine Kontrolle mehr über seine Beine.
const ZOMBIE_STAGGER_KNOCKBACK_SPEED: float = 3.0
## Ein Stoß ohne Anteil nach oben hebt den Zombie trotzdem kurz ab (Anteil des Stoßes, Obergrenze in m/s).
const ZOMBIE_KNOCKBACK_LIFT_SHARE: float = 0.2
const ZOMBIE_KNOCKBACK_LIFT_MAX: float = 2.2
## Höhen (m), in denen ein Zombie prüft, ob ein Hindernis überspringbar ist (Bühnenkante). Die
## letzte ist die Obergrenze. Danach wartet er ZOMBIE_HOP_COOLDOWN Sekunden bis zum nächsten Sprung.
const ZOMBIE_HOP_PROBE_HEIGHTS: Array[float] = [0.2, 0.35, 0.5, 0.65]
const ZOMBIE_HOP_COOLDOWN: float = 0.4
## Sicherung gegen festhängende Wellen (WaveManager): So lange darf ein Zombie auf der Stelle
## stehen, ohne beim Spieler zu sein, bevor er an einen anderen Spawnpunkt gesetzt wird. Nach
## so vielen Versuchen verschwindet er ohne Belohnung.
const ZOMBIE_STUCK_SECONDS: float = 12.0
const ZOMBIE_STUCK_MAX_RESCUES: int = 3
## Bewegt sich ein Zombie mindestens so weit (m), gilt er als unterwegs. Näher am Spieler als
## ZOMBIE_STUCK_ENGAGED_DISTANCE (m, waagerecht) gilt er als im Kampf, auch wenn er steht.
const ZOMBIE_STUCK_MOVE_DISTANCE: float = 1.0
const ZOMBIE_STUCK_ENGAGED_DISTANCE: float = 4.0
## Unterhalb dieser Höhe (m) ist ein Zombie aus der Welt gefallen. Der Boden liegt bei 0.
const ZOMBIE_OUT_OF_WORLD_Y: float = -15.0
## Ersatz-Abstand zum Spieler (m), wenn es beim Umsetzen keinen Spawnpunkt gibt.
const ZOMBIE_RESCUE_FALLBACK_DISTANCE: float = 8.0

# --- Wellen ---
## Zombies je Welle ohne Elite: WAVE_BASE_COUNT + WAVE_COUNT_PER_WAVE * Welle.
const WAVE_BASE_COUNT: int = 6
const WAVE_COUNT_PER_WAVE: int = 4
## Sprinter-Anteil in Prozent: [ab Welle, Prozent], aufsteigend. Der letzte passende Eintrag gilt.
const SPRINTER_SHARE_STEPS: Array = [[3, 20], [6, 35]]
## Elite-Anzahl (zusätzlich): [ab Welle, Anzahl], aufsteigend. Der letzte passende Eintrag gilt.
const ELITE_COUNT_STEPS: Array = [[2, 1], [6, 2], [10, 3]]
## Zombies gleichzeitig: MAX_ZOMBIES_ALIVE bis Welle 10, danach je Welle
## MAX_ZOMBIES_ALIVE_PER_LATE_WAVE mehr, höchstens MAX_ZOMBIES_ALIVE_CAP.
const MAX_ZOMBIES_ALIVE: int = 24
const MAX_ZOMBIES_ALIVE_PER_LATE_WAVE: int = 2
const MAX_ZOMBIES_ALIVE_CAP: int = 48
## Spawn-Abstand: max(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_BASE - SPAWN_INTERVAL_PER_WAVE * Welle).
const SPAWN_INTERVAL_BASE: float = 1.5
const SPAWN_INTERVAL_PER_WAVE: float = 0.1
const SPAWN_INTERVAL_MIN: float = 0.4
## Ab Welle 12 wird der Abstand je Welle um SPAWN_INTERVAL_LATE_PER_WAVE kürzer, bis zum Boden
## SPAWN_INTERVAL_FLOOR. Vorher blieb der Nachschub ab Welle 11 gleich.
const SPAWN_INTERVAL_LATE_FROM_WAVE: int = 11
const SPAWN_INTERVAL_LATE_PER_WAVE: float = 0.02
const SPAWN_INTERVAL_FLOOR: float = 0.15
## Schaden der Zombies: ab Welle ZOMBIE_DAMAGE_FROM_WAVE je Welle ZOMBIE_DAMAGE_PER_WAVE mehr.
const ZOMBIE_DAMAGE_FROM_WAVE: int = 5
const ZOMBIE_DAMAGE_PER_WAVE: float = 0.05
## Sprinter werden ab Welle 10 je Welle schneller, bleiben aber langsamer als der sprintende Spieler.
const SPRINTER_SPEED_PER_LATE_WAVE: float = 0.05
const SPRINTER_SPEED_MAX: float = 6.4
## Vom Vertrag offen gelassen: Abstand vom Ursprung, in dem Zombies erscheinen, wenn das Level
## keinen aktiven Spawnpunkt hat (nur für Tests ohne Level von Bedeutung).
const SPAWN_FALLBACK_DISTANCE: float = 12.0
## Spawnpunkte, die dem Spieler näher sind (m), werden gemieden, solange es andere gibt.
const SPAWN_MIN_PLAYER_DISTANCE: float = 7.0
## Gewicht eines Spawnpunkts = 1 / (SPAWN_WEIGHT_OFFSET + Entfernung zum Spieler).
const SPAWN_WEIGHT_OFFSET: float = 6.0
## Zufälliger Versatz um den Spawnpunkt (m), damit zwei Zombies nicht exakt aufeinander stehen.
const SPAWN_JITTER: float = 0.3
const INTERMISSION_SECONDS: float = 12.0
const FIRST_WAVE_DELAY: float = 4.0
## Effekt-Faktor für feste Schadenswerte (Druckwelle, Gift, Discokugel, Störsender, nicht mehr
## für Kameras: Die haben seit Abschnitt 22 feste Werte je Rarität): bis
## Welle 10 EFFECT_FACTOR_SHARE mal Lebens-Faktor (mindestens EFFECT_FACTOR_MIN). Danach wächst er
## je Welle nur noch mit EFFECT_FACTOR_LATE_MULTIPLIER, also langsamer als das Leben der Zombies
## (HP_FACTOR_LATE_MULTIPLIER). Früher hielt er für immer Schritt: Mit genug Drohnen war das Spiel
## dann nicht mehr zu verlieren.
const EFFECT_FACTOR_SHARE: float = 0.75
const EFFECT_FACTOR_MIN: float = 1.0
const EFFECT_FACTOR_LATE_MULTIPLIER: float = 1.04
## Begleiter (Discokugeln, Kameras seit Abschnitt 22 nicht mehr): Bei n gleichen Begleitern macht jeder nur
## 1 / n hoch COMPANION_STACK_EXPONENT seines Schadens. Mit 0,5 sind vier Drohnen zusammen so
## stark wie zwei einzelne, zehn so stark wie gut drei.
const COMPANION_STACK_EXPONENT: float = 0.5

# --- Kisten ---
const RARITY_BRONZE: int = 0
const RARITY_SILVER: int = 1
const RARITY_GOLD: int = 2
const RARITY_NAMES: Array[String] = ["Bronze", "Silber", "Gold"]
const RARITY_COLORS: Array[Color] = [Color(0.8, 0.5, 0.2), Color(0.78, 0.8, 0.86), Color(1.0, 0.82, 0.2)]
## Kistenchance normaler Zombies (Elite: immer). Glück addiert Prozentpunkte.
const CHEST_DROP_CHANCE_NORMAL: float = 0.03
## In dieser Welle lässt der letzte Zombie sicher eine Kiste fallen (sie hat keine Elite).
const GUARANTEED_CHEST_WAVE: int = 1
## Seltenheit in Prozent [Bronze, Silber, Gold].
const CHEST_RARITY_NORMAL: Array[float] = [70.0, 25.0, 5.0]
const CHEST_RARITY_ELITE: Array[float] = [50.0, 40.0, 10.0]
## Glück verschiebt je Stufe so viele Prozentpunkte von Bronze zu Silber bzw. zu Gold.
const LUCK_SHIFT_TO_SILVER: float = 4.0
const LUCK_SHIFT_TO_GOLD: float = 2.0
## Stufen, die das gewählte Upgrade bekommt, nach Seltenheit [Bronze, Silber, Gold].
const CHEST_LEVELS_BY_RARITY: Array[int] = [1, 2, 3]
const CHEST_OFFER_COUNT: int = 3
const CONSOLATION_POINTS: int = 500
const CONSOLATION_HEAL: int = 50
## Vom Vertrag offen gelassen: Radius, in dem der Spieler eine Kiste aufsammelt.
const CHEST_PICKUP_RADIUS: float = 0.9
## Sekunden, die eine liegen gebliebene Kiste nach einer Kistenwahl wartet, bevor sie sich von
## selbst öffnet (zwei Kisten nebeneinander gehen nicht ohne Atempause auf).
const CHEST_REOPEN_GRACE: float = 0.4
## Liegt der Ort einer fallenden Kiste weiter als das neben dem Navigationsnetz (m), rückt sie
## auf das Netz. CHEST_SPACING ist der Mindestabstand zweier Kisten, die von Zombies fallen.
const CHEST_NAV_SNAP_TOLERANCE: float = 0.6
const CHEST_SPACING: float = 1.3

# --- Upgrades allgemein (Stufenwerte in upgrade_defs.gd) ---
const UPGRADE_MAX_SLOTS: int = 6

# --- Waffen im Rucksack (Abschnitt 18) ---
## Hände des Spielers: Die eingeräumten Waffen dürfen zusammen höchstens so viele brauchen.
const PLAYER_HANDS: int = 2
## Faktor auf den Waffenschaden je Rarität (Gewöhnlich bis Legendär).
const WEAPON_RARITY_DAMAGE: Array[float] = [1.0, 1.25, 1.5, 1.8, 2.2]

# --- Neue Gegenstände (Abschnitt 19) ---
## Kantinenessen: so lange wirkt das Gift nach dem letzten Treffer.
const POISON_DURATION: float = 4.0
## Glücksrad: Faktor eines kritischen Treffers.
const CRIT_MULTIPLIER: float = 2.0
## Teleprompter: Faktor auf die Streuung der Waffe.
const SCOPE_SPREAD_FACTOR: float = 0.5
## Sicherheitsglas: Sekunden ohne Schaden, bis das Schild lädt, und Punkte je Sekunde beim Laden.
const SHIELD_RECHARGE_DELAY: float = 5.0
const SHIELD_RECHARGE_RATE: float = 20.0
## Störsender: Abstand der Elektroschläge in Sekunden.
const JAMMER_INTERVAL: float = 4.0
## Notausgang: Tempo und Dauer des Ausweichsprungs.
const DASH_SPEED: float = 16.0
const DASH_TIME: float = 0.18
## Discokugel: Abstand zum Spieler, Umlauf in Radiant je Sekunde, Abstand zweier Treffer am
## selben Zombie in Sekunden und Trefferradius.
const DISCO_ORBIT_RADIUS: float = 2.2
const DISCO_ORBIT_SPEED: float = 2.6
const DISCO_HIT_INTERVAL: float = 0.5
const DISCO_HIT_RADIUS: float = 0.9

# --- Ausbau 3 (Abschnitt 22.3): neue Gegenstände ---
## Verlangsamung (Trockeneis, Zeitlupen-Kamera): Elite spürt nur diesen Anteil, und langsamer als
## um SLOW_MAX wird kein Zombie.
const SLOW_ELITE_FACTOR: float = 0.5
const SLOW_MAX: float = 0.9
## Trockeneis: so lange bleibt ein getroffener Zombie langsamer (Sekunden).
const FROST_DURATION: float = 2.0
## Schlusspointe: Radius der Explosion der letzten Kugel.
const PUNCHLINE_RADIUS: float = 3.0
## Querschläger: Umkreis für das zweite Ziel und Anteil am Schaden des Treffers.
const RICOCHET_RADIUS: float = 6.0
const RICOCHET_DAMAGE_FACTOR: float = 0.6
## Kaktus-Requisite: Umkreis um den Spieler.
const THORNS_RADIUS: float = 2.5
## Zweite Staffel: Anteil des Maximal-Lebens nach dem Aufstehen, Sekunden Unverwundbarkeit und
## die Druckwelle (Umkreis, Stärke des Wegstoßens in m/s am Rand, Schaden: keiner).
const REVIVE_HP_SHARE: float = 0.3
const REVIVE_INVULNERABILITY: float = 1.5
const REVIVE_SHOCKWAVE_RADIUS: float = 6.0
const REVIVE_SHOCKWAVE_KNOCKBACK: float = 12.0
const REVIVE_SHOCKWAVE_DAMAGE: float = 0.0
## Requisitenbombe: höchstens so viele Minen zugleich, Auslöse-Abstand und Radius der Explosion.
const MINE_MAX_ACTIVE: int = 5
const MINE_TRIGGER_RADIUS: float = 1.2
const MINE_RADIUS: float = 3.0

# --- Rucksack (Abschnitt 16) ---
## Größtes Raster des Rucksacks in Feldern.
const BACKPACK_COLS: int = 7
const BACKPACK_ROWS: int = 5
## Punkte beim Verkaufen: Gegenstand der Rarität Gewöhnlich (jede Rarität darüber verdoppelt,
## weil sie aus zwei Gegenständen der Rarität darunter entsteht) und Rucksack-Teil.
const ITEM_SELL_BASE: int = 100
const ITEM_SELL_BAG: int = 150

# --- Material, Verschrotten, Reparieren (Abschnitt 26) ---
## Material zu Beginn eines Laufs und für jede geschaffte Welle.
const MATERIAL_START: int = 3
const MATERIAL_PER_WAVE: int = 2
## Reparatur eines kaputten Gegenstands, je Rarität (Index 0 = Gewöhnlich).
const REPAIR_COST: Array[int] = [1, 2, 3, 4, 5]
## Material fürs Verschrotten, je Rarität. Ein Rucksack-Teil gibt SCRAP_YIELD_BAG.
const SCRAP_YIELD: Array[int] = [1, 2, 3, 4, 6]
const SCRAP_YIELD_BAG: int = 1
## Kisten: Wurde so viele Kisten lang kein Rucksack-Teil angeboten, enthält die nächste sicher
## eines (solange im Raster noch Platz ist).
const CHEST_BAG_PITY: int = 2
## Chance, dass eine Kiste ein Rucksack-Teil anbietet (zusätzlich zur Garantie oben).
const CHEST_BAG_CHANCE: float = 0.3
## Gegenstände aus der letzten Kiste kommen in der nächsten seltener: Faktor auf ihr Gewicht.
const CHEST_REPEAT_WEIGHT: float = 0.2
## Verstärker beschleunigen das Nachladen höchstens um diesen Bruchteil.
const RELOAD_BONUS_MAX: float = 0.5
const UPGRADE_MAX_LEVEL: int = 5
## Kettenblitz: Sprungradius und Chance-Faktor je Schrotkugel (Waffen mit mehr als einer Kugel).
const CHAIN_RADIUS: float = 6.0
const CHAIN_PELLET_CHANCE_FACTOR: float = 0.35
## Durchschlag: Schadensverlust je weiterem Ziel.
const PIERCE_DAMAGE_FALLOFF: float = 0.15
const BURN_DURATION: float = 4.0
const BURN_ELITE_FACTOR: float = 0.3
## Vom Vertrag offen gelassen: Abstand der Brand-Ticks in Sekunden.
const BURN_TICK_INTERVAL: float = 0.5
const LIFESTEAL_MAX_PER_SECOND: float = 15.0
## Länge des Zeitfensters für die Obergrenze des Lebensraubs ("je Sekunde"). Es beginnt mit der
## ersten Heilung.
const LIFESTEAL_WINDOW: float = 1.0
## Konfetti-Explosion: höchste Kettentiefe (chain_depth) und Verzögerung der Folgeexplosion.
const EXPLOSION_MAX_CHAIN: int = 3
const EXPLOSION_CHAIN_DELAY: float = 0.12
const SHOCKWAVE_COOLDOWN: float = 3.0
## Vom Vertrag offen gelassen: Stärke des Wegstoßens (m/s) am Rand der Druckwelle.
const SHOCKWAVE_KNOCKBACK: float = 9.0
## Reichweite der Kameradrohne ohne Zoom. Die geltende Reichweite jeder Kamera steht in
## Game.cameras (CameraDefs), diese Zahl ist nur noch der Grundwert zum Nachschlagen.
const DRONE_RANGE: float = 15.0
## Vom Vertrag offen gelassen: Flughöhe der Drohne über den Füßen des Spielers.
const DRONE_HOVER_HEIGHT: float = 2.4
## Solange kein Ziel da ist, sucht die Drohne nur in diesem Abstand neu (Sekunden).
const DRONE_SCAN_INTERVAL: float = 0.1
## Synergie Gewitterfront: höchstens so viele Blitz-Auslösungen je Schuss.
const STORM_FRONT_MAX_PROCS_PER_SHOT: int = 6

# --- Level ---
## Raummaße als Vector3(Breite X, Höhe Y, Tiefe Z) in Metern. ZONE1_SIZE ist die Bühne (bis
## Ausbau 3: 22 × 18 m, seitdem rund 40 % mehr Fläche), ZONE2_SIZE gilt für jeden der vier
## kaufbaren Räume.
const ZONE1_SIZE: Vector3 = Vector3(26.5, 5.0, 21.0)
const ZONE2_SIZE: Vector3 = Vector3(14.0, 5.0, 12.0)
const STAGE_HEIGHT: float = 0.4
