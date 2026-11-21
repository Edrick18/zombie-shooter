# Zombie-Shooter – Architektur des Prototyps

Verbindlicher Bauplan für den ersten spielbaren Prototyp. Wer am Code arbeitet, hält sich an die
Namen, Signale und Zahlen in diesem Dokument. Abweichungen werden hier nachgetragen, nicht still gemacht.

## 1. Das Spiel in Kürze

Trashig-witziger 3D-Egoshooter für PC (Solo). Setting: eine TV-Gameshow, in der der Kandidat
Zombie-Wellen überleben muss. Wellen laufen endlos, bis der Spieler stirbt. Punkte für Treffer und Kills,
damit kauft man Wandwaffen und öffnet die zweite Zone. Der Kern: Elite-Zombies (und selten normale)
lassen **Kisten** fallen. Wer eine Kiste aufsammelt, wählt **1 aus 3 Upgrades**. Upgrades hängen am
Spieler und gelten für jede Waffe. So entstehen Builds.

Nicht im Prototyp: Perk-Automaten, Glücksrad, Händler, Bosswelle, Moderator-Sprüche, Meta-Progression,
Ton, echte 3D-Modelle (alles Platzhalter aus einfachen Formen).

## 2. Technik und Regeln für den Code

- **Engine:** Godot 4.7, GDScript, Renderer `gl_compatibility`, Fenster 1280×720, Stretch `canvas_items`/`expand`.
- **Godot (Konsole, für Tests):** `%USERPROFILE%\Downloads\Godot_v4.7\Godot_v4.7-stable_win64_console.exe`
  (GUI-Version daneben: `Godot_v4.7-stable_win64.exe`). Umgebungsvariable `GODOT_EXE` hat Vorrang.
- **Projektordner:** `E:\cod zombie spiel` (Leerzeichen im Pfad: in Befehlen immer in Anführungszeichen).
- **Sprache:** Bezeichner (Dateien, Klassen, Funktionen, Variablen, Signale) englisch. Kommentare
  (`##`-Doc-Kommentare über Klassen und öffentlichen Funktionen) deutsch. Alle sichtbaren Spieltexte deutsch.
- **Typisiertes GDScript** überall (`var x: int`, `func f(a: float) -> void`).
- **Keine `class_name`-Globals zwischen Dateien.** Fremde Skripte immer per
  `const Foo := preload("res://scripts/…/foo.gd")` einbinden. Grund: Der Klassen-Cache entsteht erst beim
  Import, headless-Tests würden sonst mit „Identifier not found“ scheitern.
- **Szenen entstehen im Code.** Es gibt nur `scenes/main.tscn` (ein Node3D mit `scripts/game/main.gd`).
  Alles andere (Level, Spieler, Zombies, HUD) wird per Skript aufgebaut. Keine weiteren `.tscn`-Dateien.
- **Regeln getrennt von Nodes.** Alles, was Spielregel oder Zahl ist, liegt in `scripts/core/` als
  `RefCounted` ohne Node-Abhängigkeit und ohne Zugriff auf Autoloads, damit es headless testbar ist.
  Zufall in `core/` immer über einen übergebenen `RandomNumberGenerator`.
- **Alle Zahlen in `scripts/core/balance.gd`**, nirgends sonst fest im Code.
- **Autoloads:** `Events` (Signalbus) und `Game` (Zustand des Laufs). Geprüft: Sie stehen in Godot 4.7 auch
  in `-s`-Tests zur Verfügung.
- **UI-Falle:** Anker/Presets eines Control immer **vor** `add_child` setzen (sonst Größe 0).
- **Null-Zugriffe nie hinnehmen.** Zombies und Kisten können mitten in einem Frame verschwinden: vor
  Zugriff `is_instance_valid(x)` prüfen. Tote Zombies nie zweimal töten (`is_dead`-Flag).
- **Pause:** Bei Kistenwahl, Pausemenü und Game Over ist `get_tree().paused = true`. UI-Knoten dafür
  haben `process_mode = PROCESS_MODE_ALWAYS`.

## 3. Ordner

```
project.godot
start.ps1                 Editor oder Spiel starten
run_tests.ps1             alle tests/test_*.gd headless
build.ps1                 EXE bauen: build/ZombieShooter.exe (eine Datei, Spieldaten eingebettet)
EXE bauen.bat             Knopf zum Doppelklicken, ruft build.ps1 auf
export_presets.cfg        Export-Einstellung "Windows Desktop" (ohne tests, docs, _shots, build)
data/shader_warmup.json   mitgelieferte Liste der Material-Arten zum Vorwärmen (Abschnitt 15)
docs/ARCHITEKTUR.md
scenes/main.tscn
scripts/
  autoload/events.gd      Signalbus
  autoload/game.gd        Zustand des Laufs
  core/                   reine Regeln (RefCounted)
    balance.gd
    upgrade_defs.gd
    upgrade_state.gd
    chest_roller.gd
    wave_plan.gd
    weapon_defs.gd
    weapon_state.gd
  game/
    main.gd               baut alles zusammen
    player/player.gd
    player/weapon_controller.gd
    player/view_model.gd
    level/level_builder.gd
    level/door.gd
    level/wall_buy.gd
    zombies/zombie.gd
    zombies/zombie_spawner.gd
    zombies/wave_manager.gd
    upgrades/upgrade_effects.gd
    upgrades/chest.gd
    upgrades/chest_dropper.gd
    upgrades/drone.gd
    fx/fx.gd              Leuchtspur, Blitzbogen, Explosion, Konfetti, Trefferzahl
  ui/
    hud.gd
    chest_choice.gd
    pause_menu.gd
    game_over.gd
tests/
  check_scripts.gd        lädt jedes Skript und meldet Parse-Fehler
  test_*.gd               Tests (extends SceneTree), darunter der Gesamttest test_smoke_game.gd
  capture_game.gd         Bildschirmfotos mit echter Grafik (kein Test)
_shots/                   Ausgabe von capture_game.gd (nicht in Git)
```

## 4. Kollisionslagen und Gruppen

| Lage | Name | Wer |
|---|---|---|
| 1 | world | Boden, Wände, Tür, Deko mit Kollision |
| 2 | player | Spieler |
| 3 | zombies | Zombies |
| 4 | pickups | Kisten (Area3D) |
| 5 | interactables | Wandkauf, Tür (Area3D oder StaticBody3D für den Blick-Strahl) |
| 6 | player_block | Sperren nur für den Spieler: Zombie-Gänge und Publikum. Zombies und Schüsse gehen hindurch |

- Spieler: layer 2, mask 1+3+6. Zombie: layer 3, mask 1+2+3. Schuss-Strahl: mask 1+3. Blick-Strahl für
  Interaktion: mask 1+5. Kiste (Area3D): layer 4, mask 2.
- Gruppen: `player`, `zombies`, `chests`, `interactables`, `zombie_spawns`, `nav_source` (Geometrie, aus der
  das Navigationsnetz gebacken wird), `player_block` (die Sperren der Lage 6), `main`, `fx_root`.

## 5. Eingaben (InputMap in project.godot)

`move_forward` W · `move_back` S · `move_left` A · `move_right` D · `jump` Leertaste · `sprint` Umschalt ·
`fire` linke Maustaste · `reload` R · `interact` E · `weapon_next` Mausrad hoch · `weapon_prev` Mausrad runter ·
`weapon_1` 1 · `weapon_2` 2 · `weapon_3` 3 · `pause` Esc.
In der Kistenwahl wählen die Tasten 1/2/3 oder ein Mausklick die Karte.

## 6. Autoloads

### Events (`scripts/autoload/events.gd`)

Nur Signale, keine Logik.

```gdscript
signal points_changed(total: int)
signal banner(text: String)                                   # kurze Meldung in der Bildmitte oben
signal wave_started(wave: int, total_zombies: int)
signal wave_cleared(wave: int)
signal intermission_tick(seconds_left: int)
signal zombies_left_changed(left: int)                        # noch nicht getötete Zombies der Welle
signal zombie_spawned(zombie: Node3D)
signal zombie_damaged(zombie: Node3D, amount: float, info: Dictionary)
signal zombie_killed(zombie: Node3D, info: Dictionary)
signal bullet_hit(zombie: Node3D, damage: float, info: Dictionary)   # nur Kugeltreffer der Waffe
signal player_health_changed(hp: float, max_hp: float)
signal player_damaged(amount: float)
signal player_died()
signal weapon_changed(weapon_id: String)
signal ammo_changed(mag: int, reserve: int)                   # reserve -1 = unendlich
signal weapon_fired(weapon_id: String)
signal reload_started(weapon_id: String, duration: float)
signal reload_finished(weapon_id: String)
signal chest_dropped(chest: Node3D)
signal chest_opened(rarity: int, offers: Array)               # offers: Array von Dictionaries, siehe ChestRoller
signal upgrade_chosen(upgrade_id: String, new_level: int)
signal synergy_unlocked(synergy_id: String)
signal interact_prompt_changed(text: String)                  # "" = keine Anzeige
signal game_over(stats: Dictionary)
signal run_started()
```

### Game (`scripts/autoload/game.gd`)

Hält den Zustand eines Laufs. Kennt keine konkreten Level- oder UI-Knoten.

```gdscript
enum State { MENU, PLAYING, CHOOSING, PAUSED, GAME_OVER }
var state: State
var points: int
var wave: int                      # aktuelle Welle, 0 vor dem Start
var kills: int
var total_points_earned: int
var upgrades                       # UpgradeState (core)
var rng: RandomNumberGenerator
var player: Node3D                 # wird vom Spieler in _ready gesetzt, sonst null

func start_run(seed_value: int = -1) -> void     # setzt alles zurück, sendet run_started
func add_points(base_amount: int) -> void        # wendet den Punkte-Faktor aus den Upgrades an
func can_afford(cost: int) -> bool
func spend_points(cost: int) -> bool
func open_chest(rarity: int) -> void             # würfelt Angebote, pausiert, State CHOOSING, sendet chest_opened
func choose_offer(index: int) -> void            # wendet an, sendet upgrade_chosen (+ synergy_unlocked), Pause aus
func set_paused(paused: bool) -> void            # Pausemenü
func end_run() -> void                           # nach player_died: State GAME_OVER, sendet game_over(stats)
```

`Game` hört selbst auf `zombie_damaged` (Kugeltreffer geben Treffer-Punkte) und `zombie_killed`
(Kill-Punkte, `kills += 1`) sowie auf `player_died` (ruft `end_run`).
`stats` = `{ "wave": int, "kills": int, "points": int, "upgrades": Array }`.
Die Maus ist im State PLAYING gefangen (`MOUSE_MODE_CAPTURED`), sonst sichtbar. Das stellt `Game` um.

## 7. Schadensweg (der wichtigste Vertrag)

```gdscript
# zombie.gd
func take_damage(amount: float, info: Dictionary) -> void
```

`info`-Schlüssel (alle optional außer `source`):
- `source: String` – `"bullet"`, `"lightning"`, `"burn"`, `"explosion"`, `"shockwave"`, `"drone"`
- `headshot: bool`, `weapon_id: String`, `hit_position: Vector3`, `chain_depth: int`

Ablauf:
1. Die Waffe schießt einen Strahl (bei Durchschlag mehrere Treffer hintereinander), ruft für jeden
   getroffenen Zombie `take_damage(schaden, {source = "bullet", …})` und sendet danach
   `Events.bullet_hit(zombie, schaden, info)`.
2. `zombie.take_damage` zieht Leben ab, sendet `Events.zombie_damaged`. Fällt das Leben auf 0: `is_dead = true`,
   `Events.zombie_killed(self, info)`, kurze Todesanimation, dann `queue_free()`.
3. `UpgradeEffects` hört zu: `bullet_hit` → Kettenblitz, Brand. `zombie_damaged` → Lebensraub.
   `zombie_killed` → Konfetti-Explosion. `reload_started` → Schockwelle.
4. `Game` vergibt Punkte, `ChestDropper` entscheidet über eine Kiste, `WaveManager` zählt mit.

Effekte lösen einander nicht endlos aus: Nur `source == "bullet"` löst Kettenblitz und Brand aus.
Konfetti-Explosionen dürfen Ketten bilden, aber höchstens `Balance.EXPLOSION_MAX_CHAIN` tief
(`chain_depth` in `info`), und Folgeexplosionen laufen verzögert (`call_deferred` oder kurzer Timer).

Weitere Zombie-Schnittstelle:

```gdscript
var zombie_type: String            # "walker", "sprinter", "elite"
var max_hp: float
var hp: float
var is_dead: bool
func setup(type: String, wave: int) -> void          # vor add_child aufrufen
func apply_burn(dps: float, duration: float) -> void # erneuert Dauer, höherer dps gewinnt
func apply_knockback(impulse: Vector3) -> void
```

Kopftreffer: Trefferpunkt höher als `Balance.HEADSHOT_HEIGHT_RATIO` der Zombiehöhe über dessen Füßen.

Spieler-Schnittstelle (`player.gd`, Gruppe `player`):

```gdscript
var hp: float
var max_hp: float
func take_damage(amount: float) -> void
func heal(amount: float) -> void
func refresh_stats() -> void       # liest max_hp und Tempo neu aus Game.upgrades (nach upgrade_chosen)
func get_eye_position() -> Vector3
func get_weapon_controller() -> Node   # WeaponController
```

Waffen-Schnittstelle (`weapon_controller.gd`, Kind des Spielers):

```gdscript
func has_weapon(weapon_id: String) -> bool
func give_weapon(weapon_id: String) -> void          # nimmt auf und wechselt hin
func refill_ammo(weapon_id: String) -> void
func get_current_weapon_id() -> String
```

Interaktion: Knoten in Gruppe `interactables` (Lage 5) bieten

```gdscript
func get_prompt() -> String        # z. B. "E – Schrotflinte kaufen (500)"
func interact(player: Node3D) -> void
```

Der Spieler prüft per Blick-Strahl (Reichweite `Balance.INTERACT_RANGE`) und sendet `interact_prompt_changed`.

## 8. Zahlen (alle in `balance.gd`)

### Spieler
- Leben 100. **Keine** automatische Heilung. Am Wellenende +25 Leben.
- Gehen 5,0 m/s, Sprinten 7,0 m/s, Sprung 4,5 m/s, Schwerkraft 12 m/s². Augenhöhe 1,6 m. Sichtfeld 80°.
- Nach einem Treffer 0,5 s unverwundbar gegen weitere Zombie-Schläge.
- `INTERACT_RANGE` 2,5 m.

### Punkte
- Kugeltreffer 10, Kill 60, Kopfschuss-Kill +30, Elite-Kill 150 (statt 60). Start: 0 Punkte.
- Tür zur Zone „Backstage“: 750.

### Waffen (`weapon_defs.gd`)

| id | Name | Schaden | Schuss/s | Magazin | Vorrat | Nachladen | Streuung | Kugeln | Auto | Preis | Munition |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `pistol` | Dienstpistole | 25 | 5 | 10 | unendlich | 1,2 s | 0,5° | 1 | nein | Startwaffe | – |
| `shotgun` | Publikumsjoker | 14 | 1,25 | 6 | 36 | 2,2 s | 5° | 8 | nein | 500 | 250 |
| `smg` | Quotenhammer | 16 | 12 | 30 | 150 | 1,8 s | 1,8° | 1 | ja | 1000 | 500 |

Reichweite 60 m, Kopfschuss ×2. Der Spieler trägt alle gekauften Waffen (Tasten 1–3, Mausrad).
Erneuter Kauf an derselben Wand füllt die Munition für den Munitionspreis.

### Zombies

| Typ | Leben | Tempo | Schaden | ab Welle | Farbe |
|---|---|---|---|---|---|
| `walker` (Schlurfer) | 60 | 1,6 → 3,0 m/s | 20 | 1 | graugrün |
| `sprinter` | 35 | 5,0 m/s | 15 | 3 | rot |
| `elite` | 400 | 2,6 m/s | 35 | 2 | gold, leuchtet, 1,3-fache Größe |

- Lebens-Faktor je Welle: `1 + 0.12 * (wave - 1)` bis Welle 10, danach je Welle ×1,1 zusätzlich.
- Schlurfer-Tempo steigt je Welle um 0,1 m/s bis 3,0.
- Angriff: Reichweite 1,4 m, Ausholen 0,4 s, danach 1,0 s Pause.
- Zombies je Welle: `6 + 4 * wave`. Davon Sprinter ab Welle 3: 20 %, ab Welle 6: 35 %.
  Elite: ab Welle 2 eine, ab Welle 6 zwei, ab Welle 10 drei (zusätzlich zur Zahl oben).
- Gleichzeitig lebend höchstens 24. Spawn-Abstand `max(0.4, 1.5 - 0.1 * wave)` s.
- Pause zwischen Wellen 12 s. Erste Welle startet 4 s nach Spielbeginn.

### Kisten (`chest_roller.gd`)
- Elite lässt immer eine Kiste fallen. Normale Zombies mit 3 % (+ Glück).
- Welle 1 hat keine Elite: Der letzte Zombie von Welle 1 lässt sicher eine Kiste fallen.
- Seltenheit `0 = Bronze`, `1 = Silber`, `2 = Gold`. Normale Kiste 70/25/5 %, Elite-Kiste 50/40/10 %.
  Glück verschiebt je Stufe 4 Prozentpunkte von Bronze zu Silber und 2 zu Gold.
- Die Seltenheit bestimmt die Stufen, die das gewählte Upgrade bekommt: Bronze +1, Silber +2, Gold +3
  (höchstens Stufe 5).
- Angebot: 3 verschiedene Upgrades aus den wählbaren. Wählbar ist ein Upgrade, wenn es noch nicht Stufe 5 hat
  und entweder schon im Besitz ist oder noch ein Platz frei ist. **6 Plätze.**
- Gibt es weniger als 3 wählbare, füllen Trostpreise auf: `{ "kind": "points", "amount": 500 }` oder
  `{ "kind": "heal", "amount": 50 }`.
- Angebot als Dictionary: `{ "kind": "upgrade", "id": String, "from_level": int, "to_level": int }`.
- Die Kiste bleibt liegen, bis der Spieler hineinläuft. Dann öffnet sich die Wahl, das Spiel pausiert.

### Upgrades (`upgrade_defs.gd`), Stufen 1–5

| id | Name im Spiel | Wirkung je Stufe |
|---|---|---|
| `chain_lightning` | Starkstrom-Sponsor | Kugeltreffer löst mit 10/15/20/25/30 % einen Blitz aus (Schrotkugel: Chance ×0,35). Springt auf 2/3/4/5/6 weitere Zombies im Umkreis von 6 m. Schaden 50/60/70/80/100 % des Kugelschadens. |
| `pierce` | Spezialmunition | Kugeln durchschlagen 1/2/3/4/5 weitere Zombies, je weiterem Ziel −15 % Schaden. |
| `burn` | Feuershow | Kugeltreffer setzt 4 s in Brand: 3/5/7/9/12 % des Maximal-Lebens je Sekunde (Elite: ×0,3). |
| `lifesteal` | Blutspende-Aktion | 2/4/6/8/10 % allen verursachten Schadens heilen den Spieler, höchstens 15 Leben je Sekunde. |
| `max_hp` | Stuntdouble | +20/40/60/80/100 Maximal-Leben, heilt beim Erhalt um den Zuwachs. |
| `corpse_explosion` | Konfetti-Kanone | Getötete Zombies explodieren mit 15/20/25/30/35 %. Radius 3,0/3,25/3,5/3,75/4,0 m. Schaden 30/40/50/60/75 % des Maximal-Lebens des Toten. |
| `reload_shockwave` | Werbepause | Beim Nachladen eine Druckwelle: Radius 4/4,5/5/5,5/6 m, Schaden 20/35/50/65/80 × Effekt-Faktor, stößt weg. Abklingzeit 3 s. |
| `drone` | Kameradrohne | Fliegende Kamera folgt dem Spieler und schießt alle 1,2/1,0/0,8/0,65/0,5 s auf den nächsten sichtbaren Zombie in 15 m. Schaden 12/16/20/24/30 × Effekt-Faktor. |
| `speed` | Turbo-Turnschuhe | +8/16/24/32/40 % Lauftempo. |
| `luck` | Publikumsliebling | +10/20/30/40/50 % Punkte, +1/2/3/4/5 Prozentpunkte Kistenchance bei normalen Zombies, Glück-Stufe für die Seltenheit. |

- **Effekt-Faktor** (damit feste Schadenswerte mitwachsen): `0.75 * Lebens-Faktor der Welle`, mindestens 1.
- **Synergie `storm_front` („Gewitterfront“):** `chain_lightning` 5 und `pierce` 5. Belegt keinen Platz.
  Jeder Kugeltreffer löst sicher einen Blitz aus, höchstens 6 Blitz-Auslösungen je Schuss.
- Drohnen-, Blitz-, Brand-, Explosions- und Schockwellenschaden lösen keine Kugel-Effekte aus,
  zählen aber für Lebensraub und geben Kill-Punkte (keine Treffer-Punkte).

`UpgradeState` (core) bietet:

```gdscript
const MAX_SLOTS := 6
const MAX_LEVEL := 5
func get_level(id: String) -> int
func add_levels(id: String, levels: int) -> int      # gibt die neue Stufe zurück
func owned_ids() -> Array[String]
func free_slots() -> int
func is_eligible(id: String) -> bool
func has_synergy(id: String) -> bool
func check_new_synergies() -> Array[String]          # neu freigeschaltete seit dem letzten Aufruf
func value(id: String, key: String) -> float         # Wert der aktuellen Stufe, 0.0 wenn nicht im Besitz
func points_multiplier() -> float
func speed_multiplier() -> float
func bonus_max_hp() -> float
func luck_level() -> int
```

## 9. Level „Studio“ (`level_builder.gd`)

Alles aus Quadern (MeshInstance3D + StaticBody3D), bunt und grell beleuchtet wie ein billiges TV-Studio.

- **Zone 1 „Bühne“** (Start): Raum ca. 22 × 18 m, 5 m hoch. Eine flache Bühne (0,4 m) mit Showtreppe,
  Zuschauertribüne als Deko, ein paar Kulissen als Deckung. 3 Zombie-Eingänge (Öffnungen in der Wand mit
  kurzem Gang dahinter, dort die Spawnpunkte). Wandkauf Schrotflinte.
- **Zone 2 „Backstage“**: Raum ca. 14 × 12 m hinter einer kaufbaren Tür (750). 2 weitere Zombie-Eingänge,
  die erst nach dem Öffnen aktiv sind. Wandkauf MP.
- Spawnpunkte sind `Marker3D` in Gruppe `zombie_spawns` mit Meta `zone` (1 oder 2).
- Navigation: eine `NavigationRegion3D`, deren Netz zur Laufzeit aus den Kollisionen der Gruppe `nav_source`
  gebacken wird. Die Tür selbst gehört nicht zu `nav_source` (das Netz führt durch die Türöffnung). Solange
  die Tür zu ist, sind die Spawns der Zone 2 aus, also läuft kein Zombie gegen die Tür.
- `level_builder.gd` liefert: `func build(parent: Node3D) -> Dictionary` mit
  `{ "player_spawn": Vector3, "nav_region": NavigationRegion3D, "door": Node3D }`.
- `door.gd`: `is_open`, Signal `opened`. Nach dem Öffnen: Kollision weg, Türblatt fährt hoch,
  Spawns der Zone 2 aktiv.

## 10. Zombies

`CharacterBody3D` mit `NavigationAgent3D`. Ziel ist der Spieler, Pfad alle 0,25 s neu. Gibt es kein
Navigationsnetz (headless-Test), laufen sie geradeaus auf den Spieler zu. Einfache Abstoßung untereinander,
damit sie nicht in einem Punkt stehen. Aussehen: Kapsel-Körper, Kugel-Kopf, zwei ausgestreckte Arme, Farbe
nach Typ, wackelnder Gang im Code. Treffer lassen kurz weiß aufblitzen, Brand färbt orange.

`zombie_spawner.gd`: `func spawn(type: String, wave: int) -> Node3D` wählt einen aktiven Spawnpunkt
(möglichst nicht den dem Spieler nächsten zweimal hintereinander).
`wave_manager.gd`: steuert Wellen nach `WavePlan`, sendet `wave_started`, `zombies_left_changed`,
`wave_cleared`, `intermission_tick`, heilt am Wellenende.

## 11. Oberfläche

- **HUD:** Lebensbalken mit Zahl (unten links), Punkte (oben rechts, groß), Welle und verbleibende Zombies
  (oben links), Waffenname und Munition (unten rechts), Fadenkreuz, Treffermarker, Interaktions-Hinweis
  (Mitte unten), Upgrade-Leiste mit Name und Stufe (links, bis 6 Einträge + Synergie), Banner-Meldungen
  (Welle X, Synergie), roter Rand bei Schaden, Countdown zwischen Wellen.
- **Kistenwahl:** 3 Karten nebeneinander mit Seltenheits-Farbe (Bronze/Silber/Gold), Name, „Stufe 2 → 4“,
  Wirkungstext mit Zahlen der neuen Stufe. Wahl per Taste 1/2/3 oder Klick. Überschrift im Showton.
- **Pausemenü (Esc):** Weiter, Neustart, Beenden.
- **Game Over:** erreichte Welle, Kills, Punkte, Upgrades. Knöpfe Neustart und Beenden.
- Look: Gameshow, kräftige Farben, große Schrift. Kein Text, der über den Rand läuft (1280×720 als Maß).

## 12. Tests

- `tests/check_scripts.gd`: lädt alle `res://scripts/**/*.gd` und meldet jede Datei, die nicht lädt.
- Reine Regeln: `test_upgrade_state.gd`, `test_chest_roller.gd`, `test_wave_plan.gd`, `test_weapon_state.gd`,
  dazu `test_game_state.gd` (Autoload `Game`, Projekteinstellungen).
- Je Modul ein Test mit Ersatz-Knoten für die Nachbarn: `test_player_weapons.gd`, `test_zombies_waves.gd`,
  `test_upgrade_effects.gd`, `test_level.gd`, `test_ui.gd`.
- Gesamttest `test_smoke_game.gd`: lädt `scenes/main.tscn` headless als aktuelle Szene und spielt einen
  Lauf über die öffentlichen Schnittstellen: Schuss → Kill → Punkte, Elite → Kiste → Wahl → Upgrade, alle
  zehn Upgrades mit erzwungener Stufe, Synergie bei 5 + 5, Tür (echter Blick-Strahl, Taste E) mit Pfaden
  von jedem Spawnpunkt, kein Zombie-Schlag durch die Wand zwischen Bühne und Backstage, Wandkäufe,
  zweiter Lauf in derselben Szene, drei ganze Wellen mit einem schummelnden Spieler, Tod → Game Over,
  Neustart → sauberer zweiter Lauf.
- Ein Test besteht nur, wenn Godot mit Code 0 endet und die Ausgabe weder `SCRIPT ERROR` noch `ERROR:` enthält.
- `tests/capture_game.gd` (ohne `--headless`, Fenster 1280×720): speichert Bildschirmfotos typischer
  Situationen in einen übergebenen Ordner. Aufruf:
  `Godot_v4.7-stable_win64_console.exe --path "E:\cod zombie spiel" -s res://tests/capture_game.gd -- "E:\cod zombie spiel\_shots"`.
  Das Skript beendet sich immer selbst (Zeitlimit 120 s, dann Exit-Code 2).

## 13. Zusammenbau und genaue Schnittstellen

Stand nach dem Zusammenbau aller Module. Dieser Abschnitt beschreibt den Code, wie er ist.
Wo er den Abschnitten 1 bis 12 etwas hinzufügt oder sie genauer fasst, gilt dieser Abschnitt.
Bewusste Abweichungen von den Abschnitten 1 bis 12 und offene Punkte stehen in Abschnitt 14.

### 13.1 Wem welche Datei gehört

| Modul | Dateien | Test |
|---|---|---|
| Fundament | `project.godot`, `scenes/main.tscn`, `scripts/autoload/*`, `scripts/core/*`, `scripts/game/main.gd`, `run_tests.ps1`, `start.ps1` | `check_scripts.gd`, `test_upgrade_state.gd`, `test_chest_roller.gd`, `test_wave_plan.gd`, `test_weapon_state.gd`, `test_game_state.gd` |
| Spieler | `scripts/game/player/player.gd`, `weapon_controller.gd`, `view_model.gd` | `test_player_weapons.gd` |
| Level | `scripts/game/level/level_builder.gd`, `door.gd`, `wall_buy.gd` | `test_level.gd` |
| Zombies | `scripts/game/zombies/zombie.gd`, `zombie_spawner.gd`, `wave_manager.gd` | `test_zombies_waves.gd` |
| Upgrades | `scripts/game/upgrades/upgrade_effects.gd`, `chest.gd`, `chest_dropper.gd`, `drone.gd` | `test_upgrade_effects.gd` |
| FX | `scripts/game/fx/fx.gd` | in `test_upgrade_effects.gd` |
| Oberfläche | `scripts/ui/hud.gd`, `chest_choice.gd`, `pause_menu.gd`, `game_over.gd` | `test_ui.gd` |
| Alles zusammen | – | `test_smoke_game.gd`, `capture_game.gd` |

- Alle Module sind fertig gebaut. Öffentliche Namen, Signaturen und Knotennamen aus diesem Abschnitt sind
  fest: Zusätzliche öffentliche Funktionen sind erlaubt, entfernen oder umbenennen nicht.
- Alle Spielzahlen stehen in `balance.gd` (dazu die Waffentabelle in `weapon_defs.gd` und die Stufenwerte
  in `upgrade_defs.gd`). In den Modul-Skripten bleiben nur reine Optik- und Technik-Zahlen (Farben,
  Mesh-Maße, Dauer eines Effekts, Federwerte der Kamera). Eine neue Spielzahl kommt in `balance.gd`.
- Module binden einander nicht im Kreis ein. Ein Elternskript darf sein Kind per `preload` einbinden
  (`player.gd` → `weapon_controller.gd`), das Kind spricht den Elternknoten über `Node3D` und `call(...)` an.
  Fremde Module spricht man über Gruppen, `Game.player`, Events und `has_method`/`call` an.

### 13.2 Zusammenbau in `main.gd`

`scenes/main.tscn` enthält nur den Knoten `Main` (Node3D) mit `scripts/game/main.gd`. `_ready` baut in
dieser Reihenfolge (jeder Knoten ist direkt Kind von `Main`, die Namen sind fest):

| Schritt | Knoten | Typ / Skript | Aufbau |
|---|---|---|---|
| 1 | `Level` | Node3D | `level_info = LevelBuilder.new().build(level_root)` |
| 2 | `Zombies` | Node3D | leerer Behälter für Zombies |
| 3 | `Chests` | Node3D | leerer Behälter für Kisten |
| 4 | `Fx` | Node3D, Gruppe `fx_root` | leerer Behälter für Effekte und die Drohne |
| 5 | `Player` | `player.gd` | `Player.new()`, `position = level_info["player_spawn"]`, `add_child` |
| 6 | `ZombieSpawner` | `zombie_spawner.gd` | `zombie_parent = zombies_root` vor `add_child` |
| 7 | `UpgradeEffects` | `upgrade_effects.gd` | ohne Parameter |
| 8 | `ChestDropper` | `chest_dropper.gd` | `chest_parent = chests_root` vor `add_child` |
| 9 | `WaveManager` | `wave_manager.gd` | `spawner = <ZombieSpawner>` vor `add_child` |
| 10 | `Hud` | `hud.gd`, Ebene 1 | ohne Parameter |
| 11 | `ChestChoice` | `chest_choice.gd`, Ebene 10 | ohne Parameter |
| 12 | `PauseMenu` | `pause_menu.gd`, Ebene 20 | ohne Parameter |
| 13 | `GameOver` | `game_over.gd`, Ebene 30 | ohne Parameter |
| 14 | – | – | `Game.start_run(run_seed)` (nur wenn `start_on_ready`) |

- Jedes Modul entsteht mit `Skript.new()` **ohne Argumente**. Ein `_init` mit Pflicht-Parametern bricht den
  Zusammenbau. Was ein Modul braucht, bekommt es über die oben genannten Eigenschaften, über Gruppen,
  `Game` und Events.
- `main.gd` hat die Variablen mit Skript-Typ: `level_root`, `level_info` (Dictionary), `zombies_root`,
  `chests_root`, `fx_root`, `player`, `spawner`, `upgrade_effects`, `chest_dropper`, `wave_manager`, `hud`,
  `chest_choice`, `pause_menu`, `game_over`. `Main` ist in der Gruppe `main`. Tests greifen darüber zu:
  `main.wave_manager`, `main.level_info["door"]`, `main.get_node("Level/...")`.
- `var run_seed: int = -1` (Seed für `Game.start_run`, vor `add_child` setzen) und
  `var start_on_ready: bool = true`.
- **Zeitpunkt:** Wenn `Game.start_run` läuft, sind alle Module im Baum und haben ihr `_ready` hinter sich.
  Deshalb gilt: **Module richten sich bei `Events.run_started` ein** (volles Leben, Startwaffe, Welle 0,
  Countdown, HUD auf Anfang). Wer in `_ready` schon etwas sendet, sendet es bei `run_started` noch einmal,
  denn das HUD entsteht nach dem Spieler.
- **Neustart:** `Game.restart_run()` setzt den Zustand zurück und lädt die Szene neu
  (`reload_current_scene`). Danach läuft wieder `main._ready` und damit `start_run`. Ein zweites
  `Game.start_run()` in derselben Szene (Tests) funktioniert ebenfalls sauber. Bei jedem `run_started`:
  `main.gd` stellt den Spieler zurück auf `player_spawn` (Blick zur Bühne), der Spieler hat volles Leben,
  der WeaponController nur noch die volle Pistole, der WaveManager räumt alte Zombies weg (`despawn`, ohne
  `zombie_killed`), der ChestDropper alte Kisten, UpgradeEffects die Drohne und wartende Explosionen, die
  Tür schließt sich wieder (`door.close()`, Spawns der Zone 2 aus), das HUD steht auf Anfang.
- **Reihenfolge der Empfänger** von `zombie_killed`: `Game` (Punkte, Kills), `UpgradeEffects`,
  `ChestDropper`, `WaveManager`, danach die Oberfläche. Niemand darf sich auf mehr als das verlassen.

Wo man was findet:

| Gesucht | Weg |
|---|---|
| Spieler | `Game.player` (vor Zugriff `is_instance_valid`), Gruppe `player`, `Main/Player` |
| Kamera | `player.get_camera()`, Knoten `Player/Camera` |
| Waffen | `player.get_weapon_controller()`, Knoten `Player/WeaponController` |
| ViewModel | Knoten `Player/Camera/ViewModel` |
| lebende Zombies | Gruppe `zombies` (tote verlassen die Gruppe sofort), Kinder von `Main/Zombies` |
| Kisten | Gruppe `chests`, Kinder von `Main/Chests` |
| Interaktionsobjekte | Gruppe `interactables` |
| Spawnpunkte | Gruppe `zombie_spawns` (Marker3D, Meta `zone` und `active`) |
| Behälter für Effekte | `Fx.root_of(self)` (Gruppe `fx_root`, Knoten `Main/Fx`) |
| Tür | `main.level_info["door"]`, Knoten `Main/Level/Door` |
| Navigation | `main.level_info["nav_region"]`, Knoten `Main/Level/NavRegion` |
| Zufall | `Game.rng` (für allen Spielzufall der Module, damit Läufe mit Seed wiederholbar sind) |

### 13.3 `Game` (Autoload), genaue Schnittstelle

```gdscript
enum State { MENU, PLAYING, CHOOSING, PAUSED, GAME_OVER }
var state: State                    # MENU bis zum ersten start_run
var points: int
var wave: int                       # setzt Game selbst bei Events.wave_started
var kills: int
var total_points_earned: int
var upgrades: UpgradeState          # wird bei start_run NEU angelegt: nie zwischenspeichern
var rng: RandomNumberGenerator      # wird bei start_run NEU angelegt: nie zwischenspeichern
var player: Node3D                  # setzt der Spieler in _ready, start_run lässt es stehen
var current_offers: Array[Dictionary]   # nur im State CHOOSING gefüllt
var current_rarity: int

func start_run(seed_value: int = -1) -> void
func add_points(base_amount: int) -> void        # roundi(base * upgrades.points_multiplier()), <= 0 wird ignoriert
func can_afford(cost: int) -> bool               # cost >= 0 and points >= cost
func spend_points(cost: int) -> bool
func open_chest(rarity: int) -> void             # nur im State PLAYING, sonst passiert nichts
func choose_offer(index: int) -> void            # nur im State CHOOSING, ungültiger Index ändert nichts
func set_paused(paused: bool) -> void            # nur PLAYING <-> PAUSED
func end_run() -> void                           # wirkt einmal
func get_stats() -> Dictionary
func restart_run() -> void                       # Pause aus, Zustand zurück, Szene neu laden
func quit_game() -> void                         # get_tree().quit()
func is_playing() -> bool                        # state == PLAYING
func effect_factor() -> float                    # WavePlan.effect_factor(max(wave, 1))
```

- `start_run`: setzt Punkte, Welle, Kills, Upgrades und Zufall zurück, State `PLAYING`, Pause aus, sendet
  `run_started` und danach `points_changed(0)`. `seed_value >= 0` setzt den Seed, sonst `randomize()`.
- Punkte: `zombie_damaged` mit `info["source"] == "bullet"` gibt `add_points(10)` (je Aufruf von
  `take_damage`, also bei der Schrotflinte je Kugel). `zombie_killed` gibt `kills += 1` und
  `add_points(60)`, bei Elite `add_points(150)`, bei `info["headshot"] == true` jeweils 30 mehr (Elite mit
  Kopfschuss 180). Den Typ liest `Game` aus `zombie.zombie_type`. Ein ungültiger Zombie zählt als normaler Kill.
- `choose_offer`: Erst State `PLAYING` und Pause aus, dann die Wirkung. Upgrade:
  `upgrades.add_levels(id, to_level - from_level)`, `upgrade_chosen(id, neue_stufe)`, danach je neuer
  Synergie `synergy_unlocked(id)`. Trostpreis Punkte: genau `amount` Punkte, **ohne** Punkte-Faktor (die Karte
  zeigt 500). Trostpreis Heilung: `Game.player.heal(amount)`, wenn der Spieler gültig ist.
- `get_stats()` und `game_over(stats)`: `{ "wave": int, "kills": int, "points": int, "upgrades": Array,
  "synergies": Array[String] }`. `points` sind die **insgesamt verdienten** Punkte (`total_points_earned`).
  `upgrades` ist `UpgradeState.summary()`: je Upgrade `{ "id": String, "name": String, "level": int }` in
  der Reihenfolge des Erwerbs. `synergies` sind Synergie-IDs (Name über `UpgradeDefs.synergy_name`).
- Pause: `open_chest`, `set_paused(true)` und `end_run` setzen `get_tree().paused = true`. `choose_offer`,
  `set_paused(false)`, `start_run` und `restart_run` heben sie auf.
- Maus: im State `PLAYING` `MOUSE_MODE_CAPTURED`, sonst sichtbar. Headless (`DisplayServer.get_name() ==
  "headless"`) fasst `Game` die Maus nicht an.
- `restart_run` ohne `current_scene` (Test, der `Main` selbst an die Wurzel hängt und `current_scene` nicht
  setzt) ruft sofort `start_run()`.

### 13.4 Core-Skripte, genaue Schnittstelle

Alle `extends RefCounted`, ohne Nodes und ohne Autoloads. Einbinden per `preload`.

**`balance.gd`** – nur Konstanten. Gruppen: Kollisionslagen und Masken (`LAYER_WORLD` 1, `LAYER_PLAYER` 2,
`LAYER_ZOMBIES` 4, `LAYER_PICKUPS` 8, `LAYER_INTERACTABLES` 16, `LAYER_PLAYER_BLOCK` 32 als Bitwerte,
`MASK_PLAYER` 37, `MASK_ZOMBIE` 7, `MASK_SHOT` 5, `MASK_INTERACT` 17, `MASK_CHEST` 2,
`MASK_LINE_OF_SIGHT` 1), Spieler, Punkte, Waffen allgemein, Zombies (`ZOMBIE_TYPES`: je Typ `name`, `hp`,
`speed`, `damage`, `from_wave`, `scale`, `color`, `glow`), Wellen, Kisten (`RARITY_BRONZE/SILVER/GOLD`,
`RARITY_NAMES`, `RARITY_COLORS`), Upgrades allgemein, Level (`ZONE1_SIZE`, `ZONE2_SIZE`, `STAGE_HEIGHT`).
Die Datei ist die Liste. Beim Zusammenbau kamen die Zahlen dazu, die die Module gebraucht haben:

| Gruppe | Konstanten |
|---|---|
| Spieler | `PLAYER_AIR_CONTROL` 0.35, `PLAYER_JUMP_BUFFER_TIME` 0.12 s, `PLAYER_COYOTE_TIME` 0.1 s, `PLAYER_STEP_HEIGHT` 0.3 m, `CAMERA_RECOIL_KICK_DEG` (Pistole 0.6, Schrotflinte 2.2, MP 0.32), `CAMERA_RECOIL_RECOVERY` 10 /s, `CAMERA_RECOIL_MAX_DEG` 5 |
| Waffen | `FIRE_BUFFER_TIME` 0.12 s, `FIRE_MAX_SHOTS_PER_FRAME` 4 |
| Zombie-Angriff | `ZOMBIE_ATTACK_WINDUP_SPEED_FACTOR` 0.3, `ZOMBIE_ATTACK_HIT_RANGE_BONUS` 0.3 m, `ZOMBIE_ATTACK_STOP_RANGE_FACTOR` 0.8 |
| Zombie-Bewegung | `ZOMBIE_STAGGER_KNOCKBACK_SPEED` 3 m/s, `ZOMBIE_KNOCKBACK_LIFT_SHARE` 0.2, `ZOMBIE_KNOCKBACK_LIFT_MAX` 2.2 m/s, `ZOMBIE_HOP_PROBE_HEIGHTS` 0.2 / 0.35 / 0.5 / 0.65 m, `ZOMBIE_HOP_COOLDOWN` 0.4 s |
| Festhänge-Sicherung | `ZOMBIE_STUCK_SECONDS` 12, `ZOMBIE_STUCK_MAX_RESCUES` 3, `ZOMBIE_STUCK_MOVE_DISTANCE` 1 m, `ZOMBIE_STUCK_ENGAGED_DISTANCE` 4 m, `ZOMBIE_OUT_OF_WORLD_Y` −15, `ZOMBIE_RESCUE_FALLBACK_DISTANCE` 8 m |
| Spawn | `SPAWN_MIN_PLAYER_DISTANCE` 7 m, `SPAWN_WEIGHT_OFFSET` 6, `SPAWN_JITTER` 0.3 m |
| Kisten | `CHEST_REOPEN_GRACE` 0.4 s, `CHEST_NAV_SNAP_TOLERANCE` 0.6 m, `CHEST_SPACING` 1.3 m |
| Upgrades | `LIFESTEAL_WINDOW` 1 s, `DRONE_SCAN_INTERVAL` 0.1 s |

**`weapon_defs.gd`**

```gdscript
const INFINITE_RESERVE: int = -1
const START_WEAPON: String = "pistol"
const ORDER: Array[String] = ["pistol", "shotgun", "smg"]     # Index + 1 = Taste weapon_1..3
const WEAPONS: Dictionary    # id -> { name, damage, fire_rate, magazine, reserve, reload_time,
                             #         spread_deg, pellets, automatic, price, ammo_price }
static func has(weapon_id: String) -> bool
static func all_ids() -> Array[String]
static func get_def(weapon_id: String) -> Dictionary          # {} bei unbekannter ID
static func display_name(weapon_id: String) -> String
static func fire_interval(weapon_id: String) -> float         # 1 / fire_rate
static func pierce_damage_factor(target_index: int) -> float  # 0 -> 1.0, 1 -> 0.85, 2 -> 0.7225 ...
static func bullet_damage(weapon_id: String, headshot: bool, target_index: int = 0) -> float
```

`damage` gilt je Kugel, `spread_deg` ist der halbe Streuwinkel in Grad, `reserve` der Vorrat beim Kauf und
nach dem Auffüllen (`-1` unendlich), `price` 0 heißt Startwaffe.

**`weapon_state.gd`** – eine Instanz je getragener Waffe.

```gdscript
var weapon_id: String
var mag: int
var reserve: int            # -1 = unendlich
var is_reloading: bool
var reload_left: float
var cooldown_left: float    # <= 0 = schussbereit
func _init(id: String = "pistol")       # volles Magazin, voller Vorrat
func get_def() -> Dictionary
func magazine_size() -> int
func has_infinite_reserve() -> bool
func tick(delta: float) -> bool         # true genau in dem Schritt, in dem ein Nachladen fertig wird
func can_fire() -> bool                 # Kugel im Magazin, kein Nachladen, Schussfolge abgelaufen
func fire() -> bool                     # eine Kugel aus dem Magazin (auch bei 8 Schrotkugeln);
                                        # bleibt nach einem langen Zeitschritt schussbereit (siehe unten)
func can_reload() -> bool               # nicht dabei, Magazin nicht voll, Vorrat != 0
func needs_reload() -> bool             # Magazin leer und can_reload()
func is_out_of_ammo() -> bool           # Magazin leer und Vorrat 0
func reload_duration() -> float
func start_reload() -> bool
func cancel_reload() -> void            # Waffenwechsel: Nachladen verfällt
func refill() -> void                   # Magazin und Vorrat voll, Nachladen beendet
```

Der Controller ruft je Bild erst `tick(delta)`, dann bei Bedarf `fire()`. `fire()` rechnet den Rest des
letzten Zeitschritts an. War der Schritt länger als die Schussfolge (MP unter 12 Bildern je Sekunde,
Ruckler), bleibt die Waffe danach schussbereit, und der Controller schießt bei Dauerfeuer im selben Bild
weiter, insgesamt höchstens `FIRE_MAX_SHOTS_PER_FRAME` Schüsse je Bild. So trifft Dauerfeuer die Schussrate
bei jeder Bildrate ab Schussrate ÷ 4 (MP: ab 3 Bildern je Sekunde), und ein langer Ruckler wird kein
Feuerstoß. Angespart wird nie: Wer in einem Bild nicht schießt, verliert den Rest.

**`wave_plan.gd`** – alles `static`, ohne Zufall. Wellen unter 1 zählen als Welle 1.

```gdscript
static func normal_count(wave: int) -> int            # 6 + 4 * wave (ohne Elite)
static func sprinter_share_percent(wave: int) -> int  # 0, 20 (ab 3), 35 (ab 6)
static func sprinter_count(wave: int) -> int          # Anteil von normal_count, ab ,5 aufgerundet
static func walker_count(wave: int) -> int
static func elite_count(wave: int) -> int             # 0, 1 (ab 2), 2 (ab 6), 3 (ab 10)
static func total_count(wave: int) -> int             # normal_count + elite_count
static func spawn_list(wave: int) -> Array[String]    # geordnet, Einträge "walker" / "sprinter" / "elite"
static func hp_factor(wave: int) -> float
static func walker_speed(wave: int) -> float
static func spawn_interval(wave: int) -> float
static func effect_factor(wave: int) -> float
static func zombie_hp(type: String, wave: int) -> float       # Grundleben * hp_factor
static func zombie_speed(type: String, wave: int) -> float    # walker: walker_speed, sonst fest
static func zombie_damage(type: String) -> float
static func plan(wave: int) -> Dictionary
```

`plan(wave)` liefert `{ "wave": int, "spawns": Array[String], "total": int, "hp_factor": float,
"walker_speed": float, "spawn_interval": float, "effect_factor": float }`. `total` ist die Länge von
`spawns` und der Wert für `wave_started(wave, total_zombies)`.
Beispiele: Welle 1 = 10 Schlurfer. Welle 3 = 14 Schlurfer, 4 Sprinter, 1 Elite. Welle 6 = 19 / 11 / 2.
Welle 10 = 30 / 16 / 3. Sprinter sind gleichmäßig gestreut, Elite gleichmäßig über die Welle verteilt.

**`upgrade_defs.gd`**

```gdscript
const MAX_LEVEL: int = 5
const ORDER: Array[String]      # die 10 IDs in fester Reihenfolge
const UPGRADES: Dictionary      # id -> { name, description, values, fixed, format }
const SYNERGIES: Dictionary     # id -> { name, description, requires, fixed, format }
static func all_ids() -> Array[String]
static func has(upgrade_id: String) -> bool
static func display_name(upgrade_id: String) -> String
static func value_keys(upgrade_id: String) -> Array[String]
static func value(upgrade_id: String, key: String, level: int) -> float   # 0.0 bei Stufe <= 0
static func effect_text(upgrade_id: String, level: int) -> String         # deutscher Text mit Zahlen der Stufe
static func synergy_ids() -> Array[String]                                # ["storm_front"]
static func synergy_name(synergy_id: String) -> String                    # "Gewitterfront"
static func synergy_text(synergy_id: String) -> String
static func synergy_requirements(synergy_id: String) -> Dictionary        # { "chain_lightning": 5, "pierce": 5 }
static func format_number(number: float) -> String                        # 3.25 -> "3,25", 4.0 -> "4"
static func format_percent(fraction: float) -> String                     # 0.15 -> "15"
```

Schlüssel für `value(...)` und `Game.upgrades.value(id, key)`. Anteile und Chancen sind **Bruchteile**
(0.15 = 15 %), keine Prozentzahlen:

| id | Schlüssel und Werte der Stufen 1 bis 5 | dazu aus `Balance` |
|---|---|---|
| `chain_lightning` | `chance` 0.10 / 0.15 / 0.20 / 0.25 / 0.30 · `jumps` 2 / 3 / 4 / 5 / 6 · `damage_factor` 0.5 / 0.6 / 0.7 / 0.8 / 1.0 | `CHAIN_RADIUS` 6, `CHAIN_PELLET_CHANCE_FACTOR` 0.35 (Waffen mit `pellets` > 1), `STORM_FRONT_MAX_PROCS_PER_SHOT` 6 |
| `pierce` | `targets` 1 / 2 / 3 / 4 / 5 | `PIERCE_DAMAGE_FALLOFF` 0.15, gerechnet in `WeaponDefs.pierce_damage_factor` |
| `burn` | `dps_percent` 0.03 / 0.05 / 0.07 / 0.09 / 0.12 | `BURN_DURATION` 4, `BURN_ELITE_FACTOR` 0.3, `BURN_TICK_INTERVAL` 0.5 |
| `lifesteal` | `ratio` 0.02 / 0.04 / 0.06 / 0.08 / 0.10 | `LIFESTEAL_MAX_PER_SECOND` 15 |
| `max_hp` | `bonus` 20 / 40 / 60 / 80 / 100 | – |
| `corpse_explosion` | `chance` 0.15 / 0.20 / 0.25 / 0.30 / 0.35 · `radius` 3.0 / 3.25 / 3.5 / 3.75 / 4.0 · `damage_percent` 0.30 / 0.40 / 0.50 / 0.60 / 0.75 | `EXPLOSION_MAX_CHAIN` 3, `EXPLOSION_CHAIN_DELAY` 0.12 |
| `reload_shockwave` | `radius` 4.0 / 4.5 / 5.0 / 5.5 / 6.0 · `damage` 20 / 35 / 50 / 65 / 80 | `SHOCKWAVE_COOLDOWN` 3, `SHOCKWAVE_KNOCKBACK` 9 |
| `drone` | `interval` 1.2 / 1.0 / 0.8 / 0.65 / 0.5 · `damage` 12 / 16 / 20 / 24 / 30 | `DRONE_RANGE` 15, `DRONE_HOVER_HEIGHT` 2.4 |
| `speed` | `bonus` 0.08 / 0.16 / 0.24 / 0.32 / 0.40 | – |
| `luck` | `points_bonus` 0.10 / 0.20 / 0.30 / 0.40 / 0.50 · `chest_chance` 0.01 / 0.02 / 0.03 / 0.04 / 0.05 | `LUCK_SHIFT_TO_SILVER` 4, `LUCK_SHIFT_TO_GOLD` 2 |

Feste Schadenswerte (`reload_shockwave.damage`, `drone.damage`) nimmt das Upgrade-Modul mal
`Game.effect_factor()`.

**`upgrade_state.gd`** – eine Instanz je Lauf (`Game.upgrades`).

```gdscript
const MAX_SLOTS := 6
const MAX_LEVEL := 5
func get_level(id: String) -> int
func add_levels(id: String, levels: int) -> int      # neue Stufe; unverändert bei unbekannter ID,
                                                     # levels <= 0 oder neuem Upgrade ohne freien Platz
func owned_ids() -> Array[String]                    # Reihenfolge des Erwerbs
func free_slots() -> int
func is_eligible(id: String) -> bool
func eligible_ids() -> Array[String]                 # in der Reihenfolge von UpgradeDefs.ORDER
func has_synergy(id: String) -> bool                 # Voraussetzungen erfüllt
func check_new_synergies() -> Array[String]          # jede Synergie genau einmal
func active_synergies() -> Array[String]
func value(id: String, key: String) -> float
func points_multiplier() -> float                    # 1.0 + luck.points_bonus
func speed_multiplier() -> float                     # 1.0 + speed.bonus
func bonus_max_hp() -> float
func luck_level() -> int
func chest_chance_bonus() -> float                   # luck.chest_chance
func summary() -> Array[Dictionary]                  # { "id", "name", "level" } je Upgrade
```

**`chest_roller.gd`** – alles `static`.

```gdscript
const KIND_UPGRADE: String = "upgrade"
const KIND_POINTS: String = "points"
const KIND_HEAL: String = "heal"
static func drop_chance(is_elite: bool, upgrades: UpgradeState) -> float      # Elite 1.0, sonst 0.03 + Glück
static func should_drop(rng: RandomNumberGenerator, is_elite: bool, upgrades: UpgradeState) -> bool
static func rarity_weights(is_elite: bool, luck_level: int) -> Array[float]   # Prozent [Bronze, Silber, Gold]
static func roll_rarity(rng: RandomNumberGenerator, is_elite: bool, luck_level: int) -> int
static func levels_for_rarity(rarity: int) -> int                             # 1 / 2 / 3
static func rarity_name(rarity: int) -> String                                # "Bronze" / "Silber" / "Gold"
static func rarity_color(rarity: int) -> Color
static func build_offers(rng: RandomNumberGenerator, upgrades: UpgradeState, rarity: int) -> Array[Dictionary]
static func consolation_offer(index: int) -> Dictionary
static func offer_title(offer: Dictionary) -> String          # Upgrade-Name oder "Trostpreis: ..."
static func offer_level_text(offer: Dictionary) -> String     # "Neu: Stufe 2" / "Stufe 2 → 4" / ""
static func offer_description(offer: Dictionary) -> String    # Wirkungstext der neuen Stufe
```

`build_offers` liefert immer genau 3 Einträge: zuerst bis zu 3 verschiedene, zufällig gezogene wählbare
Upgrades `{ "kind": "upgrade", "id": String, "from_level": int, "to_level": int }`, danach Trostpreise im
Wechsel `{ "kind": "points", "amount": 500 }`, `{ "kind": "heal", "amount": 50 }`, wieder Punkte.
Die Kistenwahl baut ihre Karten aus `offer_title`, `offer_level_text`, `offer_description`,
`rarity_name` und `rarity_color`.

### 13.5 `fx.gd`, genaue Schnittstelle

`extends RefCounted`, nur statische Funktionen. Positionen sind Weltkoordinaten.

```gdscript
const GROUP_FX_ROOT: String = "fx_root"
static func root_of(from: Node) -> Node          # Knoten der Gruppe fx_root, sonst Wurzel, null wenn from ungültig
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color) -> void
static func muzzle_flash(parent: Node3D) -> void                       # Kind von parent (Mündung)
static func lightning(parent: Node, points: PackedVector3Array) -> void
static func explosion(parent: Node, pos: Vector3, radius: float, color: Color) -> void
static func confetti(parent: Node, pos: Vector3) -> void
static func shockwave(parent: Node, pos: Vector3, radius: float) -> void
static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color) -> void
static func hit_flash(mesh: MeshInstance3D, color: Color, duration: float = 0.08) -> void
```

Aufruf: `Fx.tracer(Fx.root_of(self), from, to, farbe)`. Jede Funktion tut nichts, wenn `parent` ungültig
ist oder nicht im Baum hängt (auch `null`), räumt ihren Effekt selbst weg (Tweens am Effekt-Knoten), läuft
headless ohne Fehler und ändert nie den Spielzustand. Obergrenzen halten Kettenreaktionen billig: höchstens
40 Trefferzahlen, 6 Effekt-Lichter und 10 Konfetti-Wolken gleichzeitig. Trefferzahlen sind auf dem
Bildschirm etwa gleich groß (Größe wächst mit dem Abstand zur Kamera, schrumpft in der Nähe). Die
Explosion zeichnet nur die Außenseite ihrer Kugeln, damit sie aus der Nähe nicht das Bild überstrahlt.

Wer welche Effekte auslöst: Leuchtspur und Einschlag-Funke der WeaponController, Mündungsfeuer das
ViewModel, alle Trefferzahlen (auch die der Kugeln) UpgradeEffects und die Drohne, das Aufblitzen eines
getroffenen Zombies der Zombie selbst (eigenes Material, nicht `Fx.hit_flash`).

### 13.6 Schnittstellen der Module

**Spieler** (`player.gd`, `CharacterBody3D`, Gruppe `player`, Lage 2, Maske Lagen 1 + 3 + 6 = `MASK_PLAYER`). Ursprung = Füße.
`_init` baut `Shape`, `Camera`, `Camera/ViewModel` und `WeaponController`, sie sind also schon vor
`add_child` da.

```gdscript
var hp: float
var max_hp: float
var is_dead: bool
func take_damage(amount: float) -> void     # 0,5 s Unverwundbarkeit, player_damaged, player_health_changed, einmal player_died
func heal(amount: float) -> void
func refresh_stats() -> void                # max_hp und Tempo aus Game.upgrades, Zuwachs an max_hp heilt
func get_eye_position() -> Vector3
func get_aim_direction() -> Vector3         # Blickrichtung der Kamera, Einheitsvektor
func get_camera() -> Camera3D
func get_weapon_controller() -> Node
func look_at_point(target: Vector3) -> void # Blick sofort auf einen Weltpunkt (Tests, Skripte), setzt Rückstoß zurück
func get_look_pitch() -> float
func is_sprinting() -> bool
func is_invulnerable() -> bool
```

Der Spieler setzt `Game.player = self` in `_ready`, ruft bei `upgrade_chosen` selbst `refresh_stats()`
und stellt bei `run_started` volles Leben her. Blick-Strahl: Maske `MASK_INTERACT`, Flächen eingeschlossen.
Gilt der getroffene Collider **oder einer seiner Vorfahren** als Interaktionsobjekt (Gruppe
`interactables`, Methoden `get_prompt` und `interact`), sendet der Spieler dessen Hinweis über
`interact_prompt_changed` und ruft bei `interact` (E) `interact(self)`.

- Eingaben wirken nur im State `PLAYING` und solange der Spieler lebt. Der Mausblick läuft in `_input` über
  `InputEventMouseMotion.screen_relative` (unabhängig von der Fenstergröße), Blick nach oben und unten bis
  knapp 88°.
- Bewegung: Beschleunigung `PLAYER_ACCELERATION`, in der Luft mal `PLAYER_AIR_CONTROL`, gemerkter Sprung
  (`PLAYER_JUMP_BUFFER_TIME`) und Sprung kurz nach der Kante (`PLAYER_COYOTE_TIME`). Stufen bis
  `PLAYER_STEP_HEIGHT` läuft er ohne Sprung hoch. Die Bühnenkante (0,4 m) braucht Sprung, Treppe oder Rampe.
  Sprinten geht in jede Richtung und sperrt das Schießen nicht.
- Die Schüsse folgen der echten Kamera (Fadenkreuz = Bildmitte). Der Kamera-Rückstoß
  (`CAMERA_RECOIL_KICK_DEG`) verzieht also wirklich, er klingt mit `CAMERA_RECOIL_RECOVERY` ab.
- Reine Optik: Wackeln bei Treffern, Eintauchen bei der Landung, Schrittwippen, Neigung beim Seitwärtslaufen,
  weiteres Sichtfeld beim Sprinten, Kamera gleitet zwischen den Physik-Schritten, Todeskamera am Boden.

**Waffen** (`weapon_controller.gd`, `Node`, Kind `WeaponController` des Spielers).

```gdscript
func has_weapon(weapon_id: String) -> bool
func give_weapon(weapon_id: String) -> void
func refill_ammo(weapon_id: String) -> void
func get_current_weapon_id() -> String
func get_owned_weapon_ids() -> Array[String]      # in Tastenreihenfolge
func get_state(weapon_id: String) -> WeaponState  # null, wenn nicht im Besitz
func try_fire() -> bool                           # Schuss ohne Eingabe-Prüfung, true wenn geschossen
func start_reload() -> void                       # nur im State PLAYING und solange der Spieler lebt
func switch_to(weapon_id: String) -> void
func is_reloading() -> bool                       # lädt die Waffe in der Hand gerade nach?
```

Sendet `weapon_changed`, `ammo_changed`, `weapon_fired`, `reload_started`, `reload_finished` und je
Treffer `bullet_hit` (nach `take_damage`). Schießt nur im State `PLAYING` und solange der Spieler lebt.
Bei `run_started`: nur noch die Pistole, voll. Das Mausrad (`weapon_next`/`weapon_prev`) kommt nur als
einzelnes Ereignis, deshalb in `_unhandled_input` auswerten. Kopftreffer fragt die Waffe mit
`zombie.is_headshot(trefferpunkt)` ab. `info` eines Kugeltreffers:
`{ "source": "bullet", "headshot": bool, "weapon_id": String, "hit_position": Vector3 }`.

- Schuss: je Kugel ein Strahl vom Auge in Blickrichtung, Streuung gleichmäßig über die Kreisfläche
  (`Game.rng`). Durchschlag aus `Game.upgrades.value("pierce", "targets")`, Schaden je Ziel aus
  `WeaponDefs.bullet_damage`. Sterbende Zombies im Weg verbrauchen keinen Durchschlag, Wände stoppen die Kugel.
- Reihenfolge der Signale eines Schusses: alle `bullet_hit`, dann `weapon_fired`, dann `ammo_changed`,
  bei leerem Magazin zum Schluss `reload_started` (automatisches Nachladen, auch beim Wechsel zu einer
  leeren Waffe).
- Halbautomatische Waffen merken sich einen knapp zu früh gedrückten Abzug (`FIRE_BUFFER_TIME`).
  Automatische Waffen geben bei gehaltenem Abzug in einem langen Bild mehrere Schüsse ab (höchstens
  `FIRE_MAX_SHOTS_PER_FRAME`, jeder mit eigenen Signalen), damit die Schussrate auch bei niedriger
  Bildrate stimmt.
  Schussfolge und Nachladen aller getragenen Waffen laufen weiter, auch wenn sie nicht in der Hand sind.
  Ein Waffenwechsel bricht das Nachladen der alten Waffe ab (ohne `reload_finished`).
- Nach Pause oder Kistenwahl zählt die Eingabe des ersten Bildes nicht, und der Abzug muss erst losgelassen
  werden: Der Klick oder die Taste, die das Menü schloss, schießt nicht und wechselt keine Waffe.
- `refill_ammo` auf eine Waffe, die gerade nachlädt, sendet `reload_finished`. Feuer mit leerem Magazin
  und leerem Vorrat sendet höchstens alle 1,5 s `banner("Munition leer!")`.

**ViewModel** (`view_model.gd`, `Node3D`): `var weapon_id`, `func set_weapon(new_weapon_id: String) -> void`,
`func get_muzzle_position() -> Vector3`, `func get_muzzle_node() -> Node3D`. Hört selbst auf
`weapon_changed`, `weapon_fired`, `reload_started`, `reload_finished`. Drei eckige Waffen mit Händen
(Pistole gelb/schwarz, Pump-Schrotflinte rot/gold, MP türkis/pink), Rückstoß als Feder, Nachlade- und
Wechselpose. Das Modell ist klein (Maßstab 0,3) und sitzt nah an der Kamera, damit es nie in Wände ragt.

**Zombie** (`zombie.gd`, `CharacterBody3D`, Gruppe `zombies`, Lage 3 = `LAYER_ZOMBIES`, Maske Lagen 1 + 2 + 3 = `MASK_ZOMBIE`). Ursprung = Füße.

```gdscript
var zombie_type: String
var max_hp: float
var hp: float
var is_dead: bool
var wave: int
var move_speed: float
var attack_damage: float
var body_height: float      # Balance.ZOMBIE_HEIGHT * scale (Elite 1,3)
var body_radius: float
func setup(type: String, wave_number: int) -> void          # vor add_child
func take_damage(amount: float, info: Dictionary) -> void
func apply_burn(dps: float, duration: float) -> void        # dps = Lebenspunkte je Sekunde, fertig gerechnet
func apply_knockback(impulse: Vector3) -> void              # Geschwindigkeit in m/s, klingt ab
func is_burning() -> bool
func is_headshot(hit_position: Vector3) -> bool
func get_center_position() -> Vector3
func get_head_position() -> Vector3                         # Kopfmitte, liegt sicher im Kopftreffer-Bereich
func get_burn_dps(dps_percent: float) -> float              # Anteil am Maximal-Leben -> dps, Elite mal BURN_ELITE_FACTOR
func get_attack_range() -> float                            # ZOMBIE_ATTACK_RANGE + zusätzlicher Körperradius (Elite)
func is_winding_up() -> bool
func teleport_to(world_position: Vector3) -> void           # versetzen und anhalten (Rettung, Tests)
func despawn() -> void                                      # sofort weg ohne zombie_killed, Punkte und Kiste
```

- Knoten: `Shape`, `Body` (Rumpf, trägt `Head`, `ArmL`, `ArmR`, `Flames`), `NavAgent`, bei der Elite
  dazu `Glow` und `HealthBar`. Die Elite trägt eine Krone und einen Lebensbalken.
- Bewegung: Der `NavigationAgent3D` berechnet alle `ZOMBIE_REPATH_INTERVAL` s nur den Pfad. Abgelaufen wird
  er vom Zombie selbst, Punkt für Punkt (ein Punkt gilt bei 0,2 m waagerechtem Abstand als erreicht). So
  schneidet er an Türöffnungen und Kulissen keine Ecke. Ohne Navigationsnetz oder Pfad läuft er geradeaus
  auf den Spieler zu. Niedrige Kanten bis `ZOMBIE_HOP_PROBE_HEIGHTS` (Bühne) überspringt er.
- Angriff: in Reichweite `get_attack_range()` holt er `ZOMBIE_ATTACK_WINDUP` s sichtbar aus (Arme über den
  Kopf) und rückt dabei mit `ZOMBIE_ATTACK_WINDUP_SPEED_FACTOR` nach. Der Schlag trifft, wenn der Spieler
  dann noch näher als Reichweite + `ZOMBIE_ATTACK_HIT_RANGE_BONUS` und höchstens eine Körperhöhe darüber
  oder darunter steht. Wegtreten weicht also aus. Danach `ZOMBIE_ATTACK_COOLDOWN` Pause.
- Kein Schlag durch Wände: Ausholen und Treffer brauchen freie Bahn zum Spieler. Geprüft wird in
  Schlagweite mit zwei Strahlen gegen die Welt (`MASK_LINE_OF_SIGHT`): Körpermitte zu Körpermitte und Kopf
  zu Augen. Ist einer frei, gilt die Bahn als frei. Eine Wand oder Kulisse schützt also, eine hüfthohe
  Deckung nicht. Tritt der Spieler während des Ausholens hinter eine Wand, geht der Schlag ins Leere.
  Der Zombie bleibt in der Stopp-Reichweite (`ZOMBIE_ATTACK_STOP_RANGE_FACTOR`) nur stehen, wenn die Bahn
  frei ist. Sonst folgt er weiter dem Pfad um das Hindernis herum, statt hinter der Wand zu parken.
- Rückstoß: klingt linear mit `ZOMBIE_KNOCKBACK_DAMPING` ab, hebt den Zombie kurz an
  (`ZOMBIE_KNOCKBACK_LIFT_*`), und über `ZOMBIE_STAGGER_KNOCKBACK_SPEED` kann er nicht laufen.
- `apply_burn` erneuert einen laufenden Brand mit `max(Rest, Dauer)` und dem höheren dps. Über die ganze
  Dauer fällt genau dps × Dauer an (ein Rest zwischen zwei Ticks kommt anteilig).
- `take_damage` sendet `zombie_damaged(self, amount, info)` mit dem **unveränderten** Betrag, auch beim
  tödlichen Treffer. Tote Zombies und Beträge <= 0 werden ignoriert.
- Tod: `is_dead = true`, raus aus der Gruppe `zombies`, Kollision aus, dann `zombie_killed(self, info)`,
  nach `Balance.ZOMBIE_DEATH_TIME` `queue_free()`. In `zombie_killed` ist der Knoten noch gültig (Position,
  `max_hp`, `zombie_type` lesbar).
- Brand: `apply_burn` bekommt Schaden je Sekunde in Lebenspunkten. Das Upgrade-Modul rechnet
  `dps_percent * zombie.max_hp`, bei Elite mal `BURN_ELITE_FACTOR`. Der Zombie tickt alle
  `BURN_TICK_INTERVAL` s über `take_damage(..., {"source": "burn"})`.

**ZombieSpawner** (`zombie_spawner.gd`, `Node`): `var zombie_parent: Node3D`,
`func spawn(type: String, wave: int) -> Node3D` (sendet `zombie_spawned`, `null` wenn der Spawner nicht im
Baum hängt), `func get_active_spawns() -> Array[Marker3D]`, `func alive_count() -> int`,
`func pick_spawn() -> Marker3D`, `func get_last_spawn() -> Marker3D`.
Ein Spawnpunkt ist aktiv, wenn sein Meta `active` wahr ist oder fehlt. Wahl des Punkts: nie derselbe
zweimal hintereinander, Punkte näher als `SPAWN_MIN_PLAYER_DISTANCE` am Spieler werden gemieden, unter
den übrigen zufällig (`Game.rng`), nähere etwas häufiger (Gewicht `1 / (SPAWN_WEIGHT_OFFSET + Abstand)`).
Der Zombie erscheint bis `SPAWN_JITTER` neben dem Punkt und schaut gleich zum Spieler.

**WaveManager** (`wave_manager.gd`, `Node`): `var auto_start: bool = true`, `var spawner: Node`,
`var current_wave: int`, `var zombies_left: int`, `var is_wave_active: bool`,
`func start_wave(n: int) -> void`, `func get_countdown() -> float`,
`func get_wave_banner(wave: int) -> String`, `func get_queued_count() -> int`,
`func get_wave_alive_count() -> int`.

- `run_started` → Countdown `FIRST_WAVE_DELAY` → `start_wave(1)` → Wellenende → `wave_cleared`,
  `Game.player.heal(WAVE_END_HEAL)` → Countdown `INTERMISSION_SECONDS` → nächste Welle.
- `auto_start = false` hält den Countdown an (keine Welle beginnt von selbst). Es darf jederzeit gesetzt
  werden, auch nach `run_started`. Eine mit `start_wave(n)` begonnene Welle läuft normal bis `wave_cleared`.
- `intermission_tick(seconds_left)` kommt bei jedem Wechsel der vollen Sekunde, auch vor der ersten Welle.
  `intermission_tick(0)` heißt: Countdown vorbei, die Welle beginnt.
- `start_wave` sendet `wave_started(n, total)`, `zombies_left_changed(total)` und das Banner der Welle.
  Es beginnt immer mit „Welle n“ und trägt einen Spruch im Showton („Welle 3 – Jetzt wird gerannt!“,
  `get_wave_banner`). Läuft noch eine Welle, wird sie abgebrochen: Ihre Zombies bleiben, verlieren Meta
  `wave_spawn` und zählen nicht mehr.
- Weitere Banner: am Wellenende „Welle n überstanden! +25 Leben“, beim Erscheinen einer Elite
  „Stargast im Anmarsch – mit Geschenk!“.
- Gezählt werden nur Zombies, die der WaveManager selbst erzeugt hat (Meta `wave_spawn` = true).
- Höchstens `MAX_ZOMBIES_ALIVE` leben gleichzeitig. Ist die Grenze erreicht, kommt je frei gewordenem Platz
  genau einer nach.
- Sicherung gegen eine Welle, die nie endet (einmal je Sekunde): Ein aus der Welt gefallener Zombie
  (`ZOMBIE_OUT_OF_WORLD_Y`) kommt sofort an einen Spawnpunkt zurück. Wer `ZOMBIE_STUCK_SECONDS` lang weder
  vorankommt noch beim Spieler steht noch Schaden nimmt, wird an einen anderen Spawnpunkt gesetzt, nach
  `ZOMBIE_STUCK_MAX_RESCUES` Versuchen verschwindet er ohne Belohnung und zählt als erledigt. Stimmt die
  Zahl nicht mehr (Zombie ohne `zombie_killed` entfernt), wird sie berichtigt.
- Bei `game_over` stoppen Spawns, Countdown und Zählung.

**UpgradeEffects** (`upgrade_effects.gd`, `Node`): `var drone: Node3D`. Hört auf `bullet_hit`,
`zombie_damaged`, `zombie_killed`, `reload_started`, `weapon_fired`, `upgrade_chosen`, `synergy_unlocked`,
`run_started`. Maximal-Leben und Tempo setzt der Spieler selbst, Punkte-Faktor `Game`, Kistenglück der
ChestDropper. Zusätzlich: `func tick(delta: float) -> void` (läuft je Physik-Schritt),
`get_shockwave_cooldown_left()`, `get_pending_explosion_count()`, `get_lifesteal_budget_left()`,
`get_lightning_procs_this_shot()`.

- Kettenblitz: Der von der Kugel getroffene Zombie bekommt keinen Blitzschaden. Jeder Sprung geht zum
  nächsten noch nicht getroffenen Zombie im Umkreis `CHAIN_RADIUS` um den zuletzt getroffenen (Mitte zu
  Mitte). Auch ein tödlicher Kugeltreffer startet die Kette. Gewitterfront: sicherer Blitz, höchstens
  `STORM_FRONT_MAX_PROCS_PER_SHOT` je Schuss (der Zähler beginnt bei jedem `weapon_fired` neu, es zählt
  nur ein Blitz, der wirklich überspringt).
- Brand: `dps_percent × max_hp`, bei Elite mal `BURN_ELITE_FACTOR`, über `zombie.apply_burn`.
- Lebensraub: Anteil des Betrags aus `zombie_damaged` (auch Überschaden), höchstens
  `LIFESTEAL_MAX_PER_SECOND` je Fenster von `LIFESTEAL_WINDOW` s, das mit der ersten Heilung beginnt.
  Bei vollem Leben verfällt nichts vom Kontingent, und es beginnt auch kein Fenster: Erst eine Heilung,
  die wirklich ankommt, startet es. So sind nie mehr als 15 Leben in einer Sekunde möglich.
- Konfetti-Explosion: wird in `zombie_killed` nur vorgemerkt und im nächsten Physik-Schritt gezündet
  (Folgeexplosionen nach `EXPLOSION_CHAIN_DELAY`). Trifft Zombies, deren Mitte im Radius liegt und die
  freie Sichtlinie haben. Der Spieler nimmt keinen Schaden.
- Druckwelle: Die Abklingzeit beginnt nur, wenn die Welle mindestens einen Zombie getroffen hat.
- Trefferzahlen: UpgradeEffects zeigt sie für Kugeln (weiß, Kopftreffer gelb), Blitz, Explosion und
  Druckwelle, die Drohne für ihre Schüsse. Brand-Ticks zeigen keine Zahl.
- Bei `upgrade_chosen` gibt es Konfetti vor dem Spieler, bei `synergy_unlocked` Blitze rund um ihn.

**Drone** (`drone.gd`, `Node3D`, Knoten `Drone` unter `Main/Fx`): `var level: int`,
`func set_level(new_level: int) -> void`, `var show_damage_numbers: bool`, `func try_fire() -> bool`,
`func find_target() -> Node3D`, `func get_fire_interval() -> float`, `func get_shot_damage() -> float`,
`func get_muzzle_position() -> Vector3`. Eine fliegende TV-Kamera, die schräg rechts vor dem Spieler
schwebt (2,6 m vorn, 2,0 m rechts, `DRONE_HOVER_HEIGHT`), nicht in Wände fliegt und im Takt ihrer Stufe
auf den nächsten Zombie mit freier Sichtlinie in `DRONE_RANGE` (von der Drohne gemessen) schießt.

**Chest** (`chest.gd`, `Area3D`, Gruppe `chests`, Lage 4 = `LAYER_PICKUPS`, Maske Lage 2 = `MASK_CHEST`): `var rarity: int`,
`var is_collected: bool`, `func setup(chest_rarity: int) -> void` (vor `add_child`),
`func collect() -> void`. `collect` ruft `Game.open_chest(rarity)` und entfernt die Kiste. Es wirkt nur
einmal und nur im State `PLAYING` (sonst bleibt die Kiste liegen). Die Kiste fragt in jedem Physik-Schritt
ab, ob der Spieler in ihr steht (kein `body_entered`). Eine liegen gebliebene Kiste wartet nach einer
anderen Kistenwahl `CHEST_REOPEN_GRACE` s. Aussehen: schwebende, drehende Truhe in der Farbe der
Seltenheit mit „?“, Lichtsäule, Bodenring, Licht und Funken. Knoten `Body` ist die Truhe.

**ChestDropper** (`chest_dropper.gd`, `Node`): `var chest_parent: Node3D`,
`func spawn_chest(position: Vector3, rarity: int) -> Node3D` (sendet `chest_dropped`),
`func find_drop_spot(position: Vector3) -> Vector3`. Die sichere Kiste
der Welle 1 erkennt der ChestDropper selbst: Er merkt sich `total_zombies` aus `wave_started` und zählt
`zombie_killed` mit (nur Zombies mit Meta `wave_spawn`), unabhängig von der Reihenfolge der Empfänger.
Als Netz darunter fällt sie spätestens bei `wave_cleared(1)` am Ort des letzten Kills. Es gibt sie je Lauf
einmal. `spawn_chest` setzt die Kiste auf den Boden und, wenn sie weiter als `CHEST_NAV_SNAP_TOLERANCE`
neben dem Navigationsnetz läge, auf das Netz. Kisten von Zombies halten `CHEST_SPACING` Abstand
zueinander. Zu jeder Kiste von einem Zombie gibt es eine kleine Explosion und Konfetti. Das Banner
dazu zeigt das HUD.

**LevelBuilder** (`level_builder.gd`, `RefCounted`): `func build(parent: Node3D) -> Dictionary` mit
`{ "player_spawn": Vector3, "nav_region": NavigationRegion3D, "door": Node3D }`. `player_spawn` sind die
Füße des Spielers in Weltkoordinaten. Der Builder wird nach `build` verworfen. Spawnpunkte: Marker3D in
Gruppe `zombie_spawns` mit Meta `zone` (int) und Meta `active` (bool, Zone 2 anfangs `false`).
Knotennamen unter `Level`: `NavRegion`, `Door`, `WallBuy_shotgun`, `WallBuy_smg`, dazu `Show`,
`Environment`, `Lights`, `Zone1`, `Zone2`, `Audience`, `Entrances` (darin `Entrance_A` bis `Entrance_E`
mit den Markern `Spawn_A` bis `Spawn_E`).

- Grundriss (+X rechts, +Z zum Publikum, der Spieler schaut anfangs nach −Z): Zone 1 „Bühne“ x −11..11,
  z −9..9. Die Bühne (0,4 m) liegt an der Rückwand, davor die Showtreppe, links und rechts je eine Rampe.
  Publikum hinter einer Brüstung bei z = 9 (Deko, für den Spieler gesperrt). Zone 2 „Backstage“ liegt
  **östlich** davon (x 11,4..25,4, z −3..9) hinter der Tür in der Ostwand bei z = 4.
  `player_spawn` = (0, 0, 5).
- Zombie-Eingänge: A Showtor in der Rückwand auf Bühnenhöhe, B Westwand, C Ostwand (Zone 1), D Nordwand,
  E Ostwand (Zone 2). Jeder ist ein 4,5 m langer Gang mit Spawnpunkt, Warnlampe und einer Sperre auf Lage 6
  (Gruppe `player_block`): Der Spieler kommt nicht hinein, Zombies und Schüsse kommen hindurch.
- Wandkäufe: Schrotflinte an der Rückwand links der Bühne, MP an der Südwand im Backstage.
- Navigation: eine `NavigationRegion3D`, zur Laufzeit synchron gebacken aus den Kollisionen der Gruppe
  `nav_source` mit `NavigationServer3D.parse_source_geometry_data` und `bake_from_source_geometry_data`
  (wenige Millisekunden). Agentenradius 0,5 m und -höhe 2,5 m (passt für die Elite), Zellgröße 0,25 m.
  Nach dem Backen werden die Punkte um eine Zellhöhe nach unten geschoben, weil Godot 4.7 das Netz sonst
  über der Oberfläche ablegt. Die Karte beantwortet Pfad-Abfragen erst einige Physik-Schritte nach `build`.
- Knoten `Show` (innere Klasse `StudioShow`): bewegt die vier Bühnenscheinwerfer, lässt Lampen blinken
  und das Publikum bei Kills und Wellenbeginn jubeln (Schild „APPLAUS“), backt das Netz
  (`func bake() -> bool`) und lässt eine Kiste, die tiefer als 0,6 m in einem Zombie-Gang landet, vor die
  Öffnung rutschen (hört auf `chest_dropped`).
- Licht: warmes Hauptlicht für Zone 1, kühleres und dunkleres für den Backstage (dessen Geometrie liegt
  auf Render-Ebene 2). Kein Licht wirft Schatten.

**Door** (`door.gd`, `StaticBody3D`, Lagen 1 + 5, Gruppe `interactables`, nicht `nav_source`):
`signal opened`, `var is_open: bool`, `var cost: int`, `var zone: int`, `var zone_name: String`,
`var size: Vector3`, `func get_prompt() -> String`, `func interact(player: Node3D) -> void` (bezahlt mit
`Game.spend_points(cost)`, dann `open()`), `func open() -> void` (gratis, wirkt einmal: Kollision weg,
Türblatt fährt hoch, Meta `active = true` an allen Spawnpunkten ihrer Zone, raus aus `interactables`,
`opened`, Banner „Backstage ist offen!“), `func close() -> void` (macht all das rückgängig, läuft bei
`run_started`). Hinweis: „E – Backstage öffnen (750)“, ohne genug Punkte „Backstage (750) – dir fehlen
320 Punkte“. Ein Kaufversuch ohne Punkte gibt das Banner „Nicht genug Punkte! Dir fehlen N.“ und die Tür
rüttelt. Eine Lampe im Türblatt ist grün, sobald die Punkte reichen.

**WallBuy** (`wall_buy.gd`, `StaticBody3D`, Lage 5 = `LAYER_INTERACTABLES`, Gruppe `interactables`): `var weapon_id: String`,
`func setup(new_weapon_id: String) -> void` (vor `add_child`), `func get_prompt() -> String`,
`func interact(player: Node3D) -> void`. Erster Kauf: `price`, dann `give_weapon`. Danach: `ammo_price`,
dann `refill_ammo`. Sind Magazin und Vorrat voll, kostet ein weiterer Kauf nichts und ändert nichts.
Hinweise: „E – Publikumsjoker kaufen (500)“, „E – Munition für Publikumsjoker (250)“,
„Publikumsjoker: Munition ist voll“, ohne genug Punkte „Publikumsjoker (500) – dir fehlen 120 Punkte“.
Banner: „Publikumsjoker gekauft!“, „Munition aufgefüllt!“, „Munition ist schon voll!“,
„Nicht genug Punkte! Dir fehlen N.“. Die Tafel zeigt Namen, Umriss der Waffe und den Preis (nach dem
Kauf den Munitionspreis).

**Oberfläche** (alle `CanvasLayer`; Kistenwahl, Pausemenü und Game Over mit `PROCESS_MODE_ALWAYS`):

- `hud.gd`: Ebene 1, liest nur Events, `UpgradeDefs`, `WeaponDefs`, `Game` (und bei `run_started` Leben,
  Waffe und Munition vom Spieler). `func show_banner(text: String, dedupe_key: String = "") -> void`,
  `func is_banner_active() -> bool`, `func get_banner_queue_size() -> int`.
  - Banner laufen nacheinander (höchstens 5 warten), gleiche Meldungen innerhalb von 3 s nur einmal.
    Mit `dedupe_key` gilt auch eine fremde Meldung als gleich, deren Text den Schlüssel enthält. Zwei
    Meldungen mit demselben Schlüssel und verschiedenem Text laufen beide.
    Zu lange Texte werden kleiner gesetzt und notfalls mit „...“ gekürzt. Solange ein Menü offen ist
    (State nicht `PLAYING`), ist die Banner-Plakette ausgeblendet.
  - Das HUD meldet selbst: „Synergie: Gewitterfront!“ bei `synergy_unlocked` und „Gold-Kiste gefallen!“
    bei `chest_dropped`. Kein anderes Modul meldet Kisten oder Synergien per Banner. Jede Kiste wird
    gemeldet: Fallen kurz nacheinander eine Bronze- und eine Gold-Kiste, laufen beide Banner. Nur dieselbe
    Meldung (gleiche Seltenheit) entfällt innerhalb von 3 s.
  - Schnelle Punktgewinne laufen zu einer wachsenden „+N“-Zahl zusammen. Der Treffermarker zeigt Treffer,
    Kopftreffer und Kills verschieden. Bei wenig Leben (ab 30 %) pulsiert die Zahl, und der Bildrand
    bleibt rot (die Bildmitte bleibt frei). Bei fast leerem Magazin (ab 30 %) steht dort
    „WENIG MUNITION“, bei leerem „NACHLADEN [R]“ in der Bildmitte.
  - Der gemeinsame Stil der vier Bildschirme (Farben, Schrift, Plaketten, Knöpfe, Upgrade-Symbole) liegt
    als statische Hilfen und innere Klassen in `hud.gd`. Die anderen binden ihn mit
    `const UiStyle := preload("res://scripts/ui/hud.gd")` ein.
- `chest_choice.gd`: Ebene 10. `var offers: Array`, `var rarity: int`, `var cards: Array[Control]`,
  `func show_offers(chest_rarity: int, chest_offers: Array) -> void`, `func is_open() -> bool`,
  `func choose(index: int) -> void` (schließt sofort und ruft `Game.choose_offer(index)`),
  `func close() -> void`, `func request_choice(index: int, held_action: String = "") -> bool`,
  `func is_input_locked() -> bool`, `func is_click_locked() -> bool`,
  `func get_pointer_rest_position() -> Vector2`. Öffnet bei `chest_opened`. Tasten: Aktionen `weapon_1`
  bis `weapon_3`. Tasten und Klicks gehen über `request_choice`: 0,4 s Sperre nach dem Öffnen, kurze
  Bestätigung, dann wartet die Wahl, bis die Taste losgelassen ist. Schutz vor dem blinden Klick aus dem
  Gefecht (nach dem gefangenen Modus steht der Zeiger in der Bildmitte, also auf der mittleren Karte):
  Beim Öffnen setzt die Wahl den Zeiger auf die Hinweiszeile unter den Karten
  (`get_pointer_rest_position`, nur mit echtem Bildschirm), und Mausklicks zählen erst 0,8 s nach dem
  Öffnen (`CLICK_LOCK_SECONDS`, `is_click_locked`). Karten: Taste, Symbol, Name, „NEU · Stufe 2“ oder
  „Stufe 2 → 4“, Stufenpunkte, Wirkungstext der neuen Stufe (aus `ChestRoller.offer_description`, Zahl
  und Einheit mit geschütztem Leerzeichen). Trostpreise haben eine eigene Karte („TROSTPREIS“).
  Ohne Angebote bleibt die Wahl geschlossen.
- `pause_menu.gd`: Ebene 20. `func open() -> void`, `func resume() -> void`, `func is_open() -> bool`.
  Die Aktion `pause` schaltet zwischen `PLAYING` und `PAUSED`. Knöpfe: Weiter → `resume()`, Neustart →
  `Game.restart_run()`, Beenden → `Game.quit_game()`. Darunter steht die Tastenbelegung.
- `game_over.gd`: Ebene 30. `var stats: Dictionary`, `func show_stats(run_stats: Dictionary) -> void`,
  `func is_open() -> bool`, `func close() -> void`, `func request_restart() -> bool`,
  `func is_input_locked() -> bool`. Öffnet bei `game_over`. Knöpfe und die Taste R (Neustart) sind die
  ersten 0,6 s gesperrt.

### 13.7 Tests schreiben

- `extends SceneTree`, Fehler zählen, deutsche Meldungen mit `FEHLER:` über `printerr`, am Ende
  `quit(1 if _failures > 0 else 0)`. `run_tests.ps1` führt zuerst `check_scripts.gd` und dann alle
  `tests/test_*.gd` aus.
- **Autoloads in `-s`-Skripten:** Die Namen `Game` und `Events` kennt Godot erst, **nachdem** das Testskript
  übersetzt und `_init` gelaufen ist. Daraus folgt:
  - Im Testskript selbst nie `Game` oder `Events` schreiben, sondern `root.get_node("Game")`.
  - Skripte, die `Game` oder `Events` benutzen (alles unter `scripts/game` und `scripts/ui`), im Test nicht
    per `preload` einbinden, sondern zur Laufzeit mit `load(...)`, frühestens in `_initialize()`.
    Core-Skripte dürfen per `preload` rein.
  - In `_initialize()` hängen die Autoloads zwar an der Wurzel, ihr `_ready` ist aber noch nicht gelaufen.
    Erst ein Bild warten: `func _initialize() -> void: _run()` und in `_run()` als Erstes
    `await process_frame`.
- Spiel im Test starten:
  `var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()`,
  `main.set("run_seed", 7)`, `root.add_child(main)`, `current_scene = main` (damit `restart_run` die Szene
  neu laden kann), dann einige Bilder warten. Für feste Zeitschritte Godot mit `--fixed-fps 60` starten
  (headless läuft sonst in Echtzeit und 300 Bilder sind dann nur etwa zwei Sekunden).
- **Zeitraffer im Test:** `Engine.time_scale` allein streckt den Zeitschritt der Physik (bei 10 wären das
  Schritte von 1/6 s). Deshalb zugleich `Engine.physics_ticks_per_second = 60 * time_scale` setzen: Dann
  rechnet die Physik weiter in Schritten von 1/60 s Spielzeit. So macht es `test_smoke_game.gd` (Faktor 6).
- **Freigegebene Knoten:** Ein schon freigegebenes Objekt darf nie an einen typisierten Parameter, in eine
  typisierte Variable oder als Bindung in ein Lambda gehen (Laufzeitfehler bzw. `ERROR:`-Zeile). In Tests
  die Instanz-ID merken (`get_instance_id`, `is_instance_id_valid`). Wer `Game.player` weiterreicht, prüft
  vorher `is_instance_valid`.
- Ohne echte Eingabe steuern: `main.wave_manager.auto_start = false`, `main.wave_manager.start_wave(n)`,
  `main.spawner.spawn(type, wave)`, `weapon_controller.try_fire()`, `start_reload()`, `switch_to(id)`,
  `main.chest_dropper.spawn_chest(position, rarity)`, `chest.collect()`, `main.chest_choice.choose(index)`
  oder `Game.choose_offer(index)`, `door.open()`, `wall_buy.interact(player)`, `Game.add_points(n)`.
  Echte Tasten gehen mit `Input.parse_input_event(...)` und `physical_keycode`.

### 13.8 Entscheidungen, die der Vertrag offen ließ

1. **Wo die Zahlen stehen:** Die Waffentabelle steht in `weapon_defs.gd`, die Stufenwerte der Upgrades in
   `upgrade_defs.gd` (so benennt sie Abschnitt 8). Alle übrigen Zahlen stehen in `balance.gd`.
2. **Neu festgelegte Zahlen** (in `balance.gd` mit „Vom Vertrag offen gelassen“ markiert):
   `HEADSHOT_HEIGHT_RATIO` 0.78, `EXPLOSION_MAX_CHAIN` 3, `EXPLOSION_CHAIN_DELAY` 0.12 s,
   `BURN_TICK_INTERVAL` 0.5 s, `SHOCKWAVE_KNOCKBACK` 9 m/s, `DRONE_HOVER_HEIGHT` 2.4 m, `PLAYER_HEIGHT` 1.8,
   `PLAYER_RADIUS` 0.35, `MOUSE_SENSITIVITY` 0.0025, `PLAYER_ACCELERATION` 40, `ZOMBIE_HEIGHT` 1.8,
   `ZOMBIE_RADIUS` 0.35, `ZOMBIE_DEATH_TIME` 0.35 s, `ZOMBIE_SEPARATION_RADIUS` 0.9,
   `ZOMBIE_SEPARATION_STRENGTH` 1.5, `ZOMBIE_KNOCKBACK_DAMPING` 6, `CHEST_PICKUP_RADIUS` 0.9,
   `SPAWN_FALLBACK_DISTANCE` 12, Farben der Zombie-Typen und der Seltenheiten.
3. **Lebens-Faktor nach Welle 10:** Faktor von Welle 10 (2,08) mal 1,1 je weiterer Welle. Welle 11 = 2,288,
   Welle 12 = 2,5168. Der lineare Teil wächst nach Welle 10 nicht weiter.
4. **Sprinter-Zahl:** Anteil von `6 + 4 * wave`, ab ,5 aufgerundet (Welle 3: 4, Welle 6: 11).
5. **Reihenfolge einer Welle** ist fest (kein Zufall): Sprinter gleichmäßig gestreut, Elite gleichmäßig
   verteilt, nie als Erste.
6. **Durchschlag:** „je weiterem Ziel −15 %“ ist multiplikativ (85 %, 72,25 %, 61,4 % ...).
7. **Trostpreise:** Reihenfolge Punkte, Heilung, Punkte. Punkte kommen ohne Punkte-Faktor aufs Konto.
8. **`stats["points"]`** sind die insgesamt verdienten Punkte. Zusätzlicher Schlüssel `synergies`.
9. **Zombie-Tod:** Der Zombie verlässt die Gruppe `zombies` sofort. `zombie_damaged` trägt den
   unveränderten Betrag (auch Überschaden).
10. **Spawnpunkte** tragen Meta `active`. Die Tür schaltet sie beim Öffnen frei.
11. **Sichere Kiste der Welle 1:** Der ChestDropper zählt selbst mit (siehe 13.6).
12. **Ursprung von Spieler und Zombie** sind die Füße. `player_spawn` und Spawnpunkte liegen auf Bodenhöhe.
13. **`refresh_stats`** ruft der Spieler selbst bei `upgrade_chosen`. Ein Zuwachs an Maximal-Leben heilt.
14. **`Game`** hat zusätzlich `current_offers`, `current_rarity`, `get_stats`, `restart_run`, `quit_game`,
    `is_playing`, `effect_factor`.
15. **Zusätzliche Schnittstellen der Module:** `player.is_dead`, `get_aim_direction`, `get_camera`;
    `zombie.is_headshot`, `get_center_position`, `is_burning`, `wave`, `move_speed`, `attack_damage`,
    `body_height`, `body_radius`; `weapon_controller.get_state`, `get_owned_weapon_ids`;
    `zombie_spawner.get_active_spawns`, `alive_count`; `wave_manager.get_countdown`; `door.cost`, `zone`,
    `zone_name`, `size`; die Funktionen der Oberfläche in 13.6; `Fx.root_of`, `Fx.hit_flash`.
16. **Eingaben** in `project.godot` gelten für alle Geräte (`device` -1). Godot 4.7 legt neue Ereignisse
    sonst mit Gerät 16 (Tastatur) bzw. 32 (Maus) an, sie würden dann nur dafür gelten.
17. **Physik:** In `project.godot` ist keine 3D-Physik-Engine festgelegt (Voreinstellung von Godot).
18. **`run_tests.ps1`** prüft zuerst alle Skripte (`check_scripts.gd`), dann die Tests. Beide `.ps1` sind
    als UTF-8 mit BOM gespeichert, damit PowerShell 5.1 die Umlaute richtig liest.
19. **Schussfolge:** `WeaponState` rechnet den Rest eines Zeitschritts an, bei langen Bildern fallen
    mehrere Schüsse je Bild, höchstens `FIRE_MAX_SHOTS_PER_FRAME` (siehe 13.4).
20. **Treffer-Punkte der Schrotflinte:** 10 Punkte je Kugel, die trifft (bis zu 80 je Schuss). Das folgt
    aus „Kugeltreffer 10“ und ist beim Ausbalancieren zu prüfen.
21. **Lage 6 `player_block`** und `MASK_PLAYER` 37: nur der Spieler stößt an die Sperren der Zombie-Gänge
    und des Publikums.
22. **Wer was meldet:** Wellen, Wellenende und Elite der WaveManager, Kisten und Synergien das HUD, Tür und
    Wandkauf sich selbst, leere Munition der WeaponController.
23. **Neuer Lauf in derselben Szene:** `main.gd` stellt den Spieler auf den Startpunkt, die Tür schließt
    sich (`door.close()`).

## 14. Abweichungen und offene Punkte

### 14.1 Bewusste Abweichungen von den Abschnitten 1 bis 12

- **Lage 6** für Sperren nur gegen den Spieler (Abschnitt 4 kannte fünf Lagen).
- **Wellen-Banner** tragen einen Spruch („Welle 3 – Jetzt wird gerannt!“) statt nur „Welle n“. Dazu kommen
  Banner zum Wellenende und zur Elite. Abschnitt 1 schloss Moderator-Sprüche aus, gemeint war eine
  Moderator-Figur mit Ton. Die Texte sind fest je Welle, ohne Zufall.
- **Zombies laufen den Pfad selbst ab** (der `NavigationAgent3D` berechnet ihn nur) und springen über
  niedrige Kanten. Abschnitt 10 nannte nur den Agenten.
- **Navigationsnetz** wird über den `NavigationServer3D` gebacken und danach um eine Zellhöhe abgesenkt,
  nicht mit `NavigationRegion3D.bake_navigation_mesh` (Grund in 13.6, Level).
- **Backstage liegt östlich** der Bühne, nicht dahinter. Spawn A liegt auf Bühnenhöhe.
- **Spieler:** Stufen bis 0,3 m ohne Sprung, gemerkter Sprung, Sprung kurz nach der Kante, Kamera-Rückstoß,
  der wirklich verzieht. Mausblick in `_input` statt `_unhandled_input`.
- **Druckwelle:** Die Abklingzeit beginnt nur bei einem Treffer. **Kettenblitz:** Der getroffene Zombie
  selbst bekommt keinen Blitz. **Lebensraub:** festes Fenster von 1 s ab der ersten Heilung.
- **Wandkauf:** Volle Munition kostet nichts. Die Hinweise nennen ohne genug Punkte den Fehlbetrag.
- **Kistenwahl:** neue Upgrades zeigen „NEU · Stufe N“ statt „Neu: Stufe N“, Trostpreise eine eigene Karte.
  Klicks zählen erst 0,8 s nach dem Öffnen, der Mauszeiger wird beim Öffnen unter die Karten gesetzt.
- **Zombie-Angriff:** braucht außer Reichweite und Höhe auch freie Bahn zum Spieler (kein Schlag durch
  Wände). Abschnitt 8 nannte nur die Reichweite.
- **Kiste im Zombie-Gang:** Das Level schiebt sie vor die Öffnung, damit der Spieler sie erreicht.
- **Anzeige-Schwellen** stehen als Konstanten in `hud.gd` (wenig Munition, wenig Leben, roter Rand). Sie
  ändern keine Spielregel.

### 14.2 Stand der Prüfung

- `check_scripts.gd`, alle `tests/test_*.gd` (12 Dateien mit dem Gesamttest) und ein Lauf von
  `capture_game.gd` laufen ohne Fehlerzeile durch.
- Die Bilder aus `capture_game.gd` (14 Stück, 1280×720) wurden durchgesehen. Dabei behoben: riesige
  Trefferzahlen aus der Nähe, weiß überstrahlende Explosion, Drohne über der Punkte-Anzeige, roter
  Schleier über dem ganzen Bild bei wenig Leben, HUD-Banner hinter Menü-Überschriften, getrennte Zahl
  und Einheit auf den Karten, ganz weißer Zombie unter Dauerfeuer.
- Nach der Durchsicht durch zwei Prüfer behoben, jeweils mit eigenem Test: Zombies schlugen durch Wände
  (ein Sprinter parkte hinter der Wand zum Backstage), ein zweites Kisten-Banner innerhalb von 3 s
  entfiel auch bei anderer Seltenheit, das Zeitfenster des Lebensraubs begann schon bei vollem Leben
  (30 Leben in 0,15 s möglich), schnelles Klicken aus dem Gefecht wählte blind die mittlere Karte,
  Dauerfeuer gab höchstens einen Schuss je Bild ab (unter 12 Bildern je Sekunde fehlte der MP Schussrate).
- Der gesetzte Mauszeiger der Kistenwahl ist nur mit einem Wegwerf-Skript im echten Fenster geprüft
  (Zeiger steht nach dem gefangenen Modus bei 640 × 360, nach dem Setzen auf der Hinweiszeile), nicht von
  Hand im Spiel.
- **Niemand hat das Spiel bisher mit Maus und Tastatur gespielt.** Spielgefühl (Rückstoß, Wackeln,
  Mausempfindlichkeit, Sprung) und Schwierigkeit sind ungeprüft.

### 14.3 Balance (gemessen, nicht geändert)

- **Rechnung Pistole (nur Körpertreffer):** Welle 1 braucht 30 Schuss, Welle 2 60, Welle 3 70, Welle 4 102.
  Mit Nachladen sind das etwa 9 / 18 / 21 / 32 s Feuer. Die Zombies erscheinen über 13 / 18 / 22 / 24 s.
  Bis Welle 3 hält die Pistole also gerade mit, ab Welle 4 (Schlurfer brauchen den vierten Treffer) nicht mehr.
- **Punkte:** Nach Welle 1 hat man etwa 900 Punkte (Schrotflinte 500), nach Welle 3 etwa 4.400 (Tür 750,
  MP 1.000). Die Wirtschaft ist großzügig.
- **Simulation:** Ein Bot mit ehrlichem Zielen (4 Schuss/s, Streuung, nur Körper, nur Pistole), der stehen
  bleibt, räumt jede Welle 6 bis 10 s nach dem letzten Spawn, kassiert dabei in Welle 2 aber 5 bis 7 und in
  Welle 3 4 bis 16 Schläge. Stehenbleiben geht also ab Welle 2 nicht. Einfache Bots, die ohne Sprint
  zurückweichen und nichts kaufen, überstehen Welle 1 immer ohne Treffer, Welle 2 in 8 von 10 Läufen,
  Welle 3 in 2 von 10. Das liegt auch an ihrer schlichten Wegwahl: Sie laufen in Zombies hinein.
  Wer umzingelt ist, verliert 100 Leben in etwa 3 s (ein Schlag je 0,5 s).
- **Zu prüfen:** `SHOCKWAVE_KNOCKBACK` 9 m/s wirft Zombies etwa 6,75 m weit (Abklingzeit 3 s, ein Schlurfer
  braucht 4 s zurück). Die Gewitterfront ist sehr stark (jeder Treffer ein Blitz mit 100 % Schaden auf bis
  zu 6 Zombies). Sprinten rückwärts (7 m/s) ist schneller als jeder Zombie. Die Schrotflinte gibt bis zu
  80 Treffer-Punkte je Schuss.

### 14.4 Bekannte Schwächen

- Ein Zombie, der nach drei Rettungsversuchen ohne Belohnung verschwindet, sendet kein `zombie_killed`.
  In keinem Testlauf kam das vor.
- Liegt eine Kiste hinter einer Kulisse, gibt es keinen Pfad-Test vom Spieler aus. Sie liegt aber immer auf
  dem Navigationsnetz, also dort, wo auch Zombies laufen.
- Viele Trefferzahlen an einem dichten Pulk überlagern sich.
- Der Pfeil in „Stufe 2 → 4“ kommt aus einer System-Schrift (Windows). Ohne sie fehlt das Zeichen.
- Hält man beim Klick auf eine Karte die Maustaste länger als etwa 0,6 s, schießt eine automatische Waffe
  nach der Wahl einmal.
- Das Publikum ist nur durch die Brüstung (1,1 m) vor Zombies geschützt.
- Requisiten im Raum stehen an festen Stellen. Wer `ZONE1_SIZE` oder `ZONE2_SIZE` ändert, muss sie nachziehen.
- Es gibt keinen Ton und kein Hauptmenü (das Spiel startet sofort).

## 15. Ruckler, Vorwärmen und Einstellungen (Stand 2026-11-20)

**Ursache der Ruckler (gemessen mit `tests/perf_game.gd`).** Godot übersetzt den Shader einer
Material-Art beim ersten Zeichnen und wirft ihn weg, sobald das letzte Material dieser Art
verschwindet. Kisten, Explosionen, Druckwellen und Elite-Zombies bauten ihre Materialien jedes Mal
neu, also wurde jedes Mal neu übersetzt. Mit dem OpenGL-Treiber der Grafikkarte kostete das 300 bis
700 ms je Art (erste Kiste 1,1 s, jede Kistenöffnung etwa 0,5 s), und der Zwischenspeicher auf der
Platte half nicht. Vorher: 46 Bilder über 25 ms, längstes 1257 ms. Nachher: keines über 25 ms,
längstes 19 ms.

**Drei Bausteine der Behebung.**

1. `scripts/game/fx/shader_keep.gd` (statisch): `Game` verbindet `SceneTree.node_added` mit
   `ShaderKeep.track_node`. Von jeder neuen Material-Art (Schlüssel aus allen Schaltern eines
   `StandardMaterial3D`, ohne Farben und Zahlen) bleibt eine Kopie für immer im Speicher, damit lebt
   der Shader weiter. Dasselbe für die Arten von `Label3D`. Materialien, die nie über einen neuen
   Knoten in den Baum kommen (wie das Aufblitzen in `Fx.hit_flash`), meldet der Erzeuger selbst mit
   `ShaderKeep.hold(material)` an.
2. `scripts/game/warmup.gd`: `main.gd` zeigt vor dem ersten `Game.start_run` ein Ladebild und zeichnet
   jede bekannte Art einmal in allen vier Lichtlagen (ohne Zusatzlicht, Punktlicht, Strahler, beides),
   dazu als Partikel und als 3D-Schrift. Der Aufbau steht 600 m unter dem Studio und hat eine eigene
   Kamera. Headless (Tests) und nach einem Neustart des Laufs entfällt das. `main.warmup_enabled = false`
   schaltet es ab (Bildschirmfotos, Messung mit `-- nowarm`). `_ready` von `main.gd` wartet dabei:
   Der Lauf beginnt nicht headless erst nach ein paar Bildern.
3. `project.godot`: `rendering/gl_compatibility/driver.windows="opengl3_angle"`. ANGLE (OpenGL über
   Direct3D 11) sieht gleich aus, aber sein Shader-Zwischenspeicher funktioniert: Ab dem zweiten Start
   dauert das Vorwärmen etwa 0,2 s, beim allerersten Start auf einem Rechner einige Sekunden.

**Liste der Arten.** Mitgeliefert in `res://data/shader_warmup.json` (im Export über
`include_filter="data/*.json"`). Neu aufnehmen nach neuen Inhalten:
`Godot_v4.7-stable_win64_console.exe --disable-vsync --path "<Projekt>" -s res://tests/perf_game.gd -- record`.
Was dort fehlt, lernt das Spiel beim ersten Auftreten selbst (ein Ruckler, dann
`user://shader_warmup.json`) und wärmt es ab dem nächsten Start vor.

**Regeln für neue Inhalte.** Materialien möglichst teilen statt je Objekt neu bauen. Trefferzahlen
nutzen eine feste Schriftgröße (`Fx.NUMBER_FONT_SIZE`), die Größe kommt über den Maßstab: Jede neue
Schriftgröße würde eine neue Schrift-Textur erzeugen.

**Einstellungen.** `scripts/game/settings.gd` (statisch) hält alle Werte des Spielers und speichert sie
in `user://settings.cfg` (Windows: `%APPDATA%\Godot\app_userdata\Zombie-Shooter\settings.cfg`).
Jeder Wert hat einen Setter, der ihn begrenzt, dazu `get_value(id)` und `set_value(id, wert)` über
den Namen. Headless wird die Datei weder gelesen noch geschrieben, und `apply_video` tut nichts.

| Name | Bereich | Standard | Wirkt über |
|---|---|---|---|
| `mouse_sensitivity` | 0,1 bis 3,0 (Schritt 0,05) | 1,0 | Faktor auf `Balance.MOUSE_SENSITIVITY` in `player.gd` |
| `fov` | 60 bis 110 Grad | `Balance.PLAYER_FOV` (80) | `player.gd` liest den Wert jedes Bild |
| `window_mode` | 0 Fenster, 1 Vollbild randlos, 2 Vollbild exklusiv | 0 | `apply_video` |
| `vsync` | an oder aus | an | `apply_video` |
| `fps_limit` | 0 (keine), 30, 60, 120, 144, 165, 240 | 0 | `apply_video` (`Engine.max_fps`) |
| `render_scale` | 0,5 bis 1,0 (Schritt 0,05) | 1,0 | `apply_video` (`scaling_3d_scale`) |
| `msaa` | 0 aus, 1 = 2-fach, 2 = 4-fach, 3 = 8-fach | 0 | `apply_video` (`msaa_3d`) |
| `show_fps` | an oder aus | aus | `hud.gd`, innere Klasse `FpsLabel` |

`main.gd` ruft beim Start `Settings.ensure_loaded()` und `Settings.apply_video(get_window())`.

**Einstellungs-Menü.** `scripts/ui/settings_menu.gd` ist eine zweite Ansicht im Pausemenü
(`pause_menu.settings_menu`, Knopf `settings_button`, `open_settings()`, `close_settings()`,
`is_settings_open()`). Die Zeilen stehen in der Tabelle `ROWS`: Regler (`sliders[id]`,
`value_labels[id]`) oder Umschalt-Knopf (`cyclers[id]`, ein Klick schaltet zum nächsten Wert). Jede
Änderung wirkt sofort und wird gespeichert, `reset_button` stellt alles auf Standard. Esc führt aus
den Einstellungen zur Hauptansicht, das zweite Esc setzt das Spiel fort. Eine neue Einstellung braucht:
Wert und Setter in `settings.gd` (auch in `get_value`, `set_value`, `load_from`, `save_to`,
`reset_to_defaults`) und eine Zeile in `ROWS`.

**FPS-Anzeige.** `hud.fps_label` unten in der Mitte, aktualisiert viermal je Sekunde und läuft auch in
der Pause, damit sie beim Umschalten sofort erscheint.

**Tests.** `tests/test_settings_shaders.gd` (Einstellungen, Grafikwerte, Schlüssel, Liste, Einstellungs-Menü, FPS-Anzeige),
`tests/test_player_weapons.gd` prüft den Faktor am Mausblick. `tests/perf_game.gd` ist kein Test,
sondern die Messung (nicht headless).

## 16. Rucksack, Gegenstände und Kandidaten (Stand 2026-11-20)

Dieser Abschnitt ersetzt die Regeln der Abschnitte 8 und 11 zu Kistenwahl, Upgrade-Plätzen und
Synergie. Die Wirkung der zehn Upgrades selbst (Abschnitt 8, `upgrade_defs.gd`, `upgrade_effects.gd`)
ist unverändert.

**Grundsatz.** `Game.upgrades` bleibt die einzige Stelle, aus der Effekte ihre Stufen lesen. Die Stufen
werden aber nicht mehr direkt gewählt, sondern aus dem Rucksack berechnet: `Game.sync_build()` ruft
`backpack.apply_to(upgrades, CharacterDefs.extra(character_id))`. Die sechs Plätze gibt es nicht mehr,
den Platz begrenzt das Raster.

**Dateien.**

| Datei | Inhalt |
|---|---|
| `scripts/core/item_defs.gd` | Tabelle der Gegenstände: Art, Form, Gruppe, Texte, Verkaufswert, Gewicht in Kisten |
| `scripts/core/backpack_state.gd` | Raster, Einräumen, Drehen, Zusammenlegen, Rucksack-Teile, Nachbarschaft, Verbindungen |
| `scripts/core/character_defs.gd` | Kandidaten: Eigenheiten, Startwaffen, Start-Rucksack, Start-Gegenstände |
| `scripts/ui/backpack_screen.gd` | Rucksack-Bildschirm (Ebene 15), Ziehen und Ablegen |
| `scripts/ui/character_select.gd` | Kandidatenwahl vor dem Lauf (Ebene 40) |

**Gegenstände (21).** Drei Arten:

- *Upgrade-Gegenstand* (10): heißt und wirkt wie das Upgrade mit derselben ID, Stufe 1 bis 5, Form aus
  1 bis 3 Feldern, gehört zu einer Gruppe. Technik: `chain_lightning`, `pierce`, `drone`. Feuer: `burn`,
  `corpse_explosion`. Körper: `lifesteal`, `max_hp`, `speed`. Show: `luck`, `reload_shockwave`.
- *Verstärker* (8), ohne Stufe, wirkt nur über Nachbarn: `cable` (Technik +1 Stufe), `accelerant`
  (Feuer +1), `energy_drink` (Körper +1), `cue_card` (Show +1), `trophy` (alle Gruppen +1, nur in
  Gold-Kisten), `spotlight` (+5 % Waffenschaden je Nachbar), `speed_loader` (Nachladen 8 % schneller je
  Nachbar, höchstens 50 %), `piggy_bank` (+4 % Punkte je freiem Nachbarfeld).
- *Rucksack-Teil* (3): `bag_small` (2 Felder), `bag_medium` (4, ab Silber), `bag_large` (6, nur Gold).
  Wird an den Rand des Rucksacks gelegt, vergrößert das Raster und ist dann verbraucht.

**Raster.** Höchstens 7 mal 5 Felder (`Balance.BACKPACK_COLS`, `BACKPACK_ROWS`), davon existieren die
Felder der Startform (12) plus eingeräumte Rucksack-Teile. Formen lassen sich in Vierteldrehungen
drehen. Nachbarn sind Gegenstände mit gemeinsamer Kante (übereck zählt nicht). Neben dem Raster liegt
die Ablage für 5 Gegenstände (`BACKPACK_STORAGE`): Was dort liegt, wirkt nicht. Ist sie überfüllt,
lässt sich der Rucksack nicht schließen.

**Stufen.**

- Wirksame Stufe eines Upgrade-Gegenstands = eigene Stufe + 1 je passendem benachbartem Verstärker,
  höchstens 5.
- Gleichen Upgrade-Gegenstand auf einen eingeräumten legen: Die Stufen addieren sich (höchstens 5), es
  bleibt ein Gegenstand. Liegen gleiche Gegenstände getrennt, addiert sich ihre Wirkung ebenfalls: Das
  Zusammenlegen spart also Platz.
- Verbindung (bisher Synergie): Gewitterfront ist aktiv, wenn Blitz und Durchschlag je mit Stufe 5
  wirken UND nebeneinander liegen. Sie verschmelzen nicht zu einem Gegenstand (Abweichung von der
  ersten Idee: So bleibt die Verbindung beim Umräumen umkehrbar).

**Zusatzwerte.** `UpgradeState.set_derived(levels, synergies, extra)` nimmt neben den Stufen die Werte
`max_hp` (Leben), `speed`, `damage`, `reload`, `points` (Bruchteile). Sie kommen von Verstärkern und
vom Kandidaten und stecken in `bonus_max_hp()`, `speed_multiplier()`, `points_multiplier()`,
`damage_multiplier()` (Waffenschaden im `WeaponController`) und `reload_time_multiplier()`
(`WeaponState.reload_factor`). `add_levels` von Hand (Tests) verlässt den abgeleiteten Zustand.

**Kisten.** `ChestRoller.build_item_offers(rng, backpack, rarity)` liefert 3 Angebote
`{ "kind": "item", "id", "level", "owned_level" }`. Upgrade-Gegenstände haben die Stufe der Seltenheit
(Bronze 1, Silber 2, Gold 3). Mindestens ein Angebot ist ein Upgrade-Gegenstand, höchstens eines ein
Rucksack-Teil. Was schon mit Stufe 5 wirkt, wird nicht mehr angeboten. Trostpreise gibt es nur, wenn
die Auswahl nicht für 3 reicht. `build_offers` (alte Upgrade-Angebote) besteht weiter für Tests.

**Ablauf in `Game`.**

```
Kiste aufgesammelt   open_chest(rarity)        PLAYING -> CHOOSING, Pause an
Karte gewählt        choose_offer(index)       Gegenstand in die Ablage, CHOOSING -> PACKING,
                                               backpack_opened(uid)
Taste Tab            open_backpack()           PLAYING -> PACKING, Pause an, backpack_opened(-1)
Umräumen             Game.backpack ändern, danach Game.sync_build() -> build_changed
Verkaufen            sell_item(uid)            Punkte: 100 je Stufe, Verstärker 100, Rucksack-Teil 150
Schließen            close_backpack()          PACKING -> PLAYING, Pause aus. Jetzt erst kommen
                                               upgrade_chosen (je gestiegenem Upgrade) und
                                               synergy_unlocked, dann backpack_closed
```

`build_changed` kommt bei jeder Änderung, auch wenn Stufen sinken: Spieler (Leben, Tempo), Drohne und
HUD-Leiste gleichen sich daran ab. `upgrade_chosen` bleibt das Signal für den Jubel. `State.PACKING`
hat den Wert 5 (hinten angehängt). Mit `Game.auto_pack = true` räumt sich ein gewählter Gegenstand
selbst ein und der Rucksack öffnet sich nicht: für Tests, Messung und Bildschirmfotos.

**Kandidaten.** `Game.character_id` ("" = keiner) bleibt über Läufe erhalten und muss vor `start_run`
gesetzt sein. Ohne Kandidat gelten die Grundwerte mit leerem Rucksack: So laufen alle Tests.

| ID | Name | Leben | Tempo | Waffen neben der Pistole | Start |
|---|---|---|---|---|---|
| `janitor` | Der Hausmeister | 130 | 5 % langsamer | Schrotflinte | Werbepause, Rucksack 4 x 3 |
| `intern` | Die Praktikantin | 80 | 10 % schneller | Maschinenpistole | Turbo-Turnschuhe, Rucksack 6 x 2 |
| `technician` | Der Tontechniker | 100 | normal | keine | 500 Punkte, Starkstrom-Sponsor mit Verlängerungskabel, Rucksack in Kreuzform |

`main.gd` zeigt nach dem Vorwärmen die Kandidatenwahl und ruft `Game.start_run` erst nach
`character_chosen`. Headless oder mit `main.character_select_enabled = false` beginnt der Lauf sofort.
Ein Neustart lädt die Szene neu und zeigt die Wahl wieder.

**Rucksack-Bildschirm.** `main.backpack_screen`. Tab öffnet und schließt, Esc schließt. Ziehen mit der
Maus, Drehen mit R oder Rechtsklick, Doppelklick auf einen Gegenstand in der Ablage räumt ihn selbst
ein. Für Tests und andere Module: `pick_up(uid)`, `rotate_held()`, `drop_on_cell(cell)`,
`drop_on_storage()`, `drop_on_sell()`, `cancel_hold()`, `quick_place(uid)`, `request_close()`.
Halten ändert den Rucksack nicht, erst das Ablegen. Die Kandidatenwahl ist `main.character_select`
(`open()`, `choose(id)`, Signal `character_chosen`).

**Tests.** `tests/test_backpack.gd` (Kern und Ablauf in Game), `tests/test_backpack_screen.gd`,
`tests/test_character_select.gd`. Die älteren Tests benutzen `Game.auto_pack` oder legen Angebote von
Hand in `Game.current_offers`.

## 17. Raritäten statt Stufen, Kisten-Regeln, Buff-Anzeige (Stand 2026-11-20)

Dieser Abschnitt ersetzt in Abschnitt 16 die Absätze „Stufen“ und „Kisten“ und die Angaben zu den
Verstärkern. Raster, Drehen, Verschieben, Ablage und Kandidaten gelten unverändert.

**Raritäten.** Upgrade-Gegenstände und Verstärker haben eine von fünf Raritäten: Gewöhnlich,
Ungewöhnlich, Selten, Episch, Legendär (`ItemDefs.RARITY_NAMES`, Farben in `RARITY_COLORS`). Im Code
bleibt das die Zahl 1 bis 5 im Feld `level`: Bei Upgrade-Gegenständen ist sie zugleich die Stufe, mit
der das Upgrade in `UpgradeDefs` wirkt. Im Spiel steht nirgends mehr „Stufe“. Rucksack-Teile haben
keine Rarität.

**Kombinieren.** Zwei gleiche Gegenstände derselben Rarität werden zu einem der nächsten Rarität
(`BackpackState.merge_target`, `merge`, `find_merge_partner`). Verschiedene Raritäten lassen sich nicht
kombinieren, Legendär ist das Ende. Das gilt auch für Verstärker. Ein Legendärer entspricht damit 16
Gewöhnlichen. Liegt derselbe Gegenstand mehrfach im Rucksack, zählt nur der beste: Die Wirkung stapelt
sich nicht (`upgrade_levels` nimmt das Maximum). Mit `Game.auto_pack` kombiniert sich ein neuer
Gegenstand von selbst, auch in Ketten.

**Verstärker nach Rarität.**

| Art | Gewöhnlich | Ungewöhnlich | Selten | Episch | Legendär |
|---|---|---|---|---|---|
| Gruppen-Verstärker und Pokal: Nachbarn wirken um so viele Raritäten höher (`BOOST_STEPS`) | 1 | 1 | 2 | 2 | 3 |
| Scheinwerfer: Waffenschaden je Nachbar | 4 % | 6 % | 8 % | 10 % | 12 % |
| Ladehilfe: schnelleres Nachladen je Nachbar (zusammen höchstens 50 %) | 6 % | 9 % | 12 % | 15 % | 18 % |
| Sparschwein: Punkte je freiem Nachbarfeld | 4 % | 6 % | 8 % | 10 % | 12 % |

Die wirksame Rarität eines Upgrade-Gegenstands ist seine eigene plus die Anhebung durch Verstärker,
höchstens Legendär. Die Gewitterfront braucht weiter Blitz und Durchschlag, beide wirksam Legendär und
nebeneinander.

**Verkaufen.** Gewöhnlich 100 Punkte, jede Rarität darüber das Doppelte (bis 1.600), Rucksack-Teil 150.

**Kisten.** `ChestRoller.build_item_offers(rng, backpack, rarity, force_bag, recent)`:

- Rarität des Fundes nach Kiste: Bronze Gewöhnlich, Silber Ungewöhnlich, Gold Selten. Das gilt jetzt
  auch für Verstärker.
- Rucksack-Teile: Eine Kiste bietet mit 30 % eines an (`Balance.CHEST_BAG_CHANCE`). Kam zwei Kisten
  lang keines, enthält die nächste sicher eines (`CHEST_BAG_PITY`, `Game` zählt mit). Nie mehr als
  eines, und nur, solange es ins Raster passt. Vorher lag die Chance je Bronze-Kiste bei etwa 10 %.
- Abwechslung: Gegenstände aus der letzten Kiste zählen in der nächsten nur mit 20 % ihres Gewichts
  (`CHEST_REPEAT_WEIGHT`). Ausgeschlossen wird nur noch, was der Spieler schon in Legendär hat. Vorher
  fiel jedes Upgrade ab wirksamer Stufe 5 aus der Auswahl, und mit dem alten Addieren der Stufen war
  das schnell erreicht: Übrig blieben immer dieselben Verstärker.
- `owned_level` im Angebot ist die höchste Rarität, in der der Spieler den Gegenstand besitzt
  (`BackpackState.highest_level`, auch in der Ablage).

**HUD.** Die Leiste mit den Upgrades links gibt es nicht mehr (welche Gegenstände man hat, zeigt der
Rucksack). An ihrer Stelle steht die Buff-Anzeige: `hud.buff_header`, `hud.buff_rows` mit je einem Kind
`Buff_<key>` und dem Label `Text`. `Hud.buff_entries(upgrades)` liefert die Zeilen: Schaden, Nachladen,
Tempo, Punkte (in Prozent, nur wenn nicht 0), Leben (Zusatz-Leben) und jede aktive Verbindung
(`synergy_<id>`). Ein Malus (zum Beispiel das Tempo des Hausmeisters) steht in Orange mit Minus. Die
Liste im Game Over zeigt je Upgrade die Rarität (`Row_<id>/Rarity`) statt einer Stufenzahl.

## 18. Waffen im Rucksack, Hände, Sterne, mehrfache Wirkung (Stand 2026-11-21)

Dieser Abschnitt ersetzt aus Abschnitt 8 die Waffenregeln (Vorrat, Wandkauf von Munition,
Waffenwechsel) und aus den Abschnitten 16 und 17 alles zu Nachbarschaft und Verstärkern.

### 18.1 Regeln

- **Waffen sind Gegenstände** mit Form und Rarität (`ItemDefs`, Art `weapon`, id = Waffen-ID). Was als
  Waffe im Raster liegt, hält der Spieler in der Hand. Einen Waffenwechsel gibt es nicht mehr.
- **Zwei Hände** (`Balance.PLAYER_HANDS`). Jede Waffe braucht eine oder zwei (`ItemDefs.hands`). Die
  eingeräumten Waffen dürfen zusammen höchstens zwei brauchen, sonst passt die Waffe nicht ins Raster
  (`BackpackState.has_free_hands`, `can_place`). Möglich sind also: eine Zweihand-Waffe, eine
  Einhand-Waffe oder zwei Einhand-Waffen (gleiche oder verschiedene: beidhändig).
- **Reihenfolge der Hände:** von links nach rechts im Raster (`BackpackState.loadout`). Index 0 ist die
  linke Hand.
- **Ohne Waffe im Rucksack** hält der Spieler die Dienstpistole mit der uid 0 (`Game.loadout`).
- **Schießen:** Die Aktion `fire` (linke Maustaste) schießt mit allen gehaltenen Waffen, jede in ihrer
  eigenen Schussfolge. `reload` lädt alle nach. Munition ist unendlich, es gibt nur das Magazin.
- **Waffen (9):** Einhand: `pistol` Dienstpistole, `revolver`, `smg`, `sawed_off`. Zweihand: `shotgun`,
  `rifle`, `sniper`, `minigun`, `rocket_launcher`. Schaden mal `Balance.WEAPON_RARITY_DAMAGE`
  (1,0 / 1,25 / 1,5 / 1,8 / 2,2) je Rarität.
- **Sterne:** Ein Gegenstand mit Sternfeldern (`ItemDefs.stars`, sie drehen sich mit) wirkt nur für
  die Waffen, die eines seiner Sternfelder belegen. Ohne Waffe auf einem Stern wirkt er nicht. Die
  Anzeige zeigt jedes Sternfeld: gefüllt, wenn eine Waffe darauf liegt (`BackpackState.is_star_lit`),
  sonst leer. Sterne haben bisher: `chain_lightning`, `pierce`, `burn` (Kugel-Effekte), `spotlight`
  (Schaden), `speed_loader` (Nachladen). Alles andere wirkt für den Spieler als Ganzes.
- **Mehrfache Wirkung:** Jedes wirkende Exemplar zählt. `UpgradeDefs.combined_value(id, key, stufen)`
  verbindet die Werte: addieren (Standard), bester Wert bei `radius`, `range`, `damage_factor`,
  `damage_percent`, kleinster bei `interval`, und `chance` endet bei 1,0. Jede Kameradrohne im
  Rucksack ist eine eigene Drohne.
- **Verstärker (3):** `spotlight` (+10 % Schaden für Waffen auf den Sternen), `speed_loader` (Waffen
  auf den Sternen laden 10 % schneller nach, zusammen höchstens 50 %), `piggy_bank` (+6 % Punkte,
  ohne Sterne). Die Werte gelten für Gewöhnlich und wachsen mit `ItemDefs.STAT_FACTORS`. Die fünf
  Verstärker, die Nachbarn eine Rarität höher machten, gibt es nicht mehr.
- **Gewitterfront:** aktiv, wenn `chain_lightning` und `pierce` beide Legendär auf dieselbe Waffe
  wirken.
- **Wandkäufe** verkaufen für Punkte eine gewöhnliche Waffe: `Game.grant_item(id, 1)` legt sie in die
  Ablage und öffnet den Rucksack. Munition wird nicht mehr gekauft.

### 18.2 Schnittstellen im Kern (fertig und getestet in `tests/test_backpack.gd`)

```
ItemDefs      is_weapon(id), hands(id), has_stars(id), stars(id, rot), star_target(id),
              is_weapon_mod(id), weapon_damage_factor(level), weapon_text(id, level),
              stat(id), stat_amount(id, level)
BackpackState hands_used(exclude_uid), has_free_hands(uid), star_cells_of(uid), star_targets(uid),
              is_star_lit(uid, cell), mods_of(weapon_uid), is_active(uid), loadout(),
              global_copies(), upgrade_levels(), stat_contribution(uid), stars_at(id, pos, rot)
UpgradeDefs   combined_value(id, key, levels), STACK_MODES
UpgradeState  copies(id), value(id, key), value_with(other, id, key), level_with(other, id),
              set_derived(levels, synergies, extra, copies)
Game          loadout            Array aus { uid, id, level, hands, copies, damage, reload }
              loadout_entry(uid), weapon_upgrades(uid) -> UpgradeState
              bullet_value(weapon_uid, id, key), bullet_level(weapon_uid, id)
              weapon_damage_multiplier(uid), weapon_reload_multiplier(uid)
              grant_item(id, level) -> uid
Events        loadout_changed, hand_ammo_changed(hand, mag, magazine_size),
              hand_reload_started(hand, duration), hand_reload_finished(hand)
```

`Game.upgrades` enthält in den Werten nur, was für den Spieler als Ganzes gilt
(`Game.upgrades.value("lifesteal", "ratio")` addiert alle Exemplare). Kugel-Effekte je Waffe gibt es
nur über `Game.bullet_value(weapon_uid, ...)`: Das verbindet die allgemeinen Exemplare mit denen der
Waffe. Tests, die Stufen von Hand in `Game.upgrades` setzen (`add_levels`), wirken damit weiter für
jede Waffe. `Game.upgrades.get_level(id)` nennt für Übersichten die beste wirkende Rarität, auch von
Stern-Gegenständen.

Nach jeder Änderung am Rucksack ruft der Aufrufer `Game.sync_build()`. Das berechnet `Game.upgrades`
und `Game.loadout` neu und sendet `build_changed`.

### 18.3 Aufteilung der Module

| Modul | Dateien | Aufgabe |
|---|---|---|
| Waffen | `scripts/core/weapon_defs.gd`, `weapon_state.gd`, `scripts/game/player/weapon_controller.gd`, `view_model.gd`, `scripts/game/level/wall_buy.gd`, Waffenanzeige in `scripts/ui/hud.gd` | neun Waffen, unendliche Munition, beidhändig, Wandkauf über `grant_item`, Anzeige je Hand |
| Effekte | `scripts/game/upgrades/upgrade_effects.gd`, `drone.gd` | Kugel-Effekte je Waffe über `info["weapon_uid"]`, eine Drohne je Exemplar |
| Rucksack-Bildschirm | `scripts/ui/backpack_screen.gd` | Sterne zeichnen, Hände anzeigen, Texte für Waffen und Stern-Gegenstände |

**Treffer-Info:** Die Waffensteuerung gibt in `info` von `take_damage` und `bullet_hit` zusätzlich mit:
`"weapon_uid": int` (uid der Waffe aus `Game.loadout`, 0 = Dienstpistole ohne Rucksack),
`"weapon": String` (Waffen-ID) und `"hand": int`. Fehlt `weapon_uid` (ältere Tests), gilt -1: Dann
zählen nur die allgemeinen Upgrades.

### 18.4 Stand nach dem Zusammenbau

Waffen (Zahlen in `weapon_defs.gd`, DPS ohne Nachladen):

| ID | Name | Hände | Schaden | Schuss/s | Magazin | Nachladen | Preis | DPS |
|---|---|---|---|---|---|---|---|---|
| `pistol` | Dienstpistole | 1 | 25 | 5 | 10 | 1,2 s | 0 | 125 |
| `revolver` | Kandidatenschreck | 1 | 70 | 2 | 6 | 1,9 s | 400 | 140 |
| `smg` | Quotenhammer | 1 | 16 | 12 | 30 | 1,8 s | 1000 | 192 |
| `sawed_off` | Blitzrunde | 1 | 5 x 14 | 2 | 2 | 1,4 s | 400 | 140 |
| `shotgun` | Publikumsjoker | 2 | 8 x 14 | 1,25 | 6 | 2,2 s | 500 | 140 |
| `rifle` | Dauerbrenner | 2 | 24 | 9 | 30 | 2,0 s | 1250 | 216 |
| `sniper` | Fernbedienung | 2 | 240 | 0,8 | 5 | 2,6 s | 1250 | 192 |
| `minigun` | Applausmaschine | 2 | 13 | 20 | 120 | 4,0 s | 2000 | 260 |
| `rocket_launcher` | Showfinale | 2 | 250 und Explosion 150 in 3,5 m | 1 | 1 | 2,4 s | 2000 | 250 |

- `WeaponController`: `get_hands()` (je Hand `hand`, `uid`, `id`, `level`, `hands`, `mag`, `magazine`,
  `reloading`, `reload_left`, `reload_duration`), `get_state_of(uid)`, `try_fire()`, `start_reload()`,
  `is_reloading()`. Für Tests und Werkzeuge: `give_weapon(id)` und `equip(ids)` räumen den Rucksack
  so um, dass der Spieler genau diese Waffen hält (sie rufen `Game.sync_build()` und überschreiben
  damit von Hand gesetzte Upgrades), `refill_ammo(id)`, `get_state(id)`, `get_current_weapon_id()`,
  `get_owned_weapon_ids()`, `has_weapon(id)`. `switch_to` tut nichts mehr.
- `ViewModel`: `set_loadout(hands)`, `play_fire(hand)`, `get_muzzle_position(hand)`. Knoten je Hand unter
  `Rig/Hand0` und `Rig/Hand1`.
- `UpgradeEffects`: `drones` (eine Drohne je Kameradrohne im Rucksack, `drone` bleibt die erste),
  Gewitterfront gilt nur für die Waffe, auf die beide Gegenstände wirken. Die Druckwelle der
  Werbepause löst beim Nachladen jeder Hand aus, höchstens einmal je Physik-Schritt.
- `BackpackScreen`: `star_marks()`, `hand_slots()`, `hands_text()`, `hands_label`.
- HUD: `hand_boxes` und `reload_bars` (eine je gehaltener Waffe), `magazine_label` statt `reserve_label`.
- Wandkauf: Hinweis „E: Publikumsjoker kaufen (500 Punkte)“, Kauf über `Game.grant_item`.
- Die älteren Abschnitte 8, 13 und 14 beschreiben an einigen Stellen noch Vorrat, Waffenwechsel und
  den Munitionskauf: Dort gilt dieser Abschnitt.

Offen und bekannt: Zwei Maschinenpistolen beidhändig machen mehr Schaden je Sekunde (384) als jede
Zweihand-Waffe. Wand-Silhouetten gibt es nur für Schrotflinte und Maschinenpistole. Die Balance
ist nach dem Umbau nicht neu gemessen.
