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
## "" = keine Anzeige.
@warning_ignore("unused_signal")
signal interact_prompt_changed(text: String)
@warning_ignore("unused_signal")
signal game_over(stats: Dictionary)
@warning_ignore("unused_signal")
signal run_started()
