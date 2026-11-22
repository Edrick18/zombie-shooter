extends Node
## Signalbus des Spiels (Autoload "Events"). Nur Signale, keine Logik.
## Besitzer: Fundament. Die Liste entspricht genau Abschnitt 6 der Architektur.

@warning_ignore("unused_signal")
signal points_changed(total: int)
## Kurze Meldung in der Bildmitte oben.
@warning_ignore("unused_signal")
signal banner(text: String)
@warning_ignore("unused_signal")
signal wave_started(wave: int, total_zombies: int)
@warning_ignore("unused_signal")
signal wave_cleared(wave: int)
@warning_ignore("unused_signal")
signal intermission_tick(seconds_left: int)
## Noch nicht getötete Zombies der Welle.
@warning_ignore("unused_signal")
signal zombies_left_changed(left: int)
@warning_ignore("unused_signal")
signal zombie_spawned(zombie: Node3D)
@warning_ignore("unused_signal")
signal zombie_damaged(zombie: Node3D, amount: float, info: Dictionary)
@warning_ignore("unused_signal")
signal zombie_killed(zombie: Node3D, info: Dictionary)
## Nur Kugeltreffer der Waffe.
@warning_ignore("unused_signal")
signal bullet_hit(zombie: Node3D, damage: float, info: Dictionary)
@warning_ignore("unused_signal")
signal player_health_changed(hp: float, max_hp: float)
@warning_ignore("unused_signal")
signal player_damaged(amount: float)
@warning_ignore("unused_signal")
signal player_died()
@warning_ignore("unused_signal")
signal weapon_changed(weapon_id: String)
## reserve -1 = unendlich.
@warning_ignore("unused_signal")
signal ammo_changed(mag: int, reserve: int)
@warning_ignore("unused_signal")
signal weapon_fired(weapon_id: String)
@warning_ignore("unused_signal")
signal reload_started(weapon_id: String, duration: float)
@warning_ignore("unused_signal")
signal reload_finished(weapon_id: String)
@warning_ignore("unused_signal")
signal chest_dropped(chest: Node3D)
## offers: Array von Dictionaries, siehe ChestRoller.
@warning_ignore("unused_signal")
signal chest_opened(rarity: int, offers: Array)
@warning_ignore("unused_signal")
signal upgrade_chosen(upgrade_id: String, new_level: int)
@warning_ignore("unused_signal")
signal synergy_unlocked(synergy_id: String)
## Der Rucksack hat sich geändert (eingeräumt, verschoben, verkauft) und Game.upgrades ist schon
## neu berechnet. Kommt bei jeder Änderung, auch wenn Stufen sinken. upgrade_chosen kommt dagegen
## nur beim Schließen des Rucksacks für gestiegene Stufen.
signal build_changed
## Der Rucksack-Bildschirm soll sich öffnen. new_uid: gerade aus einer Kiste gewählter Gegenstand
## in der Ablage, -1 beim Öffnen mit der Taste.
signal backpack_opened(new_uid: int)
signal backpack_closed
## Die Waffensteuerung hat die Waffen in der Hand neu eingerichtet (nach build_changed oder
## run_started). Die Hände stehen in WeaponController.get_hands().
signal loadout_changed
## Magazin einer Hand hat sich geändert. hand: 0 = links, 1 = rechts.
signal hand_ammo_changed(hand: int, mag: int, magazine_size: int)
## Eine Hand lädt nach (duration in Sekunden) bzw. ist damit fertig.
signal hand_reload_started(hand: int, duration: float)
signal hand_reload_finished(hand: int)
## Schild des Spielers (Sicherheitsglas) hat sich geändert. max_shield 0 = kein Schild.
signal player_shield_changed(shield: float, max_shield: float)
## Ausweichsprünge (Notausgang): verfügbare und höchstens mögliche Sprünge. max_charges 0 = keiner.
signal dash_charges_changed(charges: int, max_charges: int)
## Der Spieler hat einen Ausweichsprung gemacht.
signal player_dashed
## Eine Explosion an dieser Stelle (Rakete, Konfetti-Kanone), auch wenn sie niemanden trifft.
## Nur für Ton und Anzeige: Der Schaden läuft wie bisher über take_damage.
signal explosion(position: Vector3, radius: float)
# --- Abschnitt 22 ---
## Game.cameras hat sich geändert (Kamera oder Kamera-Gegenstand eingeräumt, verschoben, verkauft).
## Kommt in sync_build vor build_changed, und nur, wenn sich die Liste wirklich geändert hat.
@warning_ignore("unused_signal")
signal cameras_changed
## Eine Kamera hat geschossen, geblitzt oder markiert. camera_id: Kameratyp aus CameraDefs,
## position: Ort der Kamera. Nur für Ton und Anzeige, gesendet vom Kamera-Knoten.
@warning_ignore("unused_signal")
signal camera_fired(camera_id: String, position: Vector3)
## Die Requisitenbombe hat eine Mine gelegt bzw. eine Mine wurde ausgelöst (kurz vor ihrer
## Explosion, die zusätzlich als explosion(position, radius) kommt).
@warning_ignore("unused_signal")
signal mine_placed(position: Vector3)
@warning_ignore("unused_signal")
signal mine_triggered(position: Vector3)
## Die Zweite Staffel hat einen tödlichen Treffer abgefangen: Der Spieler steht wieder.
@warning_ignore("unused_signal")
signal player_revived
## Ladungen der Zweiten Staffel: bereit / im Rucksack (0 / 0 = kein Exemplar).
@warning_ignore("unused_signal")
signal revive_charges_changed(charges: int, max_charges: int)
## Das Konto hat sich geändert (Abschnitt 22.5). bank: neuer Stand, gained: Änderung (am Laufende
## die verdienten Punkte, auch 0, beim Kauf eines Pakets der negative Preis).
@warning_ignore("unused_signal")
signal bank_changed(bank: int, gained: int)
## Ein Paket wurde gekauft: Sein Inhalt kann ab jetzt in Kisten liegen.
@warning_ignore("unused_signal")
signal pack_unlocked(pack_id: String)
# --- Abschnitt 26 ---
## Das Material des Laufs hat sich geändert. total: neuer Stand, delta: Änderung (positiv bei
## Wellen-Prämie und Verschrotten, negativ beim Reparieren, 0 beim Start eines Laufs).
@warning_ignore("unused_signal")
signal materials_changed(total: int, delta: int)
## Ein kaputter Gegenstand wurde repariert (Game.repair_item). Kommt nach materials_changed.
## build_changed kommt dabei nicht: Der Gegenstand liegt weiter in der Ablage.
@warning_ignore("unused_signal")
signal item_repaired(uid: int)
## Ein Gegenstand wurde verschrottet (Game.scrap_item) und ist schon aus dem Rucksack entfernt.
## amount: das Material, das es dafür gab. Kommt nach build_changed und materials_changed.
@warning_ignore("unused_signal")
signal item_scrapped(uid: int, amount: int)
## "" = keine Anzeige.
@warning_ignore("unused_signal")
signal interact_prompt_changed(text: String)
@warning_ignore("unused_signal")
signal game_over(stats: Dictionary)
@warning_ignore("unused_signal")
signal run_started()
