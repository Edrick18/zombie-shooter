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
echte 3D-Modelle (alles Platzhalter aus einfachen Formen). Ton gibt es seit Abschnitt 21.

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
- Es gibt kein Hauptmenü (das Spiel startet mit der Kandidatenwahl). Ton: siehe Abschnitt 21.

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

## 19. Zwölf neue Gegenstände (Stand 2026-11-21)

Elf davon sind Upgrade-Gegenstände: Sie stehen mit Werten je Rarität in `UpgradeDefs.UPGRADES`
(Liste `UpgradeDefs.ITEM_ONLY`, nicht in `ORDER`) und mit Form und Sternen in `ItemDefs`. Der zwölfte,
die Wiederholung, ist ein Verstärker, dessen Stern auf Gegenstände zielt. Der Kern (Tabellen, Sterne,
mehrfache Wirkung, Kisten) ist fertig und in `tests/test_backpack.gd` getestet.

### 19.1 Für die Waffe auf den Sternen

Diese Werte gelten je Waffe. Gelesen werden sie mit `Game.bullet_value(weapon_uid, id, key)`, ob der
Gegenstand für die Waffe wirkt, sagt `Game.bullet_level(weapon_uid, id) > 0`.

| ID | Name | Schlüssel und Regel |
|---|---|---|
| `extra_shot` | Zugabe | `shots` zusätzliche Kugeln je Schuss (bei Schrot je Schuss, nicht je Schrotkugel), jede mit dem Anteil `damage_factor` am Kugelschaden. Die Zusatzkugel fliegt leicht versetzt. Beim Raketenwerfer ist es eine zweite Rakete. In `info` steht `"extra": true`. |
| `poison` | Kantinenessen | Jeder Kugeltreffer vergiftet für `Balance.POISON_DURATION` Sekunden (ein weiterer Treffer stellt die Zeit neu). `dps` Schaden je Sekunde mal `Game.effect_factor()`, Quelle `"poison"`. |
| `crit` | Glücksrad | Je Kugel mit `chance` ein kritischer Treffer: Schaden mal `Balance.CRIT_MULTIPLIER`. Zufall aus `Game.rng`. In `info` steht `"crit": true`. |
| `big_mag` | Überlänge | Magazin = Grundgröße mal (1 + `bonus`), aufgerundet. |
| `scope` | Teleprompter | Streuung mal `Balance.SCOPE_SPREAD_FACTOR`, Kopfschuss-Schaden mal (1 + `headshot_bonus`). |
| `fire_rate` | Schnelldurchlauf | Schussfolge durch (1 + `bonus`). |

### 19.2 Für den Spieler als Ganzes

Gelesen mit `Game.upgrades.value(id, key)` (alle Exemplare zusammen) oder `Game.upgrades.copies(id)`
(Rarität je Exemplar).

| ID | Name | Schlüssel und Regel |
|---|---|---|
| `shield` | Sicherheitsglas | Schild mit `amount` Punkten. Schaden trifft zuerst das Schild. Nach `Balance.SHIELD_RECHARGE_DELAY` Sekunden ohne Schaden lädt es mit `SHIELD_RECHARGE_RATE` je Sekunde. Signal `player_shield_changed(shield, max_shield)`. |
| `kill_heal` | Trostpflaster | Jeder Kill (gleich welche Quelle) heilt `heal` Leben. |
| `disco_ball` | Discokugel | Je Exemplar eine eigene Kugel, die im Abstand `Balance.DISCO_ORBIT_RADIUS` um den Spieler kreist. Sie macht `damage` mal `Game.effect_factor()` an Zombies im Abstand `DISCO_HIT_RADIUS`, am selben Zombie höchstens alle `DISCO_HIT_INTERVAL` Sekunden, Quelle `"disco"`. |
| `jammer` | Störsender | Alle `Balance.JAMMER_INTERVAL` Sekunden `damage` mal `Game.effect_factor()` an allen Zombies im Umkreis `radius`, Quelle `"jammer"`. Ohne Zombie im Umkreis verfällt der Schlag nicht: Er löst aus, sobald einer da ist. |
| `dash` | Notausgang | Aktion `dash` (Taste Q): Ausweichsprung in Laufrichtung (ohne Richtung nach vorn) mit `Balance.DASH_SPEED` für `DASH_TIME`. `charges` Sprünge, jeder lädt in `cooldown` Sekunden nach. Während des Sprungs nimmt der Spieler keinen Schaden. Signale `dash_charges_changed(charges, max_charges)` und `player_dashed`. |

### 19.3 Wiederholung

`replay` (Verstärker, nur in Gold-Kisten): Sein Stern zielt auf einen Upgrade-Gegenstand
(`ItemDefs.STAR_ITEM`, `ItemDefs.star_hits`). Der Gegenstand zählt dann ein weiteres Mal, das zweite
Mal höchstens in der Rarität der Wiederholung (`BackpackState.copy_levels`). Das gilt auch für
Kugel-Effekte (die Waffe bekommt sie doppelt), Drohnen und Discokugeln (eine mehr). Auf Waffen,
Verstärker und andere Wiederholungen wirkt sie nicht.

### 19.4 Sternmuster (ungedreht)

`extra_shot` zwei Felder in einer Linie vor der Form, `poison` die vier Ecken, `crit` links und
rechts, `big_mag` über und unter beiden Feldern, `scope` ein Feld in der Innenecke, `fire_rate` ein
Ring aus sechs Feldern, `replay` ein Feld rechts daneben.

Die Taste für den Ausweichsprung ist Q und nicht die linke Alt-Taste: Alt zusammen mit der
Leertaste (Springen) öffnet unter Windows das Fenstermenü.

### 19.5 Stand nach dem Zusammenbau (2026-11-21)

Alle zwölf Gegenstände sind gebaut und getestet. Neue öffentliche Teile der Module:

- `player.gd`: `shield`, `max_shield`, `dash_charges`, `max_dash_charges`, `try_dash() -> bool`,
  `is_dashing()`, `is_invulnerable()`. Ein neues Schild und neue Sprung-Ladungen kommen leer an
  und laden dann normal auf (sonst wäre Ein- und Ausräumen im Rucksack eine Gratis-Heilung).
- `upgrade_effects.gd`: Listen `drones` und `disco_balls` (ein Knoten je Exemplar),
  `get_jammer_time_left()`. Gift, Brand und Kettenblitz lesen ihre Werte je Waffe über
  `info["weapon_uid"]`.
- `disco_ball.gd` (neu): `set_level`, `set_slot(index, total)`, `get_hit_damage()`, `tick(delta, base_angle)`.
- `zombie.gd`: `apply_poison(dps, duration)`, `is_poisoned()`.
- `weapon_controller.gd`: Treffer-`info` trägt zusätzlich `extra` (Zusatzkugel) und `crit`.
- `hud.gd`: Schild-Anzeige (`shield_box`, `shield_label`, `shield_max_label`, `shield_bar`) und
  Sprung-Anzeige (`dash_box`, `dash_pips`), beide nur sichtbar, wenn der Gegenstand im Rucksack liegt.

Mit echter Grafik angesehen: Discokugel, Gift-Färbung, Störsender-Blitz, Schild- und Sprung-Anzeige,
Sternmuster im Rucksack. `tests/perf_game.gd` misst die neuen Gegenstände mit (Abschnitt „Gift,
Brand, Störsender, Discokugel, Schild“): 0 Bilder über 25 ms. Mit `-- trace` druckt die Messung zu
jedem langen Bild die Signale, die davor kamen.

## 20. Balance der späten Wellen und der Begleiter (Stand 2026-11-21)

Anlass: Mit zehn Kamera-Drohnen war der Spieler ab etwa Welle 30 unbesiegbar.

Ursachen:

1. Der Schaden von Drohne, Discokugel, Störsender, Gift, Brand, Blitz und Explosion wird mit
   `Game.effect_factor()` multipliziert. Dieser Faktor wuchs ohne Ende mit 75 % des Zombie-Lebens
   mit. Die Zombies wurden gegen diese Effekte also nie zäher.
2. Jedes Exemplar einer Drohne war eine volle, unabhängige Drohne. Zehn Drohnen = zehnfacher Schaden.
3. Der Druck der Gegner war ab Welle 11 gedeckelt: höchstens 24 Zombies gleichzeitig, ein Zombie
   alle 0,4 s, Schaden und Tempo gleich wie in Welle 1.

Änderungen (alle Zahlen in `balance.gd`, Formeln in `wave_plan.gd`):

| Was | Vorher | Jetzt |
|---|---|---|
| `WavePlan.effect_factor(wave)` | 0,75 × Lebens-Faktor, ohne Grenze | bis Welle 10 wie vorher, danach nur noch × `EFFECT_FACTOR_LATE_MULTIPLIER` (1,04) je Welle. Das Leben wächst weiter × 1,1. |
| Mehrere Drohnen oder Discokugeln | jede voll | jede macht den Anteil `UpgradeDefs.companion_factor(n)` = 1 / n^`COMPANION_STACK_EXPONENT` (0,5). Zwei zusammen 1,41-fach, vier 2-fach, zehn 3,16-fach. |
| `WavePlan.max_alive(wave)` | fest 24 | 24 bis Welle 10, danach +`MAX_ZOMBIES_ALIVE_PER_LATE_WAVE` (2) je Welle bis `MAX_ZOMBIES_ALIVE_CAP` (48) |
| `WavePlan.spawn_interval(wave)` | Untergrenze 0,4 s | ab `SPAWN_INTERVAL_LATE_FROM_WAVE` (11) weitere −0,02 s je Welle bis `SPAWN_INTERVAL_FLOOR` (0,15 s) |
| `WavePlan.damage_factor(wave)` | immer 1 | 1 + `ZOMBIE_DAMAGE_PER_WAVE` (0,05) je Welle ab `ZOMBIE_DAMAGE_FROM_WAVE` (5). `WavePlan.zombie_damage(type, wave)` rechnet ihn ein. |
| Sprinter-Tempo | fest | nach Welle 10 +`SPRINTER_SPEED_PER_LATE_WAVE` (0,05 m/s) je Welle bis `SPRINTER_SPEED_MAX` (6,4) |

`WavePlan.plan()` hat dadurch neun Schlüssel (neu `max_alive`, `damage_factor`). `wave_manager.gd`
liest `WavePlan.max_alive`, `zombie.gd` liest `WavePlan.zombie_damage`. `drone.gd` und
`disco_ball.gd` multiplizieren ihren Schaden mit `companion_factor` der Zahl ihrer Geschwister.

Gerechnet, nicht gespielt: Zehn legendäre Drohnen schaffen in Welle 33 etwa 0,65 Walker je Sekunde,
während bis zu 6,7 je Sekunde erscheinen. Ob sich das im Spiel richtig anfühlt, muss ein Probelauf
zeigen. Stellschrauben sind die Zahlen oben.

Bekannt offen: Zwei Quotenhammer (SMG) in beiden Händen sind stärker als jede Zweihandwaffe.

## 21. Ton (Stand 2026-11-21)

- `scripts/game/audio/sfx.gd`: ein Knoten, den `main.gd` als Kind `Sfx` anlegt. Er hört nur auf
  `Events` und auf Knöpfe, ändert nichts am Spiel und benutzt nie `Game.rng`. Öffentlich:
  `play(id, volume_db := 0.0)`, `play_at(id, position, volume_db := 0.0)`, `has_sound(id)`,
  `get_play_count(id)`, `sound_ids()`, `playback_enabled`. Welches Signal welches Geräusch auslöst,
  steht im Kopf der Datei, Lautstärke, Tonhöhen-Streuung und Mindestabstand je Geräusch in der
  Tabelle `SOUNDS`.
- Zwei Vorräte von Spielern: 16 ohne Ort (Schüsse, Treffer, Menü, Fanfaren) und 12 mit Ort in der
  Welt (Stöhnen, Tod, Explosion, Blitz, Kiste, Drohne). Eigener Bus `Sfx` unter `Master`.
  `process_mode` ALWAYS, damit Menü-Geräusche auch in der Pause erklingen.
- 40 WAV-Dateien in `audio/` (16 Bit, Mono, 44100 Hz), alle berechnet von `tools/make_sounds.py`
  (kein fremdes Material). Ersetzen durch echte Aufnahmen: Datei mit gleichem Namen ablegen, siehe
  `audio/LIESMICH.txt`. Fehlt eine Datei, bleibt nur dieses Geräusch stumm.
- Neues Signal `Events.explosion(position, radius)`: gesendet von `weapon_controller._explode` und
  `upgrade_effects._explode`, damit auch eine Rakete in die Wand zu hören ist. `Events` hat damit
  36 Signale.
- Einstellung `master_volume` (0 bis 1, Standard 0,8, Abschnitt `ton` in `user://settings.cfg`),
  Regler „Lautstärke“ im Einstellungsmenü, `Settings.apply_audio()` setzt den Master-Bus.
- Headless (Tests) startet kein Spieler, die Starts werden nur gezählt (`get_play_count`). Sonst
  endet ein Test oft mitten in einem Geräusch, und Godot meldet verlorene Objekte.
  `tests/test_audio.gd` schaltet `playback_enabled` selbst ein und wartet am Ende.
- Geprüft sind die Dateien nur in Zahlen (Länge, Pegel) und die Auslöser im Test. Angehört hat sie
  noch niemand: Lautstärken stehen in `SOUNDS` und sind nach dem ersten Probehören nachzustellen.

## 22. Ausbau 3: Kameras mit festen Werten, neue Waffen und Gegenstände, größeres Studio, Freischalten (Stand 2026-11-21)

Vom Nutzer entschieden: Kameras haben feste Werte und werden über Gegenstände stärker. Es gibt
mehrere Kameratypen, mehr Waffen, mehr Gegenstände. Die Wandwaffen entfallen (man konnte Waffen zu
schnell auf Legendär kaufen). Das Studio wird größer und bekommt mehr kaufbare Räume. Mit Punkten
schaltet man zwischen den Läufen Pakete mit 3 bis 5 Gegenständen oder Waffen frei, die danach in
Kisten liegen können.

Dieser Abschnitt legt Regeln und Zahlen fest. Die genauen Schnittstellen trägt der Kern in 22.7 nach.

### 22.1 Kameras

- Eine Kamera ist ein Gegenstand der neuen Art `camera`. Jedes eingeräumte Exemplar ist ein eigener
  Knoten im Spiel (eine Wiederholung auf ihrem Stern macht ein zweites Exemplar, wie bisher).
- **Feste Werte je Rarität.** Kein `Game.effect_factor()`, kein `companion_factor` mehr für
  Kameras. (Discokugel, Störsender, Gift, Brand, Blitz, Explosion bleiben, wie sie sind.)
- Werte stehen in der neuen Datei `scripts/core/camera_defs.gd`. `"drone"` bleibt die ID der
  Kameradrohne.

| ID | Name | Regel | Werte Gewöhnlich bis Legendär |
|---|---|---|---|
| `drone` | Kameradrohne | Einzelschuss auf den nächsten Zombie mit Sichtlinie | Schaden 15/21/28/36/46, Abstand 1,2/1,0/0,8/0,65/0,5 s, Reichweite 15 m |
| `cam_tele` | Tele-Kamera | seltener, starker Schuss, geht durch weitere Zombies in der Linie | Schaden 70/100/135/175/220, Abstand 3,2/2,9/2,6/2,3/2,0 s, Reichweite 30 m, Durchschlag 1/1/2/2/3 |
| `cam_flash` | Blitzlicht-Kamera | Blitz trifft alle Zombies in einem Kegel von 90 Grad vor der Kamera (sie dreht sich zum nächsten Zombie) | Schaden 18/25/33/42/52, Abstand 3,0/2,8/2,6/2,4/2,2 s, Reichweite 7 m |
| `cam_slow` | Zeitlupen-Kamera | Treffer verlangsamt den Zombie für 2 s (Elite: halbe Wirkung) | Schaden 4/6/8/10/12, Abstand 1,5/1,4/1,3/1,2/1,1 s, Reichweite 12 m, Verlangsamung 30/35/40/45/50 % |
| `cam_director` | Regie-Kamera | markiert einen Zombie für 4 s (zuerst Elite, dann unmarkierte), kein Schaden. Markierte nehmen aus jeder Quelle mehr Schaden | Abstand 3,0/2,7/2,4/2,1/1,8 s, Reichweite 18 m, Mehr-Schaden 20/25/30/40/50 % |

Mehrere Verlangsamungen oder Markierungen addieren sich nicht: Es gilt die stärkste, die Zeit wird
neu gestellt.

Kamera-Gegenstände (Art `upgrade`, Sterne zielen auf Kameras: `ItemDefs.STAR_CAMERA`). Mehrere
Exemplare auf derselben Kamera addieren sich.

| ID | Name | Wirkung auf die Kamera auf den Sternen | Werte |
|---|---|---|---|
| `cam_lens` | Großes Objektiv | mehr Schaden | +20/30/40/55/70 % |
| `cam_zoom` | Zoom | mehr Reichweite | +20/30/40/50/60 % |
| `cam_battery` | Akkupack | schnellere Schussfolge (Abstand durch 1 + Bonus) | +15/25/35/45/60 % |
| `cam_second` | Zweitkamera | jeder Schuss trifft ein zweites Ziel mit einem Anteil der Wirkung (Blitzlicht: zweiter Blitz 0,4 s später mit dem Anteil) | 40/55/70/85/100 % |
| `cam_uplink` | Sendeleitung | ohne Sterne: alle Kameras mehr Schaden und schnellere Schussfolge | +8/12/16/20/25 % |

Die fertigen Werte einer Kamera rechnet der Kern aus (reine Funktion, testbar), das Spiel liest sie
nur.

### 22.2 Neue Waffen (zehn, zusammen 19)

Neue Felder in `WeaponDefs` (alle mit Standardwert, alte Waffen bleiben unverändert): `mode`
(`"bullet"` Standard, `"grenade"`, `"flame"`, `"beam"`), `burst` (Schüsse je Abzug, Standard 1),
`pierce` (durchschlägt so viele weitere Zombies, Standard 0), `arc_jumps` und `arc_factor`
(eingebauter Blitz auf weitere Zombies), `range` (m, nur `flame`).

| ID | Name | Hände | Werte |
|---|---|---|---|
| `burst_pistol` | Dreierpack | 1 | Schaden 22, Salve aus 3 Schüssen (0,07 s Abstand), 2,2 Salven/s, Magazin 15, Nachladen 1,4 s, Streuung 1,0 |
| `nail_gun` | Bühnenbau | 1 | Schaden 9, 14 Schuss/s, Dauerfeuer, Magazin 40, Nachladen 1,6 s, Streuung 2,2, Durchschlag 1 |
| `machine_pistol` | Werbeblock | 1 | Schaden 11, 18 Schuss/s, Dauerfeuer, Magazin 20, Nachladen 1,2 s, Streuung 3,0 |
| `crossbow` | Zielgerade | 1 | Schaden 110, 1,1 Schuss/s, Magazin 1, Nachladen 1,3 s, Streuung 0, Durchschlag 3 |
| `grenade_launcher` | Knalleffekt | 1 | Granate im Bogen (Schwerkraft), Treffer 60, Explosion 110 im Radius 3,0 m, 1 Schuss/s, Magazin 4, Nachladen 2,8 s |
| `flamethrower` | Heiße Phase | 2 | Kegel bis 7 m, 15 Stöße/s mit Schaden 9 an allen Zombies im Kegel, setzt in Brand (8 Schaden/s für 3 s), Magazin 100, Nachladen 3,0 s, Dauerfeuer |
| `beam` | Rotlicht | 2 | Dauerstrahl: 20 Treffer/s mit Schaden 9, geht durch alle Zombies in der Linie, Magazin 80, Nachladen 2,6 s, Streuung 0 |
| `tesla` | Kurzschluss | 2 | Schaden 45, 3 Schuss/s, jeder Treffer springt auf 3 weitere Zombies im Umkreis von 5 m mit 60 %, Magazin 12, Nachladen 2,4 s |
| `lmg` | Marathonsendung | 2 | Schaden 20, 11 Schuss/s, Dauerfeuer, Magazin 100, Nachladen 4,5 s, Streuung 2,0 |
| `auto_shotgun` | Zuschauerfrage | 2 | Schaden 11, 7 Schrotkugeln, 3 Schuss/s, Dauerfeuer, Magazin 8, Nachladen 2,6 s, Streuung 6,5 |

Gegenstände auf der Waffe (Blitz, Brand, Gift, Glücksrad und so weiter) wirken bei jedem Treffer
auch für Flammen und Strahl. Die Wandwaffen entfallen ganz: Waffen gibt es aus Kisten und als
Startwaffe des Kandidaten. `WeaponDefs.price` bleibt als Zahl stehen (für einen späteren Händler),
wird aber nirgends mehr benutzt.

### 22.3 Neue Gegenstände (acht, dazu vier Kameras und fünf Kamera-Gegenstände)

Für die Waffe auf den Sternen (wie in 19.1, gelesen mit `Game.bullet_value(weapon_uid, id, key)`):

| ID | Name | Regel | Werte |
|---|---|---|---|
| `frost` | Trockeneis | Kugeltreffer verlangsamt den Zombie für 2 s (Elite: halbe Wirkung) | `slow` 20/25/30/35/40 % |
| `opener` | Eröffnungsgag | die erste Kugel jedes Magazins macht mehr Schaden | `bonus` +100/150/200/275/350 % |
| `punchline` | Schlusspointe | die letzte Kugel jedes Magazins explodiert am Einschlag, Radius 3 m, Schaden mal `Game.effect_factor()`, Quelle `"explosion"` | `damage` 60/90/120/160/200 |
| `ricochet` | Querschläger | ein Kugeltreffer springt mit `chance` auf einen weiteren Zombie im Umkreis von 6 m, mit 60 % des Schadens | `chance` 20/30/40/50/60 % |

Für den Spieler als Ganzes:

| ID | Name | Regel | Werte |
|---|---|---|---|
| `thorns` | Kaktus-Requisite | trifft ein Zombie den Spieler, nehmen alle Zombies im Umkreis von 2,5 m Schaden mal `Game.effect_factor()`, Quelle `"thorns"` | `damage` 40/60/80/110/140 |
| `revive` | Zweite Staffel | ein tödlicher Treffer tötet nicht: 30 % Leben, 1,5 s unverwundbar, Druckwelle. Jedes Exemplar ist eine Ladung, die nach `waves` geschafften Wellen wiederkommt | `waves` 5/4/4/3/3 |
| `snack` | Pausensnack | am Wellenende zusätzliche Heilung | `heal` 10/15/20/25/35 |
| `mine` | Requisitenbombe | legt alle `interval` s eine Mine an die Füße des Spielers (höchstens 5 zugleich). Kommt ein Zombie auf 1,2 m heran, explodiert sie: Radius 3 m, Schaden mal `Game.effect_factor()`, Quelle `"mine"` | `interval` 8/7/6/5/4 s, `damage` 70/100/130/170/220 |

### 22.4 Größeres Studio, mehr Räume

- Die Bühne (Zone 1) wird in der Fläche etwa 40 % größer.
- Vier kaufbare Räume statt einem: Backstage (wie bisher), Kantine, Garderobe, Regieraum. Preise
  750, 1250, 2000 und 3000 Punkte. Jeder Raum hat eigene Zombie-Eingänge, die erst nach dem Kauf
  benutzt werden, und eigene Requisiten als Deckung.
- Beide Wandkäufe verschwinden, `scripts/game/level/wall_buy.gd` wird gelöscht.

### 22.5 Freischalten zwischen den Läufen

- **Konto:** Am Ende eines Laufs kommen alle Punkte aufs Konto, die der Spieler in diesem Lauf
  verdient hat (Treffer, Kills, Wellen). Punkte aus dem Verkauf von Gegenständen zählen nicht, und
  was im Lauf für Räume ausgegeben wurde, wird nicht abgezogen.
- **Pakete:** Mit dem Konto kauft man Pakete in beliebiger Reihenfolge. Ein Paket schaltet 4
  Gegenstände oder Waffen frei. Kisten bieten nur an, was freigeschaltet ist (Rucksack-Teile immer).
  Startgegenstände der Kandidaten und `Game.grant_item` gehen immer.
- **Von Anfang an frei:** `pistol`, `revolver`, `smg`, `shotgun`, `chain_lightning`, `pierce`,
  `burn`, `lifesteal`, `max_hp`, `corpse_explosion`, `reload_shockwave`, `drone`, `speed`, `luck`,
  `spotlight`, `speed_loader`, `piggy_bank` und die drei Rucksack-Teile.

| Paket | Name | Preis | Inhalt |
|---|---|---|---|
| `camera_team` | Kamerateam | 2000 | `cam_tele`, `cam_lens`, `cam_battery`, `cam_zoom` |
| `rapid_fire` | Schnellfeuer | 2000 | `machine_pistol`, `nail_gun`, `fire_rate`, `big_mag` |
| `first_aid` | Erste Hilfe | 2500 | `shield`, `kill_heal`, `snack`, `dash` |
| `poison_kitchen` | Giftküche | 3000 | `poison`, `frost`, `flamethrower`, `sawed_off` |
| `precision` | Präzision | 3500 | `sniper`, `crossbow`, `scope`, `crit` |
| `big_bang` | Knallbonbon | 4000 | `grenade_launcher`, `punchline`, `mine`, `extra_shot` |
| `control_room` | Regieraum-Technik | 4500 | `cam_flash`, `cam_slow`, `cam_second`, `cam_uplink` |
| `sustained_fire` | Dauerfeuer | 5000 | `rifle`, `lmg`, `burst_pistol`, `opener` |
| `high_voltage` | Hochspannung | 6000 | `tesla`, `jammer`, `ricochet`, `disco_ball` |
| `grand_finale` | Großes Finale | 8000 | `minigun`, `rocket_launcher`, `auto_shotgun`, `beam` |
| `special_broadcast` | Sondersendung | 10000 | `replay`, `revive`, `thorns`, `cam_director` |

- **Speichern:** `user://progress.cfg` (Konto, gekaufte Pakete, beste Welle, Zahl der Läufe).
  Headless wird die Datei weder gelesen noch geschrieben, und dort gilt alles als freigeschaltet
  (`unlock_all`), damit Tests den ganzen Vorrat sehen. Tests für das Freischalten schalten das ab.
- **Oberfläche:** Bildschirm „Programm“ mit Kontostand und den Paketen als Karten (Name, Preis,
  Inhalt mit Art und Kurztext, Kaufen). Erreichbar von der Kandidatenwahl und vom Game-Over-Schirm.
  Game Over zeigt, wie viel aufs Konto kam.

### 22.6 Wem welche Datei gehört (Bau in zwei Stufen)

Stufe 1, gleichzeitig:

- **Kern:** `scripts/core/*`, `scripts/autoload/*`, in `zombie.gd` nur Verlangsamung und Markierung
  (22.7), die Kern-Tests (`test_backpack`, `test_chest_roller`, `test_game_state`,
  `test_upgrade_state`, `test_weapon_state`, `test_wave_plan`, neu `test_cameras_core`,
  `test_progress`) und Abschnitt 22.7 dieses Dokuments. Außerhalb davon nur die kleinsten
  Anpassungen, damit alles lädt und die vorhandenen Tests bestehen.
- **Studio:** `scripts/game/level/*`, bei Bedarf Zombie-Eingänge in `zombie_spawner.gd` und
  `wave_manager.gd`, `tests/test_level.gd`.

Stufe 2, gleichzeitig, nach dem Kern:

- **Waffen:** `weapon_controller.gd`, `view_model.gd`, neue Dateien unter `scripts/game/player/`,
  `tests/test_player_weapons.gd`.
- **Kameras und Effekte:** `upgrade_effects.gd`, `drone.gd`, neue Dateien unter
  `scripts/game/upgrades/`, `player.gd` (nur Zweite Staffel), `tests/test_upgrade_effects.gd`,
  `tests/test_player_abilities.gd`.
- **Oberfläche:** `scripts/ui/*`, `main.gd`, `tests/test_ui.gd`, `test_backpack_screen.gd`,
  `test_character_select.gd`, neu `test_unlock_screen.gd`.
- **Ton:** `tools/make_sounds.py`, `audio/`, `scripts/game/audio/sfx.gd`, `tests/test_audio.gd`.

`scripts/game/fx/fx.gd` ändert in Stufe 2 niemand: Neue Bilder (Strahl, Flamme, Blitzlicht, Mine)
baut jedes Modul in eigenen Dateien. `tests/test_smoke_game.gd`, `perf_game.gd` und
`capture_game.gd` gehören dem Zusammenbau.

### 22.7 Schnittstellen des Kerns (Stand nach Stufe 1)

Der Kern ist gebaut und getestet (`test_cameras_core`, `test_progress`, dazu `test_backpack`,
`test_chest_roller`, `test_game_state`, `test_upgrade_state`, `test_weapon_state`,
`test_zombies_waves`). Was im Spiel schon wirkt: die Kameradrohne mit festen Werten und
Kamera-Gegenständen, Verlangsamung und Markierung am Zombie, Kisten nur mit Freigeschaltetem,
Konto und Pakete in `Game`. Alles andere aus Abschnitt 22 liegt als Daten und Regeln bereit und
ist im Spiel noch wirkungslos (Liste je Helfer am Ende). Eine neue Waffe schießt bis dahin wie
eine normale Kugelwaffe (der Granatwerfer wie ein kleiner Raketenwerfer).

#### Neue Dateien

| Datei | Inhalt |
|---|---|
| `scripts/core/camera_defs.gd` | Kameratabelle, Rechnung der fertigen Werte, Texte |
| `scripts/core/unlock_defs.gd` | Startvorrat und Pakete |
| `scripts/core/progress_state.gd` | Konto, gekaufte Pakete, beste Welle, Läufe (RefCounted) |
| `tests/test_cameras_core.gd`, `tests/test_progress.gd` | Tests dazu |

#### CameraDefs

```
ORDER       ["drone", "cam_tele", "cam_flash", "cam_slow", "cam_director"]
MOD_ORDER   ["cam_lens", "cam_zoom", "cam_battery", "cam_second", "cam_uplink"]
MOD_DAMAGE, MOD_RANGE, MOD_RATE, MOD_SECOND, MOD_UPLINK   die fünf IDs als Konstanten
SLOW_DURATION 2.0   MARK_DURATION 4.0   FLASH_CONE_DEG 90.0 (voller Winkel)
SECOND_FLASH_DELAY 0.4   MIN_INTERVAL 0.05
all_ids(), has(id), is_mod(item_id), display_name(id)
base(id, key, level) -> float     Grundwert: key "damage", "interval", "range", "pierce", "slow", "mark"
mod_total(mod_id, key, levels) -> float
stats(id, level, mods := {}, uplinks := []) -> Dictionary     die fertigen Werte (reine Funktion)
effect_text(id, level) -> String  Text mit den Grundwerten der Rarität
```

`stats` rechnet: Schaden = Grundwert × (1 + Objektive + Sendeleitungen), Abstand = Grundwert /
(1 + Akkupacks + Sendeleitungen), mindestens `MIN_INTERVAL`, Reichweite = Grundwert × (1 + Zooms),
`second` = Summe der Zweitkameras. `mods` ist `mod_id -> Array` der Raritäten, `uplinks` die
Raritäten aller Sendeleitungen. Die Stufenwerte der fünf Kamera-Gegenstände stehen in
`UpgradeDefs.UPGRADES` (Schlüssel `bonus`, bei `cam_second` `share`), weil sie die Art `upgrade` haben.

#### Einträge in `Game.cameras`

Ein Eintrag je Kamera-Exemplar, in der Reihenfolge des Erwerbs. `Game.cameras` wird in
`sync_build()` und beim Start eines Laufs neu gerechnet. Das Array wird nur ersetzt, wenn sich
etwas geändert hat: Dann kommt `Events.cameras_changed` (vor `build_changed`). Wer prüfen will, ob
er neu lesen muss, vergleicht mit `is_same`. Nur lesen.

| Schlüssel | Typ | Bedeutung |
|---|---|---|
| `key` | String | eindeutig je Exemplar: `"<uid>:<nummer>"`, die Kamera selbst hat `:0` |
| `uid` | int | uid der Kamera im Rucksack |
| `copy` | int | 0 = die Kamera selbst, ab 1 Exemplare aus Wiederholungen |
| `id` | String | Kameratyp |
| `level` | int | Rarität dieses Exemplars (bei Wiederholung höchstens deren Rarität) |
| `mods` | Dictionary | Kamera-Gegenstände auf der Kamera: `mod_id -> Array[int]` Raritäten |
| `damage` | float | Schaden je Schuss, fertig gerechnet (Regie-Kamera 0) |
| `interval` | float | Sekunden zwischen zwei Schüssen |
| `range` | float | Reichweite in Metern |
| `pierce` | int | weitere Zombies in der Linie (nur Tele, sonst 0) |
| `slow`, `slow_duration` | float | Verlangsamung als Bruchteil (nur Zeitlupe, sonst 0) und Dauer |
| `mark`, `mark_duration` | float | Mehr-Schaden als Bruchteil (nur Regie, sonst 0) und Dauer |
| `second` | float | Anteil der Wirkung fürs zweite Ziel, 0 = keine Zweitkamera |
| `cone_deg` | float | voller Öffnungswinkel (nur Blitzlicht, sonst 0) |
| `damage_bonus`, `rate_bonus`, `range_bonus` | float | die Zuschläge als Bruchteile (für die Anzeige) |

Feste Werte heißt: kein `Game.effect_factor()`, kein `companion_factor`, die Werte so nehmen, wie
sie dastehen. Eine Wiederholung auf einer Kamera ergibt ein zweites Exemplar mit denselben
Kamera-Gegenständen, eine Wiederholung auf einem Kamera-Gegenstand zählt ihn doppelt (auch die
Sendeleitung).

#### Geänderte und neue Funktionen im Kern

```
ItemDefs      KIND_CAMERA "camera", STAR_CAMERA "camera", CAMERA_COLOR
              is_camera(id), is_camera_mod(id) (Sterne zielen auf Kameras, ohne Sendeleitung)
              star_hits: STAR_CAMERA trifft Kameras, STAR_ITEM (Wiederholung) trifft Upgrade-Gegenstände
              und Kameras. has_rarity, display_name, description, subtitle ("Selten · Kamera · 2 Felder"),
              color kennen Kameras. weapon_text nennt Salve, Durchschlag, Explosion, Flamme, Strahl, Sprünge.
              ORDER hat 64 Einträge (19 Waffen, 33 Upgrade-Gegenstände, 5 Kameras, 4 Verstärker, 3 Rucksack-Teile).
BackpackState cameras() -> Array[Dictionary]   { key, uid, copy, id, level, mods }
              copy_levels(uid), mods_of(uid), star_targets(uid), is_active(uid) gelten auch für Kameras.
              Kameras stehen nicht in upgrade_levels() und global_copies(). cam_uplink steht in global_copies().
UpgradeDefs   "drone" ist entfernt (ORDER hat 9 Einträge). Neu in UPGRADES und ITEM_ONLY (24 Einträge):
              frost, opener, punchline, ricochet, thorns, revive, snack, mine, cam_lens, cam_zoom,
              cam_battery, cam_second, cam_uplink. STACK_MODES neu: "slow" max, "waves" min.
WeaponDefs    ORDER hat 19 Einträge. MODE_BULLET, MODE_GRENADE, MODE_FLAME, MODE_BEAM, PIERCE_ALL (999)
              mode(id), burst(id), burst_interval(id), pierce(id), arc_jumps(id), arc_factor(id),
              arc_radius(id), reach(id) (Schlüssel "range", sonst Balance.WEAPON_RANGE), cone_deg(id)
              (halber Winkel), burn_dps(id), burn_time(id), projectile_speed(id), projectile_gravity(id),
              is_automatic(id). dps(id) zählt alle Schüsse einer Salve.
WeaponState   burst_left, burst_wait, burst_size(), burst_interval(), is_bursting(),
              burst_shot_due(), fire_burst_shot(), cancel_burst(). start_reload() bricht die Salve ab.
ChestRoller   build_item_offers(rng, backpack, rarity, force_bag := false, recent := [], progress := null)
              Mit progress nur Freigeschaltetes (Rucksack-Teile immer), null = alles. Der sichere erste
              Eintrag ist ein Upgrade-Gegenstand oder eine Kamera.
UnlockDefs    START, PACK_ORDER, PACKS, all_pack_ids(), has_pack(id), pack_name(id), pack_price(id),
              pack_items(id), is_start_item(item_id), pack_of(item_id) ("" = in keinem Paket), start_items()
ProgressState bank, packs (Kaufreihenfolge), unlock_all, best_wave, runs
              has_pack(id), is_item_unlocked(item_id), can_buy(id), buy(id) -> bool, add_bank(n) -> int,
              record_run(wave), open_packs(), to_dict(), from_dict(data)
Balance       SLOW_ELITE_FACTOR 0.5, SLOW_MAX 0.9, FROST_DURATION 2.0, PUNCHLINE_RADIUS 3.0,
              RICOCHET_RADIUS 6.0, RICOCHET_DAMAGE_FACTOR 0.6, THORNS_RADIUS 2.5, REVIVE_HP_SHARE 0.3,
              REVIVE_INVULNERABILITY 1.5, REVIVE_SHOCKWAVE_RADIUS 6.0, REVIVE_SHOCKWAVE_KNOCKBACK 12.0,
              REVIVE_SHOCKWAVE_DAMAGE 0.0, MINE_MAX_ACTIVE 5, MINE_TRIGGER_RADIUS 1.2, MINE_RADIUS 3.0,
              CAMERA_RECOIL_KICK_DEG hat alle 19 Waffen.
```

`Game` (neu oder geändert):

```
cameras: Array[Dictionary]        siehe oben
cameras_of(camera_id) -> Array[Dictionary], camera_entry(key) -> Dictionary, camera_levels() -> Dictionary
progress: ProgressState           Fortschritt über alle Läufe
progress_file_enabled: bool       false ohne Bildschirm: dort wird nie geladen oder gespeichert
bank_points_earned: int           im Lauf verdiente Punkte fürs Konto (ohne Verkaufserlöse)
last_bank_gain: int               Gutschrift des zuletzt beendeten Laufs
buy_pack(pack_id) -> bool         kauft, speichert, sendet pack_unlocked und bank_changed(konto, -preis)
save_progress_to(path) -> bool, load_progress_from(path) -> bool   ConfigFile, Abschnitt "progress"
PROGRESS_PATH "user://progress.cfg"
get_stats()                       neu: "cameras" (Array aus { id, name, level }), "bank_gained", "bank"
sync_build()                      rechnet auch cameras neu
open_chest(rarity)                reicht progress an die Kisten weiter
grant_item(id, level)             fragt nicht nach dem Freischalten
```

- `upgrade_chosen(id, level)` kommt beim Schließen des Rucksacks jetzt auch für neue oder bessere
  Kameras (id = Kameratyp). Namen dafür mit `ItemDefs.display_name(id)` holen, nicht mit
  `UpgradeDefs.display_name`.
- `Game.upgrades` kennt die Kameradrohne nicht mehr: `get_level("drone")` ist 0, `add_levels("drone", n)`
  tut nichts. Eine Kamera kommt nur über den Rucksack ins Spiel (`backpack.add_item`, einräumen,
  `sync_build()`), so machen es jetzt auch die Tests.
- **Konto:** Gezählt wird alles, was im Lauf gutgeschrieben wird (Treffer, Kills, Wellen-Prämien,
  auch Trostpreis-Punkte, mit Punkte-Faktor), außer Verkaufserlösen. Startpunkte des Kandidaten
  zählen nicht, Ausgaben werden nicht abgezogen. Abgerechnet wird genau einmal je Lauf
  (`_settle_run`): in `end_run()` vor `game_over`, sonst beim Neustart oder Beenden aus der Pause,
  beim Schließen des Fensters oder wenn ein neuer `start_run()` einen offenen Lauf ablöst.
  `bank_changed(konto, gutschrift)` kommt dabei immer, auch mit Gutschrift 0.
- **Headless:** `progress.unlock_all = true`, die Datei wird weder gelesen noch geschrieben. Tests
  für das Freischalten setzen `Game.progress.unlock_all = false` und danach wieder `true`.

#### Signale (Events hat jetzt 43)

| Signal | Sender | Bedeutung |
|---|---|---|
| `cameras_changed` | Game | `Game.cameras` wurde ersetzt |
| `bank_changed(bank, gained)` | Game | Konto geändert: am Laufende die Gutschrift, beim Kauf der negative Preis |
| `pack_unlocked(pack_id)` | Game | Paket gekauft |
| `camera_fired(camera_id, position)` | noch niemand (Kamera-Knoten) | Schuss, Blitz oder Markierung einer Kamera, für Ton und Anzeige |
| `mine_placed(position)`, `mine_triggered(position)` | noch niemand (Requisitenbombe) | Mine gelegt, Mine ausgelöst (die Explosion kommt zusätzlich als `explosion`) |
| `player_revived` | noch niemand (`player.gd`) | Zweite Staffel hat einen tödlichen Treffer abgefangen |

#### Zombie (`zombie.gd`)

```
apply_slow(factor, duration)   factor 0.3 = 30 % langsamer. Elite: mal Balance.SLOW_ELITE_FACTOR.
                               Höchstens Balance.SLOW_MAX. Die stärkste gilt, die Zeit beginnt neu.
is_slowed() -> bool, get_speed_factor() -> float (1,0 ohne Verlangsamung)
apply_mark(bonus, duration)    Markierte nehmen aus jeder Quelle (1 + bonus) mal Schaden.
                               Die stärkste gilt, die Zeit beginnt neu.
is_marked() -> bool, get_damage_factor() -> float (1,0 ohne Markierung)
```

- Die Verlangsamung bremst nur das Laufen (`move_speed` bleibt der Grundwert), nicht den Schlag.
  Zu sehen: eisblauer Körper.
- Die Markierung rechnet `take_damage` selbst ein. `zombie_damaged` meldet den erhöhten Betrag,
  `bullet_hit` weiter den Betrag der Waffe. Wer Trefferzahlen zeigt und den echten Schaden will,
  multipliziert mit `zombie.get_damage_factor()` (vor dem Treffer lesen). Zu sehen: pinke Pyramide
  über dem Kopf (Kind `Mark`).

#### Werte der neuen Gegenstände lesen

| Gegenstand | Lesen | Feste Zahlen |
|---|---|---|
| `frost` | `Game.bullet_value(weapon_uid, "frost", "slow")`, wirkt wenn `Game.bullet_level(weapon_uid, "frost") > 0` | `Balance.FROST_DURATION` |
| `opener` | `Game.bullet_value(weapon_uid, "opener", "bonus")` (1,0 = +100 %) | |
| `punchline` | `Game.bullet_value(weapon_uid, "punchline", "damage")` mal `Game.effect_factor()` | `Balance.PUNCHLINE_RADIUS` |
| `ricochet` | `Game.bullet_value(weapon_uid, "ricochet", "chance")` | `Balance.RICOCHET_RADIUS`, `RICOCHET_DAMAGE_FACTOR` |
| `thorns` | `Game.upgrades.value("thorns", "damage")` mal `Game.effect_factor()` | `Balance.THORNS_RADIUS` |
| `revive` | `Game.upgrades.copies("revive")`: je Exemplar eine Ladung, ihre Wartezeit `UpgradeDefs.value("revive", "waves", rarität)` | `Balance.REVIVE_*` |
| `snack` | `Game.upgrades.value("snack", "heal")` | |
| `mine` | `Game.upgrades.value("mine", "interval")` (kleinster) und `("mine", "damage")` (Summe) mal `Game.effect_factor()` | `Balance.MINE_*` |
| Kamera-Gegenstände | stecken schon in `Game.cameras` | |

Mehrere Exemplare: `slow` nimmt den stärksten Wert, `chance` endet bei 100 %, `waves` und
`interval` nehmen den kleinsten, alles andere addiert sich.

#### Formen und Sternmuster (ungedreht, x nach rechts, y nach unten)

| ID | Form | Sterne |
|---|---|---|
| `drone` | 2 Felder waagerecht | |
| `cam_slow` | 1 Feld | |
| `cam_tele` | 3 Felder in einer Linie | |
| `cam_director` | L aus 3 Feldern | |
| `cam_flash` | Quadrat aus 4 Feldern | |
| `cam_lens` | 1 Feld | links und rechts (Ziel: Kamera) |
| `cam_zoom` | 2 Felder senkrecht | rechts neben beiden Feldern (Ziel: Kamera) |
| `cam_battery` | 1 Feld | links, rechts und unten (Ziel: Kamera) |
| `cam_second` | 2 Felder waagerecht | ein Feld davor, bei (2, 0) (Ziel: Kamera) |
| `cam_uplink` | L aus 3 Feldern | keine |
| `frost` | 1 Feld | drei in einer Reihe darüber |
| `opener` | L aus 3 Feldern | links und über dem Eckfeld |
| `punchline` | 2 Felder senkrecht | drei in einer Reihe darunter |
| `ricochet` | 1 Feld | rechts oben und rechts unten (übereck) |
| `thorns` | L aus 3 Feldern | keine |
| `revive` | Quadrat aus 4 Feldern | keine |
| `snack` | 1 Feld | keine |
| `mine` | 2 Felder waagerecht | keine |

Waffen: `burst_pistol` L aus 3, `nail_gun` Quadrat aus 4, `machine_pistol` L aus 3, `crossbow` T aus 4,
`grenade_launcher` L aus 4 (alle eine Hand), `flamethrower` 4 in Linie mit 2 darunter am Ende,
`beam` L aus 5, `tesla` 3 in Linie mit 2 darunter, `lmg` 4 in Linie mit 2 darunter in der Mitte,
`auto_shotgun` L aus 5 (alle zwei Hände). Nur in Silber und Gold: `beam`, `auto_shotgun`.

#### Entscheidungen über Abschnitt 22 hinaus

1. **Kameradrohne ganz aus `UpgradeDefs` entfernt** (nicht nur für Text behalten): Name, Text und
   Zahlen der Kameras stehen allein in `CameraDefs`. Sonst gäbe es zwei Tabellen für dieselbe Kamera.
2. **Formen weichen vom Vorschlag ab,** damit keine zwei Kameras dieselbe Form haben: Zeitlupe
   1 Feld, Blitzlicht 4 Felder (statt je 2). Der Akkupack hat Sterne links, rechts und unten (statt
   oben und unten): Sonst wäre er ein gedrehtes Objektiv.
3. **Zuschläge addieren sich:** Objektiv und Sendeleitung beim Schaden, Akkupack und Sendeleitung
   bei der Schussfolge. Die Zweitkamera hat keinen Deckel: Zwei legendäre geben dem zweiten Ziel 200 %.
4. **Wiederholung auf einer Kamera:** Das zweite Exemplar hat dieselben Kamera-Gegenstände.
5. **Verlangsamung:** höchstens 90 %, sie bremst nur das Laufen.
6. **Was in keinem Paket steht, gilt als frei** (`ProgressState.is_item_unlocked`). Der Test in
   `test_progress.gd` stellt sicher, dass jeder Gegenstand genau ein Zuhause hat.
7. **Konto:** Abrechnung auch bei Abbruch des Laufs (siehe oben), Trostpreis-Punkte zählen mit.
8. **Salve:** `fire_rate` zählt Salven je Sekunde. Der Schnelldurchlauf verkürzt auch den Abstand
   in der Salve. Reicht das Magazin nicht, ist die Salve kürzer.
9. **Zahlen, die 22.2 offen ließ** (alle in `weapon_defs.gd`): Preise der neuen Waffen, Streuung von
   Granatwerfer (0,5) und Kurzschluss (0,6), halber Flammenwinkel 14 Grad, Granate 22 m/s bei
   Schwerkraft 12 m/s², Kurzschluss ohne Dauerfeuer.
10. **Zweite Staffel:** Die Druckwelle stößt nur weg (Radius 6 m, 12 m/s, kein Schaden).
11. **Requisitenbombe mit mehreren Exemplaren:** kürzester Abstand, Schaden addiert sich (wie beim
    Störsender). Es bleibt bei höchstens 5 Minen.

Abschnitte 22.1 bis 22.6 sind unverändert.

#### Kleinste Anpassungen außerhalb des Kerns (damit alles lädt und die Tests bestehen)

- `drone.gd`: liest Schaden, Abstand und Reichweite aus ihrem Eintrag (`stats`, `set_stats(entry)`,
  `get_range()`, Konstante `CAMERA_ID`). Ohne Eintrag gelten die Grundwerte ihrer Rarität.
- `upgrade_effects.gd`: eine Drohne je Eintrag aus `Game.cameras_of("drone")`, die Einträge werden
  zugeteilt, sobald sich `Game.cameras` ändert (`_assign_drone_stats`).
- `backpack_screen.gd`: nur die Tabelle `NAME_HYPHENS` (Trennstellen für die neuen Namen).
- `chest_choice.gd`: Die Karte einer Kamera nennt „Kamera · …“ statt „Verstärker · …“.
- `view_model.gd`: `_build_placeholder(slot, id)`, ein schlichtes Platzhalter-Modell für jede
  Waffe ohne eigenes Modell (kurz für eine Hand, lang für zwei). Ohne Eintrag in `RECOIL` hat
  eine Waffe dort weder Rückstoß noch Mündungsfeuer.
- Tests: `test_upgrade_effects.gd` (Drohne über den Rucksack, feste Werte), `test_backpack_screen.gd`
  (Hilfsfunktion `_level` kennt Kameras), `test_smoke_game.gd` (Drohne über den Rucksack),
  `test_ui.gd` (Kartentext gegen `ItemDefs.description` statt `UpgradeDefs.effect_text`: Bei
  Stern-Gegenständen hängt der Hinweis auf die Sterne daran. Kamera-Karten heißen „Kamera“).

#### Was die Helfer der Stufe 2 noch bauen

**Waffen** (`weapon_controller.gd`, `view_model.gd`):

- Salve über `WeaponState`: nach `tick()` in einer Schleife `burst_shot_due()` und je Schuss
  `fire_burst_shot()`. Ohne das gibt der Dreierpack nur einen Schuss je Abzug.
- `MODE_GRENADE`: Geschoss im Bogen (`projectile_speed`, `projectile_gravity`), am Einschlag
  Treffer `damage` und Explosion (`explosion_damage`, `explosion_radius`, `Events.explosion`).
- `MODE_FLAME`: je Stoß alle Zombies im Kegel (`reach`, `cone_deg` als halber Winkel) mit `damage`,
  dazu Brand über `zombie.apply_burn(WeaponDefs.burn_dps(id), WeaponDefs.burn_time(id))` (fester Wert).
- `MODE_BEAM`: je Treffer alle Zombies in der Linie (`pierce` = `PIERCE_ALL`).
- Eingebauter Durchschlag `WeaponDefs.pierce(id)`: addiert sich zu `Game.bullet_value(uid, "pierce",
  "targets")`. Vorschlag: Schadensverlust wie bisher (`pierce_damage_factor`), beim Strahl keiner.
- Eingebauter Blitz (Kurzschluss): `arc_jumps`, `arc_factor`, `arc_radius`, Quelle `"lightning"`.
- Flamme und Strahl melden jeden Treffer als `bullet_hit` mit `weapon_uid`, damit die Gegenstände
  auf der Waffe wirken.
- `opener` (erste Kugel jedes Magazins) und `punchline` (letzte Kugel, Explosion mit der Quelle
  `"explosion"`): Beide brauchen den Magazinstand, deshalb hier.
- Modelle für die zehn neuen Waffen statt der Platzhalter, dazu ihre Einträge in `RECOIL` und
  `WEAPON_OFFSETS`. Der Kamera-Rückstoß steht schon in `Balance.CAMERA_RECOIL_KICK_DEG`.

**Kameras und Effekte** (`upgrade_effects.gd`, `drone.gd`, neue Dateien, `player.gd` nur Zweite Staffel):

- Knoten für `cam_tele`, `cam_flash`, `cam_slow`, `cam_director`: je Eintrag aus `Game.cameras` einer,
  Werte nur aus dem Eintrag. Schadensquelle = Kameratyp (`"drone"` bleibt, dazu `"cam_tele"`,
  `"cam_flash"`, `"cam_slow"`). Zeitlupe über `zombie.apply_slow(slow, slow_duration)`, Regie über
  `zombie.apply_mark(mark, mark_duration)` (zuerst Elite, dann Unmarkierte).
- `second` > 0: zweites Ziel mit diesem Anteil der Wirkung (Blitzlicht: zweiter Blitz nach
  `CameraDefs.SECOND_FLASH_DELAY`). Gilt auch für die Drohne.
- `Events.camera_fired(camera_id, position)` bei jedem Schuss senden, auch in `drone.gd`.
- `frost` (bei `bullet_hit`: `apply_slow`), `ricochet` (bei `bullet_hit`: zweiter Zombie mit der
  Quelle `"ricochet"`, löst selbst nichts weiter aus), `thorns` (bei `player_damaged`, Quelle
  `"thorns"`), `snack` (bei `wave_cleared`), `mine` (Quelle `"mine"`, `mine_placed`, `mine_triggered`,
  `explosion`), `revive` (in `player.gd`, `player_revived`, Ladungen je Exemplar).

**Oberfläche** (`scripts/ui/*`, `main.gd`):

- Bildschirm „Programm“: `Game.progress`, `UnlockDefs`, `Game.buy_pack(id)`, Signale `bank_changed`
  und `pack_unlocked`. Game Over zeigt `stats["bank_gained"]` und `stats["bank"]`.
- Kameras sind keine Upgrades mehr: Sie fehlen deshalb in der Upgrade-Leiste des HUD und in der
  Upgrade-Liste von Game Over (dort `Game.cameras`, `Game.camera_levels()` oder `stats["cameras"]`
  nehmen). `hud.make_upgrade_row` holt Namen mit `UpgradeDefs.display_name`: für Kameras
  `ItemDefs.display_name` nehmen.
- `chest_choice.gd`: Eine Kamera zeigt auf ihrer Karte die Form statt eines gezeichneten Bilds
  (auch die Kameradrohne, die früher ihr Bild hatte). Die Zeile darunter nennt schon „Kamera · …“.
- `backpack_screen.gd`: Hinweise für Kamera-Gegenstände („Stern auf eine Kamera legen“ statt
  „auf eine Waffe“), für die Wiederholung auf Kameras, „Darauf wirken“ bei Kameras
  (`pack.mods_of(uid)`), fertige Werte einer Kamera aus `Game.camera_entry(key)`, Bilder für die
  neuen Gegenstände.
- Anzeige für die Ladungen der Zweiten Staffel, wenn der Effekte-Helfer sie anbietet.

**Ton** (`sfx.gd`, `tools/make_sounds.py`):

- Neue Signale: `camera_fired` (je Kameratyp), `mine_placed`, `mine_triggered`, `player_revived`,
  `pack_unlocked`, `bank_changed`.
- `weapon_fired(weapon_id)` kommt für zehn neue Waffen-IDs (Flamme und Strahl bis zu 20 Mal je Sekunde).
- Neue Schadensquellen in `zombie_damaged`: `"cam_tele"`, `"cam_flash"`, `"cam_slow"`, `"ricochet"`,
  `"thorns"`, `"mine"`.

**Zusammenbau:** `tests/capture_game.gd` und `tests/perf_game.gd` setzen die Drohne noch mit
`_set_upgrades({"drone": n})`: Das erzeugt keine Drohne mehr (kein Fehler, sie fehlt nur). Dort wie
in `test_smoke_game.gd` die Kamera in den Rucksack legen und `Game.sync_build()` rufen.

## 23. Größeres Studio und kaufbare Räume (Stand 2026-11-21)

Setzt 22.4 um. Dieser Abschnitt gilt vor Abschnitt 9 und vor dem Teil „LevelBuilder“, „Door“ und
„WallBuy“ in 13.6, wo sie sich widersprechen (Liste in 23.8).

### 23.1 Grundriss

Achsen wie bisher: +X ist rechts (Osten), +Z zeigt zum Publikum (Süden), der Spieler schaut am
Anfang nach −Z. Alle Räume sind 5 m hoch, die Wände 0,4 m dick.

| Zone | Name | Innenmaße | Lage (x von..bis, z von..bis) | Preis |
|---|---|---|---|---|
| 1 | Bühne | 26,5 × 21 m | −13,25..13,25, −10,5..10,5 | – |
| 2 | Backstage | 14 × 12 m | 13,65..27,65, −1,5..10,5 (Südost) | 750 |
| 3 | Kantine | 14 × 12 m | −27,65..−13,65, −1,5..10,5 (Südwest) | 1250 |
| 4 | Garderobe | 14 × 12 m | 13,65..27,65, −13,9..−1,9 (Nordost) | 2000 |
| 5 | Regieraum | 14 × 12 m | −27,65..−13,65, −13,9..−1,9 (Nordwest) | 3000 |

- Die Bühne hatte 22 × 18 m (396 m²), jetzt 26,5 × 21 m (556,5 m², plus 40,5 %). Das Podest ist
  14 × 5 m groß (vorher 12 × 4,5 m), 0,4 m hoch, mit Showtreppe vorn und je einer Rampe links und
  rechts.
- `player_spawn` bleibt (0, 0, 5). Die Kulissen in der Raummitte (zwei Stellwände, zwei
  Kandidatenpulte) stehen an ihren alten Plätzen, damit Tests mit festen Koordinaten weiter
  stimmen. Neu auf der Bühne: das Geschenk „HAUPTGEWINN“ (−9,45, −2,2) und das Glücksrad
  (9,65, 6,5). Die zwei Studiokameras stehen jetzt bei (−8,4, 7,9) und (6,4, 8,3).
- Die beiden hinteren Räume ragen 3,4 m nach Norden über die Bühne hinaus.
- Jeder Raum hat eigene Farben und Requisiten: Backstage (grau-blau, Kisten, Flightcases,
  Kabeltrommel, Requisitenregal, Scheinwerfer auf Stativ), Kantine (Karo in Creme und Orange,
  Essensausgabe mit Tafel „HEUTE: KOPFSALAT“, Kühlschrank, vier Stehtische, zwei Automaten,
  Tablettwagen, Getränkekisten), Garderobe (Streifen in Rosa, zwei Kleiderständer, zwei
  Schminktische mit Spiegel, Paravent, Schrank, Hutschachteln, Schild „NUR FÜR STARS“), Regieraum
  (dunkelblau, Monitorwand mit „AUF SENDUNG“, Regiepult, vier Serverschränke, Bandarchiv,
  Kabeltrommel).
- Regel für Requisiten: Alles mit Kollision ist mindestens 0,9 m hoch. Der Spieler springt 0,84 m,
  Zombies hüpfen 0,65 m, so entsteht kein Platz, auf den nur der Spieler kommt. Die Mitte jedes
  Raums (7 m von der Bühnenwand, 6 m von der Nordwand) bleibt frei.

### 23.2 Türen

Sechs Türen, alle `door.gd`, alle in der neuen Gruppe `doors`:

| Knoten unter `Level` | Lage (x, z) | verkauft |
|---|---|---|
| `Door` | (13,45, 4) Ostwand der Bühne | Backstage, 750 |
| `DoorCanteen` | (−13,45, 4) Westwand | Kantine, 1250 |
| `DoorWardrobe` | (13,45, −6) Ostwand | Garderobe, 2000 |
| `DoorControlRoom` | (−13,45, −6) Westwand | Regieraum, 3000 |
| `LinkEast` | (20,65, −1,7) Wand zwischen Backstage und Garderobe | den Raum, der noch zu ist |
| `LinkWest` | (−20,65, −1,7) Wand zwischen Kantine und Regieraum | den Raum, der noch zu ist |

- Alle vier Räume sind direkt von der Bühne aus kaufbar. Über jeder Tür hängt auf der Bühne ein
  Schild mit dem Raumnamen in der Farbe des Raums, das Türblatt nennt Raum und Preis.
- Wird ein Raum gekauft (an welcher seiner Türen auch immer), gehen alle Türen dieses Raums auf,
  seine Spawnpunkte werden aktiv, es kommt genau ein Banner „<Raum> ist offen!“.
- Eine Verbindungstür geht erst auf, wenn beide Räume gekauft sind. Ist einer offen, verkauft sie
  den anderen zu dessen Preis (Hinweis, Türblatt und `cost` wechseln mit). So entsteht je Seite
  ein Rundweg Bühne – vorderer Raum – hinterer Raum – Bühne.
- `door.gd`, neu: `const GROUP_DOORS`, `signal closed`, `var back_zone: int` (0 = keine
  Verbindungstür), `var back_zone_name: String`, `var back_cost: int`,
  `func zone_opened(opened_zone: int) -> void` (Meldung an jede Tür, ruft `open()` selbst auf).
  `zone`, `zone_name` und `cost` nennen immer den Raum, den es an dieser Tür gerade zu kaufen gibt.
  `open()` öffnet den Raum der Tür ohne Bezahlung, `close()` läuft bei `run_started` und stellt
  auch die Belegung einer Verbindungstür zurück. `is_open`, `opened`, `get_prompt()`,
  `interact()`, `size` sind unverändert.

### 23.3 Zombie-Eingänge

Elf Eingänge (`Entrances/Entrance_A` bis `Entrance_K` mit `Spawn_A` bis `Spawn_K`), gebaut wie
bisher (4,5 m langer Gang, Spieler-Sperre auf Lage 6, Warnlampe, Schild „AUFTRITT ZOMBIES“):

| Zone | Eingänge |
|---|---|
| 1 Bühne | A Showtor in der Rückwand auf Bühnenhöhe (x 0), B Südwand ganz im Westen (x −11,25), C Rückwand ganz im Osten (x 11,25) |
| 2 Backstage | D Südwand (x 18,65), E Ostwand (z 7,0) |
| 3 Kantine | F Südwand (x −18,65), G Westwand (z 7,0) |
| 4 Garderobe | H Nordwand (x 23,15), I Ostwand (z −10,4) |
| 5 Regieraum | J Nordwand (x −23,15), K Westwand (z −10,4) |

Meta `zone` ist 1 bis 5, Meta `active` ist nur in Zone 1 von Anfang an wahr. `zombie_spawner.gd`
und `wave_manager.gd` brauchten keine Änderung an der Logik (nur Kommentare im Spawner).
Die Eingänge B und C liegen nicht mehr in der West- und Ostwand, weil dort jetzt die Türen sind.

### 23.4 Navigation

- Gebacken wird weiter einmal und synchron aus der Gruppe `nav_source` (gemessen 34 ms für das
  ganze Studio). Danach verteilt `StudioShow.bake()` die Flächen auf fünf Regionen: `NavRegion`
  (Bühne, immer an) und `NavRegion2` bis `NavRegion5` (je Raum samt seiner Gänge). Alle Regionen
  teilen dieselben Eckpunkte und schließen an den Türen lückenlos an.
- Die Region eines Raums ist nur an, solange er gekauft ist. Kein Zombie plant einen Weg durch
  eine geschlossene Tür, auch nicht den kürzeren durch einen fremden Raum.
- Flächen mit einer Ecke in der Bühne gehören zur Bühne (auch der Streifen durch eine Türöffnung),
  sonst entscheidet der Mittelpunkt.
- Das Level stellt die Navigationskarte auf synchrones Abgleichen
  (`NavigationServer3D.map_set_use_async_iterations(map, false)`): Ein gekaufter Raum ist nach
  3 Physik-Schritten erreichbar, mit und ohne `--fixed-fps` (vorher 4 bis 9).
- Die Türen gehören weiter nicht zu `nav_source`.

### 23.5 Sichtbarkeit und Licht

- Ein Raum, seine Gänge und seine Lichter sind ausgeblendet, bis er gekauft ist (Knoten `ZoneN`,
  `Entrance_X`, Lichter). Die Wand zwischen zwei Räumen einer Seite liegt unter `Partitions` und
  ist immer zu sehen.
- Lichter: 23 Punktlichter und 4 Scheinwerfer, wenn alles offen ist (am Anfang 9 und 4). Je Raum
  ein Deckenlicht in seiner Farbe und das grüne Licht in jedem Gang, dazu ein Schminklicht in der
  Garderobe und ein Monitorlicht im Regieraum. Der Compatibility-Renderer zeigt höchstens 32
  Punktlichter und Scheinwerfer je Bild und 8 je Mesh, deshalb ein Deckenlicht je Raum statt zwei
  und zwölf Mesh-Stücke für den Bühnenboden.
- Die Geometrie aller Räume liegt auf Render-Ebene 2 (kühles Hauptlicht `KeyCool`).

### 23.6 `level_info` und Knoten

`LevelBuilder.build` liefert jetzt fünf Schlüssel. Die drei alten sind unverändert:

- `player_spawn: Vector3`, `nav_region: NavigationRegion3D` (Netz der Bühne), `door: Node3D`
  (Tür zum Backstage, Knoten `Level/Door`).
- Neu `rooms: Array[Dictionary]`, nach Preis geordnet, je Raum: `zone` (int), `key`
  (`backstage`, `canteen`, `wardrobe`, `control_room`), `name`, `cost`, `door` (Tür an der
  Bühne), `nav_region`, `center` (Bodenmitte in Weltkoordinaten), `size` (Innenmaße).
- Neu `links: Array[Node3D]` (die beiden Verbindungstüren).

Knoten unter `Level`: `NavRegion`, `NavRegion2` bis `NavRegion5`, `Door`, `DoorCanteen`,
`DoorWardrobe`, `DoorControlRoom`, `LinkEast`, `LinkWest`, `Show`, `Environment`, `Lights`,
`Zone1` bis `Zone5`, `Partitions`, `Audience`, `Entrances`.

`StudioShow` (Knoten `Show`), neu: `zone_doors`, `zone_regions`, `zone_nodes`, `zone_warn`
(Dictionary, Schlüssel = Zone), `stage_rect`, `zone_rects`, `func is_zone_open(zone: int) -> bool`.
`warn_zone2` gibt es nicht mehr.

### 23.7 Konstanten

- `balance.gd`: `DOOR_COSTS: Array[int] = [DOOR_COST, 1250, 2000, 3000]` (Zonen 2 bis 5),
  `DOOR_COST` bleibt 750. `ZONE1_SIZE` ist jetzt (26,5, 5, 21). `ZONE2_SIZE` (14, 5, 12) gilt für
  jeden kaufbaren Raum.
- `level_builder.gd`, neu: `ROOMS` (Tabelle der Räume: Zone, Schlüssel, Name, Türknoten, Seite,
  Reihe, Eingänge, Farbe), `DOOR_BACK_Z = -6`, `LINK_DOOR_INSET = 7`, `PLAYER_SPAWN_Z = 5`,
  `STAGE_ENTRANCE_INSET = 2`, `CLADDING = 0,04`, `SHOW_SIGN_WIDTH = 12`, `ROOM_LIGHT_RANGE = 13`,
  dazu die Farben der drei neuen Räume. Geändert: `STAGE_DEPTH` 4,5 → 5, `STAGE_HALF_WIDTH` 6 → 7.
  Requisiten eines Raums stehen in Raum-Koordinaten (`_room_point(room, u, v)`: u = Abstand von
  der Bühnenwand, v = Abstand von der Nordwand), so gelten sie östlich und westlich gleich.

### 23.8 Was sich gegenüber den Abschnitten 9, 13 und 14 ändert

- Wandkäufe gibt es nicht mehr: `wall_buy.gd` ist gelöscht, die Knoten `WallBuy_shotgun` und
  `WallBuy_smg` fehlen, der Teil „WallBuy“ in 13.6 und „Wandkauf“ in 14.1 entfallen. In Abschnitt 3
  (Ordner), 13.1 und 18.3 steht die Datei noch.
- Abschnitt 9: Maße der Bühne, Lage und Zahl der Eingänge (11 statt 5), Zahl der Zonen (5 statt
  2), „eine NavigationRegion3D“ (jetzt fünf), Rückgabe von `build` (fünf Schlüssel).
- 13.6 „LevelBuilder“: Grundriss, Knotennamen, Eingänge, Licht. „Door“: Eine Tür öffnet nur noch
  die Spawnpunkte ihres eigenen Raums, dazu Verbindungstüren und `closed`.
- 14.1: „Backstage liegt östlich“ stimmt weiter, es liegt jetzt in der Südhälfte der Ostseite.
- 14.4: Requisiten stehen weiter an festen Stellen, in den Räumen aber relativ zum Raum. Dass
  kein begehbarer Fleck abgeschnitten ist und unter jedem Fleck Boden liegt, prüft
  `test_level.gd` jetzt mit einer Füll-Probe im Raster von 0,25 m.
- 13.2 (`main.gd`) braucht keine Änderung. Der Kommentar an `level_info` in `main.gd` nennt noch
  drei Schlüssel.

### 23.9 Stand der Prüfung

- `tests/test_level.gd`: 859 Prüfungen, bestanden mit und ohne `--fixed-fps 60`. Neu geprüft:
  Zahl und Preise der Türen, Spawnpunkte je Zone erst nach dem Kauf aktiv, kein Pfad in einen
  geschlossenen Raum, jeder offene Raum von der Bühne erreichbar und zurück, Kauf an der
  Verbindungstür in beiden Reihenfolgen, Rundweg mit einem Läufer in Spielergröße, echte Zombies
  (`zombie.gd`) aus sieben Gängen finden in die Garderobe und zum Spielerstart, kein Wandkauf
  mehr, Spielerstart frei, kein Loch nach draußen, Boden unter jedem begehbaren Fleck, neuer Lauf.
- `tests/test_zombies_waves.gd` (238 Prüfungen) und `tests/check_scripts.gd` (41 Skripte) bestehen
  unverändert.
- `tests/test_smoke_game.gd` hat neun Prüfungen, die den alten Stand erwarten (5 Spawnpunkte, alle
  Spawnpunkte aktiv nach der Backstage-Tür, zwei Wandkäufe). `tests/capture_game.gd` greift auf
  `Level/WallBuy_shotgun` und `Level/WallBuy_smg` zu. Beides gehört dem Zusammenbau.
- Mit Grafik angesehen (45 Bilder `_shots/studio_*.png`): Bühne, alle Türen, jeder Raum aus
  mehreren Richtungen, Draufsicht ohne Decken. Von Hand gespielt hat das neue Studio niemand.

## 24. Ausbau 3: Stand nach dem Zusammenbau (Stand 2026-11-21)

Alles aus Abschnitt 22 ist gebaut. Die Liste „Was die Helfer der Stufe 2 noch bauen“ in 22.7 ist
damit erledigt. Dieser Abschnitt nennt, was dabei über 22 und 23 hinaus entstanden ist.

### 24.1 Waffen (`weapon_controller.gd`, `view_model.gd`, neu `grenade.gd`, `beam_fx.gd`, `flame_fx.gd`)

- Salve, Granate im Bogen, Flamme im Kegel, Dauerstrahl, eingebauter Durchschlag und eingebauter
  Blitz arbeiten wie in 22.2 und 22.7 beschrieben. Alle zehn Waffen haben eigene Modelle.
- `WeaponController.get_stream(hand_index := 0) -> Node3D`: Bild von Strahl oder Flamme der Hand.
- Treffer-`info` hat zusätzlich `mode`, `opener`, `scored` (gab Treffer-Punkte), ein Blitzsprung
  `arc: true`, die Explosion der Schlusspointe `punchline: true`.
- **Punkte bei Flamme und Strahl:** Je Schuss zählt nur der erste getroffene Zombie als `"bullet"`
  (mit Punkten). Alle weiteren nehmen denselben Schaden mit der Quelle `"flame"` oder `"beam"`.
  `bullet_hit` kommt für alle, damit Gegenstände auf der Waffe wirken.
- **Eröffnungsgag:** gilt für den Schuss aus dem vollen Magazin, samt Zusatzkugel, Explosion und
  Blitzsprüngen dieses Schusses. **Schlusspointe:** der Schuss, der das Magazin leert, explodiert
  einmal am ersten Einschlag, ein Schuss ins Leere nicht. Bei Waffen mit einem Schuss je Magazin
  (Zielgerade, Showfinale) wirken beide bei jedem Schuss.
- Kein Mündungsfeuer bei Flamme, Strahl und Armbrust (`ViewModel.NO_MUZZLE_FLASH`).

### 24.2 Kameras und Effekte (`upgrade_effects.gd`, `drone.gd`, neu `camera_base.gd`, `cam_tele.gd`, `cam_flash.gd`, `cam_slow.gd`, `cam_director.gd`, `mine.gd`, `upgrade_fx.gd`)

- Ein Knoten je Eintrag aus `Game.cameras`, neu zugeteilt bei `cameras_changed`. Die Kameras teilen
  sich die Plätze um den Spieler (erst Drohnen, dann Tele, Blitzlicht, Zeitlupe, Regie).
  `upgrade_effects.cameras` (alle Knoten), `camera_nodes(camera_id)`, Gruppe `"cameras"`.
- Tele-Linie und Blitz-Kegel zählen in der Waagerechten (die Kameras schweben über den Köpfen).
  Jeder Durchschlag der Tele-Kamera macht vollen Schaden, eine Wand beendet den Schuss.
- Zeitlupe wählt zuerst nicht verlangsamte Zombies. Regie hält eine Elite dauerhaft markiert.
- **Minen:** erst nach `Mine.ARM_TIME` (0,6 s) scharf, eine neue braucht 1,0 m Abstand zu jeder
  liegenden (`MINE_MIN_SPACING`): Wer stehen bleibt, bekommt eine Mine statt fünf auf einem Fleck.
  `upgrade_effects.get_mine_count()`, `get_mine_time_left()`, Liste `mines`.
- **Kaktus-Requisite** wirkt einen Physik-Schritt nach dem Treffer.
- **Zweite Staffel** (`player.gd`): `revive_charges`, `max_revive_charges`,
  `get_revive_waves_left() -> Array[int]`. Signal `Events.revive_charges_changed(charges, max)`
  (Events hat damit 44 Signale). Neue Ladungen kommen leer an.
- Querschläger würfelt je Treffer und prüft keine Sichtlinie (wie der Kettenblitz).

### 24.3 Oberfläche (`scripts/ui/*`, `main.gd`)

- **Programm:** `scripts/ui/unlock_screen.gd`, Knoten `Main/UnlockScreen` (Ebene 45,
  `main.unlock_screen`). Elf Karten im Raster, rechts eine Tafel zum markierten Paket. Ein Klick auf
  die Karte markiert nur, gekauft wird mit dem Knopf, Enter oder Leertaste. `open()`, `close()`,
  Signal `closed`, `is_open()`, `select(pack_id)`, `buy(pack_id)`, `request_buy(pack_id)`, statisch
  `pack_state(id)` (`"owned"`, `"buyable"`, `"locked"`), `missing_points(id)`.
- Kandidatenwahl und Game Over: Knopf „Programm“ und Taste P (`open_program()`,
  Signal `program_requested`). Game Over zeigt „Aufs Konto“ und „Kontostand“ und nennt Kameras im Build.
- HUD: Kameras als Zeilen in der Buff-Anzeige (`camera_entries`), Ladungen der Zweiten Staffel
  (`revive_box`, `revive_pips`). Rucksack: fertige Werte einer Kamera (`camera_stats_text(entry)`),
  „Darauf wirken“, eigene Hinweise für Kamera-Zubehör.

### 24.4 Ton

61 Dateien statt 40 (zehn Schüsse, vier Kameratypen, Mine gelegt und ausgelöst, Zweite Staffel,
Paketkauf, Gutschrift `bank_coins`, Querschläger, Kaktus). Der Drohnenschuss kommt jetzt über
`camera_fired`. Flamme und Strahl sind 0,4 s lange gleichförmige Stücke, die sich überlappen
(`STREAM_GAP` 0,12 s), ihr Treffer-Ton ist gedrosselt.

### 24.5 Zusammenbau und Prüfung

- `run_tests.ps1`: 21 Dateien, alle bestanden (neu: `test_cameras_core`, `test_progress`,
  `test_unlock_screen`).
- `tests/perf_game.gd` misst jetzt die zehn neuen Waffen, Gegenstände an der Waffe (`_attach`
  legt sie so, dass der Stern trifft), alle Kameratypen, Minen und eine Welle mit sechs Waffen.
  Ergebnis: kein Shader-Ruckler, 21 Material-Arten in `data/shader_warmup.json`. Ein Waffenwechsel
  mit vollem Rucksack kostet ein Bild von etwa 30 ms (`sync_build`): Im Spiel passiert das nur beim
  Schließen des Rucksacks.
- `perf_game.gd` und `capture_game.gd` schalten `Game.progress_file_enabled` ab: Werkzeuge fassen
  den echten Spielstand nie an. Wer mit Bildschirm Proben fährt, tut das auch.
- Einmal mit Bildschirm durchgespielt (Probe, kein Test im Repo): Kisten bieten im frischen Spiel
  nur den Startvorrat, Raumkauf, Welle mit Kameras, Game Over mit Gutschrift, Paketkauf,
  `user://progress.cfg` wird geschrieben und enthält Konto, Pakete, beste Welle und Läufe.

### 24.6 Bauchtasche (Nachtrag 2026-11-21)

Viertes Rucksack-Teil `bag_tiny` (Bauchtasche): genau ein Feld, Gewicht 5, in jeder Kiste
möglich, von Anfang an frei (`UnlockDefs.START`), Verkaufswert wie die anderen Rucksack-Teile.
`ItemDefs.ORDER` hat damit 65 Einträge (4 Rucksack-Teile).

### 24.7 Offen

- Nichts davon ist von einem Menschen gespielt oder angehört. Balance der festen Kamerawerte, der
  neuen Waffen, der Paketpreise und der Kisten-Mischung mit 64 Gegenständen ist nur gerechnet.
- Zwei Quotenhammer beidhändig sind weiter stärker als jede Zweihandwaffe.
- Ab der neunten Kamera ragen Kameras in die oberen Bildecken.
- Abschnitt 13.2 (Baum in `main.gd`), 13.6 und 21 sind älter als dieser Stand: Bei Widerspruch
  gelten 22 bis 24.

## 25. Neue Anordnung des Rucksack-Bildschirms, Kombinieren in der Ablage (Stand 2026-11-21)

Vom Nutzer gewünscht: der Rucksack-Bildschirm in der Aufteilung, die Spiele mit Raster-Rucksack
üblich haben (Ablage als Regal links, Rucksack in der Mitte, Karte am Gegenstand). Regeln und
Bedienung sind gleich geblieben. Wo ältere Abschnitte (16, 18, 22.7, 24.3) eine feste Info-Tafel
rechts oder eine Ablage-Zeile unten beschreiben, gilt dieser Abschnitt.

### 25.1 Aufbau (`scripts/ui/backpack_screen.gd`)

- **Oben:** Leiste mit Titel links, den beiden Händen in der Mitte, Punkten und Knopf „?“ rechts.
- **Links:** die Ablage als Regal mit „ABLAGE n / 5“. Die Gegenstände liegen untereinander in
  echter Form mit Raritäts-Kästchen, der Name steht daneben. Bei viel Inhalt werden erst die
  Felder kleiner, dann die Abstände, zuletzt entfallen die Namen. Zeilen über der Grenze sind rot.
- **Mitte:** der Rucksack, Feldgröße 96 px. Gezeichnet sind nur vorhandene Felder als eine Fläche
  mit Umriss. Mögliche neue Felder erscheinen blass nur, solange ein Rucksack-Teil gehalten wird.
  Darunter eine Zeile „Freie Felder · Hände · Bonus“.
- **Rechts unten:** das Feld „VERKAUFEN“, kleiner als früher, weiter zum Draufziehen.
- **Unten:** Leiste mit Tastenhinweisen, der Warnung „Noch N Gegenstände aus der Ablage räumen“
  und „FERTIG“.
- **Karte am Gegenstand:** erscheint neben dem Gegenstand unter der Maus oder in der Hand, immer
  ganz im Bild und nie auf ihm. Sie wählt zuerst eine Seite, die seine Sternfelder frei lässt.
  Inhalt: Name, Zeile „Rarität · Art · Felder“, Wertebalken, Wirkung, „Darauf wirken“,
  Schlagworte, Verkaufswert (alles aus `describe(uid)`).
- **Wertebalken:** Waffen gegen den besten Wert aller Waffen (Schaden, Schüsse je Sekunde,
  Magazin, Nachladen), Kameras gegen den besten Grundwert aller Kameras derselben Rarität
  (Schaden, Schussfolge, Reichweite).
- **Hilfe:** „So geht es“ ist eine Tafel, die Knopf „?“, F1 oder H ein- und ausblenden. Beim
  ersten Öffnen des Rucksacks in einem Programmlauf steht sie von selbst da.

### 25.2 Schnittstelle

- Unverändert: `board`, `request_close`, `describe`, `camera_stats_text`, `star_marks`,
  `hand_slots`, `drop_at`, `drop_preview`, `item_at`, `cell_rect`, `grid_rect`, `storage_area`,
  `sell_rect`, die Labels `stats_label`, `hands_label`, `storage_label`, `warning_label`,
  `hint_label`, `done_button`.
- Ersetzt: `info_*_label` durch `card_name_label`, `card_subtitle_label`, `card_text_label`,
  `card_extra_label`, `card_sell_label`, dazu `card`, `card_tags_label`, `card_bars_box`.
- Neu: `is_card_open()`, `card_uid()`, `card_rect()`, `card_text()`, `card_bars()`,
  `stat_bars(uid)`, `help_panel`, `is_help_open()`, `set_help_open(bool)`, `toggle_help()`,
  `grid_origin()`, `pack_rect()`, `drawn_cells()`, `ghost_cells()`, `shelf_layout()`,
  `item_rect(uid)`, `overflow_text()`, `drop_on_storage_item(target_uid)`, `storage_merge_target()`.
- `storage_rect(index)` ist jetzt die Zeile im Regal.

### 25.3 Kombinieren in der Ablage

Zwei gleiche Gegenstände gleicher Rarität lassen sich auch kombinieren, wenn sie in der Ablage
liegen: Ablage auf Ablage, Raster auf Ablage, Ablage auf Raster. Das Ergebnis bleibt, wo das Ziel
lag. Rucksack-Teile und Legendäre bleiben ausgenommen.

- Kern (`backpack_state.gd`): `can_merge(uid, target_uid)`, `merge(uid, target_uid)` nimmt auch
  ein Ziel in der Ablage, `find_storage_merge_partner(uid)`. `merge_target(uid, cell)` und
  `find_merge_partner(uid)` gelten weiter nur für das Raster, das selbsttätige Einräumen
  (`Game._auto_pack`) kombiniert also weiter nur mit Eingeräumtem.
- Bildschirm: Loslassen auf einem passenden Gegenstand im Regal kombiniert, das Ziel leuchtet
  beim Halten wie im Raster. Nach jedem Kombinieren blitzt das Ergebnis kurz auf.

### 25.4 Tests und offene Punkte

- `test_backpack_screen.gd` 1436 Prüfungen, `test_backpack.gd` 5108, alle 21 Dateien bestehen.
- Zwei Tests hingen an der Rechnerlast und sind abgesichert: `test_audio.gd` prüft den Takt von
  Flamme und Strahl nur, wenn die Schüsse wirklich im Takt kamen. `test_smoke_game.gd` schickt im
  Tod-Test Schlurfer nach, falls Gegenstände aus den Kisten davor welche töten.
- Offen: Bilder statt Namen auf den Gegenständen, eine Werkbank für Rezepte, andere Bildschirme
  angleichen. Ganz rechts im vollen Raster steht die Karte links und verdeckt Nachbarn. Ein Stern
  eines Nachbarn kann in hochkant liegenden Gegenständen einen Buchstaben des Namens verdecken.
  Nur bei 1280×720 angesehen.

## 26. Ausbau 4: Ablage ohne Grenze, Material, kaputte Fundstücke, Grafik und Ton (Stand 2026-11-21)

Vom Nutzer entschieden: Die Ablage hat keine Grenze mehr. Neben dem Verkaufen für Punkte kann man
Gegenstände verschrotten und bekommt dafür Material. Alles, was man findet, ist zuerst kaputt und
muss mit Material repariert werden, bevor man es einräumen oder kombinieren kann. Kisten geben
weiter eine Karte aus drei. Dazu bessere Grafik (Zombies, Licht und Stimmung, Treffer und Effekte,
Bilder für alle Gegenstände) und besserer Ton (Musik, Raumklang und Mischung, mehr Wucht und
Abwechslung).

### 26.1 Regeln

- **Ablage:** unbegrenzt. `Balance.BACKPACK_STORAGE`, `BackpackState.STORAGE_CAPACITY` und
  `storage_overflow()` entfallen, ebenso die Sperre von „FERTIG“ und der Verkauf bei Überlauf im
  selbsttätigen Einräumen. Das Regal im Rucksack-Bildschirm rollt (Mausrad), nichts schrumpft.
- **Material:** eine zweite Währung je Lauf, `Game.materials: int`. Start `Balance.MATERIAL_START`
  (3). Für jede geschaffte Welle `Balance.MATERIAL_PER_WAVE` (2).
- **Verschrotten:** `Game.scrap_item(uid) -> int` nimmt einen Gegenstand aus Raster oder Ablage
  (kaputt oder heil) und gibt `Balance.SCRAP_YIELD[rarität - 1]` Material (1, 2, 3, 4, 6), ein
  Rucksack-Teil `Balance.SCRAP_YIELD_BAG` (1). Verkaufen für Punkte bleibt daneben bestehen, auch
  für kaputte Gegenstände, zum vollen Wert.
- **Kaputt:** Jeder Eintrag im Rucksack hat das Feld `broken: bool`. Gegenstände aus Kisten kommen
  kaputt in die Ablage (`Game.broken_loot == true`). Nicht kaputt sind: Rucksack-Teile (sie sind
  Platz, kein Gegenstand zum Benutzen), die Startgegenstände der Kandidaten und alles aus
  `Game.grant_item(id, level)` ohne den neuen dritten Parameter `broken := false`.
- **Sperre:** Ein kaputter Gegenstand lässt sich nicht einräumen (`can_place` false, `place` false,
  `auto_place` false) und nicht kombinieren, weder als Ziel noch als Quelle (`can_merge` false).
  Er liegt in der Ablage und wirkt nicht.
- **Reparieren:** `Game.repair_item(uid) -> bool` kostet `Balance.REPAIR_COST[rarität - 1]`
  Material (1, 2, 3, 4, 5). Danach ist `broken` false, der Gegenstand bleibt, wo er liegt.
  `Game.repair_cost(uid) -> int`, `Game.scrap_value(uid) -> int`, `Game.can_repair(uid) -> bool`.
- **Signale:** `Events.materials_changed(total, delta)`, `Events.item_repaired(uid)`,
  `Events.item_scrapped(uid, amount)`.
- **Headless:** `Game.broken_loot` ist ohne Bildschirm `false` (wie `unlock_all`), damit die
  vorhandenen Tests ihre Fundstücke weiter benutzen können. Tests für diese Regeln schalten es ein
  und danach wieder aus.
- **Selbsttätiges Einräumen** (`Game.auto_pack`): Ein kaputtes Fundstück bleibt in der Ablage. Es
  wird nicht von selbst repariert.

### 26.2 Bilder für Gegenstände

Neue Datei `scripts/ui/item_icons.gd` (nur static): `has(id) -> bool` und
`draw(canvas: CanvasItem, id: String, rect: Rect2, tint: Color = Color.WHITE)` zeichnet das Bild
eines Gegenstands mit den Zeichenbefehlen des `canvas` in das Rechteck. Für alle 65 IDs aus
`ItemDefs.ORDER`. Alle Bildschirme benutzen nur diese Datei.

### 26.3 Wem welche Datei gehört

- **Kern:** `scripts/core/*`, `scripts/autoload/*`, `chest_dropper.gd`/`wave_manager.gd` nur für die
  Wellen-Prämie, Kern-Tests (`test_backpack`, `test_game_state`, neu `test_materials`).
- **Rucksack und HUD:** `scripts/ui/backpack_screen.gd`, `scripts/ui/hud.gd`,
  `tests/test_backpack_screen.gd`, `tests/test_ui.gd` (nur HUD-Teile).
- **Bilder:** `scripts/ui/item_icons.gd`, `scripts/ui/chest_choice.gd`, `scripts/ui/unlock_screen.gd`,
  `scripts/ui/game_over.gd`, neu `tests/test_item_icons.gd`, `tests/test_unlock_screen.gd`,
  `tests/test_ui.gd` (nur Karten-Teile).
- **Zombies:** `scripts/game/zombies/zombie.gd`, `tests/test_zombies_waves.gd`.
- **Licht und Stimmung:** `scripts/game/level/*`, `scripts/game/main.gd`, `project.godot` (nur
  Abschnitt `rendering`), `tests/test_level.gd`.
- **Treffer und Effekte:** `scripts/game/fx/fx.gd`, neue Dateien unter `scripts/game/fx/`,
  `scripts/game/player/*` (Mündungsfeuer, Leuchtspur, Kamera-Wackeln), `scripts/game/upgrades/*_fx.gd`,
  `tests/test_player_weapons.gd`, `tests/test_player_abilities.gd`.
- **Ton:** `tools/make_sounds.py`, `audio/*`, `scripts/game/audio/*`, `scripts/game/settings.gd`,
  `scripts/ui/settings_menu.gd`, `tests/test_audio.gd`, `tests/test_settings_shaders.gd`.

`tests/test_smoke_game.gd`, `perf_game.gd`, `capture_game.gd` und `docs/ARCHITEKTUR.md` gehören dem
Zusammenbau.

### 26.4 Schnittstellen des Kerns

Stand nach dem Bau des Kerns (2026-11-21). Geprüft in `tests/test_materials.gd` (210 Prüfungen),
`tests/test_backpack.gd` (5150) und `tests/test_game_state.gd`. Events hat jetzt 47 Signale.

#### Form der Einträge im Rucksack

`BackpackState.item(uid)`, `placed_items()`, `storage_items()` und `remove(uid)` liefern je Gegenstand:

```
{ "uid": int, "id": String, "level": int, "rot": int, "placed": bool, "pos": Vector2i, "broken": bool }
```

- `"broken"` steht in **jedem** Eintrag, auch in heilen (`false`) und in Rucksack-Teilen (immer `false`).
- Ein kaputter Gegenstand liegt **immer in der Ablage** (`placed == false`). Kaputt und eingeräumt
  zugleich gibt es nicht. Deshalb zählt er nirgends mit: nicht in `loadout()`, `cameras()`,
  `upgrade_levels()`, `global_copies()`, `stats()`, `summary()`, `hands_used()`, nicht als Sternziel
  und nicht als Sternquelle.
- Die Rarität (`"level"`) eines kaputten Gegenstands ist bekannt und bleibt bei der Reparatur gleich.

#### `BackpackState` (`scripts/core/backpack_state.gd`)

| Funktion | Bedeutung |
|---|---|
| `add_item(id: String, level: int = 1, broken: bool = false) -> int` | Neuer Gegenstand in die Ablage, gibt die uid (-1 bei unbekannter ID). `broken = true` legt ihn kaputt ab. Ein Rucksack-Teil ist nie kaputt, auch mit `broken = true`. |
| `is_broken(uid: int) -> bool` | Kaputt? `false` auch für eine unbekannte uid. |
| `set_broken(uid: int, broken: bool) -> bool` | Macht kaputt oder heil. `true`, wenn sich etwas geändert hat. `false` bei unbekannter uid, wenn er schon so ist, und für Rucksack-Teile. Wird ein **eingeräumter** Gegenstand kaputt, kommt er dabei in die Ablage (danach `Game.sync_build()` rufen). |
| `repair(uid: int) -> bool` | Wie `set_broken(uid, false)`: `true`, wenn er kaputt war. Kostet hier nichts, die Kosten regelt `Game.repair_item`. Der Gegenstand bleibt in der Ablage. |
| `can_place(uid, pos, rot) -> bool`, `place(uid, pos, rot) -> bool` | Für einen kaputten Gegenstand immer `false`, nichts ändert sich. |
| `find_spot(uid) -> Dictionary`, `auto_place(uid) -> bool` | Für einen kaputten Gegenstand leer bzw. `false`. |
| `can_merge(uid, target_uid) -> bool`, `merge(uid, target_uid) -> bool` | `false`, sobald einer der beiden kaputt ist (beide Richtungen, Raster und Ablage). |
| `merge_target(uid, cell) -> int`, `find_merge_partner(uid) -> int`, `find_storage_merge_partner(uid) -> int` | `-1` für einen kaputten Gegenstand, und ein kaputter wird nie als Partner genannt. |
| `set_rotation(uid, rot)`, `remove(uid)`, `store(uid)`, `has_item(uid)`, `highest_level(id)` | Unverändert, gelten auch für kaputte. `highest_level` zählt kaputte mit (Besitz für die Kisten-Angebote). |

Entfallen ist `Balance.BACKPACK_STORAGE`. Die Ablage hat keine Grenze.

#### `Game` (`scripts/autoload/game.gd`)

| Mitglied | Bedeutung |
|---|---|
| `var materials: int` | Material des Laufs. Nur lesen. Bei jedem neuen Lauf (`start_run`, `restart_run`) `Balance.MATERIAL_START` (3). |
| `var broken_loot: bool` | `true`: Gegenstände aus Kisten kommen kaputt in die Ablage. Mit Bildschirm `true`, ohne (headless, Tests) `false`. Bleibt über Läufe erhalten, darf gesetzt werden. |
| `add_materials(amount: int) -> void` | Schreibt Material gut, sendet `materials_changed(stand, amount)`. 0 oder weniger ändert und sendet nichts. |
| `repair_cost(uid: int) -> int` | `Balance.REPAIR_COST[rarität - 1]` (1, 2, 3, 4, 5). **0**, wenn es ihn nicht gibt oder er nicht kaputt ist (auch für Rucksack-Teile). |
| `scrap_value(uid: int) -> int` | `Balance.SCRAP_YIELD[rarität - 1]` (1, 2, 3, 4, 6), ein Rucksack-Teil `Balance.SCRAP_YIELD_BAG` (1). Kaputt und heil geben gleich viel. 0, wenn es ihn nicht gibt. |
| `can_repair(uid: int) -> bool` | Er ist kaputt und `materials >= repair_cost(uid)`. |
| `repair_item(uid: int) -> bool` | Zieht `repair_cost(uid)` ab, macht ihn heil, er bleibt in der Ablage. Sendet `materials_changed(stand, -kosten)`, dann `item_repaired(uid)`. **Kein `build_changed`** (am Build ändert sich nichts): Wer anzeigt, zeichnet nach `true` selbst neu oder hört auf `item_repaired`. `false` ohne jede Änderung und ohne Signal, wenn er nicht kaputt ist, es ihn nicht gibt oder das Material nicht reicht. |
| `scrap_item(uid: int) -> int` | Entfernt den Gegenstand aus Raster oder Ablage (kaputt oder heil, auch Rucksack-Teile in der Ablage), ruft `sync_build()` und schreibt das Material gut. Reihenfolge der Signale: `build_changed` (davor `cameras_changed`, falls nötig), `materials_changed(stand, ertrag)`, `item_scrapped(uid, ertrag)`. Gibt den Ertrag zurück, 0 ohne Signal, wenn es ihn nicht gibt. Gibt keine Punkte. |
| `sell_item(uid: int) -> int` | Unverändert, auch für kaputte zum vollen Wert (`ItemDefs.sell_value`). Gibt kein Material. |
| `grant_item(id: String, level: int = 1, broken: bool = false) -> int` | Neu der dritte Parameter. Ohne ihn heil, gleich wie `broken_loot` steht. Rucksack-Teile nie kaputt. |
| `choose_offer(index: int) -> void` | Ein gewählter Gegenstand kommt mit `broken_loot` kaputt in die Ablage (Rucksack-Teile nie), danach wie bisher State PACKING und `backpack_opened(uid)`. |
| `close_backpack() -> bool` | Schließt immer, wenn der State PACKING ist. Die Ablage hält den Rucksack nicht mehr offen. `false` nur noch bei falschem State. |
| `start_run(seed_value: int = -1) -> void` | Sendet zusätzlich `materials_changed(Balance.MATERIAL_START, 0)`, nach `run_started` und `points_changed`. |
| `get_stats() -> Dictionary` | Neuer Schlüssel `"materials": int` (aktueller Stand). |
| `auto_pack` (`_auto_pack`) | Verkauft nichts mehr. Was nirgends passt, keine Hand frei hat oder kaputt ist, bleibt in der Ablage. Repariert wird nicht von selbst. Rucksack-Teile räumen sich weiter selbst ein. |

Wellen-Prämie: `Game` hört selbst auf `Events.wave_cleared` und ruft `add_materials(Balance.MATERIAL_PER_WAVE)`
(2). `wave_manager.gd` und `chest_dropper.gd` sind unverändert. In den States MENU und GAME_OVER gibt es keine Prämie.

Startgegenstände der Kandidaten (`CharacterDefs.build_backpack`) und alles, was Module mit
`backpack.add_item(id, level)` ohne dritten Parameter anlegen (Wandkauf in `weapon_controller.gd`), sind heil.

#### Signale (`scripts/autoload/events.gd`)

| Signal | Wann |
|---|---|
| `materials_changed(total: int, delta: int)` | `total` neuer Stand, `delta` Änderung: +2 je Welle, +Ertrag beim Verschrotten, +n bei `add_materials`, -Kosten beim Reparieren, **0 beim Start eines Laufs** (Anzeige zurücksetzen, kein Gewinn). |
| `item_repaired(uid: int)` | Nach `Game.repair_item`, nach `materials_changed`. Der Gegenstand ist schon heil. |
| `item_scrapped(uid: int, amount: int)` | Nach `Game.scrap_item`, als Letztes. Der Gegenstand ist schon entfernt, `Game.backpack.item(uid)` ist leer. |

#### Veraltete Hüllen (nur damit alter Code lädt, beim Umbau des Bildschirms entfernen)

- `BackpackState.storage_overflow() -> bool`: gibt immer `false` zurück.
- `BackpackState.STORAGE_CAPACITY: int`: jetzt `999999`.

Benutzer: `scripts/ui/backpack_screen.gd` (Zeilen 1461, 1462, 1497, 1514, 1848: Überschrift
„ABLAGE n / 999999“, Warnung, blasser Knopf, Feld `"over"` in `shelf_layout()`) und
`tests/test_backpack_screen.gd` (Zeilen 501, 736, 955, 1305, 1311, 1365, 1368, 1379, 1442, 1501, 1506, 1507).
`tests/test_backpack.gd` prüft die beiden Hüllen in `_test_storage_and_remove` mit zwei Prüfungen:
Wer die Hüllen löscht, löscht diese zwei Zeilen mit.

Folge für `tests/test_backpack_screen.gd`: 21 von 1436 Prüfungen scheitern, alle prüfen die
entfallene Regel (Überlauf, Warnung „Noch N Gegenstände“, blasses FERTIG, abgelehntes Schließen
und was im selben Ablauf darauf aufbaut). Sie gehören mit dem Umbau des Bildschirms ersetzt.

#### Entscheidungen über 26.1 hinaus

- **Kaputt heißt Ablage:** Statt jede Auswertung zu filtern, gilt die feste Regel, dass ein kaputter
  Gegenstand nie eingeräumt ist. `set_broken(uid, true)` auf einem eingeräumten Gegenstand lagert
  ihn deshalb aus.
- **`repair_cost` ist 0 für heile Gegenstände**, nicht der Preis ihrer Rarität. `repair_cost(uid) > 0`
  ist damit gleichbedeutend mit `is_broken(uid)`.
- **Kein eigenes Ausgeben von Material:** Es gibt kein `spend_materials`. Material sinkt nur durch
  `repair_item`.
- **Kein State-Zwang:** `repair_item` und `scrap_item` prüfen den State nicht (wie `sell_item`).
- **Reparieren sendet kein `build_changed`**, Verschrotten schon (auch aus der Ablage, wie Verkaufen).
- **Kombinieren:** Beide müssen heil sein, das Ergebnis ist also immer heil.
- **Kisten-Angebote:** Ein kaputter Gegenstand in der Ablage zählt als Besitz (`owned_level`).
- **`broken_loot` und `auto_pack` zusammen** (mit Bildschirm, z. B. `tests/perf_game.gd` und
  `tests/capture_game.gd`): Fundstücke bleiben kaputt in der Ablage und wirken nie. Wer dort die
  alte Wirkung braucht, setzt `Game.broken_loot = false`.

#### Hinweise für Tests der Oberfläche

- Headless ist `Game.broken_loot == false`. Kaputte Gegenstände für einen Test:
  `Game.backpack.add_item(id, level, true)`, `Game.grant_item(id, level, true)` oder
  `Game.broken_loot = true` setzen und am Ende wieder `false`.
- Material für einen Test: `Game.add_materials(n)`. Start je Lauf 3.

## 27. Ausbau 4: Stand nach dem Zusammenbau (Stand 2026-11-21)

Alles aus Abschnitt 26 ist gebaut. Wo ältere Abschnitte widersprechen (10, 13.5, 13.6, 21, 23.5,
24.4, 25), gilt dieser Abschnitt.

### 27.1 Rucksack-Bildschirm und HUD

- Ablage ohne Grenze: Überschrift „ABLAGE n“, das Regal rollt (Mausrad, Rollbalken, von selbst
  beim Ziehen an den Rand), Feldgröße 42 px, neueste oben. „FERTIG“ ist nie gesperrt.
- Material: „MATERIAL n“ mit Zahnrad in der oberen Leiste und klein im HUD unter den Punkten.
- Kaputte Gegenstände: grau, schraffiert, rotes Schild mit den Reparaturkosten. Über dem Raster
  rote Vorschau und „ERST REPARIEREN“.
- Drei Felder rechts unten: „REPARIEREN“ (−N Material), „VERSCHROTTEN“ (+N Material), „VERKAUFEN“
  (+N Punkte). Tasten am Gegenstand unter dem Zeiger: F repariert, zweimal X innerhalb von 1,5 s
  verschrottet (das erste X merkt nur vor), N blendet die Namen ein.
- Bilder: Jeder Gegenstand zeigt sein Bild aus `ItemIcons` auf einer Fläche in der Farbe seiner
  Rarität. Der Name steht nur in der Karte (und mit N als Zeile am unteren Rand).
- Neue Funktionen in `backpack_screen.gd`: `drop_on_repair()`, `drop_on_scrap()`, `repair(uid)`,
  `press_repair()`, `press_scrap()`, `scrap_armed_uid()`, `repair_rect()`, `scrap_rect()`,
  `action_at(pos)`, `shelf_scroll()`, `set_shelf_scroll(v)`, `scroll_to_item(uid)`, `icon_rect(uid)`,
  `names_shown()`, `toggle_names()`. Entfernt: `overflow_text()`.
- Die Hüllen `BackpackState.storage_overflow()` und `STORAGE_CAPACITY` benutzt niemand mehr außer
  zwei Zeilen in `test_backpack.gd`: Sie können mit diesen Zeilen entfallen.

### 27.2 Bilder (`scripts/ui/item_icons.gd`)

65 Bilder aus Zeichenbefehlen, ohne Dateien. `has(id)`, `draw(canvas, id, rect, tint)`,
`commands(id, rect, tint)` (dieselben Befehle als Liste), Klasse `View` (Control). Das Bild füllt
das größte Quadrat in der Mitte des Rechtecks. Benutzt in Rucksack, HUD (Kamera-Zeilen),
Kistenkarten (Karte 470 px hoch, Hinweis „Kommt kaputt in die Ablage · Reparatur: N Material“,
`ChestChoice.broken_note`), Programm und Game Over.

### 27.3 Zombies (`zombie.gd`, neu `zombie_look.gd`, `zombie_body.gd`)

- Körper aus elf Teilen (Elite 13) mit Gesicht, Gelenken und Schritten: Schlurfer als Kandidat,
  Sprinter als Kabelträger, Elite als Showmaster. Vier Varianten je Typ, Zufall aus `look_seed`
  bzw. `randi()`, nie aus `Game.rng`.
- `Body` ist jetzt ein `Node3D`, Kopf und Arme liegen unter `Body/Rig/Hips/Torso/…`.
  `get_body()`, `get_mesh_count()`, `look_seed`.
- Tod je Ursache (umfallen, Kopf fliegt weg, zerlegt, sackt zusammen). Der Körper liegt
  `ZombieBody.CORPSE_TIME` (1,6 s) im Behälter `ZombieCorpses` ohne Kollision, ab `MAX_CORPSES` (8)
  kürzer.
- Eine neue Material-Art (`emission_enabled=1,vertex_color_use_as_albedo=1`): Farben stecken in
  den Ecken der Netze, ein Material je Körper. Sie steht in `data/shader_warmup.json`.
- Spielregeln, Trefferzonen und Signale sind unverändert. Bei Schlag, Zucken und Taumeln verlässt
  der sichtbare Kopf kurz seine Trefferzone.

### 27.4 Licht und Stimmung (`level_builder.gd`, `project.godot`)

- Umgebung: Tonwert-Kurve Filmic, leichter Kontrast und Sättigung, violetter Dunst, Glühen mit
  Schwelle 1,0 (nur Farben über 1,0 leuchten nach). Der Compatibility-Renderer kann SSIL, SSR,
  SDFGI und Volumen-Nebel nicht, SSAO ist zu teuer: nicht benutzt.
- Fünf gerichtete Lichter auf eigenen Render-Ebenen (`LAYER_ACTORS/ROOMS/STAGE/FLOOR`): Spieler,
  Zombies und Kisten bleiben überall hell. `ShadowKey` trifft nur die Böden und wirft als einziges
  Licht Schatten.
- 27 Punktlichter und Scheinwerfer bei offenen Räumen (15 am Start), je Raum drei mit eigener
  Stimmung. Höchstens 7 Lichter je großem Mesh.
- Bei `wave_cleared` leuchtet das Applaus-Schild, bei `wave_started` rotes Warnlicht.
- Regel: Dunst und Glühen nie im Spiel umschalten (sonst werden alle Shader neu übersetzt).
- Fund, nicht behoben: Mit der Einstellung „Auflösung 3D“ unter 100 % dauert ein Bild hier 6 bis
  10 ms statt etwa 2 ms. Ob das am neuen Licht liegt, ist nicht gegengemessen.

### 27.5 Treffer und Effekte (`fx.gd`, neu `fx_pool.gd`, `view_model.gd`, `player.gd`)

- Vorrat `FxPool` mit festen Größen: 32 Leuchtspuren, 72 Funken, 88 Spritzer/Rauch, 28
  Einschussmale. Kein neues Licht je Schuss (ein gemeinsames `MuzzleLight`).
- Mündungsfeuer je Waffenart, Leuchtspur, Hülsen, Einschläge an Wand und Boden (`Fx.impact`),
  grüne Spritzer am Zombie (`Fx.splatter`), Platzen beim Tod (`Fx.kill_burst`), kräftigere
  Explosion, Blitz, Flamme, Strahl, Mine mit Blinklicht.
- Trefferzahlen: Größe nach Schaden, Krit pink mit „!“, Treffer innerhalb von 0,22 s und 0,5 m
  zählen in einer Zahl zusammen.
- Kamera-Wackeln (`player.add_camera_shake`, Stärke `CAMERA_SHAKE_STRENGTH`): höchstens 1,15 Grad,
  nach etwa 0,3 s weg, `get_aim_direction()` rechnet es heraus.
- Offen im HUD: eine eigene Marke für kritische Treffer und die Kill-Marke bei Kills durch Flamme,
  Strahl, eigene Explosionen und Blitzsprünge.

### 27.6 Ton (`scripts/game/audio/*`, `tools/make_sounds.py`, `tools/make_music.py`)

- Musik: `music_menu`, `music_calm`, `music_wave`, `music_late` (Zusatzspur ab Welle 10),
  `music_game_over`, berechnet, 22050 Hz Stereo, zusammen 10,7 MB. `music.gd` (Kind von `sfx.gd`)
  wählt nach `Game.state` und Signalen, blendet in 1 s über, wird in Pause, Kistenwahl und
  Rucksack leiser und dumpfer.
- Busse (`audio_buses.gd`): `Master` mit Begrenzer (−1 dBFS), darunter `Sfx` mit Hall-Bus `Reverb`
  für alles mit Ort, und `Music` mit Tiefpass. Laute Ereignisse drängen die Musik kurz zurück
  (`"duck"` in `SOUNDS`).
- Einstellungen `music_volume` (0,7) und `sfx_volume` (1,0) mit Reglern „MUSIK“ und „GERÄUSCHE“.
- 103 Dateien statt 61: drei Varianten für häufige Geräusche, sattere Schüsse und Explosion,
  neu Schritte, Landen, Herzschlag unter 30 % Leben, Publikum (Raunen, Jubel, „Oh“, Buh),
  Reparieren, Verschrotten, Material.
- `tools/check_mix.py` rechnet die Mischung nach. Angehört hat es niemand. Nachstellen nach dem
  Probehören: Lautstärke je Musikstück in `music.gd` (`LAYERS`, dazu `FADE_TIME`, `MUFFLE_DB`,
  `MUFFLE_CUTOFF`), je Geräusch in `sfx.gd` (`SOUNDS`: `db`, `duck`), Hall und Begrenzer in
  `audio_buses.gd` (`REVERB_*`, `LIMITER_CEILING_DB`).

### 27.7 Zusammenbau und Prüfung

- `run_tests.ps1`: 23 Dateien, alle bestanden (neu `test_materials`, `test_item_icons`).
- `tests/perf_game.gd -- record`: 22 Material-Arten, kein Shader-Ruckler. Volle Welle im Mittel
  4,6 ms je Bild (vor Ausbau 4: 3,1 ms). Die zwei Bilder über 25 ms sind Waffenwechsel der Messung.
- Mit Bildschirm durchgespielt (Probe, kein Test im Repo): Kiste, Fundstück kommt kaputt ins Regal,
  lässt sich nicht einräumen, Reparatur kostet Material, danach einräumen, Kampf mit neuen Zombies,
  Licht und Effekten.
- Wer mit Bildschirm probt, setzt `Game.progress_file_enabled = false` und bedient die Kistenwahl
  über `chest_choice.choose(index)`, nicht über `Game.choose_offer` (sonst bleibt die Anzeige stehen).
- `tests/perf_game.gd` und `tests/capture_game.gd` setzen `Game.broken_loot = false`.

### 27.8 Offen

- Nichts davon ist von einem Menschen gespielt oder angehört. Material-Zahlen, Paketpreise und
  alle Lautstärken sind nur gerechnet.
- Das Banner am Wellenende nennt das Material nicht (die Anzeige im HUD zeigt „+2“).
- Beim Verschrotten erklingen Zerknüllen und Klimpern gleichzeitig.

## 28. Bildrate: Messlatte, Engpässe, Änderungen (Stand 2026-11-22)

Wo ältere Abschnitte widersprechen (15, 27.4, 27.7), gilt dieser Abschnitt.

### 28.1 Messlatte `tests/perf_late.gd`

Kein Test, braucht ein Fenster (etwa 90 s). Misst den Dauerzustand in schweren Lagen bei
1920 × 1080 mit den gespeicherten Einstellungen (gelesen, nie geschrieben, kein Spielstand):

- a leere Bühne, b 48 Zombies aus Welle 22 (30 Schlurfer, 16 Sprinter, 2 Elite), c wie b mit
  Dauerfeuer (c1 Applausmaschine, c2 Flammenwerfer, c3 Raketen), d wie c mit zehn Kameras,
  Discokugel, Störsender, Minen und allen Räumen offen, p wie d pausiert (Vergleichswert für e
  und f), e Rucksack offen (volles Raster, 30 im Regal), f Kistenwahl offen.
- Je Lage: Mittel, Bilder je Sekunde, 1-%-Tief, längstes Bild, Zerlegung (Skript, Physik, Server,
  Zeichnen und Rest), Monitore. Zeile `PERF|…` zum Auswerten.
- Fester Zufall, feste Plätze, fester `look_seed`. Das Fenster nimmt keine Eingaben an.
- Schalter hinter `--`: `lagen=`, `sek=`, `groesse=`, `msaa=`, `skala=`, `aus=` (Verdächtige
  abschalten), `ruhig=`, `versteckt=`, `inventur`, `takt`, `spur=<Datei>` (Spielstand je
  Physikschritt), `bilder=<name>` (Fotos nach `_shots/`). Die Liste steht im Kopf des Skripts.
- Mit `--fixed-fps 60 -- takt aus=ton` ist ein Lauf Schritt für Schritt gleich. Mit Ton nicht:
  Das Raunen des Publikums (`sfx.gd`) läuft nach echter Zeit und verbraucht globale Zufallszahlen.
- Vor jedem Lauf mit `tasklist` prüfen, dass `ZombieShooter.exe` nicht läuft. Streuung über drei
  Läufe 1 bis 4 %, zwischen ruhigem und belegtem Rechner bis 10 %.

### 28.2 Engpässe (gemessen, Rechner des Nutzers: RX 7900 GRE, i7-13700KF)

Das Spiel hängt am Prozessor (ein Thread), nicht an der Grafikkarte.

1. Sprungproben der Zombies (`_try_hop`): im Gedränge bis zu neun `test_move` je Zombie und
   Schritt gegen andere Zombies, immer umsonst. Über die Hälfte des Physikschritts.
2. Rucksack-Bildschirm: zeichnete jedes Bild alle Bilder der Gegenstände neu (32 ms je Bild).
3. Treiber ANGLE: Faktor 2,1 bis 3,0 gegenüber dem OpenGL-Treiber der Grafikkarte (a 1,86 gegen
   0,62 ms, d 9,57 gegen 4,21 ms). Nicht geändert, siehe 28.5.
4. „Auflösung 3D“ unter 100 %: +9 bis 11 ms je Bild, gleich bei 50, 75 oder 95 %. Liegt an ANGLE
   (mit dem OpenGL-Treiber weg), nicht am Licht aus Abschnitt 27.4. Im Projekt nicht behebbar.
5. Zehn Kameras samt HUD-Zeilen: 1,8 bis 2,5 ms in Lage d.
6. HUD: 0,4 ms leer, 1,5 bis 2,2 ms in Lage d (Buff-Leiste davon 0,75 bis 1,2 ms).
7. Zombie-Körper: 706 Zeichenaufrufe für 48 Zombies, 1,3 bis 1,95 ms.
8. Level-Geometrie 1,0 ms, `move_and_slide` 27 bis 35 µs je Zombie und Schritt, Animation der
   Zombies 0,38 ms, alle Punktlichter samt Schatten 0,74 ms.

Unwichtig (unter 0,1 ms oder nicht messbar): Glühen, Dunst, Ton, `StudioShow`, Publikum,
Trennungskräfte, Wegsuche, Sichtstrahlen. Kantenglättung 8-fach und die Fenstergröße
(1280 × 720 gegen 1920 × 1080) kosten hier höchstens 0,1 ms.

### 28.3 Änderungen

- `zombie.gd`: `_try_hop` läuft nur noch, wenn `_touches_world_wall()` einen Kontakt mit etwas
  meldet, das kein `CharacterBody3D` ist und dessen Normale flacher als `WALL_NORMAL_MAX_Y` (0,72)
  steht. Zombies und Spieler lösen keine Proben mehr aus. Das Verhalten ist gleich (Spur über 2616
  Physikschritte: Lage aller Zombies, Leben, `Game.rng`, Kills, Kisten).
- `zombie.gd`: Der Körper naher Zombies wird einmal je Physikschritt gestellt statt bis 100-mal
  je Sekunde (`POSE_WITH_PHYSICS`, spätestens nach `POSE_MAX_WAIT` 0,05 s). Flammen, Giftblasen,
  Elite-Licht und Flackern laufen im selben Takt. Ausholen, Schlag, Treffer und Erscheinen
  bleiben in jedem Bild. Über 60 B/s bewegen sich die Glieder im 60er-Takt wie der Zombie selbst.
  `_animate_alive` gibt `bool` zurück, `_update_material`, `_animate_flames`, `_animate_poison`
  haben den Parameter `posed`.
- `backpack_screen.gd`: Zeichnen auf Flächen verteilt (`board_faces`, `board_top`, `shelf_top`).
  Die Bilder der Gegenstände zeichnen sich nur bei Änderung, die Flächen darüber nur bei Änderung
  oder solange etwas pulsiert. Reihenfolge und Aussehen wie vorher.
- `settings_menu.gd`, `settings.gd`: Der Hinweis zu „Auflösung 3D“ verspricht kein „schneller“
  mehr.
- Tests: `test_zombies_waves.gd` (keine Proben an Zombies, Meldung an einer Weltwand, Körper-Takt),
  `test_backpack_screen.gd` (in Ruhe kein Neuzeichnen, je Änderung genau die richtige Fläche).
- Keine neue Material-Art (22), keine neue Einstellung, kein neues Signal.

### 28.4 Vorher und nachher (Mittel je Bild, je drei Läufe abwechselnd alt und neu)

| Lage | ms vorher → nachher | B/s vorher → nachher | 1-%-Tief ms |
|---|---|---|---|
| a leere Bühne | 1,88 → 1,86 | 532 → 538 | 3,3 → 2,6 |
| b 48 Zombies | 5,38 → 3,91 | 186 → 256 | 10,4 → 6,3 |
| c Dauerfeuer | 8,44 → 5,82 | 118 → 172 | 16,1 → 10,8 |
| d Kameras, alles offen | 14,15 → 9,57 | 71 → 105 | 20,4 → 15,0 |
| p wie d, pausiert | 4,36 → 4,34 | 230 → 230 | 5,5 → 5,4 |
| e Rucksack | 32,10 → 8,67 | 31 → 115 | 34,5 → 9,8 |
| f Kistenwahl | 6,08 → 6,08 | 164 → 164 | 7,5 → 7,7 |

Ein einzelner Kontrolllauf danach bei belegtem Rechner: b 4,43, c 6,42, d 10,02, e 8,92 ms.
Die Fotos `_shots/perf_before_*.png` und `perf_after_*.png` sind Byte für Byte gleich (aufgenommen
mit festen 60 Bildern je Sekunde, der Körper-Takt bei höherer Bildrate ist nicht fotografiert).
`run_tests.ps1`: 23 Dateien bestanden. `perf_game.gd`: 22 Material-Arten, kein Shader-Ruckler.

### 28.5 Noch zu holen (nicht gebaut)

1. OpenGL-Treiber der Grafikkarte statt ANGLE: gemessen a 0,62, b 1,51, c 2,55, d 4,21, e 4,09,
   f 2,53 ms. Preis: Vorwärmen 10 bis 11 s bei jedem Start statt 0,3 s und einzelne Bilder von 30
   bis 33 ms. Das ist die Abwägung aus Abschnitt 15, entscheidet der Nutzer. Sinnvoll wäre eine
   Einstellung mit Neustart, kein fester Wechsel.
2. Zombie als ein Netz mit Skelett (11 → 1 Zeichenaufruf): geschätzt 1,0 bis 1,3 ms in b, großer
   Aufwand, neue Shader-Variante.
3. Bilder aus `ItemIcons` einmal in eine Textur zeichnen: geschätzt Rucksack 8,7 → 5 ms, HUD in d
   0,5 bis 1,0 ms, Kistenwahl 1 ms.
4. Kamera-Modelle und Level je Material zusammenfassen: geschätzt je 0,3 bis 0,5 ms in d.
5. Jolt-Physik: gemessen 0,3 bis 0,4 ms je Schritt, Risiko anderes Laufgefühl.
6. `--render-thread separate` startet mit ANGLE nicht („Error initializing GLAD“).

## 29. Einstellung „Grafik-Unterbau“ (Stand 2026-11-22)

Wo Abschnitt 15 oder 28.5 widersprechen, gilt dieser Abschnitt.

### 29.1 Was der Spieler sieht

- Neue Zeile „GRAFIK-UNTERBAU“ in den Einstellungen (zwölf Zeilen, `ROW_START_Y` 124, `ROW_STEP` 40,
  die Fußzeile endet bei 682 von 690 Punkten der Ansicht im Pausemenü).
- „Sicher“ (Standard) = ANGLE über Direct3D 11: Vorwärmen 0,3 bis 0,4 s, kein Shader-Ruckler.
- „Schnell“ = OpenGL-Treiber der Grafikkarte: gemessen 2,3- bis 2,7-fache Bildrate, dafür Vorwärmen
  bei jedem Start 11 s (aus den Quellen) bis 15 s (EXE) und einzelne Ruckler.
- Die Wahl gilt erst nach einem Neustart. Solange ein anderer Unterbau läuft als gewählt, steht
  am Knopf „(Neustart)“. Das Ladebild nennt mit „Schnell“ die längere Wartezeit
  (`Warmup.loading_text(driver)`).

### 29.2 Technik

- `project.godot`: `application/config/project_settings_override="user://start.cfg"`. Godot liest
  diese Datei beim Start selbst, vor dem ersten Skript. Sie enthält genau einen Wert:
  Abschnitt `rendering`, Schlüssel `gl_compatibility/driver.windows`, Wert `opengl3_angle` oder
  `opengl3`. Fehlt die Datei, gilt `project.godot` (ANGLE).
- `settings.gd`: `graphics_driver` (`DRIVER_SAFE` 0, `DRIVER_FAST` 1), `DRIVER_IDS`, `DRIVER_NAMES`,
  `START_PATH`, `set_graphics_driver`, `active_driver()` (aus
  `RenderingServer.get_current_rendering_driver_name()`), `restart_needed()`,
  `load_start_from(path)`, `save_start_to(path)`. Die Wahl steht nur in der Startdatei, nicht in
  `settings.cfg`: Es gibt eine Quelle. `ensure_loaded` liest beide Dateien, `save` schreibt beide.
  „STANDARD“ stellt auf „Sicher“ zurück.
- Headless (Tests) wird die Startdatei nicht geschrieben. Gelesen wird sie von der Engine immer,
  auch headless: `active_driver()` kann in Tests deshalb 0 oder 1 sein. Tests rechnen relativ dazu.
- Die Kommandozeile schlägt die Startdatei: Messungen mit Fenster (`perf_late.gd`, `perf_game.gd`,
  `capture_game.gd`) nennen den Treiber ausdrücklich (`--rendering-driver opengl3_angle` oder
  `opengl3`), sonst messen sie mit der Wahl des Nutzers.
- Startet der OpenGL-Treiber nicht, fällt Godot von selbst auf ANGLE zurück
  (`rendering/gl_compatibility/fallback_to_angle`, Vorgabe an). Der Knopf zeigt dann weiter
  „(Neustart)“.

### 29.3 Messung (ein Lauf je Unterbau, 1920 × 1080, Einstellungen des Nutzers)

| Lage | Sicher ms / B/s | Schnell ms / B/s | 1-%-Tief Sicher → Schnell |
|---|---|---|---|
| a leere Bühne | 2,05 / 487 | 0,64 / 1564 | 2,8 → 1,4 ms |
| b 48 Zombies | 4,43 / 226 | 1,66 / 604 | 6,6 → 4,4 ms |
| c Dauerfeuer | 6,42 / 156 | 2,40 / 417 | 10,7 → 6,3 ms |
| d Kameras, alles offen | 10,02 / 100 | 4,01 / 249 | 15,2 → 7,9 ms |
| e Rucksack | 8,92 / 112 | 4,22 / 237 | 11,0 → 7,2 ms |
| f Kistenwahl | 6,50 / 154 | 2,52 / 397 | 7,5 → 4,6 ms |

`perf_game.gd` mit „Schnell“: 7 Bilder über 25 ms, längstes 117 ms (im Dauerfeuer mit sechs Waffen),
mit „Sicher“ 1 Bild, längstes 30 ms. Ein bis zwei davon sind in beiden Fällen Waffenwechsel der
Messung. Die übrigen sind Shader, die der Treiber trotz Vorwärmen beim ersten Auftreten noch einmal
anfasst. Nicht untersucht, welche.

Geprüft mit der EXE: Mit Startdatei `opengl3` meldet das Protokoll den OpenGL-Treiber (Vorwärmen
15,2 s), ohne Datei ANGLE (0,4 s). `settings.cfg` und `progress.cfg` des Nutzers blieben dabei
unverändert, die Startdatei der Probe ist wieder gelöscht.
