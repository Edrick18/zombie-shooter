extends RefCounted
## Fortschritt über alle Läufe (Abschnitt 22.5): Konto, gekaufte Pakete, beste Welle, Zahl der
## Läufe. Reine Logik ohne Nodes und ohne Dateien: Game lädt und speichert über to_dict/from_dict.
## Einbinden mit: const ProgressState := preload("res://scripts/core/progress_state.gd")

const UnlockDefs := preload("res://scripts/core/unlock_defs.gd")

## Punkte auf dem Konto. Am Ende eines Laufs kommen die im Lauf verdienten Punkte dazu.
var bank: int = 0
## Gekaufte Pakete in der Reihenfolge des Kaufs. Nur lesen: gekauft wird mit buy.
var packs: Array[String] = []
## true: Alles gilt als freigeschaltet (Tests ohne Bildschirm sehen so den ganzen Vorrat). Wird
## nicht gespeichert.
var unlock_all: bool = false
## Höchste Welle, die je erreicht wurde.
var best_wave: int = 0
## Zahl der beendeten Läufe.
var runs: int = 0


## Ist dieses Paket gekauft?
func has_pack(pack_id: String) -> bool:
	return packs.has(pack_id)


## Darf dieser Gegenstand in Kisten liegen? Ja mit unlock_all, für den Startvorrat (auch die
## Rucksack-Teile), für den Inhalt gekaufter Pakete und für alles, was in keinem Paket steht.
func is_item_unlocked(item_id: String) -> bool:
	if unlock_all or UnlockDefs.is_start_item(item_id):
		return true
	var pack_id: String = UnlockDefs.pack_of(item_id)
	return pack_id.is_empty() or packs.has(pack_id)


## Kann dieses Paket jetzt gekauft werden? Es gibt es, es ist noch nicht gekauft und das Konto reicht.
func can_buy(pack_id: String) -> bool:
	return UnlockDefs.has_pack(pack_id) and not packs.has(pack_id) and bank >= UnlockDefs.pack_price(pack_id)


## Kauft das Paket: zieht den Preis vom Konto ab. false (und nichts ändert sich), wenn es nicht geht.
func buy(pack_id: String) -> bool:
	if not can_buy(pack_id):
		return false
	bank -= UnlockDefs.pack_price(pack_id)
	packs.append(pack_id)
	return true


## Schreibt Punkte aufs Konto und gibt den gutgeschriebenen Betrag zurück (0 bei amount <= 0).
func add_bank(amount: int) -> int:
	if amount <= 0:
		return 0
	bank += amount
	return amount


## Merkt einen beendeten Lauf: ein Lauf mehr, beste Welle höchstens besser.
func record_run(wave: int) -> void:
	runs += 1
	best_wave = maxi(best_wave, wave)


## Pakete, die noch nicht gekauft sind, in der Reihenfolge von UnlockDefs.PACK_ORDER.
func open_packs() -> Array[String]:
	var result: Array[String] = []
	for pack_id: String in UnlockDefs.PACK_ORDER:
		if not packs.has(pack_id):
			result.append(pack_id)
	return result


## Zustand zum Speichern: { "bank": int, "packs": Array[String], "best_wave": int, "runs": int }.
## unlock_all gehört nicht dazu.
func to_dict() -> Dictionary:
	return {"bank": bank, "packs": packs.duplicate(), "best_wave": best_wave, "runs": runs}


## Übernimmt einen gespeicherten Zustand. Fehlende oder kaputte Werte werden zu 0 bzw. leer,
## unbekannte und doppelte Pakete entfallen. unlock_all bleibt, wie es ist.
func from_dict(data: Dictionary) -> void:
	bank = maxi(0, _to_int(data.get("bank", 0)))
	best_wave = maxi(0, _to_int(data.get("best_wave", 0)))
	runs = maxi(0, _to_int(data.get("runs", 0)))
	packs = []
	var stored: Variant = data.get("packs", [])
	if stored is Array or stored is PackedStringArray:
		for entry: Variant in stored:
			var pack_id: String = str(entry)
			if UnlockDefs.has_pack(pack_id) and not packs.has(pack_id):
				packs.append(pack_id)


static func _to_int(value: Variant) -> int:
	if value is int or value is float or value is bool:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return 0
