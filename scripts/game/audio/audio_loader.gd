extends RefCounted
## Modul: Ton (scripts/game/audio).
## Lädt Tondateien für sfx.gd und music.gd. Nur statische Funktionen, einbinden mit preload.

## Lädt eine Tondatei, ohne je eine Fehlermeldung auszulösen.
## 1. Hat Godot die Datei eingelesen (im fertigen Spiel gibt es nur das), wird sie normal geladen.
## 2. Sonst wird die rohe WAV-Datei direkt gelesen (frisch kopiertes Projekt ohne Import).
## 3. Fehlt beides, kommt null zurück.
static func load_stream(path: String) -> AudioStream:
	if is_imported(path) and ResourceLoader.exists(path):
		var imported: AudioStream = load(path) as AudioStream
		if imported != null:
			return imported
	if FileAccess.file_exists(path):
		return AudioStreamWAV.load_from_file(path)
	# Letzter Versuch: ein Paket, in dem die Import-Notiz nicht lesbar ist, die Datei aber bekannt.
	if not FileAccess.file_exists(path + ".import") and ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


## Gibt es die Import-Notiz der Datei und die Datei, auf die sie zeigt? Nur dann lädt load()
## ohne Fehlermeldung.
static func is_imported(path: String) -> bool:
	var note_path: String = path + ".import"
	if not FileAccess.file_exists(note_path):
		return false
	var note: ConfigFile = ConfigFile.new()
	if note.load(note_path) != OK:
		return false
	var target: String = str(note.get_value("remap", "path", ""))
	return target != "" and FileAccess.file_exists(target)


## Sorgt dafür, dass die Datei als Schleife spielt, und gibt zurück, ob sie das jetzt tut.
## Die Schleifen des Spiels tragen ihre Schleifenpunkte in der Datei (Eintrag "smpl", geschrieben
## von tools/make_sounds.py und tools/make_music.py), Godot übernimmt sie beim Einlesen. Hat das
## nicht geklappt (andere Import-Einstellung, eigene Aufnahme ohne den Eintrag), wird hier die
## ganze Datei zur Schleife erklärt.
static func ensure_loop(stream: AudioStream) -> bool:
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	if wav == null:
		return false
	if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		wav.loop_begin = 0
		wav.loop_end = roundi(wav.get_length() * float(wav.mix_rate))
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return wav.loop_mode == AudioStreamWAV.LOOP_FORWARD


## Spielt die Datei als Schleife?
static func is_loop(stream: AudioStream) -> bool:
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	return wav != null and wav.loop_mode != AudioStreamWAV.LOOP_DISABLED
